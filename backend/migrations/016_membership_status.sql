-- Track membership lifecycle on profiles so the admin portal and mobile app
-- can see pending/confirmed terminations.
-- Run this in the Supabase SQL editor before deploying the backend change.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS membership_status TEXT NOT NULL DEFAULT 'active';

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_membership_status_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_membership_status_check
  CHECK (membership_status IN ('active', 'pending_termination', 'suspended', 'terminated', 'inactive'));

-- Admin review metadata on termination requests.
ALTER TABLE public.termination_requests ADD COLUMN IF NOT EXISTS reviewed_by UUID;
ALTER TABLE public.termination_requests ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE public.termination_requests ADD COLUMN IF NOT EXISTS review_note TEXT;
