begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back COST-POOLS-ALLOCATION-KEYS-01 (P-2b).
--
-- Two things make this revert less routine than the ones before it.
--
-- **Two enums and an exclusion constraint.** A type left behind blocks the
-- next forward replay with "type already exists", which turns a revert into a
-- wedge; both are checked by name.
--
-- **This migration replaced a function it does not own.** P-2b re-creates
-- `public.set_cost_allocation_rule` to move it onto the finance command
-- plumbing. A `create or replace` has no inverse of its own, so the revert
-- relies on the replay rebuilding P-2a's version -- and the assertion here is
-- that the function still stands afterwards rather than having been dropped
-- along with the package that last touched it. That is the failure mode worth
-- catching: a rollback that takes a neighbouring package's write surface with
-- it is silent until someone tries to use it.

select plan(9);

select hasnt_table('public', 'cost_pools', 'the pool table is gone');
select hasnt_table('public', 'allocation_keys', 'and the key table');

select ok(
  (select count(*) = 0 from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname in ('cost_pool_scope', 'allocation_basis')),
  'both enums with them -- a type left behind blocks the next forward replay');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'workspace_cost_pools', 'allocation_keys_as_of',
       'upsert_cost_pool', 'upsert_allocation_key'
     )),
  0,
  'all four public functions are gone');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'cost_pool_snapshot', 'allocation_key_snapshot',
       'allocation_basis_resolution'
     )),
  0,
  'and the three private helpers with them');

-- The neighbouring package. P-2b replaced its command; the revert must leave
-- P-2a whole rather than taking its write surface with it.
select has_function('public', 'set_cost_allocation_rule',
  'P-2a''s command still stands: this package replaced its body, and a revert '
  'of the replacement is P-2a''s own version, not an absence');

select has_table('public', 'finance_account_allocation_rules',
  'with its satellite table');

select has_table('public', 'units',
  'the unit records stay -- this package only read them as a distribution '
  'basis and altered nothing');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and (function.proname like '%cost_pool%'
          or function.proname like '%allocation_key%'
          or function.proname like '%allocation_basis%')),
  0,
  'and nothing pool- or key-shaped is left behind under another name');

select * from finish();
rollback;
