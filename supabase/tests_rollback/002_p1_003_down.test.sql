begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

select has_table('public', 'workspaces', 'P1-002 workspaces remains');
select has_table('public', 'user_profiles', 'P1-002 user_profiles remains');
select has_table('public', 'roles', 'P1-002 roles remains');
select has_table('public', 'permissions', 'P1-002 permissions remains');
select has_table('public', 'memberships', 'P1-002 memberships remains');
select has_table('public', 'role_permissions', 'P1-002 role_permissions remains');
select has_table('public', 'entity_scopes', 'P1-002 entity_scopes remains');
select has_table('public', 'audit_events', 'P1-002 audit_events remains');
select has_table('public', 'mutation_receipts', 'P1-002 mutation_receipts remains');

select hasnt_function('private', 'is_active_workspace_member', array['uuid']);
select hasnt_function('private', 'has_workspace_permission', array['uuid', 'text']);
select hasnt_function('private', 'is_current_active_membership', array['uuid', 'uuid']);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
  ),
  0,
  'P1-003 policies are removed'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
      and grantee in ('anon', 'authenticated')
  ),
  0,
  'P1-002 client table grants are restored'
);

select has_schema('private', 'P1-002 private schema remains');

select * from finish();

rollback;
