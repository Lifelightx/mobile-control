import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_links/app_links.dart';
import 'bloc/connection_bloc.dart';
import 'screens/pairing_screen.dart';
import 'screens/dashboard_screen.dart';
import 'discovery_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const ControlHubApp());
}

class ControlHubApp extends StatefulWidget {
  const ControlHubApp({super.key});

  @override
  State<ControlHubApp> createState() => _ControlHubAppState();
}

class _ControlHubAppState extends State<ControlHubApp> {
  late final ConnectionBloc _connectionBloc;

  @override
  void initState() {
    super.initState();
    _connectionBloc = ConnectionBloc()..add(AutoConnect());
  }

  @override
  void dispose() {
    _connectionBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _connectionBloc,
      child: MaterialApp(
        title: 'Developer Control Hub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8839EF),
            secondary: Color(0xFFBD93F9),
            surface: Color(0xFF28283E),
            error: Color(0xFFD20F39),
          ),
          scaffoldBackgroundColor: const Color(0xFF1E1E2E),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E2E),
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        home: const AppContentGate(),
      ),
    );
  }
}

class AppContentGate extends StatefulWidget {
  const AppContentGate({super.key});

  @override
  State<AppContentGate> createState() => _AppContentGateState();
}

class _AppContentGateState extends State<AppContentGate> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinking() async {
    // 1. Handle link when app is launched from a cold state
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (e) {
      // Failed to parse link on start
    }

    // 2. Handle link when app is running in the background/foreground
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleIncomingUri(uri);
      },
      onError: (err) {
        // Deep linking stream error
      },
    );
  }

  void _handleIncomingUri(Uri uri) {
    try {
      if (uri.scheme == 'devcontrol' && uri.host == 'pair') {
        final ip = uri.queryParameters['ip'];
        final portStr = uri.queryParameters['port'];
        final secret = uri.queryParameters['secret'];

        if (ip != null && portStr != null && secret != null) {
          final port = int.tryParse(portStr) ?? 3000;
          context.read<ConnectionBloc>().add(PairDevice(
            agent: DiscoveredAgent(name: 'Setup Deep Link', ip: ip, port: port),
            secret: secret,
          ));
        }
      }
    } catch (e) {
      // Ignore invalid link formats
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConnectionBloc, HubConnectionState>(
      listener: (context, state) {
        if (state is ConnectionFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 30),
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is DashboardActive) {
          return const DashboardScreen();
        }
        return const PairingScreen();
      },
    );
  }
}
