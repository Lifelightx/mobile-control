import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api_client.dart';

class ClipboardScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const ClipboardScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchClipboard();
  }

  Future<void> _fetchClipboard() async {
    setState(() => _isLoading = true);
    try {
      final text = await _apiClient.getClipboard(widget.ip, widget.port, widget.token);
      if (mounted) {
        setState(() {
          _controller.text = text;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _syncToPhone() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to phone clipboard!')));
    }
  }

  Future<void> _syncToLaptop() async {
    setState(() => _isLoading = true);
    try {
      await _apiClient.setClipboard(widget.ip, widget.port, widget.token, _controller.text);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced to laptop clipboard!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Clipboard Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _fetchClipboard,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Clipboard is empty...',
                          hintStyle: TextStyle(color: Colors.white30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _syncToPhone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyan,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.download, color: Colors.black),
                          label: const Text('Copy to Phone', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _syncToLaptop,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.upload, color: Colors.black),
                          label: const Text('Send to Laptop', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
