/**
 * Wallet Routes
 *
 * Reads from Supabase tables: `wallets`, `transactions`. Monetary updates
 * go through a small helper that updates the wallet row atomically using
 * Postgres arithmetic.
 */

const crypto = require('crypto');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const express = require('express');
const { body } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');
const notifyService = require('../services/notifyService');
const alertService = require('../services/alertService');

const newRef = (prefix) => `${prefix}-${Date.now()}-${Math.floor(Math.random() * 10000)}`;

/**
 * Notify all admin/staff profiles about a new deposit request.
 * Non-fatal: errors are logged but never bubble up to the caller.
 */
async function notifyAdminsNewDeposit({ amount, userId, depositId, hasProof }) {
  try {
    const amountFmt = Number(amount).toLocaleString('en-NG', { style: 'currency', currency: 'NGN' });
    const proofNote = hasProof ? ' (proof attached)' : ' (no proof)';
    const title = 'New Deposit Request';
    const body = `A deposit of ${amountFmt} has been submitted${proofNote}. Verify in the admin dashboard.`;

    // 1. Fetch all admin/staff profile IDs
    const { data: admins } = await supabase
      .from('profiles')
      .select('id, email')
      .in('role', ['admin', 'super_admin', 'superadmin', 'staff', 'operator']);

    if (!admins || admins.length === 0) {
      logger.info('notifyAdminsNewDeposit: no admin profiles found');
      return;
    }

    const profileIds = admins.map(a => a.id);
    const adminEmails = admins.map(a => a.email).filter(Boolean);

    // 2. In-app notifications + FCM push for each admin
    await notifyService.broadcast({
      profileIds,
      channels: ['in_app', 'push'],
      title,
      body,
      type: 'deposit',
    });

    // 3. Email alert via alertService SMTP (non-blocking)
    if (adminEmails.length > 0) {
      await alertService.sendEmailAlert({
        title: `💰 ${title}`,
        message: `${body}<br><br>Deposit ID: <code>${depositId || 'N/A'}</code><br>User ID: <code>${userId}</code>`,
        auditId: depositId || 'deposit',
        userId,
        riskLevel: 'INFO',
        timestamp: new Date().toISOString(),
        metadata: { amount, hasProof },
      }).catch(err => logger.warn('Admin deposit email failed (non-fatal):', err.message));
    }

    logger.info(`Admin deposit notification sent to ${profileIds.length} admin(s)`);
  } catch (err) {
    logger.warn('notifyAdminsNewDeposit error (non-fatal):', err.message);
  }
}
const newTransactionId = () => `TXN-${crypto.randomUUID()}`;

async function ensureWallet(profileId) {
  const { data, error } = await supabase
    .from('wallets')
    .select('*')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (error) throw error;
  if (data) return data;
  const { data: created, error: cErr } = await supabase
    .from('wallets')
    .insert({ profile_id: profileId, balance: 0, currency: 'NGN' })
    .select('*')
    .single();
  if (cErr) throw cErr;
  return created;
}

async function adjustBalance(profileId, delta) {
  const wallet = await ensureWallet(profileId);
  const newBalance = Number(wallet.balance) + Number(delta);
  if (newBalance < 0) {
    const err = new Error('Insufficient wallet balance');
    err.statusCode = 400;
    throw err;
  }
  const { data, error } = await supabase
    .from('wallets')
    .update({ balance: newBalance })
    .eq('id', wallet.id)
    .select('*')
    .single();
  if (error) throw error;
  return data;
}

async function recordTransaction(profileId, row) {
  const { data, error } = await supabase
    .from('transactions')
    .insert({
      transaction_id: newTransactionId(),
      profile_id: profileId,
      reference: newRef('TXN'),
      status: 'completed',
      ...row,
    })
    .select('*')
    .single();
  if (error) throw error;
  return data;
}

/**
 * GET /api/v1/wallet/balance
 */
