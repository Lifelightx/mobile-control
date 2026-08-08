import 'package:flutter/material.dart';
import '../api_client.dart';

class DockerScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const DockerScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<DockerScreen> createState() => _DockerScreenState();
}

class _DockerScreenState extends State<DockerScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _containers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    setState(() => _isLoading = true);
    try {
      final containers = await _apiClient.listDockerContainers(widget.ip, widget.port, widget.token);
      if (mounted) {
        setState(() {
          _containers = containers;
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

  Future<void> _performAction(String action, String id, String name) async {
    try {
      if (action == 'start') {
        await _apiClient.startDockerContainer(widget.ip, widget.port, widget.token, id);
      } else if (action == 'stop') {
        await _apiClient.stopDockerContainer(widget.ip, widget.port, widget.token, id);
      } else if (action == 'restart') {
        await _apiClient.restartDockerContainer(widget.ip, widget.port, widget.token, id);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully ${action}ed $name')));
      _loadContainers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to $action $name: $e')));
    }
  }

  Future<void> _showLogs(String id, String name) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Logs: $name', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: FutureBuilder<String>(
          future: _apiClient.getDockerContainerLogs(widget.ip, widget.port, widget.token, id),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.cyan)));
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
            }
            return Container(
              width: double.maxFinite,
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: Text(
                  snapshot.data ?? 'No logs',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Docker Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _loadContainers,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _containers.length,
              itemBuilder: (ctx, idx) {
                final container = _containers[idx] as Map<String, dynamic>;
                final names = (container['names'] as List<dynamic>?)?.join(', ') ?? 'Unknown';
                final cleanName = names.startsWith('/') ? names.substring(1) : names;
                final state = container['state'] as String? ?? 'unknown';
                final status = container['status'] as String? ?? '';
                final isRunning = state.toLowerCase() == 'running';
                final id = container['id'] as String;

                return Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.directions_boat_rounded,
                        color: isRunning ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    title: Text(cleanName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white54),
                      color: const Color(0xFF0F172A),
                      onSelected: (val) {
                        if (val == 'logs') {
                          _showLogs(id, cleanName);
                        } else {
                          _performAction(val, id, cleanName);
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (!isRunning)
                          const PopupMenuItem(
                            value: 'start',
                            child: Text('Start', style: TextStyle(color: Colors.greenAccent)),
                          ),
                        if (isRunning) ...[
                          const PopupMenuItem(
                            value: 'stop',
                            child: Text('Stop', style: TextStyle(color: Colors.redAccent)),
                          ),
                          const PopupMenuItem(
                            value: 'restart',
                            child: Text('Restart', style: TextStyle(color: Colors.orangeAccent)),
                          ),
                        ],
                        const PopupMenuItem(
                          value: 'logs',
                          child: Text('Logs', style: TextStyle(color: Colors.cyanAccent)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
