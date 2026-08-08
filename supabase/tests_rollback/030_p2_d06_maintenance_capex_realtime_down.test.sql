begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- Rolling back only the realtime step must leave both tables themselves
-- intact — the publication membership is a separate migration for exactly
-- that reason (mirrors 028_p2_d05a_operations_signals_realtime_down).
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename = 'maintenance_tickets'),
  0,
  'maintenance_tickets is no longer published for realtime'
);
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename = 'capex_projects'),
  0,
  'capex_projects is no longer published for realtime'
);
select has_table('public', 'maintenance_tickets',
  'the ticket table survives the realtime rollback');
select has_table('public', 'capex_projects',
  'the project table survives the realtime rollback');

select * from finish();

rollback;
