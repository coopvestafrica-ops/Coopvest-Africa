/**
 * Shared loan policy rules — Coopvest Africa Loan Policy.
 *
 * Single source of truth for:
 *   - Savings-based loan multipliers per product (Premium 4×, Maxi 5×, others 3×)
 *   - Statuses that block new applications (Active Default Restriction)
 *   - Statuses that count as an "active loan" for the contribution-reduction guard
 *
 * NOTE: the 6-month minimum contribution-history rule is intentionally NOT
 * enforced here yet — it is disabled while the platform is in testing.
 */

const LOAN_MULTIPLIERS = {
  'Quick Loan': 3,
  'Flexi Loan': 3,
  'Stable Loan (12 months)': 3,
  'Stable Loan (18 months)': 3,
  'Premium Loan': 4,
  'Maxi Loan': 5,
  // Legacy products
  'Micro Loan': 3,
  'Business Loan': 3,
  'Emergency Loan': 3,
};
const DEFAULT_MULTIPLIER = 3;

// A member with a loan in any of these statuses cannot take a new loan.
const DEFAULT_BLOCKING_STATUSES = ['overdue', 'defaulted', 'in_recovery'];

// Loans in these statuses count as "active" for the rule that forbids
// reducing the monthly contribution below the level used for eligibility.
const ACTIVE_LOAN_STATUSES = ['approved', 'active', 'repaying', 'overdue', 'in_recovery'];

function multiplierFor(loanType) {
  return LOAN_MULTIPLIERS[loanType] || DEFAULT_MULTIPLIER;
}

function maxLoanAmount(loanType, totalSavings) {
  return (Number(totalSavings) || 0) * multiplierFor(loanType);
}

module.exports = {
  LOAN_MULTIPLIERS,
  DEFAULT_MULTIPLIER,
  DEFAULT_BLOCKING_STATUSES,
  ACTIVE_LOAN_STATUSES,
  multiplierFor,
  maxLoanAmount,
};
