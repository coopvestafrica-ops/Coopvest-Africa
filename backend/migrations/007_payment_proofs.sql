-- =============================================================================
-- Coopvest Africa — Payment Proofs Migration
-- 
-- This migration adds:
--   1. payment_proofs table - stores member payment proof submissions
--   2. digital_receipts table - stores auto-generated digital receipts
--   3. Updates audit_logs table with additional columns
--   4. RLS policies for security
--   5. Auto-update trigger
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Payment Proofs Table
-- Stores member proof of payment submissions for manual verification
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_proofs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Member identification
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  
  -- Payment details
  payment_type TEXT NOT NULL CHECK (payment_type IN (
    'monthly_contribution',
    'loan_repayment',
    'registration_fee',
    'investment',
    'other'
  )),
  amount DECIMAL(18, 2) NOT NULL,
  currency TEXT DEFAULT 'NGN',
  payment_date DATE NOT NULL,
  payment_method TEXT CHECK (payment_method IN (
    'bank_transfer',
    'ussd',
    'pos',
    'cash_deposit',
    'card'
  )),
  
  -- Bank details
  receiving_bank TEXT,
  bank_account_name TEXT,
  bank_account_number TEXT,
  
  -- Transaction reference
  transaction_reference TEXT,
  
  -- Proof of payment (file URL)
  proof_url TEXT,
  proof_type TEXT CHECK (proof_type IN ('image', 'pdf', 'screenshot')),
  original_filename TEXT,
  file_size INTEGER,
  
  -- Verification status
  status TEXT DEFAULT 'pending' CHECK (status IN (
    'pending',
    'under_review',
    'approved',
    'rejected'
  )),
  
  -- Rejection details
  rejection_reason TEXT,
  rejected_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES public.profiles(id),
  
  -- Approval details
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.profiles(id),
  
  -- Internal notes (from admin)
  admin_notes TEXT,
  
  -- Linked contribution record (created after approval)
  contribution_id UUID,
  
  -- Optional note from member
  member_note TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Soft delete
  deleted_at TIMESTAMPTZ
);

-- Indexes for payment_proofs
CREATE INDEX IF NOT EXISTS idx_payment_proofs_profile ON public.payment_proofs(profile_id);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_status ON public.payment_proofs(status);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_payment_type ON public.payment_proofs(payment_type);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_created_at ON public.payment_proofs(created_at);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_transaction_ref ON public.payment_proofs(transaction_reference);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_payment_date ON public.payment_proofs(payment_date);

-- -----------------------------------------------------------------------------
-- 2. Digital Receipts Table
-- Stores auto-generated digital receipts after payment approval
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.digital_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Receipt identification
  receipt_number TEXT UNIQUE NOT NULL,
  receipt_id TEXT UNIQUE, -- Short ID for QR code
  
  -- Links to payment proof
  payment_proof_id UUID UNIQUE REFERENCES public.payment_proofs(id) ON DELETE SET NULL,
  
  -- Member information
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  member_name TEXT,
  membership_id TEXT,
  
  -- Payment information
  payment_type TEXT,
  amount DECIMAL(18, 2) NOT NULL,
  currency TEXT DEFAULT 'NGN',
  
  -- Transaction details
  transaction_reference TEXT,
  payment_date DATE,
  payment_method TEXT,
  receiving_bank TEXT,
  
  -- Approval information
  approved_by UUID REFERENCES public.profiles(id),
  approved_by_name TEXT,
  approved_at TIMESTAMPTZ,
  
  -- QR code for verification
  qr_code_url TEXT,
  verification_hash TEXT,
  
  -- Receipt data (JSON for flexibility)
  receipt_data JSONB DEFAULT '{}'::jsonb,
  
  -- Organization info
  organization_name TEXT DEFAULT 'Coopvest Africa',
  organization_logo_url TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for digital_receipts
CREATE INDEX IF NOT EXISTS idx_digital_receipts_profile ON public.digital_receipts(profile_id);
CREATE INDEX IF NOT EXISTS idx_digital_receipts_receipt_number ON public.digital_receipts(receipt_number);
CREATE INDEX IF NOT EXISTS idx_digital_receipts_created_at ON public.digital_receipts(created_at);

