/**
 * Payment Proof Admin Routes
 * 
 * Admin endpoints for managing and verifying payment proofs submitted by members.
 * Used by the Admin Dashboard to review, approve, or reject payment proofs.
 * 
 * Authentication: Supabase JWT (requireAdmin middleware) — flows with the existing Admin Dashboard integration on this backend.
 */

const express = require('express');
const { body, param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');

router.use(requireAdmin);

function paging(req) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
  return { page, limit, from: (page - 1) * limit, to: page * limit - 1 };
}

async function logAdminAction(action, resource, resourceId, metadata = {}, req = null) {
  try {
    await supabase.from('audit_logs').insert({
      actor_id: req?.user?.id || null,
      actor_type: 'admin',
      action,
      resource,
      resource_id: resourceId,
      details: { ...metadata, source: 'admin-web' },
      ip_address: req?.ip || null,
      user_agent: req?.get('user-agent') || null,
    });
  } catch (err) {
    logger.warn('audit_logs insert failed:', err.message);
  }
}

async function logMemberActivity(profileId, activityType, description, metadata = {}, req = null) {
  try {
    await supabase.from('member_activity_timeline').insert({
      profile_id: profileId,
      activity_type: activityType,
      description,
      metadata,
      actor_type: 'admin',
      ip_address: req?.ip || null,
      device_info: req?.get('user-agent') || null,
    });
  } catch (err) {
    logger.warn('member_activity_timeline insert failed:', err.message);
  }
}

/**
 * GET /api/v2/admin/payment-proofs/summary
 * Get summary statistics for payment proofs
 */
