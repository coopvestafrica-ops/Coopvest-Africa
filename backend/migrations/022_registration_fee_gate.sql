-- Migration 022: Registration fee → membership activation gate
-- (Corrected for live application: member_fees may not exist — guarded.)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS registration_fee_paid BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS registration_fee_paid_at TIMESTAMPTZ;

-- Backfill (idempotent, safe to re-run):
--   (1) approved registration_fee payment proof  →  paid
--   (2) member_fees registration_fee paid (only if that table exists)
--   (3) GRANDFATHER: existing kyc_verified AND is_active members → paid
--       (so live active members are not locked out at rollout).
DO $$
BEGIN
  IF to_regclass('public.member_fees') IS NOT NULL THEN
    UPDATE public.profiles p
    SET registration_fee_paid = TRUE
    WHERE p.id IN (
      SELECT DISTINCT profile_id
      FROM public.payment_proofs
      WHERE payment_type = 'registration_fee' AND status = 'approved' AND deleted_at IS NULL
      UNION
      SELECT DISTINCT profile_id
      FROM public.member_fees
      WHERE fee_type = 'registration_fee' AND status = 'paid'
    );
  ELSE
    UPDATE public.profiles p
    SET registration_fee_paid = TRUE
    WHERE p.id IN (
      SELECT DISTINCT profile_id
      FROM public.payment_proofs
      WHERE payment_type = 'registration_fee' AND status = 'approved' AND deleted_at IS NULL
    );
  END IF;
END $$;

-- Grandfather (separate, unconditional)
UPDATE public.profiles
SET registration_fee_paid = TRUE
WHERE kyc_verified = TRUE AND is_active = TRUE;

COMMENT ON COLUMN public.profiles.registration_fee_paid IS
  'True once the member''s registration (entrance) fee has been verified and settled. Gates full dashboard access together with kyc_verified. Existing verified members are grandfathered as paid on rollout.';