/**
 * KYC Admin API Routes
 * 
 * Comprehensive endpoints for KYC management in the Admin Dashboard.
 * These endpoints allow administrators to:
 * - View all member KYC details
 * - Verify or reject KYC submissions
 * - Manage identity documents
 * - View audit trails
 * - Suspend/reactivate accounts
 * - Request additional documents
 * - Add internal notes
 */

const express = require('express');
const { body, param, query } = require('express-validator');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate, requireAdmin } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');

// Use authenticate middleware to verify Supabase JWT
router.use(authenticate);

function paging(req) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 20));
  return { page, limit, from: (page - 1) * limit, to: page * limit - 1 };
}

async function logAdminAction(action, target, metadata = {}, req = null) {
  try {
    await supabase.from('audit_logs').insert({
      actor_id: null,
      actor_type: 'admin',
      action,
      resource: target?.model || null,
      resource_id: target?.id || null,
      target_profile_id: target?.profileId || null,
      details: { ...metadata, source: 'admin-web' },
      ip_address: req?.ip || null,
      user_agent: req?.get('user-agent') || null,
    });
  } catch (err) {
    logger.warn('audit_logs insert failed:', err.message);
  }
}

async function logMemberActivity(profileId, activityType, description, metadata = {}, actorId = null, req = null) {
  try {
    await supabase.from('member_activity_timeline').insert({
      profile_id: profileId,
      activity_type: activityType,
      description,
      metadata,
      actor_id: actorId,
      actor_type: 'admin',
      ip_address: req?.ip || null,
      device_info: req?.get('user-agent') || null,
    });
  } catch (err) {
    logger.warn('member_activity_timeline insert failed:', err.message);
  }
}

// ============================================================================
// KYC Management Endpoints
// ============================================================================

/**
 * GET /api/v2/admin/kyc/summary
 * Get KYC statistics summary
 */
