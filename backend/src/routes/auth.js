/**
 * Auth Routes
 *
 * All authentication endpoints — Supabase-backed.
 * Response shapes are aligned with the Flutter AuthResponse.fromJson contract:
 *   { token, refresh_token, user: { userId, id, email, name, phone, ... }, expires_at }
 */

const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const supabase = require('../config/supabase');
const { authenticate, decodeSessionId } = require('../middleware/auth');
const logger = require('../utils/logger');
const {
  hasValue,
  buildRegistrationCandidates,
  mergeStoredPersonalInfo,
  ageInYears,
  MIN_AGE_YEARS,
} = require('../services/registrationMerge');

const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  next();
};

/**
 * Build the user object returned to the Flutter app.
 * Merges Supabase auth.user metadata with the public.profiles row.
 */
const buildUserPayload = (authUser, profile) => {
  const kycApproved = profile?.kyc_verified === true;
  const feePaid = profile?.registration_fee_paid === true;
  const blocked = profile?.is_active === false ||
    profile?.membership_status === 'terminated';
  return {
    userId: profile?.user_id || authUser.user_metadata?.userId || authUser.id,
    id: authUser.id,
    email: authUser.email,
    name: profile?.name || authUser.user_metadata?.name || '',
    phone: profile?.phone || authUser.user_metadata?.phone || null,
    role: profile?.role || authUser.user_metadata?.role || 'member',
    kycStatus: kycApproved ? 'approved' : 'pending',
    registration_fee_paid: feePaid,
    membershipStatus: profile?.is_active === false ? 'inactive' : 'active',
    emailVerified: authUser.email_confirmed_at ? true : false,
    registration_completed: profile?.registration_completed === true,
    created_at: profile?.created_at || authUser.created_at,
    updated_at: profile?.updated_at || authUser.updated_at || authUser.created_at,
    // Machine-readable membership activation gate (mirrors /auth/me) so the
    // Flutter AuthGuard can route to the correct onboarding step.
    activation_gate: {
      activated: kycApproved && feePaid && !blocked,
      kyc_approved: kycApproved,
      registration_fee_paid: feePaid,
      blocked,
    },
  };
};

/**
 * Build a standardised success response that AuthResponse.fromJson can parse.
 */
const buildAuthResponse = (session, userPayload) => ({
  success: true,
  token: session.access_token,
  refresh_token: session.refresh_token,
  expires_at: session.expires_at
    ? new Date(session.expires_at * 1000).toISOString()
    : new Date(Date.now() + 3600 * 1000).toISOString(),
  user: userPayload,
});

/**
 * Ensure a profile row exists for a Supabase auth user.
 * Creates one if missing (idempotent via ON CONFLICT DO NOTHING).
 */
