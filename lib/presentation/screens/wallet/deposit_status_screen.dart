import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../data/models/wallet_models.dart';
import '../../../presentation/providers/deposit_history_provider.dart';

/// Deposit Status Tracker Screen
///
/// Shows the user all their deposit requests with a live status timeline —
/// Submitted → Under Review → Verified / Rejected — plus admin notes.
class DepositStatusScreen extends ConsumerStatefulWidget {
  const DepositStatusScreen({super.key});

  @override
  ConsumerState<DepositStatusScreen> createState() => _DepositStatusScreenState();
}

class _DepositStatusScreenState extends ConsumerState<DepositStatusScreen> {
  String _filter = 'all'; // all | pending | verified | rejected

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(depositHistoryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(depositHistoryProvider);

    final filtered = _filter == 'all'
        ? state.requests
        : state.requests.where((r) => r.status == _filter).toList();

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: context.scaffoldBackground,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'My Deposits',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: CoopvestColors.primary),
            onPressed: () => ref.read(depositHistoryProvider.notifier).load(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context),
          Expanded(
            child: state.isLoading && state.requests.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: CoopvestColors.primary),
                  )
                : state.error != null && state.requests.isEmpty
                    ? _buildError(context, state.error!)
                    : filtered.isEmpty
                        ? _buildEmpty(context)
                        : RefreshIndicator(
                            onRefresh: () => ref.read(depositHistoryProvider.notifier).load(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => _buildCard(ctx, filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  // ── Filter chip bar ───────────────────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context) {
    final filters = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('verified', 'Verified'),
      ('rejected', 'Rejected'),
    ];

    return Container(
      height: 48,
      color: context.scaffoldBackground,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((f) {
          final selected = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f.$1),
              selectedColor: CoopvestColors.primary.withOpacity(0.15),
              checkmarkColor: CoopvestColors.primary,
              labelStyle: TextStyle(
                color: selected ? CoopvestColors.primary : context.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
              side: BorderSide(
                color: selected ? CoopvestColors.primary : context.dividerColor,
              ),
              backgroundColor: context.cardBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Deposit card ──────────────────────────────────────────────────────────────

  Widget _buildCard(BuildContext context, DepositRequest req) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          _buildCardHeader(context, req),
          const Divider(height: 1),
          // Status timeline
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: _buildTimeline(context, req),
          ),
          // Admin notes (rejection reason)
          if (req.adminNotes != null && req.adminNotes!.isNotEmpty)
            _buildAdminNote(context, req),
          // Proof thumbnail
          if (req.paymentProofUrl != null && req.paymentProofUrl!.isNotEmpty)
            _buildProofRow(context, req.paymentProofUrl!),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCardHeader(BuildContext context, DepositRequest req) {
    final statusColor = _statusColor(req.status);
    final statusIcon  = _statusIcon(req.status);
    final statusLabel = _statusLabel(req.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₦${req.amount.formatNumber()}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(req.createdAt.toLocal()),
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status timeline ───────────────────────────────────────────────────────────

  Widget _buildTimeline(BuildContext context, DepositRequest req) {
    final steps = _timelineSteps(req);
    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isLast = i == steps.length - 1;
        return _buildTimelineRow(context, step, isLast);
      }),
    );
  }

  Widget _buildTimelineRow(
    BuildContext context,
    _TimelineStep step,
    bool isLast,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: dot + connector
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.done
                        ? (step.color ?? CoopvestColors.primary)
                        : context.dividerColor,
                    border: Border.all(
                      color: step.done
                          ? (step.color ?? CoopvestColors.primary)
                          : context.dividerColor,
                      width: 2,
                    ),
                  ),
                  child: step.done
                      ? Icon(
                          step.color == CoopvestColors.error
                              ? Icons.close
                              : Icons.check,
                          size: 8,
                          color: Colors.white,
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 2),
                      color: step.done ? context.dividerColor : context.dividerColor.withOpacity(0.4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right: label + timestamp
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontWeight: step.done ? FontWeight.w600 : FontWeight.normal,
                      color: step.done ? context.textPrimary : context.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (step.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle!,
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_TimelineStep> _timelineSteps(DepositRequest req) {
    final fmtDate = (DateTime? dt) => dt == null
        ? null
        : DateFormat('dd MMM, hh:mm a').format(dt.toLocal());

    final submittedAt = fmtDate(req.createdAt);
    final verifiedAtStr = fmtDate(req.verifiedAt);

    if (req.isRejected) {
      return [
        _TimelineStep(
          label: 'Submitted',
          subtitle: submittedAt,
          done: true,
        ),
        _TimelineStep(
          label: 'Under Review',
          subtitle: 'Admin reviewed your deposit',
          done: true,
        ),
        _TimelineStep(
          label: 'Not Approved',
          subtitle: verifiedAtStr ?? 'Rejected',
          done: true,
          color: CoopvestColors.error,
        ),
      ];
    }

    if (req.isVerified) {
      return [
        _TimelineStep(
          label: 'Submitted',
          subtitle: submittedAt,
          done: true,
        ),
        _TimelineStep(
          label: 'Under Review',
          subtitle: 'Admin reviewed your deposit',
          done: true,
        ),
        _TimelineStep(
          label: 'Verified — Wallet Credited',
          subtitle: verifiedAtStr,
          done: true,
          color: CoopvestColors.success,
        ),
      ];
    }

    // pending
    return [
      _TimelineStep(
        label: 'Submitted',
        subtitle: submittedAt,
        done: true,
      ),
      _TimelineStep(
        label: 'Under Review',
        subtitle: 'Awaiting admin verification',
        done: false,
      ),
      _TimelineStep(
        label: 'Wallet Credit',
        subtitle: 'Will be credited once verified',
        done: false,
      ),
    ];
  }

  // ── Admin note ────────────────────────────────────────────────────────────────

  Widget _buildAdminNote(BuildContext context, DepositRequest req) {
    final isRejection = req.isRejected;
    final color = isRejection ? CoopvestColors.error : CoopvestColors.info;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRejection ? Icons.info_outline : Icons.comment_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRejection ? 'Reason for rejection' : 'Admin note',
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  req.adminNotes!,
                  style: TextStyle(fontSize: 13, color: context.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Proof thumbnail ───────────────────────────────────────────────────────────

  Widget _buildProofRow(BuildContext context, String url) {
    return GestureDetector(
      onTap: () => _showProofFull(context, url),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.dividerColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image, color: context.textSecondary),
                ),
              ),
              Positioned(
                bottom: 6, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'View proof',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProofFull(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty / Error ─────────────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64,
              color: context.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            _filter == 'all' ? 'No deposits yet' : 'No $_filter deposits',
            style: TextStyle(
              fontSize: 16,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your deposit history will appear here.',
            style: TextStyle(fontSize: 13, color: context.textSecondary.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: CoopvestColors.error),
            const SizedBox(height: 12),
            Text(
              'Could not load deposits',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(error, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.read(depositHistoryProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: CoopvestColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':   return CoopvestColors.success;
      case 'rejected':   return CoopvestColors.error;
      case 'cancelled':  return CoopvestColors.error;
      default:           return CoopvestColors.warning;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'verified':   return Icons.check_circle_outline;
      case 'rejected':   return Icons.cancel_outlined;
      case 'cancelled':  return Icons.cancel_outlined;
      default:           return Icons.hourglass_empty;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'verified':   return 'Verified';
      case 'rejected':   return 'Rejected';
      case 'cancelled':  return 'Cancelled';
      default:           return 'Pending';
    }
  }
}

// ── Internal data class ───────────────────────────────────────────────────────

class _TimelineStep {
  final String label;
  final String? subtitle;
  final bool done;
  final Color? color;

  const _TimelineStep({
    required this.label,
    this.subtitle,
    required this.done,
    this.color,
  });
}
