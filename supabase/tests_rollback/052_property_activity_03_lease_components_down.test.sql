begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-ACTIVITY-03 (V-2a).
--
-- This package replaces two function bodies and creates nothing, so there is
-- no object whose absence proves the revert — the same shape as
-- PROPERTY-ACTIVITY-02's and FINANCE-01c's rollbacks. Both functions must
-- still be there, with the same properties, and **without** the component
-- clause. Asserting that the component is unreachable again is the point: a
-- revert that kept half the change would leave the schema in a state no
-- migration describes.
--
-- The other half is what must survive. The finance clause is
-- PROPERTY-ACTIVITY-02's and the leasing clauses are 01's; a revert that swept
-- up everything in the same neighbourhood would silently take two other
-- packages with it, and the timeline would quietly lose rows nobody was
-- looking for.

select plan(12);

-- ---------------------------------------------------------------------------
-- The change is gone
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where entity_type = 'lease_component'),
  0, 'the component type is out of the taxonomy again');

select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_component%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'property_activity_rows'),
  'and out of the row resolution, body and all -- not merely filtered out '
  'somewhere downstream');

-- ---------------------------------------------------------------------------
-- Everything else survives
-- ---------------------------------------------------------------------------

select has_function('private', 'property_activity_taxonomy',
  'the taxonomy function survives: this package replaced it, never created it');
select has_function('private', 'property_activity_rows',
  'as does the row resolution');
select has_function('public', 'property_activity',
  'and the read port, which this package never touched at all');

select is(
  (select count(*)::integer from private.property_activity_taxonomy()),
  15,
  'the taxonomy is back to its fifteen entries -- one fewer than with the '
  'component, and no others lost on the way');

select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where entity_type = 'finance_ledger_entry' and domain = 'finance'),
  1, 'PROPERTY-ACTIVITY-02''s finance entry is untouched');

select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where domain = 'leasing'),
  4,
  'and leasing is back to unit, lease, leasing_case and rent_roll_snapshot');

select ok(
  (select pg_get_functiondef(function.oid) like '%finance_ledger_entries%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'property_activity_rows'),
  'the finance clause is still in the row resolution');

select ok(
  (select pg_get_functiondef(function.oid) like '%rent_roll_snapshots%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'property_activity_rows'),
  'and so is the rent roll clause it was inserted after');

select ok(
  (select function.prosecdef
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'property_activity_rows'),
  'the reverted body is still SECURITY DEFINER: the revert must not change '
  'who it runs as');

select is(
  (select count(*)::integer
   from information_schema.role_routine_grants
   where routine_schema = 'private'
     and routine_name in ('property_activity_taxonomy', 'property_activity_rows')
     and grantee in ('anon', 'authenticated', 'PUBLIC')),
  0, 'and no client role gained execute on either of them');

select * from finish();
rollback;
