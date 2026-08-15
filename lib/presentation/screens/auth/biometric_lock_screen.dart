import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/services/security_service.dart';
import '../../../core/utils/utils.dart';

/// Full-screen lock shown when the app is unlocked (cold start or resume) but
/// biometric authentication is enabled and has not yet been satisfied.
///
/// The user can retry the biometric prompt or fall back to signing in with
/// their password (which signs them out and returns to the login screen).
class BiometricLockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback onUsePassword;

  const BiometricLockScreen({
    Key? key,
    required this.onUnlocked,
    required this.onUsePassword,
  }) : super(key: key);

  @override
  ConsumerState<BiometricLockScreen> createState() =>
      _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _isAuthenticating = false;

  Future<void> _tryBiometric() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);
    try {
      final ok = await SecurityService().authenticate();
      if (ok && mounted) {
        widget.onUnlocked();
      }
    } catch (e) {
      logger.e('Biometric lock auth error: $e');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CoopvestColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    size: 72,
                    color: CoopvestColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Biometric Login Required',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate with your fingerprint or face to unlock your Coopvest account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAuthenticating ? null : _tryBiometric,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CoopvestColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isAuthenticating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.fingerprint),
                    label: Text(_isAuthenticating
                        ? 'Authenticating...'
                        : 'Unlock with Biometrics'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onUsePassword,
                  child: Text(
                    'Sign in with password instead',
                    style: TextStyle(color: context.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
