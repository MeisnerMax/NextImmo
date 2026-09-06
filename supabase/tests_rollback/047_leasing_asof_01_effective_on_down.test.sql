begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-ASOF-01 drops the shared predicate and returns the three
-- rent-roll helpers to their copied filter.
--
-- Reverting this package puts both defects back, and that is what the
-- assertions here establish: the predicate is gone, and the helpers ask about
-- `end_date` again. A rollback that left half the change behind would leave the
-- schema in a state no migration describes.
--
-- The leasing tables themselves belong to P2-D05 and must be untouched: this
-- package only ever read them.

select plan(12);

select hasnt_function('private', 'lease_is_effective_on',
  'the shared predicate is removed');

-- The three helpers survive -- this package replaced them, never created them.
select has_function('private', 'rent_roll_unit_rows',
  'the unit rows helper survives: P2-D05 owns it');
select has_function('private', 'rent_roll_currencies',
  'and the currency scan');
select has_function('private', 'rent_roll_unit_currencies',
  'and the per-unit currency scan, owned by P2-D05b');
select has_function('public', 'rent_roll_live',
  'and the read port above them');
select has_function('public', 'create_rent_roll_snapshot',
  'and the snapshot command that shares them');

-- They ask the old question again.
select ok(
  (select pg_get_functiondef(function.oid) like '%end_date%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private' and function.proname = 'rent_roll_unit_rows'),
  'the unit rows helper filters on end_date again'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_is_effective_on%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private' and function.proname = 'rent_roll_currencies'),
  'and the currency scan no longer calls the predicate'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_is_effective_on%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private' and function.proname = 'rent_roll_unit_currencies'),
  'nor does the per-unit scan'
);

-- The status-only helper is a different question and was never touched.
select has_function('private', 'lease_status_is_effective',
  'the AGG-004 occupancy helper survives untouched: it answers about now, not '
  'about a reference date'
);

-- The data this package only ever read.
select has_table('public', 'leases', 'the lease table survives');
select is(
  (select count(*)::integer
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'leases'
     and column_name in ('start_date', 'end_date', 'move_out_date', 'ended_at')),
  4,
  'including the four date columns the predicate read'
);

select * from finish();

rollback;
