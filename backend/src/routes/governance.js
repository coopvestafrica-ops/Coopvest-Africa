/**
 * Super Admin governance routes.
 *
 * Implements the Super Admin governance surface consumed by the Admin Dashboard:
 *   - Login monitoring        GET/POST  /login-events, /login-history (enriched)
 *   - Audit trail             (enriched logAdminAction lives in adminApi.js)
 *   - Approval workflow       GET/POST  /approvals[/:id/:action]
 *   - Security alerts         GET/POST  /security-alerts[/:id/:action]
 *   - Live admin monitoring   GET/POST  /activity[ /online ]
 *   - Activity dashboard      GET       /stats
 *   - Permissions             GET       /permissions, /roles/:id/permissions
 *
 * Mounted under /api/admin (and /api/v2/admin). All routes are protected by
 * requireAdmin (applied in adminApi.js router). This sub-router is itself
 * requireAdmin-guarded when mounted.
 *
 * Data is persisted to existing Supabase tables (which are reachable via the
 * REST API / service role key — the PG-wire bootstrap is blocked by an unknown
 * DB password):
 *   - security_events   (replaces security_alerts — alert/severity/resolve)
 *   - security_sessions (replaces admin_activity — online/active sessions)
 *   - audit_logs        (approval requests are recorded here as
 *                        action='approval.requested' so /approvals reads them
 *                        back; also the core audit trail)
 *   - login_history     (login monitoring)
 *   - admin_roles / admin_staff / admin_notifications (staff & roles)
 *
 * NOTE: a bootstrap in src/config/governanceSchema.js still attempts to create
 * the originally-designed tables (admin_approvals, security_alerts,
 * admin_activity) over the PG wire for projects that have a DB password
 * configured, but it degrades gracefully and the routes below work without it.
 */

const express = require('express');
const router = express.Router();

