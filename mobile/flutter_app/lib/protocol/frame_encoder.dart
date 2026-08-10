import 'dart:typed_data';

class FrameEncoder {
  static Uint8List encode(Uint8List payload) {
    final length = payload.length;
    final buffer = ByteData(4);
    buffer.setUint32(0, length, Endian.big);
    
    final result = Uint8List(4 + length);
    result.setAll(0, buffer.buffer.asUint8List());
    result.setAll(4, payload);
    return result;
  }
}
