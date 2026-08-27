/**
 * Authentication Middleware
 *
 * Verifies every protected request by calling supabase.auth.getUser(token),
 * which validates the Supabase JWT server-side without a local secret.
 * On success it attaches the resolved profile to req.user.
 *
 * Exports:
 *   authenticate   — requires a valid Supabase JWT
 *   optionalAuth   — sets req.user if JWT is valid, else continues
 *   requireAdmin   — valid JWT + role in ('admin', 'superadmin', 'staff')
 *   requireService — valid x-service-token header
 */

const supabase = require('../config/supabase');
const logger = require('../utils/logger');

/**
 * Extract the Supabase session_id from an already-verified JWT payload.
 * Signature validation is done by supabase.auth.getUser, so a plain decode
 * of the payload segment is sufficient here.
 */
function decodeSessionId(token) {
  try {
    const payload = token.split('.')[1];
    if (!payload) return null;
    const json = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return json.session_id || null;
  } catch (_) {
    return null;
  }
}

/**
 * Verify a Supabase Bearer token and return the matching profile row.
 * Throws if the token is invalid or the profile is missing.
 */
async function verifyToken(token) {
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    throw new Error('Invalid or expired token');
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, user_id, email, name, role, is_active, is_flagged, active_session_id')
    .eq('id', user.id)
    .maybeSingle();

  if (profileError) {
    logger.error('Failed to fetch user profile:', profileError.message);
  }

  return { profile, supabaseUser: user };
}

const authenticate = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'Authentication required. Provide Bearer token in Authorization header.',
      });
    }

    const token = authHeader.split(' ')[1];

    let profile;
    let supabaseUser;
    
    try {
      const result = await verifyToken(token);
      profile = result.profile;
      supabaseUser = result.supabaseUser;
    } catch (err) {
      return res.status(401).json({ success: false, error: 'Invalid or expired token' });
    }

    // Auto-create profile if Supabase user exists but profile doesn't
    // This handles the case where a user signs up via Supabase but the profile
    // row hasn't been created yet
    if (!profile && supabaseUser) {
      logger.info(`Creating missing profile for user: ${supabaseUser.id}`);
      
      const userId = `USR-${Date.now().toString(36).toUpperCase()}`;
      const { data: newProfile, error: createError } = await supabase
        .from('profiles')
        .insert({
          id: supabaseUser.id,
          user_id: userId,
          email: supabaseUser.email,
          name: supabaseUser.user_metadata?.name || supabaseUser.email?.split('@').first || 'User',
          phone: supabaseUser.user_metadata?.phone || null,
          role: 'member',
        })
        .select('id, user_id, email, name, phone, role, is_active, is_flagged')
        .maybeSingle();
      
      if (createError) {
        logger.error('Failed to auto-create profile:', createError.message);
        return res.status(500).json({ success: false, error: 'Failed to create user profile' });
      }
      
      profile = newProfile;
    }

    if (!profile) {
      return res.status(401).json({ success: false, error: 'User profile not found' });
    }

    if (profile.is_active === false) {
      return res.status(403).json({ success: false, error: 'Account is disabled' });
    }

    // Single-device enforcement: /auth/sync claims profiles.active_session_id
    // on every fresh login, so a session claimed by a newer login on another
    // device no longer matches and gets signed out here. Profiles with no
    // claimed session yet (active_session_id IS NULL) are left alone.
    // The claim endpoint itself (/auth/sync) sets req.skipSingleSessionCheck
    // so a brand-new session can pass through and claim the session.
    const tokenSessionId = decodeSessionId(token);
    if (!req.skipSingleSessionCheck && profile.active_session_id && tokenSessionId && profile.active_session_id !== tokenSessionId) {
      return res.status(401).json({
        success: false,
        error: 'You have been signed in on another device. Please log in again.',
        code: 'SESSION_REPLACED',
      });
    }

    req.user = {
      id: profile.id,
      email: profile.email,
      userId: profile.user_id,
      name: profile.name,
      role: profile.role || 'member',
      isFlagged: profile.is_flagged === true,
    };

    req.token = token;
    next();
  } catch (error) {
    logger.error('Authentication error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) return next();

    const token = authHeader.split(' ')[1];

    let profile;
    try {
      const result = await verifyToken(token);
      profile = result.profile;
    } catch (_) {
      return next();
    }

    if (profile) {
      req.user = {
        id: profile.id,
        email: profile.email,
        userId: profile.user_id,
        name: profile.name,
        role: profile.role || 'member',
      };
      req.token = token;
    }
    next();
  } catch (_) {
    next();
  }
};

const requireAdmin = (req, res, next) => {
  return authenticate(req, res, () => {
    if (req.user && ['admin', 'superadmin', 'super_admin', 'staff'].includes(req.user.role)) {
      return next();
    }
    res.status(403).json({ success: false, error: 'Admin access required' });
  });
};

