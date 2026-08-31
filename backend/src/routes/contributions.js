/**
 * Contributions Routes
 *
 * Member monthly contribution records and plan management.
 * Stored in `contributions` (transaction records) and `contribution_plans`
 * (member's active plan + pending reduction requests).
 *
 * Flutter endpoints used by ContributionApiService and ContributionPlanApiService:
 *   GET   /contributions                        — paginated list
 *   GET   /contributions/summary                — totals & status
 *   GET   /contributions/plan                   — active plan
 *   PATCH /contributions/plan/increase          — immediate increase
 *   POST  /contributions/plan/reduction-request — 3-month-notice reduction
 *   DELETE /contributions/plan/reduction-request/:id — cancel pending reduction
 *   GET   /contributions/:id                    — single record
 *   GET   /contributions/:id/receipt            — receipt URL
 */

const express = require('express');
const { param, body, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const loanPolicy = require('../lib/loanPolicy');
const logger = require('../utils/logger');

router.use(authenticate);

const MINIMUM_MONTHLY_AMOUNT = 5000;

async function getOrCreatePlan(profileId) {
  const { data } = await supabase
    .from('contribution_plans')
    .select('*')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (data) return data;

  const { data: created, error } = await supabase
    .from('contribution_plans')
    .insert({
      profile_id: profileId,
      current_monthly_amount: MINIMUM_MONTHLY_AMOUNT,
      minimum_amount: MINIMUM_MONTHLY_AMOUNT,
    })
    .select('*')
    .single();
  if (error) throw error;
  return created;
}

/**
 * GET /api/v1/contributions/summary
 * Must be defined before /:id to avoid route collision.
 */
router.get('/summary', async (req, res) => {
  try {
    const { data: all, error } = await supabase
      .from('contributions')
      .select('amount, status, contribution_month, created_at')
      .eq('profile_id', req.user.id);
    if (error) throw error;

    const now = new Date();
    const thisMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const thisYear = String(now.getFullYear());

    const successful = (all || []).filter((c) => c.status === 'successful');
    const pending = (all || []).filter((c) => c.status === 'pending');
    const overdue = (all || []).filter((c) => c.status === 'overdue');

    let totalThisMonth = successful
      .filter((c) => (c.contribution_month || '').startsWith(thisMonth))
      .reduce((s, c) => s + parseFloat(c.amount || 0), 0);

    let totalThisYear = successful
      .filter((c) => (c.contribution_month || '').startsWith(thisYear))
      .reduce((s, c) => s + parseFloat(c.amount || 0), 0);

    let lifetimeContributions = successful.reduce((s, c) => s + parseFloat(c.amount || 0), 0);

    // Fallback to the savings table + this-month credit transactions when the
    // contributions table has no rows. Members who deposit via the wallet flow
    // accrue savings without contribution records, so without this fallback the
    // "monthly contribution progress" card shows 0/₦10,000 even when the member
    // has real savings. Only used as a floor — never double-counts contribution
    // rows that already exist.
    if (!all || all.length === 0) {
      try {
        const { data: savings } = await supabase
          .from('savings')
          .select('total_saved, monthly_savings, last_savings_date')
          .eq('profile_id', req.user.id)
          .maybeSingle();
        if (savings) {
          lifetimeContributions = Number(savings.total_saved) || 0;
        }

        // This month's credit transactions (deposits/contributions) give a
        // realistic "this month" figure for the progress card.
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
        const { data: monthCredits } = await supabase
          .from('transactions')
          .select('amount, type, category, created_at')
          .eq('profile_id', req.user.id)
          .in('category', ['credit', 'deposit'])
          .gte('created_at', monthStart);
        totalThisMonth = (monthCredits || []).reduce(
          (s, t) => s + (Number(t.amount) || 0),
          0,
        );

        // This year's credits for the yearly figure.
        const yearStart = new Date(now.getFullYear(), 0, 1).toISOString();
        const { data: yearCredits } = await supabase
          .from('transactions')
          .select('amount, category, created_at')
          .eq('profile_id', req.user.id)
          .in('category', ['credit', 'deposit'])
          .gte('created_at', yearStart);
        totalThisYear = (yearCredits || []).reduce(
          (s, t) => s + (Number(t.amount) || 0),
          0,
        );
      } catch (fbErr) {
        logger.warn('contributions summary savings fallback failed:', fbErr.message);
      }
    }

    const plan = await getOrCreatePlan(req.user.id);

    res.json({
      success: true,
      totalThisMonth,
      totalThisYear,
      lifetimeContributions,
      expectedMonthlyAmount: plan.current_monthly_amount || MINIMUM_MONTHLY_AMOUNT,
      contributionStatus: overdue.length > 0 ? 'overdue' : totalThisMonth > 0 ? 'up_to_date' : 'pending',
      monthsContributed: successful.length,
      totalContributionsCount: (all || []).length,
      pendingAmount: pending.reduce((s, c) => s + parseFloat(c.amount || 0), 0),
      overdueAmount: overdue.reduce((s, c) => s + parseFloat(c.amount || 0), 0),
    });
  } catch (err) {
    logger.error('contributions summary error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/contributions/plan
 */
router.get('/plan', async (req, res) => {
  try {
    const plan = await getOrCreatePlan(req.user.id);

    const { data: pendingReduction } = await supabase
      .from('contribution_plan_reductions')
      .select('*')
      .eq('profile_id', req.user.id)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    res.json({
      success: true,
      current_monthly_amount: plan.current_monthly_amount,
      minimum_amount: plan.minimum_amount || MINIMUM_MONTHLY_AMOUNT,
      pending_reduction: pendingReduction
        ? {
            id: pendingReduction.id,
            requested_amount: pendingReduction.requested_amount,
            requested_at: pendingReduction.created_at,
            effective_date: pendingReduction.effective_date,
            status: pendingReduction.status,
          }
        : null,
    });
  } catch (err) {
    logger.error('contribution plan get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PATCH /api/v1/contributions/plan/increase
 */
router.patch(
  '/plan/increase',
  [body('new_monthly_amount').isFloat({ min: MINIMUM_MONTHLY_AMOUNT })],
  validate,
  async (req, res) => {
    try {
      const { new_monthly_amount } = req.body;
      const plan = await getOrCreatePlan(req.user.id);

      if (new_monthly_amount <= plan.current_monthly_amount) {
        return res.status(400).json({
          success: false,
          error: 'New amount must be greater than current monthly amount. Use a reduction request to decrease.',
        });
      }

      const { data: updated, error } = await supabase
        .from('contribution_plans')
        .update({
          current_monthly_amount: new_monthly_amount,
          updated_at: new Date().toISOString(),
        })
        .eq('profile_id', req.user.id)
        .select('*')
        .single();
      if (error) throw error;

      res.json({
        success: true,
        current_monthly_amount: updated.current_monthly_amount,
        minimum_amount: updated.minimum_amount || MINIMUM_MONTHLY_AMOUNT,
        pending_reduction: null,
      });
    } catch (err) {
      logger.error('contribution plan increase error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/contributions/plan/reduction-request
 * 3-month notice period: effective_date = now + 3 months
 */
router.post(
  '/plan/reduction-request',
  [body('requested_amount').isFloat({ min: MINIMUM_MONTHLY_AMOUNT })],
  validate,
  async (req, res) => {
    try {
      const { requested_amount } = req.body;
      const plan = await getOrCreatePlan(req.user.id);

      if (requested_amount >= plan.current_monthly_amount) {
        return res.status(400).json({
          success: false,
          error: 'Reduction amount must be less than your current monthly contribution.',
        });
      }

      // Policy: a member with an active loan may not reduce their monthly
      // contribution below the level used for that loan's eligibility
      // (increases are always allowed).
      const { data: activeLoans, error: loansErr } = await supabase
        .from('loans')
        .select('id, loan_id, monthly_contribution_at_application')
        .eq('profile_id', req.user.id)
        .in('status', loanPolicy.ACTIVE_LOAN_STATUSES);
      if (loansErr && !/Could not find the .* column|column .* does not exist/i.test(loansErr.message || '')) throw loansErr;

      const floor = (activeLoans || []).reduce(
        (max, l) => Math.max(max, Number(l.monthly_contribution_at_application) || 0),
        0,
      );
      if (floor > 0 && requested_amount < floor) {
        return res.status(400).json({
          success: false,
          code: 'REDUCTION_BLOCKED_ACTIVE_LOAN',
          error: `You have an active loan. Your monthly contribution cannot be reduced below ₦${floor.toLocaleString()} — the level used for your loan eligibility — until the loan is fully repaid. You may still increase your contribution at any time.`,
          minimumAllowed: floor,
        });
      }

      const { data: existingPending } = await supabase
        .from('contribution_plan_reductions')
        .select('id')
        .eq('profile_id', req.user.id)
        .eq('status', 'pending')
        .maybeSingle();

      if (existingPending) {
        return res.status(400).json({
          success: false,
          error: 'You already have a pending reduction request. Cancel it before submitting a new one.',
        });
      }

      const effectiveDate = new Date();
      effectiveDate.setMonth(effectiveDate.getMonth() + 3);

      const { data: reduction, error } = await supabase
        .from('contribution_plan_reductions')
        .insert({
          profile_id: req.user.id,
          requested_amount,
          effective_date: effectiveDate.toISOString(),
          status: 'pending',
        })
        .select('*')
        .single();
      if (error) throw error;

      res.status(201).json({
        success: true,
        id: reduction.id,
        requested_amount: reduction.requested_amount,
        requested_at: reduction.created_at,
        effective_date: reduction.effective_date,
        status: reduction.status,
      });
    } catch (err) {
      logger.error('contribution plan reduction request error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * DELETE /api/v1/contributions/plan/reduction-request/:id
 */
router.delete(
  '/plan/reduction-request/:id',
  [param('id').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const { data: reduction, error: findErr } = await supabase
        .from('contribution_plan_reductions')
        .select('id, status, profile_id')
        .eq('id', req.params.id)
        .maybeSingle();

      if (findErr) throw findErr;
      if (!reduction) return res.status(404).json({ success: false, error: 'Reduction request not found.' });
      if (reduction.profile_id !== req.user.id) {
        return res.status(403).json({ success: false, error: 'Not authorised.' });
      }
      if (reduction.status !== 'pending') {
        return res.status(400).json({ success: false, error: 'Only pending requests can be cancelled.' });
      }

      const { error } = await supabase
        .from('contribution_plan_reductions')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', req.params.id);
      if (error) throw error;

      res.json({ success: true, message: 'Reduction request cancelled.' });
    } catch (err) {
      logger.error('contribution plan cancel reduction error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/contributions
 */
router.get(
  '/',
  [
    query('page').optional().isInt({ min: 1 }),
    query('page_size').optional().isInt({ min: 1, max: 100 }),
  ],
  validate,
  async (req, res) => {
    try {
      const page = parseInt(req.query.page) || 1;
      const pageSize = parseInt(req.query.page_size) || 20;

      const { data, error, count } = await supabase
        .from('contributions')
        .select('*', { count: 'exact' })
        .eq('profile_id', req.user.id)
        .order('created_at', { ascending: false })
        .range((page - 1) * pageSize, page * pageSize - 1);

      if (error) throw error;

      res.json({
        success: true,
        data: data || [],
        total_count: count || 0,
        page,
        page_size: pageSize,
      });
    } catch (err) {
      logger.error('contributions list error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/contributions/:id
 */
router.get('/:id', [param('id').notEmpty()], validate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('contributions')
      .select('*')
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .maybeSingle();

    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Contribution not found.' });

    res.json({ success: true, ...data });
  } catch (err) {
    logger.error('contributions get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/contributions/:id/receipt
 */
router.get('/:id/receipt', [param('id').notEmpty()], validate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('contributions')
      .select('id, receipt_url')
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .maybeSingle();

    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Contribution not found.' });

    const baseUrl = process.env.APP_BASE_URL || process.env.API_BASE_URL || '';
    const receiptUrl = data.receipt_url || `${baseUrl}/receipts/${data.id}.pdf`;

    res.json({ success: true, receipt_url: receiptUrl });
  } catch (err) {
    logger.error('contributions receipt error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
