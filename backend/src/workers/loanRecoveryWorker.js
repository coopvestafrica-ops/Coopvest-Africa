/**
 * Loan Recovery Worker — Coopvest Africa Loan Policy (Section 4.1)
 *
 * Runs daily to enforce the 3-stage loan recovery process:
 *
 *   Stage 1 — 1st missed month:
 *     Automated repayment reminders sent via email and in-app notifications.
 *
 *   Stage 2 — 2nd consecutive missed month:
 *     A ₦3,000 late repayment charge is applied to the outstanding balance.
 *     An escalation notice is issued to the borrower.
 *     Admin is notified of the default status.
 *
 *   Stage 3 — 3rd consecutive missed month:
 *     Guarantors are contacted. Loan recovery process is initiated.
 *     Admin dashboard is alerted. Additional recovery actions apply.
 *
 * NOTE: The ₦3,000 penalty is NOT applied on the first missed payment.
 * It is applied only after the 2nd consecutive missed month.
 */

const supabase = require('../config/supabase');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');

const POLL_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours
const LATE_REPAYMENT_PENALTY_NGN = 3000;

/**
 * Return how many consecutive months have been missed for a loan.
 * Looks at missed_months column on the loan record if available,
 * or falls back to counting unpaid installments past their due date.
 */
function getConsecutiveMissedMonths(loan) {
  // Use server-tracked missed_months if available
  if (typeof loan.missed_months === 'number') return loan.missed_months;
  // Fallback: estimate from last_repayment_date vs today.
  // `disbursed_at` doesn't exist on the loans table; `approved_at` is the
  // closest actual populated timestamp for when the loan started.
  const disbursedAtValue = loan.disbursed_at || loan.approved_at;
  if (!disbursedAtValue) return 0;
  const disbursed = new Date(disbursedAtValue);
  const now = new Date();
  const monthsSinceDisbursed =
    (now.getFullYear() - disbursed.getFullYear()) * 12 +
    (now.getMonth() - disbursed.getMonth());
  const expectedPayments = Math.min(monthsSinceDisbursed, loan.tenure_months || loan.tenure || 0);
  const paidPayments = loan.payments_made || 0;
  return Math.max(0, expectedPayments - paidPayments);
}

async function notifyAdminOfDefault(loan, stage) {
  try {
    // Find admin profiles
    const { data: admins } = await supabase
      .from('profiles')
      .select('id')
      .eq('role', 'admin');

    if (!admins || admins.length === 0) return;

    await notifyService.broadcast({
      profileIds: admins.map((a) => a.id),
      channels: ['in_app', 'email'],
      title: `⚠️ Loan Default Alert — Stage ${stage}`,
      body: `Loan ${loan.loan_id || loan.id} is in Stage ${stage} default. Borrower profile: ${loan.profile_id}. Amount overdue: ₦${(loan.amount || 0).toLocaleString()}.`,
    });
  } catch (err) {
    logger.warn('loanRecoveryWorker: admin notification failed:', err.message);
  }
}

async function notifyGuarantors(loan) {
  try {
    // Fetch guarantors for this loan
    const { data: guarantors } = await supabase
      .from('loan_guarantors')
      .select('guarantor_profile_id, guarantor_name')
      .eq('loan_id', loan.id)
      .eq('status', 'accepted');

    if (!guarantors || guarantors.length === 0) return;

    for (const g of guarantors) {
      await notifyService.sendInApp({
        profileId: g.guarantor_profile_id,
        title: '⚠️ Loan Recovery Notice',
        body: `A loan you guaranteed is now 3 months overdue. As a guarantor, you may be contacted as part of Coopvest Africa's loan recovery process in accordance with the loan policy you accepted.`,
        type: 'loan_recovery',
        category: 'warning',
        priority: 'high',
      });
    }

    logger.info(`loanRecoveryWorker: guarantors notified for loan ${loan.loan_id || loan.id}`);
  } catch (err) {
    logger.warn('loanRecoveryWorker: guarantor notification failed:', err.message);
  }
}

