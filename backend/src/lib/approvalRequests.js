/**
 * Maker-checker approval requests.
 *
 * Requests are persisted as rows in `security_events` (the same store the
 * governance routes use) so they appear in the Admin Dashboard Approval
 * Center. `requestType === 'loan_approval'` requests are executable: when the
 * Super Admin decides, the linked loan is approved/rejected for real.
 */

const supabase = require('../config/supabase');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');

const APPROVAL_PREFIX = '[approval] ';

function parseDetails(row) {
  try {
    return typeof row.details === 'string' ? JSON.parse(row.details) : (row.details || {});
  } catch (_) {
    return {};
  }
}

/** Returns the pending loan_approval request for a loan, or null. */
async function findPendingLoanApproval(loanId) {
  const { data, error } = await supabase
    .from('security_events')
    .select('id, event, details, resolved')
    .like('event', `${APPROVAL_PREFIX}%`)
    .eq('resolved', false);
  if (error) throw error;
  return (data || []).find(
    (r) => parseDetails(r).requestType === 'loan_approval' && parseDetails(r).payload?.loanId === loanId,
  ) || null;
}

/**
 * Submit a maker-checker request. Mirrors the governance POST /approvals
 * payload shape so the Approval Center renders it uniformly.
 */
async function createApprovalRequest({ requestType, title, payload = {}, reason = null, thresholdValue = null, user }) {
  const details = {
    requestType,
    title: title || requestType,
    payload,
    reason,
    thresholdValue,
    requestedBy: user.id,
    requestedByEmail: user.email,
    requestedByRole: user.role,
    source: 'admin-web',
  };
  const { data, error } = await supabase
    .from('security_events')
    .insert({
      event: APPROVAL_PREFIX + (title || requestType),
      username: user.email || null,
      severity: /loan|contribution|financial|policy|fee|export|member_delete/i.test(requestType) ? 'high' : 'medium',
      details: JSON.stringify(details),
      resolved: false,
    })
    .select('*')
    .single();
  if (error) throw error;

  try {
    await supabase.from('audit_logs').insert({
      actor_id: user.id,
      actor_role: user.role,
      action: 'approval.requested',
      target_model: 'admin_approval',
      target_id: data.id,
      metadata: { requestType, title: title || requestType, reason, requestedBy: user.email },
    });
  } catch (_) {}

  // Best-effort: let Super Admins know there is a request waiting on them.
  try {
    const { data: superAdmins } = await supabase
      .from('profiles')
      .select('id')
      .in('role', ['superadmin', 'super_admin']);
    if (superAdmins?.length) {
      await notifyService.broadcast({
        profileIds: superAdmins.map((a) => a.id),
        channels: ['in_app', 'email'],
        title: 'Approval Required',
        body: `${user.email || 'A staff member'} submitted "${title || requestType}" for your approval.`,
      });
    }
  } catch (err) {
    logger.warn('approvalRequests: super admin notification failed:', err.message);
  }

  return data;
}

/**
 * Execute a decided loan_approval request against the loans table.
 * Never throws — failures are logged and returned.
 */
async function executeLoanApprovalDecision(payload, decision, decidedBy, reason) {
  const loanId = payload?.loanId;
  if (!loanId) return { executed: false, error: 'payload.loanId missing' };

  const { data: loan, error: fetchError } = await supabase
    .from('loans')
    .select('id, status, profile_id, amount, loan_type')
    .eq('id', loanId)
    .maybeSingle();
  if (fetchError) throw fetchError;
  if (!loan) return { executed: false, error: 'loan not found' };

  if (['approved', 'rejected', 'completed', 'cancelled'].includes(loan.status)) {
    return { executed: false, error: `loan already ${loan.status}` };
  }

  const now = new Date().toISOString();
  const approve = decision === 'approve';
  const update = approve
    ? { status: 'approved', approved_by: decidedBy.id, approved_at: now, rejected_reason: null, rejected_by: null, updated_at: now }
    : { status: 'rejected', rejected_reason: reason || null, rejected_by: decidedBy.id, approved_by: null, approved_at: null, updated_at: now };

  const { error: updateError } = await supabase.from('loans').update(update).eq('id', loanId);
  if (updateError) throw updateError;

  try {
    await supabase.from('audit_logs').insert({
      actor_id: decidedBy.id,
      actor_role: decidedBy.role,
      action: approve ? 'LOAN_APPROVED' : 'LOAN_REJECTED',
      target_model: 'Loan',
      target_id: loanId,
      metadata: { reason: reason || null, via: 'approval_center', approved: approve },
    });
  } catch (_) {}

  try {
    const fmt = `₦${Number(loan.amount || 0).toLocaleString()}`;
    await notifyService.broadcast({
      profileIds: [loan.profile_id],
      channels: ['in_app', 'email'],
      title: approve ? 'Loan Approved 🎉' : 'Loan Application Update',
      body: approve
        ? `Your loan of ${fmt} has been approved and will be disbursed shortly.`
        : `Your loan application was not approved.${reason ? ` Reason: ${reason}` : ''}`,
    });
  } catch (err) {
    logger.warn('approvalRequests: borrower notification failed:', err.message);
  }

  return { executed: true };
}

module.exports = {
  APPROVAL_PREFIX,
  parseDetails,
  findPendingLoanApproval,
  createApprovalRequest,
  executeLoanApprovalDecision,
};
