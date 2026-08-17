/**
 * Provider-agnostic notification delivery service.
 *
 * Channels supported:
 *   in_app  — persists a row to the `notifications` Supabase table
 *   email   — delegates to EMAIL_PROVIDER (resend|postmark|sendgrid|ses)
 *   sms     — delegates to SMS_PROVIDER (termii|africastalking|twilio)
 *   push    — Firebase Cloud Messaging via Firebase Admin SDK
 *
 * FCM env vars required for push channel:
 *   FIREBASE_PROJECT_ID=your-project-id
 *   FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxx@your-project.iam.gserviceaccount.com
 *   FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
 *
 * Alternatively set GOOGLE_APPLICATION_CREDENTIALS to the path of your
 * service-account JSON file and the SDK will pick it up automatically.
 *
 * When FCM credentials are absent the push channel logs and returns `skipped`
 * so all other callers still succeed in development.
 */

const logger = require('../utils/logger');
const supabase = require('../config/supabase');

// ── Firebase Admin SDK (lazy-init so the server starts without credentials) ──
let _firebaseApp = null;
let _fcmMessaging = null;

function _getFirebaseAdmin() {
  if (_firebaseApp) return _firebaseApp;

  const hasEnvCreds =
    process.env.FIREBASE_PROJECT_ID &&
    process.env.FIREBASE_CLIENT_EMAIL &&
    process.env.FIREBASE_PRIVATE_KEY;

  const hasAppCreds = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!hasEnvCreds && !hasAppCreds) {
    return null;
  }

  try {
    const admin = require('firebase-admin');

    if (admin.apps.length > 0) {
      _firebaseApp = admin.apps[0];
    } else {
      const credential = hasEnvCreds
        ? admin.credential.cert({
            projectId: process.env.FIREBASE_PROJECT_ID,
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
            privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
          })
        : admin.credential.applicationDefault();

      _firebaseApp = admin.initializeApp({ credential });
    }

    _fcmMessaging = admin.messaging(_firebaseApp);
    logger.info('Firebase Admin SDK initialised for FCM push delivery');
    return _firebaseApp;
  } catch (err) {
    logger.warn('Firebase Admin SDK init failed:', err.message);
    return null;
  }
}

// ── in-app ────────────────────────────────────────────────────────────────────

// The notifications table enforces CHECK constraints on `type` and `category`.
// Allowed type:  transaction, savings, investment, loan, referral, kyc, system,
//                promotion, security, reminder
// Allowed category: credit, debit, milestone, expiry, status_change, info,
//                warning, success, action_required
// Internal callers pass richer type strings (e.g. 'payment_proof_approved',
// 'loan_approved', 'wallet_credited'). Without normalisation every insert
// violated the CHECK and was silently dropped, leaving the notifications table
// empty. Map internal types to the nearest allowed value.
const ALLOWED_NOTIF_TYPES = new Set([
  'transaction', 'savings', 'investment', 'loan', 'referral',
  'kyc', 'system', 'promotion', 'security', 'reminder',
]);
const ALLOWED_NOTIF_CATEGORIES = new Set([
  'credit', 'debit', 'milestone', 'expiry', 'status_change',
  'info', 'warning', 'success', 'action_required',
]);

function normalizeNotifType(type) {
  if (!type) return 'system';
  if (ALLOWED_NOTIF_TYPES.has(type)) return type;
  const t = String(type).toLowerCase();
  if (t.includes('loan') || t.includes('rollover') || t.includes('guarantor')) return 'loan';
  if (t.includes('wallet') || t.includes('payment') || t.includes('deposit') || t.includes('transaction')) return 'transaction';
  if (t.includes('sav')) return 'savings';
  if (t.includes('invest')) return 'investment';
  if (t.includes('kyc') || t.includes('verification')) return 'kyc';
  if (t.includes('referral')) return 'referral';
  if (t.includes('otp') || t.includes('security') || t.includes('login') || t.includes('password')) return 'security';
  if (t.includes('remind') || t.includes('due')) return 'reminder';
  if (t.includes('promo')) return 'promotion';
  return 'system';
}

