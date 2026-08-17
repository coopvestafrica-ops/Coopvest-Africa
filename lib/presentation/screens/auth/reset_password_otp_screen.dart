import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/utils.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';

/// Reset Password OTP Screen — Step 2: enter OTP + new password
class ResetPasswordOtpScreen extends ConsumerStatefulWidget {
  final String email;

  const ResetPasswordOtpScreen({Key? key, required this.email}) : super(key: key);

  @override
  ConsumerState<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends ConsumerState<ResetPasswordOtpScreen> {
  late List<TextEditingController> _otpControllers;
  late List<FocusNode> _otpFocusNodes;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isResending = false;
  int _remainingSeconds = 120;
  bool _canResend = false;

  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _startTimer();
  }

  @override
  void dispose() {
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes) f.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _canResend = true;
        } else {
          _startTimer();
        }
      });
    });
  }

  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    if (index == 5 && value.isNotEmpty) {
      _otpFocusNodes[index].unfocus();
    }
  }

  Future<void> _resendOtp() async {
    setState(() { _isResending = true; _remainingSeconds = 120; _canResend = false; });
    _startTimer();
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/auth/request-password-reset', data: {
        'email': widget.email,
      });
      if (mounted) {
        for (final c in _otpControllers) c.clear();
        _otpFocusNodes[0].requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset code resent'), backgroundColor: CoopvestColors.success));
      }
    } catch (_) {
      if (mounted) {
        // Only surface a real retry hint; we don't reveal whether the email is
        // registered (the backend returns 200 for unknown emails too).
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not resend code. Check your connection and try again.'), backgroundColor: CoopvestColors.error));
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _resetPassword() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter all 6 digits'), backgroundColor: CoopvestColors.error));
      return;
    }
    setState(() {
      _passwordError = Validators.validatePassword(_passwordController.text);
      _confirmPasswordError = _passwordController.text != _confirmPasswordController.text ? 'Passwords do not match' : null;
    });
    if (_passwordError != null || _confirmPasswordError != null) return;

    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/auth/reset-password', data: {
        'email': widget.email,
        'code': otp,
        'new_password': _passwordController.text,
      });

      if (mounted) {
        _showSuccessAndNavigate();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: CoopvestColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessAndNavigate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: CoopvestColors.success.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, size: 48, color: CoopvestColors.success),
            ),
            const SizedBox(height: 16),
            Text('Password Reset!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
            const SizedBox(height: 8),
            const Text('Your password has been reset successfully. Please log in with your new password.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: CoopvestColors.primary, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                },
                child: const Text('Go to Login'),
              ),
            ),
          ],
        ),
      ),
    );
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
        title: Text('Reset Password', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Enter Your Reset Code', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  text: 'We sent a 6-digit code to ',
                  style: TextStyle(color: context.textSecondary, height: 1.5),
                  children: [
                    TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w600, color: CoopvestColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) => Flexible(
                  child: Container(
                    margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                    height: 58,
                    child: TextField(
                      controller: _otpControllers[index],
                      focusNode: _otpFocusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      onChanged: (v) => _onOtpChanged(v, index),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: context.cardBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.dividerColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.dividerColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CoopvestColors.primary, width: 2)),
                      ),
                      style: TextStyle(color: context.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 16),
              Center(
                child: _canResend
                    ? GestureDetector(
                        onTap: _isResending ? null : _resendOtp,
                        child: Text(_isResending ? 'Sending...' : 'Resend Code', style: const TextStyle(color: CoopvestColors.primary, fontWeight: FontWeight.bold)),
                      )
                    : Text('Resend code in ${_remainingSeconds}s', style: TextStyle(color: context.textSecondary)),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              Text('Set New Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 16),
              AppTextField(
                label: 'New Password',
                hint: 'At least 8 characters',
                controller: _passwordController,
                obscureText: _obscurePassword,
                errorText: _passwordError,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: context.textSecondary),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Confirm New Password',
                hint: 'Re-enter new password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                errorText: _confirmPasswordError,
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: context.textSecondary),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Reset Password', onPressed: _resetPassword, isLoading: _isLoading, width: double.infinity),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
