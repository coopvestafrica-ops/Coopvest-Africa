import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_config.dart';
import '../../../config/theme_config.dart';
import '../../../data/models/payment_proof_model.dart';
import '../../widgets/common/buttons.dart';
import '../contributions/payment_proof_upload_screen.dart';

/// Account Activation Screen
///
/// Shown to a member who has completed registration and KYC verification but
/// has NOT yet paid the (non-refundable) ₦5,000 registration fee that unlocks
/// full member-dashboard access. Mirrors the server-side activation gate:
///
///   kyc_verified = TRUE AND registration_fee_paid = TRUE  → dashboard
///
/// This screen is purely informational + a pointer to the payment-proof
/// upload flow. The real enforcement lives on the backend; AuthGuard simply
/// routes here when the profile gate isn't satisfied.
class AccountActivationScreen extends ConsumerWidget {
  final String? paymentPendingNote;

  const AccountActivationScreen({super.key, this.paymentPendingNote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Activate Membership',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: CoopvestColors.primary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Celebration header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CoopvestColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.celebration,
                      size: 48,
                      color: CoopvestColors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "You're Almost There!",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: CoopvestColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your Coopvest Africa account has been successfully verified.\n\n'
                      'To activate your membership and gain access to your member dashboard, '
                      'please pay the ₦5,000 non-refundable registration fee.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CoopvestColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Registration fee card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: CoopvestColors.lightGray),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Registration Fee',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₦${AppConfig.entranceFee.toStringAsFixed(0)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: CoopvestColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'One-time, non-refundable',
                        style: TextStyle(
                          fontSize: 12,
                          color: CoopvestColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Account status breakdown
              Text(
                'Account Status',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const _StatusRow(
                icon: Icons.verified,
                iconColor: CoopvestColors.success,
                label: 'KYC',
                value: '✅ Verified',
              ),
              const _StatusRow(
                icon: Icons.payment,
                iconColor: CoopvestColors.warning,
                label: 'Registration',
                value: '🟡 Payment Required',
                highlight: true,
              ),
              const _StatusRow(
                icon: Icons.lock_outline,
                iconColor: CoopvestColors.textSecondary,
                label: 'Membership',
                value: '🔒 Not Activated',
              ),
              const SizedBox(height: 24),

              // Primary action
              PrimaryButton(
                label: 'Pay ₦5,000 to Activate',
                icon: const Icon(Icons.payment, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PaymentProofUploadScreen(
                        initialPaymentType: PaymentProofType.registrationFee,
                        prefillAmount: AppConfig.entranceFee,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Pay via bank transfer, card, or any approved method, then submit your '
                'proof of payment for verification. Once verified, your membership is '
                'activated and your dashboard unlocks.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: CoopvestColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the account-status breakdown.
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool highlight;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? CoopvestColors.warning.withOpacity(0.12)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? CoopvestColors.warning.withOpacity(0.4)
              : CoopvestColors.lightGray,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight ? CoopvestColors.warning : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}