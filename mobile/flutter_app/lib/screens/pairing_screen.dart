import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/connection_bloc.dart';
import '../discovery_service.dart';
import '../api_client.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '3000');
  final TextEditingController _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _showPairingDialog(BuildContext context, DiscoveredAgent agent) {
    _secretController.clear();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Pair with ${agent.name}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IP: ${agent.ip}:${agent.port}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secretController,
              decoration: InputDecoration(
                hintText: 'Enter 8-character Pairing Code',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF28283E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white30)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8839EF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final secret = _secretController.text.trim();
              if (secret.isNotEmpty) {
                Navigator.pop(dialogContext);
                context.read<ConnectionBloc>().add(PairDevice(
                  agent: agent,
                  secret: secret,
                ));
              }
            },
            child: const Text('Pair Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showManualConnectDialog(BuildContext context) {
    _ipController.clear();
    _portController.text = '3000';
    _secretController.clear();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Manual Setup',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  hintText: 'Agent IP Address (e.g., 192.168.1.10)',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF28283E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  hintText: 'Port (default: 3000)',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF28283E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _secretController,
                decoration: InputDecoration(
                  hintText: 'Pairing Code',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF28283E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ),
        actions: [

          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white30)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8839EF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final ip = _ipController.text.trim();
              final portStr = _portController.text.trim();
              final secret = _secretController.text.trim();
              if (ip.isNotEmpty && portStr.isNotEmpty && secret.isNotEmpty) {
                final port = int.tryParse(portStr) ?? 3000;
                Navigator.pop(dialogContext);
                context.read<ConnectionBloc>().add(PairDevice(
                  agent: DiscoveredAgent(name: 'Manual Agent', ip: ip, port: port),
                  secret: secret,
                ));
              }
            },
            child: const Text('Connect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Header
              const Text(
                'Control Hub',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Pair with a desktop agent on your LAN',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Discovery Pulse Radar Area
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF8839EF).withAlpha(((1 - _pulseController.value) * 255).toInt()),
                            border: Border.all(
                              color: const Color(0xFF8839EF).withAlpha((0.5 * 255).toInt()),
                              width: 2,
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF28283E),
                      ),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Dynamic Status Info
              BlocBuilder<ConnectionBloc, HubConnectionState>(
                builder: (context, state) {
                  if (state is ConnectionFailure) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Text(
                            'Connection Failed. Please try again.',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8839EF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            context.read<ConnectionBloc>().add(StartDiscovery());
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry Scan'),
                        ),
                      ],
                    );
                  }
                  if (state is DiscoveryLoading) {
                    return const Text(
                      'Scanning local network...',
                      style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    );
                  }
                  if (state is DiscoverySuccess && state.agents.isNotEmpty) {
                    return Text(
                      'Found ${state.agents.length} agent(s)',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    );
                  }
                  return const Text(
                    'Ensure Desktop Agent is running',
                    style: TextStyle(color: Colors.white30),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 20),

              // Discovered Agents List
              Expanded(
                child: BlocBuilder<ConnectionBloc, HubConnectionState>(
                  builder: (context, state) {
                    if (state is PairingInProgress) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF8839EF)),
                      );
                    }
                    if (state is DiscoverySuccess) {
                      final agents = state.agents;
                      if (agents.isEmpty) {
                        return const Center(
                          child: Text(
                            'No agents discovered yet.',
                            style: TextStyle(color: Colors.white30),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: agents.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final agent = agents[index];
                          return Card(
                            color: const Color(0xFF28283E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.laptop_chromebook, color: Color(0xFF8839EF)),
                              title: Text(
                                agent.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${agent.ip}:${agent.port}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
                              onTap: () => _showPairingDialog(context, agent),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),

              const SizedBox(height: 16),
              // Manual configuration option
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF28283E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _showManualConnectDialog(context),
                icon: const Icon(Icons.settings_ethernet_rounded),
                label: const Text('Configure Manually'),
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
