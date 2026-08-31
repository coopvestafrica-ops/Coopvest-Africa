-- Payment allocation support for deposit_requests.
-- Adds an allocation_type so admin verification routes the payment to
-- savings (wallet) or loan repayment, and supports a mixed split.
ALTER TABLE public.deposit_requests
  ADD COLUMN IF NOT EXISTS allocation_type TEXT NOT NULL DEFAULT 'monthly_contribution'
    CHECK (allocation_type IN ('monthly_contribution', 'loan_repayment', 'mixed')),
  ADD COLUMN IF NOT EXISTS loan_id UUID REFERENCES public.loans(id),
  ADD COLUMN IF NOT EXISTS savings_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS loan_amount NUMERIC;

-- Loan repayment requests created from the member app link to a loan_repayments row.
ALTER TABLE public.loan_repayments
  ADD COLUMN IF NOT EXISTS deposit_request_id UUID REFERENCES public.deposit_requests(id);
