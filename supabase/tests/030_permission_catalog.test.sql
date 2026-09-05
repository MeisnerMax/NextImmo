begin;

create extension if not exists pgtap with schema extensions;

-- PERMISSION-CATALOG-02: one canonical permission catalog, and least-privilege
-- role bundles for the five spec'd roles (enterprise_target_architecture:
-- admin, manager, analyst, operations, viewer).
--
-- The seeding mechanism is private.seed_workspace_role_catalog: called by the
-- migration for every workspace that exists at migration time, and by
-- operations for workspaces created later. It is deliberately NOT a trigger —
-- the pgTAP suites build their own catalogs per file and an automatic insert
-- on workspace creation would collide with every one of them.
--
-- PROPERTY-DATA-02 added `property.create` (catalog + admin/manager bundle).
--
-- This file uses ONLY the seeded catalog (no fixture-owned permission rows),
-- which is itself part of the proof: the seed is complete enough to run the
-- real task/notification/search surface for non-admins.

select plan(37);

-- ---------------------------------------------------------------------------
-- Mechanism
-- ---------------------------------------------------------------------------

select has_function('private', 'ensure_permission_catalog',
  'the catalog seeder exists');
select has_function('private', 'seed_workspace_role_catalog',
  'the workspace role seeder exists');
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'private'
     and function.proname in ('ensure_permission_catalog', 'seed_workspace_role_catalog')
     and acl.grantee in ('anon'::regrole, 'authenticated'::regrole)),
  0,
  'no client role can call the seeders'
);

-- ---------------------------------------------------------------------------
-- Fixture: two workspaces (B stays unseeded), four users. Everything below
-- runs against the REAL seeded catalog.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pc02-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pc02-operations@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pc02-analyst@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pc02-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'pc02-a', 'PC02 A'),
  ('f1000000-0000-0000-0000-000000000002', 'pc02-b', 'PC02 B');

select lives_ok(
  $$select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000001')$$,
  'seeding a workspace succeeds'
);
select lives_ok(
  $$select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000001')$$,
  'seeding is idempotent'
);

-- ---------------------------------------------------------------------------
-- The canonical catalog
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from public.permissions),
  30,
  'the catalog carries exactly the 30 canonical keys'
);
select is(
  (select string_agg(permission.key, ',' order by permission.key) from public.permissions as permission),
  'audit.read,capex.approve,capex.manage,capex.read,document.manage,document.read,document.verify,import.manage,import.read,lease.manage,lease.read,maintenance.manage,maintenance.read,notification.manage,notification.read,party.manage,party.read,property.create,property.read,property.update,reporting.generate,search.read,search.reindex,security.manage,task.manage,task.read,valuation.approve,valuation.manage,valuation.read,workspace.read',
  'the catalog keys match the client parity list key for key'
);