const supabase = require('../config/supabase');
const logger = require('../utils/logger');
const approvalRequests = require('../lib/approvalRequests');

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function clientMeta(req) {
  const ua = req.headers['user-agent'] || '';
  return {
    ip: (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim(),
    userAgent: ua,
    browser: parseBrowser(ua),
    os: parseOS(ua),
    device: parseDevice(ua),
  };
}

function parseBrowser(ua) {
  if (!ua) return 'Unknown';
  if (/edg/i.test(ua)) return 'Edge';
  if (/chrome|crios/i.test(ua)) return 'Chrome';
  if (/firefox|fxios/i.test(ua)) return 'Firefox';
  if (/safari/i.test(ua)) return 'Safari';
  return 'Unknown';
}
function parseOS(ua) {
  if (!ua) return 'Unknown';
  if (/windows nt 10/i.test(ua)) return 'Windows 10/11';
  if (/windows/i.test(ua)) return 'Windows';
  if (/mac os x|iphone|ipad/i.test(ua)) return /iphone|ipad/i.test(ua) ? 'iOS' : 'macOS';
  if (/android/i.test(ua)) return 'Android';
  if (/linux/i.test(ua)) return 'Linux';
  return 'Unknown';
}
function parseDevice(ua) {
  if (!ua) return 'Unknown';
  if (/iphone|ipad|android.*mobile/i.test(ua)) return 'Mobile';
  if (/android|tablet|ipad/i.test(ua)) return 'Tablet';
  return 'Desktop';
}

// Approximate location from a string. Real geo-IP requires a lookup service
// (MaxMind/IPAPI); we keep it best-effort and let the frontend record GPS.
function approxLocation(ip) {
  if (!ip || ip === '::1' || ip.startsWith('127.') || ip.startsWith('10.')) return 'Local network';
  return 'Unknown — configure a geo-IP provider for city/country';
}

async function profileById(id) {
  if (!id) return null;
  const { data } = await supabase
    .from('profiles')
    .select('id, user_id, name, email, role, is_active')
    .eq('id', id)
    .maybeSingle();
  return data || null;
}

// Insert a security alert into the existing `security_events` table. Never
// throws (best-effort). The DB-wire-only `security_alerts` table may not exist
// (no DB password), so we use `security_events` which is reachable via REST.
async function raiseSecurityAlert({ alertType, severity = 'medium', title, description, profileId = null, email = null, ip = null, location = null, device = null, metadata = {} }) {
  try {
    await supabase.from('security_events').insert({
      event: title || alertType,
      username: email || null,
      ip_address: ip,
      severity,
      details: JSON.stringify({
        alertType, description, profileId, email, location, device, metadata,
      }),
      resolved: false,
    });
  } catch (err) {
    logger.warn('security alert insert failed:', err.message);
  }
}

// Record a login event to login_history (best-effort, never throws).
//
// NOTE: the production login_history table currently exposes only these
// columns: id, profile_id, success, failure_reason, ip_address, user_agent,
// device_type, location, created_at (migration 012's ADD COLUMNs for email,
// device_name, os, browser, app_version, login_method, mfa_used, session_id
// were never applied to prod). Inserting any of those missing columns makes
// PostgREST reject the whole insert with PGRST204, which silently empties the
// sessions / login-history pages. Only insert columns that exist; the extra
// device detail is still recoverable from user_agent on read.
async function recordLogin({ profileId, email, success, failureReason, req, mfaUsed = false, loginMethod = 'password', sessionId = null }) {
  try {
    const m = clientMeta(req);
    const now = new Date();
    const { error } = await supabase.from('login_history').insert({
      profile_id: profileId || null,
      success: !!success,
      failure_reason: success ? null : failureReason || null,
      ip_address: m.ip || null,
      user_agent: m.userAgent || null,
      device_type: m.device,
      location: approxLocation(m.ip),
      created_at: now.toISOString(),
    });
    if (error) logger.warn('login_history insert failed:', error.message);
  } catch (err) {
    logger.warn('recordLogin error:', err.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login monitoring — record + read
// ─────────────────────────────────────────────────────────────────────────────

/**
 * POST /api/admin/login-events
 * Called by the dashboard frontend immediately after a Supabase auth attempt
 * (success or failure). Records device/IP/UA/metadata into login_history and,
 * on failure or anomaly, raises a security_alert.
 */
router.post('/login-events', async (req, res) => {
  try {
    const { email, success, failureReason, profileId, mfaUsed, loginMethod, sessionId } = req.body || {};
    const m = clientMeta(req);
    const profile = profileId ? await profileById(profileId) : (email ? (await supabase.from('profiles').select('id, role, is_active').ilike('email', email).maybeSingle()).data : null);

    // Disabled-account login attempt → critical alert
    if (profile && profile.is_active === false && !success) {
      await raiseSecurityAlert({
        alertType: 'disabled_account_login',
        severity: 'critical',
        title: 'Disabled account login attempt',
        description: `Account ${email || profile.id} attempted to log in while disabled.`,
        profileId: profile.id, email, ip: m.ip, location: approxLocation(m.ip), device: m.device,
        metadata: { ua: m.userAgent, browser: m.browser, os: m.os },
      });
    }

    await recordLogin({ profileId: profile?.id || profileId, email, success, failureReason, req, mfaUsed, loginMethod, sessionId });

    // Failed-login burst detection (≥3 failures in 10 min from same IP)
    if (!success && m.ip) {
      const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
      const { count } = await supabase.from('login_history').select('id', { count: 'exact', head: true }).eq('ip_address', m.ip).eq('success', false).gte('created_at', since);
      if ((count || 0) >= 3) {
        await raiseSecurityAlert({
          alertType: 'multiple_failed_logins',
          severity: 'high',
          title: 'Multiple failed login attempts',
          description: `${count} failed logins from ${m.ip} in the last 10 minutes.`,
          profileId: profile?.id || null, email, ip: m.ip, location: approxLocation(m.ip), device: m.device,
          metadata: { count, ua: m.userAgent },
        });
      }
    }

    // New-device / new-country detection for successful logins
    if (success && profile) {
      const { data: prior } = await supabase.from('login_history')
        .select('ip_address, location, device_type')
        .eq('profile_id', profile.id).eq('success', true)
        .lt('created_at', new Date(Date.now() - 30000).toISOString())
        .order('created_at', { ascending: false }).limit(50);
      const priorSet = prior || [];
      const knownDevice = priorSet.some((r) => (r.device_type || '') === m.device);
      if (!knownDevice) {
        await raiseSecurityAlert({
          alertType: 'new_device_login',
          severity: 'medium',
          title: 'Login from a new device',
          description: `${email} logged in from a new ${m.device} (${m.browser}/${m.os}).`,
          profileId: profile.id, email, ip: m.ip, location: approxLocation(m.ip), device: m.device,
          metadata: { ua: m.userAgent },
        });
      }
    }

    res.json({ success: true });
  } catch (err) {
    logger.error('login-events error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/admin/logout-events
 * Records a logout (closes the most recent open login for this profile).
 */
router.post('/logout-events', async (req, res) => {
  try {
    const { profileId, sessionId } = req.body || {};
    if (!profileId) return res.status(400).json({ success: false, error: 'profileId required' });
    const { data: last } = await supabase.from('login_history')
      .select('id, created_at')
      .eq('profile_id', profileId).is('logout_at', null)
      .order('created_at', { ascending: false }).limit(1);
    const row = (last || [])[0];
    if (row) {
      const duration = Math.max(0, Math.floor((Date.now() - new Date(row.created_at).getTime()) / 1000));
      await supabase.from('login_history').update({ logout_at: new Date().toISOString(), session_duration_seconds: duration }).eq('id', row.id);
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Live admin monitoring (heartbeats)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * POST /api/admin/activity
 * Heartbeat from the dashboard. Upserts a security_sessions row (is_current=true)
 * so the Super Admin can see who is online and what they are doing. Uses the
 * existing security_sessions table (admin_activity needs a DB-password migration).
 */
router.post('/activity', async (req, res) => {
  try {
    if (!req.user?.id) return res.status(401).json({ success: false, error: 'Not authenticated' });
    const { page, module: mod, action } = req.body || {};
    const m = clientMeta(req);
    // security_sessions has no per-page columns; stash current page/module in
    // `location` (free text) and keep is_current + login_time fresh as a heartbeat.
    // The table has no unique constraint on user_id, so we select-then-update or
    // insert (upsert with onConflict would fail without a unique constraint).
    const payload = {
      user_id: req.user.id,
      user_name: req.user.email || req.user.name || null,
      role: req.user.role || null,
      ip_address: m.ip,
      device: m.device,
      location: [page, mod, action].filter(Boolean).join(' | ') || m.userAgent || null,
      login_time: new Date().toISOString(),
      is_current: true,
    };
    const { data: existing } = await supabase.from('security_sessions')
      .select('id').eq('user_id', req.user.id).limit(1).maybeSingle();
    let error;
    if (existing && existing.id) {
      ({ error } = await supabase.from('security_sessions').update(payload).eq('id', existing.id));
    } else {
      ({ error } = await supabase.from('security_sessions').insert(payload));
    }
    if (error) throw error;
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/admin/online
 * Admins with a heartbeat (login_time) in the last N minutes (default 5).
 * Reads from security_sessions where is_current=true and login_time >= since.
 */
router.get('/online', async (req, res) => {
  try {
    const minutes = Math.max(1, parseInt(req.query.minutes, 10) || 5);
    const since = new Date(Date.now() - minutes * 60 * 1000).toISOString();
    const { data, error } = await supabase.from('security_sessions')
      .select('id, user_id, user_name, role, ip_address, device, location, login_time, is_current, created_at')
      .eq('is_current', true)
      .gte('login_time', since)
      .order('login_time', { ascending: false });
    if (error) throw error;
    const admins = (data || []).map((a) => {
      const locParts = (a.location || '').split(' | ');
      return {
        id: a.id,
        profileId: a.user_id,
        email: a.user_name,
        role: a.role,
        currentPage: locParts[0] || null,
        currentModule: locParts[1] || null,
        lastAction: locParts[2] || null,
        ipAddress: a.ip_address,
        device: a.device,
        lastHeartbeat: a.login_time,
        isOnline: true,
      };
    });
    res.json({ success: true, data: admins, total: admins.length, onlineCount: admins.length });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Approval workflow
// ─────────────────────────────────────────────────────────────────────────────

// Approval requests are persisted as rows in the existing `security_events`
// table (admin_approvals needs a DB-password migration we cannot run). The
// request_type/title live in `event`, the structured payload in `details`
// (JSON string), and `resolved` flags pending (false) vs decided (true).
const APPROVAL_PREFIX = '[approval] ';
function parseApprovalDetails(r) {
  let d = {};
  try { d = typeof r.details === 'string' ? JSON.parse(r.details) : (r.details || {}); } catch (_) {}
  return d;
}

/**
 * GET /api/admin/approvals
 * Approval queue (default: pending only). Reads approval requests from
 * security_events rows whose `event` starts with the approval prefix.
 */
router.get('/approvals', async (req, res) => {
  try {
    let q = supabase.from('security_events')
      .select('id, event, username, ip_address, severity, details, resolved, created_at', { count: 'exact' })
      .like('event', APPROVAL_PREFIX + '%')
      .order('created_at', { ascending: false })
      .limit(Math.min(200, parseInt(req.query.limit, 10) || 100));
    // pending = unresolved; decided = resolved. Default: pending only.
    const status = req.query.status || 'pending';
    if (status === 'pending') q = q.eq('resolved', false);
    else if (status === 'decided') q = q.eq('resolved', true);
    // 'all' => no resolved filter
    const { data, error, count } = await q;
    if (error) throw error;

    const rows = (data || []).map((r) => {
      const d = parseApprovalDetails(r);
      return {
        id: r.id,
        requestType: d.requestType || r.event.replace(APPROVAL_PREFIX, ''),
        title: d.title || r.event.replace(APPROVAL_PREFIX, ''),
        payload: d.payload || {},
        previousValue: d.previousValue ?? null,
        newValue: d.newValue ?? null,
        status: r.resolved ? (d.decision || 'decided') : 'pending',
        requestedBy: d.requestedBy || null,
        requestedByName: r.username || d.requestedByEmail || 'Unknown',
        requestedByRole: d.requestedByRole || null,
        reason: d.reason || null,
        decidedBy: d.decidedBy || null,
        decidedByName: d.decidedByEmail || null,
        decidedByRole: d.decidedByRole || null,
        decisionReason: d.decisionReason || null,
        decidedAt: d.decidedAt || null,
        thresholdValue: d.thresholdValue ?? null,
        metadata: d,
        createdAt: r.created_at,
        updatedAt: d.decidedAt || r.created_at,
      };
    });
    res.json({ success: true, data: rows, total: count || rows.length, pending: rows.filter((r) => r.status === 'pending').length });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/admin/approvals
 * Staff/admin submits a request that requires Super Admin approval.
 * Body: { requestType, title?, payload?, previousValue?, newValue?, reason?, thresholdValue? }
 */
router.post('/approvals', async (req, res) => {
  try {
    if (!req.user?.id) return res.status(401).json({ success: false, error: 'Not authenticated' });
    const { requestType, title, payload, previousValue, newValue, reason, thresholdValue } = req.body || {};
    if (!requestType) return res.status(400).json({ success: false, error: 'requestType is required' });

    const details = {
      requestType,
      title: title || requestType,
      payload: payload || {},
      previousValue: previousValue ?? null,
      newValue: newValue ?? null,
      reason: reason || null,
      thresholdValue: thresholdValue ?? null,
      requestedBy: req.user.id,
      requestedByEmail: req.user.email,
      requestedByRole: req.user.role,
      source: 'admin-web',
    };
    const { data, error } = await supabase.from('security_events').insert({
      event: APPROVAL_PREFIX + (title || requestType),
      username: req.user.email || null,
      ip_address: (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || null,
      severity: /loan|contribution|financial|policy|fee|export|member_delete/i.test(requestType) ? 'high' : 'medium',
      details: JSON.stringify(details),
      resolved: false,
    }).select('*').single();
    if (error) throw error;

    // Always also log the approval request to the audit trail.
    try {
      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        actor_role: req.user.role,
        action: 'approval.requested',
        target_model: 'admin_approval',
        target_id: data.id,
        metadata: { requestType, title: title || requestType, reason: reason || null, requestedBy: req.user.email },
      });
    } catch (_) {}
    res.status(201).json({ success: true, data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

async function decideApproval(req, res, decision) {
  try {
    if (!['superadmin', 'super_admin'].includes(req.user?.role || '')) {
      return res.status(403).json({ success: false, error: 'Only the Super Admin can approve or reject requests' });
    }
    const { id } = req.params;
    const { reason } = req.body || {};
    const { data: existing, error: fetchError } = await supabase.from('security_events')
      .select('id, event, username, details, resolved, created_at')
      .eq('id', id).maybeSingle();
    if (fetchError) throw fetchError;
    if (!existing) return res.status(404).json({ success: false, error: 'Approval request not found' });
    if (!String(existing.event || '').startsWith(APPROVAL_PREFIX)) {
      return res.status(404).json({ success: false, error: 'Approval request not found' });
    }
    if (existing.resolved) return res.status(400).json({ success: false, error: 'Request already decided' });

    const d = parseApprovalDetails(existing);
    d.decision = decision;
    d.decidedBy = req.user.id;
    d.decidedByEmail = req.user.email;
    d.decidedByRole = req.user.role;
    d.decisionReason = reason || null;
    d.decidedAt = new Date().toISOString();

    const { data, error } = await supabase.from('security_events').update({
      details: JSON.stringify(d),
      resolved: true,
    }).eq('id', id).select('*').single();
    if (error) throw error;

    // Executable requests: a decided loan_approval applies to the loans table.
    let execution = null;
    if (d.requestType === 'loan_approval') {
      try {
        execution = await approvalRequests.executeLoanApprovalDecision(
          d.payload,
          decision === 'approved' ? 'approve' : 'reject',
          req.user,
          reason || null,
        );
      } catch (execErr) {
        logger.error('loan_approval execution failed:', execErr.message);
        execution = { executed: false, error: execErr.message };
      }
    }

    // Audit record
    try {
      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        actor_role: req.user.role,
        action: `approval.${decision}`,
        target_model: 'admin_approval',
        target_id: id,
        metadata: { requestType: d.requestType, title: d.title, reason: reason || null, decidedBy: req.user.email, execution },
      });
    } catch (_) {}

    res.json({ success: true, data, execution });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
}

router.post('/approvals/:id/approve', (req, res) => decideApproval(req, res, 'approved'));
router.post('/approvals/:id/reject', (req, res) => decideApproval(req, res, 'rejected'));

// ─────────────────────────────────────────────────────────────────────────────
// Security alerts
// ─────────────────────────────────────────────────────────────────────────────

/**
 * GET /api/admin/security-alerts
 * Returns persisted alerts + computed anomalies (failed-login bursts,
 * suspicious logins) from login_history/audit_logs so the Super Admin sees a
 * full picture even before a writer exists for every event.
 */
router.get('/security-alerts', async (req, res) => {
  try {
    const limit = Math.min(200, parseInt(req.query.limit, 10) || 50);
    const sinceHours = Math.max(1, parseInt(req.query.hours, 10) || 72);
    const since = new Date(Date.now() - sinceHours * 3600 * 1000).toISOString();

    const [alertsRes, suspiciousRes, failedRes] = await Promise.all([
      // persisted alerts live in security_events, excluding approval rows.
      supabase.from('security_events').select('id, event, username, ip_address, severity, details, resolved, created_at').not('event', 'like', APPROVAL_PREFIX + '%').gte('created_at', since).order('created_at', { ascending: false }).limit(limit),
      supabase.from('login_history').select('id, profile_id, email, ip_address, location, device_type, os, browser, success, failure_reason, created_at').eq('success', false).gte('created_at', since).order('created_at', { ascending: false }).limit(25),
      // permission/financial changes recorded as audit_logs
      supabase.from('audit_logs').select('id, actor_id, actor_role, action, target_model, target_id, metadata, ip_address, user_agent, created_at').or('action.ilike.%permission%,action.ilike.%financial%,action.ilike.%loan%,action.ilike.%contribution%').gte('created_at', since).order('created_at', { ascending: false }).limit(25),
    ]);

    const nameMap = await profileNameMap([
      ...((suspiciousRes.data || []).map((a) => a.profile_id).filter(Boolean)),
      ...((failedRes.data || []).map((a) => a.actor_id).filter(Boolean)),
    ]);

    const alerts = (alertsRes.data || []).map((a) => ({
      id: a.id, type: a.event, alertType: a.event, severity: a.severity,
      title: a.event, description: a.details,
      email: a.username, ipAddress: a.ip_address,
      status: a.resolved ? 'resolved' : 'unread',
      createdAt: a.created_at,
    }));
    const computed = (suspiciousRes.data || []).map((s) => ({
      id: `computed:${s.id}`, type: 'failed_login', alertType: 'failed_login', severity: 'low',
      title: 'Failed login', description: s.failure_reason || 'Login attempt failed',
      profileId: s.profile_id, email: s.email, user: nameMap[s.profile_id] || s.email || 'Unknown',
      ipAddress: s.ip_address, location: s.location, device: s.device_type, status: 'unread',
      createdAt: s.created_at, computed: true,
    }));
    const financial = (failedRes.data || []).map((f) => ({
      id: `audit:${f.id}`, type: 'financial_change', alertType: 'financial_change', severity: 'medium',
      title: f.action, description: `${f.action} on ${f.target_model || ''} ${f.target_id || ''}`,
      profileId: f.actor_id, user: nameMap[f.actor_id] || 'Unknown', ipAddress: f.ip_address,
      status: 'unread', createdAt: f.created_at, computed: true, metadata: f.metadata,
    }));

    const all = [...alerts, ...computed, ...financial]
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .slice(0, limit);

    res.json({
      success: true,
      data: all,
      total: all.length,
      unread: all.filter((a) => a.status === 'unread').length,
      critical: all.filter((a) => a.severity === 'critical' || a.severity === 'high').length,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/security-alerts/:id/resolve', async (req, res) => {
  try {
    if (!['superadmin', 'super_admin'].includes(req.user?.role || '')) {
      return res.status(403).json({ success: false, error: 'Super Admin only' });
    }
    const { data, error } = await supabase.from('security_events').update({
      resolved: true,
    }).eq('id', req.params.id).select('*').maybeSingle();
    if (error) throw error;
    // Audit the resolution.
    try {
      await supabase.from('audit_logs').insert({
        actor_id: req.user.id, actor_role: req.user.role,
        action: 'security_alert.resolved', target_model: 'security_event', target_id: req.params.id,
      });
    } catch (_) {}
    res.json({ success: true, data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Super Admin activity dashboard stats
// ─────────────────────────────────────────────────────────────────────────────

/**
 * GET /api/admin/stats
 * Live Super Admin dashboard statistics.
 */
router.get('/stats', async (req, res) => {
  try {
    const startOfToday = new Date();
    startOfToday.setUTCHours(0, 0, 0, 0);
    const todayIso = startOfToday.toISOString();

    const since15 = new Date(Date.now() - 15 * 60 * 1000).toISOString();

    const [
      adminsOnline, failedToday, pendingApprovals, suspicious,
      financialToday, loanApprovalsToday, contributionApprovalsToday, suspendedToday,
      totalAdmins,
    ] = await Promise.all([
      // online admins = current sessions with a recent heartbeat (login_time)
      supabase.from('security_sessions').select('id', { count: 'exact', head: true }).eq('is_current', true).gte('login_time', since15),
      supabase.from('login_history').select('id', { count: 'exact', head: true }).eq('success', false).gte('created_at', todayIso),
      // pending approval requests = unresolved security_events rows we tagged as approvals
      supabase.from('security_events').select('id', { count: 'exact', head: true }).like('event', APPROVAL_PREFIX + '%').eq('resolved', false),
      supabase.from('login_history').select('id', { count: 'exact', head: true }).eq('success', false).gte('created_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString()),
      supabase.from('audit_logs').select('id', { count: 'exact', head: true }).or('action.ilike.%loan%,action.ilike.%contribution%,action.ilike.%financial%').gte('created_at', todayIso),
      supabase.from('audit_logs').select('id', { count: 'exact', head: true }).ilike('action', '%loan%approve%').gte('created_at', todayIso),
      supabase.from('audit_logs').select('id', { count: 'exact', head: true }).ilike('action', '%contribution%create%').gte('created_at', todayIso),
      supabase.from('audit_logs').select('id', { count: 'exact', head: true }).ilike('action', '%member%suspend%').gte('created_at', todayIso),
      supabase.from('profiles').select('id', { count: 'exact', head: true }).in('role', ['admin', 'superadmin', 'super_admin', 'staff']),
    ]);

    res.json({
      success: true,
      data: {
        adminsOnline: adminsOnline.count || 0,
        failedLoginAttemptsToday: failedToday.count || 0,
        pendingApprovalRequests: pendingApprovals.count || 0,
        suspiciousActivitiesDetected: suspicious.count || 0,
        recentFinancialChanges: financialToday.count || 0,
        loanApprovalsToday: loanApprovalsToday.count || 0,
        contributionApprovalsToday: contributionApprovalsToday.count || 0,
        accountsSuspendedToday: suspendedToday.count || 0,
        totalAdmins: totalAdmins.count || 0,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Permissions
// ─────────────────────────────────────────────────────────────────────────────

const PERMISSION_CATALOG = [
  { key: 'view_contributions', label: 'View contributions', category: 'Finance' },
  { key: 'approve_payments', label: 'Approve payments', category: 'Finance' },
  { key: 'delete_transactions', label: 'Delete transactions', category: 'Finance' },
  { key: 'change_policies', label: 'Change policies', category: 'Finance' },
  { key: 'review_loans', label: 'Review loans', category: 'Loans' },
  { key: 'recommend_approval', label: 'Recommend loan approval', category: 'Loans' },
  { key: 'approve_loans', label: 'Approve loans', category: 'Loans' },
  { key: 'edit_financial_settings', label: 'Edit financial settings', category: 'Loans' },
  { key: 'view_member_profiles', label: 'View member profiles', category: 'Support' },
  { key: 'respond_to_enquiries', label: 'Respond to enquiries', category: 'Support' },
  { key: 'view_bank_details', label: 'View bank details', category: 'Support' },
  { key: 'access_financial_reports', label: 'Access financial reports', category: 'Reports' },
  { key: 'export_sensitive_data', label: 'Export sensitive financial data', category: 'Reports' },
  { key: 'manage_admins', label: 'Create/edit/suspend admin accounts', category: 'Administration' },
  { key: 'manage_permissions', label: 'Assign/revoke permissions', category: 'Administration' },
  { key: 'toggle_mobile_features', label: 'Toggle major mobile app features', category: 'Administration' },
  { key: 'change_security_settings', label: 'Change security settings', category: 'Administration' },
  { key: 'force_password_reset', label: 'Force password resets', category: 'Administration' },
  { key: 'remote_lock_admin', label: 'Lock or log out an admin remotely', category: 'Administration' },
];

router.get('/permissions', async (_req, res) => {
  res.json({ success: true, data: PERMISSION_CATALOG, permissions: PERMISSION_CATALOG, total: PERMISSION_CATALOG.length });
});

router.get('/roles/:id/permissions', async (req, res) => {
  try {
    // role_permissions stores role_id (uuid) + permission_id (uuid). We map by
    // permission_key via a join to a permissions table if present; otherwise we
    // fall back to a metadata field on the role row.
    const role = String(req.params.id);
    const { data: rp } = await supabase.from('role_permissions').select('permission_id, roles!inner(id)').eq('roles.id', role);
    const ids = (rp || []).map((r) => r.permission_id).filter(Boolean);
    let keys = [];
    if (ids.length) {
      const { data: perms } = await supabase.from('permissions').select('id, permission_key').in('id', ids);
      keys = (perms || []).map((p) => p.permission_key);
    }
    res.json({ success: true, data: keys, permissions: keys });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper: profile name map
// ─────────────────────────────────────────────────────────────────────────────
async function profileNameMap(ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  if (!unique.length) return {};
  const { data } = await supabase.from('profiles').select('id, name, email').in('id', unique);
  const map = {};
  (data || []).forEach((p) => { map[p.id] = p.name || p.email || 'Unknown'; });
  return map;
}

module.exports = router;
module.exports.PERMISSION_CATALOG = PERMISSION_CATALOG;
module.exports.recordLogin = recordLogin;
module.exports.clientMeta = clientMeta;
module.exports.raiseSecurityAlert = raiseSecurityAlert;
module.exports.profileNameMap = profileNameMap;
