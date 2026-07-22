begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- === Schema surface ===================================================

select has_function('public', 'list_workspace_members', array['uuid']);

select ok(
  (select function.prosecdef
     and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname = 'list_workspace_members'),
  'list_workspace_members is a postgres security definer with a fixed search path'
);

select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'list_workspace_members'
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute list_workspace_members'
);

select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'list_workspace_members'
     and grantee = 'authenticated'
     and privilege_type = 'EXECUTE'),
  1,
  'authenticated can execute list_workspace_members'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-dir-admin-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('da000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-dir-viewer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('db000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-dir-admin-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.user_profiles (user_id, display_name) values
  ('da000000-0000-0000-0000-000000000001', 'Directory Admin A');

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'p2d01-dir-a', 'P2D01 Directory A'),
  ('d2000000-0000-0000-0000-000000000001', 'p2d01-dir-b', 'P2D01 Directory B');

insert into public.roles (id, workspace_id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('d3000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer A'),
  ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('d5000000-0000-0000-0000-000000000001', 'security.manage', 'Security Manage'),
  ('d5000000-0000-0000-0000-000000000002', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002', 'd5000000-0000-0000-0000-000000000002'),
  ('d2000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'active'),
  ('d6000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000002', 'active'),
  ('d6000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001', 'db000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'active');

create temporary table dir_results (key text primary key, result jsonb not null);
grant all on table dir_results to authenticated;

-- === Admin reads the directory ========================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

insert into dir_results (key, result)
select 'admin', public.list_workspace_members('d1000000-0000-0000-0000-000000000001');

select is(
  (select result ->> 'ok' from dir_results where key = 'admin'),
  'true',
  'a security.manage holder can read the directory'
);
select is(
  (select jsonb_array_length(result -> 'entity') from dir_results where key = 'admin'),
  2,
  'the directory lists both workspace members'
);
select is(
  (select entry ->> 'display_name'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000001'),
  'Directory Admin A',
  'the directory joins the display name from user_profiles'
);
select is(
  (select entry ->> 'email'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000001'),
  'p2d01-dir-admin-a@example.test',
  'the directory joins the email from auth.users'
);
select is(
  (select entry ->> 'role_key'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000002'),
  'viewer',
  'the directory carries each member role key'
);
select is(
  (select entry ->> 'role_name'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000002'),
  'Viewer A',
  'the directory carries each member role name'
);
select is(
  (select entry -> 'display_name'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000002'),
  'null'::jsonb,
  'a member without a profile has a null display name'
);
select is(
  (select entry ->> 'status'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000001'),
  'active',
  'the directory carries the lifecycle status'
);
select is(
  (select entry ->> 'workspace_id'
   from dir_results, jsonb_array_elements(result -> 'entity') as entry
   where key = 'admin' and entry ->> 'user_id' = 'da000000-0000-0000-0000-000000000001'),
  'd1000000-0000-0000-0000-000000000001',
  'each directory entry is scoped to the requested workspace'
);

select is(
  public.list_workspace_members(null) #>> '{error,code}',
  'validation_failed',
  'a null workspace is rejected'
);

-- === Viewer is forbidden ==============================================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000002', true);

select is(
  public.list_workspace_members('d1000000-0000-0000-0000-000000000001') #>> '{error,code}',
  'forbidden',
  'a member without security.manage cannot read the directory'
);

-- === Two-workspace isolation ==========================================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'db000000-0000-0000-0000-000000000001', true);

select is(
  public.list_workspace_members('d1000000-0000-0000-0000-000000000001') #>> '{error,code}',
  'forbidden',
  'a foreign workspace admin cannot read another workspace directory'
);
select is(
  (select jsonb_array_length(
     public.list_workspace_members('d2000000-0000-0000-0000-000000000001') -> 'entity'
   )),
  1,
  'the foreign admin only sees their own workspace members'
);

-- === Anonymous access stays closed ====================================

reset role;
set local role anon;

select throws_ok(
  $$select public.list_workspace_members('d1000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'anon cannot execute the directory RPC'
);

reset role;

select * from finish();

rollback;
