import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../transport.dart';
import 'dart:convert';

class WebSocketTransport implements Transport {
  @override
  final TransportType type = TransportType.wifi;
  
  final String url;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  final _dataController = StreamController<Uint8List>.broadcast();
  final _closeController = StreamController<void>.broadcast();
  final _errorController = StreamController<dynamic>.broadcast();

  WebSocketTransport(this.url);

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _isConnected = true;
      
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            _dataController.add(utf8.encode(data) as Uint8List);
          } else if (data is List<int>) {
            _dataController.add(Uint8List.fromList(data));
          }
        },
        onError: (error) {
          _handleDisconnect(error);
        },
        onDone: () {
          _handleDisconnect(null);
        },
      );
    } catch (e) {
      _isConnected = false;
      throw Exception('Failed to connect to WebSocket: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close();
      _handleDisconnect(null);
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_isConnected || _channel == null) throw Exception('WebSocket disconnected');
    // Note: The agent currently expects strings for JSON payloads, but we can send text.
    // The dart layer will send utf8 string for JSON.
    // Wait, the Transport interface sends Uint8List. If it's valid UTF-8, we can decode it.
    try {
      final text = utf8.decode(data);
      _channel!.sink.add(text);
    } catch (e) {
      // Fallback for raw binary
      _channel!.sink.add(data);
    }
  }

  void _handleDisconnect(dynamic error) {
    if (!_isConnected) return;
    _isConnected = false;
    _channel = null;
    
    if (error != null) {
      _errorController.add(error);
    }
    _closeController.add(null);
  }

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  @override
  Stream<void> get onClose => _closeController.stream;

  @override
  Stream<dynamic> get onError => _errorController.stream;

  void dispose() {
    _dataController.close();
    _closeController.close();
    _errorController.close();
  }
}
