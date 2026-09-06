begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-ACTIVITY-03 (V-2a).
--
-- LEASING-COMPONENTS-01 writes audit events; this package is what makes them
-- reachable from a property. The failure it prevents is not a missing feature
-- but a **misleading** timeline: a chronicle that shows a lease whose rent
-- changed, and no record of the change, looks complete and is not.
--
-- Three things are worth pinning, and only one of them is "the row appears".
--
--   * It appears **for the right property**. The resolution is the only
--     two-hop one in `property_activity_rows` — component → lease → property —
--     so an error there would attach a component to every property in the
--     workspace, or to none. The negative assertion against a second property
--     is what separates those.
--   * It **disappears without `lease.read`**. The domain gate is the whole
--     point of the read model; a component is rent information and must not
--     leak to a caller who cannot see the lease it belongs to.
--   * The rest of the chronicle is **unaffected**. This migration replaces two
--     functions and creates nothing, so a regression here would be silent.

select plan(11);

select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where entity_type = 'lease_component'),
  1, 'the component type is in the taxonomy exactly once');

select is(
  (select domain from private.property_activity_taxonomy()
   where entity_type = 'lease_component'),
  'leasing',
  'and it sits in leasing, with the units, contracts and rent rolls it belongs to');

select is(
  (select required_permission from private.property_activity_taxonomy()
   where entity_type = 'lease_component'),
  'lease.read',
  'gated on lease.read: a component is rent information');

-- ---------------------------------------------------------------------------
-- Fixture: two properties, so "resolves to the right one" is testable.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d1200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'activity03-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('d1200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'activity03-propertyonly@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1100000-0000-0000-0000-000000000001', 'activity03', 'Activity 03');
select private.seed_workspace_role_catalog('d1100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'd1400000-0000-0000-0000-000000000001',
  'd1100000-0000-0000-0000-000000000001',
  'd1200000-0000-0000-0000-000000000001',
  role.id, 'active'
from public.roles as role
where role.workspace_id = 'd1100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

-- A role that can see the property but not its leases. Built here rather than
-- borrowed from the catalogue so the gate is tested by the permission it
-- lacks, not by whatever else a documented role happens not to hold.
insert into public.roles (id, workspace_id, key, name) values
  ('d1300000-0000-0000-0000-000000000001',
   'd1100000-0000-0000-0000-000000000001', 'property_only', 'Property Only');
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'd1100000-0000-0000-0000-000000000001',
       'd1300000-0000-0000-0000-000000000001', permission.id
from public.permissions as permission
where permission.key in ('workspace.read', 'property.read');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
values ('d1400000-0000-0000-0000-000000000002',
        'd1100000-0000-0000-0000-000000000001',
        'd1200000-0000-0000-0000-000000000002',
        'd1300000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('d1500000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000001',
   'Haus A', 'Weg 1', '10115', 'Berlin', 'de', 'residential', 1,
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001'),
  ('d1500000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000001',
   'Haus B', 'Weg 2', '10115', 'Berlin', 'de', 'residential', 1,
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('d1600000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 'A-01', 'occupied',
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001'),
  ('d1600000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000002', 'B-01', 'occupied',
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001');

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, base_rent_monthly, currency_code, created_by, updated_by
) values
  ('d1700000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 'd1600000-0000-0000-0000-000000000001',
   'Vertrag A', 'active', date '2026-01-01', 1000, 'EUR',
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001'),
  ('d1700000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000002', 'd1600000-0000-0000-0000-000000000002',
   'Vertrag B', 'active', date '2026-01-01', 800, 'EUR',
   'd1200000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_user(p_user uuid, p_statement text)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  execute p_statement into v_result;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

-- The event is produced by the real command, not inserted by hand: a fixture
-- that writes its own audit row would prove the query and not the pairing.
select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000001',
    $inner$select public.create_lease_component(
      'd1100000-0000-0000-0000-000000000001'::uuid,
      'd1700000-0000-0000-0000-000000000001'::uuid,
      'heating_advance'::public.lease_component_type, date '2026-01-01', 90,
      'd1800000-0000-0000-0000-000000000001'::uuid,
      'd1900000-0000-0000-0000-000000000001'::uuid)$inner$) -> 'ok',
  to_jsonb(true),
  'the fixture event comes from the real command');

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from private.property_activity_rows(
     'd1100000-0000-0000-0000-000000000001',
     'd1500000-0000-0000-0000-000000000001') as row
   join public.audit_events as event on event.id = row.audit_event_id
   where event.entity_type = 'lease_component'),
  1, 'the component event resolves to the property its lease sits on');

select is(
  (select count(*)::integer from private.property_activity_rows(
     'd1100000-0000-0000-0000-000000000001',
     'd1500000-0000-0000-0000-000000000002') as row
   join public.audit_events as event on event.id = row.audit_event_id
   where event.entity_type = 'lease_component'),
  0,
  'and to no other property -- the two-hop join is the one place this could '
  'over-match');

-- ---------------------------------------------------------------------------
-- Through the read port, where the permission gate lives
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000001',
    $inner$select to_jsonb(count(*)) from jsonb_array_elements(
      public.property_activity(
        'd1100000-0000-0000-0000-000000000001'::uuid,
        'd1500000-0000-0000-0000-000000000001'::uuid) -> 'events') as event
      where event ->> 'entity_type' = 'lease_component'$inner$),
  to_jsonb(1),
  'a caller with lease.read sees the component in the chronicle');

select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000002',
    $inner$select to_jsonb(count(*)) from jsonb_array_elements(
      public.property_activity(
        'd1100000-0000-0000-0000-000000000001'::uuid,
        'd1500000-0000-0000-0000-000000000001'::uuid) -> 'events') as event
      where event ->> 'entity_type' = 'lease_component'$inner$),
  to_jsonb(0),
  'a caller without lease.read does not -- rent information does not leak to '
  'someone who cannot see the lease');

-- ...and that second caller is not simply blocked from the whole chronicle,
-- which would make the assertion above true for the wrong reason.
select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000002',
    $inner$select public.property_activity(
      'd1100000-0000-0000-0000-000000000001'::uuid,
      'd1500000-0000-0000-0000-000000000001'::uuid) -> 'ok'$inner$),
  to_jsonb(true),
  'the same caller still reads the chronicle: the component is filtered, not '
  'the timeline');

select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000002',
    $inner$select to_jsonb(
      public.property_activity(
        'd1100000-0000-0000-0000-000000000001'::uuid,
        'd1500000-0000-0000-0000-000000000001'::uuid)
      -> 'visible_domains' @> '["leasing"]'::jsonb)$inner$),
  to_jsonb(false),
  'and the response says leasing is not among its visible domains, so the '
  'gap is declared rather than silent');

select is(
  pg_temp.as_user(
    'd1200000-0000-0000-0000-000000000001',
    $inner$select to_jsonb(event ->> 'action') from jsonb_array_elements(
      public.property_activity(
        'd1100000-0000-0000-0000-000000000001'::uuid,
        'd1500000-0000-0000-0000-000000000001'::uuid) -> 'events') as event
      where event ->> 'entity_type' = 'lease_component' limit 1$inner$),
  to_jsonb('lease_component.create'::text),
  'the action arrives qualified, which is what the client strips the prefix '
  'from before naming the verb');

select * from finish();
rollback;
