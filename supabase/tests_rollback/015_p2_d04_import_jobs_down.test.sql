begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- The increment-3 import_jobs / search_index aggregates are removed by the down
-- path…
select hasnt_table('public', 'import_jobs', 'import_jobs is removed by the down path');
select hasnt_table('public', 'search_index', 'search_index is removed by the down path');

select is(
  (select count(*)::integer from pg_type t
   join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typname = 'import_job_status'),
  0,
  'the import_job_status enum is removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'create_import_job', 'update_import_job', 'transition_import_job_status',
       'reindex_search_entry', 'remove_search_entry'
     )),
  0,
  'every import / search RPC is removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'import_job_snapshot', 'search_index_snapshot', 'import_job_status_can_transition'
     )),
  0,
  'the increment-3 private helpers are removed'
);

-- …while the increment-1 and increment-2 aggregates it builds on survive.
select has_table(
  'public', 'tasks',
  'the increment-2 tasks aggregate survives the increment-3 rollback'
);
select has_table(
  'public', 'notifications',
  'the increment-2 notifications aggregate survives the increment-3 rollback'
);
select has_table(
  'public', 'domain_events',
  'the increment-1 outbox survives the increment-3 rollback'
);

select * from finish();

rollback;
