-- Add profile_picture column to profiles for member avatars.
-- Run this in the Supabase SQL editor before deploying the backend change.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS profile_picture TEXT;
