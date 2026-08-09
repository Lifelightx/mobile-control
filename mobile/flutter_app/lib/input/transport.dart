import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Binary WebSocket transport for the input subsystem.
///
/// Maintains a dedicated connection to ws://<host>/ws/input — separate from
/// the JSON monitoring WebSocket. Each send() call writes one binary frame.
///
/// Reconnects automatically with exponential back-off up to 8 s.
class InputTransport {
  WebSocketChannel? _channel;
  bool _connected = false;
  bool _destroyed = false;
  Timer? _reconnectTimer;
  int _retryCount = 0;

  String? _lastIp;
  int? _lastPort;
  String? _lastToken;

  static const _maxRetrySeconds = 8;

  /// Connect to the input WebSocket.
  Future<void> connect(String ip, int port, String token) async {
    _lastIp = ip;
    _lastPort = port;
    _lastToken = token;

    disconnect();
    await _doConnect(ip, port, token);
  }

  Future<void> _doConnect(String ip, int port, String token) async {
    if (_destroyed) return;

    final url = Uri.parse('ws://$ip:$port/ws/input?token=$token');
    try {
      _channel = WebSocketChannel.connect(url);
      await _channel!.ready;

      if (_channel == null) return; // Disconnected during handshake

      _connected = true;
      _retryCount = 0;
      print('[InputTransport] Connected to $url');

      _channel!.stream.listen(
        (_) {}, // No messages expected from server on this channel
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      print('[InputTransport] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_destroyed || _reconnectTimer != null) return;
    _connected = false;
    _channel = null;

    final delaySeconds = (1 << _retryCount).clamp(1, _maxRetrySeconds);
    _retryCount++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      if (_lastIp != null && _lastPort != null && _lastToken != null) {
        _doConnect(_lastIp!, _lastPort!, _lastToken!);
      }
    });
  }

  /// Send a raw binary packet. Returns false if not connected.
  bool send(Uint8List packet) {
    if (!_connected || _channel == null) return false;
    try {
      _channel!.sink.add(packet);
      return true;
    } catch (_) {
      _scheduleReconnect();
      return false;
    }
  }

  bool get isConnected => _connected;

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _destroyed = true;
    disconnect();
  }
}