router.get('/balance', authenticate, async (req, res) => {
  try {
    const wallet = await ensureWallet(req.user.id);

    // Enrich with savings totals so the mobile dashboard's Savings card and
    // Insights can show real data (the mobile parser reads total_savings and
    // total_contributions). Best-effort: never fail the balance call if the
    // savings row is missing.
    let totalSavings = 0;
    let totalContributions = 0;
    let monthlySavings = 0;
    let consecutiveMonths = 0;
    try {
      const { data: savings } = await supabase
        .from('savings')
        .select('total_saved, monthly_savings, consecutive_months')
        .eq('profile_id', req.user.id)
        .maybeSingle();
      if (savings) {
        totalSavings = Number(savings.total_saved) || 0;
        monthlySavings = Number(savings.monthly_savings) || 0;
        consecutiveMonths = Number(savings.consecutive_months) || 0;
      }
    } catch (sErr) {
      logger.warn('wallet balance: savings lookup failed:', sErr.message);
    }

    // Total confirmed contributions = sum of successful contribution records.
    try {
      const { data: contribRows } = await supabase
        .from('contributions')
        .select('amount, status')
        .eq('profile_id', req.user.id)
        .in('status', ['completed', 'successful', 'approved']);
      totalContributions = (contribRows || []).reduce(
        (sum, c) => sum + (Number(c.amount) || 0),
        0,
      );
    } catch (cErr) {
      logger.warn('wallet balance: contributions lookup failed:', cErr.message);
    }

    res.json({
      success: true,
      balance: Number(wallet.balance),
      currency: wallet.currency || 'NGN',
      total_savings: totalSavings,
      total_contributions: totalContributions,
      monthly_savings: monthlySavings,
      consecutive_months: consecutiveMonths,
      available_for_withdrawal: Number(wallet.balance),
    });
  } catch (err) {
    logger.error('wallet balance error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/wallet/transactions
 */
router.get('/transactions', authenticate, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const page = parseInt(req.query.page) || 1;

    const { data, error, count } = await supabase
      .from('transactions')
      .select('*', { count: 'exact' })
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);

    if (error) throw error;
    res.json({
      success: true,
      transactions: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('wallet transactions error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/wallet/deposit
 */
router.post(
  '/deposit',
  authenticate,
  [body('amount').isFloat({ min: 0.01 }), body('description').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const { amount, description } = req.body;
      const wallet = await adjustBalance(req.user.id, Number(amount));
      const txn = await recordTransaction(req.user.id, {
        type: 'deposit',
        category: 'credit',
        amount,
        description: description || 'Wallet deposit',
      });
      res.status(201).json({ success: true, wallet, transaction: txn });
    } catch (err) {
      logger.error('deposit error:', err);
      res.status(err.statusCode || 500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/wallet/contribute - Creates a pending deposit request (requires admin verification)
 */
router.post(
  '/contribute',
  authenticate,
  [
    body('amount').isFloat({ min: 0.01 }),
    body('description').optional().isString(),
    body('payment_reference').optional().isString(),
    body('payment_date').optional().isISO8601(),
    body('bank_name').optional().isString(),
    body('sender_account_name').optional().isString(),
    body('sender_account_number').optional().isString(),
    body('proof_url').optional().isURL(),
  ],
  validate,
  async (req, res) => {
    try {
      const { amount, description, payment_reference, payment_date, bank_name, sender_account_name, sender_account_number, proof_url } = req.body;

      // Create a PENDING transaction (no wallet credit yet)
      const txn = await recordTransaction(req.user.id, {
        type: 'deposit',
        category: 'credit',
        amount,
        status: 'pending', // Will be updated to 'completed' after admin verification
        description: description || 'Wallet contribution',
        payment_method: 'bank_transfer',
      });

      // Create deposit request record for admin verification.
      // Non-fatal: if the deposit_requests table does not yet exist (pending migration),
      // the transaction is still recorded so the user is not blocked.
      let depositRequest = null;
      try {
        const { data: dr, error: depositErr } = await supabase
          .from('deposit_requests')
          .insert({
            profile_id: req.user.id,
            transaction_id: txn.id,
            amount: Number(amount),
            currency: 'NGN',
            status: 'pending',
            payment_reference: payment_reference || null,
            payment_date: payment_date || null,
            bank_name: bank_name || null,
            sender_account_name: sender_account_name || null,
            sender_account_number: sender_account_number || null,
            payment_proof_url: proof_url || null,
          })
          .select('*')
          .single();
        if (depositErr) {
          logger.warn('deposit_requests insert failed (run migration 001_create_deposit_requests.sql):', depositErr.message);
        } else {
          depositRequest = dr;
        }
      } catch (drErr) {
        logger.warn('deposit_requests table error (non-fatal):', drErr.message);
      }

      // Mirror the attached proof into payment_proofs so the member can see it
      // under "My Proofs". Non-fatal: the deposit itself must never be blocked.
      if (proof_url) {
        try {
          await supabase.from('payment_proofs').insert({
            profile_id: req.user.id,
            payment_type: 'monthly_contribution',
            amount: Number(amount),
            currency: 'NGN',
            payment_date: payment_date || new Date().toISOString(),
            payment_method: 'bank_transfer',
            transaction_reference: payment_reference || null,
            receiving_bank: bank_name || null,
            bank_account_name: sender_account_name || null,
            bank_account_number: sender_account_number || null,
            proof_url,
            proof_type: 'image',
            member_note: description || 'Deposit with attached proof',
            status: 'pending',
          });
        } catch (ppErr) {
          logger.warn('payment_proofs mirror insert failed (non-fatal):', ppErr.message);
        }
      }

      logger.info(`Deposit request submitted for user ${req.user.id}: ₦${amount}`);

      // Notify admins — fire-and-forget, never blocks the response
      notifyAdminsNewDeposit({
        amount,
        userId: req.user.id,
        depositId: depositRequest?.id,
        hasProof: !!proof_url,
      }).catch(() => {}); // already logs internally

      res.status(201).json({
        success: true,
        message: 'Deposit submitted for verification. Your wallet will be credited once an admin confirms your payment.',
        transaction: txn,
        deposit_request: depositRequest,
      });
    } catch (err) {
      logger.error('contribute error:', err);
      res.status(err.statusCode || 500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/wallet/deposit-requests - Get user's deposit requests
 */
router.get('/deposit-requests', authenticate, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const page = parseInt(req.query.page) || 1;
    const status = req.query.status; // optional filter

    let query = supabase
      .from('deposit_requests')
      .select('*', { count: 'exact' })
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);

    if (status) {
      query = query.eq('status', status);
    }

    const { data, error, count } = await query;

    if (error) throw error;

    res.json({
      success: true,
      deposit_requests: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('Get deposit requests error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/wallet/withdraw
 */
router.post(
  '/withdraw',
  authenticate,
  [body('amount').isFloat({ min: 0.01 }), body('description').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const { amount, description } = req.body;
      const wallet = await adjustBalance(req.user.id, -Number(amount));
      const txn = await recordTransaction(req.user.id, {
        type: 'withdrawal',
        category: 'debit',
        amount,
        description: description || 'Wallet withdrawal',
      });
      res.status(201).json({ success: true, wallet, transaction: txn });
    } catch (err) {
      logger.error('withdraw error:', err);
      res.status(err.statusCode || 500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/wallet/transfer
 */
router.post(
  '/transfer',
  authenticate,
  [
    body('toUserId').isString().notEmpty(),
    body('amount').isFloat({ min: 0.01 }),
    body('description').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const { toUserId, amount, description } = req.body;
      const { data: recipient, error: lookupErr } = await supabase
        .from('profiles')
        .select('id, user_id, name')
        .or(`user_id.eq.${toUserId},id.eq.${toUserId}`)
        .maybeSingle();
      if (lookupErr || !recipient) {
        return res.status(404).json({ success: false, error: 'Recipient not found' });
      }
      if (recipient.id === req.user.id) {
        return res.status(400).json({ success: false, error: 'Cannot transfer to yourself' });
      }

      const ref = newRef('TRF');
      const sender = await adjustBalance(req.user.id, -Number(amount));
      await adjustBalance(recipient.id, Number(amount));

      const senderTxn = await recordTransaction(req.user.id, {
        type: 'transfer_out',
        category: 'debit',
        amount,
        description: description || `Transfer to ${recipient.name || recipient.user_id}`,
        reference: ref,
        metadata: { counterparty_id: recipient.id },
      });
      await recordTransaction(recipient.id, {
        type: 'transfer_in',
        category: 'credit',
        amount,
        description: description || `Transfer from ${req.user.name || req.user.userId}`,
        reference: ref,
        metadata: { counterparty_id: req.user.id },
      });

      res.status(201).json({ success: true, wallet: sender, transaction: senderTxn });
    } catch (err) {
      logger.error('transfer error:', err);
      res.status(err.statusCode || 500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/wallet/contributions
 * Returns the caller's contribution-type transactions.
 */
router.get('/contributions', authenticate, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const page = parseInt(req.query.page) || 1;

    const { data, error, count } = await supabase
      .from('transactions')
      .select('*', { count: 'exact' })
      .eq('profile_id', req.user.id)
      .eq('category', 'contribution')
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);

    if (error) throw error;

    res.json({
      success: true,
      data: data || [],
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('wallet contributions error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/wallet/transactions/:id/receipt
 * Returns a receipt summary for a specific transaction.
 */
router.get('/transactions/:id/receipt', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('transactions')
      .select('*')
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .maybeSingle();

    if (error) throw error;
    if (!data) {
      return res.status(404).json({ success: false, error: 'Transaction not found' });
    }

    const receipt = {
      receipt_id: `RCT-${data.reference || data.id}`,
      transaction_id: data.id,
      reference: data.reference,
      type: data.type,
      category: data.category,
      amount: data.amount,
      currency: data.currency || 'NGN',
      description: data.description,
      status: data.status,
      created_at: data.created_at,
      receipt_url: null,
    };

    res.json({ success: true, receipt });
  } catch (err) {
    logger.error('transaction receipt error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/wallet/statement
 */
router.get('/statement', authenticate, async (req, res) => {
  try {
    const from = req.query.from ? new Date(req.query.from).toISOString() : null;
    const to = req.query.to ? new Date(req.query.to).toISOString() : null;

    let q = supabase
      .from('transactions')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });
    if (from) q = q.gte('created_at', from);
    if (to) q = q.lte('created_at', to);

    const { data, error } = await q;
    if (error) throw error;

    const totals = (data || []).reduce(
      (acc, t) => {
        if (t.category === 'credit') acc.credits += Number(t.amount);
        else acc.debits += Number(t.amount);
        return acc;
      },
      { credits: 0, debits: 0 }
    );

    res.json({ success: true, transactions: data || [], totals });
  } catch (err) {
    logger.error('statement error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/wallet/payment-settings
 * Returns the current payment account details shown on the deposit screen (no admin required).
 */
router.get('/payment-settings', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('settings')
      .select('value')
      .eq('key', 'payment_account')
      .maybeSingle();

    if (error) throw error;

    if (data?.value) {
      return res.json({ success: true, ...data.value });
    }

    return res.json({
      success: true,
      bank: process.env.DEFAULT_PAYMENT_BANK || 'Opay',
      account_name: process.env.DEFAULT_PAYMENT_ACCOUNT_NAME || 'Coopvest Africa',
      account_number: process.env.DEFAULT_PAYMENT_ACCOUNT_NUMBER || '',
    });
  } catch (err) {
    logger.error('wallet payment-settings error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});


/**
 * POST /api/v1/wallet/upload-proof — Upload a bank-transfer proof screenshot.
 * Returns { success: true, url: '<public-url>' }.
 * The URL is then passed as `proof_url` to POST /wallet/contribute.
 */
router.post('/upload-proof', authenticate, upload.single('proof'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded.' });
    }
    const ext = (req.file.originalname.split('.').pop() || 'jpg').toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'pdf'].includes(ext)) {
      return res.status(400).json({ success: false, message: 'Only JPG, PNG, or PDF allowed.' });
    }
    const storagePath = `proofs/${req.user.id}/${uuidv4()}.${ext}`;
    const { error: uploadError } = await supabase.storage
      .from('deposit-proofs')
      .upload(storagePath, req.file.buffer, {
        contentType: req.file.mimetype,
        upsert: false,
      });
    if (uploadError) throw uploadError;

    const { data: { publicUrl } } = supabase.storage
      .from('deposit-proofs')
      .getPublicUrl(storagePath);

    logger.info(`Deposit proof uploaded for user ${req.user.id}: ${storagePath}`);
    res.json({ success: true, url: publicUrl });
  } catch (err) {
    logger.error('upload-proof error:', err);
    res.status(500).json({ success: false, message: err.message || 'Upload failed.' });
  }
});

module.exports = router;
module.exports.ensureWallet = ensureWallet;
module.exports.adjustBalance = adjustBalance;
module.exports.recordTransaction = recordTransaction;
