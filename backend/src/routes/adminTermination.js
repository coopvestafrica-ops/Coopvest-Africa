/**
 * Membership Termination Routes (admin-facing)
 *
 * Lets the admin portal list, review, approve and reject member termination
 * requests submitted from the mobile app, and keeps profiles.membership_status
 * in sync so the change is visible everywhere.
 */

const express = require('express');
const { param, body } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

router.use(requireAdmin);

/**
 * GET / (mounted at /api/v1/admin-termination and /api/admin/termination)
 * List termination requests, newest first. Optional ?status= filter.
 */
router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, parseInt(req.query.limit) || 50);

    let q = supabase
      .from('termination_requests')
      .select('*, profile:profiles(id, user_id, name, email, phone, membership_status)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);
    if (req.query.status) q = q.eq('status', req.query.status);

    const { data, error, count } = await q;
    if (error) throw error;

    res.json({
      success: true,
      data: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('admin termination list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /:id/status
 * Body: { action: 'review' | 'approve' | 'reject', note? }
 * Transitions a termination request and syncs profiles.membership_status.
 */
router.post(
  '/:id/status',
  [
    param('id').isUUID(),
    body('action').isIn(['review', 'approve', 'reject']),
    body('note').optional().isString().isLength({ max: 1000 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { action, note } = req.body;

      const { data: request, error: findErr } = await supabase
        .from('termination_requests')
        .select('*')
        .eq('id', req.params.id)
        .maybeSingle();
      if (findErr) throw findErr;
      if (!request) {
        return res.status(404).json({ success: false, error: 'Termination request not found' });
      }
      if (!['pending', 'under_review'].includes(request.status)) {
        return res.status(400).json({
          success: false,
          error: `Cannot update a request with status: ${request.status}`,
        });
      }

      const now = new Date().toISOString();
      const update = { updated_at: now };
      let membershipStatus = null;

      if (action === 'review') {
        update.status = 'under_review';
      } else if (action === 'approve') {
        update.status = 'approved';
        update.reviewed_by = req.user.id;
        update.reviewed_at = now;
        if (note) update.review_note = note;
        membershipStatus = 'pending_termination';
      } else {
        update.status = 'rejected';
        update.reviewed_by = req.user.id;
        update.reviewed_at = now;
        if (note) update.review_note = note;
        // Rejection restores the member to full active status.
        membershipStatus = 'active';
      }

      const { data: updated, error } = await supabase
        .from('termination_requests')
        .update(update)
        .eq('id', request.id)
        .select('*')
        .single();
      if (error) throw error;

      if (membershipStatus) {
        await supabase
          .from('profiles')
          .update({ membership_status: membershipStatus })
          .eq('id', request.profile_id);
      }

      res.json({ success: true, request: updated });
    } catch (err) {
      logger.error('admin termination status error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

module.exports = router;
