begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

-- DEBT-012 delete-marker artifacts are removed on the down path.
select hasnt_column('public', 'properties', 'deleted_by', 'DEBT-012 deleted_by column is removed');
select ok(
  not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.properties'::regclass
      and tgname = 'properties_apply_delete_marker'
  ),
  'DEBT-012 delete-marker trigger is removed'
);
select hasnt_function(
  'private',
  'properties_apply_delete_marker',
  '{}'::text[],
  'DEBT-012 delete-marker trigger function is removed'
);

-- The P1-004 property contract underneath remains intact.
select has_table('public', 'properties', 'P1-004 properties remains');
select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-004 update RPC remains'
);

select * from finish();

rollback;
