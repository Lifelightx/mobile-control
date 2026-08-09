import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'encoder.dart';

/// Gesture types produced by the gesture engine.
enum GestureEvent {
  mouseMove,
  mouseDown,
  mouseUp,
  mouseScroll,
  click,
  doubleClick,
  rightClick,
  dragStart,
  dragMove,
  dragEnd,
}

/// A decoded gesture event with associated data.
class GestureResult {
  final GestureEvent event;
  final int dx;
  final int dy;
  final int button; // 0=left, 1=right, 2=middle

  const GestureResult({
    required this.event,
    this.dx = 0,
    this.dy = 0,
    this.button = 0,
  });
}

/// Converts raw Flutter touch events into remote desktop input packets.
///
/// Gesture mapping (as per Phase 9 of the plan):
///   1 finger move         → cursor movement (relative)
///   1 finger tap          → left click
///   1 finger double tap   → double click
///   1 finger long press   → drag start
///   2 finger move         → scroll
///   2 finger tap          → right click
class GestureEngine extends StatefulWidget {
  /// Called whenever a gesture is translated into a binary packet.
  final void Function(Uint8List packet) onPacket;

  /// Pointer sensitivity multiplier (1.0 = 1:1).
  final double sensitivity;

  const GestureEngine({
    super.key,
    required this.onPacket,
    this.sensitivity = 1.5,
  });

  @override
  State<GestureEngine> createState() => _GestureEngineState();
}

class _GestureEngineState extends State<GestureEngine> {
  // ─── Touch tracking ─────────────────────────────────────────────────────

  final Map<int, Offset> _pointers = {}; // pointerId → last position
  bool _isDragging = false;

  // For tap detection
  DateTime? _lastTapTime;
  static const _doubleTapWindow = Duration(milliseconds: 300);

  // Scroll accumulator (sub-pixel smoothing)
  double _scrollAccX = 0;
  double _scrollAccY = 0;
  static const _scrollThreshold = 3.0;

  // ─── Pointer event handlers ──────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;

    final delta = e.localPosition - prev;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 1) {
      // ── 1-finger: cursor movement ──
      if (!_isDragging) {
        final dx = (delta.dx * widget.sensitivity).round();
        final dy = (delta.dy * widget.sensitivity).round();
        if (dx != 0 || dy != 0) {
          widget.onPacket(BinaryEncoder.encodeMouseMove(dx, dy));
        }
      } else {
        // Drag: hold left button and move
        final dx = (delta.dx * widget.sensitivity).round();
        final dy = (delta.dy * widget.sensitivity).round();
        if (dx != 0 || dy != 0) {
          widget.onPacket(BinaryEncoder.encodeMouseMove(dx, dy));
        }
      }
    } else if (_pointers.length == 2) {
      // ── 2-finger: scroll ──
      _scrollAccX += delta.dx;
      _scrollAccY += delta.dy;

      // Emit scroll only when accumulated delta exceeds threshold
      int scrollDx = 0, scrollDy = 0;
      if (_scrollAccX.abs() >= _scrollThreshold) {
        scrollDx = (_scrollAccX / _scrollThreshold).round();
        _scrollAccX = 0;
      }
      if (_scrollAccY.abs() >= _scrollThreshold) {
        scrollDy = -(_scrollAccY / _scrollThreshold).round(); // inverted
        _scrollAccY = 0;
      }
      if (scrollDx != 0 || scrollDy != 0) {
        widget.onPacket(BinaryEncoder.encodeMouseScroll(scrollDx, scrollDy));
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final wasDown = _pointers.remove(e.pointer);

    if (wasDown == null) return;

    if (_isDragging && _pointers.isEmpty) {
      // Drag end → release left button
      _isDragging = false;
      widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 0));
      return;
    }

    if (_pointers.isEmpty) {
      // ── 1-finger lift: tap or double-tap ──
      final now = DateTime.now();
      if (_lastTapTime != null &&
          now.difference(_lastTapTime!) < _doubleTapWindow) {
        // Double-tap → double click
        _lastTapTime = null;
        _emitDoubleClick();
      } else {
        _lastTapTime = now;
        // Defer single click to allow double-tap window
        Future.delayed(_doubleTapWindow, () {
          if (_lastTapTime != null &&
              DateTime.now().difference(_lastTapTime!) >= _doubleTapWindow) {
            _lastTapTime = null;
            _emitClick();
          }
        });
      }
    } else if (_pointers.length == 1) {
      // 2-finger lift — 2-finger tap = right click
      _scrollAccX = 0;
      _scrollAccY = 0;
      _emitRightClick();
    }
  }

  void _onLongPress(LongPressStartDetails details) {
    // Long press = drag start
    _isDragging = true;
    widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 0));
  }

  // ─── Gesture helpers ─────────────────────────────────────────────────────

  void _emitClick() {
    widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 0));
    widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 0));
  }

  void _emitDoubleClick() {
    _emitClick();
    Future.microtask(_emitClick);
  }

  void _emitRightClick() {
    widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseDown, 1));
    widget.onPacket(BinaryEncoder.encodeMouseButton(Opcode.mouseUp, 1));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onLongPressStart: _onLongPress,
        behavior: HitTestBehavior.opaque,
        child: widget is _GestureEngineWithChild
            ? (_GestureEngineWithChild as dynamic).child
            : const SizedBox.expand(),
      ),
    );
  }
}

// Ignore unused — child prop may be added in future
class _GestureEngineWithChild {}
