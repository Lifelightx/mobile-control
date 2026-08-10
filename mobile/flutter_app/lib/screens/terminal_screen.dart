import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../transport/transport_manager.dart';

class TerminalScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const TerminalScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final Terminal _terminal = Terminal();
  
  StreamSubscription? _subscription;
  String? _sessionId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initTerminal();
    
    // When the user types in the terminal, send it over unified transport
    _terminal.onOutput = (String data) {
      if (_sessionId != null) {
        transportManager.send(utf8.encode(jsonEncode({
          'type': 'terminal_input',
          'id': _sessionId,
          'data': data,
        })));
      }
    };
    
    _terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      if (_sessionId != null) {
        transportManager.send(utf8.encode(jsonEncode({
          'type': 'terminal_resize',
          'id': _sessionId,
          'cols': width,
          'rows': height,
        })));
      }
    };

    _subscription = transportManager.onData.listen((event) {
      try {
        final dataBytes = event['data'] as Uint8List;
        final message = utf8.decode(dataBytes);
        final parsed = jsonDecode(message);
        
        if (parsed['type'] == 'terminal_session') {
          setState(() {
            _sessionId = parsed['id'];
            _isLoading = false;
          });
        } else if (parsed['type'] == 'terminal_output' && parsed['id'] == _sessionId) {
          _terminal.write(parsed['data']);
        }
      } catch (e) {
        // ignore parse errors
      }
    });
  }

  void _initTerminal() {
    try {
      transportManager.send(utf8.encode(jsonEncode({
         'type': 'terminal_start',
         'cols': 80,
         'rows': 24,
      })));
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start terminal: $e')));
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_sessionId != null) {
      transportManager.send(utf8.encode(jsonEncode({
        'type': 'terminal_kill',
        'id': _sessionId,
      })));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Terminal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'monospace')),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
        : SafeArea(
            child: Container(
              color: Colors.black,
              child: TerminalView(_terminal),
            ),
          ),
    );
  }
}
