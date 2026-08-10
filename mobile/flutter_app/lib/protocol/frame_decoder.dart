import 'dart:async';
import 'dart:typed_data';

class FrameDecoder {
  final _controller = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get onFrame => _controller.stream;

  Uint8List _buffer = Uint8List(0);

  void push(Uint8List data) {
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setAll(0, _buffer);
    newBuffer.setAll(_buffer.length, data);
    _buffer = newBuffer;
    
    _processBuffer();
  }

  void _processBuffer() {
    while (_buffer.length >= 4) {
      final byteData = ByteData.sublistView(_buffer, 0, 4);
      final length = byteData.getUint32(0, Endian.big);
      final totalLength = 4 + length;

      if (_buffer.length >= totalLength) {
        final frame = _buffer.sublist(4, totalLength);
        _controller.add(frame);
        _buffer = _buffer.sublist(totalLength);
      } else {
        break; // Wait for more data
      }
    }
  }

  void dispose() {
    _controller.close();
  }
}
