\set ON_ERROR_STOP on

-- P2-D04 platform_audit_jobs integration fixture. Three members of one
-- workspace:
--   * a manager holding every platform permission, who drives the happy paths;
--   * a recipient holding workspace.read plus task.read only, who is addressed
--     by the notification fan-out but must NOT see the workspace-wide feed —
--     this is what proves the recipient-scoped RLS rather than assuming it;
--   * a viewer holding workspace.read only, for the server-side denials (RLS on
--     the tables and the permission gate inside every RPC).

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'fa000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d04-manager@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'fa000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d04-recipient@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'fa000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d04-viewer@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('f1000000-0000-0000-0000-000000000001', 'p2-d04', 'P2-D04');

insert into public.roles (id, workspace_id, key, name) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'recipient', 'Recipient'),
  ('f2000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('f3000000-0000-0000-0000-000000000001', 'task.read', 'Task Read'),
  ('f3000000-0000-0000-0000-000000000002', 'task.manage', 'Task Manage'),
  ('f3000000-0000-0000-0000-000000000003', 'notification.read', 'Notification Read'),
  ('f3000000-0000-0000-0000-000000000004', 'notification.manage', 'Notification Manage'),
  ('f3000000-0000-0000-0000-000000000005', 'import.read', 'Import Read'),
  ('f3000000-0000-0000-0000-000000000006', 'import.manage', 'Import Manage'),
  ('f3000000-0000-0000-0000-000000000007', 'search.read', 'Search Read'),
  ('f3000000-0000-0000-0000-000000000008', 'search.reindex', 'Search Reindex'),
  ('f3000000-0000-0000-0000-000000000009', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  permission.id
from public.permissions as permission
where permission.key in (
  'task.read', 'task.manage', 'notification.read', 'notification.manage',
  'import.read', 'import.manage', 'search.read', 'search.reindex',
  'workspace.read'
);

-- The recipient can see tasks and the workspace, but holds no notification
-- permission at all: their own notifications must still be readable (the
-- recipient predicate in the RLS policy), while the workspace-wide feed and
-- every notification command must stay closed.
insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000009'),
  -- The viewer holds workspace.read only.
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000003', 'f3000000-0000-0000-0000-000000000009');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('f4000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'active'),
  ('f4000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', 'active'),
  ('f4000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000003', 'active');

-- A migrated entity for the task/notification/search entity links to point at.
insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
  'P2-D04 Objekt', 'Teststrasse 4', '10115', 'Berlin', 'de', 'residential',
  'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'
);

-- A second workspace the manager is NOT a member of, so the integration test can
-- prove workspace isolation against the real API rather than asserting it.
insert into public.workspaces (id, key, name)
values ('f1000000-0000-0000-0000-000000000002', 'p2-d04-foreign', 'P2-D04 Foreign');
