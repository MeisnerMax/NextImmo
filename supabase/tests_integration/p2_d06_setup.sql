\set ON_ERROR_STOP on

-- P2-D06 integration fixture: one workspace, a manager (maintenance.manage +
-- capex.manage, deliberately without capex.approve), an approver (adds
-- capex.approve — the separate gate `transition_capex_project_status`
-- checks), and a viewer who lacks both `maintenance.read` and `capex.read`.
-- One property, one party carrying an open `contractor` role (AGG-005 — the
-- contractor is a Party role, not a separate vendor master) and one party
-- without any role, for the negative `dependency_conflict` case.
--
-- Mirrors p2_d05_setup.sql: real bcrypt passwords, because this fixture is
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
    'authenticated', 'authenticated', 'p2-d06-manager@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'ea000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d06-approver@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'ea000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d06-viewer@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('e1000000-0000-0000-0000-000000000001', 'p2-d06', 'P2-D06');

insert into public.roles (id, workspace_id, key, name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'approver', 'Approver'),
  ('e2000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'maintenance.read', 'Maintenance Read'),
  ('e3000000-0000-0000-0000-000000000002', 'maintenance.manage', 'Maintenance Manage'),
  ('e3000000-0000-0000-0000-000000000003', 'capex.read', 'CapEx Read'),
  ('e3000000-0000-0000-0000-000000000004', 'capex.manage', 'CapEx Manage'),
  ('e3000000-0000-0000-0000-000000000005', 'capex.approve', 'CapEx Approve'),
  ('e3000000-0000-0000-0000-000000000006', 'workspace.read', 'Workspace Read'),
  ('e3000000-0000-0000-0000-000000000007', 'party.read', 'Party Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- Manager: everything except capex.approve — the separate gate under test.
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000004'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000006'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000007'),
  -- Approver: manager's set plus capex.approve.
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000004'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000005'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000006'),
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000007'),
  -- Viewer holds workspace.read only: no maintenance.read, no capex.read. That
  -- separates "sees nothing" (RLS) from "may not write" (permission gate).
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 'e3000000-0000-0000-0000-000000000006');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'active'),
  ('e4000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'active'),
  ('e4000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000003', 'active');

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
   'organization', 'Handwerksbetrieb Eins',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  ('e6000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'organization', 'Ohne Rolle',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');

insert into public.party_roles (
  id, workspace_id, party_id, role_type, created_by, updated_by
) values
  ('e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e6000000-0000-0000-0000-000000000001', 'contractor',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');