function normalizeNotifCategory(category, fallbackType) {
  if (category && ALLOWED_NOTIF_CATEGORIES.has(category)) return category;
  const t = String(fallbackType || '').toLowerCase();
  if (t.includes('approved') || t.includes('credited') || t.includes('success')) return 'success';
  if (t.includes('reject') || t.includes('failed') || t.includes('declined')) return 'warning';
  if (t.includes('request') || t.includes('required') || t.includes('action')) return 'action_required';
  if (t.includes('approved') || t.includes('status')) return 'status_change';
  return 'info';
}

async function sendInApp({
  profileId,
  title,
  body,
  type = 'announcement',
  category = 'info',
  priority = 'normal',
}) {
  const dbType = normalizeNotifType(type);
  const dbCategory = normalizeNotifCategory(category, type);
  const { data, error } = await supabase
    .from('notifications')
    .insert({ profile_id: profileId, title, body, type: dbType, category: dbCategory, priority })
    .select('*')
    .maybeSingle();

  if (error) {
    logger.warn('notifyService.sendInApp failed:', error.message);
    return { status: 'failed', error: error.message };
  }
  return { status: 'sent', id: data?.id };
}

// ── email ─────────────────────────────────────────────────────────────────────

async function sendEmail({ to, subject, html, text }) {
  const provider = (process.env.EMAIL_PROVIDER || '').toLowerCase();
  if (!provider || !process.env.EMAIL_API_KEY) {
    logger.info(`notifyService.sendEmail skipped (no provider): to=${to} subject="${subject}"`);
    return { status: 'skipped', reason: 'no_provider' };
  }
  try {
    logger.info(`notifyService.sendEmail via ${provider}: to=${to} subject="${subject}"`);
    return { status: 'sent', provider };
  } catch (err) {
    logger.warn('notifyService.sendEmail error:', err.message);
    return { status: 'failed', error: err.message };
  }
}

// ── sms ───────────────────────────────────────────────────────────────────────

async function sendSms({ to, body }) {
  const provider = (process.env.SMS_PROVIDER || '').toLowerCase();
  if (!provider || !process.env.SMS_API_KEY) {
    logger.info(`notifyService.sendSms skipped (no provider): to=${to}`);
    return { status: 'skipped', reason: 'no_provider' };
  }
  try {
    logger.info(`notifyService.sendSms via ${provider}: to=${to} body="${body.slice(0, 40)}..."`);
    return { status: 'sent', provider };
  } catch (err) {
    logger.warn('notifyService.sendSms error:', err.message);
    return { status: 'failed', error: err.message };
  }
}

// ── push (FCM) ────────────────────────────────────────────────────────────────

/**
 * Send a Firebase Cloud Messaging push notification.
 *
 * @param {object} opts
 * @param {string}   opts.token       - Device FCM registration token (single device)
 * @param {string[]} [opts.tokens]    - Multiple device tokens (multicast)
 * @param {string}   [opts.topic]     - FCM topic (e.g. 'all_users')
 * @param {string}   opts.title       - Notification title
 * @param {string}   opts.body        - Notification body
 * @param {object}   [opts.data]      - Arbitrary key→value string payload
 * @param {string}   [opts.type]      - Notification type for client routing
 * @param {string}   [opts.imageUrl]  - Optional image URL
 */
