import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/utils.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';

/// Forgot Password Screen — Step 1: enter email to receive OTP reset code.
/// After submission a success view appears with a 5-second countdown that
/// auto-redirects the user to the OTP entry screen.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  late TextEditingController _emailController;
  String? _emailError;
  bool _isLoading = false;
  bool _emailSent = false;
  String _sentEmail = '';

  // Countdown
  static const int _countdownSeconds = 5;
  int _secondsLeft = _countdownSeconds;
  Timer? _countdownTimer;

  // Success animation controllers
  late AnimationController _checkController;
  late AnimationController _contentController;
  late Animation<double> _checkScale;
  late Animation<double> _checkOpacity;
  late Animation<Offset> _contentSlide;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );
    _checkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _checkController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _countdownTimer?.cancel();
    _checkController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSubmit() async {
    setState(() => _emailError = Validators.validateEmail(_emailController.text));
    if (_emailError != null) return;

    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/auth/request-password-reset', data: {
        'email': _emailController.text.trim().toLowerCase(),
        'type': 'mobile',
      });
    } catch (e) {
      // A transport/network failure (or 5xx) means no email was sent. Do NOT
      // mask it as success — otherwise the user is sent to the OTP screen and
      // verifyOtp always fails with "Token has expired or is invalid" because
      // no code was ever generated. (The backend still returns 200 for an
      // unregistered email to prevent enumeration, so this only fires on real
      // failures, which is exactly when the user should retry.)
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send reset code. Check your connection and try again.'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _emailSent = true;
        _sentEmail = _emailController.text.trim().toLowerCase();
        _secondsLeft = _countdownSeconds;
      });
      _startSuccessAnimation();
    }
  }

  void _startSuccessAnimation() async {
    await _checkController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _contentController.forward();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _goToOtp();
      }
    });
  }

  void _goToOtp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      '/reset-password-otp',
      arguments: {'email': _sentEmail},
    );
  }

  void _goBackToLogin() {
    _countdownTimer?.cancel();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Forgot Password',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _emailSent ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  // ── Form view ──────────────────────────────────────────────────────────────

  Widget _buildFormView() {
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: CoopvestColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset,
              size: 40,
              color: CoopvestColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Reset Your Password',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your registered email address. We\'ll send you a 6-digit code to reset your password.',
            style: TextStyle(color: context.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          AppTextField(
            label: 'Email Address',
            hint: 'Enter your registered email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            errorText: _emailError,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Send Reset Code',
            onPressed: _validateAndSubmit,
            isLoading: _isLoading,
            width: double.infinity,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Back to Login',
                style: TextStyle(color: CoopvestColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Success view ───────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return SingleChildScrollView(
      key: const ValueKey('success'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),

          // Animated checkmark circle
          AnimatedBuilder(
            animation: _checkController,
            builder: (context, _) {
              return Opacity(
                opacity: _checkOpacity.value,
                child: Transform.scale(
                  scale: _checkScale.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E7D32),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Slide-up content
          AnimatedBuilder(
            animation: _contentController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _contentFade,
                child: SlideTransition(
                  position: _contentSlide,
                  child: child,
                ),
              );
            },
            child: Column(
              children: [
                Text(
                  'Email Sent!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(text: 'We sent a 6-digit reset code to\n'),
                      TextSpan(
                        text: _sentEmail,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: CoopvestColors.primary,
                        ),
                      ),
                      const TextSpan(
                        text: '\n\nCheck your inbox (and spam folder)',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Countdown ring + text
                _CountdownRing(
                  secondsLeft: _secondsLeft,
                  totalSeconds: _countdownSeconds,
                ),

                const SizedBox(height: 12),
                Text(
                  'Redirecting to enter code in $_secondsLeft second${_secondsLeft == 1 ? '' : 's'}…',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 36),

                // Enter code now
                PrimaryButton(
                  label: 'Enter Code Now',
                  onPressed: _goToOtp,
                  width: double.infinity,
                ),

                const SizedBox(height: 12),

                // Back to login
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _goBackToLogin,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: CoopvestColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(color: CoopvestColors.primary),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Tip box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B3A6B).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1B3A6B).withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF1B3A6B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The code expires in 10 minutes. If you don\'t see the email, check your spam or promotions folder.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Countdown ring widget ───────────────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;

  const _CountdownRing({
    required this.secondsLeft,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / totalSeconds;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2E7D32),
              ),
            ),
          ),
          Text(
            '$secondsLeft',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B3A6B),
            ),
          ),
        ],
      ),
    );
  }
}
