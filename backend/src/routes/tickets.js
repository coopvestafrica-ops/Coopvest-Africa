/**
 * Support Ticket Routes (member-facing)
 *
 * Writes to Supabase tables `tickets`, `ticket_messages`, `ticket_attachments`
 * using the canonical schema (see backend/supabase_schema.sql):
 *   tickets:         ticket_id (human ref), profile_id, category, priority,
 *                    status, title, description, assigned_staff_id, ...
 *   ticket_messages: ticket_id (uuid FK), author_id, author_role
 *                    ('member'|'staff'|'system'), body, is_internal, ...
 *
 * The same tables are read/written by the Admin dashboard backend, so a
 * complaint raised on mobile shows up for admins and admin replies flow back
 * to the member. Responses are normalised to camelCase to match the Flutter
 * support screens.
 */

const express = require('express');
const { body, param } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

router.use(authenticate);

// Categories allowed by the DB CHECK constraint on tickets.category
const TICKET_CATEGORIES = [
  'loan_issue',
  'guarantor_consent',
  'referral_bonus',
  'repayment_issue',
  'account_kyc',
  'contribution',
  'withdrawal',
  'technical_bug',
  'complaint',
  'other',
];

// Human-friendly reference stored in tickets.ticket_id (NOT the UUID PK).
const newTicketRef = () => `TK-${Date.now().toString(36).toUpperCase()}`;

/** Normalise a tickets row to the shape the mobile app expects. */
const serializeTicket = (row) => ({
  id: row.id, // UUID primary key — used for path operations
  ticketId: row.ticket_id, // human reference (TK-XXXX) for display
  userId: row.profile_id,
  category: row.category,
  priority: row.priority,
  status: row.status,
  title: row.title,
  subject: row.title, // alias for older screens
  description: row.description,
  assignedStaffId: row.assigned_staff_id ?? null,
  resolution: row.resolution ?? null,
  resolvedAt: row.resolved_at ?? null,
  createdAt: row.created_at,
  updatedAt: row.updated_at ?? row.created_at,
});

/** Normalise a ticket_messages row. memberId is the requesting member's id. */
const serializeMessage = (row, memberId) => ({
  id: row.id,
  ticketId: row.ticket_id,
  authorId: row.author_id,
  authorRole: row.author_role,
  // The member's own messages render on the right (senderType === 'user').
  senderType: row.author_id && row.author_id === memberId ? 'user' : 'admin',
  content: row.body,
  body: row.body,
  createdAt: row.created_at,
});

/**
 * POST /api/v1/tickets
 * Create a new support ticket (complaint).
 */
