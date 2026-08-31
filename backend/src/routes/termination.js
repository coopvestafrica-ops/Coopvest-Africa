/**
 * Termination Routes
 *
 * Membership termination requests. Stored in `termination_requests`.
 * All financial validations are server-side; the mobile app is a request interface only.
 *
 * Flutter endpoints used by TerminationApiService:
 *   GET  /termination/eligibility      — check if user can apply
 *   POST /termination/request          — submit a termination request
 *   GET  /termination/current          — get active/latest request
 *   GET  /termination/history          — all past requests
 *   POST /termination/:id/cancel       — cancel a pending request
 *   POST /termination/:id/confirm      — final confirmation after admin approval
 */

const express = require('express');
const { param, body } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

router.use(authenticate);

const BLOCKING_LOAN_STATUSES = ['active', 'repaying', 'overdue', 'pending', 'under_review'];

/**
 * GET /api/v1/termination/eligibility
 * Must be defined before /:id routes.
 */
router.get('/eligibility', async (req, res) => {
  try {
    const profileId = req.user.id;

    // Check for active loans
    const { data: activeLoans } = await supabase
      .from('loans')
      .select('id, status, amount')
      .eq('profile_id', profileId)
      .in('status', BLOCKING_LOAN_STATUSES);

    const hasActiveLoans = (activeLoans || []).length > 0;

    // Check for a pending termination request already
    const { data: existingRequest } = await supabase
      .from('termination_requests')
      .select('id, status')
      .eq('profile_id', profileId)
      .in('status', ['pending', 'approved', 'under_review'])
      .maybeSingle();

    const hasPendingRequest = !!existingRequest;

    const eligible = !hasActiveLoans && !hasPendingRequest;

    res.json({
      success: true,
      message: eligible
        ? 'You are eligible to apply for membership termination.'
        : hasActiveLoans
        ? 'You cannot terminate while you have active or pending loans.'
        : 'You already have a pending termination request.',
      eligibility: {
        eligible,
        hasActiveLoans,
        hasPendingRequest,
        activeLoansCount: (activeLoans || []).length,
        blockers: [
          ...(hasActiveLoans ? [`${(activeLoans || []).length} active or pending loan(s)`] : []),
          ...(hasPendingRequest ? ['Existing termination request in progress'] : []),
        ],
      },
    });
  } catch (err) {
    logger.error('termination eligibility error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * GET /api/v1/termination/current
 * Must be defined before /:id routes.
 */
router.get('/current', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('termination_requests')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) throw error;

    res.json({
      success: true,
      message: data ? 'Termination request found.' : 'No active termination request.',
      request: data || null,
    });
  } catch (err) {
    logger.error('termination current error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * GET /api/v1/termination/history
 * Must be defined before /:id routes.
 */
router.get('/history', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('termination_requests')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });

    if (error) throw error;

    res.json({
      success: true,
      message: 'Termination history retrieved.',
      requests: data || [],
    });
  } catch (err) {
    logger.error('termination history error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * POST /api/v1/termination/request
 */
router.post(
  '/request',
  [
    body('reason').isString().isLength({ min: 10, max: 1000 }),
    body('bankAccountId').optional().isString(),
    body('confirmationNote').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const profileId = req.user.id;
      const { reason, bankAccountId, confirmationNote } = req.body;

      // Re-check eligibility server-side
      const { data: activeLoans } = await supabase
        .from('loans')
        .select('id')
        .eq('profile_id', profileId)
        .in('status', BLOCKING_LOAN_STATUSES);

      if ((activeLoans || []).length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Cannot submit termination request while you have active or pending loans.',
        });
      }

      const { data: existing } = await supabase
        .from('termination_requests')
        .select('id')
        .eq('profile_id', profileId)
        .in('status', ['pending', 'approved', 'under_review'])
        .maybeSingle();

      if (existing) {
        return res.status(400).json({
          success: false,
          message: 'You already have a pending termination request.',
        });
      }

      const { data: request, error } = await supabase
        .from('termination_requests')
        .insert({
          profile_id: profileId,
          reason,
          bank_account_id: bankAccountId || null,
          confirmation_note: confirmationNote || null,
          status: 'pending',
        })
        .select('*')
        .single();

      if (error) throw error;

      // Reflect the pending termination on the member's profile so both the
      // mobile app and the admin portal can see it.
      await supabase
        .from('profiles')
        .update({ membership_status: 'pending_termination' })
        .eq('id', profileId);

      res.status(201).json({
        success: true,
        message: 'Termination request submitted successfully. You will be contacted within 5-10 business days.',
        request,
      });
    } catch (err) {
      logger.error('termination request error:', err);
      res.status(500).json({ success: false, message: err.message });
    }
  }
);

/**
 * POST /api/v1/termination/:id/cancel
 */
router.post('/:id/cancel', [param('id').notEmpty()], validate, async (req, res) => {
  try {
    const { data, error: findErr } = await supabase
      .from('termination_requests')
      .select('id, status, profile_id')
      .eq('id', req.params.id)
      .maybeSingle();

    if (findErr) throw findErr;
    if (!data) return res.status(404).json({ success: false, message: 'Request not found.' });
    if (data.profile_id !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Not authorised.' });
    }
    if (!['pending', 'under_review'].includes(data.status)) {
      return res.status(400).json({ success: false, message: `Cannot cancel a request with status: ${data.status}` });
    }

    const { error } = await supabase
      .from('termination_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', data.id);
    if (error) throw error;

    await supabase
      .from('profiles')
      .update({ membership_status: 'active' })
      .eq('id', data.profile_id);

    res.json({ success: true, message: 'Termination request cancelled.' });
  } catch (err) {
    logger.error('termination cancel error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * POST /api/v1/termination/:id/confirm
 * Final member confirmation step after admin approves.
 */
router.post('/:id/confirm', [param('id').notEmpty()], validate, async (req, res) => {
  try {
    const { data, error: findErr } = await supabase
      .from('termination_requests')
      .select('id, status, profile_id')
      .eq('id', req.params.id)
      .maybeSingle();

    if (findErr) throw findErr;
    if (!data) return res.status(404).json({ success: false, message: 'Request not found.' });
    if (data.profile_id !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Not authorised.' });
    }
    if (data.status !== 'approved') {
      return res.status(400).json({
        success: false,
        message: 'This request has not been approved by an administrator yet.',
      });
    }

    const now = new Date().toISOString();
    const { error } = await supabase
      .from('termination_requests')
      .update({ status: 'confirmed', confirmed_at: now, updated_at: now })
      .eq('id', data.id);
    if (error) throw error;

    await supabase
      .from('profiles')
      .update({ membership_status: 'terminated' })
      .eq('id', data.profile_id);

    res.json({
      success: true,
      message: 'Termination confirmed. Your account closure will be processed within 30 days.',
    });
  } catch (err) {
    logger.error('termination confirm error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
