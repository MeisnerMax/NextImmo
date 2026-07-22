begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- Schema surface added by DEBT-012.
select has_column('public', 'properties', 'deleted_by', 'properties gains a deleted_by actor column');
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.properties'::regclass
      and tgname = 'properties_apply_delete_marker'
      and not tgisinternal
  ),
  'properties has the delete-marker trigger'
);
select has_function('private', 'properties_apply_delete_marker', '{}'::text[]);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'debt012-manager@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'debt012-workspace', 'DEBT-012 Workspace');

insert into public.roles (id, workspace_id, key, name) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager');

insert into public.permissions (id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'property.read', 'Property Read'),
  ('d3000000-0000-0000-0000-000000000002', 'property.update', 'Property Update'),
  ('d3000000-0000-0000-0000-000000000003', 'audit.read', 'Audit Read');

insert into public.role_permissions (id, workspace_id, role_id, permission_id) values
  ('d4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001'),
  ('d4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002'),
  ('d4000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d5000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country,
  property_type, units, status, created_by, updated_by
) values (
  'd7000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
  'Tombstone Target', 'Marker Street 1', '10115', 'Berlin', 'de', 'multifamily',
  4, 'active',
  'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001'
);

create temporary table debt012_results (
  key text primary key,
  result jsonb not null
);
grant all on table debt012_results to authenticated;

-- Active row starts without a tombstone marker.
select is(
  (select deleted_at is null and deleted_by is null from public.properties
   where id = 'd7000000-0000-0000-0000-000000000001'),
  true,
  'active property has no delete marker'
);

select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);

-- Tombstone == archive: the acting user is recorded and the row is retained.
insert into debt012_results (key, result)
select 'tombstone', public.update_property(
  'd1000000-0000-0000-0000-000000000001',
  'd7000000-0000-0000-0000-000000000001',
  1,
  'd6000000-0000-0000-0000-000000000001',
  'd6000000-0000-0000-0000-000000000002',
  '{"status":"archived"}'::jsonb,
  'tombstone via archive'
);

select is((select result ->> 'ok' from debt012_results where key = 'tombstone'), 'true', 'archive tombstone succeeds');
select is(
  (select deleted_at is not null from public.properties where id = 'd7000000-0000-0000-0000-000000000001'),
  true,
  'tombstone sets deleted_at'
);
select is(
  (select deleted_by from public.properties where id = 'd7000000-0000-0000-0000-000000000001'),
  'd0000000-0000-0000-0000-000000000001'::uuid,
  'tombstone records the acting user in deleted_by'
);
select is(
  (select status from public.properties where id = 'd7000000-0000-0000-0000-000000000001'),
  'archived'::public.property_status,
  'tombstone leaves the row in archived status'
);
select is((select count(*)::integer from public.properties), 1, 'tombstoned row is retained and still readable for the archive view');
select is(
  (select count(*)::integer from public.properties where deleted_at is null),
  0,
  'tombstoned row is excluded from the active read predicate'
);
select is((select version from public.properties where id = 'd7000000-0000-0000-0000-000000000001'), 2::bigint, 'tombstone increments the version');
select is((select count(*)::integer from public.audit_events where entity_id = 'd7000000-0000-0000-0000-000000000001'), 1, 'tombstone writes exactly one audit event');
select is(
  (select action from public.audit_events where entity_id = 'd7000000-0000-0000-0000-000000000001' order by created_at limit 1),
  'property.update',
  'tombstone audit action is append-only property.update'
);

-- Restore == un-archive: the marker and deleter are cleared, row reactivated.
insert into debt012_results (key, result)
select 'restore', public.update_property(
  'd1000000-0000-0000-0000-000000000001',
  'd7000000-0000-0000-0000-000000000001',
  2,
  'd6000000-0000-0000-0000-000000000003',
  'd6000000-0000-0000-0000-000000000004',
  '{"status":"active"}'::jsonb,
  'restore via un-archive'
);

select is((select result ->> 'ok' from debt012_results where key = 'restore'), 'true', 'restore un-archive succeeds');
select is(
  (select deleted_at is null and deleted_by is null from public.properties
   where id = 'd7000000-0000-0000-0000-000000000001'),
  true,
  'restore clears the delete marker and deleter'
);
select is(
  (select status from public.properties where id = 'd7000000-0000-0000-0000-000000000001'),
  'active'::public.property_status,
  'restore reactivates the row'
);
select is(
  (select count(*)::integer from public.properties where deleted_at is null),
  1,
  'restored row is visible again to the active read predicate'
);
select is((select version from public.properties where id = 'd7000000-0000-0000-0000-000000000001'), 3::bigint, 'restore increments the version');
select is((select count(*)::integer from public.audit_events where entity_id = 'd7000000-0000-0000-0000-000000000001'), 2, 'restore writes a second append-only audit event');
select is(
  (select count(*)::integer from public.audit_events
   where entity_id = 'd7000000-0000-0000-0000-000000000001' and action <> 'property.update'),
  0,
  'every property tombstone/restore audit event is a property.update'
);

reset role;

select * from finish();

rollback;
