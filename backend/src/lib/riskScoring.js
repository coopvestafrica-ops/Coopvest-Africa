/**
 * Member risk scoring (Policy: Risk Assessment).
 *
 * Computes a 0–100 score per member from:
 *   - Existing loans and outstanding obligations
 *   - Previous repayment behavior (defaults, overdue, penalties)
 *   - Contribution history and consistency
 *   - Guarantor exposure (problem loans they guarantee)
 *   - Employment information
 *   - Account verification (KYC)
 *   - Fraud/duplicate-account flags
 *
 * score >= 80 → low risk, >= 60 → medium, otherwise high.
 */

const supabase = require('../config/supabase');

const PROBLEM_LOAN_STATUSES = ['overdue', 'in_recovery', 'defaulted'];

/**
 * Batch-compute risk scores for a set of profile ids.
 * Returns { [profileId]: { score, riskLevel, factors } }.
 */
async function computeRiskScores(profileIds) {
  const ids = [...new Set((profileIds || []).filter(Boolean))];
  if (ids.length === 0) return {};

  const [profilesRes, loansRes, contributionsRes, guaranteesRes] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, user_id, name, email, is_active, is_flagged, kyc_status, kyc_verified, employment_status, created_at')
      .in('id', ids),
    supabase
      .from('loans')
      .select('id, profile_id, amount, status, remaining_balance, total_repayment, penalty_applied, missed_months')
      .in('profile_id', ids),
    supabase
      .from('contributions')
      .select('profile_id, contribution_month, status')
      .in('profile_id', ids)
      .eq('status', 'successful'),
    supabase
      .from('loan_guarantors')
      .select('guarantor_profile_id, loan_id, status')
      .in('guarantor_profile_id', ids)
      .in('status', ['consented', 'accepted']),
  ]);

  if (profilesRes.error) throw profilesRes.error;
  if (loansRes.error) throw loansRes.error;

  // Statuses of the loans these members guarantee (guarantor exposure).
  const guaranteedLoanIds = [...new Set((guaranteesRes.data || []).map((g) => g.loan_id).filter(Boolean))];
  let guaranteedLoanStatus = {};
  if (guaranteedLoanIds.length > 0) {
    const { data: gLoans } = await supabase.from('loans').select('id, status').in('id', guaranteedLoanIds);
    (gLoans || []).forEach((l) => { guaranteedLoanStatus[l.id] = l.status; });
  }

  const sixMonthsAgo = new Date();
  sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);

  const loansByProfile = {};
  (loansRes.data || []).forEach((l) => {
    (loansByProfile[l.profile_id] = loansByProfile[l.profile_id] || []).push(l);
  });

  const contributionMonthsByProfile = {};
  (contributionsRes.data || []).forEach((c) => {
    const month = c.contribution_month || '';
    if (!month) return;
    // contribution_month is 'YYYY-MM' or an ISO date — count the last 6 months only
    const d = new Date(month.length === 7 ? `${month}-01` : month);
    if (Number.isNaN(d.getTime()) || d < sixMonthsAgo) return;
    const key = month.slice(0, 7);
    const set = contributionMonthsByProfile[c.profile_id] || new Set();
    set.add(key);
    contributionMonthsByProfile[c.profile_id] = set;
  });

  const guaranteesByProfile = {};
  (guaranteesRes.data || []).forEach((g) => {
    (guaranteesByProfile[g.guarantor_profile_id] = guaranteesByProfile[g.guarantor_profile_id] || []).push(g);
  });

  const result = {};
  (profilesRes.data || []).forEach((p) => {
    const pLoans = loansByProfile[p.id] || [];
    const activeLoans = pLoans.filter((l) => ['active', 'approved', 'disbursed', 'repaying'].includes(l.status));
    const problemLoans = pLoans.filter((l) => PROBLEM_LOAN_STATUSES.includes(l.status));
    const defaultedLoans = pLoans.filter((l) => l.status === 'defaulted');
    const completedLoans = pLoans.filter((l) => l.status === 'completed');
    const penalizedLoans = pLoans.filter((l) => l.penalty_applied === true);
    const outstandingBalance = pLoans
      .filter((l) => ['active', 'approved', 'disbursed', 'repaying', 'overdue', 'in_recovery'].includes(l.status))
      .reduce((s, l) => s + Number(l.remaining_balance ?? l.total_repayment ?? l.amount ?? 0), 0);

    const guaranteedProblemLoans = (guaranteesByProfile[p.id] || [])
      .filter((g) => PROBLEM_LOAN_STATUSES.includes(guaranteedLoanStatus[g.loan_id]))
      .length;

    const monthsContributed = (contributionMonthsByProfile[p.id] || new Set()).size;
    const consistency = Math.min(1, monthsContributed / 6);

    const kycVerified = p.kyc_verified === true || p.kyc_status === 'verified';
    const isFlagged = p.is_flagged === true;

    let score = 100;
    score -= activeLoans.length * 5;
    score -= problemLoans.length * 15;
    score -= defaultedLoans.length * 25;
    score -= penalizedLoans.length * 5;
    score -= guaranteedProblemLoans * 10;
    if (!kycVerified) score -= 15;
    if (isFlagged) score -= 20;
    if (p.employment_status === 'unemployed') score -= 5;
    score -= Math.round((1 - consistency) * 10);
    score = Math.max(0, Math.min(100, score));

    result[p.id] = {
      score,
      riskLevel: score >= 80 ? 'low' : score >= 60 ? 'medium' : 'high',
      factors: {
        activeLoans: activeLoans.length,
        overdueLoans: problemLoans.length,
        defaultedLoans: defaultedLoans.length,
        completedLoans: completedLoans.length,
        penalizedLoans: penalizedLoans.length,
        outstandingBalance,
        guaranteedProblemLoans,
        contributionConsistency: Math.round(consistency * 100),
        monthsContributedLast6: monthsContributed,
        employmentStatus: p.employment_status || null,
        kycVerified,
        isFlagged,
      },
    };
  });

  return result;
}

module.exports = { computeRiskScores, PROBLEM_LOAN_STATUSES };
