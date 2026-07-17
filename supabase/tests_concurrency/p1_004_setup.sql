\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ac000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'concurrency@example.test', '', now(),
  '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('1c000000-0000-0000-0000-000000000001', 'concurrency', 'Concurrency');

insert into public.roles (id, workspace_id, key, name)
values (
  '1c000000-0000-0000-0000-000000000002',
  '1c000000-0000-0000-0000-000000000001',
  'manager', 'Manager'
);

insert into public.permissions (id, key, name) values
  ('1c000000-0000-0000-0000-000000000003', 'property.read', 'Property Read'),
  ('1c000000-0000-0000-0000-000000000004', 'property.update', 'Property Update');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  (
    '1c000000-0000-0000-0000-000000000001',
    '1c000000-0000-0000-0000-000000000002',
    '1c000000-0000-0000-0000-000000000003'
  ),
  (
    '1c000000-0000-0000-0000-000000000001',
    '1c000000-0000-0000-0000-000000000002',
    '1c000000-0000-0000-0000-000000000004'
  );

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '1c000000-0000-0000-0000-000000000001',
  'ac000000-0000-0000-0000-000000000001',
  '1c000000-0000-0000-0000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  '1c000000-0000-0000-0000-000000000005',
  '1c000000-0000-0000-0000-000000000001',
  'Before', 'Concurrency Street 1', '10115', 'Berlin', 'de', 'office',
  1, 'active',
  'ac000000-0000-0000-0000-000000000001',
  'ac000000-0000-0000-0000-000000000001'
);
