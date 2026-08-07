\set ON_ERROR_STOP on

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'c7000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'p1-018-viewer@example.test',
  extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
  now(), '', '', '', '', '{}', '{}', now(), now()
);

insert into public.roles (id, workspace_id, key, name)
values (
  '18000000-0000-0000-0000-000000000002',
  '17000000-0000-0000-0000-000000000001',
  'property_viewer',
  'Property Viewer'
);

insert into public.role_permissions (workspace_id, role_id, permission_id)
select
  '17000000-0000-0000-0000-000000000001'::uuid,
  '18000000-0000-0000-0000-000000000002'::uuid,
  permission.id
from public.permissions as permission
where permission.key in ('workspace.read', 'property.read');

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '17000000-0000-0000-0000-000000000001',
  'c7000000-0000-0000-0000-000000000001',
  '18000000-0000-0000-0000-000000000002',
  'active'
);
