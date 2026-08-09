import 'package:flutter/material.dart';
import '../api_client.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const NotificationsScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifs = await _apiClient.getNotifications(widget.ip, widget.port, widget.token);
      if (mounted) {
        setState(() {
          _notifications = notifs;
          _isLoading = false;
        });
        // Mark all as read after fetching
        _apiClient.markNotificationsRead(widget.ip, widget.port, widget.token);
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
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _loadNotifications,
          )
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
            : _notifications.isEmpty
                ? const Center(child: Text('No notifications', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (ctx, idx) {
                      final n = _notifications[idx];
                      final date = DateTime.fromMillisecondsSinceEpoch(n['timestamp']);
                      final formattedDate = DateFormat('MMM d, h:mm a').format(date);
                      final isRead = n['read'] == 1;

                      return Container(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                          color: isRead ? Colors.transparent : Colors.cyan.withValues(alpha: 0.1),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.cyan.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.notifications, color: Colors.cyanAccent, size: 20),
                          ),
                          title: Text(n['title'], style: TextStyle(color: Colors.white, fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(n['message'], style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(formattedDate, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
