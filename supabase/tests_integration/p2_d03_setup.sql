\set ON_ERROR_STOP on

-- P2-D03 documents_compliance integration fixture. Two members of one
-- workspace: an admin holding document.read/manage/verify and a viewer holding
-- workspace.read only, so the integration test can exercise both the happy path
-- and the server-side denials (RLS on the tables, permission gate in the RPCs,
-- and RLS on storage.objects for the private bucket).

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'ea000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d03-admin@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'ea000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d03-viewer@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('e1000000-0000-0000-0000-000000000001', 'p2-d03', 'P2-D03');

insert into public.roles (id, workspace_id, key, name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('e3000000-0000-0000-0000-000000000002', 'document.manage', 'Document Manage'),
  ('e3000000-0000-0000-0000-000000000003', 'document.verify', 'Document Verify'),
  ('e3000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000004'),
  -- The viewer holds workspace.read only: no document permission of any kind,
  -- so both the metadata tables and the private bucket must stay closed to it.
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000004');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'active'),
  ('e4000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'active');

-- A migrated entity to link documents to, so the DocumentLinkPort happy path and
-- the requirement projection have a real target.
insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'P2-D03 Objekt', 'Teststrasse 1', '10115', 'Berlin', 'de', 'residential',
  'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'
);
