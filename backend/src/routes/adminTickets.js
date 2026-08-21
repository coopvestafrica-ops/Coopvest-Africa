/**
 * Support Ticket Routes (admin-facing)
 *
 * Used by the admin web portal (via the member-role JWT of an admin user).
 * Cross-backend calls from the admin API server use /api/v1/admin/tickets
 * instead, which is service-token authenticated.
 */

const express = require('express');
const { body, param } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');

router.use(requireAdmin);

/**
 * GET /api/v1/admin-tickets
 */
router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, parseInt(req.query.limit) || 20);
    let q = supabase
      .from('tickets')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.priority) q = q.eq('priority', req.query.priority);
    if (req.query.category) q = q.eq('category', req.query.category);
    if (req.query.assignedTo) q = q.eq('assigned_to', req.query.assignedTo);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({
      success: true,
      tickets: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('admin tickets list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin-tickets/:id
 */
router.get('/:id', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const { data: ticket, error } = await supabase
      .from('tickets')
      .select('*, profile:profiles(id, user_id, name, email)')
      .eq('id', req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!ticket) return res.status(404).json({ success: false, error: 'Ticket not found' });

    const [msgs, atts, hist] = await Promise.all([
      supabase.from('ticket_messages').select('*').eq('ticket_id', ticket.id).order('created_at', { ascending: true }),
      supabase.from('ticket_attachments').select('*').eq('ticket_id', ticket.id),
      supabase.from('ticket_status_history').select('*').eq('ticket_id', ticket.id).order('created_at', { ascending: true }),
    ]);
    res.json({
      success: true,
      ticket: {
        ...ticket,
        messages: msgs.data || [],
        attachments: atts.data || [],
        statusHistory: hist.data || [],
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin-tickets/:id/reply
 */
router.post(
  '/:id/reply',
  [param('id').isUUID(), body('body').isString().isLength({ min: 1, max: 5000 })],
  validate,
  async (req, res) => {
    try {
      const { data: msg, error } = await supabase
        .from('ticket_messages')
        .insert({
          ticket_id: req.params.id,
          author_id: req.user.id,
          author_role: 'staff',
          body: req.body.body,
        })
        .select('*')
        .single();
      if (error) throw error;
      await supabase
        .from('tickets')
        .update({ status: 'awaiting_user', updated_at: new Date().toISOString() })
        .eq('id', req.params.id);

      // Notify the member that support replied to their live-chat ticket.
      try {
        const { data: ticket } = await supabase
          .from('tickets')
          .select('profile_id, subject')
          .eq('id', req.params.id)
          .maybeSingle();
        if (ticket && ticket.profile_id) {
          const preview = String(req.body.body || '').slice(0, 120);
          await notifyService.sendInApp({
            profileId: ticket.profile_id,
            title: '💬 New reply from support',
            body: preview,
            type: 'system',
            category: 'info',
          });
        }
      } catch (e) {
        logger.warn('admin ticket reply notify failed:', e.message);
      }

      res.status(201).json({ success: true, message: msg });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * PATCH /api/v1/admin-tickets/:id
 */
router.patch(
  '/:id',
  [
    param('id').isUUID(),
    body('status').optional().isIn(['open', 'in_progress', 'awaiting_user', 'resolved', 'closed']),
    body('priority').optional().isIn(['low', 'medium', 'high', 'urgent']),
    body('category').optional().isString(),
    body('assignedTo').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const update = {};
      if (req.body.status !== undefined) update.status = req.body.status;
      if (req.body.priority !== undefined) update.priority = req.body.priority;
      if (req.body.category !== undefined) update.category = req.body.category;
      if (req.body.assignedTo !== undefined) update.assigned_staff_id = req.body.assignedTo;
      if (req.body.status === 'closed' || req.body.status === 'resolved') {
        update.resolved_at = new Date().toISOString();
        update.resolved_by = req.user.id;
      }
      update.updated_at = new Date().toISOString();

      const { data, error } = await supabase
        .from('tickets')
        .update(update)
        .eq('id', req.params.id)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!data) return res.status(404).json({ success: false, error: 'Ticket not found' });

      if (req.body.status) {
        await supabase.from('ticket_status_history').insert({
          ticket_id: data.id,
          changed_by: req.user.id,
          new_status: req.body.status,
        });
      }
      res.json({ success: true, ticket: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

module.exports = router;
