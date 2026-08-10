/**
 * Payment Proofs Routes
 * 
 * Endpoints for members to submit and track their proof of payment submissions.
 * Allows members to submit payment proof after making direct contributions.
 * 
 * Payment Types: monthly_contribution, loan_repayment, registration_fee, investment, other
 * Payment Methods: bank_transfer, ussd, pos, cash_deposit, card
 * Status: pending, under_review, approved, rejected
 */

const express = require('express');
const { body, param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');

router.use(authenticate);

const PAYMENT_TYPES = ['monthly_contribution', 'loan_repayment', 'registration_fee', 'investment', 'other'];
const PAYMENT_METHODS = ['bank_transfer', 'ussd', 'pos', 'cash_deposit', 'card'];

/**
 * POST /api/v1/payment-proofs
 * Submit a new payment proof
 */
router.post(
  '/',
  [
    body('payment_type').isIn(PAYMENT_TYPES),
    body('amount').isFloat({ min: 1 }),
    body('payment_date').isISO8601(),
    body('payment_method').optional().isIn(PAYMENT_METHODS),
    body('receiving_bank').optional().isString(),
    body('transaction_reference').optional().isString(),
    body('proof_url').optional().isURL(),
    body('member_note').optional().isString().isLength({ max: 500 }),
  ],
  validate,
  async (req, res) => {
    try {
      const {
        payment_type,
        amount,
        payment_date,
        payment_method,
        receiving_bank,
        bank_account_name,
        bank_account_number,
        transaction_reference,
        proof_url,
        proof_type,
        original_filename,
        file_size,
        member_note,
      } = req.body;

      // Check for duplicate submission with same reference
      if (transaction_reference) {
        const { data: existing } = await supabase
          .from('payment_proofs')
          .select('id, status')
          .eq('profile_id', req.user.id)
          .eq('transaction_reference', transaction_reference)
          .is('deleted_at', null)
          .maybeSingle();

        if (existing) {
          return res.status(400).json({
            success: false,
            error: 'A payment proof with this transaction reference already exists.',
            existing_id: existing.id,
            status: existing.status,
          });
        }
      }

      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .insert({
          profile_id: req.user.id,
          payment_type,
          amount,
          currency: 'NGN',
          payment_date,
          payment_method: payment_method || null,
          receiving_bank: receiving_bank || null,
          bank_account_name: bank_account_name || null,
          bank_account_number: bank_account_number || null,
          transaction_reference: transaction_reference || null,
          proof_url: proof_url || null,
          proof_type: proof_type || null,
          original_filename: original_filename || null,
          file_size: file_size || null,
          member_note: member_note || null,
          status: 'pending',
        })
        .select('*')
        .single();

      if (error) throw error;

      // Create audit log
      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        action: 'PAYMENT_PROOF_SUBMITTED',
        resource: 'PaymentProof',
        resource_id: proof.id,
        target_profile_id: req.user.id,
        details: {
          payment_type,
          amount,
          transaction_reference,
          source: 'mobile_app',
        },
      });

      logger.info(`Payment proof submitted by user ${req.user.id}: ${proof.id}`);

      // Notify member their submission was received (fire-and-forget)
      notifyService
        .notifyPaymentProofSubmitted({
          profileId: req.user.id,
          amount,
          paymentType: payment_type,
          transactionReference: transaction_reference,
        })
        .catch((e) => logger.warn('Payment proof submitted notification failed (non-fatal):', e.message));

      res.status(201).json({
        success: true,
        message: 'Your payment proof has been submitted successfully and is awaiting verification by the Coopvest Africa team.',
        payment_proof: proof,
      });
    } catch (err) {
      logger.error('Payment proof submission error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/payment-proofs/upload
 * Upload proof file (returns URL)
 * This is a placeholder - actual file upload should use Supabase Storage
 */
router.post(
  '/upload',
  [
    body('filename').isString().isLength({ min: 1, max: 255 }),
    body('mime_type').isString().isIn(['image/jpeg', 'image/png', 'application/pdf']),
    body('file_data').isString(), // Base64 encoded
  ],
  validate,
  async (req, res) => {
    try {
      const { filename, mime_type, file_data } = req.body;

      // Validate file size (max 10MB)
      const buffer = Buffer.from(file_data, 'base64');
      if (buffer.length > 10 * 1024 * 1024) {
        return res.status(400).json({
          success: false,
          error: 'File size exceeds maximum limit of 10MB',
        });
      }

      // Generate unique filename
      const ext = filename.split('.').pop();
      const newFilename = `${req.user.id}/${Date.now()}-${Math.random().toString(36).substr(2, 9)}.${ext}`;

      // Upload to Supabase Storage
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('payment-proofs')
        .upload(newFilename, buffer, {
          contentType: mime_type,
          upsert: false,
        });

      if (uploadError) {
        logger.error('File upload error:', uploadError);
        return res.status(500).json({
          success: false,
          error: 'Failed to upload file. Please try again.',
        });
      }

      // Get public URL
      const { data: urlData } = supabase.storage
        .from('payment-proofs')
        .getPublicUrl(newFilename);

      res.json({
        success: true,
        proof_url: urlData.publicUrl,
        filename: newFilename,
        file_size: buffer.length,
        proof_type: mime_type.startsWith('image/') ? 'image' : 'pdf',
      });
    } catch (err) {
      logger.error('Payment proof upload error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/payment-proofs
 * Get all payment proofs for the current user
 */
router.get(
  '/',
  [
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 50 }),
    query('status').optional().isIn(['pending', 'under_review', 'approved', 'rejected']),
    query('payment_type').optional().isIn(PAYMENT_TYPES),
  ],
  validate,
  async (req, res) => {
    try {
      const page = parseInt(req.query.page) || 1;
      const limit = Math.min(50, parseInt(req.query.limit) || 20);
      const offset = (page - 1) * limit;

      let q = supabase
        .from('payment_proofs')
        .select('*', { count: 'exact' })
        .eq('profile_id', req.user.id)
        .is('deleted_at', null)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (req.query.status) q = q.eq('status', req.query.status);
      if (req.query.payment_type) q = q.eq('payment_type', req.query.payment_type);

      const { data, error, count } = await q;
      if (error) throw error;

      // Get associated receipts for approved proofs
      const proofIds = (data || []).map(p => p.id);
      let receipts = {};
      
      if (proofIds.length > 0) {
        const { data: receiptData } = await supabase
          .from('digital_receipts')
          .select('id, receipt_number, payment_proof_id, created_at')
          .in('payment_proof_id', proofIds);
        
        (receiptData || []).forEach(r => {
          receipts[r.payment_proof_id] = r;
        });
      }

      const proofs = (data || []).map(proof => ({
        ...proof,
        receipt: receipts[proof.id] || null,
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
      logger.error('Get payment proofs error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/payment-proofs/summary
 * Get summary of payment proofs for the current user
 */
router.get('/summary', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('payment_proofs')
      .select('status, payment_type, amount, created_at')
      .eq('profile_id', req.user.id)
      .is('deleted_at', null);

    if (error) throw error;

    const proofs = data || [];
    
    const summary = {
      total: proofs.length,
      pending: proofs.filter(p => p.status === 'pending').length,
      under_review: proofs.filter(p => p.status === 'under_review').length,
      approved: proofs.filter(p => p.status === 'approved').length,
      rejected: proofs.filter(p => p.status === 'rejected').length,
      total_amount: proofs.reduce((sum, p) => sum + parseFloat(p.amount), 0),
      approved_amount: proofs
        .filter(p => p.status === 'approved')
        .reduce((sum, p) => sum + parseFloat(p.amount), 0),
      by_type: {},
    };

    // Group by payment type
    PAYMENT_TYPES.forEach(type => {
      const typeProofs = proofs.filter(p => p.payment_type === type);
      summary.by_type[type] = {
        total: typeProofs.length,
        pending: typeProofs.filter(p => p.status === 'pending').length,
        approved: typeProofs.filter(p => p.status === 'approved').length,
        rejected: typeProofs.filter(p => p.status === 'rejected').length,
        total_amount: typeProofs.reduce((sum, p) => sum + parseFloat(p.amount), 0),
      };
    });

    res.json({
      success: true,
      summary,
    });
    } catch (err) {
      logger.error('Payment proofs summary error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/payment-proofs/:id
 * Get a specific payment proof
 */
router.get(
  '/:id',
  [param('id').isUUID()],
  validate,
  async (req, res) => {
    try {
      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('*')
        .eq('id', req.params.id)
        .eq('profile_id', req.user.id)
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

      res.json({
        success: true,
        payment_proof: {
          ...proof,
          receipt,
        },
      });
    } catch (err) {
      logger.error('Get payment proof error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/payment-proofs/:id/receipt
 * Get digital receipt for an approved payment proof
 */
router.get(
  '/:id/receipt',
  [param('id').isUUID()],
  validate,
  async (req, res) => {
    try {
      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('id, status, profile_id')
        .eq('id', req.params.id)
        .eq('profile_id', req.user.id)
        .is('deleted_at', null)
        .maybeSingle();

      if (error) throw error;
      if (!proof) {
        return res.status(404).json({
          success: false,
          error: 'Payment proof not found',
        });
      }

      if (proof.status !== 'approved') {
        return res.status(400).json({
          success: false,
          error: 'Receipt is only available for approved payments',
          status: proof.status,
        });
      }

      const { data: receipt, error: receiptError } = await supabase
        .from('digital_receipts')
        .select('*')
        .eq('payment_proof_id', proof.id)
        .maybeSingle();

      if (receiptError) throw receiptError;
      if (!receipt) {
        return res.status(404).json({
          success: false,
          error: 'Receipt not found',
        });
      }

      res.json({
        success: true,
        receipt,
      });
    } catch (err) {
      logger.error('Get receipt error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * DELETE /api/v1/payment-proofs/:id
 * Cancel/delete a pending payment proof
 */
router.delete(
  '/:id',
  [param('id').isUUID()],
  validate,
  async (req, res) => {
    try {
      const { data: proof, error } = await supabase
        .from('payment_proofs')
        .select('id, status, profile_id')
        .eq('id', req.params.id)
        .eq('profile_id', req.user.id)
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
          error: 'Only pending payment proofs can be cancelled',
          status: proof.status,
        });
      }

      const { error: deleteError } = await supabase
        .from('payment_proofs')
        .update({ deleted_at: new Date().toISOString() })
        .eq('id', proof.id);

      if (deleteError) throw deleteError;

      // Audit log
      await supabase.from('audit_logs').insert({
        actor_id: req.user.id,
        action: 'PAYMENT_PROOF_CANCELLED',
        resource: 'PaymentProof',
        resource_id: proof.id,
        target_profile_id: req.user.id,
        details: { source: 'mobile_app' },
      });

      res.json({
        success: true,
        message: 'Payment proof cancelled successfully',
      });
    } catch (err) {
      logger.error('Delete payment proof error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/payment-proofs/bank-accounts
 * Get Coopvest bank accounts for payment
 */
router.get('/bank-accounts/available', async (req, res) => {
  try {
    // Return the configured bank accounts for receiving payments
    // In production, this should come from system_settings table
    const bankAccounts = [
      {
        bank_name: 'First Bank of Nigeria',
        account_name: 'Coopvest Africa Savings',
        account_number: '3085749012',
        bank_code: '011',
      },
      {
        bank_name: 'Guaranty Trust Bank',
        account_name: 'Coopvest Africa Microfinance',
        account_number: '0145689231',
        bank_code: '058',
      },
    ];

    res.json({
      success: true,
      bank_accounts: bankAccounts,
    });
  } catch (err) {
    logger.error('Get bank accounts error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
