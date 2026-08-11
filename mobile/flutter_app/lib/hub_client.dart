import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'notification_service.dart';
import 'transport/transport.dart';
import 'transport/transport_manager.dart';
import 'transport/wifi/websocket_transport.dart';

import 'package:permission_handler/permission_handler.dart';

class HubClient {
  final _storage = const FlutterSecureStorage();
  
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  
  String? _lastIp;
  int? _lastPort;
  String? _lastToken;

  int? get closeCode => 0; // Legacy support
  String? get closeReason => 'Disconnected'; // Legacy support

  TransportType? get activeTransport => transportManager.activeType;

  Stream<Map<String, dynamic>> get metricStream => _controller?.stream ?? const Stream.empty();

  Future<Map<String, dynamic>> connect(String ip, int port, String token) async {
    _lastIp = ip;
    _lastPort = port;
    _lastToken = token;
    _isReconnecting = false;
    
    disconnect(); // Close existing first

    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    
    final systemInfoCompleter = Completer<Map<String, dynamic>>();

    try {
      AppLogger.log('[HubClient] Connecting to Wi-Fi transport: $ip:$port', ip, port);
      
      final wsUrl = 'ws://$ip:$port/ws?token=$token';
      final wsTransport = WebSocketTransport(wsUrl);
      
      // Attempt Wi-Fi Connection
      try {
        await wsTransport.connect();
        transportManager.addTransport(wsTransport);
        transportManager.setActiveTransport(TransportType.wifi);
        AppLogger.log('[HubClient] Wi-Fi Handshake complete.', ip, port);
      } catch (e) {
        AppLogger.log('[HubClient] Wi-Fi connection failed: $e', ip, port);
        throw Exception('Wi-Fi connection failed');
      }

      // Sync missed notifications
      final lastSyncStr = await _storage.read(key: 'last_notif_sync') ?? '0';
      final lastSync = int.tryParse(lastSyncStr) ?? 0;
      
      final syncPayload = utf8.encode(jsonEncode({
        'type': 'sync_notifications',
        'timestamp': lastSync,
      })) as Uint8List;
      
      await transportManager.send(syncPayload);

      // Request system info over transport
      final getInfoPayload = utf8.encode(jsonEncode({'type': 'get_system_info'})) as Uint8List;
      await transportManager.send(getInfoPayload);

      _subscription = transportManager.onData.listen(
        (event) {
          final data = event['data'] as Uint8List;
          try {
            final message = utf8.decode(data);
            if (message.contains('"type":"pong"')) return;

            final parsed = jsonDecode(message) as Map<String, dynamic>;
            if (parsed['type'] == 'system_info' && parsed['data'] != null) {
              if (!systemInfoCompleter.isCompleted) {
                systemInfoCompleter.complete(parsed['data'] as Map<String, dynamic>);
              }
            } else if (parsed['type'] == 'system_update' && parsed['data'] != null) {
              _controller?.add(parsed['data'] as Map<String, dynamic>);
            } else if (parsed['type'] == 'notification' && parsed['data'] != null) {
              final notif = parsed['data'] as Map<String, dynamic>;
              _handleIncomingNotification(notif);
            } else if (parsed['type'] == 'sync_notifications_result' && parsed['data'] != null) {
              final notifs = parsed['data'] as List<dynamic>;
              for (var n in notifs) {
                _handleIncomingNotification(n as Map<String, dynamic>);
              }
            }
          } catch (e) {
            AppLogger.log('[HubClient] Parse error: $e', ip, port);
          }
        },
        onError: (err) {
          AppLogger.log('[HubClient] Transport stream error: $err', ip, port);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.log('[HubClient] Connection closed.', ip, port);
          _scheduleReconnect();
        },
      );

      _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => sendPing());
      
      // Wait for the system_info response up to 5 seconds
      return await systemInfoCompleter.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.log('[HubClient] Connection failed: $e', ip, port);
      _scheduleReconnect();
      if (!systemInfoCompleter.isCompleted) {
        systemInfoCompleter.completeError(e);
      }
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _reconnectTimer?.cancel();
    
    AppLogger.log('[HubClient] Scheduling reconnect in 3 seconds...', _lastIp ?? '', _lastPort ?? 0);
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_lastIp != null && _lastPort != null && _lastToken != null) {
        connect(_lastIp!, _lastPort!, _lastToken!);
      }
    });
  }

  void _handleIncomingNotification(Map<String, dynamic> notif) {
    final actions = notif['actions'] as List<dynamic>?;
    NotificationService().showNotification(
      id: notif['id'].hashCode,
      title: notif['title'] ?? 'Notification',
      body: notif['body'] ?? '',
      actions: actions,
    );
    final ts = notif['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    _storage.write(key: 'last_notif_sync', value: ts.toString());

    final ack = utf8.encode(jsonEncode({
      'type': 'ack_notification',
      'id': notif['id'],
    })) as Uint8List;
    transportManager.send(ack).catchError((_) {});
  }

  void sendPing() {
    try {
      final ping = utf8.encode(jsonEncode({'type': 'ping'})) as Uint8List;
      transportManager.send(ping).catchError((_) {});
    } catch (e) {
      AppLogger.log('[HubClient] Error sending ping: $e');
    }
  }



  void disconnect() {
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    transportManager.dispose();
  }
}
