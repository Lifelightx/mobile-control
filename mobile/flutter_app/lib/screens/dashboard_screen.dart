import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/connection_bloc.dart';
import '../api_client.dart';
import 'apps_screen.dart';
import 'terminal_screen.dart';
import 'file_manager_screen.dart';
import 'docker_screen.dart';
import 'automation_screen.dart';
import 'notifications_screen.dart';
import 'clipboard_screen.dart';
import 'unlock_screen.dart';
import 'trackpad_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    
    final List<String> parts = [];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    
    return parts.join(' ');
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double dBytes = bytes.toDouble();
    while (dBytes >= 1024 && i < suffixes.length - 1) {
      dBytes /= 1024;
      i++;
    }
    return '${dBytes.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, HubConnectionState>(
      builder: (context, state) {
        if (state is! DashboardActive) {
          return const Scaffold(
            backgroundColor: Color(0xFF1E1E2E),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF8839EF))),
          );
        }

        final staticInfo = state.staticInfo;
        final liveMetrics = state.liveMetrics;

        // Static specs
        final os = staticInfo['os'] ?? {};
        final cpuSpec = staticInfo['cpu'] ?? {};
        final memSpec = staticInfo['mem'] ?? {};

        // Dynamic metrics
        final cpuLoad = (liveMetrics['cpuLoad'] as num?)?.toDouble() ?? 0.0;
        final cpuTemp = (liveMetrics['cpuTemp'] as num?)?.toDouble() ?? 0.0;
        final mem = liveMetrics['mem'] ?? {};
        final battery = liveMetrics['battery'] ?? {};
        final uptime = (liveMetrics['uptime'] as num?)?.toInt() ?? 0;

        // Calculations
        final totalMem = (memSpec['total'] as num?)?.toInt() ?? 
            (((mem['used'] as num?)?.toInt() ?? 0) + ((mem['free'] as num?)?.toInt() ?? 0));
        final usedMem = (mem['used'] as num?)?.toInt() ?? 0;
        final memPercent = totalMem > 0 ? (usedMem / totalMem) : 0.0;

        final hasBattery = battery['hasBattery'] ?? false;
        final batteryPercent = (battery['percent'] as num?)?.toInt() ?? 0;
        final isCharging = battery['isCharging'] ?? false;

        return Scaffold(
          backgroundColor: const Color(0xFF1E1E2E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E2E),
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    os['hostname'] ?? 'Workstation',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
                onPressed: () {
                  context.read<ConnectionBloc>().add(DisconnectDevice());
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8839EF), Color(0xFFBD93F9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AGENT CONNECTED',
                        style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${state.ip}:${state.port}',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildQuickStat(Icons.timer, 'Uptime', _formatUptime(uptime)),
                          _buildQuickStat(
                            Icons.battery_charging_full_rounded,
                            'Battery',
                            hasBattery ? '$batteryPercent%${isCharging ? ' (Charging)' : ''}' : 'N/A',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Live Meters Heading
                const Text(
                  'Live Telemetry',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // CPU & Memory Gauges Row
                Row(
                  children: [
                    Expanded(
                      child: _buildGaugeCard(
                        title: 'CPU LOAD',
                        value: '$cpuLoad%',
                        percent: cpuLoad / 100,
                        color: Colors.cyanAccent,
                        footer: cpuTemp > 0 ? '$cpuTemp°C Temp' : 'Normal',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildGaugeCard(
                        title: 'MEMORY',
                        value: '${(memPercent * 100).toStringAsFixed(1)}%',
                        percent: memPercent,
                        color: Colors.purpleAccent,
                        footer: '${_formatBytes(usedMem)} / ${_formatBytes(totalMem)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Quick Tools Section (User-friendly grid format, 3 items per row)
                const Text(
                  'Quick Tools',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3, // Exactly 3 items per row
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.0,
                  children: [
                    // Item 1: Apps
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.apps_rounded,
                      name: 'Apps',
                      color: Colors.cyanAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AppsScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 2: Terminal
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.terminal_rounded,
                      name: 'Terminal',
                      color: Colors.purpleAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TerminalScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 3: Files
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.folder_open_rounded,
                      name: 'Files',
                      color: Colors.amberAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FileManagerScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 4: Docker
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.directions_boat_rounded,
                      name: 'Docker',
                      color: Colors.blueAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DockerScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 5: Automations
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.auto_awesome,
                      name: 'Automations',
                      color: Colors.purpleAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AutomationScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 6: Notifications
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.notifications_active,
                      name: 'Alerts',
                      color: Colors.pinkAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationsScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 7: Clipboard
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.content_paste,
                      name: 'Clipboard',
                      color: Colors.orangeAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClipboardScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 8: Biometric Unlock
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.fingerprint_rounded,
                      name: 'Unlock',
                      color: Colors.greenAccent,
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UnlockScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Item 9: Trackpad
                    _buildToolGridCard(
                      context: context,
                      icon: Icons.touch_app_rounded,
                      name: 'Trackpad',
                      color: const Color(0xFF8839EF),
                      onTap: () async {
                        final token = await ApiClient().getToken();
                        if (token != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrackpadScreen(
                                ip: state.ip,
                                port: state.port,
                                token: token,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // System Specifications Card
                const Text(
                  'Hardware & OS Info',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28283E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildSpecRow('Operating System', '${os['distro']} (${os['release']})'),
                      const Divider(color: Colors.white10),
                      _buildSpecRow('Platform / Arch', '${os['platform']} / ${os['arch']}'),
                      const Divider(color: Colors.white10),
                      _buildSpecRow('CPU Brand', '${cpuSpec['manufacturer']} ${cpuSpec['brand']}'),
                      const Divider(color: Colors.white10),
                      _buildSpecRow('Cores', '${cpuSpec['physicalCores']} Physical / ${cpuSpec['cores']} Logic'),
                      const Divider(color: Colors.white10),
                      _buildSpecRow('Clock Speed', '${cpuSpec['speed']} GHz'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildGaugeCard({
    required String title,
    required String value,
    required double percent,
    required Color color,
    required String footer,
  }) {
    final cleanPercent = percent.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF28283E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: cleanPercent,
                  backgroundColor: Colors.white10,
                  color: color,
                  strokeWidth: 8,
                ),
              ),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            footer,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolGridCard({
    required BuildContext context,
    required IconData icon,
    required String name,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF28283E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
