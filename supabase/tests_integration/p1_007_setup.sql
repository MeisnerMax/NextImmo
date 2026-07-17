\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a7000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'p1-007@example.test',
  extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
  now(), '', '', '', '', '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('17000000-0000-0000-0000-000000000001', 'p1-007', 'P1-007');

insert into public.roles (id, workspace_id, key, name)
values (
  '17000000-0000-0000-0000-000000000002',
  '17000000-0000-0000-0000-000000000001',
  'property_manager',
  'Property Manager'
);

insert into public.permissions (id, key, name) values
  ('17000000-0000-0000-0000-000000000003', 'property.read', 'Property Read'),
  ('17000000-0000-0000-0000-000000000004', 'property.update', 'Property Update'),
  ('17000000-0000-0000-0000-000000000010', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  (
    '17000000-0000-0000-0000-000000000001',
    '17000000-0000-0000-0000-000000000002',
    '17000000-0000-0000-0000-000000000003'
  ),
  (
    '17000000-0000-0000-0000-000000000001',
    '17000000-0000-0000-0000-000000000002',
    '17000000-0000-0000-0000-000000000004'
  ),
  (
    '17000000-0000-0000-0000-000000000001',
    '17000000-0000-0000-0000-000000000002',
    '17000000-0000-0000-0000-000000000010'
  );

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '17000000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000001',
  '17000000-0000-0000-0000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  '17000000-0000-0000-0000-000000000005',
  '17000000-0000-0000-0000-000000000001',
  'Before', 'Integration Street 1', '10115', 'Berlin', 'de', 'office',
  1, 'active',
  'a7000000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000001'
);
