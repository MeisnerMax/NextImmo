begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

select has_table('public', 'properties', 'P1-011 rollback keeps properties');
select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-011 rollback keeps the property update RPC'
);
select is(
  (select count(*)::integer
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'properties'),
  0,
  'P1-011 rollback removes properties from Realtime publication'
);

select * from finish();

rollback;
