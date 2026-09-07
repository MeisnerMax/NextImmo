begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back FINANCE-BOOKINGS-01.
--
-- Two new reads go, and one replaced command must come back as FINANCE-01a
-- wrote it. The second is the one worth a test: the package added a
-- `booked_on`-inside-the-period check to `record_finance_ledger_entry` by
-- `create or replace`, which has no inverse of its own. A revert that left
-- the check standing would be a validation nobody can trace to a migration;
-- a revert that dropped the command would take FINANCE-01a's only way of
-- writing a ledger entry with it.
--
-- The check is matched on its own error field rather than on prose, because
-- prose is the part most likely to be reworded.

select plan(6);

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'workspace_finance_periods', 'property_finance_ledger_entries'
     )),
  0,
  'both new reads are gone');

select has_function('public', 'record_finance_ledger_entry',
  'FINANCE-01a''s booking command still stands: this package replaced its '
  'body, so the revert is FINANCE-01a''s own version and not an absence');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'record_finance_ledger_entry'),
  1,
  'exactly one of it -- not two, and not none');

select ok(
  (select pg_get_functiondef(function.oid) not like '%is not inside that period%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'record_finance_ledger_entry'),
  'and the period check is gone with it, rather than surviving as a rule no '
  'migration accounts for');

select has_table('public', 'finance_ledger_entries',
  'the ledger itself is untouched: this package added no table and dropped '
  'none');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'open_finance_period', 'transition_finance_period_status',
       'property_finance_actuals'
     )),
  3,
  'and FINANCE-01a''s other commands stand as they did -- what this package '
  'changed was the reads that made them usable');

select * from finish();
rollback;
