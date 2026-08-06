begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

-- === Schema surface ===================================================

select has_table('public', 'operations_signal_states', 'the acknowledgement table exists');
select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   where class.oid = 'public.operations_signal_states'::regclass),
  'operations_signal_states enables and forces RLS'
);
select policies_are('public', 'operations_signal_states',
  array['operations_signal_states_select_lease_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'operations_signal_states'
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no DML grants on the acknowledgement table'
);

select has_function('public', 'operations_signals', array['uuid', 'uuid']);
select has_function(
  'public', 'update_operations_signal_status',
  array['uuid', 'uuid', 'text', 'text', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'bigint', 'text', 'text']
);
select has_function(
  'private', 'operations_signal_state_snapshot', array['operations_signal_states']
);
select ok(
  (select bool_and(
     function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in ('operations_signals', 'update_operations_signal_status')),
  'operations_signals RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in ('operations_signals', 'update_operations_signal_status')
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute operations_signals RPCs'
);

-- === Fixtures ==========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05a-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('da000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05a-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('da000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05a-noperm-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('db000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05a-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'p2d05a-workspace-a', 'P2D05a Workspace A'),
  ('d2000000-0000-0000-0000-000000000001', 'p2d05a-workspace-b', 'P2D05a Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('d3000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('d3000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'noperm', 'No Permission A'),
  ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('d5000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('d5000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('d5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read'),
  ('d5000000-0000-0000-0000-000000000004', 'audit.read', 'Audit Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000003'),
  -- Manager A also gets audit.read so the audit-trail assertion below reads
  -- through RLS rather than around it (mirrors 017_p2_d05_leasing_operations).
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000004'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002', 'd5000000-0000-0000-0000-000000000001'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002', 'd5000000-0000-0000-0000-000000000003'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000003', 'd5000000-0000-0000-0000-000000000003'),
  ('d2000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002'),
  ('d2000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'active'),
  ('d6000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000002', 'active'),
  ('d6000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000003', 'd3000000-0000-0000-0000-000000000003', 'active'),
  ('d6000000-0000-0000-0000-000000000004', 'd2000000-0000-0000-0000-000000000001', 'db000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('d7000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  ('d7000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
   'Objekt B', 'Nebenstrasse 2', '20095', 'Hamburg', 'de', 'residential',
   'db000000-0000-0000-0000-000000000001', 'db000000-0000-0000-0000-000000000001');

insert into public.parties (
  id, workspace_id, party_type, display_name, email, phone, created_by, updated_by
) values
  -- complete contact
  ('d8000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Vollstaendig', 'vollstaendig@example.test', '+49 1', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- missing phone
  ('d8000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Ohne Telefon', 'ohnetelefon@example.test', null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

-- Units covering every kept signal type.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, currency_code,
  vacancy_since, offline_reason, created_by, updated_by
) values
  -- occupied unit, carries the expiring/contact leases below
  ('d9000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-EXPIRY', 'occupied', 'EUR', null, null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- vacant, no vacancy_since -> vacancy_missing_since
  ('d9000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-NOSINCE', 'vacant', 'EUR', null, null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- vacant for 60 days -> vacancy_aged
  ('d9000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-AGED', 'vacant', 'EUR', current_date - 60, null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- vacant for 10 days -> below the 45-day threshold, no signal
  ('d9000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-FRESH', 'vacant', 'EUR', current_date - 10, null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- offline without a reason -> offline_missing_reason
  ('d9000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-OFFLINE', 'offline', 'EUR', null, null, 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

update public.units set offline_reason = null where id = 'd9000000-0000-0000-0000-000000000005';

-- Second occupied unit for the missing-tenant-contact and no-tenant cases.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, currency_code, created_by, updated_by
) values
  ('d9000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-CONTACT', 'occupied', 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  ('d9000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'U-NOTENANT', 'occupied', 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

insert into public.leases (
  id, workspace_id, property_id, unit_id, tenant_party_id, lease_name, status,
  start_date, end_date, base_rent_monthly, currency_code, created_by, updated_by
) values
  -- expires in 20 days -> critical
  ('dc000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'd9000000-0000-0000-0000-000000000001', 'd8000000-0000-0000-0000-000000000001', 'Lease Critical', 'active',
   current_date - 300, current_date + 20, 900, 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- expires in 200 days -> outside the 180-day window, no signal. Carries the
  -- fully-contactable tenant so it produces zero signals of any kind, keeping
  -- this fixture a clean "no signal" case for the expiry window alone.
  ('dc000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'd9000000-0000-0000-0000-000000000006', 'd8000000-0000-0000-0000-000000000001', 'Lease Far', 'active',
   current_date - 10, current_date + 200, 700, 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- no tenant party at all -> missing_tenant_contact
  ('dc000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'd9000000-0000-0000-0000-000000000007', null, 'Lease No Tenant', 'active',
   current_date - 10, null, 750, 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  -- tenant has an email but no phone -> also missing_tenant_contact. Inserted
  -- here (before the role switch below) rather than mid-test: authenticated
  -- only holds SELECT on leases, every mutation goes through an RPC.
  ('dc000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
   'd9000000-0000-0000-0000-000000000006', 'd8000000-0000-0000-0000-000000000002', 'Lease Partial Contact', 'active',
   current_date, null, 700, 'EUR', 'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

create temporary table p2_d05a_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d05a_results to authenticated;

-- === operations_signals: computation ===================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

insert into p2_d05a_results (key, result)
select 'signals', public.operations_signals(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d05a_results where key = 'signals'), 'true', 'operations_signals succeeds for a permitted reader');

select is(
  (select jsonb_array_length(result #> '{entity,signals}') from p2_d05a_results where key = 'signals'),
  7,
  'exactly the seven expected signals are computed (no U-FRESH, no far-dated lease)'
);

select is(
  (select signal ->> 'severity'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000001'),
  'critical',
  'a lease expiring in 20 days is critical'
);
select is(
  (select signal ->> 'type'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'unit_id' = 'd9000000-0000-0000-0000-000000000002'
     and signal ->> 'lease_id' is null),
  'vacancy_missing_since',
  'a vacant unit without vacancy_since is flagged'
);
select is(
  (select signal ->> 'type'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'unit_id' = 'd9000000-0000-0000-0000-000000000003'),
  'vacancy_aged',
  'a unit vacant for 60 days is aged'
);
select is(
  (select count(*)::integer
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'unit_id' = 'd9000000-0000-0000-0000-000000000004'),
  0,
  'a unit vacant for only 10 days is below the aging threshold'
);
select is(
  (select signal ->> 'type'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'unit_id' = 'd9000000-0000-0000-0000-000000000005'),
  'offline_missing_reason',
  'an offline unit without a reason is flagged'
);
select is(
  (select count(*)::integer
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000002'),
  0,
  'a lease expiring in 200 days is outside the 180-day window'
);
select is(
  (select signal ->> 'type'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000003'),
  'missing_tenant_contact',
  'a lease without a tenant party is flagged as missing contact'
);
select is(
  (select signal ->> 'status'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000001'),
  'open',
  'a signal with no acknowledgement row defaults to open'
);
select is(
  (select signal ->> 'signal_key'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000001'),
  'lease_expiry:d9000000-0000-0000-0000-000000000001:dc000000-0000-0000-0000-000000000001:d8000000-0000-0000-0000-000000000001',
  'the stable key is built from type and entity ids, never the message'
);

-- Tenant with email but no phone still counts as missing contact (dc...0004,
-- inserted with the other fixture leases above, before the role switch).
select is(
  (select signal ->> 'type'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000004'),
  'missing_tenant_contact',
  'a tenant party with email but no phone still counts as missing contact'
);

-- stale_rent_roll: no snapshot exists yet.
select is(
  (select count(*)::integer
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals' and signal ->> 'type' = 'stale_rent_roll'),
  1,
  'no rent roll snapshot at all is stale'
);

-- Raw insert, not the create_rent_roll_snapshot RPC: authenticated only holds
-- SELECT on rent_roll_snapshots, so the fixture is seeded as the unrestricted
-- role, same pattern as 017_p2_d05_leasing_operations.test.sql.
reset role;
insert into public.rent_roll_snapshots (
  id, workspace_id, property_id, as_of_date, currency_code,
  unit_count, occupied_unit_count, vacant_unit_count, offline_unit_count,
  effective_lease_count, total_base_rent_monthly, total_ancillary_charges_monthly,
  total_parking_other_charges_monthly, total_rent_monthly, created_by
) values (
  'dd000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  current_date, 'EUR', 7, 3, 3, 1, 4, 3050, 0, 0, 3050, 'da000000-0000-0000-0000-000000000001'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

insert into p2_d05a_results (key, result)
select 'signals_3', public.operations_signals(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001'
);
select is(
  (select count(*)::integer
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals_3' and signal ->> 'type' = 'stale_rent_roll'),
  0,
  'a fresh rent roll snapshot clears the staleness signal'
);

-- === operations_signals: authorization ==================================

select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000003', true);
insert into p2_d05a_results (key, result)
select 'signals_noperm', public.operations_signals(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'signals_noperm'), 'forbidden', 'a member without lease.read cannot read signals');

select set_config('request.jwt.claim.sub', 'db000000-0000-0000-0000-000000000001', true);
insert into p2_d05a_results (key, result)
select 'signals_foreign', public.operations_signals(
  -- Manager B's own workspace, but Objekt A's property id: the mismatch must
  -- read as not_found, the same as create_unit's cross-workspace property
  -- check in 017_p2_d05_leasing_operations.test.sql, not leak that the
  -- property exists elsewhere.
  'd2000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'signals_foreign'), 'not_found', 'a workspace/property mismatch is not_found, not a leak that the property exists elsewhere');

select set_config('request.jwt.claim.sub', '', true);
select is(
  public.operations_signals('d1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001') ->> 'ok',
  'false',
  'a call with no auth.uid() is refused'
);

-- === update_operations_signal_status ====================================

select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

insert into p2_d05a_results (key, result)
select 'ack_create', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'lease_expiry', 'dismissed',
  'de000000-0000-0000-0000-000000000001', 'df000000-0000-0000-0000-000000000001',
  'd9000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  'd8000000-0000-0000-0000-000000000001', null, 'reviewed and postponed'
);
select is((select result ->> 'ok' from p2_d05a_results where key = 'ack_create'), 'true', 'creating an acknowledgement succeeds');
select is((select result #>> '{entity,status}' from p2_d05a_results where key = 'ack_create'), 'dismissed', 'the acknowledged status is stored');
select is((select result #>> '{entity,version}' from p2_d05a_results where key = 'ack_create'), '1', 'a new acknowledgement starts at version 1');

-- Re-creating the same signal without expected_version is a conflict, not a
-- silent overwrite.
insert into p2_d05a_results (key, result)
select 'ack_recreate', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'lease_expiry', 'resolved',
  'de000000-0000-0000-0000-000000000002', 'df000000-0000-0000-0000-000000000002',
  'd9000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  'd8000000-0000-0000-0000-000000000001'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'ack_recreate'), 'version_conflict', 'creating over an existing acknowledgement without a version is a conflict');

-- Stale version is rejected.
insert into p2_d05a_results (key, result)
select 'ack_stale', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'lease_expiry', 'resolved',
  'de000000-0000-0000-0000-000000000003', 'df000000-0000-0000-0000-000000000003',
  'd9000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  'd8000000-0000-0000-0000-000000000001', 99
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'ack_stale'), 'version_conflict', 'an expected_version mismatch is rejected');

-- Correct version transitions successfully.
insert into p2_d05a_results (key, result)
select 'ack_update', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'lease_expiry', 'resolved',
  'de000000-0000-0000-0000-000000000004', 'df000000-0000-0000-0000-000000000004',
  'd9000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  'd8000000-0000-0000-0000-000000000001', 1, null, 'renewed'
);
select is((select result #>> '{entity,status}' from p2_d05a_results where key = 'ack_update'), 'resolved', 'a correctly versioned transition succeeds');
select is((select result #>> '{entity,version}' from p2_d05a_results where key = 'ack_update'), '2', 'the version increments');

-- The read side reflects the acknowledgement.
insert into p2_d05a_results (key, result)
select 'signals_after_ack', public.operations_signals(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001'
);
select is(
  (select signal ->> 'status'
   from p2_d05a_results, jsonb_array_elements(result #> '{entity,signals}') as signal
   where key = 'signals_after_ack' and signal ->> 'lease_id' = 'dc000000-0000-0000-0000-000000000001'),
  'resolved',
  'operations_signals reports the acknowledged status'
);

-- Unknown signal type / status are rejected.
insert into p2_d05a_results (key, result)
select 'ack_bad_type', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'not_a_real_type', 'dismissed',
  'de000000-0000-0000-0000-000000000005', 'df000000-0000-0000-0000-000000000005'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'ack_bad_type'), 'validation_failed', 'an unknown signal type is rejected');

insert into p2_d05a_results (key, result)
select 'ack_bad_status', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'stale_rent_roll', 'archived',
  'de000000-0000-0000-0000-000000000006', 'df000000-0000-0000-0000-000000000006'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'ack_bad_status'), 'validation_failed', 'an unknown status is rejected');

-- A reader (lease.read only) cannot write.
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000002', true);
insert into p2_d05a_results (key, result)
select 'ack_forbidden', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'stale_rent_roll', 'dismissed',
  'de000000-0000-0000-0000-000000000007', 'df000000-0000-0000-0000-000000000007'
);
select is((select result #>> '{error,code}' from p2_d05a_results where key = 'ack_forbidden'), 'forbidden', 'a reader without lease.manage cannot acknowledge a signal');

-- Idempotent replay: same mutation id returns the same result without a
-- second version bump.
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);
insert into p2_d05a_results (key, result)
select 'ack_replay', public.update_operations_signal_status(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'lease_expiry', 'resolved',
  'de000000-0000-0000-0000-000000000004', 'df000000-0000-0000-0000-000000000004',
  'd9000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  'd8000000-0000-0000-0000-000000000001', 1, null, 'renewed'
);
select is((select result #>> '{entity,version}' from p2_d05a_results where key = 'ack_replay'), '2', 'replaying the same mutation id does not bump the version again');

-- The audit trail carries both the create and the update.
select is(
  (select count(*)::integer
   from public.audit_events as audit
   where audit.workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and audit.entity_type = 'operations_signal_state'
     and audit.action = 'operations_signal.update_status'),
  2,
  'both the create and the version transition are audited'
);

select * from finish();

rollback;
