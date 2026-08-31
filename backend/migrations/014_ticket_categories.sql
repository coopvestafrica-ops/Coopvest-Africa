-- Extend tickets.category CHECK constraint with the categories the mobile
-- app's complaint form sends (contribution, withdrawal, complaint).
-- Run this in the Supabase SQL editor before deploying the backend change
-- that whitelists these categories.

ALTER TABLE public.tickets DROP CONSTRAINT IF EXISTS tickets_category_check;

ALTER TABLE public.tickets
  ADD CONSTRAINT tickets_category_check
  CHECK (category IN (
    'loan_issue',
    'guarantor_consent',
    'referral_bonus',
    'repayment_issue',
    'account_kyc',
    'contribution',
    'withdrawal',
    'technical_bug',
    'complaint',
    'other'
  ));
