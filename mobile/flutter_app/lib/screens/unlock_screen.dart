import 'package:flutter/material.dart';
import '../biometric_unlock_service.dart';

class UnlockScreen extends StatefulWidget {
  final String ip;
  final int port;
  final String token;

  const UnlockScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.token,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with SingleTickerProviderStateMixin {
  final _service = BiometricUnlockService();
  late AnimationController _lockAnimController;
  late Animation<double> _scaleAnim;

  bool _isLoading = false;
  bool _biometricAvailable = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _lockAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _lockAnimController, curve: Curves.elasticOut),
    );
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await _service.isAvailable();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  Future<void> _triggerUnlock() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    final result = await _service.unlock(widget.ip, widget.port, widget.token);

    if (result.success) {
      _lockAnimController.forward().then((_) => _lockAnimController.reverse());
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = result.message;
        _isSuccess = result.success;
      });
    }
  }

  @override
  void dispose() {
    _lockAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        title: const Text(
          'Biometric Unlock',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Lock icon with animation
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isSuccess
                        ? Colors.greenAccent.withOpacity(0.15)
                        : const Color(0xFF28283E),
                    border: Border.all(
                      color: _isSuccess
                          ? Colors.greenAccent
                          : const Color(0xFF8839EF),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isSuccess
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded,
                    size: 56,
                    color: _isSuccess
                        ? Colors.greenAccent
                        : const Color(0xFF8839EF),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Laptop Unlock',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Authenticate with your fingerprint or PIN\nto unlock your laptop remotely.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Status message
              if (_statusMessage != null) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? Colors.greenAccent.withOpacity(0.1)
                        : Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSuccess
                          ? Colors.greenAccent.withOpacity(0.4)
                          : Colors.redAccent.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSuccess
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Unlock button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8839EF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF28283E),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      (_isLoading || !_biometricAvailable) ? null : _triggerUnlock,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.fingerprint_rounded, size: 24),
                  label: Text(
                    _isLoading
                        ? 'Unlocking...'
                        : _biometricAvailable
                            ? 'Authenticate & Unlock'
                            : 'Biometrics Unavailable',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Security note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your fingerprint data never leaves this device. Only a cryptographic signature is sent to verify your identity.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
