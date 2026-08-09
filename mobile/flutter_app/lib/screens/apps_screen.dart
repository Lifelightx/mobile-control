import 'dart:async';
import 'package:flutter/material.dart';
import '../api_client.dart';
import 'app_control_detail_screen.dart';

class AppsScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const AppsScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customCmdController = TextEditingController();
  late TabController _tabController;

  List<dynamic> _installedApps = [];
  List<dynamic> _processes = [];
  int _totalProcesses = 0;
  bool _isLoading = true;
  bool _isAutoRefresh = true;
  String _sortBy = 'cpu'; // 'cpu' or 'mem'
  String _searchQuery = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _customCmdController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_isAutoRefresh && mounted && !_isLoading && _tabController.index == 1) {
        _fetchProcesses(showLoading: false);
      }
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchInstalledApps(),
      _fetchProcesses(showLoading: false),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchInstalledApps() async {
    try {
      final apps = await _apiClient.fetchInstalledApps(widget.ip, widget.port, widget.token);
      if (mounted) {
        setState(() => _installedApps = apps);
      }
    } catch (_) {
      // Fallback handles default preset apps
    }
  }

  Future<void> _fetchProcesses({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _apiClient.fetchProcesses(
        widget.ip,
        widget.port,
        widget.token,
        sortBy: _sortBy,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _processes = res['processes'] ?? [];
          _totalProcesses = res['total'] ?? 0;
          if (showLoading) _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading processes: $e')),
        );
      }
    }
  }

  Future<void> _launchCommand(String command) async {
    try {
      await _apiClient.launchApp(widget.ip, widget.port, widget.token, command);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚀 Launched: $command'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _fetchProcesses(showLoading: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Launch failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _killProcess(int pid, String processName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Kill Process?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to kill "$processName" (PID: $pid)?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kill Process', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiClient.killProcess(widget.ip, widget.port, widget.token, pid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Killed process $processName ($pid)'),
            backgroundColor: Colors.amber.shade900,
          ),
        );
      }
      _fetchProcesses(showLoading: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kill failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _showCustomLaunchDialog() {
    _customCmdController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Custom Command', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a terminal command or app binary:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customCmdController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'e.g. code ~/project or spotify',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.pop(ctx);
                  _launchCommand(val.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            onPressed: () {
              final cmd = _customCmdController.text.trim();
              if (cmd.isNotEmpty) {
                Navigator.pop(ctx);
                _launchCommand(cmd);
              }
            },
            child: const Text('Launch', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.cyanAccent;
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.cyanAccent;
    }
  }

  IconData _getIconData(String iconKey) {
    switch (iconKey) {
      case 'code':
        return Icons.code_rounded;
      case 'web':
      case 'browser':
        return Icons.language_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'folder':
        return Icons.folder_open_rounded;
      case 'calculator':
        return Icons.calculate_rounded;
      case 'music_note':
        return Icons.music_note_rounded;
      case 'movie':
        return Icons.movie_rounded;
      case 'api':
        return Icons.api_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'forum':
        return Icons.forum_rounded;
      case 'view_in_ar':
        return Icons.view_in_ar_rounded;
      case 'palette':
        return Icons.palette_rounded;
      case 'note':
        return Icons.edit_note_rounded;
      case 'android':
        return Icons.android_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Application Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_task_rounded, color: Colors.cyanAccent),
            tooltip: 'Run Custom Command',
            onPressed: _showCustomLaunchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () => _loadInitialData(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          indicatorWeight: 3,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Installed Apps'),
            Tab(icon: Icon(Icons.memory_rounded, size: 20), text: 'Running Processes'),
          ],
        ),
      ),
      body: SafeArea(child: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Installed Apps Grid (3 per row)
          _buildInstalledAppsTab(),

          // TAB 2: Running Processes List
          _buildRunningProcessesTab(),
        ],
      )),
    );
  }

  // TAB 1: Installed Applications Grid (3 per row)
  Widget _buildInstalledAppsTab() {
    final filteredApps = _installedApps.where((app) {
      if (_searchQuery.isEmpty) return true;
      final name = (app['name'] ?? '').toString().toLowerCase();
      final cat = (app['category'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();

    return Column(
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search installed applications...',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Apps Grid (3 per row)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : filteredApps.isEmpty
                  ? const Center(
                      child: Text('No applications found', style: TextStyle(color: Colors.white54)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, // Exactly 3 apps per row
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: filteredApps.length,
                      itemBuilder: (ctx, idx) {
                        final app = filteredApps[idx] as Map<String, dynamic>;
                        final name = app['name'] ?? 'App';
                        final iconKey = app['icon'] ?? 'apps';
                        final colorHex = app['color'];
                        final color = _parseColor(colorHex);

                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AppControlDetailScreen(
                                  ip: widget.ip,
                                  port: widget.port,
                                  token: widget.token,
                                  app: app,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24, width: 1),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.18),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color.withOpacity(0.6), width: 1.5),
                                  ),
                                  child: Icon(_getIconData(iconKey), size: 24, color: color),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // TAB 2: Running Processes List
  Widget _buildRunningProcessesTab() {
    final filteredProcesses = _processes.where((p) {
      if (_searchQuery.isEmpty) return true;
      final name = (p['name'] ?? '').toString().toLowerCase();
      final cmd = (p['command'] ?? '').toString().toLowerCase();
      final pid = (p['pid'] ?? '').toString();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || cmd.contains(q) || pid.contains(q);
    }).toList();

    return Column(
      children: [
        // Search and Sort Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search process or PID...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                    items: const [
                      DropdownMenuItem(value: 'cpu', child: Text('Sort: CPU')),
                      DropdownMenuItem(value: 'mem', child: Text('Sort: MEM')),
                    ],
                    onChanged: (val) {
                      if (val != null && val != _sortBy) {
                        setState(() => _sortBy = val);
                        _fetchProcesses(showLoading: true);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Count Indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${filteredProcesses.length} of $_totalProcesses processes',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                ),
            ],
          ),
        ),

        // Process List View
        Expanded(
          child: _isLoading && _processes.isEmpty
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : filteredProcesses.isEmpty
                  ? const Center(
                      child: Text('No processes found', style: TextStyle(color: Colors.white54)),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _fetchProcesses(showLoading: false),
                      color: Colors.cyanAccent,
                      child: ListView.builder(
                        itemCount: filteredProcesses.length,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        itemBuilder: (ctx, idx) {
                          final proc = filteredProcesses[idx];
                          final pid = proc['pid'] ?? 0;
                          final name = proc['name'] ?? 'Unknown';
                          final cpu = (proc['cpu'] ?? 0.0).toDouble();
                          final mem = (proc['mem'] ?? 0.0).toDouble();
                          final user = proc['user'] ?? 'system';
                          final cmd = proc['command'] ?? '';

                          Color cpuColor = Colors.greenAccent;
                          if (cpu >= 50.0) {
                            cpuColor = Colors.redAccent;
                          } else if (cpu >= 15.0) {
                            cpuColor = Colors.amberAccent;
                          }

                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'PID $pid',
                                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (cmd.isNotEmpty && cmd != name)
                                      Text(
                                        cmd,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _buildMetricBadge('CPU', '${cpu.toStringAsFixed(1)}%', cpuColor),
                                        const SizedBox(width: 8),
                                        _buildMetricBadge('RAM', '${mem.toStringAsFixed(1)}%', Colors.cyanAccent),
                                        const SizedBox(width: 8),
                                        Text('User: $user', style: const TextStyle(color: Colors.white30, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                                tooltip: 'Kill Process',
                                onPressed: () => _killProcess(pid, name),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildMetricBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
