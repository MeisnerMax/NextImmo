begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back WARM-RENT-01 (P-7).
--
-- One function is created and nothing else, so this revert is the plain kind:
-- the function is gone and everything it read from stays.
--
-- What that "everything" is matters, though. Warm rent computes from
-- `lease_components` and borrows `private.lease_is_effective_on`; neither is
-- its property, and a revert that took either would remove the rent components
-- themselves or reopen the as-of defect LEASING-ASOF-01 closed. The three
-- assertions at the bottom are there because a future author reverting this
-- package should see immediately what it does not own.

select plan(6);

select hasnt_function('public', 'warm_rent_as_of',
  'the warm rent read is gone -- this package created it and nothing else');

select has_table('public', 'lease_components',
  'the components stay: LEASING-COMPONENTS-01 owns them, warm rent only reads');

select has_function('private', 'lease_is_effective_on',
  'and LEASING-ASOF-01''s predicate stays -- reverting it here would reopen '
  'the defect that lets an ended lease report rent');

select has_function('public', 'lease_components_as_of',
  'as does the component read, which answers a different question and is not '
  'part of this package');

select ok(
  (select count(*) > 0 from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname = 'lease_component_type'),
  'the component type enum survives: warm rent named three of its members but '
  'created none of them');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname like 'warm%'),
  0,
  'and nothing warm-rent-shaped is left behind under another name');

select * from finish();
rollback;