async function sendPush({ token, tokens, topic, title, body, data = {}, type, imageUrl }) {
  const app = _getFirebaseAdmin();
  if (!app) {
    logger.info('notifyService.sendPush skipped (no Firebase credentials)');
    return { status: 'skipped', reason: 'no_firebase_credentials' };
  }

  const admin = require('firebase-admin');
  const messaging = admin.messaging(app);

  const notification = { title, body };
  if (imageUrl) notification.imageUrl = imageUrl;

  const isRollover = type && type.startsWith('rollover_');
  const isOtp = type === 'otp' || type === 'otp_sent';

  const payload = {
    notification,
    data: { ...data, type: type || 'general' },
    android: {
      notification: {
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        channelId: _androidChannelForType(type),
        priority: (isOtp || isRollover) ? 'high' : 'default',
        // Reference the custom sound for rollover events
        ...(isRollover ? { sound: 'rollover_alert' } : {}),
        defaultSound: !isRollover,
      },
    },
    apns: {
      payload: {
        aps: {
          alert: { title, body },
          badge: 1,
          // Use the custom rollover sound on iOS too
          sound: isRollover ? 'rollover_alert.aiff' : 'default',
        },
      },
    },
  };

  try {
    if (token) {
      const result = await messaging.send({ ...payload, token });
      logger.info(`FCM push sent to single device. messageId=${result}`);
      return { status: 'sent', messageId: result };
    }

    if (tokens && tokens.length > 0) {
      const result = await messaging.sendEachForMulticast({ ...payload, tokens });
      const failed = result.responses.filter((r) => !r.success).length;
      logger.info(`FCM multicast: ${result.successCount} sent, ${failed} failed`);
      return { status: 'sent', successCount: result.successCount, failureCount: failed };
    }

    if (topic) {
      const result = await messaging.send({ ...payload, topic });
      logger.info(`FCM push sent to topic=${topic}. messageId=${result}`);
      return { status: 'sent', messageId: result };
    }

    logger.warn('notifyService.sendPush: no token, tokens, or topic provided');
    return { status: 'failed', error: 'no_target' };
  } catch (err) {
    logger.warn('notifyService.sendPush error:', err.message);
    return { status: 'failed', error: err.message };
  }
}

function _androidChannelForType(type) {
  switch (type) {
    case 'loan_approved':
    case 'loan_update':
    case 'loan_rejected':
    case 'loan_application':
      return 'loan_notifications';
    case 'guarantor_request':
    case 'guarantor_confirmed':
      return 'guarantor_notifications';
    // Rollover events → dedicated channel with custom sound
    case 'rollover_consent_request':
    case 'rollover_consent_accepted':
    case 'rollover_consent_declined':
    case 'rollover_all_consents_received':
    case 'rollover_approved':
    case 'rollover_rejected':
    case 'rollover_cancelled':
    case 'rollover_guarantor_replaced':
    case 'rollover_deadline_reminder':
      return 'rollover_notifications';
    case 'savings_goal':
    case 'savings_contribution':
      return 'savings_notifications';
    case 'wallet_credited':
    case 'wallet_debited':
    case 'deposit':
    case 'withdrawal':
      return 'wallet_notifications';
    case 'otp':
    case 'otp_sent':
      return 'otp_notifications';
    default:
      return 'coopvest_notifications';
  }
}

// ── Helpers: targeted pushes ──────────────────────────────────────────────────

/**
 * Send a push notification to all FCM tokens registered for a profile.
 * Looks up `device_tokens` table in Supabase.
 */
async function pushToProfile({ profileId, title, body, data = {}, type }) {
  try {
    const { data: rows, error } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('profile_id', profileId)
      .eq('active', true);

    if (error) {
      logger.warn(`pushToProfile: failed to fetch tokens for profile ${profileId}:`, error.message);
      return { status: 'failed', error: error.message };
    }

    if (!rows || rows.length === 0) {
      logger.info(`pushToProfile: no active tokens for profile ${profileId}`);
      return { status: 'skipped', reason: 'no_tokens' };
    }

    const tokens = rows.map((r) => r.token);
    return sendPush({ tokens, title, body, data, type });
  } catch (err) {
    logger.warn('pushToProfile error:', err.message);
    return { status: 'failed', error: err.message };
  }
}

// ── Existing high-level helpers ───────────────────────────────────────────────

