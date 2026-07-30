begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- P2-D05 leasing_operations artifacts are removed on the down path.
select hasnt_table('public', 'units', 'P2-D05 units table is removed');
select hasnt_table('public', 'leases', 'P2-D05 leases table is removed');
select hasnt_type('public', 'unit_status', 'P2-D05 unit_status enum is removed');
select hasnt_type('public', 'lease_status', 'P2-D05 lease_status enum is removed');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'leasing_command_gate', 'claim_leasing_mutation', 'finish_leasing_mutation',
       'unit_snapshot', 'lease_snapshot', 'lease_status_is_effective',
       'unit_effective_lease_count', 'assert_unit_occupancy',
       'units_assert_occupancy', 'leases_assert_occupancy',
       'sync_unit_occupancy', 'lease_status_transition_allowed',
       'leasing_property_in_workspace'
     )),
  0,
  'P2-D05 private helpers are removed'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'create_unit', 'update_unit', 'transition_unit_status',
       'create_lease', 'update_lease', 'transition_lease_status'
     )),
  0,
  'P2-D05 leasing RPCs are removed'
);

-- The layers underneath remain intact.
select has_table('public', 'properties', 'P1-004 properties table remains');
select has_table('public', 'parties', 'P2-D02 parties table remains');
select has_function(
  'private', 'has_workspace_permission', array['uuid', 'text'],
  'P1-003 permission helper remains'
);

select * from finish();

rollback;
