/**
 * Ownership Validation Middleware
 *
 * Validates that users can only access their own resources. Uses Supabase
 * tables as the source of truth.
 */

const supabase = require('../config/supabase');
const logger = require('../utils/logger');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Look up a loan row by either its text reference (loans.loan_id, e.g.
 * "LN-...") or its canonical UUID (loans.id). Returns the row or null.
 * Makes the loan routes tolerant of whichever identifier the client sends.
 */
async function findLoanByIdentifier(identifier) {
  if (!identifier) return null;
  const column = UUID_RE.test(identifier) ? 'id' : 'loan_id';
  const { data, error } = await supabase
    .from('loans')
    .select('*')
    .eq(column, identifier)
    .maybeSingle();
  if (error) throw error;
  return data || null;
}

const verifyLoanOwnership = async (req, res, next) => {
  try {
    const { loanId } = req.params;
    if (!loanId) {
      return res.status(400).json({ success: false, error: 'Loan ID is required' });
    }

    const loan = await findLoanByIdentifier(loanId);
    if (!loan || loan.profile_id !== req.user.id) {
      return res.status(404).json({ success: false, error: 'Loan not found or access denied' });
    }

    req.loan = loan;
    req.loanId = loanId;
    req.loanOwnerId = req.user.id;
    next();
  } catch (error) {
    logger.error('Loan ownership verification error:', error);
    res.status(500).json({ success: false, error: 'Failed to verify loan ownership' });
  }
};

const verifyQROwnership = async (req, res, next) => {
  try {
    const qrId = (req.params && req.params.qrId) || (req.body && req.body.qrId);
    if (!qrId) {
      return res.status(400).json({ success: false, error: 'QR ID is required' });
    }

    const { data: qr, error } = await supabase
      .from('loan_qrs')
      .select('*')
      .eq('qr_id', qrId)
      .maybeSingle();

    if (error) throw error;
    if (!qr || qr.applicant_id !== req.user.id) {
      return res.status(404).json({ success: false, error: 'QR code not found or access denied' });
    }

    req.loanQR = qr;
    req.qrId = qrId;
    req.qrOwnerId = req.user.id;
    next();
  } catch (error) {
    logger.error('QR ownership verification error:', error);
    res.status(500).json({ success: false, error: 'Failed to verify QR ownership' });
  }
};

const requireLoanOwnership = verifyLoanOwnership;

module.exports = {
  verifyLoanOwnership,
  verifyQROwnership,
  requireLoanOwnership,
};
