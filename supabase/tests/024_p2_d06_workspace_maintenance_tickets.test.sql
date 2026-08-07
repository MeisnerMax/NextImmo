begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- === Schema surface =====================================================

select has_function('public', 'workspace_maintenance_tickets', array['uuid', 'text', 'text']);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'workspace_maintenance_tickets'
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute workspace_maintenance_tickets'
);

-- === Fixtures ============================================================
--
-- Two properties in one workspace (unlike 023_p2_d06_maintenance_capex,
-- whose single fixture property cannot prove a workspace-wide read spans
-- more than one), plus a second workspace to prove scoping.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-wmt-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-wmt-noperm-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-wmt-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'p2d06-wmt-workspace-a', 'P2D06 WMT Workspace A'),
  ('f2000000-0000-0000-0000-000000000001', 'p2d06-wmt-workspace-b', 'P2D06 WMT Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('f3000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('f3000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'noperm', 'No Permission A'),
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('f5000000-0000-0000-0000-000000000001', 'maintenance.read', 'Maintenance Read'),
  ('f5000000-0000-0000-0000-000000000002', 'maintenance.manage', 'Maintenance Manage'),
  ('f5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000003'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000003'),
  ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001'),
  ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'active'),
  ('f6000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000002', 'active'),
  ('f6000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('f7000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'Objekt A1', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'),
  ('f7000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'Objekt A2', 'Nebenstrasse 2', '10117', 'Berlin', 'de', 'residential',
   'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001'),
  ('f7000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000001',
   'Objekt B1', 'Dritte Strasse 3', '20095', 'Hamburg', 'de', 'residential',
   'fb000000-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);

create temporary table wmt_results (
  key text primary key,
  result jsonb not null
);
grant all on table wmt_results to authenticated;

insert into wmt_results (key, result)
select 'create_a1', public.create_maintenance_ticket(
  'f1000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 'Heizung A1',
  'fc000000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
  null, null, 'general', 'urgent'
);
insert into wmt_results (key, result)
select 'create_a2', public.create_maintenance_ticket(
  'f1000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000002', 'Fenster A2',
  'fc000000-0000-0000-0000-000000000002', 'fd000000-0000-0000-0000-000000000002',
  null, null, 'general', 'normal'
);

select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
insert into wmt_results (key, result)
select 'create_b1', public.create_maintenance_ticket(
  'f2000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000003', 'Dach B1',
  'fc000000-0000-0000-0000-000000000003', 'fd000000-0000-0000-0000-000000000003',
  null, null, 'general', 'urgent'
);

-- === workspace_maintenance_tickets(): the RPC under test ================

select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
insert into wmt_results (key, result)
select 'read_a', public.workspace_maintenance_tickets('f1000000-0000-0000-0000-000000000001');
select is(
  (select jsonb_array_length(result -> 'entity') from wmt_results where key = 'read_a'),
  2,
  'both tickets across both of workspace A''s properties are returned, no property id needed'
);
select is(
  (select array_agg(entity ->> 'property_id' order by entity ->> 'property_id')
   from wmt_results, jsonb_array_elements(result -> 'entity') as entity
   where key = 'read_a'),
  array['f7000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000002'],
  'the two returned tickets belong to the two distinct properties'
);

insert into wmt_results (key, result)
select 'read_a_urgent', public.workspace_maintenance_tickets(
  'f1000000-0000-0000-0000-000000000001', null, 'urgent'
);
select is(
  (select jsonb_array_length(result -> 'entity') from wmt_results where key = 'read_a_urgent'),
  1,
  'the priority filter narrows across properties, matching the per-property RPC''s filter shape'
);

-- Workspace scoping: workspace B's manager never sees workspace A's tickets.
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
insert into wmt_results (key, result)
select 'read_b', public.workspace_maintenance_tickets('f2000000-0000-0000-0000-000000000001');
select is(
  (select jsonb_array_length(result -> 'entity') from wmt_results where key = 'read_b'),
  1,
  'workspace B only sees its own ticket'
);

insert into wmt_results (key, result)
select 'read_cross_workspace', public.workspace_maintenance_tickets('f1000000-0000-0000-0000-000000000001');
select is(
  (select result #>> '{error,code}' from wmt_results where key = 'read_cross_workspace'),
  'forbidden',
  'a member of workspace B has no membership-derived permission in workspace A'
);

-- Permission gate: workspace.read alone is not maintenance.read.
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
insert into wmt_results (key, result)
select 'read_noperm', public.workspace_maintenance_tickets('f1000000-0000-0000-0000-000000000001');
select is(
  (select result #>> '{error,code}' from wmt_results where key = 'read_noperm'),
  'forbidden',
  'a member without maintenance.read cannot use the workspace-wide read either'
);

-- Unauthenticated call.
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$ select public.workspace_maintenance_tickets('f1000000-0000-0000-0000-000000000001') $$,
  '42501'
);

select * from finish();

rollback;
