\set ON_ERROR_STOP on

-- SECURITY-STORAGE-AAL-03.
--
-- Three identities against two workspaces, so every denial in the storage
-- matrix is attributable to exactly one cause:
--
--   storage-full     workspace A, document.read + document.manage
--   storage-read     workspace A, document.read only
--   storage-foreign  workspace B, document.read + document.manage
--
-- The read-only and foreign identities exist so a denial can be traced to the
-- missing permission or the wrong workspace rather than to the assurance level,
-- and the full identity is used on both sides of an MFA elevation so the aal1
-- denials cannot be explained by a missing membership.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '5a000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-full@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-read@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-foreign@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name) values
  ('51000000-0000-0000-0000-000000000001', 'storage-a', 'Storage A'),
  ('52000000-0000-0000-0000-000000000001', 'storage-b', 'Storage B');

insert into public.roles (id, workspace_id, key, name) values
  ('51000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001', 'document_manager', 'Document Manager A'),
  ('51000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000001', 'document_reader', 'Document Reader A'),
  ('52000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000001', 'document_manager', 'Document Manager B');

insert into public.permissions (id, key, name) values
  ('53000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('53000000-0000-0000-0000-000000000002', 'document.manage', 'Document Manage'),
  ('53000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- A / manager: read + manage
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000003'),
  -- A / reader: read only, deliberately no manage
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000003'),
  -- B / manager: read + manage, but only inside workspace B
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002'),
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000003');

insert into public.memberships (workspace_id, user_id, role_id, status) values
  ('51000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', 'active'),
  ('51000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000003', 'active'),
  ('52000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000002', 'active');
