import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'transport.dart';

class TransportManager {
  final Map<TransportType, Transport> _transports = {};
  
  StreamController<Map<String, dynamic>> _dataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onData => _dataController.stream;

  TransportType? _activeType;
  TransportType? get activeType => _activeType;

  void addTransport(Transport transport) {
    _transports[transport.type] = transport;
    
    transport.onData.listen((data) {
      // Decode if we are the active transport or handle messages generically
      _dataController.add({
        'transport': transport.type,
        'data': data,
      });
    });

    transport.onClose.listen((_) {
      if (_activeType == transport.type) {
        _activeType = null;
        // Trigger fallback?
      }
    });
  }

  Transport? getTransport(TransportType type) {
    return _transports[type];
  }

  void setActiveTransport(TransportType type) {
    if (_transports.containsKey(type) && _transports[type]!.isConnected) {
      _activeType = type;
    }
  }

  Future<void> send(Uint8List data) async {
    final active = _activeType != null ? _transports[_activeType] : null;
    if (active != null && active.isConnected) {
      await active.send(data);
    } else {
      throw Exception('No active connected transport');
    }
  }

  Future<Map<String, dynamic>> sendRequest(String action, [Map<String, dynamic>? payload]) async {
    final requestId = const Uuid().v4();
    final completer = Completer<Map<String, dynamic>>();
    
    final subscription = onData.listen((event) {
      try {
        final dataBytes = event['data'] as Uint8List;
        final message = utf8.decode(dataBytes);
        final parsed = jsonDecode(message);
        
        if (parsed['type'] == 'response' && parsed['requestId'] == requestId) {
          if (parsed['status'] == 'success') {
            completer.complete(parsed['payload'] ?? <String, dynamic>{});
          } else {
            completer.completeError(parsed['error'] ?? 'Unknown error');
          }
        }
      } catch (e) {
        // ignore parse errors
      }
    });
    
    try {
      await send(utf8.encode(jsonEncode({
        'type': 'request',
        'requestId': requestId,
        'action': action,
        'payload': payload ?? {},
      })));
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      subscription.cancel();
    }
  }

  void dispose() {
    for (var t in _transports.values) {
      t.disconnect();
    }
    _transports.clear();
    _activeType = null;
    _dataController.close();
    _dataController = StreamController<Map<String, dynamic>>.broadcast();
  }
}

final transportManager = TransportManager();
