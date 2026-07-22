\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ad000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'debt-012@example.test',
  extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
  now(), '', '', '', '', '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('1d000000-0000-0000-0000-000000000001', 'debt-012', 'DEBT-012');

insert into public.roles (id, workspace_id, key, name)
values (
  '1d000000-0000-0000-0000-000000000002',
  '1d000000-0000-0000-0000-000000000001',
  'property_manager',
  'Property Manager'
);

insert into public.permissions (id, key, name) values
  ('1d000000-0000-0000-0000-000000000003', 'property.read', 'Property Read'),
  ('1d000000-0000-0000-0000-000000000004', 'property.update', 'Property Update'),
  ('1d000000-0000-0000-0000-000000000010', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  (
    '1d000000-0000-0000-0000-000000000001',
    '1d000000-0000-0000-0000-000000000002',
    '1d000000-0000-0000-0000-000000000003'
  ),
  (
    '1d000000-0000-0000-0000-000000000001',
    '1d000000-0000-0000-0000-000000000002',
    '1d000000-0000-0000-0000-000000000004'
  ),
  (
    '1d000000-0000-0000-0000-000000000001',
    '1d000000-0000-0000-0000-000000000002',
    '1d000000-0000-0000-0000-000000000010'
  );

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '1d000000-0000-0000-0000-000000000001',
  'ad000000-0000-0000-0000-000000000001',
  '1d000000-0000-0000-0000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  '1d000000-0000-0000-0000-000000000005',
  '1d000000-0000-0000-0000-000000000001',
  'Tombstone Target', 'Tombstone Street 1', '10115', 'Berlin', 'de',
  'multifamily', 4, 'active',
  'ad000000-0000-0000-0000-000000000001',
  'ad000000-0000-0000-0000-000000000001'
);
