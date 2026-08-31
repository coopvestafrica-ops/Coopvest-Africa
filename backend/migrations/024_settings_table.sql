-- ============================================================================
-- Migration 024 — App-wide settings table
-- ============================================================================
-- Creates the key-value settings store used by:
--   • GET/PUT /api/v1/admin/payment-settings
--   • GET/PUT /api/v1/admin/salary-deduction
--   • GET     /api/v1/wallet/payment-settings
--
-- Idempotent — safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.settings (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the payment account row so the admin PUT upsert always works.
INSERT INTO public.settings (key, value)
VALUES ('payment_account', '{}'::jsonb)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.settings (key, value)
VALUES ('salary_deduction_global', '{"enabled": false}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Allow the service role (backend) full access; block the anon role entirely.
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

-- The backend always connects with the service role which bypasses RLS,
-- but add an explicit policy for clarity and any future non-service usage.
CREATE POLICY IF NOT EXISTS settings_service_all
  ON public.settings
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
