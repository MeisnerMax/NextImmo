\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'b7000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'p1-011-b@example.test',
  extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
  now(), '', '', '', '', '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('27000000-0000-0000-0000-000000000001', 'p1-011-b', 'P1-011 B');

insert into public.roles (id, workspace_id, key, name)
values (
  '27000000-0000-0000-0000-000000000002',
  '27000000-0000-0000-0000-000000000001',
  'property_manager',
  'Property Manager B'
);

insert into public.role_permissions (workspace_id, role_id, permission_id)
select
  '27000000-0000-0000-0000-000000000001'::uuid,
  '27000000-0000-0000-0000-000000000002'::uuid,
  permission.id
from public.permissions as permission
where permission.key in ('workspace.read', 'property.read', 'property.update');

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '27000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001',
  '27000000-0000-0000-0000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  '27000000-0000-0000-0000-000000000005',
  '27000000-0000-0000-0000-000000000001',
  'Foreign Before', 'Foreign Street 1', '20095', 'Hamburg', 'de', 'office',
  1, 'active',
  'b7000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001'
);
