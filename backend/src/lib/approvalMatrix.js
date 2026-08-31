/**
 * Loan Approval Matrix — maker-checker thresholds.
 *
 * Reads `system_settings['loan_approval.thresholds']` (same key the Admin
 * Dashboard's Loan Approval Matrix page manages) and decides whether a given
 * admin role may approve a loan of a given amount outright, or whether the
 * approval must go through the Approval Center (Super Admin = checker).
 */

const supabase = require('../config/supabase');
const logger = require('../utils/logger');

const SUPER_ADMIN_ROLES = ['superadmin', 'super_admin'];
const SETTING_KEY = 'loan_approval.thresholds';
const UNLIMITED = 1e12; // JSON cannot represent Infinity; treat anything above this as unlimited

const DEFAULT_THRESHOLDS = {
  levels: [
    { level: 1, maxAmount: 100000, role: 'staff' },
    { level: 2, maxAmount: 1000000, role: 'admin' },
    { level: 3, maxAmount: UNLIMITED + 1, role: 'super_admin' },
  ],
};

async function getThresholds() {
  try {
    const { data } = await supabase
      .from('system_settings')
      .select('value')
      .eq('key', SETTING_KEY)
      .maybeSingle();
    if (data?.value && Array.isArray(data.value.levels)) return data.value;
  } catch (err) {
    logger.warn('approvalMatrix: failed to load thresholds, using defaults:', err.message);
  }
  return DEFAULT_THRESHOLDS;
}

/** Maximum amount this role may approve outright (Infinity = unlimited). */
function maxApprovableAmount(role, thresholds) {
  if (SUPER_ADMIN_ROLES.includes(role || '')) return Infinity;
  const levels = (thresholds?.levels || []).filter((l) => l.role === role);
  if (levels.length === 0) return 0;
  const max = levels.reduce((m, l) => Math.max(m, Number(l.maxAmount) || 0), 0);
  return max > UNLIMITED ? Infinity : max;
}

/** True when this role must route a loan of `amount` through the Approval Center. */
async function requiresSuperAdminApproval(role, amount) {
  const thresholds = await getThresholds();
  const limit = maxApprovableAmount(role, thresholds);
  return Number(amount) > limit;
}

module.exports = {
  SUPER_ADMIN_ROLES,
  DEFAULT_THRESHOLDS,
  getThresholds,
  maxApprovableAmount,
  requiresSuperAdminApproval,
};
