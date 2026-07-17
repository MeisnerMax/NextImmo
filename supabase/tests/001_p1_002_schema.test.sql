begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

select has_schema('private', 'private schema exists');

select has_table('public', 'workspaces', 'workspaces exists');
select has_table('public', 'user_profiles', 'user_profiles exists');
select has_table('public', 'roles', 'roles exists');
select has_table('public', 'permissions', 'permissions exists');
select has_table('public', 'memberships', 'memberships exists');
select has_table('public', 'role_permissions', 'role_permissions exists');
select has_table('public', 'entity_scopes', 'entity_scopes exists');
select has_table('public', 'audit_events', 'audit_events exists');
select has_table('public', 'mutation_receipts', 'mutation_receipts exists');
select has_column('public', 'memberships', 'role_id', 'membership has exactly one role column');
select col_not_null('public', 'memberships', 'role_id', 'membership role is required');
select has_column('public', 'audit_events', 'mutation_id', 'audit has mutation id');
select col_not_null('public', 'audit_events', 'correlation_id', 'audit correlation id is required');
select has_column('public', 'mutation_receipts', 'request_hash', 'receipt has request hash');
select col_type_is('public', 'mutation_receipts', 'request_hash', 'bytea', 'request hash is bytea');

select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.roles'::regclass and conname = 'roles_workspace_id_key_unique'),
  'role key is unique per workspace'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.memberships'::regclass and conname = 'memberships_workspace_user_unique'),
  'membership is unique per workspace and user'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.memberships'::regclass and conname = 'memberships_workspace_role_fkey'),
  'membership role FK includes workspace'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.role_permissions'::regclass and conname = 'role_permissions_workspace_role_fkey'),
  'role permission FK includes workspace'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.entity_scopes'::regclass and conname = 'entity_scopes_workspace_membership_fkey'),
  'entity scope FK includes workspace'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.mutation_receipts'::regclass and conname = 'mutation_receipts_workspace_mutation_unique'),
  'mutation id is unique per workspace'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.audit_events'::regclass and conname = 'audit_events_workspace_mutation_unique'),
  'audit mutation id is unique per workspace'
);

select ok(
  not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
      and c.contype = 'f'
      and c.confdeltype not in ('r', 'c')
  ),
  'all foreign keys use RESTRICT except the allowed auth user cascade'
);

select ok(
  (select c.confdeltype = 'c'
   from pg_constraint c
   join pg_class t on t.oid = c.conrelid
   join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public'
     and t.relname = 'user_profiles'
     and c.conname = 'user_profiles_user_id_fkey'),
  'user profile auth user FK cascades'
);

select ok(
  not exists (
    select 1
    from pg_constraint c
    join pg_class source_table on source_table.oid = c.conrelid
    join pg_namespace source_schema on source_schema.oid = source_table.relnamespace
    join pg_class target_table on target_table.oid = c.confrelid
    join pg_namespace target_schema on target_schema.oid = target_table.relnamespace
    join unnest(c.conkey) as source_key(attnum) on true
    join pg_attribute source_column
      on source_column.attrelid = source_table.oid
      and source_column.attnum = source_key.attnum
    where c.contype = 'f'
      and source_schema.nspname = 'public'
      and target_schema.nspname = 'auth'
      and target_table.relname = 'users'
      and source_column.attname in ('created_by', 'updated_by', 'actor_user_id')
  ),
  'audit actor and provenance columns have no auth user foreign keys'
);

select ok(bool_and(c.relrowsecurity and c.relforcerowsecurity), 'all public baseline tables enable and force RLS')
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
    'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
  );

select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'public'
     and tablename in (
       'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
       'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
     )
     and cmd <> 'SELECT'),
  0,
  'baseline has no client mutation policies'
);

select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in (
       'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
       'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
     )
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles have no table mutation grants'
);

insert into public.workspaces (id, key, name)
values ('10000000-0000-0000-0000-000000000001', 'test-workspace', 'Test Workspace');

select throws_ok(
  $$insert into public.roles (workspace_id, key, name)
    values ('10000000-0000-0000-0000-000000000001', 'Invalid Key', 'Invalid')$$,
  '23514',
  null,
  'role keys must be normalized'
);

