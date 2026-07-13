/**
 * Guarantor Routes
 *
 * Handles guarantor management for loan applications.
 * Guarantors are tracked via the `loan_guarantors` table which links
 * guarantor profiles to loans. This module exposes the member-facing
 * endpoints consumed by the Flutter mobile app.
 *
 * Table: loan_guarantors
 *   id, loan_id, qr_id, guarantor_id,
 *   status ('pending'|'consented'|'rejected'|'revoked'),
 *   consented_at, created_at, updated_at
 */

const express = require('express');
const { param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Map database status → Flutter-expected status.
 * DB:      'pending' | 'consented' | 'rejected' | 'revoked'
 * Flutter: 'pending' | 'accepted'  | 'declined' | 'expired'
 */
function mapStatus(dbStatus) {
  switch (dbStatus) {
    case 'consented': return 'accepted';
    case 'rejected':  return 'declined';
    case 'revoked':   return 'expired';
    default:          return dbStatus;
  }
}

/** Map Flutter status filter → database status value. */
function mapStatusFilter(flutterStatus) {
  switch (flutterStatus) {
    case 'accepted': return 'consented';
    case 'declined': return 'rejected';
    case 'expired':  return 'revoked';
    default:         return flutterStatus;
  }
}

/**
 * Build a GuarantorRequest-shaped object from a joined DB row.
 * `row._consentedCount` must be set before calling this.
 * Fetches borrower profile separately to avoid FK join errors.
 */
async function toGuarantorRequest(row) {
  const loan = row.loans || {};

  // Fetch borrower profile separately (safer without FK join)
  let borrowerName = 'Coopvest Member';
  let borrowerPhone = '';
  if (loan.profile_id) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('name, phone')
      .eq('id', loan.profile_id)
      .maybeSingle();
    if (profile) {
      borrowerName = profile.name || 'Coopvest Member';
      borrowerPhone = profile.phone || '';
    }
  }

  return {
    id: row.id,
    loanId: row.loan_id,
    loanType: loan.loan_type || '',
    loanAmount: parseFloat(loan.amount || 0),
    memberName: borrowerName,
    memberPhone: borrowerPhone,
    memberId: loan.profile_id || '',
    requestedAt: row.created_at,
    expiresAt: null,
    status: mapStatus(row.status || 'pending'),
    requiredGuarantors: 3,
    currentGuarantors: row._consentedCount || 0,
  };
}

/** Build a GuaranteedLoan-shaped object from a joined DB row. */
async function toGuaranteedLoan(row) {
  const loan = row.loans || {};

  // Fetch borrower profile separately
  let borrowerName = 'Coopvest Member';
  if (loan.profile_id) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('name')
      .eq('id', loan.profile_id)
      .maybeSingle();
    if (profile) {
      borrowerName = profile.name || 'Coopvest Member';
    }
  }

  let status = 'active';
  if (loan.status === 'completed') status = 'completed';
  else if (loan.status === 'defaulted') status = 'defaulted';

  return {
    id: row.id,
    loanId: row.loan_id,
    loanType: loan.loan_type || '',
    loanAmount: parseFloat(loan.amount || 0),
    borrowerName: borrowerName,
    guaranteedAt: row.consented_at || row.created_at,
    status,
  };
}

/** Shared SELECT fragment for loan_guarantors with nested loan + borrower.
 * Uses separate queries instead of FK joins to avoid foreign key errors. */
const GUARANTOR_SELECT = `
  id,
  loan_id,
  qr_id,
  status,
  created_at,
  consented_at,
  loans (
    id,
    loan_type,
    amount,
    tenure_months,
    profile_id,
    status
  )
`;

/** Attach the count of already-consented guarantors to each row (in-place). */
async function attachConsentedCount(rows) {
  await Promise.all(rows.map(async (row) => {
    const { count } = await supabase
      .from('loan_guarantors')
      .select('id', { count: 'exact', head: true })
      .eq('loan_id', row.loan_id)
      .eq('status', 'consented');
    row._consentedCount = count || 0;
  }));
}

