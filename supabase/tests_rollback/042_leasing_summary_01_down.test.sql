begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-SUMMARY-01 removes exactly one read function.
--
-- The package added no table, no column, no policy and no permission: every
-- number it publishes is computed from leasing data that P2-D05 already owned.
-- So the whole of this test is about what the revert must NOT touch. Leases,
-- units, their occupancy invariant and the lease.read policy are the record of
-- who occupies the building and what they pay; a revert that took any of it
-- with it would delete the tenancy, not the report about it.

select plan(11);

create or replace function pg_temp.has_public_function(p_name text)
returns boolean
language sql
as $$
  select exists (
    select 1 from pg_proc as function
    join pg_namespace as namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public' and function.proname = p_name
  );
$$;

select hasnt_function('public', 'property_leasing_summary',
  'the read port is removed');

-- The leasing tables and their shape survive untouched.
select has_table('public', 'leases', 'the lease table survives');
select has_table('public', 'units', 'the unit table survives');
select has_column('public', 'units', 'vacancy_since',
  'the vacancy start the summary measured from survives');
select has_column('public', 'units', 'area_sqm',
  'the area it summed survives');
select has_column('public', 'leases', 'notice_date',
  'the decision dates it counted survive');

-- AGG-004 is the invariant that makes "occupied" mean something. It predates
-- this package and outlives it.
select ok(
  (select count(*) = 2
   from pg_trigger as trigger
   join pg_class as class on class.oid = trigger.tgrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and trigger.tgname in (
       'units_occupancy_invariant', 'leases_occupancy_invariant'
     )),
  'the occupancy invariant survives on both sides'
);
select has_function('private', 'assert_unit_occupancy',
  'and so does the assertion behind it'
);

-- Access to leasing data was never this package's to grant or revoke.
select ok(
  (select count(*) > 0
   from pg_policies
   where schemaname = 'public'
     and tablename = 'leases'
     and policyname = 'leases_select_lease_read'),
  'the lease.read policy that predates this package is untouched'
);
select is(
  (select count(*)::integer from public.permissions
   where key in ('lease.summary.read', 'property.leasing.read')),
  0,
  'no leasing-summary permission was ever introduced, so none can linger'
);
-- The P2-D05 command surface is what actually writes a tenancy. The revert
-- names it rather than counting it, so a future package that removes one of
-- these has to say so here.
select ok(
  (select bool_and(pg_temp.has_public_function(name))
   from unnest(array[
     'create_lease', 'update_lease', 'transition_lease_status',
     'create_leasing_case', 'update_leasing_case',
     'transition_leasing_case_status'
   ]) as name),
  'the six P2-D05 leasing commands survive: this package only ever read them'
);

select * from finish();

rollback;
