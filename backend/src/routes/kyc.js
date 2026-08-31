/**
 * KYC Routes
 *
 * Persists KYC state into Supabase tables `kyc` (one row per profile) and
 * `kyc_documents` (N uploaded documents per profile).
 */

const express = require('express');
const { body } = require('express-validator');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/auth');
const validate = require('../middleware/validate');
const logger = require('../utils/logger');
const { ageInYears, MIN_AGE_YEARS } = require('../services/registrationMerge');

// In-memory file upload (10 MB max) — the file is streamed straight into
// Supabase Storage, never touching the disk.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
});

router.use(authenticate);

async function getOrCreateKyc(profileId) {
  const { data, error } = await supabase
    .from('kyc')
    .select('*')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (error) throw error;
  if (data) return data;

  const { data: created, error: cErr } = await supabase
    .from('kyc')
    .insert({ profile_id: profileId, status: 'pending' })
    .select('*')
    .single();
  if (cErr) throw cErr;
  return created;
}

/**
 * GET /api/v1/kyc/status
 */
router.get('/status', async (req, res) => {
  try {
    const kyc = await getOrCreateKyc(req.user.id);
    res.json({ success: true, kyc });
  } catch (err) {
    logger.error('kyc status error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/kyc/submit
 */
router.post(
  '/submit',
  [
    body('personalInfo').isObject(),
    body('address').optional().isObject(),
    body('employmentInfo').optional().isObject(),
  ],
  validate,
  async (req, res) => {
    try {
      const { personalInfo, address, employmentInfo, bankInfo, bvn, nin } = req.body;
      const kyc = await getOrCreateKyc(req.user.id);

      // Merge new structured fields into the existing JSONB blocks so partial
      // submits (e.g. bank-only updates) don't wipe previously saved data.
      const mergedPersonal = {
        ...(kyc.personal_info || {}),
        ...(personalInfo || {}),
      };
      const mergedEmployment = {
        ...(kyc.employment_info || {}),
        ...(employmentInfo || {}),
      };
      const mergedBank = {
        ...(kyc.bank_info || {}),
        ...(bankInfo || {}),
      };

      // Adults only: reject KYC submissions whose date of birth is under 18.
      // Checked against the merged record so previously saved DOBs are gated
      // too, not just the one in this request.
      const dob = mergedPersonal.date_of_birth || kyc.date_of_birth;
      if (dob) {
        const age = ageInYears(dob);
        if (age !== null && age < MIN_AGE_YEARS) {
          return res.status(422).json({
            success: false,
            message: `You must be at least ${MIN_AGE_YEARS} years old to register on Coopvest.`,
          });
        }
      }

      const { data, error } = await supabase
        .from('kyc')
        .update({
          personal_info: mergedPersonal,
          address: address || kyc.address,
          employment_info: mergedEmployment,
          bank_info: mergedBank,
          bvn: bvn || kyc.bvn || (bankInfo && bankInfo.bvn) || null,
          nin: nin || kyc.nin || null,
          status: 'submitted',
          submitted_at: new Date().toISOString(),
        })
        .eq('id', kyc.id)
        .select('*')
        .single();
      if (error) throw error;
      res.json({ success: true, kyc: data });
    } catch (err) {
      logger.error('kyc submit error:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

/**
 * POST /api/v1/kyc/upload
 *
 * Multipart upload for a single KYC image. Field `file` carries the image
 * and `type` is one of: `selfie`, `id_document` (optionally `side=back`).
 *
 * The file is stored in the private `kyc-documents` Supabase Storage bucket
 * under `kyc/{userId}/{type}-{timestamp}.{ext}`. Because the bucket is private,
 * we return a long-lived signed URL (10 years) so the image is viewable from
 * the app/admin without making the bucket public. The service role key used by
 * the backend bypasses RLS, so no storage policies are required to write.
 *
 * - `selfie`         → updates the `kyc.selfie` JSONB column { url, uploaded_at }
 * - `id_document`    → inserts a `kyc_documents` row (front_image_url or
 *                      back_image_url when `side=back`).
 *
 * Returns: { success: true, url, path, type }
 */
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No file uploaded (field name must be "file").' });
    }
    const type = (req.body.type || '').toString();
    if (!['selfie', 'id_document'].includes(type)) {
      return res.status(400).json({ success: false, error: "type must be 'selfie' or 'id_document'." });
    }
    // kyc_documents.type CHECK only allows: national_id, passport, drivers_license,
    // voters_card, utility_bill, bank_statement. 'id_document' from the app would
    // violate the constraint, so map it to 'national_id' (a generic national ID).
    const side = (req.body.side || 'front').toString() === 'back' ? 'back' : 'front';

    const ext = (req.file.originalname.split('.').pop() || 'jpg').toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp', 'heic'].includes(ext)) {
      return res.status(400).json({ success: false, error: 'Only JPG, PNG, WEBP or HEIC images are allowed.' });
    }

    const storagePath = `kyc/${req.user.id}/${type}-${Date.now()}-${uuidv4()}.${ext}`;
    const { error: uploadError } = await supabase.storage
      .from('kyc-documents')
      .upload(storagePath, req.file.buffer, {
        contentType: req.file.mimetype || `image/${ext === 'jpg' ? 'jpeg' : ext}`,
        upsert: false,
      });
    if (uploadError) throw uploadError;

    // Signed URL (10 years) so the private object is viewable by the app/admin.
    let url;
    try {
      const { data: signed, error: signedErr } = await supabase.storage
        .from('kyc-documents')
        .createSignedUrl(storagePath, 60 * 60 * 24 * 365 * 10);
      if (signedErr) throw signedErr;
      url = signed.signedUrl;
    } catch (e) {
      logger.warn('kyc upload: signed URL failed, using public URL:', e.message || e);
      const { data: { publicUrl } } = supabase.storage.from('kyc-documents').getPublicUrl(storagePath);
      url = publicUrl;
    }

    const kyc = await getOrCreateKyc(req.user.id);

    if (type === 'selfie') {
      // The `selfie` column is JSONB. Persist the URL + metadata there. The old
      // code wrote to a non-existent `selfie_url` column, which silently failed
      // and is why selfies were never saved.
      const { error: updErr } = await supabase
        .from('kyc')
        .update({ selfie: { url, path: storagePath, uploaded_at: new Date().toISOString() } })
        .eq('id', kyc.id);
      if (updErr) throw updErr;
    } else {
      // id_document → kyc_documents row on the correct side column. The table
      // has no `url`/`meta` columns — using them caused "could not find the
      // column" errors.
      const sideKey = side === 'back' ? 'back_image_url' : 'front_image_url';
      const { error: docErr } = await supabase
        .from('kyc_documents')
        .insert({ kyc_id: kyc.id, profile_id: req.user.id, type: type === 'id_document' ? 'national_id' : type, [sideKey]: url });
      if (docErr) throw docErr;
    }

    logger.info(`KYC ${type} uploaded for user ${req.user.id}: ${storagePath}`);
    res.status(201).json({ success: true, url, path: storagePath, type });
  } catch (err) {
    logger.error('kyc upload error:', err);
    res.status(500).json({ success: false, error: err.message || 'Upload failed.' });
  }
});

/**
 * POST /api/v1/kyc/document
 *
 * Registers a previously-uploaded image URL against the KYC record. Kept for
 * backwards compatibility — prefer POST /kyc/upload which uploads + registers
 * in one step and writes to the correct columns.
 */
router.post('/document', async (req, res) => {
  try {
    const { type, url, side } = req.body || {};
    if (!type || !url) {
      return res.status(400).json({ success: false, error: 'type and url are required' });
    }
    const kyc = await getOrCreateKyc(req.user.id);
    // The table has no `url`/`meta` columns. Store on front_image_url (or
    // back_image_url when side=back).
    const sideKey = side === 'back' ? 'back_image_url' : 'front_image_url';
    const { data, error } = await supabase
      .from('kyc_documents')
      .insert({ kyc_id: kyc.id, profile_id: req.user.id, type, [sideKey]: url })
      .select('*')
      .single();
    if (error) throw error;
    res.status(201).json({ success: true, document: data });
  } catch (err) {
    logger.error('kyc document error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/kyc/selfie
 *
 * Registers a previously-uploaded selfie URL. Kept for backwards
 * compatibility — prefer POST /kyc/upload (type=selfie). Writes to the
 * `selfie` JSONB column (the table has no `selfie_url` column, so the old
 * code silently failed to save selfies).
 */
router.post('/selfie', async (req, res) => {
  try {
    const { url } = req.body || {};
    if (!url) return res.status(400).json({ success: false, error: 'url is required' });
    const kyc = await getOrCreateKyc(req.user.id);
    const { data, error } = await supabase
      .from('kyc')
      .update({ selfie: { url, uploaded_at: new Date().toISOString() } })
      .eq('id', kyc.id)
      .select('*')
      .single();
    if (error) throw error;
    res.json({ success: true, kyc: data });
  } catch (err) {
    logger.error('kyc selfie error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/kyc/documents
 */
router.get('/documents', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('kyc_documents')
      .select('*')
      .eq('profile_id', req.user.id)
      .order('created_at', { ascending: false });
    if (error) throw error;
    res.json({ success: true, documents: data || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * PUT /api/v1/kyc/bank
 */
router.put(
  '/bank',
  [body('bankName').isString(), body('accountNumber').isString(), body('accountName').isString()],
  validate,
  async (req, res) => {
    try {
      const { bankName, accountNumber, accountName } = req.body;
      const kyc = await getOrCreateKyc(req.user.id);
      const { data, error } = await supabase
        .from('kyc')
        .update({
          bank_info: { bankName, accountNumber, accountName },
        })
        .eq('id', kyc.id)
        .select('*')
        .single();
      if (error) throw error;
      res.json({ success: true, kyc: data });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

module.exports = router;