-- -----------------------------------------------------------------------------
-- 3. Extend audit_logs table if needed
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  -- Add new columns if they don't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'resource') THEN
    ALTER TABLE public.audit_logs ADD COLUMN resource TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'resource_id') THEN
    ALTER TABLE public.audit_logs ADD COLUMN resource_id UUID;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'target_profile_id') THEN
    ALTER TABLE public.audit_logs ADD COLUMN target_profile_id UUID;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'ip_address') THEN
    ALTER TABLE public.audit_logs ADD COLUMN ip_address TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'user_agent') THEN
    ALTER TABLE public.audit_logs ADD COLUMN user_agent TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'details') THEN
    ALTER TABLE public.audit_logs ADD COLUMN details JSONB DEFAULT '{}'::jsonb;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Columns may already exist: %', SQLERRM;
END$$;

-- -----------------------------------------------------------------------------
-- 4. Add payment_proofs to auto-update trigger
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  tbl TEXT;
  tables TEXT[] := ARRAY[
    'profiles','kyc','savings','savings_goals','referrals','referral_events',
    'wallets','transactions','bank_accounts','loans','loan_qrs','loan_guarantors',
    'rollovers','investment_pools','investment_participations','notifications',
    'tickets','ticket_messages','user_settings','loan_repayments',
    'scheduled_notifications','payment_proofs','digital_receipts'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS set_updated_at ON public.%I;',
      tbl
    );
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
      tbl
    );
  END LOOP;
END$$;

-- -----------------------------------------------------------------------------
-- 5. RLS Policies for payment_proofs
-- -----------------------------------------------------------------------------
ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;

-- Members can only see their own payment proofs
DROP POLICY IF EXISTS payment_proofs_self_select ON public.payment_proofs;
CREATE POLICY payment_proofs_self_select ON public.payment_proofs
  FOR SELECT USING (profile_id = auth.uid() OR public.is_staff());

-- Members can insert their own payment proofs
DROP POLICY IF EXISTS payment_proofs_self_insert ON public.payment_proofs;
CREATE POLICY payment_proofs_self_insert ON public.payment_proofs
  FOR INSERT WITH CHECK (profile_id = auth.uid());

-- Members can update their own pending payment proofs
DROP POLICY IF EXISTS payment_proofs_self_update ON public.payment_proofs;
CREATE POLICY payment_proofs_self_update ON public.payment_proofs
  FOR UPDATE USING (profile_id = auth.uid() OR public.is_staff())
  WITH CHECK (profile_id = auth.uid() OR public.is_staff());

-- -----------------------------------------------------------------------------
-- 6. RLS Policies for digital_receipts
-- -----------------------------------------------------------------------------
ALTER TABLE public.digital_receipts ENABLE ROW LEVEL SECURITY;

-- Members can see their own receipts
DROP POLICY IF EXISTS digital_receipts_self_select ON public.digital_receipts;
CREATE POLICY digital_receipts_self_select ON public.digital_receipts
  FOR SELECT USING (profile_id = auth.uid() OR public.is_staff());

-- Staff can insert receipts
DROP POLICY IF EXISTS digital_receipts_staff_insert ON public.digital_receipts;
CREATE POLICY digital_receipts_staff_insert ON public.digital_receipts
  FOR INSERT WITH CHECK (public.is_staff());

-- Staff can update receipts
DROP POLICY IF EXISTS digital_receipts_staff_update ON public.digital_receipts;
CREATE POLICY digital_receipts_staff_update ON public.digital_receipts
  FOR UPDATE USING (public.is_staff());

-- -----------------------------------------------------------------------------
-- 7. Create function to generate receipt number
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_receipt_number()
RETURNS TEXT AS $$
DECLARE
  receipt_num TEXT;
  year_part TEXT;
  seq_num INTEGER;
BEGIN
  year_part := to_char(NOW(), 'YY');
  
  -- Get next sequence number for this year
  SELECT COALESCE(MAX(
    CAST(SUBSTRING(receipt_number FROM 4 FOR 6) AS INTEGER)
  ), 0) + 1
  INTO seq_num
  FROM public.digital_receipts
  WHERE receipt_number LIKE 'RCP' || year_part || '%';
  
  receipt_num := 'RCP' || year_part || LPAD(seq_num::TEXT, 6, '0');
  
  RETURN receipt_num;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 8. Create function to handle payment proof approval
