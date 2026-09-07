begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back FINANCE-COST-TYPES-01.
--
-- This package changed one function it does not own, by `create or replace`,
-- and added nothing else. A revert therefore has exactly two obligations, and
-- the second is the one worth a test: P-2a's read must still stand, and it
-- must be P-2a's version — the one without the account version — rather than
-- an absence or a half-reverted definition.
--
-- Asserted through the payload rather than the signature, because a
-- `create or replace` leaves the signature identical either way.
--
-- The payload assertions match source text, which is the weaker kind of
-- check: they would also pass if the key were spelled differently or moved
-- into a comment. That is accepted here because the alternative — calling the
-- reverted function and inspecting its JSON — needs a workspace, a member and
-- an account, and a rollback test that builds a fixture is a rollback test
-- that can fail for reasons unrelated to the rollback. The four assertions
-- around them are properties of the replay rather than of this package, and
-- are kept as the frame: they say what the revert must not have taken with
-- it.

select plan(6);

select has_function('public', 'cost_allocation_rules',
  'P-2a''s read still stands: this package replaced its body, so the revert is '
  'P-2a''s own version and not an absence');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'cost_allocation_rules'),
  1,
  'exactly one of it -- not two, and not none');

-- Both keys, not one. The package adds `version` *and* `parent_account_id`,
-- and an earlier draft of this test asserted only the first while its message
-- called that "the whole of what this package added". A half-reverted body —
-- version gone, parent still there — passed it green, which is precisely the
-- state this file's own header says it exists to exclude.
select ok(
  (select pg_get_functiondef(function.oid) not like '%''version'', account.version%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'cost_allocation_rules'),
  'the account version is gone from the payload');

select ok(
  (select pg_get_functiondef(function.oid)
     not like '%''parent_account_id'', account.parent_account_id%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'cost_allocation_rules'),
  'and so is the parent — the package added two keys, so a revert that '
  'removed one and left the other is a third shape no test describes');

select has_table('public', 'finance_account_allocation_rules',
  'P-2a''s satellite is untouched: this package added no table and dropped '
  'none');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'create_finance_account', 'update_finance_account',
       'record_finance_ledger_entry', 'open_finance_period'
     )),
  4,
  'and FINANCE-01a''s commands stand as they did -- they were always there, '
  'and what this package changed was only the read that made them reachable');

select * from finish();
rollback;
