\set ON_ERROR_STOP on

-- P2-D05 integration fixture: one workspace, a leasing manager and a viewer who
-- deliberately lacks `lease.read`, one property to hang units off, and one party
-- carrying an open `tenant` role (AGG-005 — there is no cloud `tenants` table;
-- `create_lease` refuses a tenant party without that role).
--
-- Mirrors p2_d02_setup.sql: real bcrypt passwords, because this fixture is
-- consumed by a Flutter client that signs in over the Auth API rather than by
-- pgTAP running as postgres.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'ea000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d05-manager@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'ea000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d05-viewer@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('e1000000-0000-0000-0000-000000000001', 'p2-d05', 'P2-D05');

insert into public.roles (id, workspace_id, key, name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('e3000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('e3000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read'),
  ('e3000000-0000-0000-0000-000000000004', 'party.read', 'Party Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000004'),
  -- The viewer holds workspace.read only: no lease.read, no lease.manage. That
  -- separates "sees nothing" (RLS) from "may not write" (permission gate).
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'active'),
  ('e4000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'e5000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000001',
  'Integrationsobjekt', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
  'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'
);

insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values
  ('e6000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Eins',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  ('e6000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Zwei',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');

insert into public.party_roles (
  id, workspace_id, party_id, role_type, created_by, updated_by
) values
  ('e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e6000000-0000-0000-0000-000000000001', 'tenant',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  ('e7000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e6000000-0000-0000-0000-000000000002', 'tenant',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');
