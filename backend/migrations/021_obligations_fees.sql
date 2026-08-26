-- Migration 021: Separate obligation types + super-admin configurable fees
--
-- Savings, loan repayment, fines and fees are tracked as separate obligations.
-- A deposit may carry an explicit per-type allocation breakdown
-- (deposit_requests.allocations) that the admin verify flow applies.

-- 1) Widen deposit_requests allocation types and add allocation breakdown
DO $$
BEGIN
  -- Drop the narrow CHECK from migration 020 so new types pass
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.deposit_requests'::regclass
      AND pg_get_constraintdef(oid) LIKE '%allocation_type%IN%'
  ) THEN
    EXECUTE (
      SELECT 'ALTER TABLE deposit_requests DROP CONSTRAINT ' || conname
      FROM pg_constraint
      WHERE conrelid = 'public.deposit_requests'::regclass
        AND pg_get_constraintdef(oid) LIKE '%allocation_type%IN%'
    );
  END IF;
END $$;

ALTER TABLE deposit_requests ADD CONSTRAINT allocation_type_check
  CHECK (allocation_type IN (
    'monthly_contribution',
    'loan_repayment',
    'fine',
    'fee',
    'registration_fee',
    'mixed'
  )) NOT VALID;
ALTER TABLE deposit_requests VALIDATE CONSTRAINT allocation_type_check;

ALTER TABLE deposit_requests ADD COLUMN IF NOT EXISTS allocations JSONB;
-- allocations: [{ "type": "savings"|"loan_repayment"|"fine"|"fee"|"registration_fee",
--                 "amount": numeric, "loan_id"?, "fee_id"? }]

ALTER TABLE deposit_requests ADD COLUMN IF NOT EXISTS fee_id UUID;

-- 2) Super-admin configurable fee catalogue
CREATE TABLE IF NOT EXISTS fee_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,           -- e.g. "Registration Fee"
  category    TEXT NOT NULL DEFAULT 'fee'     -- 'registration_fee' | 'fee' | 'fine'
              CHECK (category IN ('registration_fee', 'fee', 'fine')),
  amount      NUMERIC NOT NULL CHECK (amount >= 0),
  description TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3) Member obligations for fines/fees (penalties also land here now)
CREATE TABLE IF NOT EXISTS member_fees (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  fee_type_id UUID REFERENCES fee_types(id),
  loan_id     UUID REFERENCES loans(id),
  fee_type    TEXT NOT NULL CHECK (fee_type IN ('fine', 'fee', 'registration_fee')),
  label       TEXT NOT NULL DEFAULT '',
  amount      NUMERIC NOT NULL CHECK (amount >= 0),
  status      TEXT NOT NULL DEFAULT 'outstanding'
              CHECK (status IN ('outstanding', 'paid', 'waived')),
  assigned_by UUID,
  paid_at     TIMESTAMPTZ,
  deposit_id  UUID REFERENCES deposit_requests(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS member_fees_profile_idx ON member_fees (profile_id, status);
CREATE INDEX IF NOT EXISTS member_fees_loan_idx ON member_fees (loan_id);

-- Seed the default late-repayment fine so the catalogue is bootstrapped
INSERT INTO fee_types (name, category, amount, description)
VALUES ('Late Loan Repayment Fine', 'fine', 3000, 'Penalty for the 2nd consecutive missed monthly repayment (Loan Policy §4.1)')
ON CONFLICT (name) DO NOTHING;