router.get('/summary', async (req, res) => {
  try {
    const { data: total, count: totalCount } = await supabase
      .from('profiles')
      .select('id', { count: 'exact', head: true });

    const { data: verified } = await supabase
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('kyc_verified', true);

    const { data: pending } = await supabase
      .from('kyc')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'pending');

    const { data: rejected } = await supabase
      .from('kyc')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'rejected');

    const { data: inactive } = await supabase
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('is_active', false);

    res.json({
      success: true,
      summary: {
        total_members: totalCount || 0,
        kyc_verified: verified || 0,
        kyc_pending: pending || 0,
        kyc_rejected: rejected || 0,
        inactive_accounts: inactive || 0,
        verification_rate: totalCount > 0 ? Math.round((verified / totalCount) * 100) : 0
      }
    });
  } catch (err) {
    logger.error('kyc summary error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v2/admin/kyc/pending
 * List pending KYC submissions
 */
router.get('/pending', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    
    const { data, error, count } = await supabase
      .from('kyc')
      .select(`
        *,
        profile:profiles(id, user_id, name, email, phone, is_active, kyc_verified)
      `, { count: 'exact' })
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    res.json({
      success: true,
      pendingKyc: data || [],
      pagination: { page, limit, total: count || 0 }
    });
  } catch (err) {
    logger.error('pending kyc error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/kyc
 * List all KYC records with pagination and filters
 */
router.get('/', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('kyc')
      .select(`
        *,
        profile:profiles(id, user_id, name, email, phone, is_active, is_flagged)
      `, { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (req.query.status) q = q.eq('status', req.query.status);
    if (req.query.verified === 'true') q = q.eq('verified', true);
    if (req.query.verified === 'false') q = q.eq('verified', false);
    if (req.query.profileId) q = q.eq('profile_id', req.query.profileId);

    const { data, error, count } = await q;
    if (error) throw error;

    res.json({ 
      success: true, 
      kycRecords: data || [], 
      pagination: { page, limit, total: count || 0 } 
    });
  } catch (err) {
    logger.error('admin kyc list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/kyc/:profileId
 * Get complete KYC details for a specific member
 */
router.get('/:profileId', async (req, res) => {
  try {
    const { profileId } = req.params;

    // Get profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', profileId)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!profile) return res.status(404).json({ success: false, error: 'Member not found' });

    // Get KYC record
    const { data: kyc, error: kycError } = await supabase
      .from('kyc')
      .select('*')
      .eq('profile_id', profileId)
      .maybeSingle();
    if (kycError) throw kycError;

    // Get KYC documents
    const { data: kycDocuments, error: docsError } = await supabase
      .from('kyc_documents')
      .select('*')
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false });
    if (docsError) throw docsError;

    // Get member documents
    const { data: memberDocs, error: memberDocsError } = await supabase
      .from('member_documents')
      .select('*')
      .eq('profile_id', profileId)
      .order('uploaded_at', { ascending: false });
    if (memberDocsError) throw memberDocsError;

    // Get bank accounts
    const { data: bankAccounts, error: bankError } = await supabase
      .from('bank_accounts')
      .select('*')
      .eq('profile_id', profileId);
    if (bankError) throw bankError;

    // Get next of kin
    const { data: nextOfKin, error: nokError } = await supabase
      .from('next_of_kin')
      .select('*')
      .eq('profile_id', profileId)
      .maybeSingle();
    if (nokError) throw nokError;

    // Get admin notes
    const { data: adminNotes, error: notesError } = await supabase
      .from('admin_notes')
      .select('*, admin:profiles!admin_id(id, name, email)')
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false });
    if (notesError) throw notesError;

    // Get activity timeline
    const { data: timeline, error: timelineError } = await supabase
      .from('member_activity_timeline')
      .select('*')
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false })
      .limit(50);
    if (timelineError) throw timelineError;

    res.json({
      success: true,
      member: {
        ...profile,
        kyc: kyc || null,
        kycDocuments: kycDocuments || [],
        memberDocuments: memberDocs || [],
        bankAccounts: bankAccounts || [],
        nextOfKin: nextOfKin || null,
        adminNotes: adminNotes || [],
        activityTimeline: timeline || [],
      },
    });
  } catch (err) {
    logger.error('admin kyc detail error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/kyc/:profileId/verify
 * Verify KYC for a member
 */
router.post(
  '/:profileId/verify',
  [
    body('verificationLevel').optional().isInt({ min: 0, max: 3 }),
    body('notes').optional().isString(),
  ],
  validate,
  async (req, res) => {
    try {
      const { profileId } = req.params;
      const { verificationLevel = 1, notes } = req.body;

      // Update KYC status
      const { data: kyc, error: kycError } = await supabase
        .from('kyc')
        .update({
          status: 'verified',
          verified: true,
          verified_at: new Date().toISOString(),
          verification_level: verificationLevel,
          verification_notes: notes || null,
          reviewed_at: new Date().toISOString(),
        })
        .eq('profile_id', profileId)
        .select('*')
        .maybeSingle();
      if (kycError) throw kycError;
      if (!kyc) return res.status(404).json({ success: false, error: 'KYC record not found' });

      // Update profile KYC status
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .update({
          kyc_verified: true,
          kyc_verified_at: new Date().toISOString(),
        })
        .eq('id', profileId)
        .select('*')
        .maybeSingle();
      if (profileError) throw profileError;

      // Log admin action
      await logAdminAction('KYC_VERIFIED', { model: 'KYC', id: kyc.id, profileId }, { 
        verificationLevel, 
        notes 
      }, req);

      // Log member activity
      await logMemberActivity(profileId, 'kyc_verified', 'KYC verified by administrator', {
        verificationLevel,
        notes,
      }, null, req);

      res.json({ success: true, kyc, profile });
    } catch (err) {
      logger.error('admin kyc verify error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/admin/kyc/:profileId/reject
 * Reject KYC for a member
 */
router.post(
  '/:profileId/reject',
  [
    body('reason').isString().isLength({ min: 10, max: 1000 }),
    body('requestDocuments').optional().isBoolean(),
  ],
  validate,
  async (req, res) => {
    try {
      const { profileId } = req.params;
      const { reason, requestDocuments = false } = req.body;

      // Update KYC status
      const { data: kyc, error: kycError } = await supabase
        .from('kyc')
        .update({
          status: 'rejected',
          verified: false,
          rejection_reason: reason,
          reviewed_at: new Date().toISOString(),
        })
        .eq('profile_id', profileId)
        .select('*')
        .maybeSingle();
      if (kycError) throw kycError;

      // Update profile
      await supabase
        .from('profiles')
        .update({
          kyc_verified: false,
          kyc_rejection_reason: reason,
        })
        .eq('id', profileId);

      // Log admin action
      await logAdminAction('KYC_REJECTED', { model: 'KYC', id: kyc?.id, profileId }, { 
        reason,
        requestDocuments,
      }, req);

      // Log member activity
      await logMemberActivity(profileId, 'kyc_rejected', `KYC rejected: ${reason}`, {
        reason,
        requestDocuments,
      }, null, req);

      res.json({ success: true, kyc });
    } catch (err) {
      logger.error('admin kyc reject error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/admin/kyc/:profileId/documents/:documentId/verify
 * Verify a specific KYC document
 */
router.post(
  '/:profileId/documents/:documentId/verify',
  [body('notes').optional().isString()],
  validate,
  async (req, res) => {
    try {
      const { profileId, documentId } = req.params;
      const { notes } = req.body;

      const { data: doc, error } = await supabase
        .from('kyc_documents')
        .update({
          status: 'verified',
          verified_at: new Date().toISOString(),
          rejection_reason: null,
        })
        .eq('id', documentId)
        .eq('profile_id', profileId)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!doc) return res.status(404).json({ success: false, error: 'Document not found' });

      await logAdminAction('KYC_DOCUMENT_VERIFIED', { model: 'KycDocument', id: doc.id, profileId }, { notes }, req);
      await logMemberActivity(profileId, 'document_verified', `Document (${doc.type}) verified by administrator`, {}, null, req);

      res.json({ success: true, document: doc });
    } catch (err) {
      logger.error('admin document verify error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/admin/kyc/:profileId/documents/:documentId/reject
 * Reject a specific KYC document
 */
router.post(
  '/:profileId/documents/:documentId/reject',
  [body('reason').isString().isLength({ min: 5, max: 500 })],
  validate,
  async (req, res) => {
    try {
      const { profileId, documentId } = req.params;
      const { reason } = req.body;

      const { data: doc, error } = await supabase
        .from('kyc_documents')
        .update({
          status: 'rejected',
          rejection_reason: reason,
        })
        .eq('id', documentId)
        .eq('profile_id', profileId)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!doc) return res.status(404).json({ success: false, error: 'Document not found' });

      await logAdminAction('KYC_DOCUMENT_REJECTED', { model: 'KycDocument', id: doc.id, profileId }, { reason }, req);
      await logMemberActivity(profileId, 'document_rejected', `Document (${doc.type}) rejected: ${reason}`, { reason }, null, req);

      res.json({ success: true, document: doc });
    } catch (err) {
      logger.error('admin document reject error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ============================================================================
// Member Account Management
// ============================================================================

/**
 * POST /api/v1/admin/kyc/:profileId/suspend
 * Suspend a member account
 */
router.post(
  '/:profileId/suspend',
  [body('reason').isString().isLength({ min: 5, max: 500 })],
  validate,
  async (req, res) => {
    try {
      const { profileId } = req.params;
      const { reason } = req.body;

      const { data: profile, error } = await supabase
        .from('profiles')
        .update({
          is_active: false,
          is_flagged: true,
          flagged_reason: reason,
        })
        .eq('id', profileId)
        .select('*')
        .maybeSingle();
      if (error) throw error;
      if (!profile) return res.status(404).json({ success: false, error: 'Member not found' });

      await logAdminAction('MEMBER_SUSPENDED', { model: 'Profile', id: profileId, profileId }, { reason }, req);
      await logMemberActivity(profileId, 'account_suspended', `Account suspended: ${reason}`, { reason }, null, req);

      res.json({ success: true, profile });
    } catch (err) {
      logger.error('admin suspend error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/admin/kyc/:profileId/reactivate
 * Reactivate a suspended member account
 */
router.post('/:profileId/reactivate', async (req, res) => {
  try {
    const { profileId } = req.params;

    const { data: profile, error } = await supabase
      .from('profiles')
      .update({
        is_active: true,
        is_flagged: false,
        flagged_reason: null,
      })
      .eq('id', profileId)
      .select('*')
      .maybeSingle();
    if (error) throw error;
    if (!profile) return res.status(404).json({ success: false, error: 'Member not found' });

    await logAdminAction('MEMBER_REACTIVATED', { model: 'Profile', id: profileId, profileId }, {}, req);
    await logMemberActivity(profileId, 'account_reactivated', 'Account reactivated by administrator', {}, null, req);

    res.json({ success: true, profile });
  } catch (err) {
    logger.error('admin reactivate error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// Admin Notes Management
// ============================================================================

/**
 * GET /api/v1/admin/kyc/:profileId/notes
 * Get admin notes for a member
 */
router.get('/:profileId/notes', async (req, res) => {
  try {
    const { profileId } = req.params;

    const { data: notes, error } = await supabase
      .from('admin_notes')
      .select('*, admin:profiles!admin_id(id, name, email)')
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json({ success: true, notes: notes || [] });
  } catch (err) {
    logger.error('admin notes list error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/admin/kyc/:profileId/notes
 * Add an admin note for a member
 */
router.post(
  '/:profileId/notes',
  [body('note').isString().isLength({ min: 1, max: 5000 })],
  validate,
  async (req, res) => {
    try {
      const { profileId } = req.params;
      const { note } = req.body;

      const { data: adminNote, error } = await supabase
        .from('admin_notes')
        .insert({
          profile_id: profileId,
          note,
          admin_id: null, // Will be set via service token
        })
        .select('*')
        .maybeSingle();

      if (error) throw error;

      await logAdminAction('ADMIN_NOTE_ADDED', { model: 'AdminNote', id: adminNote.id, profileId }, { noteLength: note.length }, req);

      res.status(201).json({ success: true, note: adminNote });
    } catch (err) {
      logger.error('admin note add error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * DELETE /api/v1/admin/kyc/:profileId/notes/:noteId
 * Delete an admin note
 */
router.delete('/:profileId/notes/:noteId', async (req, res) => {
  try {
    const { profileId, noteId } = req.params;

    const { error } = await supabase
      .from('admin_notes')
      .delete()
      .eq('id', noteId)
      .eq('profile_id', profileId);

    if (error) throw error;

    await logAdminAction('ADMIN_NOTE_DELETED', { model: 'AdminNote', id: noteId, profileId }, {}, req);

    res.json({ success: true });
  } catch (err) {
    logger.error('admin note delete error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// Document Request Management
// ============================================================================

/**
 * POST /api/v1/admin/kyc/:profileId/documents/request
 * Request additional documents from a member
 */
router.post(
  '/:profileId/documents/request',
  [
    body('documentType').isString().isIn([
      'passport_photograph', 'signature', 'means_of_identification',
      'proof_of_address', 'employment_letter', 'payslip', 'utility_bill', 'bank_statement'
    ]),
    body('reason').optional().isString().isLength({ max: 500 }),
    body('expiresInDays').optional().isInt({ min: 1, max: 30 }).default(7),
  ],
  validate,
  async (req, res) => {
    try {
      const { profileId } = req.params;
      const { documentType, reason, expiresInDays = 7 } = req.body;

      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + expiresInDays);

      const { data: request, error } = await supabase
        .from('document_requests')
        .insert({
          profile_id: profileId,
          document_type: documentType,
          reason: reason || null,
          expires_at: expiresAt.toISOString(),
          status: 'pending',
        })
        .select('*')
        .maybeSingle();

      if (error) throw error;

      await logAdminAction('DOCUMENT_REQUESTED', { model: 'DocumentRequest', id: request.id, profileId }, {
        documentType,
        reason,
        expiresAt: expiresAt.toISOString(),
      }, req);

      await logMemberActivity(profileId, 'document_uploaded', `Additional document requested: ${documentType}`, {
        documentType,
        reason,
      }, null, req);

      res.status(201).json({ success: true, request });
    } catch (err) {
      logger.error('admin document request error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * GET /api/v1/admin/kyc/:profileId/documents/requests
 * Get pending document requests for a member
 */
router.get('/:profileId/documents/requests', async (req, res) => {
  try {
    const { profileId } = req.params;

    const { data: requests, error } = await supabase
      .from('document_requests')
      .select('*')
      .eq('profile_id', profileId)
      .order('requested_at', { ascending: false });

    if (error) throw error;
    res.json({ success: true, requests: requests || [] });
  } catch (err) {
    logger.error('admin document requests error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// Activity Timeline Management
// ============================================================================

/**
 * GET /api/v1/admin/kyc/:profileId/timeline
 * Get activity timeline for a member
 */
router.get('/:profileId/timeline', async (req, res) => {
  try {
    const { profileId } = req.params;
    const limit = Math.min(100, parseInt(req.query.limit, 10) || 50);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);

    const { data: timeline, error } = await supabase
      .from('member_activity_timeline')
      .select('*')
      .eq('profile_id', profileId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw error;
    res.json({ success: true, timeline: timeline || [] });
  } catch (err) {
    logger.error('admin timeline error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/admin/audit-logs
 * Get audit logs with filters
 */
router.get('/audit-logs', async (req, res) => {
  try {
    const { page, limit, from, to } = paging(req);
    let q = supabase
      .from('audit_logs')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (req.query.action) q = q.eq('action', req.query.action);
    if (req.query.resource) q = q.eq('resource', req.query.resource);
    if (req.query.targetProfileId) q = q.eq('target_profile_id', req.query.targetProfileId);
    if (req.query.startDate) q = q.gte('created_at', req.query.startDate);
    if (req.query.endDate) q = q.lte('created_at', req.query.endDate);

    const { data, error, count } = await q;
    if (error) throw error;

    res.json({ 
      success: true, 
      logs: data || [], 
      pagination: { page, limit, total: count || 0 } 
    });
  } catch (err) {
    logger.error('admin audit logs error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