router.post(
  '/',
  [
    body('title').optional().isString().isLength({ min: 3, max: 200 }),
    body('subject').optional().isString().isLength({ min: 3, max: 200 }),
    body('description').optional().isString().isLength({ min: 3, max: 5000 }),
    body('message').optional().isString().isLength({ min: 3, max: 5000 }),
    body('category').optional().isString(),
    body('priority').optional().isIn(['low', 'medium', 'high', 'urgent']),
  ],
  validate,
  async (req, res) => {
    try {
      const title = (req.body.title || req.body.subject || '').trim();
      const description = (req.body.description || req.body.message || '').trim();
      const category = TICKET_CATEGORIES.includes(req.body.category)
        ? req.body.category
        : 'other';
      const priority = req.body.priority || 'medium';

      if (!title || title.length < 3) {
        return res.status(400).json({ success: false, error: 'A title is required' });
      }
      if (!description || description.length < 3) {
        return res.status(400).json({ success: false, error: 'A description is required' });
      }

      const { data: ticket, error } = await supabase
        .from('tickets')
        .insert({
          ticket_id: newTicketRef(),
          profile_id: req.user.id,
          title,
          description,
          category,
          priority,
          status: 'open',
        })
        .select('*')
        .single();
      if (error) throw error;

      // Seed the conversation with the member's opening message.
      await supabase.from('ticket_messages').insert({
        ticket_id: ticket.id,
        author_id: req.user.id,
        author_role: 'member',
        body: description,
      });

      res.status(201).json({ success: true, ticket: serializeTicket(ticket) });
    } catch (err) {
      logger.error('ticket create error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/tickets
 */
router.get('/', async (req, res) => {
  try {
    let q = supabase
      .from('tickets')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.category) q = q.eq('category', req.query.category);
    const { data, error } = await q;
    if (error) throw error;
    res.json({ success: true, tickets: (data || []).map(serializeTicket) });
  } catch (err) {
    logger.error('ticket list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/tickets/:id
 * Returns the ticket plus its (non-internal) messages and attachments.
 */
router.get('/:id', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const { data: ticket, error } = await supabase
      .from('tickets')
      .select('*')
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .maybeSingle();
    if (error) throw error;
    if (!ticket) return res.status(404).json({ success: false, error: 'Ticket not found' });

    const [msgsRes, attsRes] = await Promise.all([
      supabase
        .from('ticket_messages')
        .select('*')
        .eq('ticket_id', ticket.id)
        .eq('is_internal', false)
        .order('created_at', { ascending: true }),
      supabase
        .from('ticket_attachments')
        .select('*')
        .eq('ticket_id', ticket.id)
        .order('created_at', { ascending: true }),
    ]);
    if (msgsRes.error) throw msgsRes.error;
    if (attsRes.error) throw attsRes.error;

    const messages = (msgsRes.data || []).map((m) => serializeMessage(m, req.user.id));
    res.json({
      success: true,
      ticket: { ...serializeTicket(ticket), messages },
      messages,
      attachments: attsRes.data || [],
    });
  } catch (err) {
    logger.error('ticket detail error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/tickets/:id/messages  (also accepts /reply for back-compat)
 * Member adds a reply to their ticket.
 */
const handleMemberReply = async (req, res) => {
  try {
    const content = (req.body.content || req.body.body || req.body.message || '').trim();
    if (!content) {
      return res.status(400).json({ success: false, error: 'A message is required' });
    }

    const { data: ticket, error } = await supabase
      .from('tickets')
      .select('id, status')
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .maybeSingle();
    if (error) throw error;
    if (!ticket) return res.status(404).json({ success: false, error: 'Ticket not found' });

    const { data: msg, error: mErr } = await supabase
      .from('ticket_messages')
      .insert({
        ticket_id: ticket.id,
        author_id: req.user.id,
        author_role: 'member',
        body: content,
      })
      .select('*')
      .single();
    if (mErr) throw mErr;

    // Re-open resolved/closed tickets when the member responds again.
    const nextStatus = ['resolved', 'closed'].includes(ticket.status)
      ? 'in_progress'
      : ticket.status;
    await supabase
      .from('tickets')
      .update({
        status: nextStatus,
        last_user_response_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', ticket.id);

    res.status(201).json({ success: true, message: serializeMessage(msg, req.user.id) });
  } catch (err) {
    logger.error('ticket reply error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
};

router.post('/:id/messages', [param('id').isUUID(), body('content').optional().isString()], validate, handleMemberReply);
router.post('/:id/reply', [param('id').isUUID()], validate, handleMemberReply);

/**
 * PATCH /api/v1/tickets/:id/close  (also accepts PATCH /:id with {status})
 * Member closes their own ticket.
 */
const handleClose = async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('tickets')
      .update({ status: 'closed', resolved_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Ticket not found' });
    res.json({ success: true, ticket: serializeTicket(data) });
  } catch (err) {
    logger.error('ticket close error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
};

router.patch('/:id/close', [param('id').isUUID()], validate, handleClose);
router.patch('/:id', [param('id').isUUID()], validate, (req, res, next) => {
  if ((req.body.status || '').toLowerCase() === 'closed') return handleClose(req, res);
  return res.status(400).json({ success: false, error: 'Unsupported ticket update' });
});

module.exports = router;
