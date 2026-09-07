begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-COMPONENTS-01c.
--
-- One function body is replaced and nothing is created, so — as with 01b,
-- PROPERTY-ACTIVITY-03 and FINANCE-01c — there is no object whose absence
-- proves the revert. The read must still be there, still answer in the
-- envelope 01b established, and must have stopped reporting coverage.
--
-- The last of those is the assertion that matters. A revert that kept the
-- coverage block while losing the rest, or lost it while keeping a stale
-- comment claiming otherwise, would leave a contract no migration describes —
-- and a client that reads `entity.coverage` would then silently see every
-- lease as complete, which is the exact failure DEC-029 exists to prevent.

select plan(7);

select has_function('public', 'lease_components_as_of',
  'the as-of read survives: 01c replaced it, never created it');

select is(
  (select pg_get_function_result(function.oid) from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_components_as_of'),
  'jsonb',
  'and still answers in 01b''s envelope rather than reverting two packages');

select ok(
  (select pg_get_functiondef(function.oid) not like '%coverage%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_components_as_of'),
  'coverage is gone from the body -- not merely absent from one branch of it');

select ok(
  (select pg_get_functiondef(function.oid) like '%as_of_date%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_components_as_of'),
  'while the as-of date 01b introduced is still reported');

select ok(
  (select function.prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_components_as_of'),
  'the reverted body is still SECURITY DEFINER');

-- The invariants this package leaned on belong to migration 54 and must
-- survive its revert untouched.
select ok(
  (select count(*) > 0 from pg_constraint
   where conrelid = 'public.lease_components'::regclass
     and contype = 'x' and conname = 'lease_components_no_overlap'),
  'the overlap constraint is LEASING-COMPONENTS-01''s and stays: the write '
  'half of DEC-029 does not depend on the reporting half');

select has_function('private', 'lease_is_effective_on',
  'and so does LEASING-ASOF-01''s predicate, which this read only borrowed');

select * from finish();
rollback;
