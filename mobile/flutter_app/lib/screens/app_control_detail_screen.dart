import 'package:flutter/material.dart';
import '../api_client.dart';

class AppControlDetailScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;
  final Map<String, dynamic> app;

  const AppControlDetailScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
    required this.app,
  }) : super(key: key);

  @override
  State<AppControlDetailScreen> createState() => _AppControlDetailScreenState();
}

class _AppControlDetailScreenState extends State<AppControlDetailScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _isPerforming = false;

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

  Future<void> _performAction(String action) async {
    setState(() => _isPerforming = true);
    final appName = widget.app['name'] ?? 'App';
    final cmd = widget.app['command'];

    try {
      await _apiClient.sendWindowAction(
        widget.ip,
        widget.port,
        widget.token,
        appName: appName,
        action: action,
        command: cmd,
      );

      if (mounted) {
        String msg = '';
        Color bg = Colors.cyan;
        switch (action) {
          case 'open':
            msg = '🚀 Launched $appName';
            bg = Colors.green.shade800;
            break;
          case 'close':
            msg = '🛑 Closed $appName';
            bg = Colors.red.shade800;
            break;
          case 'minimize':
            msg = '📉 Minimized $appName';
            bg = Colors.amber.shade900;
            break;
          case 'maximize':
            msg = '📈 Maximized $appName';
            bg = Colors.blue.shade800;
            break;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: bg,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerforming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.app['name'] ?? 'Application';
    final category = widget.app['category'] ?? 'System';
    final iconKey = widget.app['icon'] ?? 'apps';
    final colorHex = widget.app['color'];
    final command = widget.app['command'] ?? '';
    final themeColor = _parseColor(colorHex);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // App Header Hero Box
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: themeColor.withOpacity(0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: themeColor, width: 2),
                    ),
                    child: Icon(_getIconData(iconKey), size: 36, color: themeColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (command.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Window Actions',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 14),

            if (_isPerforming)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _buildActionButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Open',
                    color: Colors.greenAccent,
                    onTap: () => _performAction('open'),
                  ),
                  _buildActionButton(
                    icon: Icons.power_settings_new_rounded,
                    label: 'Close',
                    color: Colors.redAccent,
                    onTap: () => _performAction('close'),
                  ),
                  _buildActionButton(
                    icon: Icons.remove_rounded,
                    label: 'Minimize',
                    color: Colors.amberAccent,
                    onTap: () => _performAction('minimize'),
                  ),
                  _buildActionButton(
                    icon: Icons.crop_square_rounded,
                    label: 'Maximize',
                    color: Colors.cyanAccent,
                    onTap: () => _performAction('maximize'),
                  ),
                ],
              ),

            const SizedBox(height: 28),

            // Future app-specific control placeholder
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.white38),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom App Integration',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Specific shortcuts and controls for this app will be available soon.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
