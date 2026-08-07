begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

-- Rolling back only the realtime step must leave the leasing contract itself
-- intact — the publication membership is a separate migration for exactly that
-- reason (mirrors 012_p2_d03_realtime_down / 010_p2_d02_realtime_down).
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename in ('units', 'leases')),
  0,
  'P2-D05 leasing tables are no longer published for realtime'
);
select has_table('public', 'units', 'the units table survives the realtime rollback');
select has_table('public', 'leases', 'the leases table survives the realtime rollback');

select * from finish();

rollback;
