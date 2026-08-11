-- =============================================================================
-- Coopvest Africa — Add missing KYC/bank columns to profiles table
--
-- The POST /auth/complete-registration endpoint upserts all onboarding data
-- (personal, employment, bank, BVN/NIN) into public.profiles. The following
-- columns were missing, causing the upsert to fail with a 500 error
-- ("Failed to save registration data") whenever a member submitted bank
-- details or BVN/NIN during KYC onboarding.
-- =============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS bank_code TEXT,
  ADD COLUMN IF NOT EXISTS account_number TEXT,
  ADD COLUMN IF NOT EXISTS account_name TEXT,
  ADD COLUMN IF NOT EXISTS account_type TEXT,
  ADD COLUMN IF NOT EXISTS bvn TEXT,
  ADD COLUMN IF NOT EXISTS nin TEXT;
