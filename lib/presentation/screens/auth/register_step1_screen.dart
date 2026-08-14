import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../data/models/auth_models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';

/// Registration Step 1 - Basic Account Creation
class RegisterStep1Screen extends ConsumerStatefulWidget {
  const RegisterStep1Screen({Key? key}) : super(key: key);

  @override
  ConsumerState<RegisterStep1Screen> createState() =>
      _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends ConsumerState<RegisterStep1Screen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _isLoading = false;

  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  double _passwordStrength = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _passwordController.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updatePasswordStrength() {
    final password = _passwordController.text;
    double strength = 0;
    if (password.length >= 8) strength += 0.25;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.25;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.25;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.25;
    setState(() => _passwordStrength = strength);
  }

  Future<void> _validateAndContinue() async {
    setState(() {
      _nameError = Validators.validateName(_nameController.text);
      _phoneError = Validators.validatePhone(_phoneController.text);
      _emailError = Validators.validateEmail(_emailController.text);
      _passwordError = Validators.validatePassword(_passwordController.text);
      _confirmPasswordError =
          _passwordController.text != _confirmPasswordController.text
              ? 'Passwords do not match'
              : null;
    });

    if (_nameError != null ||
        _phoneError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) return;

    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please accept Terms & Privacy Policy'),
          backgroundColor: CoopvestColors.error));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).register(
            email: _emailController.text.trim().toLowerCase(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );

      if (mounted) {
        final regArgs = {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
        };

        // If email is already confirmed (autoconfirm enabled), skip
        // the verification screen and go straight to onboarding.
        final sbUser = sb.Supabase.instance.client.auth.currentUser;
        if (sbUser?.emailConfirmedAt != null) {
          Navigator.of(context).pushNamed('/register-step3', arguments: regArgs);
        } else {
          Navigator.of(context).pushNamed('/register-step2', arguments: regArgs);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('AuthException: ', '');

        if (msg.contains('already exists') ||
            msg.contains('email-already-in-use') ||
            msg.contains('already registered')) {
          await _handleExistingAccount();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg), backgroundColor: CoopvestColors.error));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Handle the case where a Supabase account already exists for this email.
  Future<void> _handleExistingAccount() async {
    try {
      // Try to sign in with the provided credentials
      final result = await sb.Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );

      final sbUser = result.user;
      if (sbUser != null) {
        if (sbUser.emailConfirmedAt == null) {
          // Account exists but email not verified — resend and go to step 2
          try {
            await sb.Supabase.instance.client.auth.resend(
              type: sb.OtpType.signup,
              email: sbUser.email!,
            );
          } catch (_) {
            // Continue even if resend fails
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Account found! Please verify your email to continue.'),
              backgroundColor: CoopvestColors.warning,
            ));
            Navigator.of(context).pushNamed('/register-step2', arguments: {
              'name': _nameController.text.trim(),
              'phone': _phoneController.text.trim(),
              'email': _emailController.text.trim().toLowerCase(),
            });
          }
        } else {
          // Account verified — redirect to login
          await sb.Supabase.instance.client.auth.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Account already exists and is verified. Please log in instead.'),
              backgroundColor: CoopvestColors.info,
            ));
            Navigator.of(context).pushReplacementNamed('/login');
          }
        }
      }
    } on sb.AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('wrong') || msg.contains('credentials')) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Account Exists'),
              content: const Text(
                'An account with this email already exists. Would you like to log in or reset your password?',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushReplacementNamed('/login');
                  },
                  child: const Text('Go to Login'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/forgot-password',
                        arguments:
                            _emailController.text.trim().toLowerCase());
                  },
                  child: const Text('Reset Password'),
                ),
              ],
            ),
          );
        }
      } else if (msg.contains('rate limit') || msg.contains('too many')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Too many attempts. Please wait a moment and try again.'),
            backgroundColor: CoopvestColors.error,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'An account already exists with this email. Please try logging in.'),
            backgroundColor: CoopvestColors.error,
          ));
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'An account already exists with this email. Please try logging in.'),
          backgroundColor: CoopvestColors.error,
        ));
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () {
            // The Create Account screen can be reached two ways:
            //   1. From Welcome "Create Account" via pushReplacementNamed('/register')
            //      — this leaves nothing to pop back to (empty nav stack), which
            //        previously produced a blank screen. In that case route to /welcome.
            //   2. From Login "Sign Up" via pushNamed('/register') — safe to pop.
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/welcome');
            }
          },
        ),
        title: Text('Create Account',
            style: TextStyle(
                color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: CoopvestColors.primary, shape: BoxShape.circle),
                    child: const Center(
                        child: Text('1',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Container(height: 2, color: context.dividerColor)),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: context.dividerColor, shape: BoxShape.circle),
                    child: Center(
                        child: Text('2',
                            style: TextStyle(
                                color: context.textSecondary,
                                fontWeight: FontWeight.bold))),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text('Basic Account Information',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary)),
              const SizedBox(height: 8),
              Text('Enter your basic information to get started',
                  style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 24),
              AppTextField(
                  label: 'Full Name',
                  hint: 'As per your official ID',
                  controller: _nameController,
                  errorText: _nameError),
              const SizedBox(height: 20),
              AppTextField(
                  label: 'Phone Number',
                  hint: '+234 801 234 5678',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  errorText: _phoneError),
              const SizedBox(height: 20),
              AppTextField(
                  label: 'Email Address',
                  hint: 'your.email@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _emailError),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Password',
                hint: 'Enter your password',
                controller: _passwordController,
                obscureText: _obscurePassword,
                errorText: _passwordError,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: context.textSecondary),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              if (_passwordController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _passwordStrength,
                  backgroundColor: context.dividerColor,
                  color: _passwordStrength < 0.5
                      ? CoopvestColors.error
                      : _passwordStrength < 0.75
                          ? Colors.orange
                          : CoopvestColors.success,
                ),
                const SizedBox(height: 4),
                Text(
                  _passwordStrength < 0.25
                      ? 'Very Weak'
                      : _passwordStrength < 0.5
                          ? 'Weak'
                          : _passwordStrength < 0.75
                              ? 'Medium'
                              : 'Strong',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
              const SizedBox(height: 20),
              AppTextField(
                label: 'Confirm Password',
                hint: 'Re-enter your password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                errorText: _confirmPasswordError,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: context.textSecondary),
                  onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Checkbox(
                      value: _agreeToTerms,
                      onChanged: (v) =>
                          setState(() => _agreeToTerms = v ?? false),
                      activeColor: CoopvestColors.primary),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        text: 'I agree to the ',
                        style: TextStyle(color: context.textSecondary),
                        children: [
                          TextSpan(
                              text: 'Terms of Service',
                              style: const TextStyle(
                                  color: CoopvestColors.primary,
                                  fontWeight: FontWeight.bold)),
                          const TextSpan(text: ' and '),
                          TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                  color: CoopvestColors.primary,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                  label: 'Continue',
                  onPressed: _validateAndContinue,
                  isLoading: _isLoading,
                  width: double.infinity),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
