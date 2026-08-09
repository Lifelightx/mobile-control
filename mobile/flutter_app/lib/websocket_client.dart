import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'notification_service.dart';

class WebSocketClient {
  final _storage = const FlutterSecureStorage();
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  String? _lastIp;
  int? _lastPort;
  String? _lastToken;

  int? get closeCode => _channel?.closeCode;
  String? get closeReason => _channel?.closeReason;

  Stream<Map<String, dynamic>> get metricStream => _controller?.stream ?? const Stream.empty();

  Future<void> connect(String ip, int port, String token) async {
    _lastIp = ip;
    _lastPort = port;
    _lastToken = token;
    _isReconnecting = false;
    
    disconnect(); // Close existing first

    _controller ??= StreamController<Map<String, dynamic>>.broadcast();

    final wsUrl = Uri.parse('ws://$ip:$port/ws?token=$token');

    try {
      AppLogger.log('[WebSocketClient] Connecting to: $wsUrl', ip, port);
      _channel = WebSocketChannel.connect(wsUrl);

      // CRITICAL: Await the WebSocket handshake to fully complete.
      // Without this, the stream listener fires onDone immediately if the
      // HTTP→WS upgrade hasn't finished yet, silently closing the connection.
      await _channel!.ready;

      // Guard: if disconnect() was called during the handshake await gap,
      // _channel will be null. Abort cleanly rather than throw a NPE.
      if (_channel == null) {
        AppLogger.log('[WebSocketClient] Aborted: disconnect() was called during handshake.', ip, port);
        _controller?.close();
        _controller = null;
        return;
      }

      AppLogger.log('[WebSocketClient] Handshake complete. Listening for messages.', ip, port);

      // Phase 7: Reconnect Synchronization
      // Ask the server for any notifications we missed while disconnected
      final lastSyncStr = await _storage.read(key: 'last_notif_sync') ?? '0';
      final lastSync = int.tryParse(lastSyncStr) ?? 0;
      _channel!.sink.add(jsonEncode({
        'type': 'sync_notifications',
        'timestamp': lastSync,
      }));

      _subscription = _channel!.stream.listen(
        (message) {
          final messageStr = message.toString();
          // Silently swallow pong responses to avoid cluttering logs
          if (messageStr.contains('"type":"pong"')) return;

          AppLogger.log('[WebSocketClient] Message received: $message', ip, port);
          try {
            final parsed = jsonDecode(message) as Map<String, dynamic>;
            if (parsed['type'] == 'system_update' && parsed['data'] != null) {
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
            AppLogger.log('[WebSocketClient] Parse error: $e', ip, port);
          }
        },
        onError: (err) {
          AppLogger.log('[WebSocketClient] Stream error: $err', ip, port);
          // Do not bubble error to bloc so UI stays on dashboard
          _scheduleReconnect();
        },
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          AppLogger.log('[WebSocketClient] Connection closed. Code: $code, Reason: $reason', ip, port);
          // Do not bubble error to bloc so UI stays on dashboard
          _scheduleReconnect();
        },
      );

      // Start a 10-second periodic heartbeat ping to keep the connection alive
      _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => sendPing());
    } catch (e) {
      AppLogger.log('[WebSocketClient] Connection failed: $e', ip, port);
      // Do not bubble error to bloc
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _reconnectTimer?.cancel();
    
    AppLogger.log('[WebSocketClient] Scheduling reconnect in 3 seconds...', _lastIp ?? '', _lastPort ?? 0);
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
    // Update last sync time
    final ts = notif['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    _storage.write(key: 'last_notif_sync', value: ts.toString());

    // Send ACK back to server
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'ack_notification',
        'id': notif['id'],
      }));
    }
  }

  void sendPing() {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        AppLogger.log('[WebSocketClient] Error sending ping: $e');
      }
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
    _channel?.sink.close();
    _channel = null;
    // Don't close controller here if we want auto-reconnect to reuse it
    // _controller?.close(); 
    // _controller = null;
  }
}
