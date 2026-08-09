import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class BiometricUnlockService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  /// Check if biometric authentication is available on this device
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Authenticate with biometrics and send unlock request to agent
  Future<UnlockResult> unlock(String ip, int port, String token) async {
    // Step 1: Biometric authentication
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock your laptop',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Unlock Laptop',
            cancelButton: 'Cancel',
          ),
        ],
      );
      if (!authenticated) {
        return UnlockResult(success: false, message: 'Biometric authentication failed or cancelled.');
      }
    } catch (e) {
      return UnlockResult(success: false, message: 'Biometric error: $e');
    }

    // Step 2: Build signed unlock request
    final deviceId = await _storage.read(key: 'device_id') ?? 'unknown';
    final nonce = _generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = '$deviceId:$nonce:$timestamp';
    final signature = _sign(payload, token);

    // Step 3: Send to agent
    try {
      final response = await http.post(
        Uri.parse('http://$ip:$port/auth/unlock'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'deviceId': deviceId,
          'timestamp': timestamp,
          'nonce': nonce,
          'signature': signature,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          return UnlockResult(success: true, message: 'Laptop unlocked successfully!');
        }
      }
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      return UnlockResult(success: false, message: error);
    } catch (e) {
      return UnlockResult(success: false, message: 'Could not reach agent: $e');
    }
  }

  String _generateNonce() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// HMAC-SHA256 signature using JWT as the shared secret key
  String _sign(String payload, String key) {
    final hmac = Hmac(sha256, utf8.encode(key));
    return hmac.convert(utf8.encode(payload)).toString();
  }
}

class UnlockResult {
  final bool success;
  final String message;
  UnlockResult({required this.success, required this.message});
}
