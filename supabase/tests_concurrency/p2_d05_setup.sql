\set ON_ERROR_STOP on

-- P2-D05 gate: two-session lease-mutation concurrency.
--
-- The lease starts at `landlord_signed` and the unit at `vacant`, so both
-- sessions race on the one lease mutation that also has a side effect —
-- activation flips the unit's occupancy through private.sync_unit_occupancy.
-- Racing an ordinary attribute update would only re-test what P1-004 already
-- proves about optimistic concurrency; racing the activation additionally
-- proves that AGG-004 cannot be broken by two writers agreeing on a stale
-- version.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ec000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'p2-d05-concurrency@example.test', '', now(),
  '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('ec000000-0000-0000-0000-000000000010', 'p2-d05-concurrency', 'P2-D05 Concurrency');

insert into public.roles (id, workspace_id, key, name)
values (
  'ec000000-0000-0000-0000-000000000011',
  'ec000000-0000-0000-0000-000000000010',
  'manager', 'Manager'
);

insert into public.permissions (id, key, name) values
  ('ec000000-0000-0000-0000-000000000012', 'lease.read', 'Lease Read'),
  ('ec000000-0000-0000-0000-000000000013', 'lease.manage', 'Lease Manage');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  (
    'ec000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000011',
    'ec000000-0000-0000-0000-000000000012'
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000011',
    'ec000000-0000-0000-0000-000000000013'
  );

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  'ec000000-0000-0000-0000-000000000010',
  'ec000000-0000-0000-0000-000000000001',
  'ec000000-0000-0000-0000-000000000011',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  'ec000000-0000-0000-0000-000000000020',
  'ec000000-0000-0000-0000-000000000010',
  'Concurrency Objekt', 'Concurrency Street 1', '10115', 'Berlin', 'de',
  'residential', 1, 'active',
  'ec000000-0000-0000-0000-000000000001',
  'ec000000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values (
  'ec000000-0000-0000-0000-000000000030',
  'ec000000-0000-0000-0000-000000000010',
  'ec000000-0000-0000-0000-000000000020',
  'C-01', 'vacant',
  'ec000000-0000-0000-0000-000000000001',
  'ec000000-0000-0000-0000-000000000001'
);

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status, start_date,
  base_rent_monthly, currency_code, created_by, updated_by
) values (
  'ec000000-0000-0000-0000-000000000040',
  'ec000000-0000-0000-0000-000000000010',
  'ec000000-0000-0000-0000-000000000020',
  'ec000000-0000-0000-0000-000000000030',
  'Concurrency Vertrag', 'landlord_signed', date '2026-01-01',
  1000, 'EUR',
  'ec000000-0000-0000-0000-000000000001',
  'ec000000-0000-0000-0000-000000000001'
);
