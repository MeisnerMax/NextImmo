\set ON_ERROR_STOP on

-- FINANCE-01c gate: three-session business-key concurrency.
--
-- One holder and two challengers, because the package fixes two commands and
-- a two-session test could only ever prove one of them. The holder opens an
-- explicit transaction and claims both keys -- the account code and the fiscal
-- month -- then sits on them; the two challengers arrive while that
-- transaction is still open, each racing one of the keys.
--
-- Everything below is workspace-level: no property, no unit, no lease. Neither
-- command under test touches one, and inventing a property would only add a
-- fixture that a future reader has to rule out.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'fc000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'finance-01c-concurrency@example.test', '',
  now(), '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values (
  'fc000000-0000-0000-0000-000000000010',
  'finance-01c-concurrency', 'FINANCE-01c Concurrency'
);

insert into public.roles (id, workspace_id, key, name)
values (
  'fc000000-0000-0000-0000-000000000011',
  'fc000000-0000-0000-0000-000000000010',
  'manager', 'Manager'
);

-- Only the permission the two commands actually check. `finance.read` would
-- read as a requirement of the write path, which it is not.
insert into public.permissions (id, key, name) values
  ('fc000000-0000-0000-0000-000000000012', 'finance.manage', 'Finance Manage');

insert into public.role_permissions (workspace_id, role_id, permission_id)
values (
  'fc000000-0000-0000-0000-000000000010',
  'fc000000-0000-0000-0000-000000000011',
  'fc000000-0000-0000-0000-000000000012'
);

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  'fc000000-0000-0000-0000-000000000010',
  'fc000000-0000-0000-0000-000000000001',
  'fc000000-0000-0000-0000-000000000011',
  'active'
);