const requireService = (req, res, next) => {
  // Get the expected tokens from environment
  const serviceToken = process.env.MOBILE_API_SERVICE_TOKEN;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  
  // Check X-Service-Token header first (preferred method)
  const xServiceToken = req.headers['x-service-token'] || req.headers['X-Service-Token'];
  if (xServiceToken) {
    if ((serviceToken && xServiceToken === serviceToken) || (serviceRoleKey && xServiceToken === serviceRoleKey)) {
      req.service = { name: 'admin-web', role: 'service' };
      return next();
    }
  }
  
  // Check Authorization Bearer header
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const bearerToken = authHeader.split(' ')[1];
    if (bearerToken) {
      if ((serviceToken && bearerToken === serviceToken) || (serviceRoleKey && bearerToken === serviceRoleKey)) {
        req.service = { name: 'admin-web', role: 'service' };
        return next();
      }
    }
  }
  
  // No valid token found
  return res.status(401).json({ success: false, error: 'Invalid or missing service token' });
};

// Require a specific role (or set of roles). Super Admin always passes.
function requireRole(roles) {
  const allowed = Array.isArray(roles) ? roles : [roles];
  return (req, res, next) => {
    return authenticate(req, res, () => {
      if (!req.user) return res.status(401).json({ success: false, error: 'Not authenticated' });
      if (['superadmin', 'super_admin'].includes(req.user.role)) return next();
      if (allowed.includes(req.user.role)) return next();
      res.status(403).json({ success: false, error: 'Insufficient role' });
    });
  };
}

// Super Admin only — used for sensitive operations (emergency controls,
// approval decisions, policy changes).
const requireSuperAdmin = requireRole(['superadmin', 'super_admin']);

// ─────────────────────────────────────────────────────────────────────────────
// Membership activation gate
// ─────────────────────────────────────────────────────────────────────────────
// Gates full member dashboard access behind the onboarding funnel:
//
//   REGISTERED → PHONE/EMAIL VERIFIED → KYC APPROVED → REGISTRATION FEE PAID
//                                                                 → ACCOUNT ACTIVE
//
// Server-side enforcement only — never trust a client-side (Flutter) gate, a
// member could otherwise reach protected endpoints by manipulating the app.
// A member may access onboarding/KYC/payment endpoints regardless, but must
// satisfy BOTH of the following before money/disbursement/financial routes:
//   - kyc_verified = TRUE
//   - registration_fee_paid = TRUE
//
// The exact stage is made machine-readable on the response so the mobile app
// can render the right onboarding screen instead of a generic 403.
const ACTIVATION_BLOCKED = 'ACTIVATION_BLOCKED';

async function loadGateProfile(profileId) {
  const { data } = await supabase
    .from('profiles')
    .select('id, kyc_verified, registration_fee_paid, membership_status, is_active')
    .eq('id', profileId)
    .maybeSingle();
  return data;
}

/**
 * Attach the member's activation-gate summary to req so downstream handlers
 * (e.g. /auth/me) can expose it without an extra query. Safe to call after
 * `authenticate`.
 */
async function attachGateStatus(req, res, next) {
  try {
    if (req.user && req.user.id) {
      const profile = await loadGateProfile(req.user.id);
      req.gate = gateStatusFor(profile);
    } else {
      req.gate = { activated: false, kyc_approved: false, registration_fee_paid: false };
    }
  } catch (err) {
    logger.warn('attachGateStatus: profile lookup failed:', err.message);
    req.gate = { activated: false, kyc_approved: false, registration_fee_paid: false };
  }
  next();
}

/** Build a stable, machine-readable gate summary from a profiles row. */
function gateStatusFor(profile) {
  const kycApproved = profile?.kyc_verified === true;
  const feePaid = profile?.registration_fee_paid === true;
  const blocked = profile?.is_active === false ||
    profile?.membership_status === 'terminated';
  return {
    activated: kycApproved && feePaid && !blocked,
    kyc_approved: kycApproved,
    registration_fee_paid: feePaid,
    blocked,
  };
}

/**
 * Require the member to have passed the activation gate (KYC approved AND
 * registration fee paid). Returns a structured 403 with `code:
 * ACTIVATION_BLOCKED` and a `gate` breakdown so the client can route to the
 * correct onboarding step instead of hiding the dashboard in one place.
 */
function requireActivated(req, res, next) {
  return authenticate(req, res, async () => {
    try {
      const profile = await loadGateProfile(req.user.id);
      const gate = gateStatusFor(profile);
      req.gate = gate;
      if (gate.activated) return next();
      return res.status(403).json({
        success: false,
        error: 'Your membership has not been fully activated. Complete KYC verification and pay the registration fee to unlock your member dashboard.',
        code: ACTIVATION_BLOCKED,
        gate,
      });
    } catch (err) {
      logger.error('requireActivated: gate check failed:', err.message);
      return res.status(500).json({ success: false, error: 'Failed to verify membership status' });
    }
  });
}

module.exports = {
  authenticate,
  optionalAuth,
  requireAdmin,
  requireService,
  requireRole,
  requireSuperAdmin,
  decodeSessionId,
  requireActivated,
  attachGateStatus,
  gateStatusFor,
  ACTIVATION_BLOCKED,
};
