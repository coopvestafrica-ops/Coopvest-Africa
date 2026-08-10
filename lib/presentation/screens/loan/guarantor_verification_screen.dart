import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../data/api/loan_api_service.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';

/// Guarantor Verification Screen
///
/// Shown after a guarantor scans a borrower's QR code. Walks them through
/// a 3-step flow: Review loan summary → Read and accept terms → Confirm.
/// On confirmation the screen calls the real backend API to mark the
/// loan_guarantors record as 'consented'.
class GuarantorVerificationScreen extends ConsumerStatefulWidget {
  final String loanId;
  final String borrowerName;
  final double loanAmount;
  final String loanType;
  final int loanTenor;
  final String guarantorId;
  final String guarantorName;
  final String? guarantorPhone;

  const GuarantorVerificationScreen({
    super.key,
    required this.loanId,
    required this.borrowerName,
    required this.loanAmount,
    required this.loanType,
    required this.loanTenor,
    required this.guarantorId,
    required this.guarantorName,
    this.guarantorPhone,
  });

  @override
  ConsumerState<GuarantorVerificationScreen> createState() =>
      _GuarantorVerificationScreenState();
}

class _GuarantorVerificationScreenState
    extends ConsumerState<GuarantorVerificationScreen> {
  String _verificationStatus = 'review';
  bool _isProcessing = false;
  bool _agreedToTerms = false;

  double get _guarantorLiability => widget.loanAmount / 3;

  Future<void> _confirmConsent() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please read and accept the liability terms'),
          backgroundColor: CoopvestColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _verificationStatus = 'processing';
    });

    try {
      // Get actual savings balance from wallet
      final walletState = ref.read(walletProvider);
      final savingsBalance = walletState.wallet?.totalSavings ?? 
                            walletState.wallet?.balance ?? 0.0;
      
      final loanApiService = ref.read(loanApiServiceProvider);
      final request = GuarantorConfirmRequest(
        guarantorId:   widget.guarantorId,
        guarantorName: widget.guarantorName,
        guarantorPhone: widget.guarantorPhone ?? '',
        savingsBalance: savingsBalance,
      );

      await loanApiService.confirmGuarantee(widget.loanId, request);

      setState(() {
        _verificationStatus = 'confirmed';
        _isProcessing = false;
      });

      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _verificationStatus = 'consent';
        _isProcessing = false;
      });
      if (mounted) {
        String errorMsg;
        final raw = e.toString();
        if (raw.contains('SocketException') || raw.contains('Failed host') || raw.contains('connection')) {
          errorMsg = 'No internet connection. Please check your network and try again.';
        } else if (raw.contains('401') || raw.contains('Unauthorized')) {
          errorMsg = 'Your session has expired. Please log in again.';
        } else if (raw.contains('already confirmed')) {
          errorMsg = 'You have already confirmed this guarantee.';
        } else if (raw.contains('timeout')) {
          errorMsg = 'The request timed out. Please try again.';
        } else if (raw.contains('Exception:')) {
          // Clean up 'Exception: <message>' wrapping
          errorMsg = raw.replaceFirst(RegExp(r'^Exception:s*'), '');
        } else {
          errorMsg = 'Unable to confirm guarantee. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: CoopvestColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
            const Icon(Icons.check_circle, color: CoopvestColors.success, size: 32),
            const SizedBox(width: 12),
            Text('Guarantee Confirmed', style: TextStyle(color: context.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your guarantee has been successfully recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CoopvestColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Liability Share',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₦${_guarantorLiability.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: CoopvestColors.primary,
                    ),
                  ),
                ],
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
          'Guarantee Consent',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgressStepper(context),
              const SizedBox(height: 24),
              if (_verificationStatus == 'review')
                _buildReviewScreen(context)
              else if (_verificationStatus == 'consent')
                _buildConsentScreen(context)
              else
                _buildProcessingScreen(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStepper(BuildContext context) {
    final steps = ['Review', 'Consent', 'Confirm'];
    final currentStep = _verificationStatus == 'review'
        ? 0
        : (_verificationStatus == 'consent' ? 1 : 2);
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          return Expanded(
            child: Container(
              height: 2,
              color: index ~/ 2 < currentStep
                  ? CoopvestColors.primary
                  : context.dividerColor,
            ),
          );
        }
        final stepIndex = index ~/ 2;
        final isActive = stepIndex <= currentStep;
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? CoopvestColors.primary : context.dividerColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: stepIndex < currentStep
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : context.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _buildReviewScreen(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          backgroundColor: context.cardBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.description, color: CoopvestColors.primary),
                const SizedBox(width: 8),
                Text('Loan Summary',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: context.textPrimary)),
              ]),
              const SizedBox(height: 16),
              _buildSummaryRow(context, 'Borrower:', widget.borrowerName),
              _buildSummaryRow(context, 'Loan Type:', widget.loanType),
              _buildSummaryRow(
                  context, 'Amount:', '₦${widget.loanAmount.toStringAsFixed(2)}'),
              _buildSummaryRow(
                  context, 'Tenor:', '${widget.loanTenor} months'),
            ],
          ),
        ),
        const SizedBox(height: 32),
        PrimaryButton(
          label: 'Continue to Consent',
          onPressed: () => setState(() => _verificationStatus = 'consent'),
          width: double.infinity,
        ),
      ],
    );
  }

  Widget _buildConsentScreen(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guarantor Consent',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimary),
        ),
        const SizedBox(height: 12),

        // Policy notification copy — exact text from Loan Policy §3.2
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CoopvestColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CoopvestColors.primary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline, color: CoopvestColors.primary, size: 18),
                  SizedBox(width: 8),
                  Text('Guarantor Notice',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: CoopvestColors.primary)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'You have been listed as a guarantor for ${widget.borrowerName}\'s '
                'loan application. By accepting, you acknowledge your responsibility '
                "under the loan agreement and Coopvest Africa's loan policy.",
                style: TextStyle(
                    color: context.textPrimary, height: 1.6, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Liability disclosure
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Liability Disclosure',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontSize: 14)),
              const SizedBox(height: 10),
              Text(
                '• You are guaranteeing ₦${widget.loanAmount.toStringAsFixed(2)} for ${widget.borrowerName}.',
                style: TextStyle(
                    color: context.textSecondary, height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const Text(
                '• If the borrower fails to repay for 3 consecutive months without '
                'approved arrangements, guarantors may become responsible for '
                'supporting repayment of the outstanding balance.',
                style: TextStyle(height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '• Your estimated liability share: ₦${_guarantorLiability.toStringAsFixed(2)} (1/3 of loan).',
                style: TextStyle(
                    color: context.textSecondary, height: 1.5, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Standard policy notice (Loan Policy §5.2)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CoopvestColors.warning.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CoopvestColors.warning.withOpacity(0.25)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined,
                  color: CoopvestColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Late loan repayments may attract a ₦3,000 penalty fee after '
                  'repeated default notices. Continued non-payment beyond three '
                  "months may trigger guarantor recovery procedures in accordance "
                  "with Coopvest Africa's loan policy.",
                  style: TextStyle(
                      color: CoopvestColors.warning, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Consent checkbox
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _agreedToTerms
                ? CoopvestColors.success.withOpacity(0.06)
                : context.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _agreedToTerms
                  ? CoopvestColors.success.withOpacity(0.4)
                  : context.dividerColor,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                activeColor: CoopvestColors.success,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "I have read and understood the guarantor responsibilities and "
                    "Coopvest Africa's loan policy. I consent to act as guarantor "
                    "for this loan.",
                    style: TextStyle(
                        color: context.textPrimary, fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        PrimaryButton(
          label: 'Confirm Guarantee',
          onPressed: _confirmConsent,
          isLoading: _isProcessing,
          width: double.infinity,
        ),
      ],
    );
  }

  Widget _buildProcessingScreen(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          const CircularProgressIndicator(color: CoopvestColors.primary),
          const SizedBox(height: 24),
          Text(
            'Processing your guarantee...',
            style: TextStyle(color: context.textPrimary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: context.textPrimary)),
        ],
      ),
    );
  }
}
