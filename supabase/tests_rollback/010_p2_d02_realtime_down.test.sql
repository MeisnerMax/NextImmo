begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

-- Rolling back the party realtime migration removes only the publication entry.
select is(
  (select count(*)::integer
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'parties'),
  0,
  'P2-D02 rollback removes parties from the Realtime publication'
);

-- The P2-D02 contract underneath remains intact.
select has_table('public', 'parties', 'P2-D02 rollback keeps the parties table');
select has_function(
  'public', 'create_party',
  array['uuid', 'text', 'text', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'text'],
  'P2-D02 rollback keeps the create_party RPC'
);

select * from finish();

rollback;
