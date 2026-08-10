import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_client.dart';
import '../hub_client.dart';
import '../discovery_service.dart';

// --- Events ---
abstract class ConnectionEvent {}

class StartDiscovery extends ConnectionEvent {}

class StopDiscovery extends ConnectionEvent {}

class AgentsUpdated extends ConnectionEvent {
  final List<DiscoveredAgent> agents;
  AgentsUpdated(this.agents);
}

class PairDevice extends ConnectionEvent {
  final DiscoveredAgent agent;
  final String secret;
  PairDevice({required this.agent, required this.secret});
}

class AutoConnect extends ConnectionEvent {}

class UpdateMetrics extends ConnectionEvent {
  final Map<String, dynamic> metrics;
  UpdateMetrics(this.metrics);
}

class DisconnectDevice extends ConnectionEvent {}

class WebSocketDisconnected extends ConnectionEvent {
  final String message;
  WebSocketDisconnected(this.message);
}

// --- States ---
abstract class HubConnectionState {}

class ConnectionInitial extends HubConnectionState {}

class DiscoveryLoading extends HubConnectionState {}

class DiscoverySuccess extends HubConnectionState {
  final List<DiscoveredAgent> agents;
  DiscoverySuccess(this.agents);
}

class PairingInProgress extends HubConnectionState {}

class PairingSuccess extends HubConnectionState {
  final String token;
  PairingSuccess(this.token);
}

class DashboardActive extends HubConnectionState {
  final String ip;
  final int port;
  final String deviceName;
  final String activeTransport;
  final Map<String, dynamic> staticInfo;
  final Map<String, dynamic> liveMetrics;

  DashboardActive({
    required this.ip,
    required this.port,
    required this.deviceName,
    required this.activeTransport,
    required this.staticInfo,
    required this.liveMetrics,
  });

  DashboardActive copyWith({
    Map<String, dynamic>? liveMetrics,
  }) {
    return DashboardActive(
      ip: ip,
      port: port,
      deviceName: deviceName,
      activeTransport: activeTransport,
      staticInfo: staticInfo,
      liveMetrics: liveMetrics ?? this.liveMetrics,
    );
  }
}

class ConnectionFailure extends HubConnectionState {
  final String message;
  ConnectionFailure(this.message);
}

// --- BLoC Implementation ---
class ConnectionBloc extends Bloc<ConnectionEvent, HubConnectionState> {
  final ApiClient _apiClient = ApiClient();
  final HubClient _wsClient = HubClient();
  final DiscoveryService _discoveryService = DiscoveryService();
  final _storage = const FlutterSecureStorage();

  StreamSubscription? _discoverySubscription;
  StreamSubscription? _metricsSubscription;
  // Guard flag: true while _connectWs is in progress. Prevents
  // _onWebSocketDisconnected from calling disconnect() mid-handshake,
  // which would nullify _channel and cause a Null check NPE.
  bool _isConnecting = false;

  ConnectionBloc() : super(ConnectionInitial()) {
    on<StartDiscovery>(_onStartDiscovery);
    on<StopDiscovery>(_onStopDiscovery);
    on<AgentsUpdated>(_onAgentsUpdated);
    on<PairDevice>(_onPairDevice);
    on<AutoConnect>(_onAutoConnect);
    on<UpdateMetrics>(_onUpdateMetrics);
    on<DisconnectDevice>(_onDisconnectDevice);
    on<WebSocketDisconnected>(_onWebSocketDisconnected);
  }

  Future<void> _onStartDiscovery(StartDiscovery event, Emitter<HubConnectionState> emit) async {
    emit(DiscoveryLoading());
    await _discoveryService.stop(); // Stop any leftover sessions
    _discoverySubscription?.cancel();

    _discoverySubscription = _discoveryService.agentsStream.listen(
      (agents) => add(AgentsUpdated(agents)),
      // Do NOT dispatch DisconnectDevice on mDNS errors — that calls
      // _wsClient.disconnect() which kills the WebSocket mid-handshake.
      // Simply restart scanning instead.
      onError: (err) => add(StartDiscovery()),
    );

    await _discoveryService.start();
  }

  Future<void> _onStopDiscovery(StopDiscovery event, Emitter<HubConnectionState> emit) async {
    await _discoveryService.stop();
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
  }

  void _onAgentsUpdated(AgentsUpdated event, Emitter<HubConnectionState> emit) {
    if (state is DiscoveryLoading || state is DiscoverySuccess) {
      emit(DiscoverySuccess(event.agents));
    }
  }

