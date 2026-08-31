-- ============================================================================
-- Migration 025 — bulk_imports table
-- ============================================================================
-- Stores bulk file upload/import history for the Excel Manager page.
-- Idempotent — safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.bulk_imports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  filename     TEXT NOT NULL,
  type         TEXT NOT NULL DEFAULT 'bulk_contributions',
  uploaded_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  record_count INTEGER NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','reviewing','processed','failed')),
  error_count  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bulk_imports_created_at_idx ON public.bulk_imports(created_at DESC);

ALTER TABLE public.bulk_imports ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS bulk_imports_service_all
  ON public.bulk_imports
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
