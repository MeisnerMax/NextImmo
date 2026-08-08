begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- Rolling back only the realtime step must leave the aggregates themselves
-- intact — the publication membership is a separate migration for exactly that
-- reason (mirrors 020_p2_d05_realtime_down / 012_p2_d03_realtime_down).
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename in ('leasing_cases', 'rent_roll_snapshots')),
  0,
  'P2-D05 increment 2 aggregates are no longer published for realtime'
);
select has_table('public', 'leasing_cases', 'the leasing_cases table survives the realtime rollback');
select has_table('public', 'rent_roll_snapshots', 'the rent_roll_snapshots table survives the realtime rollback');

-- Increment 1's publication membership is a different migration and is still
-- applied at this point.
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename in ('units', 'leases')),
  2,
  'increment 1 units and leases stay published'
);

select * from finish();

rollback;
