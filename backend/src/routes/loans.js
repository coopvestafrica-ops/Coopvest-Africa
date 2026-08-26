/**
 * Loans Routes
 *
 * All data is persisted in Supabase (`loans`, `loan_qrs`). Routes rely on
 * Supabase Auth JWT via the `authenticate` middleware, which resolves the
 * acting user's profile row.
 */

const express = require('express');
const { body, param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const { verifyLoanOwnership } = require('../middleware/ownership');
const referralService = require('../services/referralService');
const qrCodeService = require('../services/qrCodeService');
const loanPolicy = require('../lib/loanPolicy');
const logger = require('../utils/logger');

const ADMIN_ROLES = ['admin', 'superadmin', 'super_admin', 'staff'];
const AGREEMENT_VERSION = 'v1.0';

const LOAN_TYPES = [
  // Mobile app loan types
  'Quick Loan',
  'Flexi Loan',
  'Stable Loan (12 months)',
  'Stable Loan (18 months)',
  'Premium Loan',
  'Maxi Loan',
  // Legacy types
  'Micro Loan',
  'Business Loan',
  'Emergency Loan',
];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Resolve a loanId param to the canonical UUID (loans.id).
 * Accepts a bare UUID (passthrough) or a text loan reference stored in
 * loans.loan_id. Returns the UUID string, or null if not found.
 */
async function resolveLoanUuid(rawId) {
  const id = (rawId || '').trim();
  if (!id) return null;
  if (UUID_RE.test(id)) return id;
  try {
    const { data, error } = await supabase
      .from('loans')
      .select('id')
      .eq('loan_id', id)
      .maybeSingle();
    if (error) throw error;
    return data ? data.id : null;
  } catch (err) {
    logger.error('resolveLoanUuid error:', err.message);
    return null;
  }
}

const auditLog = async (actorId, action, targetId, metadata = {}) => {
  try {
    await supabase.from('audit_logs').insert({
      actor_id: actorId,
      action,
      target_model: 'Loan',
      target_id: targetId,
      metadata,
    });
  } catch (err) {
    logger.warn('audit_logs insert failed:', err.message);
  }
};

const newLoanId = () => `LN-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

/**
 * POST /api/v1/loans/apply
 */
router.post(
  '/apply',
  authenticate,
  [
    body('loanType').isIn(LOAN_TYPES),
    body('amount').isFloat({ min: 1 }),
    body('tenureMonths').isInt({ min: 1, max: 60 }),
    body('purpose').optional().isString().isLength({ max: 500 }),
    body('applyReferralBonus').optional().isBoolean(),
    body('agreementAccepted').isBoolean(),
    body('agreementVersion').optional().isString().isLength({ max: 20 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { loanType, amount, tenureMonths, purpose, applyReferralBonus, agreementAccepted, agreementVersion } = req.body;
      const profileId = req.user.id;

      // ── Digital loan agreement (Policy §2.2) ──────────────────────────────
      if (agreementAccepted !== true) {
        return res.status(400).json({
          success: false,
          code: 'AGREEMENT_REQUIRED',
          error: 'You must read and accept the Digital Loan Agreement before applying.',
        });
      }

      // ── Active default restriction (Policy §4) ────────────────────────────
      // Flagged accounts and members with overdue/defaulted/in-recovery loans
      // cannot take a new loan until obligations are regularized.
      const { data: profile, error: profileErr } = await supabase
        .from('profiles')
        .select('id, is_flagged')
        .eq('id', profileId)
        .maybeSingle();
      if (profileErr) throw profileErr;
      if (profile?.is_flagged === true) {
        return res.status(403).json({
          success: false,
          code: 'ACCOUNT_FLAGGED',
          error: 'Your account is currently restricted. Please contact support to resolve outstanding issues before applying for a loan.',
        });
      }

      const { data: memberLoans, error: loansErr } = await supabase
        .from('loans')
        .select('id, loan_id, amount, status, remaining_balance, total_repayment')
        .eq('profile_id', profileId)
        .in('status', loanPolicy.DEFAULT_BLOCKING_STATUSES);
      if (loansErr) throw loansErr;

      if (memberLoans && memberLoans.length > 0) {
        const outstanding = memberLoans.map((l) => ({
          loanId: l.loan_id || l.id,
          status: l.status,
          balance: Number(l.remaining_balance ?? l.total_repayment ?? l.amount ?? 0),
        }));
        return res.status(403).json({
          success: false,
          code: 'ACTIVE_DEFAULT_RESTRICTION',
          error: 'You have an overdue or defaulted loan. New loan applications are restricted until your outstanding obligations are resolved.',
          outstandingObligations: outstanding,
        });
      }

      // ── Savings-based eligibility cap (Policy §3) ─────────────────────────
      // savings.total_saved is never written anywhere in the codebase, so it
      // is always 0 and would cap every loan at ₦0. Use the wallet balance —
      // the member's actual funds — as the basis for the eligibility cap,
      // falling back to total_saved only if it was ever populated.
      const { data: savings, error: savingsErr } = await supabase
        .from('savings')
        .select('total_saved')
        .eq('profile_id', profileId)
        .maybeSingle();
      if (savingsErr) throw savingsErr;

      const { data: walletRow } = await supabase
        .from('wallets')
        .select('balance')
        .eq('profile_id', profileId)
        .maybeSingle();

      const savedAmount = Number(savings?.total_saved || 0);
      const walletBalance = Number(walletRow?.balance || 0);
      const totalSavings = savedAmount > 0 ? savedAmount : walletBalance;
      const maxAllowed = loanPolicy.maxLoanAmount(loanType, totalSavings);
      if (Number(amount) > maxAllowed) {
        return res.status(400).json({
          success: false,
          code: 'EXCEEDS_SAVINGS_LIMIT',
          error: maxAllowed > 0
            ? `The maximum you can borrow on a ${loanType} is ₦${maxAllowed.toLocaleString()} (${loanPolicy.multiplierFor(loanType)}× your savings of ₦${totalSavings.toLocaleString()}).`
            : `You need accumulated savings to apply for a ${loanType}. Eligibility is based on ${loanPolicy.multiplierFor(loanType)}× your savings.`,
          maxAllowed,
          multiplier: loanPolicy.multiplierFor(loanType),
          totalSavings,
        });
      }

      let bonusPercent = 0;
      if (applyReferralBonus) {
        const { summary } = await referralService.getReferralSummary(profileId);
        bonusPercent = summary.isBonusAvailable ? summary.currentTierBonus : 0;
      }

      const calc = referralService.calculateInterestWithBonus(loanType, amount, tenureMonths, bonusPercent);

      // Snapshot the member's current contribution commitment — it becomes the
      // floor below which they cannot reduce while this loan is active (Policy:
      // contribution reduction during an active loan).
      let currentContribution = null;
      try {
        const { data: plan } = await supabase
          .from('contribution_plans')
          .select('current_monthly_amount')
          .eq('profile_id', profileId)
          .maybeSingle();
        currentContribution = plan?.current_monthly_amount ?? null;
      } catch (_) { /* contribution_plans may not exist yet */ }

      const loanId = newLoanId();
      const insertPayload = {
        loan_id: loanId,
        profile_id: profileId,
        loan_type: loanType,
        amount,
        tenure_months: tenureMonths,
        purpose: purpose || null,
        base_interest_rate: calc.baseInterestRate,
        referral_bonus_percent: calc.referralBonusPercent,
        effective_interest_rate: calc.effectiveInterestRate,
        monthly_repayment: calc.monthlyRepaymentAfterBonus,
        total_repayment: calc.totalRepayment,
        savings_from_bonus: calc.totalSavingsFromBonus,
        status: 'pending',
        agreement_accepted_at: new Date().toISOString(),
        agreement_version: agreementVersion || AGREEMENT_VERSION,
        monthly_contribution_at_application: currentContribution,
      };

      let { data: loan, error } = await supabase
        .from('loans')
        .insert(insertPayload)
        .select('*')
        .single();

      if (error && /Could not find the .* column|column .* does not exist/i.test(error.message || '')) {
        // Migration 019 not applied yet — retry without the new columns.
        delete insertPayload.agreement_accepted_at;
        delete insertPayload.agreement_version;
        delete insertPayload.monthly_contribution_at_application;
        ({ data: loan, error } = await supabase.from('loans').insert(insertPayload).select('*').single());
      }
      if (error) throw error;

      // Retain evidence of the borrower's digital acceptance (Policy §2.2).
      const { error: agreementErr } = await supabase.from('loan_agreements').insert({
        loan_id: loan.id,
        profile_id: profileId,
        agreement_version: agreementVersion || AGREEMENT_VERSION,
        accepted_at: new Date().toISOString(),
        ip_address: (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || null,
        user_agent: req.headers['user-agent'] || null,
        metadata: { loanType, amount, tenureMonths },
      });
      if (agreementErr) logger.warn('loan_agreements insert failed:', agreementErr.message);

      let bonusResult = null;
      if (applyReferralBonus && bonusPercent > 0) {
        bonusResult = await referralService.applyBonusToLoan(profileId, loanId, loanType);
      }

      await auditLog(profileId, 'LOAN_APPLIED', loan.id, { loanType, amount, bonusPercent, agreementAccepted: true });

      res.status(201).json({
        success: true,
        loan,
        interest: calc,
        bonus: bonusResult,
      });
    } catch (err) {
      logger.error('Loan apply error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/loans/:loanId/generate-qr
 */
router.post(
  '/:loanId/generate-qr',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    try {
      const { loanId } = req.params;
      const { applicantName, applicantPhone, options } = req.body;
      const loan = req.loan;

      // Idempotency: reuse the loan's existing unexpired QR instead of minting
      // a new one, so the borrower always sees (and guarantors always scan)
      // the same code across app restarts and retries.
      const { data: existingQr, error: existingQrError } = await supabase
        .from('loan_qrs')
        .select('*')
        .eq('loan_id', loan.id)
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (existingQrError) throw existingQrError;

      if (existingQr) {
        // Self-heal QRs minted before the compact-payload fix: their images
        // encode the full signed loan record and are too dense to scan.
        // Re-render from just the lookup keys and persist the fixed image.
        // Already-compact QRs re-render byte-identically, so no DB write.
        let qrImage = existingQr.qr_code;
        try {
          const rendered = await qrCodeService.renderLoanQrImage(existingQr.qr_id, loan.id);
          if (rendered && rendered !== existingQr.qr_code) {
            const { error: healErr } = await supabase
              .from('loan_qrs')
              .update({ qr_code: rendered })
              .eq('qr_id', existingQr.qr_id);
            if (healErr) throw healErr;
            qrImage = rendered;
          }
        } catch (healErr) {
          logger.warn('QR self-heal render failed, serving stored image:', healErr.message || healErr);
        }

        const found = existingQr.guarantors_found || 0;
        const required = existingQr.guarantors_required || 3;
        return res.json({
          success: true,
          message: 'Existing QR code returned.',
          qr: {
            id: existingQr.qr_id,
            loanId,
            expiresAt: existingQr.expires_at,
            qrCode: qrImage,
            data: existingQr.qr_data,
          },
          progress: {
            found,
            required,
            percentage: required > 0 ? Math.round((found / required) * 100) : 0,
          },
        });
      }

      const qrResult = await qrCodeService.generateLoanQRCode(
        {
          loanId,
          applicantId: req.user.id,
          applicantName: applicantName || req.user.name,
          applicantPhone,
          loanAmount: loan.amount,
          loanCurrency: 'NGN',
          loanTenure: loan.tenure_months,
          interestRate: loan.effective_interest_rate,
          monthlyRepayment: loan.monthly_repayment,
          totalRepayment: loan.total_repayment,
          purpose: loan.purpose,
        },
        options
      );

      const { data: qrRow, error } = await supabase
        .from('loan_qrs')
        .insert({
          qr_id: qrResult.qrData.qrId,
          loan_id: loan.id,
          applicant_id: req.user.id,
          applicant_name: applicantName || req.user.name,
          applicant_phone: applicantPhone,
          qr_data: qrResult.qrData,
          qr_code: qrResult.qrCode,
          signature: qrResult.qrData.signature,
          expires_at: qrResult.qrData.expiresAt,
          guarantors_required: 3,
          guarantors_found: 0,
        })
        .select('*')
        .single();
      if (error) throw error;

      await auditLog(req.user.id, 'LOAN_QR_GENERATED', loan.id, { qrId: qrRow.qr_id });

      res.status(201).json({
        success: true,
        message: qrResult.message,
        qr: {
          id: qrRow.qr_id,
          loanId,
          expiresAt: qrRow.expires_at,
          qrCode: qrRow.qr_code,
          data: qrRow.qr_data,
        },
        progress: { found: 0, required: 3, percentage: 0 },
      });
    } catch (err) {
      logger.error('QR generation error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/loans
 */
router.get('/', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('loans')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });
    if (error) throw error;

    const loans = data || [];

    // Attach live guarantor progress to each loan so the borrower's app can
    // show "X of 3 guarantors approved" and keep the session visible until all
    // 3 consent (or the borrower cancels). Batch-fetched to avoid N+1 queries.
    if (loans.length) {
      const loanIds = loans.map((l) => l.id);

      // Count consented guarantors per loan.
      const { data: guarantorRows } = await supabase
        .from('loan_guarantors')
        .select('loan_id, status')
        .in('loan_id', loanIds);
      const consentedByLoan = {};
      (guarantorRows || []).forEach((g) => {
        if (g.status === 'consented') {
          consentedByLoan[g.loan_id] = (consentedByLoan[g.loan_id] || 0) + 1;
        }
      });

      // Required count + the persisted QR image/data live on loan_qrs. Fetch the
      // latest QR row per loan so the app can re-share the same QR with the
      // remaining guarantors after being closed.
      const { data: qrRows } = await supabase
        .from('loan_qrs')
        .select('loan_id, qr_id, qr_code, qr_data, guarantors_required, expires_at, status')
        .in('loan_id', loanIds)
        .order('created_at', { ascending: false });
      const requiredByLoan = {};
      const latestQrByLoan = {};
      (qrRows || []).forEach((q) => {
        requiredByLoan[q.loan_id] = q.guarantors_required || 3;
        // Keep only the most recent QR row per loan.
        if (!latestQrByLoan[q.loan_id]) latestQrByLoan[q.loan_id] = q;
      });

      loans.forEach((l) => {
        const qr = latestQrByLoan[l.id];
        l.guarantors_accepted = consentedByLoan[l.id] || 0;
        l.guarantors_required = requiredByLoan[l.id] || 3;
        l.qr_id = qr ? qr.qr_id : null;
        l.qr_code = qr ? qr.qr_code : null;
        l.qr_data = qr ? qr.qr_data : null;
        l.qr_expires_at = qr ? qr.expires_at : null;
        l.qr_status = qr ? qr.status : null;
      });
    }

    res.json({ success: true, loans, total: loans.length });
  } catch (err) {
    logger.error('Error getting loans:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/loans/qr-codes
 */
router.get(
  '/qr-codes',
  authenticate,
  [
    query('status').optional().isIn(['active', 'expired', 'all']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 }),
  ],
  validate,
  async (req, res) => {
    try {
      const status = req.query.status || 'all';
      const page = parseInt(req.query.page) || 1;
      const limit = parseInt(req.query.limit) || 20;

      let q = supabase
        .from('loan_qrs')
        .select('*', { count: 'exact' })
        .eq('applicant_id', req.user.id)
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1);

      if (status === 'active') q = q.gt('expires_at', new Date().toISOString());
      if (status === 'expired') q = q.lte('expires_at', new Date().toISOString());

      const { data, error, count } = await q;
      if (error) throw error;

      const qrCodes = (data || []).map((qr) => {
        const found = qr.guarantors_found || 0;
        const required = qr.guarantors_required || 3;
        return {
          ...qr,
          progress: {
            found,
            required,
            percentage: required > 0 ? Math.round((found / required) * 100) : 0,
            remaining: required - found,
          },
          isExpired: new Date() > new Date(qr.expires_at),
        };
      });

      res.json({
        success: true,
        qrCodes,
        pagination: { page, limit, total: count || 0 },
      });
    } catch (err) {
      logger.error('Error listing QR codes:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/loans/qr-stats
 */
router.get('/qr-stats', async (req, res) => {
  try {
    res.json({ success: true, stats: qrCodeService.getLoanQRStats?.() || {} });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/loans/qr/:qrId
 *
 * Look up loan details by QR code ID. Called by the Flutter QR scanner
 * after decoding the QR image so the guarantor sees real borrower data.
 */
router.get(
  '/qr/:qrId?',
  authenticate,
  async (req, res) => {
    try {
      const qrId = (req.params.qrId || '').trim();
      if (!qrId) {
        return res.status(400).json({ success: false, error: 'QR code ID is required' });
      }

      // Fetch QR row
      const { data: qrRow, error: qrErr } = await supabase
        .from('loan_qrs')
        .select('qr_id, loan_id, guarantors_required, guarantors_found, expires_at')
        .eq('qr_id', qrId)
        .maybeSingle();

      if (qrErr) {
        logger.error('QR lookup error:', qrErr);
        throw qrErr;
      }
      if (!qrRow) {
        return res.status(404).json({ success: false, error: 'QR code not found or expired' });
      }

      // Fetch loan data (without FK join to avoid foreign key errors)
      const { data: loanData, error: loanErr } = await supabase
        .from('loans')
        .select('id, loan_type, amount, tenure_months, status, profile_id')
        .eq('id', qrRow.loan_id)
        .maybeSingle();

      if (loanErr) {
        logger.error('Loan lookup error:', loanErr);
        throw loanErr;
      }

      // Fetch borrower profile separately (safer without FK)
      const { data: profileData } = await supabase
        .from('profiles')
        .select('id, name, phone')
        .eq('id', loanData?.profile_id)
        .maybeSingle();

      const loan = loanData || {};
      const borrower = profileData || {};

      res.json({
        success: true,
        qrId: qrRow.qr_id,
        loanId: qrRow.loan_id,
        loanType: loan.loan_type || 'Quick Loan',
        loanAmount: parseFloat(loan.amount || 0),
        loanTenure: loan.tenure_months || 12,
        borrowerName: borrower.name || 'Coopvest Member',
        borrowerPhone: borrower.phone || '',
        borrowerId: loan.profile_id || '',
        guarantorsRequired: qrRow.guarantors_required || 3,
        guarantorsFound: qrRow.guarantors_found || 0,
        expiresAt: qrRow.expires_at,
        isExpired: qrRow.expires_at ? new Date() > new Date(qrRow.expires_at) : false,
      });
    } catch (err) {
      logger.error('Error fetching loan by QR ID:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/loans/:loanId/guarantors
 * Returns the real guarantor list for a loan (name, phone, status) from
 * loan_guarantors joined with profiles. Accessible by the borrower and by
 * any guarantor assigned to the loan.
 * Called by Flutter LoanDetailsScreen via LoanApiService.getLoanGuarantors.
 */
router.get(
  '/:loanId/guarantors',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const rawId = (req.params.loanId || '').trim();
      const column = UUID_RE.test(rawId) ? 'id' : 'loan_id';
      const { data: loan, error: loanError } = await supabase
        .from('loans')
        .select('id, profile_id')
        .eq(column, rawId)
        .maybeSingle();
      if (loanError) throw loanError;
      if (!loan) {
        return res.status(404).json({ success: false, error: 'Loan not found' });
      }

      const { data: links, error } = await supabase
        .from('loan_guarantors')
        .select('id, guarantor_id, status, consented_at, created_at')
        .eq('loan_id', loan.id)
        .order('created_at', { ascending: true });
      if (error) throw error;

      const rows = links || [];
      const isOwner = loan.profile_id === req.user.id;
      const isGuarantor = rows.some((r) => r.guarantor_id === req.user.id);
      if (!isOwner && !isGuarantor) {
        return res.status(404).json({ success: false, error: 'Loan not found or access denied' });
      }

      const guarantorIds = [...new Set(rows.map((r) => r.guarantor_id).filter(Boolean))];
      const profileMap = {};
      if (guarantorIds.length) {
        const { data: profiles, error: profileError } = await supabase
          .from('profiles')
          .select('id, name, email, phone')
          .in('id', guarantorIds);
        if (profileError) throw profileError;
        for (const p of profiles || []) profileMap[p.id] = p;
      }

      const guarantors = rows.map((r) => {
        const p = profileMap[r.guarantor_id] || {};
        return {
          id: r.id,
          name: p.name || p.email || 'Unknown',
          phone: p.phone || '',
          status: r.status || 'pending',
          confirmed_at: r.consented_at || null,
        };
      });

      res.json({ success: true, guarantors });
    } catch (err) {
      logger.error('Error getting loan guarantors:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * Clamp a due date to the 30th of the month `installmentIndex` months after
 * `startDate`. Months without a 30th (February) use their last day instead.
 */
function dueDateForInstallment(startDate, installmentIndex) {
  const base = new Date(startDate);
  const targetMonth = base.getMonth() + installmentIndex;
  const year = base.getFullYear() + Math.floor(targetMonth / 12);
  const month = ((targetMonth % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return new Date(Date.UTC(year, month, Math.min(30, lastDay)));
}

/**
 * GET /api/v1/loans/:loanId/repayment-schedule
 * Builds the monthly repayment schedule for a loan. The first installment is
 * due on the 30th of the application month (or the 30th of the following
 * month when the application is made on/after the 30th); subsequent
 * installments fall on the 30th of each month until the loan is fully repaid.
 * Paid installments are derived from remaining_balance vs total_repayment.
 * Called by Flutter LoanDetailsScreen via LoanApiService.getRepaymentSchedule.
 */
router.get(
  '/:loanId/repayment-schedule',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    try {
      const loan = req.loan;
      const tenure = Number(loan.tenure_months) || 0;
      const monthly = Number(loan.monthly_repayment) || 0;
      const principal = Number(loan.amount) || 0;
      const totalRepayment = Number(loan.total_repayment) || monthly * tenure;
      const remaining = Number(loan.remaining_balance ?? totalRepayment);
      const start = loan.created_at ? new Date(loan.created_at) : new Date();

      const firstIndex = start.getDate() < 30 ? 0 : 1;
      const paidInstallments = monthly > 0
        ? Math.min(tenure, Math.max(0, Math.floor((totalRepayment - remaining) / monthly + 1e-6)))
        : 0;

      const now = new Date();
      const installments = [];
      for (let i = 1; i <= tenure; i++) {
        const dueDate = dueDateForInstallment(start, firstIndex + i - 1);
        let status;
        if (i <= paidInstallments) {
          status = 'paid';
        } else if (i === paidInstallments + 1) {
          status = 'due';
        } else {
          status = dueDate < now ? 'missed' : 'upcoming';
        }
        installments.push({
          installment_number: i,
          amount: monthly,
          due_date: dueDate.toISOString(),
          status,
        });
      }

      res.json({
        success: true,
        schedule: {
          installments,
          total_interest: Math.max(0, totalRepayment - principal),
          total_principal: principal,
        },
      });
    } catch (err) {
      logger.error('Error building repayment schedule:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/loans/:loanId/status
 * Returns the current status of a loan.
 * Called by Flutter LoanApiService to poll loan state.
 */
router.get(
  '/:loanId/status',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    const loan = req.loan;
    res.json({
      success: true,
      loanId: loan.loan_id || loan.id,
      status: loan.status,
      updatedAt: loan.updated_at,
    });
  }
);

/**
 * GET /api/v1/loans/:loanId
 */
router.get(
  '/:loanId',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    const loan = req.loan;
    // Attach live guarantor progress (consented count + required) so the
    // borrower's app can render "X of 3 guarantors approved".
    try {
      const { count: accepted } = await supabase
        .from('loan_guarantors')
        .select('id', { count: 'exact', head: true })
        .eq('loan_id', loan.id)
        .eq('status', 'consented');
      const { data: qrRow } = await supabase
        .from('loan_qrs')
        .select('guarantors_required')
        .eq('loan_id', loan.id)
        .maybeSingle();
      loan.guarantors_accepted = accepted || 0;
      loan.guarantors_required = (qrRow && qrRow.guarantors_required) || 3;
    } catch (_) { /* leave defaults if lookup fails */ }
    res.json({ success: true, loan });
  }
);

/**
 * POST /api/v1/loans/:loanId/cancel
 * Cancels a pending loan application.
 * Called by Flutter LoanDashboardScreen / LoanDetailsScreen cancel action.
 */
router.post(
  '/:loanId/cancel',
  authenticate,
  [
    param('loanId').notEmpty(),
    body('reason').optional().isString().isLength({ max: 500 }),
  ],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    try {
      const loan = req.loan;
      const { reason } = req.body;

      if (!['pending', 'under_review'].includes(loan.status)) {
        return res.status(400).json({
          success: false,
          error: `Only pending or under-review loans can be cancelled. Current status: ${loan.status}`,
        });
      }

      const now = new Date().toISOString();
      const { data: updated, error } = await supabase
        .from('loans')
        .update({ status: 'cancelled', cancelled_at: now, updated_at: now })
        .eq('id', loan.id)
        .select('*')
        .single();
      if (error) throw error;

      await auditLog(req.user.id, 'LOAN_CANCELLED', loan.id, { reason: reason || null });

      res.json({
        success: true,
        message: 'Loan application cancelled successfully.',
        loan: updated,
      });
    } catch (err) {
      logger.error('Loan cancel error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/loans/:loanId/guarantors/confirm
 *
 * Called by the Flutter GuarantorVerificationScreen when a guarantor
 * accepts responsibility for a loan after scanning the borrower's QR code.
 */
router.post(
  '/:loanId/guarantors/confirm',
  authenticate,
  [
    param('loanId').notEmpty(),
    body('guarantor_id').notEmpty(),
  ],
  validate,
  async (req, res) => {
    try {
      const { loanId: rawLoanId } = req.params;
      const { guarantor_id: guarantorId, guarantor_name, guarantor_phone } = req.body;

      const actorId = req.user.id;

      // Resolve composite text references to a UUID before querying.
      const loanId = await resolveLoanUuid(rawLoanId);
      if (!loanId) {
        return res.status(400).json({ success: false, error: 'Invalid loan reference format. Please update your app and try again.' });
      }

      const { data: row, error: findErr } = await supabase
        .from('loan_guarantors')
        .select('id, status, loan_id')
        .eq('loan_id', loanId)
        .eq('guarantor_id', guarantorId)
        .maybeSingle();

      if (findErr) throw findErr;

      const now = new Date().toISOString();

      if (!row) {
        const { error: insertErr } = await supabase
          .from('loan_guarantors')
          .insert({
            loan_id: loanId,
            guarantor_id: guarantorId,
            status: 'consented',
            consented_at: now,
          });
        if (insertErr) throw insertErr;
      } else {
        if (row.status === 'consented') {
          return res.status(400).json({ success: false, error: 'You have already confirmed this guarantee.' });
        }
        const { error: updateErr } = await supabase
          .from('loan_guarantors')
          .update({ status: 'consented', consented_at: now, updated_at: now })
          .eq('id', row.id);
        if (updateErr) throw updateErr;
      }

      try {
        const { data: qrRow } = await supabase
          .from('loan_qrs')
          .select('guarantors_found')
          .eq('loan_id', loanId)
          .maybeSingle();
        if (qrRow) {
          await supabase
            .from('loan_qrs')
            .update({ guarantors_found: (qrRow.guarantors_found || 0) + 1, updated_at: now })
            .eq('loan_id', loanId);
        }
      } catch (_) {}

      const { count: confirmedCount } = await supabase
        .from('loan_guarantors')
        .select('id', { count: 'exact', head: true })
        .eq('loan_id', loanId)
        .eq('status', 'consented');

      await auditLog(actorId, 'GUARANTOR_CONSENTED', loanId, {
        guarantorId,
        guarantorName: guarantor_name,
      });

      res.json({
        success: true,
        message: 'Guarantee confirmed successfully.',
        guarantor_status: 'consented',
        guarantors_now_confirmed: confirmedCount || 0,
      });
    } catch (err) {
      logger.error('Error confirming guarantee:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/loans/:loanId/guarantors/decline
 */
router.post(
  '/:loanId/guarantors/decline',
  authenticate,
  [
    param('loanId').notEmpty(),
    body('guarantor_id').notEmpty(),
  ],
  validate,
  async (req, res) => {
    try {
      const { loanId: rawLoanId } = req.params;
      const { guarantor_id: guarantorId, reason } = req.body;

      // Resolve composite text references to a UUID before querying.
      const loanId = await resolveLoanUuid(rawLoanId);
      if (!loanId) {
        return res.status(400).json({ success: false, error: 'Invalid loan reference format. Please update your app and try again.' });
      }

      const { data: row, error: findErr } = await supabase
        .from('loan_guarantors')
        .select('id, status')
        .eq('loan_id', loanId)
        .eq('guarantor_id', guarantorId)
        .maybeSingle();

      if (findErr) throw findErr;
      if (!row) return res.status(404).json({ success: false, error: 'Guarantor record not found.' });
      if (row.status !== 'pending') {
        return res.status(400).json({ success: false, error: `Request is already ${row.status}.` });
      }

      const now = new Date().toISOString();
      const { error: updateErr } = await supabase
        .from('loan_guarantors')
        .update({ status: 'rejected', updated_at: now })
        .eq('id', row.id);

      if (updateErr) throw updateErr;

      await auditLog(req.user.id, 'GUARANTOR_REJECTED', loanId, { guarantorId, reason: reason || null });

      res.json({ success: true, message: 'Guarantee request declined.' });
    } catch (err) {
      logger.error('Error declining guarantee:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/loans/:loanId/apply-penalty
 * Admin/staff only — penalties are imposed on borrowers, never by them.
 * The automated Stage 2 penalty is applied by loanRecoveryWorker.
 */
router.post(
  '/:loanId/apply-penalty',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      if (!ADMIN_ROLES.includes(req.user.role)) {
        return res.status(403).json({ success: false, error: 'Only admin staff can apply loan penalties.' });
      }
      const uuid = await resolveLoanUuid(req.params.loanId);
      if (!uuid) return res.status(404).json({ success: false, error: 'Loan not found' });
      const { data: loan, error: loanErr } = await supabase
        .from('loans')
        .select('*')
        .eq('id', uuid)
        .maybeSingle();
      if (loanErr) throw loanErr;
      if (!loan) return res.status(404).json({ success: false, error: 'Loan not found' });
      const PENALTY = 3000;

      if (!['active', 'repaying', 'overdue'].includes(loan.status)) {
        return res.status(400).json({
          success: false,
          error: 'Penalty can only be applied to active, repaying, or overdue loans.',
        });
      }

      // Fines are separate obligations — create an outstanding member_fees row
      // rather than adding the penalty to the loan balance.
      const { data: feeRow, error: feeErr } = await supabase
        .from('member_fees')
        .insert({
          profile_id: loan.profile_id,
          loan_id: loan.id,
          fee_type: 'fine',
          label: 'Late Loan Repayment Fine',
          amount: PENALTY,
          status: 'outstanding',
          assigned_by: req.user.id,
        })
        .select('id')
        .maybeSingle();
      if (feeErr) throw feeErr;

      const { data: updated, error } = await supabase
        .from('loans')
        .update({
          penalty_applied: true,
          penalty_amount: (loan.penalty_amount || 0) + PENALTY,
          status: 'overdue',
          updated_at: new Date().toISOString(),
        })
        .eq('id', loan.id)
        .select('*')
        .single();

      if (error) throw error;

      await auditLog(req.user.id, 'LOAN_PENALTY_APPLIED', loan.id, {
        penalty: PENALTY,
        fee_id: feeRow ? feeRow.id : null,
        reason: 'Stage 2 — 2nd consecutive missed month (Loan Policy §4.1)',
      });

      res.json({
        success: true,
        message: 'Late repayment penalty of ₦3,000 recorded as a separate fine obligation.',
        penalty: PENALTY,
        fee_id: feeRow ? feeRow.id : null,
        loan: updated,
      });
    } catch (err) {
      logger.error('Apply penalty error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/loans/:loanId/recovery-status
 */
router.get(
  '/:loanId/recovery-status',
  authenticate,
  [param('loanId').notEmpty()],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    const loan = req.loan;
    const missedMonths = loan.missed_months || 0;
    let stage = 'none';
    if (missedMonths >= 3) stage = 'recovery';
    else if (missedMonths === 2) stage = 'penalty';
    else if (missedMonths === 1) stage = 'reminder';

    res.json({
      success: true,
      loanId: loan.loan_id || loan.id,
      status: loan.status,
      missedMonths,
      stage,
      penaltyApplied: loan.penalty_applied || false,
      penaltyAmount: loan.penalty_amount || 0,
      outstandingBalance: loan.outstanding_balance || loan.amount || 0,
      recoveryInitiatedAt: loan.recovery_initiated_at || null,
      notice:
        'Late loan repayments may attract a ₦3,000 penalty fee after repeated default notices. ' +
        'Continued non-payment beyond three months may trigger guarantor recovery procedures ' +
        "in accordance with Coopvest Africa\u2019s loan policy.",
    });
  }
);

/**
 * POST /api/v1/loans/:loanId/repay
 *
 * Records a loan repayment.
 *
 * - paymentMethod: 'wallet'          → instantly deduct the member's wallet
 *   and mark the repayment paid (no admin verification needed).
 *   For any other method (e.g. 'bank_transfer') + optional proof_url → create
 *   a pending loan_repayment + deposit_request with allocation_type =
 *   'loan_repayment'. Admin verification of that deposit then marks the
 *   repayment paid and reduces loans.remaining_balance.
 *
 * Members can also repay via the generic POST /wallet/contribute endpoint by
 * sending allocation_type='loan_repayment' (handled in wallet.js); this
 * endpoint is the loan-explicit helper the app's LoanApiService calls.
 */
router.post(
  '/:loanId/repay',
  authenticate,
  [
    param('loanId').notEmpty(),
    body('amount').isFloat({ min: 0.01 }),
    body('paymentMethod').optional().isString(),
  ],
  validate,
  verifyLoanOwnership,
  async (req, res) => {
    try {
      const loan = req.loan;
      const amount = Number(req.body.amount);
      const paymentMethod = (req.body.paymentMethod || 'bank_transfer').toString();
      const proofUrl = req.body.proof_url || null;

      if (!['active', 'repaying', 'overdue'].includes(loan.status)) {
        return res.status(400).json({
          success: false,
          error: `Repayment is only accepted for active, repaying or overdue loans. Current status: ${loan.status}`,
        });
      }

      const now = new Date().toISOString();

      // ── Instant wallet repayment ──
      if (paymentMethod === 'wallet') {
        const { ensureWallet } = require('./wallet');
        const wallet = await ensureWallet(loan.profile_id);
        const balance = Number(wallet.balance || 0);
        if (balance < amount) {
          return res.status(400).json({ success: false, error: 'Insufficient wallet balance for this repayment.' });
        }
        const newBalance = balance - amount;
        const { error: wErr } = await supabase
          .from('wallets')
          .update({ balance: newBalance, last_updated: now })
          .eq('id', wallet.id);
        if (wErr) throw wErr;

        const { data: txn } = await supabase
          .from('transactions')
          .insert({
            profile_id: loan.profile_id,
            type: 'loan_repayment',
            category: 'debit',
            amount,
            status: 'completed',
            description: `Loan repayment for ${loan.loan_id || loan.id}`,
            payment_method: 'wallet',
            balance_before: balance,
            balance_after: newBalance,
            completed_at: now,
          })
          .select('*')
          .maybeSingle();

        const remainingBefore = Number(loan.remaining_balance ?? loan.total_repayment ?? 0);
        const remaining = Math.max(0, remainingBefore - amount);
        await supabase
          .from('loans')
          .update({ remaining_balance: remaining, updated_at: now })
          .eq('id', loan.id);

        const { data: repayment, error: rErr } = await supabase
          .from('loan_repayments')
          .insert({
            loan_id: loan.id,
            profile_id: loan.profile_id,
            amount,
            status: 'paid',
            paid_at: now,
            reference: txn ? txn.id : null,
          })
          .select('*')
          .maybeSingle();
        if (rErr) throw rErr;

        return res.status(201).json({
          success: true,
          message: `Repayment of ₦${amount.toLocaleString()} applied. New loan balance: ₦${remaining.toLocaleString()}.`,
          repayment,
          remaining_balance: remaining,
        });
      }

      // ── Proof-based repayment (admin verifies) ──
      const { data: txn } = await supabase
        .from('transactions')
        .insert({
          profile_id: loan.profile_id,
          type: 'loan_repayment',
          category: 'debit',
          amount,
          status: 'pending',
          description: `Loan repayment for ${loan.loan_id || loan.id}`,
          payment_method: paymentMethod,
        })
        .select('*')
        .maybeSingle();

      let depositRequest = null;
      try {
        const { data: dr } = await supabase
          .from('deposit_requests')
          .insert({
            profile_id: loan.profile_id,
            transaction_id: txn ? txn.id : null,
            amount,
            currency: 'NGN',
            status: 'pending',
            allocation_type: 'loan_repayment',
            loan_id: loan.id,
            loan_amount: amount,
            payment_proof_url: proofUrl,
          })
          .select('*')
          .maybeSingle();
        depositRequest = dr;
      } catch (drErr) {
        logger.warn('loan repayment deposit_request insert failed (migration 020 pending?):', drErr.message);
      }

      const { data: repayment } = await supabase
        .from('loan_repayments')
        .insert({
          loan_id: loan.id,
          profile_id: loan.profile_id,
          amount,
          status: 'pending',
          reference: txn ? txn.id : null,
          deposit_request_id: depositRequest ? depositRequest.id : null,
        })
        .select('*')
        .maybeSingle();

      return res.status(202).json({
        success: true,
        message: 'Repayment submitted for verification. Your loan balance will be updated once an admin confirms your payment.',
        repayment,
        deposit_request: depositRequest,
      });
    } catch (err) {
      logger.error('Loan repay error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

module.exports = router;
