begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

-- Rolling back the realtime step removes the publication membership only; the
-- aggregate itself belongs to the previous migration and must survive.
select is(
  (select count(*)::integer
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'valuation_cases'),
  0,
  'valuation_cases is no longer published for realtime'
);

select has_table(
  'public', 'valuation_cases',
  'the valuation aggregate survives the realtime rollback'
);

select * from finish();

rollback;
