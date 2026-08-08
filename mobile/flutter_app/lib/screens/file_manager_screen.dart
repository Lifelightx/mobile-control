import 'package:flutter/material.dart';
import '../api_client.dart';

class FileManagerScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const FileManagerScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _files = [];
  bool _isLoading = false;
  String _currentPath = '~';

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _currentPath = path;
    });
    try {
      final files = await _apiClient.listDirectory(widget.ip, widget.port, widget.token, path);
      if (mounted) {
        setState(() {
          _files = files;
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

  String _getParentPath(String path) {
    if (path == '~' || path == '/' || path.isEmpty) return path;
    final parts = path.split('/');
    if (parts.length <= 1) return '/';
    parts.removeLast();
    return parts.join('/').isEmpty ? '/' : parts.join('/');
  }

  Future<void> _deleteItem(String path, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete $name?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiClient.deleteFile(widget.ip, widget.port, widget.token, path);
        _loadDirectory(_currentPath);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _renameItem(String path, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'New Name', hintStyle: TextStyle(color: Colors.white30)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await _apiClient.renameFile(widget.ip, widget.port, widget.token, path, newName);
        _loadDirectory(_currentPath);
      } catch (e) {
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
        title: const Text('File Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: () => _loadDirectory(_currentPath),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                  onPressed: () {
                    final parent = _getParentPath(_currentPath);
                    if (parent != _currentPath) {
                      _loadDirectory(parent);
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (ctx, idx) {
                      final file = _files[idx] as Map<String, dynamic>;
                      final isDir = file['isDirectory'] == true;
                      final name = file['name'] as String;
                      final path = file['path'] as String;

                      return ListTile(
                        leading: Icon(
                          isDir ? Icons.folder : Icons.insert_drive_file,
                          color: isDir ? Colors.amber : Colors.white70,
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white54),
                          color: const Color(0xFF1E293B),
                          onSelected: (val) {
                            if (val == 'rename') _renameItem(path, name);
                            if (val == 'delete') _deleteItem(path, name);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename', style: TextStyle(color: Colors.white)),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                        onTap: () {
                          if (isDir) {
                            _loadDirectory(path);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
