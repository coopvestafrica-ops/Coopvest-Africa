import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/utils/utils.dart';
import '../../../data/api/loan_api_service.dart';
import '../../../data/models/loan_models.dart';
import '../../../presentation/providers/loan_provider.dart';
import '../../../presentation/widgets/common/buttons.dart';
import '../../../presentation/widgets/common/cards.dart';

/// Fetches the real guarantor list for a loan from the backend
/// (GET /loans/:loanId/guarantors).
final loanGuarantorsProvider =
    FutureProvider.family<List<GuarantorData>, String>((ref, loanId) async {
  final api = ref.watch(loanApiServiceProvider);
  final response = await api.getLoanGuarantors(loanId);
  return response.guarantors;
});

/// Fetches the real repayment schedule for a loan from the backend
/// (GET /loans/:loanId/repayment-schedule).
final loanRepaymentScheduleProvider =
    FutureProvider.family<RepaymentScheduleData, String>((ref, loanId) async {
  final api = ref.watch(loanApiServiceProvider);
  final response = await api.getRepaymentSchedule(loanId);
  return response.schedule;
});

/// Loan Details Screen - View detailed information about a specific loan
class LoanDetailsScreen extends ConsumerWidget {
  final String loanId;

  const LoanDetailsScreen({
    super.key,
    required this.loanId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loanState = ref.watch(loanProvider);
    final now = DateTime.now();
    final loan = loanState.loans.firstWhere(
      (l) => l.id == loanId,
      orElse: () => Loan(
        id: loanId,
        userId: 'demo-user',
        type: 'Personal Loan',
        amount: 50000,
        tenure: 4,
        interestRate: 5.0,
        monthlyRepayment: 13125,
        totalRepayment: 52500,
        status: 'Active',
        purpose: 'Business expansion',
        guarantorsAccepted: 3,
        guarantorsRequired: 3,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 25)),
        approvedAt: now.subtract(const Duration(days: 25)),
        disbursedAt: now.subtract(const Duration(days: 24)),
      ),
    );

    final scheduleAsync = ref.watch(loanRepaymentScheduleProvider(loanId));
    final guarantorsAsync = ref.watch(loanGuarantorsProvider(loanId));

    // Next Payment Due comes from the real repayment schedule: the first
    // unpaid installment. The Loan model's nextRepaymentDate getter is
    // unreliable here because disbursedAt is never populated by the API.
    final nextPaymentDueLabel = scheduleAsync.when(
      loading: () => '...',
      error: (_, __) => 'N/A',
      data: (schedule) {
        final unpaid = schedule.installments
            .where((i) => i.status.toLowerCase() != 'paid')
            .toList();
        if (unpaid.isEmpty) return 'Fully repaid';
        return _formatDate(unpaid.first.dueDate);
      },
    );

