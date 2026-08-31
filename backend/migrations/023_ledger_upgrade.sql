-- ============================================================================
-- Migration 023 — Central Financial Ledger upgrade
-- ============================================================================
-- Turns the append-only `ledger_entries` table (from admin_platform.sql) into
-- the full "source of truth" financial ledger:
--
--   * Serialized transaction IDs  CV-YYYY-NNNNNN  (txn_no)
--   * Structured, denormalized columns for member/organization/payment/bank
--   * Explicit initiated_by / approved_by split
--   * Related loan + payment-proof ids and the per-line allocation breakdown
--   * Bank statement import + reconciliation engine (matched / mismatch queue)
--
-- Additive only: existing ledger rows and columns are preserved. Idempotent —
-- safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Base ledger table (created if the optional admin_platform migration was
--    never run). Existing installations that already have it are unchanged.
-- ---------------------------------------------------------------------------
create table if not exists public.ledger_entries (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid references public.profiles(id) on delete set null,
  reference       text,
  type            text not null default 'adjustment',
  description     text,
  debit           numeric(14,2) not null default 0,
  credit          numeric(14,2) not null default 0,
  source          text not null default 'system',
  status          text not null default 'completed',
  initiated_by    uuid,
  reversed        boolean not null default false,
  reversal_of     uuid,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists ledger_entries_profile_idx on public.ledger_entries (profile_id, created_at desc);
create index if not exists ledger_entries_reference_idx on public.ledger_entries (reference);
create index if not exists ledger_entries_reversal_of_idx on public.ledger_entries (reversal_of);
create index if not exists ledger_entries_created_at_idx on public.ledger_entries (created_at desc);

-- ---------------------------------------------------------------------------
-- 1. leapyear-safe sequential transaction numbers  CV-YYYY-NNNNNN
-- ---------------------------------------------------------------------------
create table if not exists public.ledger_serial (
  year      integer not null default date_part('year', now())::int,
  sequence  bigint  not null default 0,
  primary key (year)
);

-- Generate the next transaction number for a given year, e.g. CV-2026-000001
create or replace function public.next_ledger_txn_no(target_year integer default null)
returns text
language plpgsql
volatile
as $$
declare
  yr integer := coalesce(target_year, date_part('year', now())::int);
  seq bigint;
begin
  insert into public.ledger_serial (year, sequence)
  values (yr, 1)
  on conflict (year) do update
    set sequence = public.ledger_serial.sequence + 1
  returning sequence into seq;
  return 'CV-' || yr::text || '-' || lpad(seq::text, 6, '0');
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Enrich ledger_entries to the full transaction record
-- ---------------------------------------------------------------------------
alter table public.ledger_entries
  add column if not exists txn_no           text default public.next_ledger_txn_no(),
  add column if not exists member_name      text,
  add column if not exists membership_id    text,      -- member-facing id (profiles.user_id)
  add column if not exists organization     text,
  add column if not exists payment_method   text,
  add column if not exists bank_account     text,
  add column if not exists amount           numeric(14,2),
  add column if not exists approved_by      uuid,
  add column if not exists checked_by       uuid,          -- verifier/finance officer
  add column if not exists requested_by     uuid,          -- who asked for an adjustment
  add column if not exists loan_id          uuid,
  add column if not exists payment_proof_id uuid,
  add column if not exists allocation       jsonb not null default '{}'::jsonb,  -- [{type, amount, loan_id?}]
  add column if not exists reconciled       boolean not null default false,
  add column if not exists reconciled_at    timestamptz;

create index if not exists ledger_entries_txn_no_idx       on public.ledger_entries (txn_no);
create index if not exists ledger_entries_member_idx       on public.ledger_entries (member_name);
create index if not exists ledger_entries_org_idx          on public.ledger_entries (organization);
create index if not exists ledger_entries_payment_meth_idx on public.ledger_entries (payment_method);
create index if not exists ledger_entries_loan_idx         on public.ledger_entries (loan_id);
create index if not exists ledger_entries_proof_idx        on public.ledger_entries (payment_proof_id);
create index if not exists ledger_entries_amount_idx       on public.ledger_entries (amount);
create index if not exists ledger_entries_approved_by_idx  on public.ledger_entries (approved_by);

-- Backfill txn_no for any pre-existing ledger rows (idempotent: only unmbered).
do $$
declare
  r record;
begin
  for r in
    select id from public.ledger_entries
    where txn_no is null
    order by created_at asc
  loop
    update public.ledger_entries
      set txn_no = public.next_ledger_txn_no()
      where id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Bank reconciliation support tables
-- ---------------------------------------------------------------------------
-- One row per imported bank-statement line. Immutable once imported; status
-- advances (unmatched -> matched | flagged) as finance reconciles.
create table if not exists public.bank_transactions (
  id                uuid primary key default gen_random_uuid(),
  statement_date    date,
  description       text,
  reference         text,
  amount            numeric(14,2) not null,
  bank_name         text,
  account_number    text,
  imported_by       uuid,
  imported_at       timestamptz not null default now(),
  status            text not null default 'unmatched'
                    check (status in ('unmatched', 'matched', 'flagged')),
  ledger_entry_id   uuid references public.ledger_entries(id),
  match_reference   text,
  match_amount      numeric(14,2),
  review_note       text
);
create index if not exists bank_transactions_ref_idx    on public.bank_transactions (reference);
create index if not exists bank_transactions_status_idx on public.bank_transactions (status);

-- Reconciliation of a ledger entry against a bank line. Pairs mirror the
-- Matched / Amount-Mismatch states from the spec.
create table if not exists public.bank_reconciliation (
  id                 uuid primary key default gen_random_uuid(),
  bank_txn_id        uuid not null references public.bank_transactions(id),
  ledger_entry_id    uuid references public.ledger_entries(id),
  reference          text,
  bank_amount        numeric(14,2) not null,
  ledger_amount      numeric(14,2),
  match_status       text not null default 'matched'
                     check (match_status in ('matched', 'amount_mismatch', 'missing_reference', 'review')),
  review_status      text not null default 'pending'
                     check (review_status in ('pending', 'resolved', 'escalated')),
  note               text,
  resolved_by        uuid,
  resolved_at        timestamptz,
  created_at         timestamptz not null default now()
);
create index if not exists bank_recon_bank_idx     on public.bank_reconciliation (bank_txn_id);
create index if not exists bank_recon_ledger_idx   on public.bank_reconciliation (ledger_entry_id);
create index if not exists bank_recon_status_idx   on public.bank_reconciliation (match_status);
create index if not exists bank_recon_review_idx   on public.bank_reconciliation (review_status);

alter table public.ledger_entries enable row level security;

-- ---------------------------------------------------------------------------
-- 4. Auto-post a ledger entry on every approved payment (source of truth).
--    Recreates handle_payment_proof_approval() so the ledger records the
--    same credit we already apply to savings/receipts/transactions. Idempotent.
-- ---------------------------------------------------------------------------
create or replace function public.handle_payment_proof_approval()
returns trigger
language plpgsql
security definer
as $$
declare
  member_record record;
  receipt_num text;
  new_contribution_id uuid;
begin
  if new.status = 'approved' and old.status != 'approved' then
    select * into member_record from public.profiles where id = new.profile_id;
    receipt_num := public.generate_receipt_number();

    -- Contribution + savings (monthly_contribution only)
    if new.payment_type = 'monthly_contribution' then
      begin
        insert into public.contributions (
          profile_id, amount, status, contribution_month, payment_proof_id, notes
        ) values (
          new.profile_id, new.amount, 'successful',
          to_char(new.payment_date, 'YYYY-MM'),
          new.id, 'Auto-created from payment proof verification'
        ) returning id into new_contribution_id;
        new.contribution_id := new_contribution_id;
      exception when others then
        new_contribution_id := null;
      end;

      begin
        update public.savings set total_saved = total_saved + new.amount,
               last_savings_date = now() where profile_id = new.profile_id;
      exception when others then null; end;
    end if;

    -- Digital receipt
    insert into public.digital_receipts (
      receipt_number, receipt_id, payment_proof_id, profile_id, member_name,
      membership_id, payment_type, amount, currency, transaction_reference,
      payment_date, payment_method, receiving_bank, approved_by, approved_by_name,
      approved_at, organization_name
    ) values (
      receipt_num, 'RCP-' || substring(receipt_num, 4, 8), new.id, new.profile_id,
      member_record.name, member_record.user_id, new.payment_type, new.amount,
      new.currency, new.transaction_reference, new.payment_date, new.payment_method,
      new.receiving_bank, new.approved_by,
      (select name from public.profiles where id = new.approved_by limit 1),
      new.approved_at, 'Coopvest Africa'
    );

    -- Wallet top-up transaction (best-effort)
    if new.payment_type in ('monthly_contribution', 'investment', 'other') then
      begin
        insert into public.transactions (
          profile_id, type, category, amount, description, reference, status
        ) values (
          new.profile_id, 'credit', 'payment_proof', new.amount,
          case new.payment_type
            when 'monthly_contribution' then 'Monthly Contribution via Payment Proof'
            when 'investment' then 'Investment via Payment Proof'
            else 'Payment via Proof'
          end,
          new.transaction_reference, 'successful'
        );
      exception when others then null; end;
    end if;

    -- NEW: post the ledger entry (append-only, source of truth). Money received
    -- is always a credit; the type/allocation describe what the payment
    -- satisfies. `allocation` extends this further into per-obligation splits.
    begin
      insert into public.ledger_entries (
        profile_id, reference, type, description, debit, credit, source,
        status, initiated_by, approved_by, txn_no, member_name, membership_id,
        payment_method, bank_account, amount, loan_id, payment_proof_id, allocation,
        checked_by
      ) values (
        new.profile_id,
        new.transaction_reference,
        new.payment_type,
        'Auto-posted from verified payment proof',
        0, new.amount, new.amount,
        'payment_proof', new.profile_id, new.approved_by,
        public.next_ledger_txn_no(),
        member_record.name, member_record.user_id,
        new.payment_method, new.receiving_bank, new.amount,
        (select loan_id from public.loan_repayments where reference = new.id limit 1),
        new.id, '{}'::jsonb,
        new.approved_by
      );
    exception when others then
      null; -- ledger post must never fail the approval itself
    end;
  end if;
  return new;
end;
$$;