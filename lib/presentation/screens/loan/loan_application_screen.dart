import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_config.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/referral_models.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/contributions/contribution_provider.dart';
import '../../../presentation/providers/referral_provider.dart';
import '../../../presentation/providers/wallet_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import '../../../presentation/widgets/common/inputs.dart';

/// Loan Application Screen with 6 Loan Types and QR-based 3-Guarantor System
/// Now includes Referral Bonus Section for tiered interest reduction
class LoanApplicationScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String userPhone;

  const LoanApplicationScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhone,
  });

  @override
  ConsumerState<LoanApplicationScreen> createState() => _LoanApplicationScreenState();
}

class _LoanApplicationScreenState extends ConsumerState<LoanApplicationScreen> {
  bool get isDarkMode => Theme.of(context).brightness == Brightness.dark;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final TextEditingController _monthlySavingsController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    // Load wallet data for savings-based loan limits
    // Load contributions to check eligibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadWallet();
      ref.read(contributionProvider.notifier).loadContributions();
    });
  }

  // Loan Types Configuration
  // Now uses savings-based multipliers instead of fixed amounts
  // Premium Loan: 4x savings, Maxi Loan: 5x savings, Others: 3x savings
  final Map<String, Map<String, dynamic>> _loanTypes = {
    'Quick Loan': {
      'duration': 4,
      'interest': 7.5,
      'multiplier': 3.0, // 3x savings
      'description': 'Short-term emergency cash for members in urgent need',
    },
    'Flexi Loan': {
      'duration': 6,
      'interest': 7.0,
      'multiplier': 3.0, // 3x savings
      'description': 'Flexible repayment plan for personal or business needs',
    },
    'Stable Loan (12 months)': {
      'duration': 12,
      'interest': 5.0,
      'multiplier': 3.0, // 3x savings
      'description': 'Long-term stability with the lowest interest rate',
    },
    'Stable Loan (18 months)': {
      'duration': 18,
      'interest': 7.0,
      'multiplier': 3.0, // 3x savings
      'description': 'Extended repayment for larger projects or investments',
    },
    'Premium Loan': {
      'duration': 24,
      'interest': 14.0,
      'multiplier': 4.0, // 4x savings - Special for premium members
      'description': 'Premium access for established members with higher limits',
    },
    'Maxi Loan': {
      'duration': 36,
      'interest': 19.0,
      'multiplier': 5.0, // 5x savings - Maximum for major investments
      'description': 'Maximum loan for major investments and business expansion',
    },
  };

  String _selectedLoanType = 'Quick Loan';
  String _loanStatus = '';
  String _loanId = '';
  String? _qrId; // QR ID from backend after generating QR code
  String? _qrCodeData; // Full QR code data string from backend
  String? _qrImageDataUrl; // Backend-generated QR PNG data URL (persisted on loan_qrs)
  String? _rejectionReason;
  bool _showQrCode = false;
  bool _isSubmitting = false;
  final ScrollController _scrollController = ScrollController();

  // Calculate monthly repayment
  double _calculateMonthlyRepayment(double amount, double interestRate, int tenure) {
    final principal = amount;
    final rate = interestRate / 100 / 12;
    final months = tenure;
    
    // EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
    final emi = principal * rate * pow(1 + rate, months) / (pow(1 + rate, months) - 1);
    return emi;
  }

  // Calculate total repayment
  double _calculateTotalRepayment(double amount, double interestRate) {
    return amount + (amount * interestRate / 100);
  }

  // Returns full QR data string for scanning (from backend or fallback)
  String get _qrDataForDisplay => _qrCodeData ?? '{"qrId":"${_qrId ?? _loanId}","loanId":"$_loanId"}';

  // Fallback display for legacy UI (shows loan ID)
  String get _formattedLoanId => 'COOP-${_loanId}';

  // Check if user is eligible for loan based on membership duration and contributions
  // Requirements: At least 6 months membership AND at least 6 months of consistent contributions
  Map<String, dynamic> _checkLoanEligibility() {
    // Get user from auth provider
    final authState = ref.read(authProvider);
    final user = authState.user;
    
    // Get contributions from contribution provider
    final contributionState = ref.read(contributionProvider);
    final contributions = contributionState.contributions;
    final summary = contributionState.summary;
    
    // Check membership duration
    int membershipMonths = 0;
    if (user != null && user.createdAt != null) {
      membershipMonths = user.membershipDurationMonths;
    }
    
    // Count months with successful contributions
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 6, 1);
    
    // Count successful contributions in the last 6 months
    final successfulContributions = contributions.where((c) {
      if (c.status.name != 'successful' && c.status.name != 'completed') {
        return false;
      }
      // Check if contribution is from the last 6 months
      if (c.postedDate != null) {
        return c.postedDate!.isAfter(sixMonthsAgo) || 
               c.postedDate!.isAtSameMomentAs(sixMonthsAgo);
      }
      if (c.createdAt != null) {
        return c.createdAt.isAfter(sixMonthsAgo) || 
               c.createdAt.isAtSameMomentAs(sixMonthsAgo);
      }
      return false;
    }).toList();
    
    // Get unique months with successful contributions
    final uniqueContributionMonths = <String>{};
    for (final c in successfulContributions) {
      if (c.contributionMonth != null) {
        uniqueContributionMonths.add(c.contributionMonth!);
      }
    }
    
    final contributionMonths = uniqueContributionMonths.length;
    
    // Also check from summary if available
    final summaryContributionMonths = summary?.monthsContributed ?? 0;
    
    // Use the higher of the two values
    final finalContributionMonths = contributionMonths > summaryContributionMonths 
        ? contributionMonths 
        : summaryContributionMonths;
    
    // Determine eligibility
    // TESTING ONLY: 6-month membership & contribution requirement bypassed for loan testing.
    // Restore the original check below when testing is complete:
    // final isEligible = membershipMonths >= 6 && finalContributionMonths >= 6;
    final isEligible = true;
    
    return {
      'isEligible': isEligible,
      'membershipMonths': membershipMonths,
      'contributionMonths': finalContributionMonths,
      'membershipRequired': 6,
      'contributionsRequired': 6,
    };
  }

  // Build eligibility status widget
  Widget _buildEligibilityWidget() {
    final eligibility = _checkLoanEligibility();
    final isEligible = eligibility['isEligible'] as bool;
    final membershipMonths = eligibility['membershipMonths'] as int;
    final contributionMonths = eligibility['contributionMonths'] as int;
    final membershipRequired = eligibility['membershipRequired'] as int;
    final contributionsRequired = eligibility['contributionsRequired'] as int;
    
    if (isEligible) {
      // User is eligible - show green status
      return AppCard(
        backgroundColor: CoopvestColors.success.withAlpha((255 * 0.1).toInt()),
        border: Border.all(color: CoopvestColors.success.withAlpha((255 * 0.3).toInt())),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: CoopvestColors.success, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'You are eligible to apply for a loan!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: CoopvestColors.success,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Membership: $membershipMonths months | Contributions: $contributionMonths months',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : CoopvestColors.darkGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // User is NOT eligible - show red warning
      String reason = '';
      if (membershipMonths < 6 && contributionMonths < 6) {
        reason = 'You need at least $membershipRequired months of membership AND $contributionsRequired months of consistent contributions to be eligible for a loan.';
      } else if (membershipMonths < 6) {
        reason = 'You need at least $membershipRequired months of membership. You currently have $membershipMonths months.';
      } else if (contributionMonths < 6) {
        reason = 'You need at least $contributionsRequired months of consistent contributions. You currently have $contributionMonths months.';
      }
      
      return AppCard(
        backgroundColor: CoopvestColors.error.withAlpha((255 * 0.1).toInt()),
        border: Border.all(color: CoopvestColors.error.withAlpha((255 * 0.3).toInt())),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.block, color: CoopvestColors.error, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Loan Eligibility Requirements Not Met',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: CoopvestColors.error,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              reason,
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : CoopvestColors.darkGray,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEligibilityRow(
                    'Membership Duration',
                    '$membershipMonths / $membershipRequired months',
                    membershipMonths >= membershipRequired,
                  ),
                  const SizedBox(height: 8),
                  _buildEligibilityRow(
                    'Consistent Contributions',
                    '$contributionMonths / $contributionsRequired months',
                    contributionMonths >= contributionsRequired,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Continue making your monthly contributions to become eligible for a loan.',
              style: TextStyle(
                color: isDarkMode ? Colors.white60 : CoopvestColors.mediumGray,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildEligibilityRow(String label, String value, bool isMet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : CoopvestColors.darkGray,
            fontSize: 13,
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                color: isMet ? CoopvestColors.success : CoopvestColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isMet ? Icons.check_circle : Icons.cancel,
              color: isMet ? CoopvestColors.success : CoopvestColors.error,
              size: 16,
            ),
          ],
        ),
      ],
    );
  }

  /// Shows the Digital Loan Agreement dialog (Loan Policy §2.2).
  /// Returns true if user accepts, false if they cancel.
  Future<bool> _showLoanAgreementDialog() async {
    bool acceptedAgreement = false;
    bool acceptedTermsAck = false;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          title: const Row(
            children: [
              Icon(Icons.description, color: CoopvestColors.primary),
              SizedBox(width: 8),
              Expanded(child: Text('Digital Loan Agreement', style: TextStyle(fontSize: 16))),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please read and accept the following before your loan application is submitted.',
                    style: TextStyle(fontSize: 12, color: CoopvestColors.mediumGray),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CoopvestColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CoopvestColors.primary.withOpacity(0.2)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Loan Agreement Terms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 10),
                        Text(
                          '1. This loan requires exactly three (3) guarantors who must provide consent before activation.\n\n'
                          '2. Repayments must be made on time each month.\n\n'
                          '3. A ₦3,000 late repayment penalty applies after 2 consecutive missed payments.\n\n'
                          '4. If repayment is missed for 3 consecutive months without approved arrangements, '
                          'guarantors may become responsible for the outstanding balance in accordance with '
                          'Coopvest Africa\'s loan policy.\n\n'
                          '5. By proceeding, you authorise Coopvest Africa to disburse the approved amount '
                          'to your registered account and to apply the terms above.',
                          style: TextStyle(fontSize: 12, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Checkbox 1: Digital agreement acceptance
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: acceptedAgreement,
                        onChanged: (v) => setDialogState(() => acceptedAgreement = v ?? false),
                        activeColor: CoopvestColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'I have read and agree to the Digital Loan Agreement above.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Checkbox 2: Loan terms acknowledgment (§2.2)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: acceptedTermsAck,
                        onChanged: (v) => setDialogState(() => acceptedTermsAck = v ?? false),
                        activeColor: CoopvestColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'I explicitly acknowledge and accept the loan terms, guarantor requirements, and repayment obligations.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CoopvestColors.primary),
              onPressed: (acceptedAgreement && acceptedTermsAck)
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('Accept & Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<void> _submitApplication() async {
    // First check if user is eligible for loan
    final eligibility = _checkLoanEligibility();
    if (!(eligibility['isEligible'] as bool)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not eligible to apply for a loan. Please meet the 6-month membership and contribution requirements.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Show Digital Loan Agreement for acceptance (Loan Policy §2.2)
    final agreementAccepted = await _showLoanAgreementDialog();
    if (!agreementAccepted) return;

    setState(() {
      _isSubmitting = true;
      _loanStatus = 'Processing';
      _rejectionReason = null;
    });

    try {
      final loanInfo = _loanTypes[_selectedLoanType]!;
      final multiplier = (loanInfo['multiplier'] as num).toDouble();
      final requestedAmount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
      final monthlySavings = double.tryParse(_monthlySavingsController.text.replaceAll(',', '')) ?? 0.0;
      
      // Get member's savings for limit calculation
      final walletState = ref.read(walletProvider);
      final memberSavings = walletState.wallet?.totalSavings ?? walletState.wallet?.balance ?? 0.0;
      
      // Calculate limits based on savings
      final minAmount = 1000.0;
      // TEMP: use 10,000,000 test cap when savings is 0 (restore to memberSavings * multiplier)
      final maxAmount = memberSavings > 0 ? memberSavings * multiplier : 10000000.0;

      // Validate amount range based on savings
      if (requestedAmount < minAmount) {
        setState(() {
          _loanStatus = 'Rejected';
          _rejectionReason = 'Minimum amount is \u20a6${minAmount.toStringAsFixed(0)}';
          _isSubmitting = false;
        });
        return;
      }

      if (requestedAmount > maxAmount) {
        setState(() {
          _loanStatus = 'Rejected';
          _rejectionReason = 'Maximum amount for ${_selectedLoanType} is \u20a6${maxAmount.toStringAsFixed(0)} (${multiplier}x your savings)';
          _isSubmitting = false;
        });
        return;
      }

      // Validate monthly savings (must be at least 10% of loan amount)
      if (monthlySavings < requestedAmount * 0.1) {
        setState(() {
          _loanStatus = 'Rejected';
          _rejectionReason = 'Monthly savings commitment must be at least 10% of loan amount (\u20a6${(requestedAmount * 0.1).toStringAsFixed(2)})';
          _isSubmitting = false;
        });
        return;
      }

      String? backendLoanId;
      String? qrId;
      String? qrCodeData;

      // Create the loan via the backend /loans/apply route.
      // (Previously this called /loans/register, which does not exist, so the
      // loan was never persisted and guarantors later saw
      // "invalid loan reference format".)
      final apiClient = ref.read(apiClientProvider);
      try {
        final applyResponse = await apiClient.post('/loans/apply', data: {
          'loanType': _selectedLoanType,
          'amount': requestedAmount,
          'tenureMonths': loanInfo['duration'],
          'purpose': _purposeController.text.trim(),
        });

        // /loans/apply returns { success, loan, interest, bonus }.
        // loan.loan_id is the text reference (e.g. "LN-...") used by
        // verifyLoanOwnership; loan.id is the canonical UUID.
        if (applyResponse != null && applyResponse['loan'] != null) {
          final loan = applyResponse['loan'] as Map<String, dynamic>;
          // Prefer the text reference for generate-qr (ownership middleware
          // looks loans up by loan_id); fall back to the UUID if absent.
          backendLoanId = (loan['loan_id'] as String?) ?? (loan['id'] as String?);
        }

        if (backendLoanId == null || backendLoanId!.isEmpty) {
          throw Exception('Backend did not return a loan id');
        }

        // Generate QR code via backend
        final qrResponse = await apiClient.post('/loans/$backendLoanId/generate-qr', data: {
          'applicantName': widget.userName,
          'applicantPhone': widget.userPhone,
        });
        
        if (qrResponse != null && qrResponse['qr'] != null) {
          final qr = qrResponse['qr'] as Map<String, dynamic>;
          qrId = qr['id'] as String?;
          // qr['data'] is a decoded JSON object (from the JSONB column), not a
          // String — assigning it directly used to throw, silently dropping us
          // into the local fallback QR that didn't match the persisted one.
          final data = qr['data'];
          qrCodeData = data is String ? data : (data != null ? jsonEncode(data) : null);
          // The backend PNG data URL is the exact image persisted on loan_qrs,
          // so displaying it keeps the QR identical across app restarts.
          _qrImageDataUrl = qr['qrCode'] as String?;
        }
      } catch (e) {
        // Backend errors - continue with local fallback IDs
        debugPrint('Backend QR generation failed, using fallback: $e');
      }

      // Simple approval logic (15%+ savings = Approved, 10–15% = Pending Review)
      final bool showQr = true; // Always show QR code
      
      // Generate local QR data if backend didn't provide one
      if (qrCodeData == null || qrCodeData!.isEmpty) {
        // Create a local QR data with all loan info
        final loanStatusText = monthlySavings >= requestedAmount * 0.15 ? 'Approved' : 'Pending Review';
        qrCodeData = 'COOPVEST_LOAN|${backendLoanId ?? 'LOCAL-${DateTime.now().millisecondsSinceEpoch}'}|$_selectedLoanType|₦$requestedAmount|${widget.userName}|${widget.userPhone}|$loanStatusText';
        qrId = backendLoanId ?? 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
      }
      
      if (monthlySavings >= requestedAmount * 0.15) {
        setState(() {
          _loanId = backendLoanId ?? 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
          _qrId = qrId;
          _qrCodeData = qrCodeData;
          _loanStatus = 'Approved';
          _rejectionReason = null;
          _showQrCode = showQr;
          _isSubmitting = false;
        });

        // Show success dialog
        _showSuccessDialog(showQr: showQr);
      } else if (monthlySavings >= requestedAmount * 0.1) {
        setState(() {
          _loanId = backendLoanId ?? 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
          _qrId = qrId;
          _qrCodeData = qrCodeData;
          _loanStatus = 'Pending Review';
          _rejectionReason = null;
          _showQrCode = showQr;
          _isSubmitting = false;
        });

        _showPendingDialog(showQr: showQr);
      } else {
        setState(() {
          _loanStatus = 'Rejected';
          _rejectionReason = 'Monthly savings commitment is too low. Minimum 10% required.';
          _isSubmitting = false;
        });
      }

    } catch (e) {
      setState(() {
        _loanStatus = 'Error';
        _rejectionReason = 'Failed to process application: $e';
        _isSubmitting = false;
      });
    }
  }

  void _showSuccessDialog({bool showQr = true}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: CoopvestColors.success),
            SizedBox(width: 8),
            Text('Success!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your ${_selectedLoanType} application has been APPROVED!', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              showQr 
                ? 'To complete the process, please share the QR code (now visible at the bottom of the screen) with your 3 guarantors.'
                : 'Your loan has been approved. QR code generation is temporarily unavailable. Please try again later or contact support.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          if (showQr)
            PrimaryButton(
              label: 'View QR Code',
              onPressed: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  }
                });
              },
            )
          else
            PrimaryButton(
              label: 'OK',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  void _showPendingDialog({bool showQr = true}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.hourglass_top, color: Colors.orange),
            SizedBox(width: 8),
            Text('Under Review'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your ${_selectedLoanType} application is now under review.'),
            const SizedBox(height: 16),
            Text(
              'Please share the QR code with your 3 guarantors. Once all 3 guarantors confirm, your loan will be processed.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          if (showQr)
            PrimaryButton(
              label: 'View QR Code',
              onPressed: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  }
                });
              },
            )
          else
            PrimaryButton(
              label: 'OK',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  void _goBack() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _monthlySavingsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loanInfo = _loanTypes[_selectedLoanType]!;
    final multiplier = (loanInfo['multiplier'] as num).toDouble();
    
    // Get member's savings from wallet provider
    final walletState = ref.watch(walletProvider);
    final memberSavings = walletState.wallet?.totalSavings ?? walletState.wallet?.balance ?? 0.0;
    
    // Calculate min and max based on savings multiplier
    final minAmount = 1000.0; // Minimum loan of ₦1,000
    // TEMP: use 10,000,000 test cap when savings is 0 (restore to memberSavings * multiplier)
    final maxAmount = memberSavings > 0 ? memberSavings * multiplier : 10000000.0;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? CoopvestColors.darkBackground : Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode ? CoopvestColors.darkSurface : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.white : CoopvestColors.darkGray),
          onPressed: _goBack,
        ),
        title: Text(
          'Apply for Loan',
          style: CoopvestTypography.headlineLarge.copyWith(
            color: isDarkMode ? Colors.white : CoopvestColors.darkGray,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Loan Eligibility Status Widget - Check 6 months membership & contributions
                _buildEligibilityWidget(),

                const SizedBox(height: 24),

                // Loan Type Selection Card
                AppCard(
                  backgroundColor: CoopvestColors.primary.withAlpha((255 * 0.05).toInt()),
                  border: Border.all(color: CoopvestColors.primary.withAlpha((255 * 0.2).toInt())),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance, color: CoopvestColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Select Loan Type',
                            style: CoopvestTypography.labelLarge.copyWith(
                              color: CoopvestColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: CoopvestColors.lightGray),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _selectedLoanType,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          isExpanded: true, // Allow dropdown to take full width
                          items: _loanTypes.entries.map((entry) {
                            final key = entry.key;
                            final value = entry.value;
                            return DropdownMenuItem(
                              value: key,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    key,
                                    style: CoopvestTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${value['duration']}m @ ${value['interest']}%',
                                    style: CoopvestTypography.bodySmall.copyWith(
                                      color: CoopvestColors.mediumGray,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedLoanType = value!;
                              _amountController.clear();
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        loanInfo['description'] as String,
                        style: CoopvestTypography.bodySmall.copyWith(
                          color: CoopvestColors.mediumGray,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Loan Amount
                AppTextField(
                  label: 'Loan Amount (\u20a6) *',
                  hint: 'Enter amount between \u20a6${minAmount.toStringAsFixed(0)} - \u20a6${maxAmount.toStringAsFixed(0)}',
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  prefixText: '\u20a6 ',
                  onChanged: (value) {
                    setState(() {});
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter loan amount';
                    }
                    final amount = double.tryParse(value.replaceAll(',', ''));
                    if (amount == null) {
                      return 'Please enter a valid number';
                    }
                    if (amount < minAmount) {
                      return 'Minimum amount is \u20a6${minAmount.toStringAsFixed(0)}';
                    }
                    if (amount > maxAmount) {
                      return 'Maximum amount is \u20a6${maxAmount.toStringAsFixed(0)}';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Monthly Savings While on Loan
                AppTextField(
                  label: 'Monthly Savings While On Loan (\u20a6) *',
                  hint: 'Minimum 10% of loan amount required',
                  controller: _monthlySavingsController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  prefixText: '\u20a6 ',
                  onChanged: (value) {
                    setState(() {});
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter monthly savings amount';
                    }
                    final savings = double.tryParse(value);
                    if (savings == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                ),

                // Show calculated values and referral bonus
                if (_amountController.text.isNotEmpty && _monthlySavingsController.text.isNotEmpty)
                  ...[
                    const SizedBox(height: 16),
                    _buildLoanSummary(loanInfo),
                    const SizedBox(height: 16),
                    _buildReferralBonusSection(context, ref, loanInfo),
                  ],

                const SizedBox(height: 16),

                // Loan Purpose
                AppTextField(
                  label: 'Loan Purpose *',
                  hint: 'Briefly describe why you need this loan',
                  controller: _purposeController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter loan purpose';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Important Notice Card
                AppCard(
                  backgroundColor: CoopvestColors.warning.withAlpha((255 * 0.1).toInt()),
                  border: Border.all(color: CoopvestColors.warning.withAlpha((255 * 0.3).toInt())),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: CoopvestColors.warning),
                          const SizedBox(width: 8),
                          Text(
                            'Important Requirements',
                            style: CoopvestTypography.labelLarge.copyWith(
                              color: CoopvestColors.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('• You need 3 guarantors to approve this loan'),
                      _buildInfoRow('• Guarantors must be existing members'),
                      _buildInfoRow('• Monthly savings must be at least 10% of loan amount'),
                      _buildInfoRow('• Defaulting loans will be inherited by guarantors'),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Submit Button
                _isSubmitting
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: CoopvestColors.primary,
                        ),
                      )
                    : PrimaryButton(
                        label: 'Submit Application',
                        onPressed: _submitApplication,
                        width: double.infinity,
                      ),

                const SizedBox(height: 16),

                // Back Button
                SecondaryButton(
                  label: 'Go Back',
                  onPressed: _goBack,
                  width: double.infinity,
                ),

                // QR Code and Status Section
                if (_showQrCode) ...[
                  const SizedBox(height: 32),
                  _buildStatusSection(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: CoopvestTypography.bodySmall.copyWith(
          color: isDarkMode ? Colors.white : CoopvestColors.darkGray,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLoanSummary(Map<String, dynamic> loanInfo) {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;
    final savings = double.tryParse(_monthlySavingsController.text) ?? 0;
    final interestRate = (loanInfo['interest'] as num).toDouble();
    final tenure = loanInfo['duration'] as int;
    
    final monthlyRepayment = _calculateMonthlyRepayment(amount, interestRate, tenure);
    final totalRepayment = _calculateTotalRepayment(amount, interestRate);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loan Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          _buildSummaryRow('Requested Amount', '\u20a6${amount.toStringAsFixed(2)}'),
          _buildSummaryRow('Interest Rate', '${interestRate}%'),
          _buildSummaryRow('Tenure', '${tenure} Months'),
          _buildSummaryRow('Monthly Repayment', '\u20a6${monthlyRepayment.toStringAsFixed(2)}', isBold: true),
          _buildSummaryRow('Total Repayment', '\u20a6${totalRepayment.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondary)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildReferralBonusSection(BuildContext context, WidgetRef ref, Map<String, dynamic> loanInfo) {
    final referralState = ref.watch(referralProvider);
    final referrals = referralState.referrals;
    final activeReferralsCount = referrals.where((r) => r.confirmed && !r.isFlagged).length;
    
    // Tiered interest reduction based on active referrals
    double reduction = 0;
    if (activeReferralsCount >= 10) reduction = 2.0;
    else if (activeReferralsCount >= 5) reduction = 1.0;
    else if (activeReferralsCount >= 2) reduction = 0.5;

    final originalInterest = (loanInfo['interest'] as num).toDouble();
    final finalInterest = max(0.0, originalInterest - reduction);

    return AppCard(
      backgroundColor: CoopvestColors.primary.withAlpha((255 * 0.1).toInt()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars, color: CoopvestColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text('Referral Bonus', style: TextStyle(fontWeight: FontWeight.bold, color: CoopvestColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Active Referrals: $activeReferralsCount', style: const TextStyle(fontSize: 12)),
          if (reduction > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Interest reduced by ${reduction}%! (Original: ${originalInterest}%, New: ${finalInterest}%)',
                style: const TextStyle(color: CoopvestColors.success, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Refer more members to reduce your loan interest rate!',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      children: [
        AppCard(
          child: Column(
            children: [
              const Text('Loan Application QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text('Status: $_loanStatus', style: TextStyle(
                color: _loanStatus == 'Approved' ? CoopvestColors.success : Colors.orange,
                fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 24),
              // Show the backend-persisted QR image so the code seen right
              // after applying is identical to the one shown after reopening
              // the app. Fall back to a locally rendered QR only if the
              // backend image is unavailable.
              if (_qrImageDataUrl != null && _qrImageDataUrl!.startsWith('data:image'))
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(_qrImageDataUrl!.substring(_qrImageDataUrl!.indexOf(',') + 1)),
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                )
              else
                QrImageView(
                  data: _qrDataForDisplay,
                  version: QrVersions.auto,
                  size: 200.0,
                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                ),
              const SizedBox(height: 16),
              Text(_formattedLoanId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Share this code with your 3 guarantors. They must scan it to approve your application.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: CoopvestColors.mediumGray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}