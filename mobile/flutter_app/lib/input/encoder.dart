import 'dart:typed_data';

enum Opcode {
  mouseMove(0x01),
  mouseDown(0x02),
  mouseUp(0x03),
  mouseScroll(0x04),
  keyDown(0x05),
  keyUp(0x06);

  final int value;
  const Opcode(this.value);
}

class BinaryEncoder {
  static const int headerSize = 12;
  static const int version = 1;
  static int _sequence = 0;

  /// Encodes an input event into a binary packet.
  /// Header Layout:
  /// [0]    uint8  Version
  /// [1]    uint8  Opcode
  /// [2-3]  uint16 Sequence (Big Endian)
  /// [4-7]  uint32 Timestamp (Big Endian)
  /// [8-11] uint32 Payload Length (Big Endian)
  static Uint8List encode(Opcode opcode, Uint8List payload) {
    final payloadLength = payload.length;
    final totalSize = headerSize + payloadLength;
    final buffer = Uint8List(totalSize);
    final data = ByteData.view(buffer.buffer);

    // Version (1 byte)
    data.setUint8(0, version);
    
    // Opcode (1 byte)
    data.setUint8(1, opcode.value);
    
    // Sequence (2 bytes)
    _sequence = (_sequence + 1) % 65536;
    data.setUint16(2, _sequence, Endian.big);
    
    // Timestamp (4 bytes)
    final timestamp = DateTime.now().millisecondsSinceEpoch % 4294967296;
    data.setUint32(4, timestamp, Endian.big);
    
    // Payload Length (4 bytes)
    data.setUint32(8, payloadLength, Endian.big);

    // Payload
    buffer.setAll(headerSize, payload);

    return buffer;
  }
  
  // Helpers for specific payloads
  
  static Uint8List encodeMouseMove(int dx, int dy) {
    final payload = Uint8List(4);
    final data = ByteData.view(payload.buffer);
    data.setInt16(0, dx, Endian.big);
    data.setInt16(2, dy, Endian.big);
    return encode(Opcode.mouseMove, payload);
  }
  
  static Uint8List encodeMouseButton(Opcode op, int button) {
    final payload = Uint8List(1);
    payload[0] = button;
    return encode(op, payload);
  }
  
  static Uint8List encodeMouseScroll(int dx, int dy) {
    final payload = Uint8List(4);
    final data = ByteData.view(payload.buffer);
    data.setInt16(0, dx, Endian.big);
    data.setInt16(2, dy, Endian.big);
    return encode(Opcode.mouseScroll, payload);
  }
  
  static Uint8List encodeKey(Opcode op, int keycode) {
    final payload = Uint8List(2);
    final data = ByteData.view(payload.buffer);
    data.setUint16(0, keycode, Endian.big);
    return encode(op, payload);
  }
}
