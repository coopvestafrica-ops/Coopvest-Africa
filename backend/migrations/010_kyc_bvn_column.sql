-- =============================================================================
-- Coopvest Africa — Add bvn column to kyc table
--
-- POST /api/v1/kyc/submit now persists the member's BVN at the top level of
-- the kyc row (in addition to inside bank_info JSONB). This column is required
-- for that write to succeed.
-- =============================================================================

ALTER TABLE public.kyc
  ADD COLUMN IF NOT EXISTS bvn TEXT;
