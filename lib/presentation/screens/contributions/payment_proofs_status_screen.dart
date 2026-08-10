import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../../data/api/payment_proof_api_service.dart';
import '../../../data/models/payment_proof_model.dart';
import '../../widgets/common/buttons.dart';

/// My Payment Proofs
///
/// Lets a member see the verification status of every payment proof they have
/// submitted (pending / under review / approved / rejected), open the proof
/// file, cancel a pending proof, and view the digital receipt once a proof is
/// approved.
class PaymentProofsStatusScreen extends ConsumerStatefulWidget {
  const PaymentProofsStatusScreen({super.key});

  @override
  ConsumerState<PaymentProofsStatusScreen> createState() =>
      _PaymentProofsStatusScreenState();
}

class _PaymentProofsStatusScreenState
    extends ConsumerState<PaymentProofsStatusScreen> {
  final ScrollController _scrollController = ScrollController();

  late final PaymentProofApiService _service;

  List<PaymentProof> _proofs = [];
  PaymentProofSummary? _summary;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String? _errorMessage;
  int _page = 1;
  bool _hasMore = true;
  PaymentProofStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    final apiClient = ref.read(apiClientProvider);
    _service = PaymentProofApiService(apiClient.dio);
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _service.getPaymentProofs(page: 1, status: _statusFilter),
        _service.getPaymentProofSummary(),
      ]);
      final list = results[0] as PaymentProofListResponse;
      final summary = results[1] as PaymentProofSummary;
      setState(() {
        _proofs = list.paymentProofs;
        _summary = summary;
        _page = 1;
        _hasMore = list.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final next = _page + 1;
      final list =
          await _service.getPaymentProofs(page: next, status: _statusFilter);
      setState(() {
        _proofs.addAll(list.paymentProofs);
        _page = next;
        _hasMore = list.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      setState(() => _isLoadingMore = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Failed host')) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'We could not load your payment proofs. Pull to refresh.';
  }

  Future<void> _cancelProof(PaymentProof proof) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel submission?'),
        content: Text(
          'This will delete your ${proof.paymentType.displayName.toLowerCase()} proof of '
          '${proof.amount.toStringAsFixed(2)} ${proof.currency}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: CoopvestColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel proof'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.cancelPaymentProof(proof.id);
      setState(() => _proofs.removeWhere((p) => p.id == proof.id));
      await _refreshSummary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment proof cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _refreshSummary() async {
    try {
      final summary = await _service.getPaymentProofSummary();
      setState(() => _summary = summary);
    } catch (_) {
      // summary is non-blocking
    }
  }

  void _openReceipt(PaymentProof proof) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Loading receipt…'),
            ],
          ),
        ),
      ),
    );
    try {
      final receipt = await _service.getReceipt(proof.id);
      Navigator.pop(context); // dismiss loader
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ReceiptView(proof: proof, receipt: receipt),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // dismiss loader
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt not available: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        title: const Text('My Payment Proofs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadInitial,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PaymentProofUploadScreen(),
          ),
        ).then((_) => _loadInitial()),
        icon: const Icon(Icons.add),
        label: const Text('New proof'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return ListView(
        // keep scrollable so RefreshIndicator works
        children: [
          const SizedBox(height: 120),
          _ErrorState(message: _errorMessage!, onRetry: _loadInitial),
        ],
      );
    }
    if (_proofs.isEmpty && _summary == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          _EmptyState(onSubmit: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentProofUploadScreen()),
          ).then((_) => _loadInitial())),
        ],
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (_summary != null) _buildSummary(_summary!),
        const SizedBox(height: 8),
        _buildFilterChips(),
        const SizedBox(height: 8),
        if (_proofs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'No payment proofs match this filter.',
                style: TextStyle(color: CoopvestColors.textSecondary),
              ),
            ),
          )
        else
          ..._proofs.map(_buildProofCard),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildSummary(PaymentProofSummary s) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: CoopvestColors.primary.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verification summary',
              style: TextStyle(
                color: CoopvestColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _summaryTile('Pending', s.pending, CoopvestColors.warning)),
                const SizedBox(width: 8),
                Expanded(child: _summaryTile('Approved', s.approved, CoopvestColors.success)),
                const SizedBox(width: 8),
                Expanded(child: _summaryTile('Rejected', s.rejected, CoopvestColors.error)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _summaryTile('Under review', s.underReview, CoopvestColors.info),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _summaryTile(
                    'Approved amount',
                    null,
                    CoopvestColors.success,
                    amount: '₦${s.approvedAmount.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String label, int? count, Color color, {String? amount}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            amount ?? (count?.toString() ?? '0'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final chips = <(String, PaymentProofStatus?, Color)>[
      ('All', null, CoopvestColors.primary),
      ('Pending', PaymentProofStatus.pending, CoopvestColors.warning),
      ('Under review', PaymentProofStatus.underReview, CoopvestColors.info),
      ('Approved', PaymentProofStatus.approved, CoopvestColors.success),
      ('Rejected', PaymentProofStatus.rejected, CoopvestColors.error),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, status, color) = chips[i];
          final selected = _statusFilter == status;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            selectedColor: color.withOpacity(0.2),
            labelStyle: TextStyle(
              color: selected ? color : CoopvestColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
            onSelected: (_) {
              setState(() => _statusFilter = status);
              _loadInitial();
            },
          );
        },
      ),
    );
  }

  Widget _buildProofCard(PaymentProof proof) {
    final statusColor = _statusColor(proof.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_statusIcon(proof.status), color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proof.paymentType.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(proof.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: CoopvestColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(proof.status, statusColor),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _detail('Amount',
                      '₦${proof.amount.toStringAsFixed(2)} ${proof.currency}'),
                ),
                Expanded(
                  child: _detail('Payment date', _formatDate(proof.paymentDate)),
                ),
              ],
            ),
            if (proof.transactionReference != null) ...[
              const SizedBox(height: 8),
              _detail('Reference', proof.transactionReference!),
            ],
            if (proof.receivingBank != null) ...[
              const SizedBox(height: 8),
              _detail('Receiving bank', proof.receivingBank!),
            ],
            if (proof.status == PaymentProofStatus.rejected &&
                proof.rejectionReason != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CoopvestColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reason for rejection',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: CoopvestColors.error,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      proof.rejectionReason!,
                      style: const TextStyle(color: CoopvestColors.error),
                    ),
                  ],
                ),
              ),
            ],
            if (proof.adminNotes != null &&
                proof.adminNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detail('Admin note', proof.adminNotes!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (proof.proofUrl != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View proof'),
                      onPressed: () => _showProofImage(proof),
                    ),
                  ),
                if (proof.proofUrl != null &&
                    proof.status == PaymentProofStatus.approved)
                  const SizedBox(width: 8),
                if (proof.status == PaymentProofStatus.approved)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CoopvestColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Receipt'),
                      onPressed: () => _openReceipt(proof),
                    ),
                  ),
                if (proof.proofUrl == null &&
                    proof.status != PaymentProofStatus.approved)
                  const Expanded(
                    child: Text(
                      'No proof file attached',
                      style: TextStyle(
                        color: CoopvestColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (proof.status == PaymentProofStatus.pending) ...[
                  if (proof.proofUrl != null) const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Cancel submission',
                    icon: const Icon(Icons.delete_outline,
                        color: CoopvestColors.error),
                    onPressed: () => _cancelProof(proof),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: CoopvestColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _statusBadge(PaymentProofStatus status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusColor(PaymentProofStatus status) {
    switch (status) {
      case PaymentProofStatus.pending:
        return CoopvestColors.warning;
      case PaymentProofStatus.underReview:
        return CoopvestColors.info;
      case PaymentProofStatus.approved:
        return CoopvestColors.success;
      case PaymentProofStatus.rejected:
        return CoopvestColors.error;
    }
  }

  IconData _statusIcon(PaymentProofStatus status) {
    switch (status) {
      case PaymentProofStatus.pending:
        return Icons.hourglass_top;
      case PaymentProofStatus.underReview:
        return Icons.visibility;
      case PaymentProofStatus.approved:
        return Icons.verified;
      case PaymentProofStatus.rejected:
        return Icons.cancel;
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _showProofImage(PaymentProof proof) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ProofImageViewer(
          url: proof.proofUrl!,
          title: proof.paymentType.displayName,
        ),
      ),
    );
  }
}

class _ReceiptView extends StatelessWidget {
  final PaymentProof proof;
  final DigitalReceipt receipt;

  const _ReceiptView({required this.proof, required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoopvestColors.scaffoldBackground,
      appBar: AppBar(title: const Text('Digital Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: CoopvestColors.primary.withOpacity(0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: CoopvestColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Payment Verified',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: CoopvestColors.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  receipt.receiptNumber,
                  style: const TextStyle(
                    color: CoopvestColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                const Divider(height: 32),
                _receiptRow('Member', receipt.memberName ?? '—'),
                if (receipt.membershipId != null)
                  _receiptRow('Membership ID', receipt.membershipId!),
                _receiptRow('Payment type',
                    receipt.paymentType ?? proof.paymentType.displayName),
                _receiptRow(
                    'Amount', '₦${receipt.amount.toStringAsFixed(2)} ${receipt.currency}'),
                if (receipt.transactionReference != null)
                  _receiptRow('Reference', receipt.transactionReference!),
                if (receipt.receivingBank != null)
                  _receiptRow('Receiving bank', receipt.receivingBank!),
                if (receipt.paymentDate != null)
                  _receiptRow('Payment date', _fmt(receipt.paymentDate!)),
                if (receipt.approvedByName != null)
                  _receiptRow('Approved by', receipt.approvedByName!),
                if (receipt.approvedAt != null)
                  _receiptRow('Approved on', _fmt(receipt.approvedAt!)),
                if (receipt.organizationName != null)
                  _receiptRow('Organization', receipt.organizationName!),
                if (receipt.verificationHash != null) ...[
                  const Divider(height: 32),
                  _receiptRow('Verification hash', receipt.verificationHash!,
                      mono: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: CoopvestColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: mono ? const TextStyle(fontFamily: 'monospace') : null,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _ProofImageViewer extends StatelessWidget {
  final String url;
  final String title;

  const _ProofImageViewer({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            url,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return CircularProgressIndicator(
                value: progress.cumulativeBytesLoaded /
                    (progress.expectedTotalBytes ?? 1),
              );
            },
            errorBuilder: (_, __, ___) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 64, color: Colors.white54),
                SizedBox(height: 12),
                Text(
                  'Could not load proof image',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSubmit;
  const _EmptyState({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.receipt_long_outlined,
          size: 72,
          color: CoopvestColors.primary.withOpacity(0.4),
        ),
        const SizedBox(height: 16),
        const Text(
          'No payment proofs yet',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'When you submit proof of a payment, it will appear here with its '
          'verification status and digital receipt.',
          textAlign: TextAlign.center,
          style: TextStyle(color: CoopvestColors.textSecondary),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Submit a proof',
          icon: const Icon(Icons.add),
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 64, color: CoopvestColors.error),
        const SizedBox(height: 16),
        const Text(
          'Something went wrong',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: CoopvestColors.textSecondary),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Try again',
          icon: const Icon(Icons.refresh),
          onPressed: onRetry,
        ),
      ],
    );
  }
}
