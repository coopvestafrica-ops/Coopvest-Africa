-- Migration 022: Registration fee → membership activation gate
--
-- Adds a single boolean gate column on profiles indicating whether the
-- member's ₦5,000 registration fee has been paid AND verified (by Finance /
-- admin, either automatically or via payment-proof review). Combined with the
-- existing `kyc_verified` flag it forms the member dashboard gate:
--
--   kyc_verified = TRUE
--   AND registration_fee_paid = TRUE
--
-- We deliberately do NOT add extra membership_status values (PAYMENT_REQUIRED,
-- PAYMENT_PENDING, etc.). The funnel is derived from real columns so the admin
-- dashboard can count each stage with plain aggregate queries:
--
--   KYC approved, fee not paid  -> registration_fee_paid IS FALSE
--   Fee paid, awaiting KYC       -> kyc_verified = FALSE
--   Fully activated             -> both TRUE
--
-- Apply via:  psql "$DATABASE_URL" -f migrations/022_registration_fee_gate.sql
-- (or run it in the Supabase SQL editor).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS registration_fee_paid BOOLEAN NOT NULL DEFAULT FALSE;

-- The payment that settled the fee (join to payment_proofs / transactions) so
-- an admin can audit exactly which proof activated the membership.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS registration_fee_paid_at TIMESTAMPTZ;

-- Backfill — two sources, both import:
--   (1) Any member with an approved registration_fee payment proof (or a paid
--       registration_fee obligation on member_fees) is treated as settled.
--   (2) GRANDFATHER: every pre-existing member whose KYC is already verified is
--     treated as fee-paid. The gate is going live against a live database, so
--     without this we would lock long-standing, active members out of their
--     dashboard the moment the column defaults to FALSE. Only NEW members
--     (those created after this rollout, i.e. kyc_verified IS FALSE or no KYC)
--     will be subject to the full Registration→KYC→₦5,000→Activation funnel.
--     Idempotent and safe to re-run.
UPDATE public.profiles p
SET registration_fee_paid = TRUE
WHERE
  p.id IN (
    SELECT DISTINCT profile_id
    FROM public.payment_proofs
    WHERE payment_type = 'registration_fee' AND status = 'approved' AND deleted_at IS NULL
    UNION
    SELECT DISTINCT profile_id
    FROM public.member_fees
    WHERE fee_type = 'registration_fee' AND status = 'paid'
  )
  OR (p.kyc_verified = TRUE AND p.is_active = TRUE);

COMMENT ON COLUMN public.profiles.registration_fee_paid IS
  'True once the member''s registration (entrance) fee has been verified and settled. Gates full dashboard access together with kyc_verified. Existing verified members are grandfathered as paid on rollout.';