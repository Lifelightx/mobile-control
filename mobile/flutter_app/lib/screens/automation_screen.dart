import 'dart:convert';
import 'package:flutter/material.dart';
import '../api_client.dart';

class AutomationScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const AutomationScreen({
    Key? key,
    required this.ip,
    required this.port,
    required this.token,
  }) : super(key: key);

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _rules = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    try {
      final rules = await _apiClient.getAutomationRules(widget.ip, widget.port, widget.token);
      if (mounted) {
        setState(() {
          _rules = rules;
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

  Future<void> _toggleRule(String id, bool enabled) async {
    try {
      await _apiClient.toggleAutomationRule(widget.ip, widget.port, widget.token, id, enabled);
      _loadRules();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error toggling rule: $e')));
    }
  }

  Future<void> _deleteRule(String id) async {
    try {
      await _apiClient.deleteAutomationRule(widget.ip, widget.port, widget.token, id);
      _loadRules();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting rule: $e')));
    }
  }

  Future<void> _addRuleDialog() async {
    final nameCtrl = TextEditingController();
    String triggerType = 'cpu_threshold';
    final triggerConfigCtrl = TextEditingController(text: '{"threshold": 90}');
    String actionType = 'notify';
    final actionConfigCtrl = TextEditingController(text: '{"message": "CPU is high!"}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Add Automation', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Rule Name', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: triggerType,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'cpu_threshold', child: Text('CPU Threshold')),
                      DropdownMenuItem(value: 'ram_threshold', child: Text('RAM Threshold')),
                      DropdownMenuItem(value: 'docker_stopped', child: Text('Docker Stopped')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        triggerType = val!;
                        if (triggerType == 'docker_stopped') {
                          triggerConfigCtrl.text = '{"containerName": "nginx"}';
                        }
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Trigger', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                  TextField(
                    controller: triggerConfigCtrl,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    decoration: const InputDecoration(labelText: 'Trigger Config (JSON)', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: actionType,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'notify', child: Text('Send Notification')),
                      DropdownMenuItem(value: 'execute_command', child: Text('Execute Command')),
                      DropdownMenuItem(value: 'restart_docker', child: Text('Restart Container')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        actionType = val!;
                        if (actionType == 'execute_command') {
                          actionConfigCtrl.text = '{"command": "echo Hello"}';
                        } else if (actionType == 'restart_docker') {
                          actionConfigCtrl.text = '{"containerId": "..."}';
                        }
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Action', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                  TextField(
                    controller: actionConfigCtrl,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    decoration: const InputDecoration(labelText: 'Action Config (JSON)', labelStyle: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _apiClient.addAutomationRule(widget.ip, widget.port, widget.token, {
                      'name': nameCtrl.text,
                      'trigger_type': triggerType,
                      'trigger_config': triggerConfigCtrl.text,
                      'action_type': actionType,
                      'action_config': actionConfigCtrl.text,
                      'enabled': 1,
                    });
                    if (mounted) Navigator.pop(ctx);
                    _loadRules();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
                child: const Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Automations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.purpleAccent,
        onPressed: _addRuleDialog,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
            : _rules.isEmpty
                ? const Center(child: Text('No automations created yet.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rules.length,
                    itemBuilder: (ctx, idx) {
                      final rule = _rules[idx];
                      final isEnabled = rule['enabled'] == 1;

                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(rule['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text('IF ${rule['trigger_type']} THEN ${rule['action_type']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: isEnabled,
                                activeColor: Colors.purpleAccent,
                                onChanged: (val) => _toggleRule(rule['id'], val),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _deleteRule(rule['id']),
                              ),
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
