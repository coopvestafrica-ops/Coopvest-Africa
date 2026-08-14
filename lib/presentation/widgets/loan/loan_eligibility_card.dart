import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_config.dart';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../widgets/common/feature_gate.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/loan_provider.dart';
import '../../../presentation/providers/wallet_provider.dart';

/// Loan eligibility progress card.
/// Shows how many months of contributions a member has vs. the 6-month
/// requirement, with a circular arc progress indicator, a live max-loan
/// calculation once eligible, and a contextual CTA.
class LoanEligibilityCard extends ConsumerWidget {
  /// When true the card navigates to the loan dashboard on tap.
  final VoidCallback? onApplyTap;

  const LoanEligibilityCard({super.key, this.onApplyTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final loanNotifier = ref.read(loanProvider.notifier);
    // Honour the admin-controlled "Loan Requests" toggle (Mobile App Content
    // Control). When disabled, the Apply button is hidden so toggles actually
    // take effect on the mobile app.
    final featureService = ref.read(featureServiceProvider);
    final loansEnabled = featureService.isEnabled('loan_requests');

    final monthsDone = user?.membershipDurationMonths ?? 0;
    final monthsRequired = AppConfig.loanEligibilityMonths;
    final monthsLeft = (monthsRequired - monthsDone).clamp(0, monthsRequired);
    final progress = (monthsDone / monthsRequired).clamp(0.0, 1.0);
    final isEligible = monthsDone >= monthsRequired;

    final totalSavings = walletState.wallet?.totalContributions ?? 0.0;
    final maxLoan = loanNotifier.calculateMaxLoanAmount(totalSavings);

    final primaryColor = isEligible ? CoopvestColors.success : CoopvestColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.08),
            primaryColor.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withOpacity(0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEligible
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loan Eligibility',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEligible
                          ? 'You qualify for a loan!'
                          : '$monthsLeft month${monthsLeft == 1 ? '' : 's'} left to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        color: isEligible
                            ? CoopvestColors.success
                            : context.textSecondary,
                        fontWeight: isEligible
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              // Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isEligible ? 'Eligible' : 'In Progress',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Progress Row ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circular arc progress
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(90, 90),
                      painter: _ArcProgressPainter(
                        progress: progress,
                        trackColor: primaryColor.withOpacity(0.12),
                        progressColor: primaryColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$monthsDone',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'of $monthsRequired',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                        Text(
                          'months',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // Right-side details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Months milestone pills
                    _MilestonePills(
                      monthsDone: monthsDone,
                      monthsRequired: monthsRequired,
                      color: primaryColor,
                    ),

                    const SizedBox(height: 14),

                    if (isEligible) ...[
                      // Max loan callout
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: CoopvestColors.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CoopvestColors.success.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Max loan available',
                              style: TextStyle(
                                fontSize: 10,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              totalSavings > 0
                                  ? '₦${maxLoan.formatNumber()}'
                                  : 'Based on savings',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: CoopvestColors.success,
                              ),
                            ),
                            if (totalSavings > 0)
                              Text(
                                '3× your ₦${totalSavings.formatNumber()} savings',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // What happens when eligible
                      Text(
                        'When eligible:',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _BulletRow(
                        icon: Icons.bolt_rounded,
                        color: CoopvestColors.primary,
                        label: 'Borrow up to 3× your savings',
                      ),
                      const SizedBox(height: 4),
                      _BulletRow(
                        icon: Icons.calendar_month_rounded,
                        color: CoopvestColors.primary,
                        label: 'Flexible repayment tenures',
                      ),
                      const SizedBox(height: 4),
                      _BulletRow(
                        icon: Icons.groups_rounded,
                        color: CoopvestColors.primary,
                        label: 'Guaranteed by 3 co-members',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Linear progress bar ──────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Contribution months progress',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: primaryColor.withOpacity(0.1),
                  color: primaryColor,
                  minHeight: 8,
                ),
              ),
            ],
          ),

          // ── CTA ──────────────────────────────────────────────────────────
          if (isEligible && loansEnabled && onApplyTap != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onApplyTap,
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Apply for a Loan Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoopvestColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ] else if (isEligible && !loansEnabled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CoopvestColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CoopvestColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: CoopvestColors.warning),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Loan applications are temporarily disabled by the administrator.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Month milestone pills (circles 1-6 with done/pending state)
// ──────────────────────────────────────────────────────────────────────────────
class _MilestonePills extends StatelessWidget {
  final int monthsDone;
  final int monthsRequired;
  final Color color;

  const _MilestonePills({
    required this.monthsDone,
    required this.monthsRequired,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(monthsRequired, (i) {
        final done = i < monthsDone;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? color : color.withOpacity(0.1),
                    border: Border.all(
                      color: done ? color : color.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, color: Colors.white, size: 13)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color.withOpacity(0.5),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small bullet row for "when eligible" section
// ──────────────────────────────────────────────────────────────────────────────
class _BulletRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _BulletRow(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Custom arc painter (240° sweep, starting bottom-left)
// ──────────────────────────────────────────────────────────────────────────────
class _ArcProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  const _ArcProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const startAngle = 150 * (pi / 180);
    const sweepDegrees = 240.0;
    const sweepAngle = sweepDegrees * (pi / 180);

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcProgressPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}