select is(
  (select string_agg(role.key, ',' order by role.key) from public.roles as role
   where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'),
  'admin,analyst,manager,operations,viewer',
  'the five spec roles exist, and only those'
);
select is(
  (select count(*)::integer from public.roles
   where workspace_id = 'f1000000-0000-0000-0000-000000000002'),
  0,
  'an unseeded workspace stays untouched'
);

-- ---------------------------------------------------------------------------
-- Least-privilege bundles, pinned as exact sets
-- ---------------------------------------------------------------------------

create or replace function pg_temp.bundle_of(role_key text)
returns text
language sql
as $$
  select string_agg(permission.key, ',' order by permission.key)
  from public.role_permissions as role_permission
  join public.roles as role on role.id = role_permission.role_id
  join public.permissions as permission on permission.id = role_permission.permission_id
  where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
    and role.key = role_key;
$$;

select is(
  pg_temp.bundle_of('admin'),
  (select string_agg(permission.key, ',' order by permission.key) from public.permissions as permission),
  'admin holds the full catalog'
);
select is(
  pg_temp.bundle_of('manager'),
  'audit.read,capex.approve,capex.manage,capex.read,document.manage,document.read,document.verify,import.manage,import.read,lease.manage,lease.read,maintenance.manage,maintenance.read,party.manage,party.read,property.create,property.read,property.update,reporting.generate,search.read,task.manage,task.read,valuation.approve,valuation.manage,valuation.read,workspace.read',
  'manager: everything operative, no security/notification/reindex administration'
);
select is(
  pg_temp.bundle_of('analyst'),
  'audit.read,capex.read,document.manage,document.read,import.manage,import.read,lease.read,maintenance.read,party.read,property.read,property.update,reporting.generate,search.read,task.manage,task.read,valuation.manage,valuation.read,workspace.read',
  'analyst: builds valuations and tasks, releases nothing, manages no operations'
);
select is(
  pg_temp.bundle_of('operations'),
  'audit.read,capex.read,document.manage,document.read,lease.read,maintenance.manage,maintenance.read,party.read,property.read,property.update,reporting.generate,search.read,task.manage,task.read,valuation.read,workspace.read',
  'operations: runs maintenance and tasks, approves nothing'
);
select is(
  pg_temp.bundle_of('viewer'),
  'audit.read,document.read,lease.read,property.read,reporting.generate,task.read,valuation.read,workspace.read',
  'viewer: reads, never writes'
);

-- The admin-only capabilities never leak into a non-admin bundle.
select is(
  (select count(*)::integer
   from public.role_permissions as role_permission
   join public.roles as role on role.id = role_permission.role_id
   join public.permissions as permission on permission.id = role_permission.permission_id
   where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
     and role.key <> 'admin'
     and role.key <> 'manager'
     and permission.key in ('security.manage', 'notification.manage', 'notification.read', 'search.reindex', 'property.create')),
  0,
  'security.manage, notification.*, search.reindex stay admin-only; property.create reaches manager at most'
);

-- PROPERTY-DATA-02: opening a new asset is a portfolio decision, so it stops
-- at manager. Analyst and operations keep property.update for existing assets.
select is(
  (select count(*)::integer
   from public.role_permissions as role_permission
   join public.roles as role on role.id = role_permission.role_id
   join public.permissions as permission on permission.id = role_permission.permission_id
   where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
     and role.key in ('analyst', 'operations', 'viewer')
     and permission.key = 'property.create'),
  0,
  'property.create never reaches analyst, operations or viewer'
);

-- ---------------------------------------------------------------------------
-- Memberships on the seeded roles, plus one property for roll-up and search
-- ---------------------------------------------------------------------------

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), 'f1000000-0000-0000-0000-000000000001', pairing.user_id, role.id, 'active'
from (values
  ('fa000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('fa000000-0000-0000-0000-000000000002'::uuid, 'operations'),
  ('fa000000-0000-0000-0000-000000000003'::uuid, 'analyst'),
  ('fa000000-0000-0000-0000-000000000004'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
  'Katalog-Haus', 'Kanonstr. 2', '10115', 'Berlin', 'de', 'residential',
  'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Operations: the real task surface without any admin right
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
set local role authenticated;

select is(
  public.create_task(
    'f1000000-0000-0000-0000-000000000001', 'Heizung entlüften',
    'f6000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001',
    p_entity_type => 'property', p_entity_id => 'f5000000-0000-0000-0000-000000000001'
  ) ->> 'ok',
  'true',
  'operations creates a task through the real RPC'
);
select is(
  public.create_task(
    'f1000000-0000-0000-0000-000000000001', 'Heizung entlüften',
    'f6000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001',
    p_entity_type => 'property', p_entity_id => 'f5000000-0000-0000-0000-000000000001'
  ) -> 'entity' ->> 'property_id',
  'f5000000-0000-0000-0000-000000000001',
  'and reads the TASK-QUERY-01 roll-up on the way'
);
select is(
  public.count_tasks('f1000000-0000-0000-0000-000000000001') -> 'entity' ->> 'count',
  '1',
  'count_tasks answers operations consistently with the list'
);
select is(
  public.update_task(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung entlüften'),
    1,
    'f6000000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000002',
    '{"assigned_to": "fa000000-0000-0000-0000-000000000002"}'::jsonb
  ) -> 'entity' ->> 'assigned_to',
  'fa000000-0000-0000-0000-000000000002',
  'operations assigns the task to themselves'
);
select is(
  public.update_task(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung entlüften'),
    2,
    'f6000000-0000-0000-0000-000000000003', 'f7000000-0000-0000-0000-000000000003',
    '{"assigned_to": "fa000000-0000-0000-0000-000000000003"}'::jsonb
  ) ->> 'ok',
  'true',
  'operations hands the task to the analyst'
);
select is(
  public.transition_task_status(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung entlüften'),
    3, 'in_progress',
    'f6000000-0000-0000-0000-000000000004', 'f7000000-0000-0000-0000-000000000004'
  ) -> 'entity' ->> 'status',
  'in_progress',
  'operations transitions along the STM-012 contract'
);

-- The operations member resolves entity names through search.read.
select ok(
  (select count(*) from public.search_index
   where workspace_id = 'f1000000-0000-0000-0000-000000000001') >= 1,
  'operations resolves entity names through search.read'
);

-- Cross-workspace isolation is untouched.
select is(
  public.count_tasks('f1000000-0000-0000-0000-000000000002') -> 'error' ->> 'code',
  'forbidden',
  'operations gets nothing in a foreign workspace'
);

-- AAL2 stays the boundary: the same user at aal1 mutates nothing.
set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal1"}';
select is(
  public.create_task(
    'f1000000-0000-0000-0000-000000000001', 'Ohne zweiten Faktor',
    'f6000000-0000-0000-0000-000000000005', 'f7000000-0000-0000-0000-000000000005'
  ) -> 'error' ->> 'code',
  'forbidden',
  'aal1 cannot mutate tasks, whatever the role grants'
);

-- ---------------------------------------------------------------------------
-- Viewer: reads, never writes
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000004","role":"authenticated","aal":"aal2"}';
select is(
  (select count(*)::integer from public.tasks
   where workspace_id = 'f1000000-0000-0000-0000-000000000001'),
  1,
  'viewer reads the task list through task.read'
);
select is(
  public.create_task(
    'f1000000-0000-0000-0000-000000000001', 'Verboten',
    'f6000000-0000-0000-0000-000000000006', 'f7000000-0000-0000-0000-000000000006'
  ) -> 'error' ->> 'code',
  'forbidden',
  'viewer cannot create tasks'
);
select is(
  (select count(*)::integer from public.search_index),
  0,
  'viewer resolves no names without search.read'
);

-- ---------------------------------------------------------------------------
-- Notifications: the B-2 emitter worked for a plain non-admin, and the feed
-- stays recipient-scoped
-- ---------------------------------------------------------------------------

reset role;
-- The reassignment above must have notified the analyst although operations
-- holds no notification permission at all (B11: the emitter is server-side).
select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'fa000000-0000-0000-0000-000000000003'
     and kind = 'task.assigned'),
  1,
  'a non-admin task event notified the analyst without notification.manage'
);
set local role authenticated;

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
select is(
  (select count(*)::integer from public.notifications),
  1,
  'the analyst reads exactly their own feed'
);
select is(
  public.mark_notification_read(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.notifications
     where recipient_user_id = 'fa000000-0000-0000-0000-000000000003'),
    'f6000000-0000-0000-0000-000000000007', 'f7000000-0000-0000-0000-000000000007'
  ) ->> 'ok',
  'true',
  'the analyst marks their own notification read'
);

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000004","role":"authenticated","aal":"aal2"}';
select is(
  (select count(*)::integer from public.notifications),
  0,
  'the viewer sees no foreign feeds: recipient scoping holds without notification.read'
);

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
select is(
  (select count(*)::integer from public.notifications),
  0,
  'the acting operations member sees no foreign feeds either'
);
select is(
  public.create_notification(
    'f1000000-0000-0000-0000-000000000001',
    array['fa000000-0000-0000-0000-000000000003']::uuid[],
    'task.assigned', 'Handgemacht',
    'f6000000-0000-0000-0000-000000000008', 'f7000000-0000-0000-0000-000000000008'
  ) -> 'error' ->> 'code',
  'forbidden',
  'without notification.manage nobody fans out notifications by hand'
);

-- ---------------------------------------------------------------------------
-- Admin keeps working unchanged
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"fa000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
select is(
  public.count_tasks('f1000000-0000-0000-0000-000000000001') -> 'entity' ->> 'count',
  '1',
  'admin still counts the workspace tasks'
);
select ok(
  (select count(*) from public.notifications
   where workspace_id = 'f1000000-0000-0000-0000-000000000001') >= 1,
  'admin oversight: notification.read serves the whole workspace feed'
);
select is(
  public.create_notification(
    'f1000000-0000-0000-0000-000000000001',
    array['fa000000-0000-0000-0000-000000000002']::uuid[],
    'task.assigned', 'Admin-Fanout',
    'f6000000-0000-0000-0000-000000000009', 'f7000000-0000-0000-0000-000000000009'
  ) ->> 'ok',
  'true',
  'admin keeps notification.manage'
);

reset role;
reset request.jwt.claims;

select * from finish();

rollback;
