/**
 * User Profile Routes
 * 
 * User profile and settings management endpoints with Supabase integration
 */

const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const multer = require('multer');
const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const logger = require('../utils/logger');

const AVATAR_BUCKET = process.env.AVATAR_BUCKET || 'kyc-documents';
const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  next();
};

/**
 * GET /api/v1/user/profile
 * Get current user's profile from Supabase
 */
router.get('/profile', authenticate, async (req, res) => {
  try {
    const { userId } = req.user;

    // Fetch profile, kyc, savings, and referrals in parallel
    const [profileRes, kycRes, savingsRes, referralRes] = await Promise.all([
      supabase.from('profiles').select('*').eq('user_id', userId).single(),
      supabase.from('kyc').select('*').eq('profile_id', req.user.id).single(),
      supabase.from('savings').select('*').eq('profile_id', req.user.id).single(),
      supabase.from('referrals').select('*').eq('profile_id', req.user.id).single()
    ]);

    if (profileRes.error && profileRes.error.code !== 'PGRST116') {
      throw profileRes.error;
    }

    const profile = profileRes.data;
    if (!profile) {
      return res.status(404).json({
        success: false,
        error: 'User profile not found'
      });
    }

    res.json({
      success: true,
      user: {
        userId: profile.user_id,
        email: profile.email,
        name: profile.name,
        phone: profile.phone,
        address: profile.address || null,
        profilePicture: profile.profile_picture || null,
        membershipStatus: profile.membership_status || 'active',
        referralCode: referralRes.data?.my_referral_code || null,
        referralCount: referralRes.data?.referral_count || 0,
        kycVerified: kycRes.data?.verified || false,
        emailVerified: true, // Handled by Supabase Auth
        savings: {
          totalSaved: savingsRes.data?.total_saved || 0,
          monthlySavings: savingsRes.data?.monthly_savings || 0,
          consecutiveMonths: savingsRes.data?.consecutive_months || 0
        },
        walletBalance: 0, // Wallet table needs to be implemented in Supabase
        role: profile.role,
        isActive: profile.is_active,
        createdAt: profile.created_at
      }
    });
  } catch (error) {
    logger.error('Get profile error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * PUT /api/v1/user/profile
 * Update user profile in Supabase
 */
router.put('/profile', authenticate, [
  body('name').optional().isLength({ min: 2, max: 100 }),
  body('phone').optional().isMobilePhone(),
  body('address').optional().isString().isLength({ max: 500 })
], validate, async (req, res) => {
  try {
    const { name, phone, address } = req.body;
    const { userId } = req.user;

    const updateData = {};
    if (name) updateData.name = name;
    if (phone) updateData.phone = phone;
    if (address !== undefined) updateData.address = address;

    const { data, error } = await supabase
      .from('profiles')
      .update(updateData)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) throw error;

    // Also update Supabase Auth metadata to keep them in sync
    await supabase.auth.admin.updateUserById(req.user.id, {
      user_metadata: { ...req.user.user_metadata, ...updateData }
    });

    res.json({
      success: true,
      user: {
        userId: data.user_id,
        email: data.email,
        name: data.name,
        phone: data.phone,
        address: data.address || null,
        profilePicture: data.profile_picture || null
      },
      message: 'Profile updated successfully'
    });
  } catch (error) {
    logger.error('Update profile error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * POST /api/v1/user/profile-picture
 * Upload the member's profile picture. Stored in the private Supabase Storage
 * bucket under avatars/{authUserId}/ and referenced from profiles.profile_picture
 * via a long-lived signed URL (the service role bypasses bucket RLS).
 */
router.post('/profile-picture', authenticate, avatarUpload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'An image file is required' });
    }
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowed.includes(req.file.mimetype)) {
      return res.status(400).json({ success: false, error: 'Only JPG, PNG or WEBP images are allowed' });
    }

    const ext = req.file.mimetype.split('/')[1].replace('jpeg', 'jpg');
    const storagePath = `avatars/${req.user.id}/avatar-${Date.now()}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from(AVATAR_BUCKET)
      .upload(storagePath, req.file.buffer, { contentType: req.file.mimetype, upsert: true });
    if (uploadError) throw uploadError;

    const { data: signed, error: signedErr } = await supabase.storage
      .from(AVATAR_BUCKET)
      .createSignedUrl(storagePath, 60 * 60 * 24 * 365 * 10);
    if (signedErr) throw signedErr;

    const { error: updateErr } = await supabase
      .from('profiles')
      .update({ profile_picture: signed.signedUrl })
      .eq('user_id', req.user.userId);
    if (updateErr) throw updateErr;

    res.json({ success: true, profilePicture: signed.signedUrl, message: 'Profile picture updated' });
  } catch (error) {
    logger.error('Profile picture upload error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * PUT /api/v1/user/password
 * Change password via Supabase Auth
 */
router.put('/password', authenticate, [
  body('newPassword').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
], validate, async (req, res) => {
  try {
    const { newPassword } = req.body;

    // Supabase handles password updates via the update method
    // Note: In a real app, you might want to verify the old password first, 
    // but Supabase's updateUser handles the hash update directly.
    const { error } = await supabase.auth.updateUser({
      password: newPassword
    });

    if (error) throw error;

    res.json({
      success: true,
      message: 'Password changed successfully'
    });
  } catch (error) {
    logger.error('Change password error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/v1/user/dashboard
 * Get user dashboard data from Supabase
 */
router.get('/dashboard', authenticate, async (req, res) => {
  try {
    const { userId } = req.user;

    const [profileRes, kycRes, savingsRes, referralRes] = await Promise.all([
      supabase.from('profiles').select('*').eq('user_id', userId).single(),
      supabase.from('kyc').select('*').eq('profile_id', req.user.id).single(),
      supabase.from('savings').select('*').eq('profile_id', req.user.id).single(),
      supabase.from('referrals').select('*').eq('profile_id', req.user.id).single()
    ]);

    if (profileRes.error) throw profileRes.error;

    const profile = profileRes.data;

    res.json({
      success: true,
      dashboard: {
        user: {
          name: profile.name,
          kycVerified: kycRes.data?.verified || false,
          emailVerified: true
        },
        wallet: {
          balance: 0,
          currency: 'NGN'
        },
        savings: {
          totalSaved: savingsRes.data?.total_saved || 0,
          monthlySavings: savingsRes.data?.monthly_savings || 0,
          consecutiveMonths: savingsRes.data?.consecutive_months || 0
        },
        referral: {
          code: referralRes.data?.my_referral_code || null,
          count: referralRes.data?.referral_count || 0
        }
      }
    });
  } catch (error) {
    logger.error('Get dashboard error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/v1/user/insights
 * Returns aggregated financial insights for the authenticated user.
 */
router.get('/insights', authenticate, async (req, res) => {
  try {
    const [savingsRes, transactionsRes, loansRes] = await Promise.all([
      supabase.from('savings').select('balance, currency').eq('profile_id', req.user.id).maybeSingle(),
      supabase
        .from('transactions')
        .select('type, amount, created_at')
        .eq('profile_id', req.user.id)
        .order('created_at', { ascending: false })
        .limit(100),
      supabase
        .from('loans')
        .select('status, amount, outstanding_balance')
        .eq('profile_id', req.user.id),
    ]);

    const savings = savingsRes.data;
    const transactions = transactionsRes.data || [];
    const loans = loansRes.data || [];

    const totalCredits = transactions
      .filter((t) => t.type === 'credit')
      .reduce((sum, t) => sum + Number(t.amount), 0);

    const totalDebits = transactions
      .filter((t) => t.type === 'debit')
      .reduce((sum, t) => sum + Number(t.amount), 0);

    const activeLoans = loans.filter((l) => l.status === 'active' || l.status === 'disbursed');
    const totalOutstanding = activeLoans.reduce(
      (sum, l) => sum + Number(l.outstanding_balance || l.amount || 0),
      0
    );

    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const monthlyCredits = transactions
      .filter((t) => t.type === 'credit' && t.created_at >= startOfMonth)
      .reduce((sum, t) => sum + Number(t.amount), 0);

    res.json({
      success: true,
      insights: {
        totalSavings: Number(savings?.balance || 0),
        totalCredits,
        totalDebits,
        netFlow: totalCredits - totalDebits,
        activeLoansCount: activeLoans.length,
        totalOutstandingLoanBalance: totalOutstanding,
        monthlyCredits,
        transactionCount: transactions.length,
        currency: savings?.currency || 'NGN',
      },
    });
  } catch (err) {
    logger.error('user insights error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PUT /api/v1/user/contribution-method
 * Update user's contribution method (manual vs payroll)
 */
router.put('/contribution-method', authenticate, [
  body('method').isIn(['manual', 'payroll']).withMessage('Method must be "manual" or "payroll"'),
  body('monthlyAmount').optional().isFloat({ min: 0 }).withMessage('Monthly amount must be a positive number'),
  body('preferredDay').optional().isInt({ min: 1, max: 28 }).withMessage('Preferred day must be between 1 and 28')
], validate, async (req, res) => {
  try {
    const { method, monthlyAmount, preferredDay } = req.body;
    const { userId } = req.user;

    // Build update object
    const updateData = {
      contribution_method: method,
      updated_at: new Date().toISOString()
    };

    // If manual method, include additional settings
    if (method === 'manual') {
      if (monthlyAmount !== undefined) {
        updateData.preferred_monthly_contribution = monthlyAmount;
      }
      if (preferredDay !== undefined) {
        updateData.contribution_day = preferredDay;
      }
    }

    // Fetch profile first to get profile_id
    const { data: profile, error: profileErr } = await supabase
      .from('profiles')
      .select('id')
      .eq('user_id', userId)
      .single();

    if (profileErr) throw profileErr;
    if (!profile) {
      return res.status(404).json({
        success: false,
        error: 'Profile not found'
      });
    }

    // Update profile with contribution method
    const { data, error } = await supabase
      .from('profiles')
      .update(updateData)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) throw error;

    logger.info(`User ${userId} updated contribution method to ${method}`);

    res.json({
      success: true,
      contributionMethod: {
        method: data.contribution_method,
        monthlyAmount: data.preferred_monthly_contribution || null,
        preferredDay: data.contribution_day || null
      },
      message: method === 'manual' 
        ? 'Manual contribution method saved' 
        : 'Payroll deduction request submitted'
    });
  } catch (error) {
    logger.error('Update contribution method error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/v1/user/contribution-method
 * Get user's current contribution method
 */
router.get('/contribution-method', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('contribution_method, preferred_monthly_contribution, contribution_day')
      .eq('user_id', req.user.userId)
      .single();

    if (error && error.code !== 'PGRST116') throw error;

    res.json({
      success: true,
      contributionMethod: {
        method: data?.contribution_method || 'manual',
        monthlyAmount: data?.preferred_monthly_contribution || 5000,
        preferredDay: data?.contribution_day || 5
      }
    });
  } catch (error) {
    logger.error('Get contribution method error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
