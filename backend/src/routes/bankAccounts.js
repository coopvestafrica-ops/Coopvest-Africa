/**
 * Bank Accounts Routes
 *
 * Linked bank accounts are stored in Supabase `bank_accounts`, one row per
 * account per profile. The first created account is marked as default.
 */

const express = require('express');
const { body, param } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

router.use(authenticate);

/**
 * GET /api/v1/bank-accounts
 */
router.get('/', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('bank_accounts')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });
    if (error) throw error;
    res.json({ success: true, accounts: data || [] });
  } catch (err) {
    logger.error('bank accounts list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/bank-accounts
 */
router.post(
  '/',
  [
    body('bankName').isString().isLength({ min: 1, max: 120 }),
    body('accountNumber').isString().isLength({ min: 6, max: 20 }),
    body('accountName').isString().isLength({ min: 1, max: 200 }),
    body('bankCode').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const { bankName, accountNumber, accountName, bankCode } = req.body;
      const { count } = await supabase
        .from('bank_accounts')
        .select('id', { count: 'exact', head: true })
        .eq('profile_id', req.user.id);

      const { data, error } = await supabase
        .from('bank_accounts')
        .insert({
          profile_id: req.user.id,
          bank_name: bankName,
          account_number: accountNumber,
          account_name: accountName,
          bank_code: bankCode || null,
          is_default: (count || 0) === 0,
        })
        .select('*')
        .single();
      if (error) throw error;
      res.status(201).json({ success: true, account: data });
    } catch (err) {
      logger.error('bank account create error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/bank-accounts/verify
 *
 * Resolves an account number + bank code to the real account holder name via
 * Paystack's bank-resolve API. The mobile KYC bank-info screen calls this
 * instead of trusting whatever the member typed, so disbursements don't go to
 * misspelled or wrong accounts.
 *
 * Requires PAYSTACK_SECRET_KEY in the environment. When the key is not
 * configured the endpoint returns 503 so the client can fall back to manual
 * entry instead of showing a fake "Verified Account Name".
 */
router.post(
  '/verify',
  [
    body('bank_code').isString().isLength({ min: 1, max: 10 }),
    body('account_number').isString().isLength({ min: 10, max: 10 }),
  ],
  validate,
  async (req, res) => {
    try {
      const { bank_code, account_number } = req.body;
      const secretKey = process.env.PAYSTACK_SECRET_KEY;
      if (!secretKey) {
        logger.error('bank verify: PAYSTACK_SECRET_KEY not configured');
        return res.status(503).json({
          success: false,
          error: 'Account verification is temporarily unavailable. Please try again later.',
        });
      }

      const url = `https://api.paystack.co/bank/resolve?account_number=${encodeURIComponent(account_number)}&bank_code=${encodeURIComponent(bank_code)}`;
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${secretKey}` },
      });
      const payload = await response.json();

      if (!response.ok || !payload.status || !payload.data?.account_name) {
        return res.status(422).json({
          success: false,
          error: 'Could not verify this account. Check the bank and account number, then try again.',
        });
      }

      return res.json({
        success: true,
        account_name: payload.data.account_name,
        account_number: payload.data.account_number,
        bank_code,
      });
    } catch (err) {
      logger.error('bank account verify error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * PATCH /api/v1/bank-accounts/:id
 */
router.patch('/:id', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const update = {};
    if (req.body.bankName !== undefined) update.bank_name = req.body.bankName;
    if (req.body.accountNumber !== undefined) update.account_number = req.body.accountNumber;
    if (req.body.accountName !== undefined) update.account_name = req.body.accountName;
    if (req.body.bankCode !== undefined) update.bank_code = req.body.bankCode;
    const { data, error } = await supabase
      .from('bank_accounts')
      .update(update)
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Account not found' });
    res.json({ success: true, account: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PATCH /api/v1/bank-accounts/:id/default
 */
router.patch('/:id/default', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const { error: clearErr } = await supabase
      .from('bank_accounts')
      .update({ is_default: false })
      .eq('profile_id', req.user.id);
    if (clearErr) throw clearErr;
    const { data, error } = await supabase
      .from('bank_accounts')
      .update({ is_default: true })
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!data) return res.status(404).json({ success: false, error: 'Account not found' });
    res.json({ success: true, account: data });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * DELETE /api/v1/bank-accounts/:id
 */
router.delete('/:id', [param('id').isUUID()], validate, async (req, res) => {
  try {
    const { error } = await supabase
      .from('bank_accounts')
      .delete()
      .eq('id', req.params.id)
      .eq('profile_id', req.user.id);
    if (error) throw error;
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
