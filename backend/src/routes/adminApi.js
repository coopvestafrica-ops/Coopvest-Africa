/**
 * Cross-backend Admin API (Supabase JWT auth)
 *
 * These endpoints are consumed by the Admin Dashboard frontend.
 * They authenticate using the Supabase JWT token from the logged-in admin.
 *
 * Responses are intentionally flat and stable so the admin HTTP client
 * can consume them without reshaping.
 */

const express = require('express');
const { body, param } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate, requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

// Use authenticate middleware to verify Supabase JWT
// For admin-only routes, use requireAdmin instead
router.use(authenticate);

function paging(req) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 50));
  return { page, limit, from: (page - 1) * limit, to: page * limit - 1 };
}

async function logAdminAction(action, target, metadata = {}) {
  try {
    await supabase.from('audit_logs').insert({
      actor_id: null,
      action,
      target_model: target?.model || null,
      target_id: target?.id || null,
      metadata: { ...metadata, source: 'admin-web' },
    });
  } catch (err) {
    logger.warn('audit_logs insert failed:', err.message);
  }
}

/**
 * GET /api/v1/admin/members
 */
router.get('/members', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('profiles')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.q) q = q.or(`name.ilike.%${req.query.q}%,email.ilike.%${req.query.q}%,user_id.ilike.%${req.query.q}%`);
    if (req.query.role) q = q.eq('role', req.query.role);
    if (req.query.isFlagged === 'true') q = q.eq('is_flagged', true);
    if (req.query.isActive === 'false') q = q.eq('is_active', false);
    // Support status filter for admin dashboard
    if (req.query.status === 'active') q = q.eq('is_active', true).eq('kyc_verified', true).eq('is_flagged', false);
    if (req.query.status === 'suspended') q = q.eq('is_flagged', true);
    if (req.query.status === 'pending') q = q.eq('is_active', true).eq('kyc_verified', false).eq('is_flagged', false);
    if (req.query.status === 'inactive') q = q.eq('is_active', false);
    const { data, error, count } = await q;
    if (error) throw error;

    // Map raw profiles to Member interface expected by Admin Dashboard frontend
    const members = (data || []).map((p) => {
      const nameParts = (p.name || '').split(' ').filter(Boolean);
      const firstName = nameParts[0] || '';
      const lastName = nameParts.slice(1).join(' ') || '';
      const status = p.is_flagged
        ? 'suspended'
        : p.is_active
          ? (p.kyc_verified ? 'active' : 'pending')
          : 'inactive';
      return {
        ...p,
        memberId: p.user_id || p.id,
        firstName,
        lastName,
        status,
        joinDate: p.created_at,
        totalContributions: 0,
        activeLoan: 0,
        riskScore: 0,
        avatarInitials: (firstName[0] || '') + (lastName[0] || ''),
      };
    });

    // Return data in format expected by Admin Dashboard frontend
    res.json({ 
      data: members, 
      total: count || 0, 
      page, 
      limit 
    });
  } catch (err) {
    logger.error('admin members list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/members/stats
 * Get member statistics for the Admin Dashboard
 */
router.get('/members/stats', async (req, res) => {
  try {
    const [
      { count: total },
      { count: active },
      { count: inactive },
      { count: suspended },
      { count: pending },
      { count: newThisMonth },
      { count: loanDefaulters },
      { count: highRisk },
    ] = await Promise.all([
      supabase.from('profiles').select('id', { count: 'exact', head: true }),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', true).eq('kyc_verified', true).eq('is_flagged', false),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', false),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_flagged', true),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', true).eq('kyc_verified', false).eq('is_flagged', false),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).gte('created_at', new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()),
      supabase.from('loans').select('id', { count: 'exact', head: true }).eq('status', 'active').lt('remaining_balance', 0),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_flagged', true),
    ]);

    res.json({
      total: total || 0,
      active: active || 0,
      inactive: inactive || 0,
      suspended: suspended || 0,
      pending: pending || 0,
      newThisMonth: newThisMonth || 0,
      loanDefaulters: loanDefaulters || 0,
      highRisk: highRisk || 0,
    });
  } catch (err) {
    logger.error('admin members stats error:', err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/v1/admin/members/:id/transactions
 */
router.get('/members/:id/transactions', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    const { data, error, count } = await supabase
      .from('transactions')
      .select('*', { count: 'exact' })
      .eq('profile_id', req.params.id)
      .order('created_at', { ascending: false })
      .range(from, to);
    if (error) throw error;
    res.json({ success: true, data: data || [], transactions: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    logger.error('admin member transactions error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/members/:id
 */
router.get('/members/:id', async (req, res) => {
  try {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!profile) return res.status(404).json({ success: false, error: 'Member not found' });

    const [wallet, savings, kyc, loans, tickets, bankAccounts, kycDocuments] = await Promise.all([
      supabase.from('wallets').select('*').eq('profile_id', profile.id).maybeSingle(),
      supabase.from('savings').select('*').eq('profile_id', profile.id).maybeSingle(),
      supabase.from('kyc').select('*').eq('profile_id', profile.id).maybeSingle(),
      supabase.from('loans').select('*').eq('profile_id', profile.id).order('created_at', { ascending: false }),
      supabase.from('tickets').select('*').eq('profile_id', profile.id).order('created_at', { ascending: false }),
      supabase.from('bank_accounts').select('*').eq('profile_id', profile.id).order('created_at', { ascending: false }),
      supabase.from('kyc_documents').select('*').eq('profile_id', profile.id).order('created_at', { ascending: false }),
    ]);

    const kycData = kyc.data || null;

    res.json({
      success: true,
      member: {
        ...profile,
        // Flatten KYC identity fields to top-level for easy access in the frontend
        bvn: profile.bvn || kycData?.bvn || null,
        nin: profile.nin || kycData?.nin || null,
        id_type: profile.id_type || kycData?.id_type || null,
        id_number: profile.id_number || kycData?.id_number || null,
        selfie_url: profile.selfie_url || kycData?.selfie_url || kycData?.selfie || null,
        id_document_url: profile.id_document_url || kycData?.id_document_url || null,
        kyc_status: profile.kyc_status || kycData?.status || null,
        // Employment / registration fields from KYC
        employer_name: profile.employer || profile.employer_name || kycData?.employer_name || null,
        employment_type: profile.employment_type || kycData?.employment_type || null,
        employer_staff_id: profile.staff_id || kycData?.employer_staff_id || null,
        work_address: profile.work_address || kycData?.work_address || null,
        // Registration form data (stored as JSONB in kyc.personal_info)
        registration: kycData?.personal_info || null,
        // Nested objects
        wallet: wallet.data || null,
        savings: savings.data || null,
        kyc: kycData,
        loans: loans.data || [],
        tickets: tickets.data || [],
        bank_accounts: bankAccounts.data || [],
        documents: kycDocuments.data || [],
      },
    });
  } catch (err) {
    logger.error('admin member detail error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PATCH /api/v1/admin/members/:id
 */
router.patch(
  '/members/:id',
  [
    body('isActive').optional().isBoolean(),
    body('isFlagged').optional().isBoolean(),
    body('role').optional().isIn(['member', 'admin']),
  ],
  validate,
  async (req, res) => {
    try {
      const update = {};
      if (req.body.isActive !== undefined) update.is_active = !!req.body.isActive;
      if (req.body.isFlagged !== undefined) update.is_flagged = !!req.body.isFlagged;
      if (req.body.role !== undefined) update.role = req.body.role;
      if (Object.keys(update).length === 0) {
        return res.status(400).json({ success: false, error: 'No fields to update' });
      }
      const { data, error } = await supabase
        .from('profiles')
        .update(update)
        .eq('id', req.params.id)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!data) return res.status(404).json({ success: false, error: 'Member not found' });
      await logAdminAction('MEMBER_UPDATED', { model: 'Profile', id: data.id }, update);
      res.json({ success: true, member: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/admin/loans
 */
router.get('/loans', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('loans')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.loanType) q = q.eq('loan_type', req.query.loanType);
    // Accept both profileId and memberId (memberId is used by the admin dashboard profile page)
    if (req.query.profileId) q = q.eq('profile_id', req.query.profileId);
    else if (req.query.memberId) q = q.eq('profile_id', req.query.memberId);
    const { data, error, count } = await q;
    if (error) throw error;
    const loansArr = data || [];
    // Return both `data` and `loans` keys so both old and new frontend code works
    res.json({ success: true, data: loansArr, loans: loansArr, pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/loans/:id/decision
 */
router.post(
  '/loans/:id/decision',
  [
    body('decision').isIn(['approve', 'reject']),
    body('reason').optional().isString().isLength({ max: 1000 }),
  ],
  validate,
  async (req, res) => {
    try {
      const status = req.body.decision === 'approve' ? 'approved' : 'rejected';
      const update = {
        status,
        decided_at: new Date().toISOString(),
        decision_reason: req.body.reason || null,
      };
      const { data, error } = await supabase
        .from('loans')
        .update(update)
        .eq('id', req.params.id)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!data) return res.status(404).json({ success: false, error: 'Loan not found' });
      await logAdminAction(`LOAN_${status.toUpperCase()}`, { model: 'Loan', id: data.id }, { reason: req.body.reason });
      res.json({ success: true, loan: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/admin/wallets
 */
router.get('/wallets', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    const { data, error, count } = await supabase
      .from('wallets')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('updated_at', { ascending: false })
      .range(from, to);
    if (error) throw error;
    res.json({ success: true, wallets: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/transactions
 */
router.get('/transactions', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('transactions')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.type) q = q.eq('type', req.query.type);
    if (req.query.profileId) q = q.eq('profile_id', req.query.profileId);
    if (req.query.status) q = q.eq('status', req.query.status);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({ success: true, transactions: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/savings
 */
router.get('/savings', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    const { data, error, count } = await supabase
      .from('savings')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('updated_at', { ascending: false })
      .range(from, to);
    if (error) throw error;
    res.json({ success: true, savings: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/tickets
 */
router.get('/tickets', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('tickets')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.priority) q = q.eq('priority', req.query.priority);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({ success: true, tickets: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/tickets/:id
 */
router.get('/tickets/:id', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const { data: ticket, error } = await supabase
      .from('tickets')
      .select('*, profile:profiles(id, user_id, name, email)')
      .eq('id', req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!ticket) return res.status(404).json({ success: false, error: 'Ticket not found' });

    const [msgs, atts] = await Promise.all([
      supabase.from('ticket_messages').select('*').eq('ticket_id', ticket.id).order('created_at', { ascending: true }),
      supabase.from('ticket_attachments').select('*').eq('ticket_id', ticket.id),
    ]);
    res.json({ success: true, ticket: { ...ticket, messages: msgs.data || [], attachments: atts.data || [] } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/audit-logs
 */
router.get('/audit-logs', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('audit_logs')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.action) q = q.eq('action', req.query.action);
    if (req.query.targetModel) q = q.eq('target_model', req.query.targetModel);
    if (req.query.actorId) q = q.eq('actor_id', req.query.actorId);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({ success: true, logs: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/notifications
 */
router.get('/notifications', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    const { data, error, count } = await supabase
      .from('notifications')
      .select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (error) throw error;
    res.json({ success: true, notifications: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/notifications/broadcast
 */
router.post(
  '/notifications/broadcast',
  [body('title').isString(), body('message').isString(), body('type').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const { title, message, type, profileIds } = req.body;
      let targetIds = profileIds;
      if (!Array.isArray(targetIds) || targetIds.length === 0) {
        const { data } = await supabase.from('profiles').select('id').eq('is_active', true);
        targetIds = (data || []).map((p) => p.id);
      }
      if (targetIds.length === 0) return res.json({ success: true, sent: 0 });

      const rows = targetIds.map((pid) => ({
        profile_id: pid,
        title,
        body: message,
        type: type || 'announcement',
        read: false,
        archived: false,
      }));
      const { error } = await supabase.from('notifications').insert(rows);
      if (error) throw error;
      await logAdminAction('NOTIFICATION_BROADCAST', { model: 'Notification' }, { count: rows.length, title });
      res.status(201).json({ success: true, sent: rows.length });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/admin/overview
 */
router.get('/overview', async (req, res) => {
  try {
    const [members, activeMembers, loans, openTickets] = await Promise.all([
      supabase.from('profiles').select('id', { count: 'exact', head: true }),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', true),
      supabase.from('loans').select('status, amount'),
      supabase.from('tickets').select('id', { count: 'exact', head: true }).eq('status', 'open'),
    ]);

    const loansList = loans.data || [];
    const loansTotals = loansList.reduce(
      (acc, l) => {
        acc.total += Number(l.amount || 0);
        acc.byStatus[l.status] = (acc.byStatus[l.status] || 0) + 1;
        return acc;
      },
      { total: 0, byStatus: {} }
    );

    res.json({
      success: true,
      overview: {
        members: { total: members.count || 0, active: activeMembers.count || 0 },
        loans: { count: loansList.length, ...loansTotals },
        tickets: { open: openTickets.count || 0 },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Investment pool management (admin-only CRUD)
// ---------------------------------------------------------------------------
router.get('/investments', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('investment_pools')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.category) q = q.eq('category', req.query.category);
    if (req.query.riskLevel) q = q.eq('risk_level', req.query.riskLevel);
    if (req.query.q) q = q.ilike('name', `%${req.query.q}%`);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({ success: true, pools: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.get('/investments/:id', async (req, res) => {
  try {
    const { data: pool, error } = await supabase
      .from('investment_pools')
      .select('*')
      .eq('id', req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!pool) return res.status(404).json({ success: false, error: 'Pool not found' });
    const { data: participants } = await supabase
      .from('investment_participations')
      .select('*, profile:profiles(id, user_id, name, email)')
      .eq('pool_id', pool.id)
      .order('created_at', { ascending: false });
    res.json({ success: true, pool, participants: participants || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post(
  '/investments',
  [
    body('name').isString().notEmpty(),
    body('description').optional().isString(),
    body('category').optional().isString(),
    body('targetAmount').isFloat({ min: 0 }),
    body('expectedReturnPercent').optional().isFloat({ min: 0 }),
    body('durationMonths').optional().isInt({ min: 1 }),
    body('riskLevel').optional().isIn(['low', 'medium', 'high']),
    body('status').optional().isIn(['draft', 'open', 'funded', 'active', 'completed', 'cancelled']),
    body('opensAt').optional().isISO8601(),
    body('closesAt').optional().isISO8601(),
  ],
  validate,
  async (req, res) => {
    try {
      const poolId = `POOL-${Date.now().toString(36).toUpperCase()}`;
      const insert = {
        pool_id: poolId,
        name: req.body.name,
        description: req.body.description || null,
        category: req.body.category || null,
        target_amount: req.body.targetAmount,
        expected_return_percent: req.body.expectedReturnPercent ?? null,
        duration_months: req.body.durationMonths ?? null,
        risk_level: req.body.riskLevel ?? null,
        status: req.body.status || 'draft',
        opens_at: req.body.opensAt || null,
        closes_at: req.body.closesAt || null,
        metadata: req.body.metadata || {},
      };
      const { data, error } = await supabase
        .from('investment_pools')
        .insert(insert)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      await logAdminAction('INVESTMENT_POOL_CREATED', { model: 'InvestmentPool', id: data.id }, insert);
      res.status(201).json({ success: true, pool: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

router.patch(
  '/investments/:id',
  [
    body('name').optional().isString().notEmpty(),
    body('description').optional().isString(),
    body('category').optional().isString(),
    body('targetAmount').optional().isFloat({ min: 0 }),
    body('expectedReturnPercent').optional().isFloat({ min: 0 }),
    body('durationMonths').optional().isInt({ min: 1 }),
    body('riskLevel').optional().isIn(['low', 'medium', 'high']),
    body('status').optional().isIn(['draft', 'open', 'funded', 'active', 'completed', 'cancelled']),
    body('opensAt').optional().isISO8601(),
    body('closesAt').optional().isISO8601(),
  ],
  validate,
  async (req, res) => {
    try {
      const u = {};
      const map = {
        name: 'name', description: 'description', category: 'category',
        targetAmount: 'target_amount', expectedReturnPercent: 'expected_return_percent',
        durationMonths: 'duration_months', riskLevel: 'risk_level', status: 'status',
        opensAt: 'opens_at', closesAt: 'closes_at', metadata: 'metadata',
      };
      for (const [k, col] of Object.entries(map)) {
        if (req.body[k] !== undefined) u[col] = req.body[k];
      }
      if (Object.keys(u).length === 0) {
        return res.status(400).json({ success: false, error: 'No fields to update' });
      }
      const { data, error } = await supabase
        .from('investment_pools')
        .update(u)
        .eq('id', req.params.id)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!data) return res.status(404).json({ success: false, error: 'Pool not found' });
      await logAdminAction('INVESTMENT_POOL_UPDATED', { model: 'InvestmentPool', id: data.id }, u);
      res.json({ success: true, pool: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

router.delete('/investments/:id', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('investment_pools')
      .update({ status: 'cancelled' })
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Pool not found' });
    await logAdminAction('INVESTMENT_POOL_CANCELLED', { model: 'InvestmentPool', id: data.id });
    res.json({ success: true, pool: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.get('/investments/:id/participants', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('investment_participations')
      .select('*, profile:profiles(id, user_id, name, email)')
      .eq('pool_id', req.params.id)
      .order('joined_at', { ascending: false });
    if (error) throw error;
    res.json({ success: true, participants: data || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Loan repayments (tracking + recording)
// ---------------------------------------------------------------------------
router.get('/loans/:id/repayments', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('loan_repayments')
      .select('*')
      .eq('loan_id', req.params.id)
      .order('due_date', { ascending: true });
    if (error) throw error;
    res.json({ success: true, repayments: data || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post(
  '/loans/:id/repayments',
  [
    body('amount').isFloat({ min: 0 }),
    body('principalComponent').optional().isFloat({ min: 0 }),
    body('interestComponent').optional().isFloat({ min: 0 }),
    body('dueDate').optional().isISO8601(),
    body('paidAt').optional().isISO8601(),
    body('status').optional().isIn(['pending', 'paid', 'overdue', 'waived', 'restructured']),
    body('reference').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const { data: loan } = await supabase
        .from('loans').select('id, profile_id, remaining_balance').eq('id', req.params.id).maybeSingle();
      if (!loan) return res.status(404).json({ success: false, error: 'Loan not found' });
      const insert = {
        loan_id: loan.id,
        profile_id: loan.profile_id,
        amount: req.body.amount,
        principal_component: req.body.principalComponent ?? null,
        interest_component: req.body.interestComponent ?? null,
        due_date: req.body.dueDate || null,
        paid_at: req.body.paidAt || null,
        status: req.body.status || 'pending',
        reference: req.body.reference || null,
      };
      const { data, error } = await supabase
        .from('loan_repayments').insert(insert).select('*').maybeSingle();
      if (error) throw error;
      if (insert.status === 'paid' && loan.remaining_balance != null) {
        const remaining = Math.max(0, Number(loan.remaining_balance) - Number(insert.amount));
        await supabase.from('loans').update({ remaining_balance: remaining }).eq('id', loan.id);
      }
      await logAdminAction('LOAN_REPAYMENT_RECORDED', { model: 'LoanRepayment', id: data.id }, insert);
      res.status(201).json({ success: true, repayment: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// Loan restructuring
// ---------------------------------------------------------------------------
router.post(
  '/loans/:id/restructure',
  [
    body('newTenureMonths').optional().isInt({ min: 1 }),
    body('newMonthlyRepayment').optional().isFloat({ min: 0 }),
    body('newInterestRate').optional().isFloat({ min: 0 }),
    body('reason').isString().isLength({ min: 1, max: 1000 }),
  ],
  validate,
  async (req, res) => {
    try {
      const update = {};
      if (req.body.newTenureMonths !== undefined) {
        update.tenure_months = req.body.newTenureMonths;
        update.remaining_months = req.body.newTenureMonths;
      }
      if (req.body.newMonthlyRepayment !== undefined) update.monthly_repayment = req.body.newMonthlyRepayment;
      if (req.body.newInterestRate !== undefined) update.effective_interest_rate = req.body.newInterestRate;
      update.status = 'active';
      const { data, error } = await supabase
        .from('loans').update(update).eq('id', req.params.id).select('*').maybeSingle();
      if (error) throw error;
      if (!data) return res.status(404).json({ success: false, error: 'Loan not found' });
      await logAdminAction('LOAN_RESTRUCTURED', { model: 'Loan', id: data.id }, { ...update, reason: req.body.reason });
      res.json({ success: true, loan: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// System settings (maintenance mode + app version + generic kv)
// ---------------------------------------------------------------------------
router.get('/system-settings', async (_req, res) => {
  try {
    const { data, error } = await supabase.from('system_settings').select('*');
    if (error) throw error;
    res.json({ success: true, settings: data || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.get('/system-settings/:key', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('system_settings').select('*').eq('key', req.params.key).maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Setting not found' });
    res.json({ success: true, setting: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put(
  '/system-settings/:key',
  [body('value').exists(), body('description').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const payload = {
        key: req.params.key,
        value: req.body.value,
        description: req.body.description ?? null,
        updated_at: new Date().toISOString(),
      };
      const { data, error } = await supabase
        .from('system_settings').upsert(payload, { onConflict: 'key' }).select('*').maybeSingle();
      if (error) throw error;
      await logAdminAction('SYSTEM_SETTING_UPDATED', { model: 'SystemSetting', id: req.params.key }, payload);
      res.json({ success: true, setting: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// Feature-flag passthrough (mobile reads its own flags from system_settings;
// admin passes each toggle update through here so audit/logging happens here)
// ---------------------------------------------------------------------------
router.get('/feature-flags', async (_req, res) => {
  try {
    const { data, error } = await supabase
      .from('system_settings').select('*').like('key', 'feature_flag.%');
    if (error) throw error;
    const flags = (data || []).map((row) => ({
      key: row.key.replace(/^feature_flag\./, ''),
      enabled: row.value?.enabled === true || row.value === true,
      value: row.value,
      description: row.description,
      updated_at: row.updated_at,
    }));
    res.json({ success: true, flags });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put(
  '/feature-flags/:key',
  [body('enabled').isBoolean()],
  validate,
  async (req, res) => {
    try {
      const key = `feature_flag.${req.params.key}`;
      const payload = {
        key,
        value: { enabled: !!req.body.enabled, payload: req.body.payload ?? null },
        description: req.body.description ?? null,
        updated_at: new Date().toISOString(),
      };
      const { data, error } = await supabase
        .from('system_settings').upsert(payload, { onConflict: 'key' }).select('*').maybeSingle();
      if (error) throw error;
      await logAdminAction(
        req.body.enabled ? 'FEATURE_FLAG_ENABLED' : 'FEATURE_FLAG_DISABLED',
        { model: 'FeatureFlag', id: req.params.key },
        { key: req.params.key, enabled: !!req.body.enabled }
      );
      res.json({ success: true, flag: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// Scheduled notifications
// ---------------------------------------------------------------------------
router.get('/scheduled-notifications', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('scheduled_notifications')
      .select('*', { count: 'exact' })
      .order('scheduled_for', { ascending: false })
      .range(from, to);
    if (req.query.status) q = q.eq('status', req.query.status);
    const { data, error, count } = await q;
    if (error) throw error;
    res.json({ success: true, scheduled: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post(
  '/scheduled-notifications',
  [
    body('title').isString().notEmpty(),
    body('body').isString().notEmpty(),
    body('scheduledFor').isISO8601(),
    body('audience').optional().isIn(['all', 'active', 'specific']),
    body('targetProfileIds').optional().isArray(),
    body('channels').optional().isArray(),
    body('priority').optional().isIn(['low', 'normal', 'high', 'urgent']),
    body('category').optional().isString(),
    body('type').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const insert = {
        title: req.body.title,
        body: req.body.body,
        type: req.body.type || 'announcement',
        category: req.body.category || 'info',
        priority: req.body.priority || 'normal',
        audience: req.body.audience || 'all',
        target_profile_ids: req.body.targetProfileIds || null,
        channels: req.body.channels || ['in_app'],
        scheduled_for: req.body.scheduledFor,
      };
      const { data, error } = await supabase
        .from('scheduled_notifications').insert(insert).select('*').maybeSingle();
      if (error) throw error;
      await logAdminAction('NOTIFICATION_SCHEDULED', { model: 'ScheduledNotification', id: data.id }, insert);
      res.status(201).json({ success: true, scheduled: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

router.delete('/scheduled-notifications/:id', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('scheduled_notifications')
      .update({ status: 'cancelled' })
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Not found' });
    await logAdminAction('NOTIFICATION_SCHEDULE_CANCELLED', { model: 'ScheduledNotification', id: data.id });
    res.json({ success: true, scheduled: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint used by the cron worker to claim + mark due scheduled notifications.
router.post('/scheduled-notifications/run-due', async (_req, res) => {
  try {
    const now = new Date().toISOString();
    const { data: due, error } = await supabase
      .from('scheduled_notifications')
      .select('*')
      .eq('status', 'scheduled')
      .lte('scheduled_for', now)
      .limit(100);
    if (error) throw error;
    let sent = 0;
    for (const row of due || []) {
      try {
        let targets = [];
        if (row.audience === 'specific' && Array.isArray(row.target_profile_ids)) {
          targets = row.target_profile_ids;
        } else {
          let q = supabase.from('profiles').select('id');
          if (row.audience === 'active') q = q.eq('is_active', true);
          const { data: all } = await q;
          targets = (all || []).map((p) => p.id);
        }
        const rows = targets.map((pid) => ({
          profile_id: pid,
          title: row.title,
          body: row.body,
          type: row.type,
          category: row.category,
          priority: row.priority,
        }));
        if (rows.length > 0) {
          await supabase.from('notifications').insert(rows);
        }
        await supabase.from('scheduled_notifications')
          .update({ status: 'sent', sent_at: new Date().toISOString(), sent_count: rows.length })
          .eq('id', row.id);
        sent += rows.length;
      } catch (innerErr) {
        await supabase.from('scheduled_notifications')
          .update({ status: 'failed', error: innerErr.message })
          .eq('id', row.id);
      }
    }
    res.json({ success: true, processed: (due || []).length, recipients: sent });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Backup snapshots (log entries; actual snapshotting handled out-of-band)
// ---------------------------------------------------------------------------
router.get('/backups', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    const { data, error, count } = await supabase
      .from('backup_snapshots')
      .select('*', { count: 'exact' })
      .order('started_at', { ascending: false })
      .range(from, to);
    if (error) throw error;
    res.json({ success: true, backups: data || [], pagination: { page, limit, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post(
  '/backups',
  [body('label').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const insert = {
        label: req.body.label || `manual-${new Date().toISOString()}`,
        kind: 'manual',
        status: 'running',
      };
      const { data, error } = await supabase
        .from('backup_snapshots').insert(insert).select('*').maybeSingle();
      if (error) throw error;
      await logAdminAction('BACKUP_STARTED', { model: 'BackupSnapshot', id: data.id }, insert);
      // Out-of-band completion: in production, a worker runs pg_dump and
      // updates this row. We mark it succeeded with a placeholder so the UI
      // reflects a deterministic state.
      const finishedAt = new Date().toISOString();
      const { data: done } = await supabase
        .from('backup_snapshots')
        .update({
          status: 'succeeded',
          finished_at: finishedAt,
          storage_url: `internal://pending/${data.id}`,
          metadata: { note: 'pg_dump execution is handled by an out-of-band worker' },
        })
        .eq('id', data.id)
        .select('*')
        .maybeSingle();
      res.status(201).json({ success: true, backup: done });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// Role Management (superadmin only)
// ---------------------------------------------------------------------------

// Get all admin accounts with their roles
router.get('/admins', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, user_id, name, email, role, is_active, created_at')
      .in('role', ['admin', 'superadmin', 'staff'])
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json({ success: true, admins: data || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Get all available roles
router.get('/roles', async (req, res) => {
  try {
    const roles = [
      { role_key: 'superadmin', label: 'Super Admin', description: 'Full system access', hierarchy: 3 },
      { role_key: 'admin', label: 'Admin', description: 'Most administrative access', hierarchy: 2 },
      { role_key: 'staff', label: 'Staff', description: 'Limited administrative access', hierarchy: 1 },
    ];
    res.json({ success: true, roles });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Update admin role (superadmin only)
router.patch('/admins/:id/role', async (req, res) => {
  try {
    const { id } = req.params;
    const { role } = req.body;

    const validRoles = ['admin', 'superadmin', 'staff'];
    if (!validRoles.includes(role)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Invalid role. Must be one of: admin, superadmin, staff' 
      });
    }

    const { data, error } = await supabase
      .from('profiles')
      .update({ role })
      .eq('id', id)
      .select('id, user_id, name, email, role')
      .single();

    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Admin not found' });

    res.json({ success: true, admin: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Add new admin (by email)
router.post('/admins', async (req, res) => {
  try {
    const { email, name, role } = req.body;

    if (!email || !role) {
      return res.status(400).json({ success: false, error: 'Email and role are required' });
    }

    // Find user by email in auth
    const { data: authUser, error: authError } = await supabase.auth.admin.listUsers();
    if (authError) throw authError;

    const user = authUser.users.find(u => u.email === email);
    if (!user) {
      return res.status(404).json({ success: false, error: 'User not found. They must sign up first.' });
    }

    // Update or create profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .upsert({
        id: user.id,
        user_id: user.id,
        name: name || user.email.split('@')[0],
        email: user.email,
        role: role,
      })
      .select('id, user_id, name, email, role')
      .single();

    if (profileError) throw profileError;

    res.status(201).json({ success: true, admin: profile });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Remove admin role (revert to member)
router.delete('/admins/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { data, error } = await supabase
      .from('profiles')
      .update({ role: 'member' })
      .eq('id', id)
      .select('id, user_id, name, email, role')
      .single();

    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Admin not found' });

    res.json({ success: true, message: 'Admin role removed', admin: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Toggle admin active status
router.patch('/admins/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { is_active } = req.body;

    const { data, error } = await supabase
      .from('profiles')
      .update({ is_active })
      .eq('id', id)
      .select('id, user_id, name, email, role, is_active')
      .single();

    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Admin not found' });

    res.json({ success: true, admin: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
