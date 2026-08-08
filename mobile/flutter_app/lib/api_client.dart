import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  
  final _storage = const FlutterSecureStorage();

  static const String keyToken = 'jwt_token';
  static const String keyDeviceId = 'paired_device_id';
  static const String keyDeviceName = 'paired_device_name';
  static const String keyAgentIp = 'agent_ip';
  static const String keyAgentPort = 'agent_port';

  // Save credentials after successful pairing
  Future<void> saveCredentials({
    required String token,
    required String deviceId,
    required String deviceName,
    required String ip,
    required int port,
  }) async {
    await _storage.write(key: keyToken, value: token);
    await _storage.write(key: keyDeviceId, value: deviceId);
    await _storage.write(key: keyDeviceName, value: deviceName);
    await _storage.write(key: keyAgentIp, value: ip);
    await _storage.write(key: keyAgentPort, value: port.toString());
  }

  // Read saved JWT token
  Future<String?> getToken() async => await _storage.read(key: keyToken);
  
  // Read saved agent connection details
  Future<Map<String, String>?> getSavedConnection() async {
    final ip = await _storage.read(key: keyAgentIp);
    final port = await _storage.read(key: keyAgentPort);
    final deviceId = await _storage.read(key: keyDeviceId);
    
    if (ip != null && port != null && deviceId != null) {
      return {'ip': ip, 'port': port, 'deviceId': deviceId};
    }
    return null;
  }

  // Clear credentials on disconnect
  Future<void> clearCredentials() async {
    await _storage.delete(key: keyToken);
    await _storage.delete(key: keyDeviceId);
    await _storage.delete(key: keyDeviceName);
    await _storage.delete(key: keyAgentIp);
    await _storage.delete(key: keyAgentPort);
  }

  // Perform HTTP pairing request
  Future<String?> pair({
    required String ip,
    required int port,
    required String deviceId,
    required String deviceName,
    required String secret,
  }) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/auth/pair',
        data: {
          'deviceId': deviceId,
          'deviceName': deviceName,
          'secret': secret,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['token'] != null) {
          final token = data['token'] as String;
          await saveCredentials(
            token: token,
            deviceId: deviceId,
            deviceName: deviceName,
            ip: ip,
            port: port,
          );
          return token;
        }
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? e.message ?? 'Unknown error';
      throw Exception(errorMsg);
    }
    throw Exception('Failed to pair with the agent.');
  }

  // Fetch static system information
  Future<Map<String, dynamic>> fetchSystemInfo(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/system',
        options: Options(headers: {
          'Authorization': 'Bearer $token',
        }),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? e.message ?? 'Unknown error';
      throw Exception(errorMsg);
    }
    throw Exception('Failed to fetch system info.');
  }

  // Send debug/diagnostic log to agent
  Future<void> sendMobileLog(String ip, int port, String message) async {
    try {
      await _dio.post(
        'http://$ip:$port/auth/log',
        data: {
          'message': message,
        },
      );
    } catch (_) {
      // Ignore failures when posting log
    }
  }

  // Application Manager APIs
  Future<Map<String, dynamic>> fetchProcesses(String ip, int port, String token, {String sortBy = 'cpu', int limit = 100}) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/apps/processes?sortBy=$sortBy&limit=$limit',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to fetch processes');
    }
    throw Exception('Failed to fetch processes');
  }

  Future<List<dynamic>> fetchInstalledApps(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/apps/installed',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['apps'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to fetch installed apps');
    }
    return [];
  }

  Future<List<dynamic>> fetchAppPresets(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/apps/presets',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['presets'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to fetch app presets');
    }
    return [];
  }

  Future<void> launchApp(String ip, int port, String token, String command) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/apps/launch',
        data: {'command': command},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200 || response.data?['success'] != true) {
        throw Exception(response.data?['message'] ?? 'Launch failed');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? e.message ?? 'Failed to launch application');
    }
  }

  Future<void> sendWindowAction(String ip, int port, String token, {required String appName, required String action, String? command}) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/apps/window-action',
        data: {
          'appName': appName,
          'action': action,
          if (command != null) 'command': command,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200 || response.data?['success'] != true) {
        throw Exception(response.data?['message'] ?? 'Window action failed');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? e.message ?? 'Failed window action');
    }
  }

  Future<void> killProcess(String ip, int port, String token, int pid) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/apps/kill',
        data: {'pid': pid},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200 || response.data?['success'] != true) {
        throw Exception(response.data?['message'] ?? 'Kill failed');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? e.message ?? 'Failed to kill process');
    }
  }
  // File Manager APIs
  Future<List<dynamic>> listDirectory(String ip, int port, String token, String path) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/files/list',
        data: {'path': path},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['files'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to list directory');
    }
    return [];
  }

  Future<void> renameFile(String ip, int port, String token, String path, String newName) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/files/rename',
        data: {'path': path, 'newName': newName},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200 || response.data?['success'] != true) {
        throw Exception(response.data?['error'] ?? 'Rename failed');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to rename file');
    }
  }

  Future<void> deleteFile(String ip, int port, String token, String path) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/files/delete',
        data: {'path': path},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode != 200 || response.data?['success'] != true) {
        throw Exception(response.data?['error'] ?? 'Delete failed');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to delete file');
    }
  }

  // Terminal APIs
  Future<String> createTerminalSession(String ip, int port, String token, {int cols = 80, int rows = 24}) async {
    try {
      final response = await _dio.post(
        'http://$ip:$port/terminal/session',
        data: {'cols': cols, 'rows': rows},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['id'] as String;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to create terminal session');
    }
    throw Exception('Failed to create terminal session');
  }

  Future<void> killTerminalSession(String ip, int port, String token, String id) async {
    try {
      await _dio.delete(
        'http://$ip:$port/terminal/session/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {}
  }
  // Docker Manager APIs
  Future<List<dynamic>> listDockerContainers(String ip, int port, String token, {bool all = true}) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/docker/containers?all=$all',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['containers'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to list containers');
    }
    return [];
  }

  Future<void> startDockerContainer(String ip, int port, String token, String id) async {
    try {
      await _dio.post(
        'http://$ip:$port/docker/start',
        data: {'id': id},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to start container');
    }
  }

  Future<void> stopDockerContainer(String ip, int port, String token, String id) async {
    try {
      await _dio.post(
        'http://$ip:$port/docker/stop',
        data: {'id': id},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to stop container');
    }
  }

  Future<void> restartDockerContainer(String ip, int port, String token, String id) async {
    try {
      await _dio.post(
        'http://$ip:$port/docker/restart',
        data: {'id': id},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to restart container');
    }
  }

  Future<String> getDockerContainerLogs(String ip, int port, String token, String id, {int tail = 100}) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/docker/logs/$id?tail=$tail',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['logs'] as String;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to fetch logs');
    }
    return '';
  }
  // Automation Engine APIs
  Future<List<dynamic>> getAutomationRules(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/automation/rules',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['rules'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to get rules');
    }
    return [];
  }

  Future<void> addAutomationRule(String ip, int port, String token, Map<String, dynamic> rule) async {
    try {
      await _dio.post(
        'http://$ip:$port/automation/rules',
        data: rule,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to add rule');
    }
  }

  Future<void> toggleAutomationRule(String ip, int port, String token, String id, bool enabled) async {
    try {
      await _dio.put(
        'http://$ip:$port/automation/rules/$id',
        data: {'enabled': enabled},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to toggle rule');
    }
  }

  Future<void> deleteAutomationRule(String ip, int port, String token, String id) async {
    try {
      await _dio.delete(
        'http://$ip:$port/automation/rules/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {}
  }

  // Notifications API
  Future<List<dynamic>> getNotifications(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/notifications',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>)['notifications'] as List<dynamic>;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to get notifications');
    }
    return [];
  }

  Future<void> markNotificationsRead(String ip, int port, String token) async {
    try {
      await _dio.post(
        'http://$ip:$port/notifications/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {}
  }
  // Clipboard APIs
  Future<String> getClipboard(String ip, int port, String token) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/clipboard',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['text'] as String;
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to read clipboard');
    }
    return '';
  }

  Future<void> setClipboard(String ip, int port, String token, String text) async {
    try {
      await _dio.post(
        'http://$ip:$port/clipboard',
        data: {'text': text},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['error'] ?? e.message ?? 'Failed to write clipboard');
    }
  }
}

class AppLogger {
  static const int maxLogs = 100;
  static final List<String> logs = [];
  static final StreamController<List<String>> _controller = StreamController<List<String>>.broadcast();

  static Stream<List<String>> get logStream => _controller.stream;

  static void log(String message, [String? ip, int? port]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timestamp] $message';
    print(logLine);
    logs.insert(0, logLine);
    if (logs.length > maxLogs) {
      logs.removeLast();
    }
    _controller.add(List.unmodifiable(logs));

    // Also send remotely if IP and Port are provided
    if (ip != null && port != null) {
      ApiClient().sendMobileLog(ip, port, message);
    }
  }
}
