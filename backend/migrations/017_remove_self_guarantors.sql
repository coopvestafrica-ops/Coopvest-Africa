-- Remove rows where a borrower stands as guarantor on their own loan.
-- Such rows should never exist; this cleans up data created before the
-- backend guard was added (guarantor.js: borrowers are now rejected with
-- "You cannot stand as a guarantor for your own loan.").
DELETE FROM public.loan_guarantors lg
USING public.loans l
WHERE lg.loan_id = l.id
  AND lg.guarantor_id = l.profile_id;
