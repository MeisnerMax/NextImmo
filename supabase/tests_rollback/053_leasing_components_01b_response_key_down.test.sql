begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-COMPONENTS-01b.
--
-- Two function bodies are replaced and nothing is created, so — as with
-- PROPERTY-ACTIVITY-02, PROPERTY-ACTIVITY-03 and FINANCE-01c — there is no
-- object whose absence proves the revert. Both functions must still exist,
-- with their grants and their SECURITY DEFINER property, and must be back to
-- answering `data`.
--
-- Asserting that the inconsistency is *back* is the point of a rollback test
-- like this one. A revert that kept half the change would leave the schema in
-- a state no migration describes, which is worse than either version.

select plan(8);

create or replace function pg_temp.body_of(p_schema text, p_name text)
returns text
language sql
as $$
  select function.prosrc
  from pg_proc as function
  join pg_namespace as namespace on namespace.oid = function.pronamespace
  where namespace.nspname = p_schema and function.proname = p_name;
$$;

select has_function('public', 'create_lease_component',
  'the create command survives: 01b replaced it, never created it');
select has_function('private', 'apply_lease_component_update',
  'as does the shared write path');

select ok(
  pg_temp.body_of('public', 'create_lease_component') like '%''data''%',
  'the create command answers `data` again -- the divergence from every other '
  'leasing command is restored, which is what reverting this package means');
select ok(
  pg_temp.body_of('private', 'apply_lease_component_update') like '%''data''%',
  'and so does the shared write path');

-- The wrappers were never touched by 01b and must be untouched by its revert.
select has_function('public', 'update_lease_component',
  'the update wrapper is unaffected in both directions');
select has_function('public', 'close_lease_component',
  'and so is the close wrapper');

select ok(
  (select function.prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'create_lease_component'),
  'the reverted body is still SECURITY DEFINER');

select is(
  (select count(*)::integer
   from information_schema.role_routine_grants
   where routine_schema = 'private'
     and routine_name = 'apply_lease_component_update'
     and grantee in ('anon', 'authenticated', 'PUBLIC')),
  0, 'and the private helper is still unreachable from any client role');

select * from finish();
rollback;
