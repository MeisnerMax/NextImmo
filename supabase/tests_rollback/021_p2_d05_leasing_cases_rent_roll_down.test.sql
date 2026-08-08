begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- P2-D05 increment 2 artifacts are removed on the down path.
select hasnt_table('public', 'leasing_cases', 'P2-D05 leasing_cases table is removed');
select hasnt_table('public', 'rent_roll_snapshots', 'P2-D05 rent_roll_snapshots table is removed');
select hasnt_table('public', 'rent_roll_snapshot_lines', 'P2-D05 rent_roll_snapshot_lines table is removed');
select hasnt_type('public', 'leasing_case_status', 'P2-D05 leasing_case_status enum is removed');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'leasing_case_snapshot', 'leasing_case_stage_rank',
       'leasing_case_status_is_terminal', 'leasing_case_transition_allowed',
       'reject_rent_roll_change', 'rent_roll_currencies',
       'rent_roll_snapshot_document', 'rent_roll_snapshot_header',
       'rent_roll_unit_rows'
     )),
  0,
  'P2-D05 increment 2 private helpers are removed'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'create_leasing_case', 'update_leasing_case',
       'transition_leasing_case_status', 'create_rent_roll_snapshot'
     )),
  0,
  'P2-D05 increment 2 RPCs are removed'
);

-- Increment 1 is a SEPARATE migration and must survive this rollback intact.
-- Increment 2 reuses its command plumbing rather than owning it, so a down path
-- that dropped the shared trio would silently break units and leases.
select has_table('public', 'units', 'increment 1 units table remains');
select has_table('public', 'leases', 'increment 1 leases table remains');
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'leasing_command_gate', 'claim_leasing_mutation', 'finish_leasing_mutation'
     )),
  3,
  'the shared leasing command trio owned by increment 1 remains'
);
select has_table('public', 'properties', 'P1-004 properties table remains');

select * from finish();

rollback;
