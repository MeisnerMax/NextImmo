begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

-- Rolling back PH-01 must remove the scope primitives and the allowlist, and
-- must leave the P1-015 AAL2 wrapper exactly as it was -- the migration
-- replaced that function's body rather than moving it, so a rollback that
-- forgets it would silently drop AAL2 enforcement.

select hasnt_function('private', 'has_entity_scope', array['uuid', 'text', 'uuid'],
  'the entity scope primitive is removed');

select hasnt_function('private', 'has_scoped_entity_permission',
  array['uuid', 'text', 'text', 'uuid'],
  'the scoped permission primitive is removed');

select is(
  (select count(*)::integer
   from pg_constraint
   where conname = 'entity_scopes_supported_entity_type_check'),
  0,
  'the entity_type allowlist constraint is removed'
);

-- The pre-PH-01 policy checked the workspace permission only.
select is(
  (select pg_get_expr(polqual, polrelid)
   from pg_policy
   where polname = 'properties_select_property_read'),
  'private.has_workspace_permission(workspace_id, ''property.read''::text)',
  'the property SELECT policy is back to the workspace-permission-only form'
);

select has_function('public', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'the public property update entry point survives the rollback');

select is(
  (select count(*)::integer
   from pg_proc
   join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
   where pg_namespace.nspname = 'public'
     and pg_proc.proname = 'update_property'
     and pg_get_functiondef(pg_proc.oid) like '%AAL2 is required for property updates%'
     and pg_get_functiondef(pg_proc.oid) not like '%has_scoped_entity_permission%'),
  1,
  'the AAL2 wrapper is restored without the scope guard'
);

select * from finish();

rollback;
