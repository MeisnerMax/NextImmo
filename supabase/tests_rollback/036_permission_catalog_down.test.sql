begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PERMISSION-CATALOG-02 must remove exactly the two seeders and
-- nothing else: the identity baseline (roles/permissions/role_permissions
-- tables, memberships), TASK-QUERY-01 and NOTIFICATION-EMITTER-01 all predate
-- this package and stay intact. Because the replayed schema is empty, the
-- catalog tables must simply hold no rows — the migration's own seeding is
-- workspace-driven and an empty database seeds nothing.

select plan(8);

select hasnt_function('private', 'ensure_permission_catalog',
  'the catalog seeder is removed');
select hasnt_function('private', 'seed_workspace_role_catalog',
  'the workspace role seeder is removed');

-- The identity baseline survives untouched.
select has_table('public', 'permissions', 'the permissions table survives');
select has_table('public', 'roles', 'the roles table survives');
select has_table('public', 'role_permissions', 'the role_permissions table survives');
select is(
  (select count(*)::integer from public.permissions),
  0,
  'no catalog rows linger after the rollback replay'
);

-- The two neighbouring packages stay intact.
select has_column('public', 'tasks', 'property_id',
  'the TASK-QUERY-01 roll-up survives');
select is(
  (select count(*)::integer from pg_trigger
   where tgname = 'tasks_emit_notifications'),
  1,
  'the NOTIFICATION-EMITTER-01 trigger survives'
);

select * from finish();

rollback;
