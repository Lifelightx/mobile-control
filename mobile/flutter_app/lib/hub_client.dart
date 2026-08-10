import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'notification_service.dart';
import 'transport/transport.dart';
import 'transport/transport_manager.dart';
import 'transport/wifi/websocket_transport.dart';
import 'transport/bluetooth/bluetooth_transport.dart';
import 'transport/bluetooth/bluetooth_platform.dart';
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
        AppLogger.log('[HubClient] Wi-Fi failed, checking Bluetooth paired devices.', ip, port);
        // Phase 9: Automatic Fallback to Bluetooth
        bool btConnected = false;
        // Request permissions before attempting fallback
        await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.location,
        ].request();

        try {
          final devices = await BluetoothPlatform.getPairedDevices();
          if (devices.isNotEmpty) {
            // Pick the first paired device for now or we could match a saved MAC
            final address = devices.first['address'] as String;
            final btTransport = BluetoothTransport(address);
            await btTransport.connect();
            
            // Phase 7: Authenticate
            final authPayload = utf8.encode(jsonEncode({
              'type': 'auth',
              'protocolVersion': 1,
              'token': token,
            })) as Uint8List;
            
            await btTransport.send(authPayload);
            
            final authResponseData = await btTransport.onData.first.timeout(const Duration(seconds: 5));
            final authResponse = jsonDecode(utf8.decode(authResponseData));
            
            if (authResponse['type'] == 'auth_success') {
              transportManager.addTransport(btTransport);
              transportManager.setActiveTransport(TransportType.bluetooth);
              btConnected = true;
              AppLogger.log('[HubClient] Bluetooth connection authenticated and successful.');
            } else {
              throw Exception('Bluetooth auth failed: ${authResponse['error']}');
            }
          }
        } catch (btErr) {
          AppLogger.log('[HubClient] Bluetooth fallback failed: $btErr');
        }

        if (!btConnected) {
          throw Exception('Both Wi-Fi and Bluetooth connection failed');
        }
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

  Future<String> pairViaBluetooth(String deviceId, String deviceName, String secret) async {
    // Request permissions for Android 12+
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    final devices = await BluetoothPlatform.getPairedDevices();
    if (devices.isEmpty) throw Exception("No paired Bluetooth devices found on your phone. Please pair with the laptop in Android Settings first.");
    
    List<String> errors = [];

    for (var device in devices) {
      final name = device['name'] as String? ?? 'Unknown';
      try {
        final address = device['address'] as String;
        final connected = await BluetoothPlatform.connect(address);
        if (!connected) {
          errors.add("$name: Connection refused.");
          continue;
        }

        final completer = Completer<String>();
        StreamSubscription? sub;
        
        sub = BluetoothPlatform.onEvents.listen((event) {
          if (event is Map) {
            final type = event['type'];
            if (type == 'data') {
              final data = event['data'] as Uint8List;
              try {
                if (data.length > 4) {
                  final payload = data.sublist(4);
                  final message = utf8.decode(payload);
                  final parsed = jsonDecode(message);
                  if (parsed['type'] == 'pair_success') {
                    completer.complete(parsed['token']);
                  } else if (parsed['type'] == 'pair_failure') {
                    completer.completeError(parsed['error'] ?? 'Server rejected pairing');
                  }
                }
              } catch (e) {}
            } else if (type == 'disconnected') {
              if (!completer.isCompleted) completer.completeError("Socket disconnected");
            }
          }
        });
        
        void sendFrame(String msg) {
          final payload = utf8.encode(msg) as Uint8List;
          final header = ByteData(4);
          header.setUint32(0, payload.length, Endian.big);
          final frame = Uint8List(4 + payload.length);
          frame.setAll(0, header.buffer.asUint8List());
          frame.setAll(4, payload);
          BluetoothPlatform.send(frame);
        }
        
        sendFrame(jsonEncode({
          'type': 'pair',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'secret': secret
        }));
        
        final token = await completer.future.timeout(const Duration(seconds: 10));
        sub.cancel();
        
        await BluetoothPlatform.disconnect();
        return token;
      } catch (e) {
         errors.add("$name: $e");
         await BluetoothPlatform.disconnect();
      }
    }
    throw Exception("Bluetooth Pairing Failed:\n" + errors.join("\n"));
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
