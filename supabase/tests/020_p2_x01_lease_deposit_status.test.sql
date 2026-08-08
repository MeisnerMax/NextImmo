begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- =============================================================================
-- P2-X01-AP4 stage 3: the lease deposit status. Asserts the column, the value
-- guard, the amount dependency, and that the P2-D05 contract underneath is
-- unchanged.
-- =============================================================================

select has_column('public', 'leases', 'deposit_status', 'deposit_status exists');
select col_type_is('public', 'leases', 'deposit_status', 'text', 'deposit_status is text');

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-4000-8000-000000000001', 'deposit-status', 'Deposit Status');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country,
  property_type, units, status, created_by, updated_by
) values (
  'f7000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
  'Deposit Target', 'Deposit Street 1', '10115', 'Berlin', 'de', 'multifamily',
  1, 'active',
  'f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values (
  'f8000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000001', 'WE-01', 'vacant',
  'f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000001'
);

insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values (
  'f9000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
  'person', 'Deposit Tenant',
  'f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000001'
);

insert into public.leases (
  id, workspace_id, property_id, unit_id, tenant_party_id, lease_name, status,
  start_date, base_rent_monthly, currency_code, security_deposit,
  billing_frequency, created_by, updated_by
) values (
  'fa000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000001', 'f8000000-0000-4000-8000-000000000001',
  'f9000000-0000-4000-8000-000000000001', 'Deposit Lease', 'draft',
  '2026-01-01', 850, 'EUR', 2550, 'monthly',
  'f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000001'
);

-- The column is optional: a lease without a known deposit state is honest null
-- rather than an invented default.
select lives_ok(
  $$update public.leases set deposit_status = null
     where id = 'fa000000-0000-4000-8000-000000000001'$$,
  'deposit_status is nullable'
);
select lives_ok(
  $$update public.leases set deposit_status = 'open'
     where id = 'fa000000-0000-4000-8000-000000000001'$$,
  'open is accepted'
);
select lives_ok(
  $$update public.leases set deposit_status = 'paid'
     where id = 'fa000000-0000-4000-8000-000000000001'$$,
  'paid is accepted'
);
select throws_ok(
  $$update public.leases set deposit_status = 'partial'
     where id = 'fa000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'an unmodelled deposit state is rejected'
);

-- A payment state without an amount would describe money that does not exist.
select throws_ok(
  $$update public.leases
       set deposit_status = 'paid', security_deposit = null
     where id = 'fa000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'deposit_status without a deposit amount is rejected'
);

select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.leases'::regclass),
  'row level security stays enabled and forced'
);
select ok(
  not has_table_privilege('anon', 'public.leases', 'select'),
  'anon still cannot read leases'
);

select * from finish();

rollback;
