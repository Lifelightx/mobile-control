import 'dart:async';
import 'package:nsd/nsd.dart';

class DiscoveredAgent {
  final String name;
  final String ip;
  final int port;

  DiscoveredAgent({
    required this.name,
    required this.ip,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredAgent &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

class DiscoveryService {
  Discovery? _discovery;
  final StreamController<List<DiscoveredAgent>> _controller =
      StreamController<List<DiscoveredAgent>>.broadcast();

  Stream<List<DiscoveredAgent>> get agentsStream => _controller.stream;

  Future<void> start() async {
    try {
      _discovery = await startDiscovery('_devcontrol._tcp');
      _discovery!.addListener(() {
        final agents = <DiscoveredAgent>[];
        for (final service in _discovery!.services) {
          final host = service.addresses?.isNotEmpty == true
              ? service.addresses!.first.address
              : service.host ?? '127.0.0.1';
          final port = service.port ?? 3000;
          final name = service.name ?? 'Developer Control Agent';
          
          agents.add(DiscoveredAgent(
            name: name,
            ip: host,
            port: port,
          ));
        }
        _controller.add(agents);
      });
    } catch (e) {
      _controller.addError(e);
    }
  }

  Future<void> stop() async {
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
      _discovery = null;
    }
  }
}
