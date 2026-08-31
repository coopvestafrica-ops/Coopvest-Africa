-- =============================================================================
-- Coopvest Africa — Add cancelled_at column and expand loans.status constraint
--
-- POST /api/v1/loans/:loanId/cancel updates a loan with
--   { status: 'cancelled', cancelled_at: <now>, updated_at: <now> }.
-- That update failed with PostgREST error
--   "could not find the 'cancelled_at' of 'loan' in the schema cache"
-- because (a) the loans table had no cancelled_at column, and (b) the status
-- CHECK constraint did not allow 'cancelled'. This migration adds the column
-- and expands the constraint to include the lifecycle statuses the backend
-- actually writes (cancelled, under_review).
--
-- Idempotent: safe to re-run.
-- =============================================================================

-- 1) Track when a loan application was cancelled.
ALTER TABLE public.loans
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- 2) Expand the status CHECK constraint to permit 'cancelled' (written by the
--    cancel route) and 'under_review' (the cancel route guards on it and the
--    mobile Loan model lists it as a valid lifecycle status). Drop the old
--    constraint if it exists, then add the expanded one. The expanded set
--    preserves every status the live database already allows (including
--    'in_recovery') so no valid lifecycle value is removed.
ALTER TABLE public.loans
  DROP CONSTRAINT IF EXISTS loans_status_check;

ALTER TABLE public.loans
  ADD CONSTRAINT loans_status_check
  CHECK (status IN (
    'pending', 'under_review', 'approved', 'active',
    'rejected', 'completed', 'defaulted', 'in_recovery', 'cancelled'
  ));
