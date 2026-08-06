\set ON_ERROR_STOP on

-- P2-D05a integration fixture: one workspace, a manager (lease.read +
-- lease.manage) and a viewer who deliberately lacks lease.read, one property,
-- and one tenant party with an email but no phone (the fixture the
-- missing_tenant_contact signal needs). Units and leases are created by the
-- test itself through the real adapters, same shape as p2_d05_setup.sql —
-- only the actor/permission/property scaffolding is fixture data here.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'fa000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d05a-manager@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    'fa000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'p2-d05a-viewer@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name)
values ('f1000000-0000-0000-0000-000000000001', 'p2-d05a', 'P2-D05a');

insert into public.roles (id, workspace_id, key, name) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('f3000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('f3000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('f3000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000003'),
  -- The viewer holds workspace.read only: no lease.read, no lease.manage.
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('f4000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'active'),
  ('f4000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'f5000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'Integrationsobjekt', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
  'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'
);

-- Email present, phone absent: the fixture missing_tenant_contact needs.
insert into public.parties (
  id, workspace_id, party_type, display_name, email, created_by, updated_by
) values (
  'f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
  'person', 'Mieter Ohne Telefon', 'ohnetelefon@example.test',
  'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'
);

insert into public.party_roles (
  id, workspace_id, party_id, role_type, created_by, updated_by
) values (
  'f7000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
  'f6000000-0000-0000-0000-000000000001', 'tenant',
  'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'
);
