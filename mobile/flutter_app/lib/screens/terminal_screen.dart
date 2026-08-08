import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import '../api_client.dart';

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
  final ApiClient _apiClient = ApiClient();
  final Terminal _terminal = Terminal();
  
  WebSocketChannel? _channel;
  String? _sessionId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initTerminal();
    
    // When the user types in the terminal, send it to the websocket
    _terminal.onOutput = (String data) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'input',
          'data': data,
        }));
      }
    };
    
    _terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'resize',
          'cols': width,
          'rows': height,
        }));
      }
    };
  }

  Future<void> _initTerminal() async {
    try {
      final id = await _apiClient.createTerminalSession(widget.ip, widget.port, widget.token);
      setState(() {
        _sessionId = id;
        _isLoading = false;
      });
      _connectWebSocket(id);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start terminal: $e')));
      }
    }
  }

  void _connectWebSocket(String id) {
    final wsUrl = 'ws://${widget.ip}:${widget.port}/terminal/ws/$id?token=${widget.token}';
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'data') {
            _terminal.write(data['data']);
          }
        } catch (e) {}
      },
      onDone: () {
        _terminal.write('\r\n[Connection Closed]\r\n');
      },
      onError: (err) {
        _terminal.write('\r\n[Connection Error: $err]\r\n');
      },
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    if (_sessionId != null) {
      _apiClient.killTerminalSession(widget.ip, widget.port, widget.token, _sessionId!);
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
