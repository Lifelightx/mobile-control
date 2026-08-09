import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../input/encoder.dart';
import '../input/transport.dart';

class TrackpadScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const TrackpadScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.token,
  });

  @override
  State<TrackpadScreen> createState() => _TrackpadScreenState();
}

class _TrackpadScreenState extends State<TrackpadScreen> {
  late final InputTransport _transport;
  final TextEditingController _keyboardController = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();

  bool _showKeyboard = false;
  bool _isDragging = false;

  // Touch tracking
  final Map<int, Offset> _pointers = {};
  DateTime? _lastTapTime;
  static const _doubleTapWindow = Duration(milliseconds: 300);

  // Scroll accumulation
  double _scrollAccY = 0;
  double _scrollAccX = 0;
  static const _scrollThreshold = 4.0;

  // Sensitivity
  double _sensitivity = 1.6;

  @override
  void initState() {
    super.initState();
    _transport = InputTransport();
    _transport.connect(widget.ip, widget.port, widget.token);
  }

  @override
  void dispose() {
    _transport.dispose();
    _keyboardController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _send(Uint8List packet) => _transport.send(packet);

  // ─── Pointer handlers ──────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    final delta = e.localPosition - prev;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 1) {
      final dx = (delta.dx * _sensitivity).round();
      final dy = (delta.dy * _sensitivity).round();
      if (dx != 0 || dy != 0) {
        _send(BinaryEncoder.encodeMouseMove(dx, dy));
      }
    } else if (_pointers.length == 2) {
      _scrollAccX += delta.dx;
      _scrollAccY += delta.dy;
      int sdx = 0, sdy = 0;
      if (_scrollAccX.abs() >= _scrollThreshold) {
        sdx = (_scrollAccX / _scrollThreshold).round();
        _scrollAccX = 0;
      }
      if (_scrollAccY.abs() >= _scrollThreshold) {
        sdy = -(_scrollAccY / _scrollThreshold).round();
        _scrollAccY = 0;
      }
      if (sdx != 0 || sdy != 0) {
        _send(BinaryEncoder.encodeMouseScroll(sdx, sdy));
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);

    if (_isDragging && _pointers.isEmpty) {
      _isDragging = false;
      _send(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 0));
      return;
    }