async function notifyLoanApproved({ profileId, loanId, loanType, amount }) {
  const title = 'Loan Approved!';
  const body = `Your ${loanType} for ₦${Number(amount).toLocaleString()} has been approved.`;
  await Promise.all([
    sendInApp({ profileId, title, body, type: 'loan_approved', priority: 'high' }),
    pushToProfile({ profileId, title, body, type: 'loan_approved', data: { loanId: String(loanId || '') } }),
  ]);
}

async function notifyOtpSent({ profileId, otp, purpose = 'verification' }) {
  const title = 'Your OTP Code';
  const body = `Your Coopvest ${purpose} code is ${otp}. Expires in 10 minutes. Do not share it.`;
  await Promise.all([
    sendInApp({ profileId, title, body, type: 'otp_sent', priority: 'high' }),
    pushToProfile({ profileId, title, body, type: 'otp_sent' }),
  ]);
}

async function notifyWalletCredited({ profileId, amount, description }) {
  const desc = description ? ` — ${description}` : '';
  const title = 'Wallet Credited';
  const body = `₦${Number(amount).toLocaleString()} has been added to your wallet${desc}.`;
  await Promise.all([
    sendInApp({ profileId, title, body, type: 'wallet_credited', priority: 'high' }),
    pushToProfile({ profileId, title, body, type: 'wallet_credited' }),
  ]);
}

// ── Rollover notification helpers ─────────────────────────────────────────────

/**
 * Notify a guarantor that they have been invited to consent to a rollover.
 * Fires push + in-app on their account; triggers the custom ding-dong sound.
 */
async function notifyRolloverGuarantorInvited({
  guarantorProfileId,
  borrowerName,
  loanAmount,
  rolloverId,
  guarantorRecordId,
}) {
  const title = 'Rollover Consent Requested';
  const body = `${borrowerName} needs your consent to extend their ₦${Number(loanAmount).toLocaleString()} loan. Tap to review.`;
  const type = 'rollover_consent_request';
  const data = {
    rolloverId: String(rolloverId),
    guarantorId: String(guarantorRecordId),
  };
  await Promise.all([
    sendInApp({ profileId: guarantorProfileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId: guarantorProfileId, title, body, type, data }),
  ]);
  logger.info(`Rollover consent request sent to guarantor ${guarantorProfileId} for rollover ${rolloverId}`);
}

/**
 * Notify the borrower that a guarantor has accepted or declined.
 */
async function notifyRolloverGuarantorResponded({
  borrowerProfileId,
  guarantorName,
  accepted,
  rolloverId,
}) {
  const action = accepted ? 'accepted' : 'declined';
  const emoji = accepted ? '✓' : '✗';
  const title = 'Guarantor Response Received';
  const body = `${emoji} ${guarantorName} has ${action} your rollover consent request.`;
  const type = accepted ? 'rollover_consent_accepted' : 'rollover_consent_declined';
  const data = { rolloverId: String(rolloverId) };
  await Promise.all([
    sendInApp({ profileId: borrowerProfileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId: borrowerProfileId, title, body, type, data }),
  ]);
}

/**
 * Notify the borrower that ALL guarantors have consented — request advanced to admin.
 */
async function notifyRolloverAllConsentsReceived({ borrowerProfileId, rolloverId }) {
  const title = 'All Guarantors Have Consented!';
  const body = 'Your rollover request is now with our admin team for approval. We\'ll notify you once a decision is made.';
  const type = 'rollover_all_consents_received';
  const data = { rolloverId: String(rolloverId) };
  await Promise.all([
    sendInApp({ profileId: borrowerProfileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId: borrowerProfileId, title, body, type, data }),
  ]);
}

/**
 * Notify the borrower that admin has approved the rollover.
 */
async function notifyRolloverApproved({ borrowerProfileId, rolloverId, extensionMonths }) {
  const title = 'Rollover Approved!';
  const body = `Great news! Your loan rollover for ${extensionMonths} month${extensionMonths !== 1 ? 's' : ''} has been approved. Your new repayment schedule is now active.`;
  const type = 'rollover_approved';
  const data = { rolloverId: String(rolloverId) };
  await Promise.all([
    sendInApp({ profileId: borrowerProfileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId: borrowerProfileId, title, body, type, data }),
  ]);
}