// ---------------------------------------------------------------------------
// GET /pending-requests
// ---------------------------------------------------------------------------
router.get('/pending-requests', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('loan_guarantors')
      .select(GUARANTOR_SELECT)
      .eq('guarantor_id', req.user.id)
      .eq('status', 'pending')
      .order('created_at', { ascending: false });

    if (error) throw error;

    const rows = data || [];
    await attachConsentedCount(rows);

    const requests = await Promise.all(rows.map(toGuarantorRequest));
    res.json({ success: true, requests, total: requests.length });
  } catch (err) {
    logger.error('Error fetching pending guarantor requests:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// GET /requests  (all statuses, optional ?status= filter)
// ---------------------------------------------------------------------------
router.get(
  '/requests',
  authenticate,
  [query('status').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const statusFilter = req.query.status || 'all';

      let q = supabase
        .from('loan_guarantors')
        .select(GUARANTOR_SELECT)
        .eq('guarantor_id', req.user.id)
        .order('created_at', { ascending: false });

      if (statusFilter !== 'all') {
        q = q.eq('status', mapStatusFilter(statusFilter));
      }

      const { data, error } = await q;
      if (error) throw error;

      const rows = data || [];
      await attachConsentedCount(rows);

      const requests = await Promise.all(rows.map(toGuarantorRequest));
      res.json({ success: true, requests, total: requests.length });
    } catch (err) {
      logger.error('Error fetching guarantor requests:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// GET /requests/:requestId
// ---------------------------------------------------------------------------
router.get(
  '/requests/:requestId',
  authenticate,
  [param('requestId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const { data: row, error } = await supabase
        .from('loan_guarantors')
        .select(GUARANTOR_SELECT)
        .eq('id', req.params.requestId)
        .eq('guarantor_id', req.user.id)
        .maybeSingle();

      if (error) throw error;
      if (!row) return res.status(404).json({ success: false, error: 'Guarantor request not found' });

      const { count } = await supabase
        .from('loan_guarantors')
        .select('id', { count: 'exact', head: true })
        .eq('loan_id', row.loan_id)
        .eq('status', 'consented');
      row._consentedCount = count || 0;

      const request = await toGuarantorRequest(row);
      res.json({ success: true, ...request });
    } catch (err) {
      logger.error('Error fetching guarantor request:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// POST /requests/:requestId/accept
// ---------------------------------------------------------------------------
router.post(
  '/requests/:requestId/accept',
  authenticate,
  [param('requestId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const { requestId } = req.params;

      // Support two caller flows:
      //  1. Guarantor dashboard — passes loan_guarantors.id (the PK)
      //  2. QR-scan flow in the Flutter app — passes loans.id (the loan UUID)
      // Try by PK first; if nothing found, try by loan_id.
      let row = null;
      {
        const { data: byId, error: err1 } = await supabase
          .from('loan_guarantors')
          .select('id, loan_id, qr_id, status')
          .eq('id', requestId)
          .eq('guarantor_id', req.user.id)
          .maybeSingle();
        if (err1) throw err1;
        row = byId;
      }

      if (!row) {
        const { data: byLoanId, error: err2 } = await supabase
          .from('loan_guarantors')
          .select('id, loan_id, qr_id, status')
          .eq('loan_id', requestId)
          .eq('guarantor_id', req.user.id)
          .maybeSingle();
        if (err2) throw err2;
        row = byLoanId;
      }

      if (!row) return res.status(404).json({ success: false, error: 'Guarantor request not found' });
      if (row.status !== 'pending') {
        return res.status(400).json({ success: false, error: `Request is already ${mapStatus(row.status)}` });
      }

      const now = new Date().toISOString();

      // Always update by the resolved PK (row.id), not the raw requestId param
      const { error: updateErr } = await supabase
        .from('loan_guarantors')
        .update({ status: 'consented', consented_at: now, updated_at: now })
        .eq('id', row.id);

      if (updateErr) throw updateErr;

      // Increment guarantors_found on the linked loan_qr row if present
      if (row.qr_id) {
        const { data: qrRow } = await supabase
          .from('loan_qrs')
          .select('guarantors_found')
          .eq('id', row.qr_id)
          .maybeSingle();

        if (qrRow) {
          await supabase
            .from('loan_qrs')
            .update({ guarantors_found: (qrRow.guarantors_found || 0) + 1, updated_at: now })
            .eq('id', row.qr_id);
        }
      }

      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        action: 'GUARANTOR_CONSENTED',
        target_model: 'LoanGuarantor',
        target_id: row.id,
        metadata: { loanId: row.loan_id },
      }).catch(() => {});

      res.json({ success: true, message: 'Guarantee accepted successfully' });
    } catch (err) {
      logger.error('Error accepting guarantor request:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// POST /requests/:requestId/decline
// ---------------------------------------------------------------------------
router.post(
  '/requests/:requestId/decline',
  authenticate,
  [param('requestId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const { requestId } = req.params;
      const { reason } = req.body || {};

      // Same dual-lookup as /accept: try by PK first, then by loan_id (QR scan flow).
      let row = null;
      {
        const { data: byId, error: err1 } = await supabase
          .from('loan_guarantors')
          .select('id, loan_id, status')
          .eq('id', requestId)
          .eq('guarantor_id', req.user.id)
          .maybeSingle();
        if (err1) throw err1;
        row = byId;
      }

      if (!row) {
        const { data: byLoanId, error: err2 } = await supabase
          .from('loan_guarantors')
          .select('id, loan_id, status')
          .eq('loan_id', requestId)
          .eq('guarantor_id', req.user.id)
          .maybeSingle();
        if (err2) throw err2;
        row = byLoanId;
      }

      if (!row) return res.status(404).json({ success: false, error: 'Guarantor request not found' });
      if (row.status !== 'pending') {
        return res.status(400).json({ success: false, error: `Request is already ${mapStatus(row.status)}` });
      }

      const now = new Date().toISOString();

      // Always update by the resolved PK (row.id), not the raw requestId param
      const { error: updateErr } = await supabase
        .from('loan_guarantors')
        .update({ status: 'rejected', updated_at: now })
        .eq('id', row.id);

      if (updateErr) throw updateErr;

      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        action: 'GUARANTOR_REJECTED',
        target_model: 'LoanGuarantor',
        target_id: row.id,
        metadata: { loanId: row.loan_id, reason: reason || null },
      }).catch(() => {});

      res.json({ success: true, message: 'Guarantee request declined' });
    } catch (err) {
      logger.error('Error declining guarantor request:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ---------------------------------------------------------------------------
// GET /my-guarantees
// ---------------------------------------------------------------------------
router.get('/my-guarantees', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('loan_guarantors')
      .select(GUARANTOR_SELECT)
      .eq('guarantor_id', req.user.id)
      .eq('status', 'consented')
      .order('consented_at', { ascending: false });

    if (error) throw error;

    const rows = data || [];
    const guarantees = await Promise.all(rows.map(toGuaranteedLoan));
    res.json({ success: true, guarantees, total: guarantees.length });
  } catch (err) {
    logger.error('Error fetching my guarantees:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// GET /stats
// ---------------------------------------------------------------------------
router.get('/stats', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('loan_guarantors')
      .select(`
        id,
        status,
        consented_at,
        loans ( amount, status )
      `)
      .eq('guarantor_id', req.user.id);

    if (error) throw error;

    const rows = data || [];

    const pendingRequests       = rows.filter(r => r.status === 'pending').length;
    const acceptedGuarantees    = rows.filter(r => r.status === 'consented').length;
    const declinedRequests      = rows.filter(r => r.status === 'rejected').length;
    const totalGuaranteedAmount = rows
      .filter(r => r.status === 'consented' && r.loans)
      .reduce((sum, r) => sum + parseFloat(r.loans.amount || 0), 0);

    res.json({
      success: true,
      pendingRequests,
      acceptedGuarantees,
      declinedRequests,
      totalGuaranteedAmount,
    });
  } catch (err) {
    logger.error('Error fetching guarantor stats:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ---------------------------------------------------------------------------
// POST /withdraw/:guaranteeId
// ---------------------------------------------------------------------------
router.post(
  '/withdraw/:guaranteeId',
  authenticate,
  [param('guaranteeId').notEmpty()],
  validate,
  async (req, res) => {
    try {
      const { guaranteeId } = req.params;

      const { data: row, error: fetchErr } = await supabase
        .from('loan_guarantors')
        .select(`id, loan_id, status, loans ( status )`)
        .eq('id', guaranteeId)
        .eq('guarantor_id', req.user.id)
        .maybeSingle();

      if (fetchErr) throw fetchErr;
      if (!row) return res.status(404).json({ success: false, error: 'Guarantee not found' });

      if (row.loans?.status && row.loans.status !== 'pending') {
        return res.status(400).json({
          success: false,
          error: 'Cannot withdraw from an approved or active loan.',
        });
      }

      const now = new Date().toISOString();
      const { error: updateErr } = await supabase
        .from('loan_guarantors')
        .update({ status: 'revoked', updated_at: now })
        .eq('id', guaranteeId);

      if (updateErr) throw updateErr;

      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        action: 'GUARANTOR_WITHDRAWN',
        target_model: 'LoanGuarantor',
        target_id: guaranteeId,
        metadata: { loanId: row.loan_id },
      }).catch(() => {});

      res.json({ success: true, message: 'Guarantee withdrawn successfully' });
    } catch (err) {
      logger.error('Error withdrawing guarantee:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

module.exports = router;
