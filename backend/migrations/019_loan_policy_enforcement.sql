-- 019_loan_policy_enforcement.sql
-- Schema support for the loan policy rules:
--   * Digital loan agreement evidence (Policy §2.2)
--   * "Request more information" admin action
--   * Contribution-reduction guard (records the contribution level used for eligibility)
--   * Account flagging reason (distinguishes system flags from manual fraud flags)

-- Digital loan agreement acceptances (borrower evidence)
CREATE TABLE IF NOT EXISTS public.loan_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id UUID NOT NULL REFERENCES public.loans(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  agreement_version TEXT NOT NULL DEFAULT 'v1.0',
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address TEXT,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_loan_agreements_loan_id ON public.loan_agreements(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_agreements_profile_id ON public.loan_agreements(profile_id);

-- Loans: agreement + info-request + eligibility snapshot columns
ALTER TABLE public.loans ADD COLUMN IF NOT EXISTS agreement_accepted_at TIMESTAMPTZ;
ALTER TABLE public.loans ADD COLUMN IF NOT EXISTS agreement_version TEXT;
ALTER TABLE public.loans ADD COLUMN IF NOT EXISTS info_requested_reason TEXT;
ALTER TABLE public.loans ADD COLUMN IF NOT EXISTS monthly_contribution_at_application NUMERIC(14,2);

-- Profiles: why the account is flagged (e.g. 'loan_default' for system flags)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS flag_reason TEXT;