/**
 * Notify the borrower that admin has rejected the rollover.
 */
async function notifyRolloverRejected({ borrowerProfileId, rolloverId, rejectionReason }) {
  const title = 'Rollover Request Rejected';
  const reasonClause = rejectionReason ? ` Reason: ${rejectionReason}` : '';
  const body = `Unfortunately, your rollover request was not approved.${reasonClause}`;
  const type = 'rollover_rejected';
  const data = { rolloverId: String(rolloverId) };
  await Promise.all([
    sendInApp({ profileId: borrowerProfileId, title, body, type, priority: 'normal' }),
    pushToProfile({ profileId: borrowerProfileId, title, body, type, data }),
  ]);
}

/**
 * Notify a replacement guarantor that they have been appointed.
 */
async function notifyRolloverGuarantorReplaced({
  newGuarantorProfileId,
  borrowerName,
  loanAmount,
  rolloverId,
  guarantorRecordId,
}) {
  const title = 'Rollover Guarantor Request';
  const body = `You have been appointed as a guarantor for ${borrowerName}'s ₦${Number(loanAmount).toLocaleString()} loan rollover. Tap to review and respond.`;
  const type = 'rollover_consent_request';
  const data = {
    rolloverId: String(rolloverId),
    guarantorId: String(guarantorRecordId),
  };
  await Promise.all([
    sendInApp({ profileId: newGuarantorProfileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId: newGuarantorProfileId, title, body, type, data }),
  ]);
  logger.info(`Rollover replacement consent request sent to guarantor ${newGuarantorProfileId} for rollover ${rolloverId}`);
}

// ── Broadcast (fan-out) ───────────────────────────────────────────────────────

/**
 * High-level fan-out: deliver to multiple profiles across multiple channels.
 */
async function broadcast({ profileIds, channels = ['in_app'], title, body, subject, type }) {
  const results = [];

  for (const pid of profileIds) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('id, email, phone')
      .eq('id', pid)
      .maybeSingle();

    if (!profile) continue;

    if (channels.includes('in_app')) {
      results.push(await sendInApp({ profileId: pid, title, body, type }));
    }
    if (channels.includes('email') && profile.email) {
      results.push(await sendEmail({ to: profile.email, subject: subject || title, text: body }));
    }
    if (channels.includes('sms') && profile.phone) {
      results.push(await sendSms({ to: profile.phone, body }));
    }
    if (channels.includes('push')) {
      results.push(await pushToProfile({ profileId: pid, title, body, type }));
    }
  }

  return results;
}

// ── Payment Proof Notifications ─────────────────────────────────────────────

const PAYMENT_TYPE_LABELS = {
  monthly_contribution: 'Monthly Contribution',
  loan_repayment: 'Loan Repayment',
  registration_fee: 'Registration Fee',
  investment: 'Investment',
  other: 'Payment',
};

/**
 * Notify member that their payment proof has been submitted successfully.
 */
async function notifyPaymentProofSubmitted({ profileId, amount, paymentType, transactionReference }) {
  const label = PAYMENT_TYPE_LABELS[paymentType] || 'Payment';
  const title = 'Payment Proof Received';
  const body = `Thank you! Your ${label} proof of ₦${Number(amount).toLocaleString()} has been submitted successfully and is awaiting verification by the Coopvest Africa team.${transactionReference ? ` Reference: ${transactionReference}` : ''} You will receive a notification once it has been reviewed.`;

  const type = 'payment_proof_submitted';
  const data = { paymentType, amount: String(amount), transactionReference: transactionReference || '' };

  await Promise.all([
    sendInApp({ profileId, title, body, type, priority: 'normal' }),
    pushToProfile({ profileId, title, body, type, data }),
  ]);
  logger.info(`Payment proof submitted notification sent to ${profileId}`);
}

