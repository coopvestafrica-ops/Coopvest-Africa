import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../presentation/widgets/common/buttons.dart';

/// Withdrawal Screen
///
/// NOTE: Bank withdrawals are temporarily disabled. The original withdrawal
/// form has been commented out and replaced with a maintenance notice. Restore
/// the commented block (and the unused imports/fields) when bank withdrawals
/// are re-enabled.
class WithdrawalScreen extends ConsumerStatefulWidget {
  final String userId;

  const WithdrawalScreen({super.key, required this.userId});

  @override
  ConsumerState<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends ConsumerState<WithdrawalScreen> {
  void _goBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: _goBack,
        ),
        title: Text(
          'Withdraw Funds',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CoopvestColors.warning.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_outlined,
                    size: 48,
                    color: CoopvestColors.warning,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Withdrawals temporarily unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We are working with our payment partner to restore bank '
                  'withdrawals. Your wallet balance is safe and remains '
                  'available for in-app contributions, loan repayments and '
                  'transfers. Please check back soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 32),
                SecondaryButton(
                  label: 'Go Back',
                  onPressed: _goBack,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /*
  // ── Original withdrawal flow (disabled) ────────────────────────────────────
  // Re-enable by restoring the wallet_provider / cards / inputs imports above
  // and uncommenting this block.

  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isProcessing = false;

  Future<void> _processWithdrawal() async {
    if (!_formKey.currentState!.validate()) return;

    final rawAmount = _amountController.text.replaceAll(',', '');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await ref.read(walletProvider.notifier).makeWithdrawal(
        amount: amount,
        description: 'Wallet withdrawal',
      );
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Withdrawal failed: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.cardBackground,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: CoopvestColors.success),
            const SizedBox(width: 8),
            Text('Withdrawal Successful', style: TextStyle(color: context.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your withdrawal of ₦\${_amountController.text} has been processed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CoopvestColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Funds will be transferred to your bank account within 24 hours.',
                style: TextStyle(color: CoopvestColors.warning, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
  // ── End disabled block ─────────────────────────────────────────────────────
  */
}