select throws_ok(
  $$insert into public.permissions (key, name) values ('property..read', 'Invalid')$$,
  '23514',
  null,
  'permission keys must be normalized'
);

select throws_ok(
  $$insert into public.mutation_receipts (workspace_id, mutation_id, request_hash)
    values (
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000001',
      decode('abcd', 'hex')
    )$$,
  '23514',
  null,
  'receipt request hash must contain 32 bytes'
);

insert into public.mutation_receipts (id, workspace_id, mutation_id, request_hash)
values (
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  decode(repeat('ab', 32), 'hex')
);

select throws_ok(
  $$insert into public.mutation_receipts (workspace_id, mutation_id, request_hash)
    values (
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000001',
      decode(repeat('cd', 32), 'hex')
    )$$,
  '23505',
  null,
  'mutation id is unique within a workspace'
);

select throws_ok(
  $$update public.mutation_receipts
    set request_hash = decode(repeat('cd', 32), 'hex')
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '23000',
  null,
  'receipt hash is immutable'
);

select throws_ok(
  $$update public.mutation_receipts
    set workspace_id = '10000000-0000-0000-0000-000000000002'
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '23000',
  null,
  'receipt workspace is immutable'
);

insert into public.audit_events (
  id,
  workspace_id,
  actor_type,
  actor_identifier,
  action,
  entity_type,
  source,
  correlation_id,
  mutation_id,
  created_at,
  updated_at,
  version
) values (
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'system',
  'pgtap',
  'schema.test',
  'workspace',
  'database',
  '60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '2026-01-01 00:00:00+00',
  '2027-01-01 00:00:00+00',
  99
);

select is(
  (select updated_at from public.audit_events where id = '40000000-0000-0000-0000-000000000001'),
  (select created_at from public.audit_events where id = '40000000-0000-0000-0000-000000000001'),
  'audit insert fixes updated_at to created_at'
);

select is(
  (select version from public.audit_events where id = '40000000-0000-0000-0000-000000000001'),
  1::bigint,
  'audit insert fixes version to one'
);

select throws_ok(
  $$update public.audit_events
    set reason = 'changed'
    where id = '40000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'audit_events is append-only',
  'audit events cannot be updated'
);

select throws_ok(
  $$delete from public.audit_events
    where id = '40000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'audit_events is append-only',
  'audit events cannot be deleted'
);

select throws_ok(
  $$insert into public.audit_events (
      workspace_id, actor_type, actor_identifier, action, entity_type, source, correlation_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'system', 'pgtap',
      'Invalid Action', 'workspace', 'database',
      '60000000-0000-0000-0000-000000000002'
    )$$,
  '23514',
  null,
  'audit action keys must be normalized'
);

select throws_ok(
  $$insert into public.audit_events (
      workspace_id, actor_type, actor_identifier, action, entity_type, source,
      correlation_id, mutation_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'system', 'pgtap',
      'schema.test', 'workspace', 'database',
      '60000000-0000-0000-0000-000000000003',
      '50000000-0000-0000-0000-000000000001'
    )$$,
  '23505',
  null,
  'audit mutation id is unique within a workspace'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.audit_events'::regclass
      and tgname = 'audit_events_append_only'
      and not tgisinternal
  ),
  'audit append-only trigger exists'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.mutation_receipts'::regclass
      and tgname = 'mutation_receipts_protected_columns'
      and not tgisinternal
  ),
  'receipt identity trigger exists'
);

select ok(
  exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'membership_status'
  ),
  'membership status enum exists'
);

select ok(
  exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'audit_actor_type'
  ),
  'audit actor enum exists'
);

select ok(
  (select count(*) = 4 from pg_enum where enumtypid = 'public.membership_status'::regtype),
  'membership status enum has four values'
);

select ok(
  (select count(*) = 3 from pg_enum where enumtypid = 'public.audit_actor_type'::regtype),
  'audit actor enum has three values'
);

select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.mutation_receipts'::regclass and conname = 'mutation_receipts_request_hash_check'),
  'hash length check exists'
);
select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.audit_events'::regclass and conname = 'audit_events_append_shape_check'),
  'audit append shape check exists'
);

select * from finish();

rollback;