router.get('/summary', async (req, res) => {
  try {
    const { count: total } = await supabase
      .from('payment_proofs')
      .select('*', { count: 'exact', head: true })
      .is('deleted_at', null);

    const { count: pending } = await supabase
      .from('payment_proofs')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'pending')
      .is('deleted_at', null);

    const { count: underReview } = await supabase
      .from('payment_proofs')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'under_review')
      .is('deleted_at', null);

    const { count: approved } = await supabase
      .from('payment_proofs')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'approved')
      .is('deleted_at', null);

    const { count: rejected } = await supabase
      .from('payment_proofs')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'rejected')
      .is('deleted_at', null);

    // Get today's stats
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayISO = today.toISOString();

    const { data: todayData } = await supabase
      .from('payment_proofs')
      .select('amount, status')
      .gte('created_at', todayISO)
      .is('deleted_at', null);

    const todayStats = todayData || [];
    const approvedToday = todayStats.filter(p => p.status === 'approved');
    const rejectedToday = todayStats.filter(p => p.status === 'rejected');

    // Get total amounts
    const { data: allAmounts } = await supabase
      .from('payment_proofs')
      .select('amount, status')
      .eq('status', 'approved')
      .is('deleted_at', null);

    const totalApprovedAmount = (allAmounts || []).reduce((sum, p) => sum + parseFloat(p.amount), 0);
    const todayApprovedAmount = approvedToday.reduce((sum, p) => sum + parseFloat(p.amount), 0);

    res.json({
      success: true,
      summary: {
        total: total || 0,
        pending: pending || 0,
        under_review: underReview || 0,
        approved: approved || 0,
        rejected: rejected || 0,
        total_approved_amount: totalApprovedAmount,
        pending_today: todayStats.length,
        approved_today: approvedToday.length,
        rejected_today: rejectedToday.length,
        today_approved_amount: todayApprovedAmount,
      },
    });
  } catch (err) {
    logger.error('Payment proofs summary error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v2/admin/payment-proofs
 * List all payment proofs with filtering and pagination
 */
router.get('/', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    
    let q = supabase
      .from('payment_proofs')
      .select(`
        *,
        profile:profiles!profile_id(id, user_id, name, email, phone, role)
      `, { count: 'exact' })
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .range(from, to);

    // Apply filters
    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.payment_type) q = q.eq('payment_type', req.query.payment_type);
    if (req.query.profile_id) q = q.eq('profile_id', req.query.profile_id);
    
    // Date range filter
    if (req.query.from_date) q = q.gte('created_at', new Date(req.query.from_date).toISOString());
    if (req.query.to_date) q = q.lte('created_at', new Date(req.query.to_date + 'T23:59:59').toISOString());
    
    // Search by member name, email, or transaction reference
    if (req.query.search) {
      const search = req.query.search;
      q = q.or(`transaction_reference.ilike.%${search}%,profile.name.ilike.%${search}%,profile.email.ilike.%${search}%,profile.user_id.ilike.%${search}%`);
    }

    const { data, error, count } = await q;
    if (error) throw error;

    // Get receipts for approved proofs
    const proofIds = (data || []).filter(p => p.status === 'approved').map(p => p.id);
    let receipts = {};
    
    if (proofIds.length > 0) {
      const { data: receiptData } = await supabase
        .from('digital_receipts')
        .select('id, receipt_number, payment_proof_id')
        .in('payment_proof_id', proofIds);
      
      (receiptData || []).forEach(r => {
        receipts[r.payment_proof_id] = r;
      });
    }

    const proofs = (data || []).map(proof => ({
      ...proof,
      receipt: receipts[proof.id] || null,
      member: proof.profile,
    }));

    res.json({
      success: true,
      payment_proofs: proofs,
      pagination: {
        page,
        limit,
        total: count || 0,
        total_pages: Math.ceil((count || 0) / limit),
      },
    });
  } catch (err) {
    logger.error('Admin list payment proofs error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v2/admin/payment-proofs/:id
 * Get detailed view of a specific payment proof
 */
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: proof, error } = await supabase
      .from('payment_proofs')
      .select(`
        *,
        profile:profiles!profile_id(id, user_id, name, email, phone, role, created_at)
      `)
      .eq('id', id)
      .is('deleted_at', null)
      .maybeSingle();

    if (error) throw error;
    if (!proof) {
      return res.status(404).json({
        success: false,
        error: 'Payment proof not found',
      });
    }

    // Get receipt if exists
    let receipt = null;
    if (proof.status === 'approved') {
      const { data: receiptData } = await supabase
        .from('digital_receipts')
        .select('*')
        .eq('payment_proof_id', proof.id)
        .maybeSingle();
      receipt = receiptData;
    }

    // Get related transactions
    const { data: transactions } = await supabase
      .from('transactions')
      .select('*')
      .eq('profile_id', proof.profile_id)
      .eq('reference', proof.transaction_reference)
      .limit(5);

    // Get audit logs for this proof
    const { data: auditLogs } = await supabase
      .from('audit_logs')
      .select('*')
      .eq('resource_id', proof.id)
      .order('created_at', { ascending: false })
      .limit(10);

    // Get reviewer info if approved/rejected
    let reviewer = null;
    if (proof.approved_by) {
      const { data: reviewerData } = await supabase
        .from('profiles')
        .select('id, name, email, role')
        .eq('id', proof.approved_by)
        .maybeSingle();
      reviewer = reviewerData;
    }

    res.json({
      success: true,
      payment_proof: {
        ...proof,
        member: proof.profile,
        receipt,
        transactions: transactions || [],
        audit_logs: auditLogs || [],
        reviewer,
      },
    });
  } catch (err) {
    logger.error('Admin get payment proof error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PATCH /api/v2/admin/payment-proofs/:id/review
 * Update review status (mark as under review)
 */
router.patch(
  '/:id/review',
  [param('id').isUUID()],
  validate,
  async (req, res) => {
    try {
      const { id } = req.params;

      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('id, status, profile_id')
        .eq('id', id)
        .is('deleted_at', null)
        .maybeSingle();

      if (error) throw error;
      if (!proof) {
        return res.status(404).json({
          success: false,
          error: 'Payment proof not found',
        });
      }

      if (proof.status !== 'pending') {
        return res.status(400).json({
          success: false,
          error: 'Only pending payment proofs can be marked for review',
          status: proof.status,
        });
      }

      const { data: updated, error: updateError } = await supabase
        .from('payment_proofs')
        .update({
          status: 'under_review',
          updated_at: new Date().toISOString(),
        })
        .eq('id', id)
        .select('*')
        .single();

      if (updateError) throw updateError;

      await logAdminAction('PAYMENT_PROOF_MARKED_REVIEW', 'PaymentProof', id, {
        previous_status: proof.status,
        new_status: 'under_review',
      }, req);

      res.json({
        success: true,
        payment_proof: updated,
      });
    } catch (err) {
      logger.error('Review payment proof error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v2/admin/payment-proofs/:id/approve
 * Approve a payment proof
 */
router.post(
  '/:id/approve',
  [
    param('id').isUUID(),
    body('admin_notes').optional().isString().isLength({ max: 1000 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { admin_notes } = req.body;

      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('*')
        .eq('id', id)
        .is('deleted_at', null)
        .maybeSingle();

      if (error) throw error;
      if (!proof) {
        return res.status(404).json({
          success: false,
          error: 'Payment proof not found',
        });
      }

      if (!['pending', 'under_review'].includes(proof.status)) {
        return res.status(400).json({
          success: false,
          error: 'Only pending or under-review payment proofs can be approved',
          status: proof.status,
        });
      }

      const now = new Date().toISOString();

      // Update payment proof status
      const { data: updated, error: updateError } = await supabase
        .from('payment_proofs')
        .update({
          status: 'approved',
          approved_at: now,
          approved_by: req.user.id,
          admin_notes: admin_notes || null,
          updated_at: now,
        })
        .eq('id', id)
        .select('*')
        .single();

      if (updateError) throw updateError;

      // The database trigger will automatically:
      // 1. Create contribution record (for monthly_contribution type)
      // 2. Update savings balance
      // 3. Create transaction record
      // 4. Create digital receipt
      //
      // Loan repayments are NOT handled by the trigger (it only creates a
      // receipt for loan_repayment). Apply the balance effect here so that an
      // admin-confirmed "loan repayment" actually reduces what the member owes.
      // Idempotent: guarded by an existing loan_repayments row for this proof.
      if (proof.payment_type === 'loan_repayment') {
        try {
          const proofId = proof.id;
          const { data: alreadyApplied } = await supabase
            .from('loan_repayments')
            .select('id')
            .eq('reference', proofId)
            .maybeSingle();

          if (!alreadyApplied) {
            const repaymentAmount = parseFloat(proof.amount) || 0;
            // Pick the member's active loan with the highest remaining balance.
            // (status 'active' first, then 'approved' with a disbursed balance.)
            const { data: memberLoans } = await supabase
              .from('loans')
              .select('id, loan_id, remaining_balance, total_repayment, status')
              .eq('profile_id', proof.profile_id)
              .in('status', ['active', 'approved'])
              .order('remaining_balance', { ascending: false, nullsFirst: false });

            const targetLoan = (memberLoans && memberLoans[0]) || null;
            if (targetLoan && repaymentAmount > 0) {
              const currentBal = parseFloat(
                targetLoan.remaining_balance != null
                  ? targetLoan.remaining_balance
                  : targetLoan.total_repayment,
              ) || 0;
              const newBalance = Math.max(0, currentBal - repaymentAmount);
              const loanUpdate = {
                remaining_balance: newBalance,
                updated_at: now,
              };
              if (newBalance <= 0) {
                loanUpdate.status = 'completed';
                loanUpdate.remaining_months = 0;
              }
              await supabase.from('loans').update(loanUpdate).eq('id', targetLoan.id);

              await supabase.from('loan_repayments').insert({
                loan_id: targetLoan.id,
                profile_id: proof.profile_id,
                amount: repaymentAmount,
                paid_at: now,
                status: 'paid',
                reference: proofId,
                recorded_by: req.user.id,
              });

              logger.info(
                `Loan repayment applied: proof ${proofId} → loan ${targetLoan.loan_id || targetLoan.id} ` +
                  `(₦${repaymentAmount}, balance ₦${currentBal} → ₦${newBalance})`,
              );
            } else if (!targetLoan) {
              logger.warn(
                `Loan repayment proof ${proofId} approved but member has no active/approved loan to apply it to.`,
              );
            }
          }
        } catch (applyErr) {
          // Never fail the approval because of the balance application — it can
          // be reconciled later. The proof is already marked approved.
          logger.error('Apply loan repayment effect failed (non-fatal):', applyErr.message);
        }

        // Lift the system default-flag once the member no longer has any
        // overdue/defaulted/in-recovery loans (Policy: Active Default
        // Restriction). Manual fraud flags (other flag_reasons) are untouched.
        try {
          const { data: profile } = await supabase
            .from('profiles')
            .select('id, is_flagged, flag_reason')
            .eq('id', proof.profile_id)
            .maybeSingle();
          if (profile?.is_flagged === true && profile?.flag_reason === 'loan_default') {
            const { data: blocking } = await supabase
              .from('loans')
              .select('id')
              .eq('profile_id', proof.profile_id)
              .in('status', ['overdue', 'defaulted', 'in_recovery'])
              .limit(1);
            if (!blocking || blocking.length === 0) {
              await supabase
                .from('profiles')
                .update({ is_flagged: false, flag_reason: null })
                .eq('id', proof.profile_id);
              logger.info(`Default flag cleared for profile ${proof.profile_id} after repayment verification.`);
            }
          }
        } catch (unflagErr) {
          logger.warn('Default-flag clear check failed (non-fatal):', unflagErr.message);
        }
      }

      // Registration fee approval → mark the fee as paid and activate the
      // membership (the activation gate: kyc_verified AND registration_fee_paid).
      // Idempotent — only flips the flag once. Also settles the corresponding
      // member_fees registration_fee obligation so the wallet/obligations view
      // no longer lists it as outstanding.
      if (proof.payment_type === 'registration_fee' && !proof.profile_id === false) {
        try {
          const { data: profile } = await supabase
            .from('profiles')
            .select('id, registration_fee_paid')
            .eq('id', proof.profile_id)
            .maybeSingle();

          if (profile && profile.registration_fee_paid !== true) {
            await supabase
              .from('profiles')
              .update({
                registration_fee_paid: true,
                registration_fee_paid_at: now,
                registration_completed: true,
                updated_at: now,
              })
              .eq('id', proof.profile_id);
            logger.info(`Registration fee verified — membership activated for profile ${proof.profile_id}`);
          }

          // Settle any outstanding registration_fee obligation for this member.
          await supabase
            .from('member_fees')
            .update({ status: 'paid', paid_at: now, deposit_id: proof.id })
            .eq('profile_id', proof.profile_id)
            .eq('fee_type', 'registration_fee')
            .eq('status', 'outstanding');
        } catch (applyFeeErr) {
          logger.error('Apply registration-fee activation failed (non-fatal):', applyFeeErr.message);
        }
      }

      // Get the created receipt
      const { data: receipt } = await supabase
        .from('digital_receipts')
        .select('*')
        .eq('payment_proof_id', id)
        .maybeSingle();

      // Log admin action
      await logAdminAction('PAYMENT_PROOF_APPROVED', 'PaymentProof', id, {
        amount: proof.amount,
        payment_type: proof.payment_type,
        transaction_reference: proof.transaction_reference,
        has_receipt: !!receipt,
      }, req);

      await logMemberActivity(proof.profile_id, 'payment_verified', 
        `Payment proof of ₦${parseFloat(proof.amount).toLocaleString()} has been verified and approved`,
        {
          payment_type: proof.payment_type,
          amount: proof.amount,
          has_receipt: !!receipt,
          receipt_number: receipt?.receipt_number,
        }, req
      );

      // Send notifications
      try {
        await notifyService.notifyPaymentProofApproved({
          profileId: proof.profile_id,
          amount: proof.amount,
          paymentType: proof.payment_type,
          receiptNumber: receipt?.receipt_number,
          transactionReference: proof.transaction_reference,
        });
      } catch (notifyErr) {
        logger.warn('Failed to send approval notification:', notifyErr.message);
      }

      logger.info(`Payment proof ${id} approved by admin`);

      res.json({
        success: true,
        message: 'Payment proof approved successfully. Member has been credited.',
        payment_proof: updated,
        receipt,
      });
    } catch (err) {
      logger.error('Approve payment proof error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v2/admin/payment-proofs/:id/reject
 * Reject a payment proof
 */
router.post(
  '/:id/reject',
  [
    param('id').isUUID(),
    body('reason').isString().isLength({ min: 10, max: 500 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { reason, rejection_category } = req.body;

      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('*')
        .eq('id', id)
        .is('deleted_at', null)
        .maybeSingle();

      if (error) throw error;
      if (!proof) {
        return res.status(404).json({
          success: false,
          error: 'Payment proof not found',
        });
      }

      if (!['pending', 'under_review'].includes(proof.status)) {
        return res.status(400).json({
          success: false,
          error: 'Only pending or under-review payment proofs can be rejected',
          status: proof.status,
        });
      }

      const now = new Date().toISOString();

      const { data: updated, error: updateError } = await supabase
        .from('payment_proofs')
        .update({
          status: 'rejected',
          rejected_at: now,
          rejection_reason: reason,
          updated_at: now,
        })
        .eq('id', id)
        .select('*')
        .single();

      if (updateError) throw updateError;

      // Log admin action
      await logAdminAction('PAYMENT_PROOF_REJECTED', 'PaymentProof', id, {
        amount: proof.amount,
        payment_type: proof.payment_type,
        rejection_reason: reason,
        rejection_category,
      }, req);

      await logMemberActivity(proof.profile_id, 'payment_rejected',
        `Payment proof of ₦${parseFloat(proof.amount).toLocaleString()} was rejected: ${reason}`,
        {
          payment_type: proof.payment_type,
          amount: proof.amount,
          rejection_reason: reason,
          rejection_category,
        }, req
      );

      // Send notification to member
      try {
        await notifyService.notifyPaymentProofRejected({
          profileId: proof.profile_id,
          amount: proof.amount,
          paymentType: proof.payment_type,
          rejectionReason: reason,
          rejectionCategory: rejection_category,
          transactionReference: proof.transaction_reference,
        });
      } catch (notifyErr) {
        logger.warn('Failed to send rejection notification:', notifyErr.message);
      }

      logger.info(`Payment proof ${id} rejected by admin: ${reason}`);

      res.json({
        success: true,
        message: 'Payment proof rejected. Member has been notified.',
        payment_proof: updated,
      });
    } catch (err) {
      logger.error('Reject payment proof error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v2/admin/payment-proofs/:id/request-info
 * Request additional information from member
 */
router.post(
  '/:id/request-info',
  [
    param('id').isUUID(),
    body('message').isString().isLength({ min: 10, max: 500 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { message } = req.body;

      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('id, profile_id, status')
        .eq('id', id)
        .is('deleted_at', null)
        .maybeSingle();

      if (error) throw error;
      if (!proof) {
        return res.status(404).json({
          success: false,
          error: 'Payment proof not found',
        });
      }

      // Log the request
      await logAdminAction('PAYMENT_PROOF_INFO_REQUESTED', 'PaymentProof', id, {
        message,
      }, req);

      await logMemberActivity(proof.profile_id, 'payment_info_requested',
        `Additional information requested for payment proof: ${message}`,
        {
          message,
          payment_proof_id: id,
        }, req
      );

      // Send notification
      try {
        await notifyService.notifyPaymentProofInfoRequested({
          profileId: proof.profile_id,
          message,
          paymentProofId: id,
        });
      } catch (notifyErr) {
        logger.warn('Failed to send info request notification:', notifyErr.message);
      }

      res.json({
        success: true,
        message: 'Information request sent to member',
      });
    } catch (err) {
      logger.error('Request info error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v2/admin/payment-proofs/:id/history
 * Get audit history for a payment proof
 */
router.get('/:id/history', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: logs, error } = await supabase
      .from('audit_logs')
      .select('*')
      .eq('resource_id', id)
      .order('created_at', { ascending: false });

    if (error) throw error;

    res.json({
      success: true,
      history: logs || [],
    });
  } catch (err) {
    logger.error('Get payment proof history error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v2/admin/payment-proofs/export
 * Export payment proofs as CSV
 */
router.get('/export/pending', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('payment_proofs')
      .select(`
        id,
        created_at,
        payment_type,
        amount,
        payment_date,
        payment_method,
        transaction_reference,
        status,
        profile:profiles!profile_id(user_id, name, email, phone)
      `)
      .eq('status', 'pending')
      .is('deleted_at', null)
      .order('created_at', { ascending: true });

    if (error) throw error;

    // Generate CSV
    const headers = ['ID', 'Date', 'Member ID', 'Name', 'Email', 'Phone', 'Type', 'Amount', 'Reference', 'Status'];
    const rows = (data || []).map(p => [
      p.id,
      new Date(p.created_at).toISOString().split('T')[0],
      p.profile?.user_id || '',
      p.profile?.name || '',
      p.profile?.email || '',
      p.profile?.phone || '',
      p.payment_type,
      p.amount,
      p.transaction_reference || '',
      p.status,
    ]);

    const csv = [
      headers.join(','),
      ...rows.map(r => r.map(v => `"${String(v || '').replace(/"/g, '""')}"`).join(',')),
    ].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="payment-proofs-${new Date().toISOString().split('T')[0]}.csv"`);
    res.send(csv);
  } catch (err) {
    logger.error('Export payment proofs error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