    if (_pointers.isEmpty) {
      final now = DateTime.now();
      if (_lastTapTime != null && now.difference(_lastTapTime!) < _doubleTapWindow) {
        _lastTapTime = null;
        _emitDoubleClick();
      } else {
        _lastTapTime = now;
        Future.delayed(_doubleTapWindow, () {
          if (_lastTapTime != null &&
              DateTime.now().difference(_lastTapTime!) >= _doubleTapWindow) {
            _lastTapTime = null;
            _emitClick();
          }
        });
      }
    } else if (_pointers.length == 1) {
      _scrollAccX = 0;
      _scrollAccY = 0;
      _emitRightClick();
    }
  }

  void _emitClick() {
    _send(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 0));
    _send(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 0));
  }

  void _emitDoubleClick() {
    _emitClick();
    Future.microtask(_emitClick);
  }

  void _emitRightClick() {
    _send(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 1));
    _send(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 1));
  }

  // ─── Keyboard ─────────────────────────────────────────────────────────

  void _onKeyEvent(KeyEvent e) {
    final physicalKey = e.physicalKey;
    final keycode = _physicalKeyToLinux(physicalKey);
    if (keycode == null) return;

    if (e is KeyDownEvent) {
      _send(BinaryEncoder.encodeKey(Opcode.keyDown, keycode));
    } else if (e is KeyUpEvent) {
      _send(BinaryEncoder.encodeKey(Opcode.keyUp, keycode));
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.mouse_rounded, color: Color(0xFF8839EF), size: 20),
            const SizedBox(width: 8),
            const Text('Trackpad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            _buildConnectionIndicator(),
          ],
        ),
        actions: [
          // Sensitivity control
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white54),
            onPressed: _showSensitivityDialog,
            tooltip: 'Sensitivity',
          ),
          // Toggle keyboard
          IconButton(
            icon: Icon(
              _showKeyboard ? Icons.keyboard_hide : Icons.keyboard_rounded,
              color: _showKeyboard ? const Color(0xFF8839EF) : Colors.white54,
            ),
            onPressed: () {
              setState(() => _showKeyboard = !_showKeyboard);
              if (_showKeyboard) {
                _keyboardFocus.requestFocus();
              } else {
                _keyboardFocus.unfocus();
              }
            },
            tooltip: 'Toggle Keyboard',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: Column(
        children: [
          // ── Trackpad surface ──────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Trackpad background with grid pattern
                Positioned.fill(
                  child: CustomPaint(painter: _TrackpadPainter()),
                ),
                // Gesture capture layer
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    behavior: HitTestBehavior.opaque,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (_) {
                        _isDragging = true;
                        _send(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 0));
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                // Hint overlay
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: const [
                      Text('1 finger — move cursor', style: TextStyle(color: Colors.white24, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('2 fingers — scroll  •  2-finger tap — right click', style: TextStyle(color: Colors.white24, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('long press — drag', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Mouse buttons ─────────────────────────────────────────────
          _buildMouseButtons(),

          // ── Hidden keyboard capture ───────────────────────────────────
          if (_showKeyboard)
            KeyboardListener(
              focusNode: _keyboardFocus,
              onKeyEvent: _onKeyEvent,
              child: Container(
                height: 0,
                color: Colors.transparent,
              ),
            ),
        ],
      )),
    );
  }

  Widget _buildConnectionIndicator() {
    return StreamBuilder<bool>(
      // Poll connection state every second
      stream: Stream.periodic(const Duration(seconds: 1))
          .map((_) => _transport.isConnected),
      builder: (context, snap) {
        final connected = snap.data ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: connected
                ? Colors.greenAccent.withOpacity(0.15)
                : Colors.redAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: connected ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                connected ? 'Connected' : 'Reconnecting…',
                style: TextStyle(
                  color: connected ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMouseButtons() {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildBtn('Left', 0)),
          const SizedBox(width: 1),
          SizedBox(width: 60, child: _buildBtn('Mid', 2)),
          const SizedBox(width: 1),
          Expanded(child: _buildBtn('Right', 1)),
        ],
      ),
    );
  }

  Widget _buildBtn(String label, int button) {
    return GestureDetector(
      onTapDown: (_) => _send(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, button)),
      onTapUp: (_) => _send(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, button)),
      onTapCancel: () => _send(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, button)),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF28283E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF28283E),
        title: const Text('Sensitivity', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (ctx, setS) => Slider(
            value: _sensitivity,
            min: 0.5,
            max: 4.0,
            divisions: 14,
            activeColor: const Color(0xFF8839EF),
            label: _sensitivity.toStringAsFixed(1),
            onChanged: (v) {
              setS(() => _sensitivity = v);
              setState(() => _sensitivity = v);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Color(0xFF8839EF))),
          ),
        ],
      ),
    );
  }

  // ─── Linux keycode map ─────────────────────────────────────────────────

  int? _physicalKeyToLinux(PhysicalKeyboardKey key) {
    final map = {
      PhysicalKeyboardKey.escape: 1,
      PhysicalKeyboardKey.digit1: 2,
      PhysicalKeyboardKey.digit2: 3,
      PhysicalKeyboardKey.digit3: 4,
      PhysicalKeyboardKey.digit4: 5,
      PhysicalKeyboardKey.digit5: 6,
      PhysicalKeyboardKey.digit6: 7,
      PhysicalKeyboardKey.digit7: 8,
      PhysicalKeyboardKey.digit8: 9,
      PhysicalKeyboardKey.digit9: 10,
      PhysicalKeyboardKey.digit0: 11,
      PhysicalKeyboardKey.backspace: 14,
      PhysicalKeyboardKey.tab: 15,
      PhysicalKeyboardKey.enter: 28,
      PhysicalKeyboardKey.controlLeft: 29,
      PhysicalKeyboardKey.keyA: 30,
      PhysicalKeyboardKey.keyS: 31,
      PhysicalKeyboardKey.keyD: 32,
      PhysicalKeyboardKey.keyF: 33,
      PhysicalKeyboardKey.keyG: 34,
      PhysicalKeyboardKey.keyH: 35,
      PhysicalKeyboardKey.keyJ: 36,
      PhysicalKeyboardKey.keyK: 37,
      PhysicalKeyboardKey.keyL: 38,
      PhysicalKeyboardKey.shiftLeft: 42,
      PhysicalKeyboardKey.keyZ: 44,
      PhysicalKeyboardKey.keyX: 45,
      PhysicalKeyboardKey.keyC: 46,
      PhysicalKeyboardKey.keyV: 47,
      PhysicalKeyboardKey.keyB: 48,
      PhysicalKeyboardKey.keyN: 49,
      PhysicalKeyboardKey.keyM: 50,
      PhysicalKeyboardKey.shiftRight: 54,
      PhysicalKeyboardKey.altLeft: 56,
      PhysicalKeyboardKey.space: 57,
      PhysicalKeyboardKey.capsLock: 58,
      PhysicalKeyboardKey.f1: 59,
      PhysicalKeyboardKey.f2: 60,
      PhysicalKeyboardKey.f3: 61,
      PhysicalKeyboardKey.f4: 62,
      PhysicalKeyboardKey.f5: 63,
      PhysicalKeyboardKey.f6: 64,
      PhysicalKeyboardKey.f7: 65,
      PhysicalKeyboardKey.f8: 66,
      PhysicalKeyboardKey.f9: 67,
      PhysicalKeyboardKey.f10: 68,
      PhysicalKeyboardKey.f11: 87,
      PhysicalKeyboardKey.f12: 88,
      PhysicalKeyboardKey.controlRight: 97,
      PhysicalKeyboardKey.altRight: 100,
      PhysicalKeyboardKey.home: 102,
      PhysicalKeyboardKey.arrowUp: 103,
      PhysicalKeyboardKey.pageUp: 104,
      PhysicalKeyboardKey.arrowLeft: 105,
      PhysicalKeyboardKey.arrowRight: 106,
      PhysicalKeyboardKey.end: 107,
      PhysicalKeyboardKey.arrowDown: 108,
      PhysicalKeyboardKey.pageDown: 109,
      PhysicalKeyboardKey.insert: 110,
      PhysicalKeyboardKey.delete: 111,
      PhysicalKeyboardKey.metaLeft: 125,
      PhysicalKeyboardKey.metaRight: 126,
    };
    return map[key];
  }
}

// ─── Trackpad surface painter ──────────────────────────────────────────────

class _TrackpadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF141428);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Subtle dot grid
    final dotPaint = Paint()..color = const Color(0xFF8839EF).withOpacity(0.08);
    const spacing = 28.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Rounded border glow
    final borderPaint = Paint()
      ..color = const Color(0xFF8839EF).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
        const Radius.circular(20),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
