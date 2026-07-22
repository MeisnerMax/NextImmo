\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'fa000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d01-admin@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'fa000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d01-invitee@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('f1000000-0000-0000-0000-000000000001', 'p2-d01', 'P2-D01');

insert into public.roles (id, workspace_id, key, name) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('f3000000-0000-0000-0000-000000000001', 'security.manage', 'Security Manage'),
  ('f3000000-0000-0000-0000-000000000002', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
values (
  'f4000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'fa000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  'active'
);
