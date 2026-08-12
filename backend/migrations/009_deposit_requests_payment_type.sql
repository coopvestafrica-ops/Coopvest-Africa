-- Migration: Add payment_type to deposit_requests
-- Description: Track the purpose of a deposit (monthly_contribution, loan_repayment,
--              overdue_payment, fine) so it can be displayed in the deposit/proof UI.
-- Date: 2026-08-12

ALTER TABLE public.deposit_requests
  ADD COLUMN IF NOT EXISTS payment_type TEXT DEFAULT 'monthly_contribution'
  CHECK (payment_type IN ('monthly_contribution', 'loan_repayment', 'overdue_payment', 'fine'));

CREATE INDEX IF NOT EXISTS idx_deposit_requests_payment_type
  ON public.deposit_requests(payment_type);
