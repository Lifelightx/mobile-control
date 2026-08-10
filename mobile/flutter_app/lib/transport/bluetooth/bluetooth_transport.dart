import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../transport.dart';
import '../../protocol/frame_decoder.dart';
import '../../protocol/frame_encoder.dart';
import 'bluetooth_platform.dart';

class BluetoothTransport implements Transport {
  @override
  final TransportType type = TransportType.bluetooth;
  
  final String address;
  bool _isConnected = false;
  
  final _dataController = StreamController<Uint8List>.broadcast();
  final _closeController = StreamController<void>.broadcast();
  final _errorController = StreamController<dynamic>.broadcast();
  
  final _decoder = FrameDecoder();
  StreamSubscription? _eventSubscription;

  BluetoothTransport(this.address) {
    _decoder.onFrame.listen((frame) {
      _dataController.add(frame);
    });
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    try {
      _isConnected = await BluetoothPlatform.connect(address);
      if (_isConnected) {
        _eventSubscription = BluetoothPlatform.onEvents.listen(
          (dynamic event) {
            if (event is Uint8List) {
              _decoder.push(event);
            }
          },
          onError: (error) {
            _handleDisconnect(error);
          },
          onDone: () {
            _handleDisconnect(null);
          },
        );
      }
    } catch (e) {
      _isConnected = false;
      throw Exception('Failed to connect to Bluetooth device: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    await BluetoothPlatform.disconnect();
    _handleDisconnect(null);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_isConnected) throw Exception('Bluetooth socket disconnected');
    final framed = FrameEncoder.encode(data);
    await BluetoothPlatform.send(framed);
  }

  void _handleDisconnect(dynamic error) {
    if (!_isConnected) return;
    _isConnected = false;
    _eventSubscription?.cancel();
    
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
    _decoder.dispose();
  }
}
