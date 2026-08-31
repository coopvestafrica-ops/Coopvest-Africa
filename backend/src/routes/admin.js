/**
 * Admin Console Routes (member-JWT, admin role)
 *
 * Used by admin users logging into the mobile admin surface with their own
 * Supabase JWT. The cross-backend proxy (admin web portal) uses the
 * /api/v1/admin/* routes in `adminApi.js` which are service-token
 * authenticated instead.
 */

const express = require('express');
const router = express.Router();

const supabase = require('../config/supabase');
const { requireAdmin } = require('../middleware/auth');
const logger = require('../utils/logger');

router.use(requireAdmin);

/**
 * GET /api/v1/admin/payment-settings
 * Returns the current payment account details shown on the deposit screen.
 */
router.get('/payment-settings', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('settings')
      .select('value')
      .eq('key', 'payment_account')
      .maybeSingle();

    // Gracefully degrade if the settings table hasn't been migrated yet.
    if (error && error.message?.includes('does not exist')) {
      return res.json({
        success: true,
        bank: process.env.DEFAULT_PAYMENT_BANK || 'Opay',
        account_name: process.env.DEFAULT_PAYMENT_ACCOUNT_NAME || 'Coopvest Africa',
        account_number: process.env.DEFAULT_PAYMENT_ACCOUNT_NUMBER || '',
        _migrated: false,
      });
    }
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
    logger.error('admin payment-settings error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/overview
 */
router.get('/overview', async (req, res) => {
  try {
    const [members, loans, tickets, kyc] = await Promise.all([
      supabase.from('profiles').select('id', { count: 'exact', head: true }),
      supabase.from('loans').select('status, amount'),
      supabase.from('tickets').select('status', { count: 'exact' }),
      supabase.from('kyc').select('status'),
    ]);

    const loansSummary = (loans.data || []).reduce(
      (acc, l) => {
        acc.total += Number(l.amount || 0);
        acc.byStatus[l.status] = (acc.byStatus[l.status] || 0) + 1;
        return acc;
      },
      { total: 0, byStatus: {} }
    );

    const kycSummary = (kyc.data || []).reduce((acc, k) => {
      acc[k.status] = (acc[k.status] || 0) + 1;
      return acc;
    }, {});

    res.json({
      success: true,
      overview: {
        members: members.count || 0,
        loans: { count: (loans.data || []).length, ...loansSummary },
        tickets: { open: tickets.count || 0, byStatus: {} },
        kyc: kycSummary,
      },
    });
  } catch (err) {
    logger.error('admin overview error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PUT /api/v1/admin/payment-settings
 * Update payment account details
 */
router.put('/payment-settings', async (req, res) => {
  try {
    const { bank, account_name, account_number } = req.body;

    if (!bank || !account_name || !account_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: bank, account_name, account_number'
      });
    }

    const paymentSettings = { bank, account_name, account_number, updated_at: new Date().toISOString() };

    // Upsert payment settings
    const { data, error } = await supabase
      .from('settings')
      .upsert(
        { key: 'payment_account', value: paymentSettings },
        { onConflict: 'key' }
      )
      .select()
      .single();

    if (error) throw error;

    logger.info('Payment settings updated by admin');
    res.json({ success: true, ...paymentSettings });
  } catch (err) {
    logger.error('admin payment-settings update error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/salary-deduction
 * Get global salary deduction setting
 */
router.get('/salary-deduction', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('settings')
      .select('value')
      .eq('key', 'salary_deduction_global')
      .maybeSingle();

    if (error && error.message?.includes('does not exist')) {
      return res.json({ success: true, enabled: false, _migrated: false });
    }
    if (error) throw error;

    res.json({
      success: true,
      enabled: data?.value?.enabled ?? false,
    });
  } catch (err) {
    logger.error('admin salary-deduction get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PUT /api/v1/admin/salary-deduction
 * Update global salary deduction setting
 */
router.put('/salary-deduction', async (req, res) => {
  try {
    const { enabled } = req.body;

    if (typeof enabled !== 'boolean') {
      return res.status(400).json({
        success: false,
        error: 'enabled must be a boolean'
      });
    }

    const { data, error } = await supabase
      .from('settings')
      .upsert(
        { key: 'salary_deduction_global', value: { enabled, updated_at: new Date().toISOString() } },
        { onConflict: 'key' }
      )
      .select()
      .single();

    if (error) throw error;

    logger.info(`Salary deduction global setting updated to: ${enabled}`);
    res.json({ success: true, enabled });
  } catch (err) {
    logger.error('admin salary-deduction update error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/organizations
 * Get enrolled organizations
 */
router.get('/organizations', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('organizations')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) throw error;

    res.json({ success: true, organizations: data || [] });
  } catch (err) {
    logger.error('admin organizations get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/organizations
 * Create new organization
 */
router.post('/organizations', async (req, res) => {
  try {
    const { name, deduction_type } = req.body;

    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Organization name is required'
      });
    }

    const { data, error } = await supabase
      .from('organizations')
      .insert({
        name,
        deduction_type: deduction_type || 'manual_upload',
        deduction_enabled: false,
        remittance_cycle: 'monthly',
      })
      .select()
      .single();

    if (error) throw error;

    logger.info(`Organization created: ${name}`);
    res.json({ success: true, organization: data });
  } catch (err) {
    logger.error('admin organizations create error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PATCH /api/v1/admin/organizations/:id
 * Update organization
 */
router.patch('/organizations/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { deduction_enabled, ...rest } = req.body;

    const updateData = { ...rest };
    if (typeof deduction_enabled === 'boolean') {
      updateData.deduction_enabled = deduction_enabled;
    }

    const { data, error } = await supabase
      .from('organizations')
      .update({ ...updateData, updated_at: new Date().toISOString() })
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;
    if (!data) {
      return res.status(404).json({ success: false, error: 'Organization not found' });
    }

    logger.info(`Organization ${id} updated`);
    res.json({ success: true, organization: data });
  } catch (err) {
    logger.error('admin organizations update error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * DELETE /api/v1/admin/organizations/:id
 * Delete organization
 */
router.delete('/organizations/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { error } = await supabase
      .from('organizations')
      .delete()
      .eq('id', id);

    if (error) throw error;

    logger.info(`Organization ${id} deleted`);
    res.json({ success: true });
  } catch (err) {
    logger.error('admin organizations delete error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// =============================================================================
// Deposit Verification Endpoints
// =============================================================================

/**
 * GET /api/v1/admin/deposits
 * Get all pending deposit requests for admin review
 */
router.get('/deposits', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const page = parseInt(req.query.page) || 1;
    const status = req.query.status || 'pending'; // default to pending
    const profileId = req.query.profile_id; // optional filter by user

    let query = supabase
      .from('deposit_requests')
      .select(`
        *,
        profile:profiles(id, user_id, name, email, phone)
      `, { count: 'exact' })
      .eq('status', status)
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1);

    if (profileId) {
      query = query.eq('profile_id', profileId);
    }

    const { data, error, count } = await query;

    if (error) throw error;

    // Also get transaction details for each deposit request
    const depositRequests = await Promise.all(
      (data || []).map(async (deposit) => {
        const { data: txn } = await supabase
          .from('transactions')
          .select('*')
          .eq('id', deposit.transaction_id)
          .maybeSingle();
        return { ...deposit, transaction: txn };
      })
    );

    res.json({
      success: true,
      deposits: depositRequests,
      pagination: { page, limit, total: count || 0 },
    });
  } catch (err) {
    logger.error('admin deposits get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/deposits/:id
 * Get single deposit request details
 */
router.get('/deposits/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: deposit, error } = await supabase
      .from('deposit_requests')
      .select(`
        *,
        profile:profiles(id, user_id, name, email, phone),
        transaction:transactions(*)
      `)
      .eq('id', id)
      .maybeSingle();

    if (error) throw error;
    if (!deposit) {
      return res.status(404).json({ success: false, error: 'Deposit request not found' });
    }

    res.json({ success: true, deposit });
  } catch (err) {
    logger.error('admin deposit get error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/deposits/:id/verify
 * Verify and approve a deposit request (credits user's wallet)
 */
router.post('/deposits/:id/verify', async (req, res) => {
  try {
    const { id } = req.params;
    const { notes } = req.body; // optional admin notes

    // Get deposit request
    const { data: deposit, error: fetchErr } = await supabase
      .from('deposit_requests')
      .select('*, transaction:transactions(*)')
      .eq('id', id)
      .maybeSingle();

    if (fetchErr) throw fetchErr;
    if (!deposit) {
      return res.status(404).json({ success: false, error: 'Deposit request not found' });
    }

    if (deposit.status !== 'pending') {
      return res.status(400).json({
        success: false,
        error: `Deposit already ${deposit.status}. Cannot verify.`
      });
    }

    const profileId = deposit.profile_id;
    const amount = Number(deposit.amount);

    // Credit user's wallet
    const wallet = await ensureWallet(profileId);
    const newBalance = Number(wallet.balance) + amount;

    // Update wallet balance
    const { data: updatedWallet, error: walletErr } = await supabase
      .from('wallets')
      .update({
        balance: newBalance,
        last_updated: new Date().toISOString()
      })
      .eq('id', wallet.id)
      .select()
      .single();

    if (walletErr) throw walletErr;

    // Update transaction to completed
    if (deposit.transaction_id) {
      await supabase
        .from('transactions')
        .update({
          status: 'completed',
          completed_at: new Date().toISOString(),
          balance_before: wallet.balance,
          balance_after: newBalance,
          metadata: {
            ...(deposit.transaction?.metadata || {}),
            verified_by: req.user.id,
            verified_at: new Date().toISOString(),
            deposit_request_id: id,
          }
        })
        .eq('id', deposit.transaction_id);
    }

    // Update deposit request status
    const { data: updatedDeposit, error: updateErr } = await supabase
      .from('deposit_requests')
      .update({
        status: 'verified',
        verified_by: req.user.id,
        verified_at: new Date().toISOString(),
        admin_notes: notes || null,
      })
      .eq('id', id)
      .select()
      .single();

    if (updateErr) throw updateErr;

    logger.info(`Deposit ${id} verified by admin ${req.user.id}: ₦${amount} to user ${profileId}`);

    res.json({
      success: true,
      message: `Deposit of ₦${amount.toLocaleString()} has been verified and credited to wallet.`,
      deposit: updatedDeposit,
      wallet: updatedWallet,
    });
  } catch (err) {
    logger.error('admin deposit verify error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/deposits/:id/reject
 * Reject a deposit request
 */
router.post('/deposits/:id/reject', async (req, res) => {
  try {
    const { id } = req.params;
    const { reason } = req.body;

    if (!reason) {
      return res.status(400).json({
        success: false,
        error: 'Rejection reason is required'
      });
    }

    // Get deposit request
    const { data: deposit, error: fetchErr } = await supabase
      .from('deposit_requests')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (fetchErr) throw fetchErr;
    if (!deposit) {
      return res.status(404).json({ success: false, error: 'Deposit request not found' });
    }

    if (deposit.status !== 'pending') {
      return res.status(400).json({
        success: false,
        error: `Deposit already ${deposit.status}. Cannot reject.`
      });
    }

    // Update deposit request status
    const { data: updatedDeposit, error: updateErr } = await supabase
      .from('deposit_requests')
      .update({
        status: 'rejected',
        admin_notes: reason,
        verified_by: req.user.id,
        verified_at: new Date().toISOString(),
      })
      .eq('id', id)
      .select()
      .single();

    if (updateErr) throw updateErr;

    // Update transaction to failed
    if (deposit.transaction_id) {
      await supabase
        .from('transactions')
        .update({
          status: 'failed',
          failure_reason: reason,
        })
        .eq('id', deposit.transaction_id);
    }

    logger.info(`Deposit ${id} rejected by admin ${req.user.id}: ${reason}`);

    res.json({
      success: true,
      message: 'Deposit request has been rejected.',
      deposit: updatedDeposit,
    });
  } catch (err) {
    logger.error('admin deposit reject error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/deposits/bulk-verify
 * Verify multiple deposits at once
 */
router.post('/deposits/bulk-verify', async (req, res) => {
  try {
    const { deposit_ids } = req.body;

    if (!Array.isArray(deposit_ids) || deposit_ids.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'deposit_ids array is required'
      });
    }

    const results = { verified: [], failed: [] };

    for (const id of deposit_ids) {
      try {
        // Get deposit request
        const { data: deposit } = await supabase
          .from('deposit_requests')
          .select('*, transaction:transactions(*)')
          .eq('id', id)
          .maybeSingle();

        if (!deposit || deposit.status !== 'pending') {
          results.failed.push({ id, reason: 'Not found or not pending' });
          continue;
        }

        const profileId = deposit.profile_id;
        const amount = Number(deposit.amount);

        // Credit wallet
        const wallet = await ensureWallet(profileId);
        const newBalance = Number(wallet.balance) + amount;

        await supabase
          .from('wallets')
          .update({
            balance: newBalance,
            last_updated: new Date().toISOString()
          })
          .eq('id', wallet.id);

        // Update transaction
        if (deposit.transaction_id) {
          await supabase
            .from('transactions')
            .update({
              status: 'completed',
              completed_at: new Date().toISOString(),
              balance_before: wallet.balance,
              balance_after: newBalance,
            })
            .eq('id', deposit.transaction_id);
        }

        // Update deposit request
        await supabase
          .from('deposit_requests')
          .update({
            status: 'verified',
            verified_by: req.user.id,
            verified_at: new Date().toISOString(),
          })
          .eq('id', id);

        results.verified.push({ id, amount });
      } catch (err) {
        results.failed.push({ id, reason: err.message });
      }
    }

    logger.info(`Bulk deposit verification by admin ${req.user.id}: ${results.verified.length} verified, ${results.failed.length} failed`);

    res.json({
      success: true,
      message: `Verified ${results.verified.length} deposits, ${results.failed.length} failed.`,
      results,
    });
  } catch (err) {
    logger.error('admin bulk deposit verify error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Import ensureWallet from wallet routes for use here
const { ensureWallet } = require('./wallet');

/**
 * POST /api/v1/admin/migrate-deposit-requests
 * Creates the deposit_requests table (one-time migration)
 * Only works if table doesn't exist
 */
router.post('/migrate-deposit-requests', async (req, res) => {
  try {
    // Check if table exists
    const { data: existing } = await supabase
      .from('information_schema.tables')
      .select('table_name')
      .eq('table_schema', 'public')
      .eq('table_name', 'deposit_requests')
      .maybeSingle();

    if (existing) {
      return res.json({
        success: true,
        message: 'deposit_requests table already exists. No migration needed.'
      });
    }

    // Use Supabase's built-in function to create table via RPC
    // Since we can't run raw SQL directly, we'll use pg_* system catalogs
    // through a workaround

    // First, try to create the table using raw SQL through a workaround
    // This uses the service role to bypass RLS

    const createTableSQL = `
      CREATE TABLE IF NOT EXISTS public.deposit_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
        transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
        amount DECIMAL(18, 2) NOT NULL,
        currency TEXT DEFAULT 'NGN',
        status TEXT DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected','cancelled')),
        payment_proof_url TEXT,
        payment_reference TEXT,
        payment_date TIMESTAMPTZ,
        bank_name TEXT,
        sender_account_name TEXT,
        sender_account_number TEXT,
        admin_notes TEXT,
        verified_by UUID REFERENCES public.profiles(id),
        verified_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;

    // Try creating through storage bucket workaround or direct query
    // Since direct SQL isn't available, return instructions
    res.json({
      success: false,
      error: 'Cannot execute raw SQL through REST API',
      message: 'Please run the SQL manually in Supabase SQL Editor',
      sql: createTableSQL,
      instructions: [
        '1. Go to https://supabase.com/dashboard/project/nyoauzqezpxeonmrxxgi/sql',
        '2. Paste and run the SQL above',
        '3. The migration will complete automatically'
      ]
    });
  } catch (err) {
    logger.error('Migration error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
