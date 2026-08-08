begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

select hasnt_function(
  'private', 'has_entity_scope', array['uuid', 'text', 'uuid'],
  'entity-scope helper is removed'
);
select hasnt_function(
  'private', 'has_scoped_entity_permission',
  array['uuid', 'text', 'text', 'uuid'],
  'scoped permission helper is removed'
);
select ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entity_scopes'::regclass
      and conname = 'entity_scopes_supported_entity_type_check'
  ),
  'supported-type constraint is removed'
);
select has_function(
  'public', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'original public property command is restored'
);
select hasnt_function(
  'private', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'private command implementation is removed'
);
select ok(
  pg_get_expr(policy.polqual, policy.polrelid) not like '%has_scoped_entity_permission%',
  'property policy returns to workspace permission only'
)
from pg_policy as policy
where policy.polrelid = 'public.properties'::regclass
  and policy.polname = 'properties_select_property_read';

select * from finish();
rollback;