  Future<void> _onPairDevice(PairDevice event, Emitter<HubConnectionState> emit) async {
    emit(PairingInProgress());
    await _discoveryService.stop(); // Stop searching
    _discoverySubscription?.cancel();

    try {
      // Get or create unique device ID for the mobile app
      String? deviceId = await _storage.read(key: 'device_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await _storage.write(key: 'device_id', value: deviceId);
      }

      // Mock or set a device name
      const deviceName = 'Testing Mobile Client';

      // Perform HTTP pair request
      String? token;

      // If IP is 0.0.0.0, perform Bluetooth-Native pairing
      if (event.agent.ip == '0.0.0.0') {
        token = await _wsClient.pairViaBluetooth(deviceId, deviceName, event.secret);
      } else {
        token = await _apiClient.pair(
          ip: event.agent.ip,
          port: event.agent.port,
          deviceId: deviceId,
          deviceName: deviceName,
          secret: event.secret,
        );
      }

      if (token != null) {
        await _storage.write(key: 'token', value: token);
        await _storage.write(key: 'ip', value: event.agent.ip == '0.0.0.0' ? '127.0.0.1' : event.agent.ip); // Dummy IP to force fallback logic
        await _storage.write(key: 'port', value: event.agent.port.toString());

        // Connect WebSocket/Bluetooth — this now returns system info!
        final systemInfo = await _connectWs(event.agent.ip == '0.0.0.0' ? '127.0.0.1' : event.agent.ip, event.agent.port, token);

        emit(DashboardActive(
          ip: event.agent.ip,
          port: event.agent.port,
          deviceName: deviceName,
          activeTransport: _wsClient.activeTransport?.name.toUpperCase() ?? 'UNKNOWN',
          staticInfo: systemInfo,
          liveMetrics: systemInfo, // initial metrics
        ));
      } else {
        emit(ConnectionFailure('Pairing failed: Token was null'));
      }
    } catch (e) {
      emit(ConnectionFailure(e.toString()));
    }
  }

  Future<void> _onAutoConnect(AutoConnect event, Emitter<HubConnectionState> emit) async {
    try {
      final saved = await _apiClient.getSavedConnection();
      final token = await _apiClient.getToken();
      
      if (saved != null && token != null) {
        emit(PairingInProgress()); // show loading
        final ip = saved['ip']!;
        final port = int.parse(saved['port']!);
        
        // Connect Transport (Wi-Fi or Bluetooth) — this now returns system info!
        final systemInfo = await _connectWs(ip, port, token);

        emit(DashboardActive(
          ip: ip,
          port: port,
          deviceName: 'Antigravity Mobile Client',
          activeTransport: _wsClient.activeTransport?.name.toUpperCase() ?? 'UNKNOWN',
          staticInfo: systemInfo,
          liveMetrics: systemInfo,
        ));
      } else {
        add(StartDiscovery()); // start discovery if no saved connection
      }
    } catch (e) {
      // Clear invalid credentials and look for agents
      await _apiClient.clearCredentials();
      add(StartDiscovery());
    }
  }

  void _onUpdateMetrics(UpdateMetrics event, Emitter<HubConnectionState> emit) {
    if (state is DashboardActive) {
      emit((state as DashboardActive).copyWith(liveMetrics: event.metrics));
    }
  }

  Future<void> _onDisconnectDevice(DisconnectDevice event, Emitter<HubConnectionState> emit) async {
    // Do not tear down the WebSocket if a handshake is in progress.
    if (_isConnecting) {
      AppLogger.log('[Bloc] DisconnectDevice suppressed — handshake in progress.');
      return;
    }
    _wsClient.disconnect();
    _metricsSubscription?.cancel();
    _metricsSubscription = null;
    
    await _discoveryService.stop();
    _discoverySubscription?.cancel();
    _discoverySubscription = null;

    await _apiClient.clearCredentials();
    emit(ConnectionInitial());
    add(StartDiscovery());
  }

  Future<Map<String, dynamic>> _connectWs(String ip, int port, String token) async {
    // Set guard FIRST before any await — the await cancel() suspension
    // point would otherwise allow WebSocketDisconnected to run disconnect()
    // and null out _channel before we even start the handshake.
    _isConnecting = true;
    await _metricsSubscription?.cancel();
    _metricsSubscription = null;
    try {
      AppLogger.log('[Bloc] WS Connection Initiating', ip, port);
      final systemInfo = await _wsClient.connect(ip, port, token);
      AppLogger.log('[Bloc] WS Handshake complete, subscribing to metric stream.', ip, port);

      _metricsSubscription = _wsClient.metricStream.listen(
        (metrics) => add(UpdateMetrics(metrics)),
        onError: (err) {
          AppLogger.log('[Bloc] WS Stream Error: $err', ip, port);
          add(WebSocketDisconnected('WebSocket error: $err'));
        },
        onDone: () {
          final code = _wsClient.closeCode;
          final reason = _wsClient.closeReason;
          AppLogger.log('[Bloc] WS Stream onDone. Code: $code, Reason: $reason', ip, port);
          add(WebSocketDisconnected('WebSocket connection closed (Code: $code, Reason: $reason).'));
        },
      );
      
      return systemInfo;
    } finally {
      _isConnecting = false;
    }
  }

  void _onWebSocketDisconnected(WebSocketDisconnected event, Emitter<HubConnectionState> emit) {
    // If we are mid-handshake, the disconnect will be handled naturally
    // by the connect() guard. Acting here would nullify _channel and cause
    // a Null check NPE in connect()'s stream.listen() call.
    if (_isConnecting) {
      AppLogger.log('[Bloc] WebSocketDisconnected suppressed during active handshake.');
      return;
    }
    if (state is DashboardActive) {
      final active = state as DashboardActive;
      AppLogger.log('[Bloc] WebSocketDisconnected event processed: ${event.message}', active.ip, active.port);
    }
    _wsClient.disconnect();
    _metricsSubscription?.cancel();
    _metricsSubscription = null;
    emit(ConnectionFailure(event.message));
  }

  @override
  Future<void> close() {
    _wsClient.disconnect();
    _metricsSubscription?.cancel();
    _discoveryService.stop();
    _discoverySubscription?.cancel();
    return super.close();
  }
}