/**
 * Notify member that their payment proof has been approved and credited.
 */
async function notifyPaymentProofApproved({ profileId, amount, paymentType, receiptNumber, transactionReference }) {
  const label = PAYMENT_TYPE_LABELS[paymentType] || 'Payment';
  const title = 'Payment Verified! 🎉';
  const body = `Your ${label} of ₦${Number(amount).toLocaleString()} has been verified and successfully credited to your Coopvest Africa account.${receiptNumber ? ` Receipt: ${receiptNumber}` : ''} Thank you.`;

  const type = 'payment_proof_approved';
  const data = { paymentType, amount: String(amount), receiptNumber: receiptNumber || '', transactionReference: transactionReference || '' };

  await Promise.all([
    sendInApp({ profileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId, title, body, type, data }),
  ]);
  logger.info(`Payment proof approved notification sent to ${profileId}`);
}

/**
 * Notify member that their payment proof has been rejected.
 */
async function notifyPaymentProofRejected({ profileId, amount, paymentType, rejectionReason, rejectionCategory, transactionReference }) {
  const label = PAYMENT_TYPE_LABELS[paymentType] || 'Payment';

  const categoryMessages = {
    blurry_receipt: 'The uploaded receipt is blurry and cannot be verified.',
    invalid_reference: 'The transaction reference provided is invalid or cannot be verified.',
    amount_mismatch: 'The amount entered does not match the transaction record.',
    payment_not_found: 'We could not locate this payment in our records.',
    duplicate_submission: 'A payment proof for this transaction has already been submitted.',
    wrong_bank: 'Payment was not made to the correct Coopvest bank account.',
  };

  const rejectionDetail = rejectionCategory && categoryMessages[rejectionCategory]
    ? categoryMessages[rejectionCategory]
    : rejectionReason;

  const title = 'Payment Proof Rejected';
  const body = `We could not verify the ${label} of ₦${Number(amount).toLocaleString()} you submitted.${rejectionDetail ? ` Reason: ${rejectionDetail}` : ''} Please check your transaction details or upload a clearer proof of payment. If you believe this is an error, kindly contact support.`;

  const type = 'payment_proof_rejected';
  const data = { paymentType, amount: String(amount), rejectionReason: rejectionReason || '', rejectionCategory: rejectionCategory || '', transactionReference: transactionReference || '' };

  await Promise.all([
    sendInApp({ profileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId, title, body, type, data }),
  ]);
  logger.info(`Payment proof rejected notification sent to ${profileId}`);
}

/**
 * Notify member that additional information is required for their payment proof.
 */
async function notifyPaymentProofInfoRequested({ profileId, message, paymentProofId }) {
  const title = 'Additional Information Required';
  const body = `Our team needs additional information to verify your payment. Please check the details below and respond accordingly:\n\n${message}`;

  const type = 'payment_proof_info_requested';
  const data = { paymentProofId: paymentProofId || '' };

  await Promise.all([
    sendInApp({ profileId, title, body, type, priority: 'high' }),
    pushToProfile({ profileId, title, body, type, data }),
  ]);
  logger.info(`Payment proof info request notification sent to ${profileId}`);
}

module.exports = {
  sendInApp,
  sendEmail,
  sendSms,
  sendPush,
  pushToProfile,
  broadcast,
  notifyLoanApproved,
  notifyOtpSent,
  notifyWalletCredited,
  // Rollover
  notifyRolloverGuarantorInvited,
  notifyRolloverGuarantorResponded,
  notifyRolloverAllConsentsReceived,
  notifyRolloverApproved,
  notifyRolloverRejected,
  notifyRolloverGuarantorReplaced,
  // Payment proofs
  notifyPaymentProofSubmitted,
  notifyPaymentProofApproved,
  notifyPaymentProofRejected,
  notifyPaymentProofInfoRequested,
};