async function processDue() {
  try {
    // Fetch all active/repaying loans
    // NOTE: `disbursed_at` does not exist on the loans table (only
    // `disbursed_by` does) — filtering on it caused PostgREST to 400 on
    // every run. `approved_at` is the actual populated timestamp marking
    // when a loan started, and the status filter already restricts us to
    // live loans, so we use that instead.
    const { data: activeLoans, error } = await supabase
      .from('loans')
      .select('*')
      .in('status', ['active', 'repaying', 'overdue'])
      .not('approved_at', 'is', null);

    if (error) throw error;
    if (!activeLoans || activeLoans.length === 0) return;

    for (const loan of activeLoans) {
      try {
        const missedMonths = getConsecutiveMissedMonths(loan);

        if (missedMonths <= 0) continue; // No missed payments — nothing to do

        const profileId = loan.profile_id;

        // ── STAGE 1: 1st missed month — send reminder ─────────────────────
        if (missedMonths === 1) {
          await notifyService.broadcast({
            profileIds: [profileId],
            channels: ['in_app', 'email'],
            title: 'Loan Repayment Reminder',
            body: `Your loan repayment is overdue. Please make your payment to avoid late fees. Late loan repayments may attract a ₦3,000 penalty fee after repeated default notices.`,
          });

          // Mark status as overdue if not already
          if (loan.status !== 'overdue') {
            await supabase
              .from('loans')
              .update({ status: 'overdue', updated_at: new Date().toISOString() })
              .eq('id', loan.id);
          }

          logger.info(`loanRecoveryWorker: Stage 1 reminder sent — loan ${loan.loan_id || loan.id}`);
        }

        // ── STAGE 2: 2nd consecutive missed month — apply ₦3,000 penalty ──
        else if (missedMonths === 2) {
          // Apply the ₦3,000 late repayment charge
          const newBalance = (loan.outstanding_balance || loan.amount || 0) + LATE_REPAYMENT_PENALTY_NGN;

          await supabase
            .from('loans')
            .update({
              outstanding_balance: newBalance,
              penalty_applied: true,
              penalty_amount: (loan.penalty_amount || 0) + LATE_REPAYMENT_PENALTY_NGN,
              status: 'overdue',
              updated_at: new Date().toISOString(),
            })
            .eq('id', loan.id);

          // Notify borrower of penalty
          await notifyService.broadcast({
            profileIds: [profileId],
            channels: ['in_app', 'email'],
            title: '⚠️ Late Repayment Penalty Applied',
            body: `A ₦3,000 late repayment charge has been added to your loan balance due to 2 consecutive missed payments. Your new outstanding balance is ₦${newBalance.toLocaleString()}. Please arrange a repayment plan immediately.`,
          });

          // Notify admin
          await notifyAdminOfDefault(loan, 2);

          logger.info(`loanRecoveryWorker: Stage 2 penalty applied — loan ${loan.loan_id || loan.id}, new balance ₦${newBalance}`);
        }

        // ── STAGE 3: 3rd+ consecutive missed month — contact guarantors ───
        else if (missedMonths >= 3) {
          // Contact guarantors
          await notifyGuarantors(loan);

          // Mark loan as in recovery
          await supabase
            .from('loans')
            .update({
              status: 'in_recovery',
              recovery_initiated_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            })
            .eq('id', loan.id)
            .neq('status', 'in_recovery'); // Only update once

          // Notify borrower
          await notifyService.broadcast({
            profileIds: [profileId],
            channels: ['in_app', 'email'],
            title: '🚨 Loan Recovery Initiated',
            body: `Your loan has been overdue for 3 consecutive months. The loan recovery process has been initiated and your guarantors have been contacted in accordance with Coopvest Africa's loan policy. Please contact us immediately to resolve this.`,
          });

          // Notify admin
          await notifyAdminOfDefault(loan, 3);

          logger.info(`loanRecoveryWorker: Stage 3 recovery initiated — loan ${loan.loan_id || loan.id}`);
        }
      } catch (loanErr) {
        logger.warn(`loanRecoveryWorker: failed to process loan ${loan.id}:`, loanErr.message);
      }
    }
  } catch (err) {
    logger.warn('loanRecoveryWorker: tick failed:', err.message);
  }
}

function start() {
  if (process.env.LOAN_RECOVERY_DISABLED === '1') {
    logger.info('loanRecoveryWorker: disabled via env');
    return null;
  }
  logger.info('loanRecoveryWorker: started (poll every 24h)');
  const handle = setInterval(processDue, POLL_INTERVAL_MS);
  // Run once shortly after startup (5 min delay to let server fully initialize)
  setTimeout(() => processDue().catch(() => {}), 5 * 60 * 1000);
  return handle;
}

module.exports = { start, processDue };
