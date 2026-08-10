import 'dart:async';
import 'dart:typed_data';

enum TransportType {
  wifi,
  bluetooth,
}

abstract class Transport {
  TransportType get type;
  bool get isConnected;

  Future<void> connect();
  Future<void> disconnect();
  Future<void> send(Uint8List data);

  Stream<Uint8List> get onData;
  Stream<void> get onClose;
  Stream<dynamic> get onError;
}
