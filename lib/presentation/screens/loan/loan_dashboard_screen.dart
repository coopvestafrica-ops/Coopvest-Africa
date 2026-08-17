import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart' hide NumExtension;
import '../../../core/extensions/number_extensions.dart';
import '../../../data/models/loan_models.dart';
import '../../../core/network/api_client.dart';
import '../../../presentation/providers/loan_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';
import 'loan_application_screen.dart';
import '../../widgets/loan/loan_eligibility_card.dart';

/// Loan Dashboard Screen - View and manage all loan applications
class LoanDashboardScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String userPhone;

  const LoanDashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhone,
  });

  @override
  ConsumerState<LoanDashboardScreen> createState() => _LoanDashboardScreenState();
}

class _LoanDashboardScreenState extends ConsumerState<LoanDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(loanProvider.notifier).getLoans();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loanState = ref.watch(loanProvider);
    final loans = loanState.loans;
    
    // Calculate stats from real data
    final activeLoans = loans.where((l) => l.status == 'active' || l.status == 'repaying').length;
    final totalBorrowed = loans.fold(0.0, (sum, l) => sum + l.amount);
    final totalRepaid = loans.where((l) => l.status == 'completed').fold(0.0, (sum, l) => sum + l.totalRepayment);
    
    final overdueLoans = loans.where((l) => l.status.toLowerCase() == 'overdue' || l.status.toLowerCase() == 'in_recovery').toList();
    final hasOverdueLoans = overdueLoans.isNotEmpty;

    final _quickStats = {
      'totalLoans': loans.length,
      'activeLoans': activeLoans,
      'totalBorrowed': totalBorrowed,
      'totalRepaid': totalRepaid,
    };

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        title: const Text('My Loans'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(loanProvider.notifier).getLoans();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Overdue Status Banner (Loan Policy §4.2) ──
                if (hasOverdueLoans) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: CoopvestColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CoopvestColors.error.withOpacity(0.5), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: CoopvestColors.error, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'OVERDUE STATUS',
                              style: TextStyle(
                                color: CoopvestColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You have ${overdueLoans.length} overdue loan${overdueLoans.length > 1 ? "s" : ""}. '
                          'Please make your repayment immediately to avoid additional penalties.',
                          style: const TextStyle(color: CoopvestColors.error, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CoopvestColors.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Late loan repayments may attract a ₦3,000 penalty fee after repeated default notices. '
                            'Continued non-payment beyond three months may trigger guarantor recovery procedures '
                            "in accordance with Coopvest Africa's loan policy.",
                            style: TextStyle(color: CoopvestColors.error, fontSize: 11, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Quick Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Active Loans',
                        '${_quickStats['activeLoans']}',
                        Icons.trending_up,
                        CoopvestColors.success,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Total Borrowed',
                        '\u20a6${(_quickStats['totalBorrowed'] as num).toDouble().toStringAsFixed(0)}',
                        Icons.account_balance,
                        CoopvestColors.primary,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Repaid',
                        '\u20a6${(_quickStats['totalRepaid'] as num).toDouble().toStringAsFixed(0)}',
                        Icons.payments,
                        CoopvestColors.info,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Applications',
                        '${_quickStats['totalLoans']}',
                        Icons.description,
                        Colors.orange,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Loan Eligibility Progress
                LoanEligibilityCard(
                  onApplyTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => LoanApplicationScreen(
                          userId: widget.userId,
                          userName: widget.userName,
                          userPhone: widget.userPhone,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Loan History Section
                Text(
                  'Loan History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                const SizedBox(height: 16),

                // Loan List
                loanState.status == LoanStatus.loading && loans.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : loans.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: loans.length,
                            itemBuilder: (context, index) {
                              final loan = loans[index];
                              return _buildLoanCard(context, loan);
                            },
                          ),

                const SizedBox(height: 24),

                // How It Works Section
                AppCard(
                  backgroundColor: context.secondaryCardBackground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How Our Loans Work',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      _buildHowItWorksStep(1, 'Apply for a loan', context),
                      _buildHowItWorksStep(2, 'Share QR code with 3 guarantors', context),
                      _buildHowItWorksStep(3, 'Guarantors confirm their guarantee', context),
                      _buildHowItWorksStep(4, 'Loan is approved and disbursed', context),
                      _buildHowItWorksStep(5, 'Repay in monthly installments', context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return AppCard(
      onTap: onTap,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(BuildContext context, Loan loan) {
    final statusColor = _getStatusColor(loan.status);
    final loanType = loan.purpose != null ? '${loan.purpose}' : 'Quick Loan';
    // A loan is "gathering guarantors" while pending/under_review and not yet
    // fully consented. This is the in-progress session the borrower can
    // resume (share QR) or cancel.
    final isGatheringGuarantors =
        (loan.status.toLowerCase() == 'pending' ||
            loan.status.toLowerCase() == 'under_review' ||
            loan.status.toLowerCase() == 'pending_guarantors' ||
            loan.status.toLowerCase() == 'awaiting_guarantors') &&
        loan.guarantorsAccepted < loan.guarantorsRequired;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () {
          Navigator.of(context).pushNamed(
            '/loan-details',
            arguments: {'loanId': loan.id},
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loanType,
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      Text(
                        'Loan ID: ${loan.id}',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(loan.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '\u20a6${loan.amount.formatNumber()}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Date',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${loan.createdAt.day}/${loan.createdAt.month}/${loan.createdAt.year}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
            if (isGatheringGuarantors) ...[
              const SizedBox(height: 16),
              _buildGuarantorProgress(loan),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelLoan(loan),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel Application'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CoopvestColors.error,
                        side: BorderSide(color: CoopvestColors.error.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Live guarantor progress indicator: "X of 3 guarantors approved" with a
  /// row of step bars that fill as each guarantor consents. The session stays
  /// visible (and counting) until all required guarantors consent.
  Widget _buildGuarantorProgress(Loan loan) {
    final accepted = loan.guarantorsAccepted;
    final required = loan.guarantorsRequired;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CoopvestColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CoopvestColors.warning.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined, size: 16, color: CoopvestColors.warning),
              const SizedBox(width: 6),
              Text(
                '$accepted of $required guarantors approved',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                required > 0 ? '${((accepted / required) * 100).round()}%' : '0%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CoopvestColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(required, (i) {
              final done = i < accepted;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < required - 1 ? 6 : 0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: done
                          ? CoopvestColors.success
                          : CoopvestColors.lightGray.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            accepted >= required
                ? 'All guarantors approved — awaiting admin review.'
                : 'Share your QR code with ${required - accepted} more guarantor${required - accepted == 1 ? '' : 's'} to continue.',
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'pending_guarantors':
      case 'awaiting_guarantors':
        return 'Awaiting Guarantors';
      case 'under_review':
        return 'Under Review';
      case 'active':
      case 'repaying':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Future<void> _cancelLoan(Loan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Loan Application?'),
        content: Text(
          'This will permanently cancel your loan application (Loan ID: ${loan.id}). '
          'Any guarantor approvals collected so far will be discarded. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Application'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: CoopvestColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Loan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/loans/${loan.id}/cancel', data: {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loan application cancelled.'),
            backgroundColor: CoopvestColors.primary,
          ),
        );
      }
      // Refresh the loans list so the cancelled session disappears.
      ref.read(loanProvider.notifier).getLoans();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel loan: $e'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return AppCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.description_outlined, size: 48, color: context.textSecondary),
              const SizedBox(height: 16),
              Text(
                'No loan applications yet',
                style: TextStyle(color: context.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHowItWorksStep(int step, String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: CoopvestColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: context.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'repaying':
        return CoopvestColors.success;
      case 'pending':
      case 'awaiting_guarantors':
        return CoopvestColors.warning;
      case 'completed':
        return CoopvestColors.info;
      case 'rejected':
      case 'cancelled':
        return CoopvestColors.error;
      default:
        return CoopvestColors.mediumGray;
    }
  }
}
