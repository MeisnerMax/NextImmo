begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back SERVICE-CHARGE-UNIT-POOL-01.
--
-- This package replaced one function body by `create or replace`, which has no
-- inverse of its own. A revert that dropped the function would take
-- SERVICE-CHARGE-PREVIEW-01's only settlement read with it; a revert that left
-- the new body standing would be a behaviour no migration accounts for.
--
-- The behavioural marker is matched on the phrase the corrected branch
-- introduces, and it is matched in BOTH directions: the single-unit assignment
-- must be gone, and the three scopes that migration 71 already refused must
-- still be refused — otherwise a revert that emptied the whole branch would
-- satisfy the first assertion and quietly widen the defect instead of
-- restoring the previous one.

select plan(6);

select has_function(
  'public', 'property_service_charge_preview',
  array['uuid', 'uuid', 'date', 'date'],
  'the settlement preview still stands: this package replaced its body, so the '
  'revert is migration 71''s version and not an absence');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  1,
  'exactly one of it -- not two, and not none');

select ok(
  (select pg_get_functiondef(function.oid)
            not like '%covers exactly one unit%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  'the single-unit assignment is gone with the migration, rather than '
  'surviving as behaviour no migration accounts for');

select ok(
  (select pg_get_functiondef(function.oid)
            like '%pool_scope_unresolvable%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  'while migration 71''s own refusal for building, entrance and meter group '
  'is still there -- paired with the assertion above, so a revert that emptied '
  'the whole branch cannot pass');

select ok(
  (select pg_get_functiondef(function.oid) like '%basis_changed_in_window%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  'and so is the refusal that carries the open modelling question');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef),
  110,
  'the public SECURITY DEFINER inventory is unchanged at 110: this package '
  'replaced a function and added none');

select * from finish();
rollback;