    final statusColor = _getStatusColor(loan.status);

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Loan Details',
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                backgroundColor: statusColor.withOpacity(0.1),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          loan.type,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            loan.status,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDetailItem(context, 'Loan ID', loan.id),
                        _buildDetailItem(context, 'Amount', '\u20a6${loan.amount.formatNumber()}'),
                        _buildDetailItem(context, 'Tenure', '${loan.tenure} months'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Repayment Summary',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    _buildSummaryRow(context, 'Monthly Repayment', '\u20a6${loan.monthlyRepayment.formatNumber()}'),
                    Divider(height: 24, color: context.dividerColor),
                    _buildSummaryRow(context, 'Total Repayment', '\u20a6${loan.totalRepayment.formatNumber()}'),
                    Divider(height: 24, color: context.dividerColor),
                    _buildSummaryRow(context, 'Interest Rate', '${loan.interestRate}%'),
                    Divider(height: 24, color: context.dividerColor),
                    _buildSummaryRow(context, 'Next Payment Due', nextPaymentDueLabel),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Repayment Schedule',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              scheduleAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Could not load repayment schedule.',
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(loanRepaymentScheduleProvider(loanId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (schedule) => schedule.installments.isEmpty
                    ? AppCard(
                        child: Center(
                          child: Text(
                            'No repayment schedule available',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ),
                      )
                    : Column(
                        children: schedule.installments
                            .map((installment) => _buildInstallmentCard(context, installment))
                            .toList(),
                      ),
              ),

              const SizedBox(height: 24),

              Text(
                'Guarantors (${loan.guarantorsAccepted}/${loan.guarantorsRequired})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              guarantorsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Could not load guarantors.',
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(loanGuarantorsProvider(loanId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (guarantors) => guarantors.isEmpty
                    ? AppCard(
                        child: Center(
                          child: Text(
                            'No guarantors yet',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ),
                      )
                    : Column(
                        children: guarantors
                            .map((guarantor) => _buildGuarantorCard(context, guarantor))
                            .toList(),
                      ),
              ),

              const SizedBox(height: 32),

              // Standard Policy Notice (Loan Policy §5.2)
              if (loan.status.toLowerCase() == 'overdue' || loan.status.toLowerCase() == 'in_recovery') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CoopvestColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CoopvestColors.error.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: CoopvestColors.error, size: 20),
                          const SizedBox(width: 8),
                          Text('Overdue Status', style: TextStyle(fontWeight: FontWeight.bold, color: CoopvestColors.error, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Late loan repayments may attract a ₦3,000 penalty fee after repeated default notices. '
                        'Continued non-payment beyond three months may trigger guarantor recovery procedures '
                        'in accordance with Coopvest Africa\'s loan policy.',
                        style: TextStyle(color: CoopvestColors.error, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CoopvestColors.warning.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CoopvestColors.warning.withOpacity(0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: CoopvestColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Late loan repayments may attract a ₦3,000 penalty fee after repeated default notices. '
                          'Continued non-payment beyond three months may trigger guarantor recovery procedures '
                          'in accordance with Coopvest Africa\'s loan policy.',
                          style: TextStyle(color: CoopvestColors.warning, fontSize: 11, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (loan.status == 'Active' || loan.status == 'Repaying')
                PrimaryButton(
                  label: 'Make Repayment',
                  onPressed: () {},
                  width: double.infinity,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
      ],
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: context.textSecondary)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
      ],
    );
  }

  Widget _buildInstallmentCard(BuildContext context, RepaymentInstallment installment) {
    final statusColor = _getInstallmentStatusColor(installment.status);
    final statusLabel = installment.status.isEmpty
        ? ''
        : installment.status[0].toUpperCase() + installment.status.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${installment.installmentNumber}',
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u20a6${installment.amount.formatNumber()}', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                  Text('Due: ${_formatDate(installment.dueDate)}', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuarantorCard(BuildContext context, GuarantorData guarantor) {
    final confirmed = const ['consented', 'confirmed', 'accepted', 'active']
        .contains(guarantor.status.toLowerCase());
    final statusLabel = confirmed ? 'Confirmed' : 'Pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: CoopvestColors.primary.withOpacity(0.1),
              child: const Icon(Icons.person, color: CoopvestColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guarantor.name, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                  Text(
                    guarantor.phone.isNotEmpty ? guarantor.phone : statusLabel,
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              confirmed ? Icons.check_circle : Icons.schedule,
              color: confirmed ? CoopvestColors.success : CoopvestColors.warning,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'repaying':
        return CoopvestColors.success;
      case 'pending':
        return CoopvestColors.warning;
      case 'overdue':
        return CoopvestColors.error;
      default:
        return CoopvestColors.mediumGray;
    }
  }

  Color _getInstallmentStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return CoopvestColors.success;
      case 'due':
        return CoopvestColors.warning;
      case 'missed':
      case 'overdue':
        return CoopvestColors.error;
      case 'upcoming':
        return CoopvestColors.primary;
      default:
        return CoopvestColors.mediumGray;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }
}
