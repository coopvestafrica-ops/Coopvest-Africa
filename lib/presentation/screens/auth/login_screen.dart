import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';
import '../../../data/models/auth_models.dart';

/// Login Screen - Supabase Authentication with Biometric Support
/// 
/// Handles user login via:
/// 1. Email + Password (Supabase Auth)
/// 2. Biometric authentication (restores existing Supabase session)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  bool _isNavigating = false;

  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  bool _biometricPrompted = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _checkBiometricStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Check if biometrics are available and enabled by the user
  Future<void> _checkBiometricStatus() async {
    if (_biometricPrompted) return;
    try {
      final canAuthenticate = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometric_enabled') ?? false;
      
      // Also check if there's a valid Supabase session (for returning users)
      final authRepo = ref.read(authRepositoryProvider);
      final hasSession = await authRepo.hasValidSession();
      
      setState(() {
        _isBiometricAvailable = canAuthenticate || isDeviceSupported;
        // Only show the biometric login button when the user has explicitly
        // enabled it in Security Settings. Previously this also showed when a
        // session existed but biometrics were not enabled, which let users tap
        // through to a restored session without having configured biometrics.
        _isBiometricEnabled = _isBiometricAvailable && isEnabled;
      });
      
      // If biometric is available and user has a valid session, prompt automatically
      if (_isBiometricEnabled && hasSession && isEnabled) {
        _biometricPrompted = true;
        // Small delay to let the UI render first
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _performBiometricAuth();
        }
      }
    } catch (e) {
      logger.e('Error checking biometric status: $e');
    }
  }

  /// Perform biometric authentication
  Future<void> _performBiometricAuth() async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your Coopvest account',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        final authRepo = ref.read(authRepositoryProvider);
        
        // Restore existing Supabase session (no re-login needed)
        // Supabase persists the session, so biometric just unlocks it
        if (await authRepo.hasValidSession()) {
          try {
            final user = await authRepo.restoreSessionWithBiometric();
            await ref.read(authProvider.notifier).getCurrentUser();
            return;
          } catch (e) {
            logger.w('Session restore failed: $e');
          }
        }
        
        // No valid session exists - user must login with email/password first
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login with email first to enable biometric login'),
              backgroundColor: CoopvestColors.warning,
            ),
          );
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric error: ${e.message}'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    }
  }

  void _validateAndLogin() {
    setState(() {
      _emailError = Validators.validateEmail(_emailController.text);
      _passwordError = Validators.validatePassword(_passwordController.text);
    });
    if (_emailError == null && _passwordError == null) _performLogin();
  }

  Future<void> _performLogin() async {
    try {
      await ref.read(authProvider.notifier).login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Supabase persists the session automatically - no need to store credentials
      // Biometric authentication will work on next login using the persisted session
      
    } catch (e) {
      if (mounted) {
        final msg = e.toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('AuthException: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: CoopvestColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;
    
    // Listen for auth state changes and navigate when authenticated
    ref.listen<AuthState>(authProvider, (previous, current) {
      if (!_isNavigating && 
          current.status == AuthStatus.authenticated && 
          previous?.status != AuthStatus.authenticated) {
        _isNavigating = true;
        Navigator.of(context).pushReplacementNamed('/home');
      }
    });

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Log in to your Coopvest account',
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 32),

              // Email field
              AppTextField(
                label: 'Email or Phone Number',
                hint: 'Enter your email or phone',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
              ),
              const SizedBox(height: 20),

              // Password field
              AppTextField(
                label: 'Password',
                hint: 'Enter your password',
                controller: _passwordController,
                obscureText: _obscurePassword,
                errorText: _passwordError,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: context.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),

              // Forgot password link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/forgot-password'),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: CoopvestColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Login button
              PrimaryButton(
                label: 'Log In',
                onPressed: _validateAndLogin,
                isLoading: isLoading,
                width: double.infinity,
              ),
              
              // Biometric login button — only shown when biometrics are enabled and available
              if (_isBiometricEnabled) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: context.dividerColor)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(color: context.textSecondary, fontSize: 14),
                      ),
                    ),
                    Expanded(child: Divider(color: context.dividerColor)),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _performBiometricAuth,
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: CoopvestColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.fingerprint,
                            size: 48,
                            color: CoopvestColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tap to use biometrics',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 32),

              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: context.textSecondary),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/register'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: CoopvestColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // Trust & security footer
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A6B).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1B3A6B).withOpacity(0.10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _TrustBadgeItem(
                      icon: Icons.lock_outline_rounded,
                      label: 'SSL Encrypted',
                      color: const Color(0xFF1B3A6B),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: const Color(0xFF1B3A6B).withOpacity(0.15),
                    ),
                    _TrustBadgeItem(
                      icon: Icons.verified_user_outlined,
                      label: 'Secure Login',
                      color: const Color(0xFF2E7D32),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: const Color(0xFF1B3A6B).withOpacity(0.15),
                    ),
                    _TrustBadgeItem(
                      icon: Icons.shield_outlined,
                      label: 'Data Protected',
                      color: const Color(0xFF1B3A6B),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustBadgeItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TrustBadgeItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.withOpacity(0.8),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
