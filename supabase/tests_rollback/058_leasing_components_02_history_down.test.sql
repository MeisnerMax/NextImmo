begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-COMPONENTS-02 (V-2b).
--
-- One function, no schema, no data. The revert is plain — and that is the
-- point worth checking, because this package reads a table full of contract
-- terms that somebody typed in. Losing the history read costs a screen; losing
-- `lease_components` would cost the rents themselves.
--
-- The exclusion constraint gets its own assertion. It is what makes "exactly
-- one period is in force" true, and it belongs to LEASING-COMPONENTS-01. A
-- revert that dropped it would leave the table accepting two rents for the
-- same day, and nothing in the schema would say which one to bill.

select plan(6);

select hasnt_function('public', 'lease_component_history',
  'the history read is gone -- this package created it and nothing else');

select has_table('public', 'lease_components',
  'the components stay: LEASING-COMPONENTS-01 owns them, the history only '
  'reads');

select ok(
  (select count(*) > 0
   from pg_constraint
   where conname = 'lease_components_no_overlap'),
  'and so does the exclusion constraint. It is what makes exactly one period '
  'per type current; without it the table would accept two rents for the same '
  'day and nothing would say which to bill');

select has_function('public', 'lease_components_as_of',
  'the as-of read stays -- it answers a different question and predates this '
  'package');

select has_function('public', 'warm_rent_as_of',
  'as does warm rent, which computes from the same rows');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname like '%component_history%'),
  0,
  'and nothing history-shaped is left behind under another name');

select * from finish();
rollback;