const ensureProfile = async (authUser, extra = {}) => {
  const userId = extra.userId || `USR-${Date.now().toString(36).toUpperCase()}`;
  const { data: existing } = await supabase
    .from('profiles')
    .select('id, user_id, email, name, phone, role, kyc_verified, is_active, membership_status, registration_fee_paid, registration_completed, completed_at, created_at, updated_at')
    .eq('id', authUser.id)
    .maybeSingle();

  if (existing) return existing;

  const { data: created, error } = await supabase
    .from('profiles')
    .insert({
      id: authUser.id,
      user_id: userId,
      email: authUser.email,
      name: extra.name || authUser.user_metadata?.name || '',
      phone: extra.phone || authUser.user_metadata?.phone || null,
      role: 'member',
      is_active: true,
    })
    .select('id, user_id, email, name, phone, role, kyc_verified, is_active, membership_status, registration_fee_paid, registration_completed, completed_at, created_at, updated_at')
    .single();

  if (error) {
    logger.error('ensureProfile: insert failed:', error.message);
    return null;
  }
  return created;
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/register
// ─────────────────────────────────────────────────────────────────────────────
router.post('/register', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('name').notEmpty().withMessage('Name is required'),
  body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
], validate, async (req, res) => {
  try {
    const { email, phone, name, password, referralCode } = req.body;
    const userId = `USR-${Date.now().toString(36).toUpperCase()}`;

    const { data, error } = await supabase.auth.signUp({
      email: email.toLowerCase(),
      password,
      options: {
        data: { name, phone: phone || null, userId, role: 'member', referralCode: referralCode || null },
      },
    });

    if (error) {
      return res.status(400).json({ success: false, error: error.message });
    }

    const authUser = data.user;

    // Supabase may not have a DB trigger — always ensure the profile row exists.
    const profile = await ensureProfile(authUser, { userId, name, phone: phone || null });

    // If no session (email confirmation required), return minimal response.
    if (!data.session) {
      return res.status(201).json({
        success: true,
        requiresEmailVerification: true,
        message: 'Registration successful. Please check your email to verify your account.',
        user: buildUserPayload(authUser, profile),
        token: null,
        refresh_token: null,
      });
    }

    return res.status(201).json(buildAuthResponse(data.session, buildUserPayload(authUser, profile)));
  } catch (err) {
    logger.error('Registration error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/login
// ─────────────────────────────────────────────────────────────────────────────
router.post('/login', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
], validate, async (req, res) => {
  try {
    const { email, password } = req.body;

    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.toLowerCase(),
      password,
    });

    if (error) {
      return res.status(401).json({ success: false, error: 'Invalid email or password' });
    }

    const authUser = data.user;

    // Fetch profile (create if missing — handles legacy accounts)
    const profile = await ensureProfile(authUser, {
      name: authUser.user_metadata?.name,
      phone: authUser.user_metadata?.phone,
    });

    return res.json(buildAuthResponse(data.session, buildUserPayload(authUser, profile)));
  } catch (err) {
    logger.error('Login error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/refresh
// ─────────────────────────────────────────────────────────────────────────────
router.post('/refresh', [
  body('refresh_token').notEmpty().withMessage('refresh_token is required'),
], validate, async (req, res) => {
  try {
    const { refresh_token } = req.body;

    const { data, error } = await supabase.auth.refreshSession({ refresh_token });
    if (error || !data.session) {
      return res.status(401).json({ success: false, error: 'Invalid or expired refresh token' });
    }

    const authUser = data.user;
    const { data: profile } = await supabase
      .from('profiles')
      .select('id, user_id, email, name, phone, role, kyc_verified, is_active, membership_status, registration_fee_paid, created_at, updated_at')
      .eq('id', authUser.id)
      .maybeSingle();

    return res.json(buildAuthResponse(data.session, buildUserPayload(authUser, profile)));
  } catch (err) {
    logger.error('Refresh token error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/google
// ─────────────────────────────────────────────────────────────────────────────
router.post('/google', [
  body('idToken').notEmpty().withMessage('idToken is required'),
], validate, async (req, res) => {
  try {
    const { idToken } = req.body;

    const { data, error } = await supabase.auth.signInWithIdToken({
      provider: 'google',
      token: idToken,
    });

    if (error || !data.session) {
      return res.status(401).json({ success: false, error: error?.message || 'Google sign-in failed' });
    }

    const authUser = data.user;
    const profile = await ensureProfile(authUser, {
      name: authUser.user_metadata?.full_name || authUser.user_metadata?.name,
      phone: authUser.user_metadata?.phone,
    });

    return res.json(buildAuthResponse(data.session, buildUserPayload(authUser, profile)));
  } catch (err) {
    logger.error('Google sign-in error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/salary-consent
// Records the user's salary deduction consent for loan access
// ─────────────────────────────────────────────────────────────────────────────
router.post('/salary-consent', [
  body('memberId').notEmpty().withMessage('Member ID is required'),
  body('consent').isBoolean().withMessage('Consent must be a boolean'),
], validate, async (req, res) => {
  try {
    const { memberId, consent, timestamp } = req.body;

    // Upsert the consent record into the profiles table
    const { data, error } = await supabase
      .from('profiles')
      .update({
        salary_deduction_consent: consent,
        salary_deduction_consent_date: timestamp || new Date().toISOString(),
      })
      .eq('user_id', memberId)
      .select()
      .single();

    if (error) {
      // If memberId doesnt match user_id, try matching by id
      const { data: retryData, error: retryError } = await supabase
        .from('profiles')
        .update({
          salary_deduction_consent: consent,
          salary_deduction_consent_date: timestamp || new Date().toISOString(),
        })
        .eq('id', memberId)
        .select()
        .single();

      if (retryError) {
        logger.error('Salary consent update error:', retryError.message);
        return res.status(400).json({ success: false, error: 'Failed to record consent. Member not found.' });
      }

      return res.json({
        success: true,
        message: 'Salary deduction consent recorded successfully',
        data: retryData,
      });
    }

    return res.json({
      success: true,
      message: 'Salary deduction consent recorded successfully',
      data,
    });
  } catch (err) {
    logger.error('Salary consent error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Shared helper — defines which fields are required vs optional across the
// complete-registration flow. Used by status, profile-completeness, and the
// POST endpoint so all three stay in sync.
// ─────────────────────────────────────────────────────────────────────────────
const REGISTRATION_FIELDS = {
  personal: {
    required: ['gender', 'date_of_birth', 'address', 'state', 'monthly_amount'],
    optional: ['lga', 'contribution_method', 'preferred_payment_day'],
  },
  employment: {
    required: ['occupation', 'employer_name', 'employment_type'],
    optional: ['employer_staff_id', 'work_address', 'years_of_employment', 'staff_id'],
  },
  nextOfKin: {
    required: ['nok_name', 'nok_relationship', 'nok_phone'],
    optional: ['nok_address'],
  },
  identity: {
    required: [],
    optional: ['id_type', 'id_number'],
  },
};

function checkCompletion(personal_info, employment_info) {
  const p = personal_info || {};
  const e = employment_info || {};

  const sections = {
    personal: {
      missing: REGISTRATION_FIELDS.personal.required.filter((f) => !hasValue(p[f])),
      filled: REGISTRATION_FIELDS.personal.required.filter((f) => hasValue(p[f])).length,
      total: REGISTRATION_FIELDS.personal.required.length,
    },
    employment: {
      missing: REGISTRATION_FIELDS.employment.required.filter((f) => !hasValue(e[f])),
      filled: REGISTRATION_FIELDS.employment.required.filter((f) => hasValue(e[f])).length,
      total: REGISTRATION_FIELDS.employment.required.length,
    },
    nextOfKin: {
      missing: REGISTRATION_FIELDS.nextOfKin.required.filter((f) => !hasValue(p[f])),
      filled: REGISTRATION_FIELDS.nextOfKin.required.filter((f) => hasValue(p[f])).length,
      total: REGISTRATION_FIELDS.nextOfKin.required.length,
    },
  };

  const totalRequired = Object.values(sections).reduce((s, sec) => s + sec.total, 0);
  const totalFilled = Object.values(sections).reduce((s, sec) => s + sec.filled, 0);
  const allRequiredMissing = Object.values(sections).flatMap((sec) => sec.missing);

  return {
    sections,
    totalRequired,
    totalFilled,
    completionPercentage: totalRequired === 0 ? 100 : Math.round((totalFilled / totalRequired) * 100),
    isComplete: allRequiredMissing.length === 0,
    missingRequiredFields: allRequiredMissing,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/complete-registration/status
// Returns whether the authenticated user has already completed onboarding.
// The Flutter app calls this on screen load to skip the flow for returning users.
// FIX: now checks that required fields actually have real values, not just
// that the JSON object exists (previously any partial save marked users done).
// ─────────────────────────────────────────────────────────────────────────────
router.get('/complete-registration/status', authenticate, async (req, res) => {
  try {
    const { data: kycRow, error } = await supabase
      .from('kyc')
      .select('national_id, date_of_birth, address, personal_info, employment_info')
      .eq('profile_id', req.user.id)
      .maybeSingle();

    if (error) throw error;

    // date_of_birth lives both in its own column and (historically) inside
    // personal_info; merge it so a completed DOB is never reported missing.
    const { isComplete, completionPercentage, missingRequiredFields } = kycRow
      ? checkCompletion(mergeStoredPersonalInfo(kycRow), kycRow.employment_info)
      : { isComplete: false, completionPercentage: 0, missingRequiredFields: [] };

    return res.json({
      success: true,
      completed: isComplete,
      completionPercentage,
      missingRequiredFields,
    });
  } catch (err) {
    logger.error('complete-registration/status error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/complete-registration
// Saves onboarding data collected after email verification.
// Called by the Flutter registration_onboarding_screen on the final step.
// Also reachable via the /api/auth/complete-registration compat alias in server.js.
//
// Accepts an optional `partial: true` flag for intermediate step saves.
// Without it, all required fields must be present or the request is rejected
// with a 422 listing exactly which fields are missing.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/complete-registration', authenticate, async (req, res) => {
  try {
    const {
      gender, date_of_birth, address, state, lga,
      occupation, employer_name, employment_type,
      employer_staff_id, work_address, years_of_employment,
      monthly_amount, contribution_method, preferred_payment_day,
      nok_name, nok_relationship, nok_phone, nok_address,
      id_type, id_number, staff_id,
      // Bank info fields
      bank_name, bank_code, account_number, account_name, account_type,
      partial,
    } = req.body;

    // Fetch the existing KYC row once. The body is merged over it for both
    // validation and the write, so a member resuming an earlier save never
    // has already-completed fields reported missing nor wiped by the upsert.
    const { data: existingKyc } = await supabase
      .from('kyc')
      .select('national_id, date_of_birth, address, personal_info, employment_info')
      .eq('profile_id', req.user.id)
      .maybeSingle();

    const { personal_info: personal_info_candidate, employment_info: employment_info_candidate } =
      buildRegistrationCandidates(req.body, existingKyc);

    // Age gate: Coopvest membership is adults only. Runs on every save
    // (partial included) and uses the merged DOB so a resume is checked too.
    // An unparseable or missing DOB is left to the completeness check below.
    if (hasValue(personal_info_candidate.date_of_birth)) {
      const age = ageInYears(personal_info_candidate.date_of_birth);
      if (age !== null && age < MIN_AGE_YEARS) {
        return res.status(422).json({
          success: false,
          message: `You must be at least ${MIN_AGE_YEARS} years old to register on Coopvest.`,
        });
      }
    }

    if (!partial) {
      const { isComplete, missingRequiredFields } = checkCompletion(
        personal_info_candidate,
        employment_info_candidate
      );

      if (!isComplete) {
        return res.status(422).json({
          success: false,
          message: 'Please fill in all required fields before completing registration.',
          missingRequiredFields,
          hint: 'Send partial:true to save progress without completing registration.',
        });
      }
    }

    // 1. Update the profiles row with employer/dept info. When this isn't a
    //    partial save, the member has completed onboarding — set the
    //    registration_completed flag so the mobile app no longer re-prompts
    //    the registration flow on every launch.
    const now = new Date().toISOString();
    const { error: profileError } = await supabase
      .from('profiles')
      .update({
        department: employer_name || null,
        updated_at: now,
        ...(partial
          ? {}
          : { registration_completed: true, completed_at: now }),
      })
      .eq('id', req.user.id);

    if (profileError) {
      logger.error('complete-registration: profile update failed:', profileError.message);
      return res.status(500).json({ success: false, error: profileError.message });
    }

    // 2. Upsert KYC row — merged over the existing row so a partial resubmit
    //    never wipes fields the member already completed. personal_info holds
    //    everything that doesn't have its own top-level column; bank fields
    //    merge from the existing row when absent from the body.
    const existingPersonal = existingKyc?.personal_info || {};
    const bankFields = {
      bank_name, bank_code, account_number, account_name, account_type,
    };
    const mergedBank = Object.fromEntries(
      Object.entries(bankFields).map(([k, v]) => [k, hasValue(v) ? v : existingPersonal[k]])
    );

    const { error: kycError } = await supabase
      .from('kyc')
      .upsert(
        {
          profile_id: req.user.id,
          national_id: hasValue(id_number) ? id_number : (existingKyc?.national_id || null),
          date_of_birth: personal_info_candidate.date_of_birth || null,
          address: hasValue(address) ? address : (existingKyc?.address || null),
          personal_info: {
            ...existingPersonal,
            gender: personal_info_candidate.gender,
            state: personal_info_candidate.state,
            lga: personal_info_candidate.lga,
            staff_id: personal_info_candidate.staff_id,
            id_type: personal_info_candidate.id_type,
            nok_name: personal_info_candidate.nok_name,
            nok_relationship: personal_info_candidate.nok_relationship,
            nok_phone: personal_info_candidate.nok_phone,
            nok_address: personal_info_candidate.nok_address,
            monthly_amount: personal_info_candidate.monthly_amount,
            contribution_method: personal_info_candidate.contribution_method,
            preferred_payment_day: personal_info_candidate.preferred_payment_day,
            ...mergedBank,
          },
          employment_info: {
            ...(existingKyc?.employment_info || {}),
            occupation: employment_info_candidate.occupation,
            employer_name: employment_info_candidate.employer_name,
            employment_type: employment_info_candidate.employment_type,
            employer_staff_id: employment_info_candidate.employer_staff_id,
            work_address: employment_info_candidate.work_address,
            years_of_employment: employment_info_candidate.years_of_employment,
          },
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'profile_id' }
      );

    if (kycError) {
      logger.error('complete-registration: kyc upsert failed:', kycError.message);
      return res.status(500).json({ success: false, error: kycError.message });
    }

    return res.status(200).json({
      success: true,
      message: partial
        ? 'Progress saved. Complete the remaining required fields to finish registration.'
        : 'Registration details saved.',
      partial: !!partial,
    });
  } catch (err) {
    logger.error('complete-registration error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/profile-completeness
// Returns a per-section breakdown of how complete the user's profile is.
// Flutter app uses this to show nudge banners and a "Complete your profile" prompt.
// Response shape:
//   {
//     completionPercentage: 45,
//     isComplete: false,
//     sections: {
//       personal:    { filled: 2, total: 5, missing: ['gender','state','monthly_amount'] },
//       employment:  { filled: 3, total: 3, missing: [] },
//       nextOfKin:   { filled: 1, total: 3, missing: ['nok_relationship','nok_phone'] },
//     },
//     missingRequiredFields: ['gender','state','monthly_amount','nok_relationship','nok_phone'],
//   }
// ─────────────────────────────────────────────────────────────────────────────
router.get('/profile-completeness', authenticate, async (req, res) => {
  try {
    const { data: kycRow, error } = await supabase
      .from('kyc')
      .select('date_of_birth, address, personal_info, employment_info')
      .eq('profile_id', req.user.id)
      .maybeSingle();

    if (error) throw error;

    const result = checkCompletion(
      mergeStoredPersonalInfo(kycRow),
      kycRow?.employment_info || {}
    );

    return res.json({ success: true, ...result });
  } catch (err) {
    logger.error('profile-completeness error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/sync
// Called by the Flutter app after Supabase sign-in to upsert the profile row
// and return the latest user payload. Returns { success, user, token }.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/sync', (req, res, next) => { req.skipSingleSessionCheck = true; next(); }, authenticate, async (req, res) => {
  try {
    const { name, phone } = req.body;
    const profileId = req.user.id;

    const updateData = { updated_at: new Date().toISOString() };
    if (name) updateData.name = name;
    if (phone) updateData.phone = phone;

    // Single-device login: this is the endpoint the app hits right after a
    // fresh sign-in, so claim the active session here. Any other device still
    // holding a token from an older session gets signed out by the auth
    // middleware on its next request.
    const sessionId = decodeSessionId(req.token);
    if (sessionId) updateData.active_session_id = sessionId;

    const { data: profile, error } = await supabase
      .from('profiles')
      .update(updateData)
      .eq('id', profileId)
      .select('id, user_id, email, name, phone, role, kyc_verified, is_active, membership_status, registration_fee_paid, created_at, updated_at')
      .maybeSingle();

    if (error) {
      logger.error('auth/sync: profile update failed:', error.message);
      return res.status(500).json({ success: false, error: error.message });
    }

    const userPayload = {
      userId: profile?.user_id || req.user.userId,
      id: profileId,
      email: profile?.email || req.user.email,
      name: profile?.name || req.user.name || '',
      phone: profile?.phone || null,
      role: profile?.role || req.user.role || 'member',
      kycStatus: profile?.kyc_verified ? 'approved' : 'pending',
      membershipStatus: profile?.is_active === false ? 'inactive' : 'active',
      emailVerified: true,
      created_at: profile?.created_at,
      updated_at: profile?.updated_at,
    };

    return res.json({ success: true, user: userPayload, token: req.token });
  } catch (err) {
    logger.error('auth/sync error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/logout
// ─────────────────────────────────────────────────────────────────────────────
router.post('/logout', authenticate, async (req, res) => {
  try {
    await supabase.auth.admin.signOut(req.token);
  } catch (err) {
    logger.warn('Admin signOut error (non-fatal):', err.message);
  }
  return res.json({ success: true, message: 'Logged out successfully' });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/me  (also /profile)
// ─────────────────────────────────────────────────────────────────────────────
router.get(['/me', '/profile'], authenticate, async (req, res) => {
  try {
    // req.user is populated by the authenticate middleware from public.profiles
    const user = {
      userId: req.user.userId,
      id: req.user.id,
      email: req.user.email,
      name: req.user.name,
      role: req.user.role,
    };

    // Enrich with full profile data
    const { data: profile } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', req.user.id)
      .maybeSingle();

    if (profile) {
      const kycApproved = profile.kyc_verified === true;
      const feePaid = profile.registration_fee_paid === true;
      const blocked = profile.is_active === false ||
        profile.membership_status === 'terminated';
      Object.assign(user, {
        phone: profile.phone,
        kycStatus: kycApproved ? 'approved' : 'pending',
        registration_fee_paid: feePaid,
        membershipStatus: profile.is_active === false ? 'inactive' : 'active',
        created_at: profile.created_at,
        updated_at: profile.updated_at,
        // Mobile AuthGate gate registration on this flag; expose it so
        // returning users who completed onboarding aren't re-prompted.
        registration_completed: profile.registration_completed === true,
        completed_at: profile.completed_at || null,
        // Machine-readable membership activation gate so the app can render
        // the correct onboarding step (KYC vs registration fee) without
        // trusting a client-only check.
        activation_gate: {
          activated: kycApproved && feePaid && !blocked,
          kyc_approved: kycApproved,
          registration_fee_paid: feePaid,
          blocked,
        },
      });
    }

    return res.json({ success: true, user });
  } catch (err) {
    logger.error('Get profile error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/verify-email
// ─────────────────────────────────────────────────────────────────────────────
router.post('/verify-email', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('code').notEmpty().withMessage('Verification code is required'),
], validate, async (req, res) => {
  try {
    const { email, code } = req.body;

    const { data, error } = await supabase.auth.verifyOtp({
      email: email.toLowerCase(),
      token: code,
      type: 'email',
    });

    if (error) {
      return res.status(400).json({ success: false, error: error.message });
    }

    return res.json({ success: true, message: 'Email verified successfully', session: data.session });
  } catch (err) {
    logger.error('Verify email error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/resend-verification
// ─────────────────────────────────────────────────────────────────────────────
router.post('/resend-verification', [
  body('email').isEmail().withMessage('Valid email is required'),
], validate, async (req, res) => {
  try {
    const { email } = req.body;

    const { error } = await supabase.auth.resend({
      type: 'signup',
      email: email.toLowerCase(),
    });

    if (error) {
      return res.status(400).json({ success: false, error: error.message });
    }

    return res.json({ success: true, message: 'Verification email resent' });
  } catch (err) {
    logger.error('Resend verification error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/request-password-reset
// ─────────────────────────────────────────────────────────────────────────────
router.post('/request-password-reset', [
  body('email').isEmail().withMessage('Valid email is required'),
], validate, async (req, res) => {
  try {
    const { email } = req.body;

    const { error } = await supabase.auth.resetPasswordForEmail(email.toLowerCase(), {
      redirectTo: process.env.PASSWORD_RESET_REDIRECT_URL || 'https://coopvest.africa/reset-password',
    });

    // Always return success — never reveal whether the email is registered (prevents enumeration).
    // Log SMTP failures internally so they can be diagnosed without leaking info to the client.
    if (error) {
      logger.warn('Password reset email failed (SMTP/config issue):', error.message);
    }

    return res.json({ success: true, message: 'If that email is registered, a reset link has been sent.' });
  } catch (err) {
    logger.error('Request password reset error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/reset-password
// Verifies the OTP from the reset email and sets the new password.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/reset-password', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('code').notEmpty().withMessage('Reset code is required'),
  body('new_password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
], validate, async (req, res) => {
  try {
    const { email, code, new_password } = req.body;

    // Verify OTP first to get a session
    const { data: verifyData, error: verifyError } = await supabase.auth.verifyOtp({
      email: email.toLowerCase(),
      token: code,
      type: 'recovery',
    });

    if (verifyError || !verifyData.session) {
      return res.status(400).json({ success: false, error: verifyError?.message || 'Invalid reset code' });
    }

    // Update the password using the session obtained from verifyOtp
    const userSupabase = supabase; // service role can update directly
    const { error: updateError } = await supabase.auth.admin.updateUserById(verifyData.user.id, {
      password: new_password,
    });

    if (updateError) {
      return res.status(400).json({ success: false, error: updateError.message });
    }

    return res.json({ success: true, message: 'Password reset successfully. Please log in with your new password.' });
  } catch (err) {
    logger.error('Reset password error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/change-password
// ─────────────────────────────────────────────────────────────────────────────
router.post('/change-password', authenticate, [
  body('current_password').notEmpty().withMessage('Current password is required'),
  body('new_password').isLength({ min: 8 }).withMessage('New password must be at least 8 characters'),
], validate, async (req, res) => {
  try {
    const { current_password, new_password } = req.body;

    // Re-authenticate to verify current password
    const { data: userData } = await supabase
      .from('profiles')
      .select('email')
      .eq('id', req.user.id)
      .single();

    const { error: verifyError } = await supabase.auth.signInWithPassword({
      email: userData.email,
      password: current_password,
    });

    if (verifyError) {
      return res.status(401).json({ success: false, error: 'Current password is incorrect' });
    }

    const { error: updateError } = await supabase.auth.admin.updateUserById(req.user.id, {
      password: new_password,
    });

    if (updateError) {
      return res.status(400).json({ success: false, error: updateError.message });
    }

    return res.json({ success: true, message: 'Password changed successfully' });
  } catch (err) {
    logger.error('Change password error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
