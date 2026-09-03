begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back TASK-QUERY-01 must remove the roll-up column with its triggers
-- and indexes, the count RPC, and every search-index projection hook — and must
-- leave the P2-D04 baseline untouched: the original protected-columns trigger,
-- the five platform RPCs, and the search_index table itself (which predates
-- this package and only gained writers here).

select plan(10);

select hasnt_column('public', 'tasks', 'property_id',
  'the roll-up column is removed');

select hasnt_function('private', 'task_property_rollup',
  'the roll-up resolver is removed');

select hasnt_function('public', 'count_tasks',
  'the count RPC is removed');

select is(
  (select count(*)::integer from pg_indexes
   where schemaname = 'public'
     and indexname in ('tasks_property_idx', 'tasks_due_idx')),
  0,
  'both query indexes are removed'
);

select is(
  (select count(*)::integer from pg_trigger
   where tgname in (
     'tasks_property_rollup',
     'properties_search_index_sync', 'units_search_index_sync',
     'leases_search_index_sync', 'parties_search_index_sync',
     'maintenance_tickets_search_index_sync', 'capex_projects_search_index_sync'
   )),
  0,
  'the roll-up trigger and all six projection triggers are removed'
);

-- Exactly one, not zero: the P2-D04 protected-columns trigger predates this
-- package and must survive the rollback.
select is(
  (select count(*)::integer from pg_trigger
   where tgrelid = 'public.tasks'::regclass
     and tgname = 'tasks_protected_columns'),
  1,
  'the original protected-columns trigger is back in force'
);

-- And it no longer protects the removed column.
select ok(
  (select pg_get_triggerdef(oid) !~ 'property_id' from pg_trigger
   where tgrelid = 'public.tasks'::regclass
     and tgname = 'tasks_protected_columns'),
  'the restored protected-columns list carries no property_id'
);

-- The snapshot is back to the audited P2-D04 shape.
select ok(
  (select pg_get_functiondef(function.oid) !~ 'property_id'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private' and function.proname = 'task_snapshot'),
  'the task snapshot no longer names the roll-up'
);

-- The definer inventory is back at the pre-package count.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef),
  65,
  'the public SECURITY DEFINER inventory is back at 65'
);

-- The projection's read surface predates this package and stays.
select has_table('public', 'search_index', 'the search index table itself survives');

select * from finish();

rollback;