-- This auto-creates contribution record and generates receipt
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_payment_proof_approval()
RETURNS TRIGGER AS $$
DECLARE
  member_record RECORD;
  receipt_num TEXT;
  new_contribution_id UUID;
BEGIN
  -- Only process when status changes to 'approved'
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    -- Get member information
    SELECT * INTO member_record
    FROM public.profiles
    WHERE id = NEW.profile_id;
    
    -- Generate receipt number
    receipt_num := public.generate_receipt_number();
    
    -- Create contribution record for monthly_contribution type
    IF NEW.payment_type = 'monthly_contribution' THEN
      INSERT INTO public.contributions (
        profile_id,
        amount,
        status,
        contribution_month,
        payment_proof_id,
        notes
      ) VALUES (
        NEW.profile_id,
        NEW.amount,
        'successful',
        TO_CHAR(NEW.payment_date, 'YYYY-MM'),
        NEW.id,
        'Auto-created from payment proof verification'
      ) RETURNING id INTO new_contribution_id;
      
      -- Update savings balance
      UPDATE public.savings
      SET 
        total_saved = total_saved + NEW.amount,
        last_savings_date = NOW()
      WHERE profile_id = NEW.profile_id;
      
      -- Update payment_proofs with contribution_id
      NEW.contribution_id := new_contribution_id;
    END IF;
    
    -- Create digital receipt
    INSERT INTO public.digital_receipts (
      receipt_number,
      receipt_id,
      payment_proof_id,
      profile_id,
      member_name,
      membership_id,
      payment_type,
      amount,
      currency,
      transaction_reference,
      payment_date,
      payment_method,
      receiving_bank,
      approved_by,
      approved_by_name,
      approved_at,
      organization_name
    ) VALUES (
      receipt_num,
      'RCP-' || SUBSTRING(receipt_num, 4, 8),
      NEW.id,
      NEW.profile_id,
      member_record.name,
      member_record.user_id,
      NEW.payment_type,
      NEW.amount,
      NEW.currency,
      NEW.transaction_reference,
      NEW.payment_date,
      NEW.payment_method,
      NEW.receiving_bank,
      NEW.approved_by,
      (SELECT name FROM public.profiles WHERE id = NEW.approved_by LIMIT 1),
      NEW.approved_at,
      'Coopvest Africa'
    );
    
    -- Create transaction record for wallet top-up
    IF NEW.payment_type IN ('monthly_contribution', 'investment', 'other') THEN
      INSERT INTO public.transactions (
        profile_id,
        type,
        category,
        amount,
        description,
        reference,
        status
      ) VALUES (
        NEW.profile_id,
        'credit',
        'payment_proof',
        NEW.amount,
        CASE NEW.payment_type
          WHEN 'monthly_contribution' THEN 'Monthly Contribution via Payment Proof'
          WHEN 'investment' THEN 'Investment via Payment Proof'
          ELSE 'Payment via Proof'
        END,
        NEW.transaction_reference,
        'successful'
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for auto-processing approvals
DROP TRIGGER IF EXISTS payment_proof_approval_trigger ON public.payment_proofs;
CREATE TRIGGER payment_proof_approval_trigger
  BEFORE UPDATE OF status ON public.payment_proofs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_payment_proof_approval();

-- -----------------------------------------------------------------------------
-- 9. Comments for documentation
-- -----------------------------------------------------------------------------
COMMENT ON TABLE public.payment_proofs IS 'Stores member proof of payment submissions for manual verification by admin';
COMMENT ON TABLE public.digital_receipts IS 'Auto-generated digital receipts after payment approval';
COMMENT ON COLUMN public.payment_proofs.payment_type IS 'Type of payment: monthly_contribution, loan_repayment, registration_fee, investment, other';
COMMENT ON COLUMN public.payment_proofs.status IS 'Verification status: pending, under_review, approved, rejected';
COMMENT ON COLUMN public.digital_receipts.receipt_number IS 'Unique receipt identifier: RCP{YY}{NNNNNN}';

-- -----------------------------------------------------------------------------
-- 10. Grant permissions
-- -----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON public.payment_proofs TO anon, authenticated;
GRANT ALL ON public.digital_receipts TO anon, authenticated;
GRANT ALL ON public.payment_proofs TO service_role;
GRANT ALL ON public.digital_receipts TO service_role;
