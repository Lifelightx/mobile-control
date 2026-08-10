import 'dart:async';
import 'package:flutter/services.dart';

class BluetoothPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.controlhub.mobile_app/bluetooth');
  static const EventChannel _eventChannel = EventChannel('com.controlhub.mobile_app/bluetooth_events');

  static Future<List<Map<String, dynamic>>> getPairedDevices() async {
    final List<dynamic> devices = await _methodChannel.invokeMethod('getPairedDevices');
    return devices.cast<Map<String, dynamic>>();
  }

  static Future<bool> connect(String address) async {
    final bool result = await _methodChannel.invokeMethod('connect', {'address': address});
    return result;
  }

  static Future<void> disconnect() async {
    await _methodChannel.invokeMethod('disconnect');
  }

  static Future<void> send(List<int> data) async {
    await _methodChannel.invokeMethod('send', {'data': data});
  }

  static Stream<dynamic> get onEvents {
    return _eventChannel.receiveBroadcastStream();
  }
}
