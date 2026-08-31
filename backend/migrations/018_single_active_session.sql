-- Single-device login: tracks the one Supabase session allowed to use the API.
-- /auth/sync (called by the app after every fresh sign-in) claims this; the
-- auth middleware rejects requests whose JWT session_id does not match.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS active_session_id UUID;
