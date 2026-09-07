begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back SUPPLIER-DETAILS-01 (P-3).
--
-- One new function and one recreated, so the revert has the same shape of risk
-- ALERT-READER-01 had: `workspace_maintenance_tickets` was dropped and
-- recreated with a fifth parameter, and a revert that failed to restore the
-- four-parameter version would leave the maintenance list callable only with
-- an argument the reverted client does not send.
--
-- Checking that the function *exists* would not catch that. The argument count
-- is checked instead — by `pronargs` rather than by rendering the signature,
-- because `pg_get_function_identity_arguments` includes parameter names and
-- would make this assertion fail on a rename that changed nothing.
--
-- The satellite table and its snapshot function belong to P2-D02 and must
-- survive: this package gave the register a write path, it did not create the
-- register.

select plan(7);

select hasnt_function('public', 'update_contractor_details',
  'the dedicated update is gone');

select has_table('public', 'party_contractor_details',
  'the register stays: P2-D02 owns it, this package only gave it a write path');

select has_function('private', 'contractor_details_snapshot',
  'and so does the snapshot function, which assign_party_role still uses');

select has_function('public', 'assign_party_role',
  'the role assignment stays -- it was deliberately left alone, and it is the '
  'only remaining way to write the satellite once this is reverted');

select has_function('public', 'workspace_maintenance_tickets',
  'the workspace ticket list stays');

select is(
  (select pronargs::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_maintenance_tickets'),
  4,
  'and it is back to four parameters. Existence alone would not prove it: a '
  'revert that dropped this package''s version without restoring the previous '
  'one leaves a list nothing can call the way the reverted client calls it');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_maintenance_tickets'),
  1,
  'exactly one of it -- not the old and the new sitting side by side as an '
  'ambiguous overload');

select * from finish();
rollback;
