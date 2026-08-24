/**
 * Admin Platform Extensions
 *
 * Adds the financial-operations modules that a savings/loans cooperative needs
 * beyond plain CRUD:
 *
 *   1. Emergency Control Center     — granular kill switches + read-only mode
 *   2. Financial Ledger             — append-only double-entry ledger with
 *                                      running balances and reversals
 *   3. System-Wide Search            — one query across every entity
 *   4. Super Admin "Attention Required" — aggregate of everything pending
 *   5. Loan Approval Matrix           — configurable amount thresholds per role
 *   6. Notification Template Manager  — editable message templates + channels
 *   7. Organization Payroll Reconciliation — expected vs actual variance
 *
 * All routes are mounted under the Admin API router and therefore inherit the
 * `requireAdmin` guard. Sensitive mutations additionally require the Super
 * Admin role.
 *
 * Configuration is stored in the existing `system_settings` key/value table
 * (jsonb `value`) so no schema migration is required to enable these features.
 * The optional `ledger_entries` table (see supabase/migrations/) enables true
 * double-entry persistence; when absent the ledger falls back to a computed
 * view over the existing `transactions` table.
 */

const express = require('express');
const { body, param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { requireSuperAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SUPER_ADMIN_ROLES = ['superadmin', 'super_admin'];
const isSuperAdmin = (req) => SUPER_ADMIN_ROLES.includes(req.user?.role || '');

async function logAdminAction(action, target, metadata = {}, req = null) {
  try {
    const ip = (req?.headers['x-forwarded-for'] || '').split(',')[0].trim() || null;
    await supabase.from('audit_logs').insert({
      actor_id: req?.user?.id || null,
      actor_role: req?.user?.role || null,
      action,
      target_model: target?.model || null,
      target_id: target?.id || null,
      metadata: { ...metadata, source: 'admin-web' },
      ip_address: ip || null,
      user_agent: req?.headers['user-agent'] || null,
    });
  } catch (err) {
    logger.warn('audit_logs insert failed:', err.message);
  }
}

async function getSetting(key, fallback) {
  const { data } = await supabase.from('system_settings').select('value').eq('key', key).maybeSingle();
  return data?.value ?? fallback;
}

async function setSetting(key, value, description = null) {
  const { data, error } = await supabase
    .from('system_settings')
    .upsert({ key, value, description, updated_at: new Date().toISOString() }, { onConflict: 'key' })
    .select('*').maybeSingle();
  if (error) throw error;
  return data;
}

// Map a profile_id to a display name (best-effort, cached per request batch).
async function profileNameMap(profileIds) {
  const ids = [...new Set((profileIds || []).filter(Boolean))];
  if (ids.length === 0) return {};
  const { data } = await supabase.from('profiles').select('id, name, email, user_id').in('id', ids);
  const map = {};
  (data || []).forEach((p) => { map[p.id] = p.name || p.email || p.user_id || p.id; });
  return map;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. EMERGENCY CONTROL CENTER
// ─────────────────────────────────────────────────────────────────────────────
// Keys live under `emergency.*` in system_settings. The middleware in
// src/middleware/systemStatus.js reads the same keys, so flipping a switch
// here takes effect immediately across the whole API.

const EMERGENCY_KEYS = [
  'emergency.freeze_loans',
  'emergency.freeze_withdrawals',
  'emergency.freeze_registration',
  'emergency.freeze_contribution_adjustments',
  'emergency.freeze_payment_proof_approval',
  'emergency.read_only',
  'emergency.force_logout_all',
  'emergency.disable_compromised_admin',
];

const DEFAULT_EMERGENCY = {
  freezeLoans: false,
  freezeWithdrawals: false,
  freezeRegistration: false,
  freezeContributionAdjustments: false,
  freezePaymentProofApproval: false,
  readOnly: false,
  forceLogoutAll: false,
  message: null,
  updatedAt: null,
};

async function loadEmergencyState() {
  const { data } = await supabase.from('system_settings').select('key, value').like('key', 'emergency.%');
  const map = {};
  (data || []).forEach((r) => { map[r.key] = r.value; });
  return {
    freezeLoans: !!(map['emergency.freeze_loans'] ?? false),
    freezeWithdrawals: !!(map['emergency.freeze_withdrawals'] ?? false),
    freezeRegistration: !!(map['emergency.freeze_registration'] ?? false),
    freezeContributionAdjustments: !!(map['emergency.freeze_contribution_adjustments'] ?? false),
    freezePaymentProofApproval: !!(map['emergency.freeze_payment_proof_approval'] ?? false),
    readOnly: !!(map['emergency.read_only'] ?? false),
    forceLogoutAll: !!(map['emergency.force_logout_all'] ?? false),
    disableCompromisedAdmin: map['emergency.disable_compromised_admin'] ?? null,
    message: map['emergency.message'] ?? null,
    updatedAt: map['emergency.updated_at'] ?? null,
  };
}

router.get('/emergency-controls', async (_req, res) => {
  try {
    res.json({ success: true, state: await loadEmergencyState() });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put(
  '/emergency-controls',
  [
    body('freezeLoans').optional().isBoolean(),
    body('freezeWithdrawals').optional().isBoolean(),
    body('freezeRegistration').optional().isBoolean(),
    body('freezeContributionAdjustments').optional().isBoolean(),
    body('freezePaymentProofApproval').optional().isBoolean(),
    body('readOnly').optional().isBoolean(),
    body('forceLogoutAll').optional().isBoolean(),
    body('message').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      if (!isSuperAdmin(req)) return res.status(403).json({ success: false, error: 'Only the Super Admin may operate emergency controls' });
      const b = req.body || {};
      const updates = [];
      const map = {
        freezeLoans: 'emergency.freeze_loans',
        freezeWithdrawals: 'emergency.freeze_withdrawals',
        freezeRegistration: 'emergency.freeze_registration',
        freezeContributionAdjustments: 'emergency.freeze_contribution_adjustments',
        freezePaymentProofApproval: 'emergency.freeze_payment_proof_approval',
        readOnly: 'emergency.read_only',
        forceLogoutAll: 'emergency.force_logout_all',
      };
      for (const [field, key] of Object.entries(map)) {
        if (b[field] !== undefined) updates.push(setSetting(key, !!b[field]));
      }
      if (b.message !== undefined) updates.push(setSetting('emergency.message', b.message || null));
      const now = new Date().toISOString();
      updates.push(setSetting('emergency.updated_at', now));
      await Promise.all(updates);

      await logAdminAction('EMERGENCY_CONTROL_UPDATED', { model: 'EmergencyControl' }, {
        changes: b,
        admin: req.user.email,
      }, req);

      res.json({ success: true, state: await loadEmergencyState() });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// Instantly disable a compromised admin account (sets is_active=false + logs).
router.post(
  '/emergency-controls/disable-admin',
  [body('adminId').isUUID()],
  validate,
  async (req, res) => {
    try {
      if (!isSuperAdmin(req)) return res.status(403).json({ success: false, error: 'Only the Super Admin may disable an admin account' });
      const { adminId } = req.body;
      const { data, error } = await supabase
        .from('profiles').update({ is_active: false }).eq('id', adminId).select('id, name, email').maybeSingle();
      if (error) throw error;
      await setSetting('emergency.disable_compromised_admin', { adminId, at: new Date().toISOString() });
      await logAdminAction('ADMIN_DISABLED_EMERGENCY', { model: 'Profile', id: adminId }, {
        admin: req.user.email, disabled: data,
      }, req);
      res.json({ success: true, disabled: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. FINANCIAL LEDGER (double-entry, running balance, reversals)
// ─────────────────────────────────────────────────────────────────────────────

const LEDGER_CATEGORY_DEBIT = 'debit';
const LEDGER_CATEGORY_CREDIT = 'credit';

// Normalize a transactions row into a ledger entry shape with a running
// balance computed in-memory (oldest → newest) for the requested profile.
function buildLedgerFromTransactions(rows, profileId) {
  const sorted = (rows || [])
    .filter((r) => r.profile_id === profileId || !profileId)
    .sort((a, b) => (a.created_at < b.created_at ? -1 : 1));
  let running = 0;
  return sorted.map((r) => {
    const amount = Number(r.amount || 0);
    const isCredit = (r.category || '').toLowerCase() === 'credit';
    running += isCredit ? amount : -amount;
    return {
      id: r.id,
      transactionId: r.id,
      profileId: r.profile_id,
      reference: r.reference || null,
      type: r.type || null,
      description: r.description || r.type || null,
      debit: isCredit ? 0 : amount,
      credit: isCredit ? amount : 0,
      amount: isCredit ? amount : -amount,
      previousBalance: running - (isCredit ? amount : -amount),
      newBalance: running,
      source: r.source || 'system',
      status: r.status || 'completed',
      initiatedBy: r.initiated_by || null,
      reversed: false,
      reversalOf: null,
      createdAt: r.created_at,
    };
  });
}

router.get('/ledger', async (req, res) => {
  try {
    const { page, limit } = req.query;
    const p = Math.max(1, parseInt(page, 10) || 1);
    const l = Math.min(200, parseInt(limit, 10) || 50);

    // Prefer a dedicated ledger_entries table when it exists.
    let data = null;
    let error = null;
    let count = 0;
    let usedFallback = false;

    let baseQuery = supabase.from('ledger_entries').select('*', { count: 'exact' });
    if (req.query.profileId) baseQuery = baseQuery.eq('profile_id', req.query.profileId);
    if (req.query.type) baseQuery = baseQuery.eq('type', req.query.type);
    if (req.query.reference) baseQuery = baseQuery.eq('reference', req.query.reference);
    if (req.query.from) baseQuery = baseQuery.gte('created_at', req.query.from);
    if (req.query.to) baseQuery = baseQuery.lte('created_at', req.query.to);
    const r1 = await baseQuery.order('created_at', { ascending: false }).range((p - 1) * l, p * l - 1);
    if (r1.error && /relation .* does not exist|Could not find|PGRST/i.test(r1.error.message)) {
      usedFallback = true;
    } else {
      data = r1.data; error = r1.error; count = r1.count || 0;
    }

    if (usedFallback) {
      // Fallback: compute the ledger from the transactions table.
      let tq = supabase.from('transactions').select('*, profile:profiles(id, user_id, name, email)', { count: 'exact' });
      if (req.query.profileId) tq = tq.eq('profile_id', req.query.profileId);
      if (req.query.type) tq = tq.eq('type', req.query.type);
      if (req.query.reference) tq = tq.eq('reference', req.query.reference);
      if (req.query.from) tq = tq.gte('created_at', req.query.from);
      if (req.query.to) tq = tq.lte('created_at', req.query.to);
      const r2 = await tq.order('created_at', { ascending: false }).range((p - 1) * l, p * l - 1);
      data = (r2.data || []).map((t) => {
        const amount = Number(t.amount || 0);
        const isCredit = (t.category || '').toLowerCase() === 'credit';
        return {
          id: t.id, transactionId: t.id, profileId: t.profile_id,
          memberName: t.profile?.name || t.profile?.email || null,
          reference: t.reference || null, type: t.type || null,
          description: t.description || t.type || null,
          debit: isCredit ? 0 : amount, credit: isCredit ? amount : 0,
          amount: isCredit ? amount : -amount,
          source: t.source || 'system', status: t.status || 'completed',
          reversed: false, reversalOf: null, createdAt: t.created_at,
          fallback: true,
        };
      });
      count = r2.count || 0;
      error = null;
    }

    if (error) throw error;

    // Enrich with member names when not already present.
    let rows = data || [];
    if (rows.length && !rows[0].memberName && !usedFallback) {
      const names = await profileNameMap(rows.map((r) => r.profile_id));
      rows = rows.map((r) => ({ ...r, memberName: names[r.profile_id] || null }));
    }

    res.json({
      success: true,
      ledger: rows,
      pagination: { page: p, limit: l, total: count },
      fallback: usedFallback,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Per-member ledger with computed running balance (works on transactions).
router.get('/ledger/member/:profileId', async (req, res) => {
  try {
    const { profileId } = req.params;
    const { data, error } = await supabase
      .from('transactions').select('*').eq('profile_id', profileId)
      .order('created_at', { ascending: true });
    if (error) throw error;
    const entries = buildLedgerFromTransactions(data, profileId);
    const currentBalance = entries.length ? entries[entries.length - 1].newBalance : 0;
    const { data: profile } = await supabase.from('profiles').select('id, name, email, user_id').eq('id', profileId).maybeSingle();
    res.json({
      success: true,
      profile: profile || null,
      currentBalance,
      entries: entries.reverse(), // newest first for display
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Append-only reversal: writes a reversing entry to ledger_entries (when the
// table exists) and logs to audit. The original is never mutated.
router.post(
  '/ledger/:id/reverse',
  [param('id').isUUID(), body('reason').isString()],
  validate,
  async (req, res) => {
    try {
      if (!isSuperAdmin(req)) return res.status(403).json({ success: false, error: 'Only the Super Admin may reverse ledger entries' });
      const { id } = req.params;
      const { reason } = req.body;

      // Locate the original entry (ledger_entries table, fallback to transactions).
      const { data: le } = await supabase.from('ledger_entries').select('*').eq('id', id).maybeSingle();
      let original = le;
      if (!original) {
        const { data: tx } = await supabase.from('transactions').select('*').eq('id', id).maybeSingle();
        original = tx;
      }
      if (!original) return res.status(404).json({ success: false, error: 'Ledger entry not found' });
      if (original.reversed) return res.status(400).json({ success: false, error: 'Entry already reversed' });

      const amount = Number(original.amount || original.credit || original.debit || 0);
      const wasCredit = original.credit ? true : (original.category || '') === 'credit';

      // Try to persist the reversing entry to ledger_entries.
      let reversal = null;
      const insertPayload = {
        profile_id: original.profile_id,
        reference: `REV-${original.reference || original.id}`,
        type: `reversal:${original.type || 'adjustment'}`,
        description: `Reversal of ${original.reference || original.id}: ${reason}`,
        debit: wasCredit ? amount : 0,
        credit: wasCredit ? 0 : amount,
        source: 'admin-reversal',
        status: 'completed',
        initiated_by: req.user.id,
        reversed: false,
        reversal_of: id,
        metadata: { reason, reversedBy: req.user.email, originalReference: original.reference },
      };
      const { data: inserted, error: insErr } = await supabase.from('ledger_entries').insert(insertPayload).select('*').maybeSingle();
      if (insErr && /relation .* does not exist|Could not find|PGRST/i.test(insErr.message)) {
        // ledger_entries table not provisioned yet — record intent in audit only.
        reversal = { ...insertPayload, id: null, fallback: true };
      } else if (insErr) {
        throw insErr;
      } else {
        reversal = inserted;
        // Mark the original as reversed (append-only spirit: we flag, never delete).
        const origTable = le ? 'ledger_entries' : 'transactions';
        await Promise.resolve(supabase.from(origTable).update({ reversed: true, reversal_of: reversal.id }).eq('id', id)).catch(() => {});
      }

      await logAdminAction('LEDGER_REVERSAL', { model: 'LedgerEntry', id }, {
        originalReference: original.reference,
        amount, reason, reversedBy: req.user.email, reversalId: reversal?.id,
      }, req);

      res.json({ success: true, reversal });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. SYSTEM-WIDE SEARCH
// ─────────────────────────────────────────────────────────────────────────────

router.get('/search', [query('q').isString()], validate, async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (q.length < 2) return res.json({ success: true, results: [] });
    const like = `%${q}%`;

    const safe = (p) => Promise.resolve(p).catch(() => ({ data: [] }));

    const [members, loans, txns, tickets, orgs, guarantors] = await Promise.all([
      safe(supabase.from('profiles').select('id, user_id, name, email, phone, is_active').or(`name.ilike.${like},email.ilike.${like},phone.ilike.${like},user_id.ilike.${like}`).limit(10)),
      safe(supabase.from('loans').select('id, loan_id, loan_type, amount, status, profile_id').or(`loan_id.ilike.${like}`).limit(10)),
      safe(supabase.from('transactions').select('id, reference, type, amount, profile_id, created_at').or(`reference.ilike.${like}`).limit(10)),
      safe(supabase.from('tickets').select('id, subject, status, category, created_at').or(`subject.ilike.${like}`).limit(10)),
      safe(supabase.from('organizations').select('id, name, email, phone').or(`name.ilike.${like},email.ilike.${like}`).limit(10)),
      safe(supabase.from('guarantor_requests').select('id, status, loan_id, guarantor_id').limit(10)),
    ]);

    const results = [];
    (members.data || []).forEach((m) => results.push({ type: 'member', id: m.id, label: m.name || m.email, sub: m.user_id, href: `/members/${m.id}`, extra: m }));
    (loans.data || []).forEach((l) => results.push({ type: 'loan', id: l.id, label: l.loan_id, sub: l.loan_type, href: `/loans`, extra: l }));
    (txns.data || []).forEach((t) => results.push({ type: 'transaction', id: t.id, label: t.reference || t.id, sub: t.type, href: `/wallet-management`, extra: t }));
    (tickets.data || []).forEach((t) => results.push({ type: 'ticket', id: t.id, label: t.subject, sub: t.category, href: `/support`, extra: t }));
    (orgs.data || []).forEach((o) => results.push({ type: 'organization', id: o.id, label: o.name, sub: o.email, href: `/organizations`, extra: o }));
    (guarantors.data || []).forEach((g) => results.push({ type: 'guarantor', id: g.id, label: g.loan_id || g.id, sub: g.status, href: `/guarantor-system`, extra: g }));

    res.json({ success: true, query: q, results });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. SUPER ADMIN "ATTENTION REQUIRED"
// ─────────────────────────────────────────────────────────────────────────────

router.get('/attention', async (_req, res) => {
  try {
    const safe = (p) => Promise.resolve(p).catch(() => ({ data: [], count: 0, error: null }));

    const oneMonthAgo = new Date(Date.now() - 30 * 86400000).toISOString();
    const now = new Date().toISOString();

    const [
      pendingApprovals, paymentProofsPending, suspiciousLogins, fraudFlags,
      overdueLoans, pendingKyc, openTickets, unpaidContributions,
    ] = await Promise.all([
      safe(supabase.from('security_events').select('id', { count: 'exact', head: true }).like('event', 'APPROVAL_%').eq('resolved', false)),
      safe(supabase.from('payment_proofs').select('id', { count: 'exact', head: true }).eq('status', 'pending')),
      safe(supabase.from('login_history').select('id', { count: 'exact', head: true }).eq('suspicious', true).gte('created_at', oneMonthAgo)),
      safe(supabase.from('security_events').select('id', { count: 'exact', head: true }).neq('resolved', true).gte('created_at', oneMonthAgo)),
      safe(supabase.from('loans').select('id', { count: 'exact', head: true }).in('status', ['active', 'disbursed']).lt('next_due_date', now)),
      safe(supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_active', true).eq('kyc_verified', false)),
      safe(supabase.from('tickets').select('id', { count: 'exact', head: true }).eq('status', 'open')),
      safe(supabase.from('contributions').select('id', { count: 'exact', head: true }).neq('status', 'paid')),
    ]);

    const items = [
      { key: 'pendingApprovals', label: 'Pending approvals', count: pendingApprovals.count || 0, severity: 'high', href: '/approval-center' },
      { key: 'paymentProofsPending', label: 'Payment proofs awaiting verification', count: paymentProofsPending.count || 0, severity: 'high', href: '/payment-proofs' },
      { key: 'suspiciousLogins', label: 'Suspicious login attempts (30d)', count: suspiciousLogins.count || 0, severity: 'medium', href: '/login-history' },
      { key: 'fraudFlags', label: 'Unresolved fraud / security flags', count: fraudFlags.count || 0, severity: 'high', href: '/fraud-detection' },
      { key: 'overdueLoans', label: 'Overdue loans', count: overdueLoans.count || 0, severity: 'high', href: '/loans' },
      { key: 'pendingKyc', label: 'Members pending KYC', count: pendingKyc.count || 0, severity: 'medium', href: '/user-verification' },
      { key: 'openTickets', label: 'Open support tickets', count: openTickets.count || 0, severity: 'medium', href: '/support' },
      { key: 'unpaidContributions', label: 'Unpaid contributions', count: unpaidContributions.count || 0, severity: 'low', href: '/contributions' },
    ].filter((i) => i.count > 0);

    const total = items.reduce((s, i) => s + i.count, 0);
    res.json({ success: true, total, items });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. LOAN APPROVAL MATRIX
// ─────────────────────────────────────────────────────────────────────────────
// Stored as system_settings `loan_approval.thresholds`:
//   { levels: [{ level, maxAmount, role }] }

const DEFAULT_THRESHOLDS = {
  levels: [
    { level: 1, maxAmount: 100000, role: 'staff' },
    { level: 2, maxAmount: 1000000, role: 'admin' },
    { level: 3, maxAmount: Infinity, role: 'super_admin' },
  ],
};

router.get('/loan-approval-matrix', async (_req, res) => {
  try {
    const thresholds = await getSetting('loan_approval.thresholds', DEFAULT_THRESHOLDS);
    res.json({ success: true, thresholds });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put(
  '/loan-approval-matrix',
  [body('levels').isArray()],
  validate,
  async (req, res) => {
    try {
      if (!isSuperAdmin(req)) return res.status(403).json({ success: false, error: 'Only the Super Admin may configure the approval matrix' });
      const thresholds = { levels: req.body.levels };
      await setSetting('loan_approval.thresholds', thresholds, 'Loan approval amount thresholds per role');
      await logAdminAction('LOAN_APPROVAL_MATRIX_UPDATED', { model: 'SystemSetting', id: 'loan_approval.thresholds' }, { levels: thresholds.levels, admin: req.user.email }, req);
      res.json({ success: true, thresholds });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// Returns the maximum loan amount the current admin may approve outright.
router.get('/loan-approval-matrix/my-limit', async (req, res) => {
  try {
    const thresholds = await getSetting('loan_approval.thresholds', DEFAULT_THRESHOLDS);
    const role = req.user?.role || 'staff';
    const myLevels = thresholds.levels.filter((l) => l.role === role || (role === 'superadmin' || role === 'super_admin'));
    const max = myLevels.reduce((m, l) => Math.max(m, l.maxAmount), 0);
    res.json({ success: true, role, maxApproveAmount: max, requiresApprovalFor: max > 0 ? max : 0 });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 6. NOTIFICATION TEMPLATE MANAGER
// ─────────────────────────────────────────────────────────────────────────────
// Stored as system_settings `notification_template.<key>`:
//   { key, title, body, channels: { push, sms, email }, enabled }

const DEFAULT_TEMPLATES = [
  { key: 'welcome', title: 'Welcome to Coopvest', body: 'Hi {{name}}, your account is ready. Start saving today!', channels: { push: true, sms: false, email: true }, enabled: true },
  { key: 'contribution_reminder', title: 'Contribution Reminder', body: 'Hi {{name}}, your contribution of ₦{{amount}} is due on {{date}}.', channels: { push: true, sms: true, email: false }, enabled: true },
  { key: 'payment_received', title: 'Payment Received', body: 'We received your payment of ₦{{amount}}. Reference {{reference}}.', channels: { push: true, sms: false, email: false }, enabled: true },
  { key: 'payment_verified', title: 'Payment Verified', body: 'Your payment of ₦{{amount}} has been verified and credited.', channels: { push: true, sms: true, email: false }, enabled: true },
  { key: 'payment_rejected', title: 'Payment Rejected', body: 'Your payment proof was rejected. Reason: {{reason}}.', channels: { push: true, sms: true, email: true }, enabled: true },
  { key: 'loan_approved', title: 'Loan Approved', body: 'Hi {{name}}, your {{loanType}} loan of ₦{{amount}} is approved.', channels: { push: true, sms: true, email: true }, enabled: true },
  { key: 'loan_rejected', title: 'Loan Rejected', body: 'Hi {{name}}, your loan application was declined. Reason: {{reason}}.', channels: { push: true, sms: true, email: true }, enabled: true },
  { key: 'loan_repayment_reminder', title: 'Repayment Reminder', body: 'Your loan repayment of ₦{{amount}} is due on {{date}}.', channels: { push: true, sms: true, email: false }, enabled: true },
  { key: 'default_warning', title: 'Default Warning', body: 'Your loan is overdue. Please regularize to avoid penalties.', channels: { push: true, sms: true, email: true }, enabled: true },
  { key: 'guarantor_notification', title: 'Guarantor Request', body: '{{memberName}} requested you as a guarantor for a ₦{{amount}} loan.', channels: { push: true, sms: true, email: false }, enabled: true },
  { key: 'account_suspension', title: 'Account Suspended', body: 'Your account is suspended. Reason: {{reason}}.', channels: { push: true, sms: true, email: true }, enabled: true },
];

async function loadTemplates() {
  const { data } = await supabase.from('system_settings').select('key, value').like('key', 'notification_template.%');
  const stored = {};
  (data || []).forEach((r) => { stored[r.key.replace('notification_template.', '')] = r.value; });
  return DEFAULT_TEMPLATES.map((t) => ({ ...t, ...stored[t.key] }));
}

router.get('/notification-templates', async (_req, res) => {
  try {
    res.json({ success: true, templates: await loadTemplates() });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put(
  '/notification-templates/:key',
  [
    body('title').optional().isString(),
    body('body').optional().isString(),
    body('channels').optional().isObject(),
    body('enabled').optional().isBoolean(),
  ],
  validate,
  async (req, res) => {
    try {
      if (!isSuperAdmin(req)) return res.status(403).json({ success: false, error: 'Only the Super Admin may edit notification templates' });
      const { key } = req.params;
      const existing = (await loadTemplates()).find((t) => t.key === key) || {};
      const merged = {
        key,
        title: req.body.title ?? existing.title ?? key,
        body: req.body.body ?? existing.body ?? '',
        channels: { ...(existing.channels || { push: true, sms: false, email: false }), ...(req.body.channels || {}) },
        enabled: req.body.enabled ?? existing.enabled ?? true,
      };
      await setSetting(`notification_template.${key}`, merged, `Notification template: ${key}`);
      await logAdminAction('NOTIFICATION_TEMPLATE_UPDATED', { model: 'SystemSetting', id: `notification_template.${key}` }, { key, admin: req.user.email }, req);
      res.json({ success: true, template: merged });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 7. DOCUMENT VAULT (permission-controlled, access-logged)
// ─────────────────────────────────────────────────────────────────────────────

router.get('/documents', async (req, res) => {
  try {
    const { page, limit } = req.query;
    const p = Math.max(1, parseInt(page, 10) || 1);
    const l = Math.min(100, parseInt(limit, 10) || 50);
    let q = supabase.from('documents').select('*, profile:profiles(id, name, email)', { count: 'exact' });
    if (req.query.profileId) q = q.eq('profile_id', req.query.profileId);
    if (req.query.type) q = q.eq('document_type', req.query.type);
    if (req.query.status) q = q.eq('status', req.query.status);
    const { data, error, count } = await q.order('uploaded_at', { ascending: false }).range((p - 1) * l, p * l - 1);
    if (error && /relation .* does not exist|Could not find|PGRST/i.test(error.message || '') || (error && /^42/i.test(error.code || ''))) {
      return res.json({ success: true, documents: [], pagination: { page: p, limit: l, total: 0 }, fallback: true });
    }
    if (error) throw error;
    res.json({ success: true, documents: data || [], pagination: { page: p, limit: l, total: count || 0 } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Log a document view/download so access is auditable.
router.post('/documents/:id/access', [body('action').isIn(['view', 'download'])], validate, async (req, res) => {
  try {
    const { id } = req.params;
    const { action } = req.body;
    await logAdminAction(`DOCUMENT_${action.toUpperCase()}`, { model: 'Document', id }, {
      admin: req.user.email, action,
    }, req);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 8. ORGANIZATION PAYROLL RECONCILIATION (expected vs actual variance)
// ─────────────────────────────────────────────────────────────────────────────

router.get('/payroll/:orgId/reconciliation', async (req, res) => {
  try {
    const { orgId } = req.params;
    const { data: org, error: orgErr } = await supabase.from('organizations').select('*').eq('id', orgId).maybeSingle();
    if (orgErr) throw orgErr;
    if (!org) return res.status(404).json({ success: false, error: 'Organization not found' });

    // Expected = sum of deduction amounts scheduled for this org.
    const { data: schedules } = await supabase.from('payroll_schedules')
      .select('profile_id, amount, status').eq('organization_id', orgId);
    const safe = (p) => Promise.resolve(p).catch(() => ({ data: [] }));

    // Actual = sum of completed contribution/transfer_in transactions tagged
    // for this org (best-effort via reference/metadata). Falls back to 0.
    const { data: txns } = await safe(supabase.from('transactions')
      .select('amount, reference, metadata, type, status')
      .in('type', ['contribution', 'savings_deposit', 'transfer_in', 'salary_deduction'])
      .eq('status', 'completed'));

    const orgTag = String(org.name || org.id);
    const actualRows = (txns || []).filter((t) => {
      const meta = t.metadata || {};
      return meta.organization_id === orgId || meta.org === orgTag || (t.reference || '').includes(orgTag);
    });

    const expected = (schedules || []).reduce((s, r) => s + Number(r.amount || 0), 0);
    const actual = actualRows.reduce((s, r) => s + Number(r.amount || 0), 0);
    const variance = expected - actual;
    const expectedCount = (schedules || []).length;
    const actualCount = actualRows.length;

    res.json({
      success: true,
      reconciliation: {
        organizationId: orgId,
        organizationName: org.name || null,
        expected: { amount: expected, count: expectedCount },
        actual: { amount: actual, count: actualCount },
        variance,
        variancePercent: expected > 0 ? Math.round((variance / expected) * 10000) / 100 : 0,
        status: variance === 0 ? 'matched' : variance > 0 ? 'shortfall' : 'surplus',
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
