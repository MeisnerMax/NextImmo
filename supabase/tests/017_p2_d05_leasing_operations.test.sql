begin;

create extension if not exists pgtap with schema extensions;

select plan(108);

-- === Schema surface ===================================================

select has_table('public', 'units', 'units table exists');
select has_table('public', 'leases', 'leases table exists');
select has_type('public', 'unit_status', 'unit_status enum exists');
select has_type('public', 'lease_status', 'lease_status enum exists');

-- STM-003 / STM-005 vocabulary, in the documented order.
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.unit_status'::regtype),
  array['vacant', 'occupied', 'offline'],
  'unit_status carries the STM-003 labels'
);
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.lease_status'::regtype),
  array['draft', 'reviewed', 'sent', 'tenant_signed', 'landlord_signed',
        'active', 'ended', 'cancelled'],
  'lease_status carries the STM-005 labels'
);

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in ('public.units'::regclass, 'public.leases'::regclass)),
  'all P2-D05 tables enable and force RLS'
);
select policies_are('public', 'units', array['units_select_lease_read']);
select policies_are('public', 'leases', array['leases_select_lease_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('units', 'leases')
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no leasing DML grants'
);

select has_function('public', 'create_unit', array['uuid', 'uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'text', 'text', 'text', 'date', 'text', 'text', 'text']);
select has_function('public', 'update_unit', array['uuid', 'uuid', 'bigint', 'jsonb', 'uuid', 'uuid', 'text']);
select has_function('public', 'transition_unit_status', array['uuid', 'uuid', 'bigint', 'unit_status', 'uuid', 'uuid', 'text']);
select has_function('public', 'create_lease', array['uuid', 'uuid', 'text', 'date', 'numeric', 'text', 'uuid', 'uuid', 'uuid', 'date', 'date', 'date', 'numeric', 'numeric', 'numeric', 'integer', 'text', 'integer', 'text', 'text']);
select has_function('public', 'update_lease', array['uuid', 'uuid', 'bigint', 'jsonb', 'uuid', 'uuid', 'text']);
select has_function('public', 'transition_lease_status', array['uuid', 'uuid', 'bigint', 'lease_status', 'uuid', 'uuid', 'date', 'text']);

select ok(
  (select bool_and(
     function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in (
       'create_unit', 'update_unit', 'transition_unit_status',
       'create_lease', 'update_lease', 'transition_lease_status'
     )),
  'leasing RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_unit', 'update_unit', 'transition_unit_status',
       'create_lease', 'update_lease', 'transition_lease_status'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute leasing RPCs'
);

-- === OPN-DOM-001, asserted structurally ===============================
--
-- The decision of 2026-07-29 overrode the documented default: a unit may hold
-- several concurrently effective leases. The absence of a uniqueness guard is
-- therefore a REQUIREMENT, not an oversight, and is asserted here so that
-- re-adding one later fails this test instead of silently reversing a decision.

select is(
  (select count(*)::integer
   from pg_index as index
   join pg_class as index_class on index_class.oid = index.indexrelid
   where index.indrelid = 'public.leases'::regclass
     and index.indisunique
     and 'unit_id' = any (
       select attribute.attname
       from pg_attribute as attribute
       where attribute.attrelid = 'public.leases'::regclass
         and attribute.attnum = any (index.indkey)
     )),
  0,
  'OPN-DOM-001: no unique index constrains leases per unit'
);
select is(
  (select count(*)::integer
   from pg_constraint as constraint_row
   where constraint_row.conrelid = 'public.leases'::regclass
     and constraint_row.contype in ('u', 'x')
     and 'unit_id' = any (
       select attribute.attname
       from pg_attribute as attribute
       where attribute.attrelid = 'public.leases'::regclass
         and attribute.attnum = any (constraint_row.conkey)
     )),
  0,
  'OPN-DOM-001: no unique or exclusion constraint constrains leases per unit'
);
-- The partial index that serves the occupancy count must stay non-unique.
select ok(
  not (select index.indisunique
       from pg_index as index
       join pg_class as index_class on index_class.oid = index.indexrelid
       where index.indrelid = 'public.leases'::regclass
         and index_class.relname = 'leases_unit_effective_idx'),
  'the effective-lease index is deliberately non-unique'
);

select has_function('private', 'assert_unit_occupancy', array['uuid', 'uuid']);
select has_function('private', 'unit_effective_lease_count', array['uuid', 'uuid']);
select has_function('private', 'sync_unit_occupancy', array['uuid', 'uuid', 'uuid']);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ba000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ba000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('bb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('b1000000-0000-0000-0000-000000000001', 'p2d05-workspace-a', 'P2D05 Workspace A'),
  ('b2000000-0000-0000-0000-000000000001', 'p2d05-workspace-b', 'P2D05 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('b3000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('b3000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('b5000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('b5000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('b5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read'),
  ('b5000000-0000-0000-0000-000000000004', 'audit.read', 'Audit Read'),
  ('b5000000-0000-0000-0000-000000000005', 'party.read', 'Party Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- Manager A: read + manage, plus party.read/audit.read so the assertions below
  -- read through RLS rather than around it.
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000002'),
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000003'),
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000004'),
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000005'),
  -- Reader A: lease.read only — may see units and leases, may not mutate either.
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-000000000003'),
  ('b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001'),
  ('b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000002'),
  ('b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('b6000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'active'),
  ('b6000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000002', 'active'),
  ('b6000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('b7000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
   'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b7000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001',
   'Objekt B', 'Nebenstrasse 2', '20095', 'Hamburg', 'de', 'residential',
   'bb000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001');

-- Tenants are Party roles (AGG-005 / P2-D02), not a separate person master.
insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values
  ('b8000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Meier',
   'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b8000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
   'organization', 'Bauunternehmen ohne Mieterrolle',
   'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001');

insert into public.party_roles (
  id, workspace_id, party_id, role_type, created_by, updated_by
) values
  ('b9000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
   'b8000000-0000-0000-0000-000000000001', 'tenant',
   'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b9000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
   'b8000000-0000-0000-0000-000000000002', 'contractor',
   'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001');

create temporary table p2_d05_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d05_results to authenticated;

-- Walks a lease from draft to active through the whole STM-005 chain. Kept as a
-- helper so the tests below read as statements about occupancy rather than as
-- five near-identical transition calls each time. Deliberately NOT security
-- definer: it must run with the caller's auth.uid().
create function pg_temp.activate_lease(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_seed text
)
returns jsonb
language plpgsql
as $$
declare
  v_targets public.lease_status[] := array[
    'reviewed'::public.lease_status,
    'sent'::public.lease_status,
    'tenant_signed'::public.lease_status,
    'landlord_signed'::public.lease_status,
    'active'::public.lease_status
  ];
  v_target public.lease_status;
  v_version bigint;
  v_result jsonb;
  v_step integer := 0;
begin
  foreach v_target in array v_targets loop
    v_step := v_step + 1;

    select lease.version into v_version
    from public.leases as lease
    where lease.workspace_id = p_workspace_id and lease.id = p_lease_id;

    v_result := public.transition_lease_status(
      p_workspace_id,
      p_lease_id,
      v_version,
      v_target,
      md5(p_seed || '-mutation-' || v_step)::uuid,
      md5(p_seed || '-correlation-' || v_step)::uuid
    );

    if v_result ->> 'ok' <> 'true' then
      return v_result;
    end if;
  end loop;

  return v_result;
end;
$$;

-- === create_unit ======================================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'ba000000-0000-0000-0000-000000000001', true);

insert into p2_d05_results (key, result)
select 'unit_1', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  '  EG-links  ', 'be000000-0000-0000-0000-000000000001',
  'bc000000-0000-0000-0000-000000000001',
  'apartment', '0', 68.5, 3, 1, 950, 1050, 'EUR'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'unit_1'), 'true', 'create_unit creates a unit');
select is((select result #>> '{entity,unit_code}' from p2_d05_results where key = 'unit_1'), 'EG-links', 'the unit code is trimmed');
select is((select result #>> '{entity,status}' from p2_d05_results where key = 'unit_1'), 'vacant', 'a new unit starts vacant (AGG-004: it has no lease)');
select is((select result #>> '{entity,version}' from p2_d05_results where key = 'unit_1'), '1', 'a new unit starts at version 1');
select isnt((select result #>> '{entity,vacancy_since}' from p2_d05_results where key = 'unit_1'), null, 'a new vacant unit records when the vacancy started');

insert into p2_d05_results (key, result)
select 'unit_2', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'EG-rechts', 'be000000-0000-0000-0000-000000000002',
  'bc000000-0000-0000-0000-000000000002',
  'apartment', '0', 54.0, 2, 1, 800, 850, 'EUR'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'unit_2'), 'true', 'create_unit creates a second unit');

-- Duplicate code within the same property is rejected.
insert into p2_d05_results (key, result)
select 'unit_dup', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'EG-links', 'be000000-0000-0000-0000-000000000003',
  'bc000000-0000-0000-0000-000000000003'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_dup'), 'validation_failed', 'a duplicate unit code is rejected');
select is((select result #>> '{error,field}' from p2_d05_results where key = 'unit_dup'), 'unit_code', 'the duplicate error names the unit code field');

-- DEC-011: a rent amount without a currency is not storable.
insert into p2_d05_results (key, result)
select 'unit_no_currency', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'OG-links', 'be000000-0000-0000-0000-000000000004',
  'bc000000-0000-0000-0000-000000000004',
  null, null, null, null, null, 900, null, null
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_no_currency'), 'validation_failed', 'DEC-011: a rent without a currency is rejected');
select is((select result #>> '{error,field}' from p2_d05_results where key = 'unit_no_currency'), 'currency_code', 'the currency error names the currency field');

-- A property from another workspace is not found, not forbidden: the caller must
-- not learn that the id exists elsewhere.
insert into p2_d05_results (key, result)
select 'unit_foreign_property', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000002',
  'FREMD', 'be000000-0000-0000-0000-000000000005',
  'bc000000-0000-0000-0000-000000000005'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_foreign_property'), 'not_found', 'a property of another workspace is not found');

reset role;

-- lease.read alone must not be able to create a unit.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ba000000-0000-0000-0000-000000000002', true);

insert into p2_d05_results (key, result)
select 'unit_reader', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'READER', 'be000000-0000-0000-0000-000000000006',
  'bc000000-0000-0000-0000-000000000006'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_reader'), 'forbidden', 'lease.read alone cannot create a unit');
select is(
  (select count(*)::integer from public.units
   where workspace_id = 'b1000000-0000-0000-0000-000000000001'),
  2,
  'a reader still sees the workspace units through RLS'
);

reset role;

-- === create_lease =====================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ba000000-0000-0000-0000-000000000001', true);

insert into p2_d05_results (key, result)
select 'lease_1', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid,
  'Mietvertrag EG-links Teilflaeche 1', '2026-08-01', 620, 'EUR',
  'be000000-0000-0000-0000-000000000011', 'bc000000-0000-0000-0000-000000000011',
  'b8000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_1'), 'true', 'create_lease creates a lease');
select is((select result #>> '{entity,status}' from p2_d05_results where key = 'lease_1'), 'draft', 'a new lease starts in draft (STM-005)');
-- property_id is derived from the unit, never taken from the caller: it cannot
-- disagree with the unit's property.
select is(
  (select result #>> '{entity,property_id}' from p2_d05_results where key = 'lease_1'),
  'b7000000-0000-0000-0000-000000000001',
  'the lease inherits the property from its unit'
);
select is((select result #>> '{entity,currency_code}' from p2_d05_results where key = 'lease_1'), 'EUR', 'the lease carries its currency (DEC-011)');

-- A party without an open tenant role is a dependency conflict, not a not_found:
-- the party exists, it just is not a tenant.
insert into p2_d05_results (key, result)
select 'lease_wrong_role', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  'Mietvertrag mit Nicht-Mieter', '2026-08-01', 500, 'EUR',
  'be000000-0000-0000-0000-000000000012', 'bc000000-0000-0000-0000-000000000012',
  'b8000000-0000-0000-0000-000000000002'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_wrong_role'), 'dependency_conflict', 'AGG-005: a party without an open tenant role cannot be a lease tenant');
select is((select result #>> '{error,field}' from p2_d05_results where key = 'lease_wrong_role'), 'tenant_party_id', 'the tenant-role error names the tenant field');

insert into p2_d05_results (key, result)
select 'lease_bad_term', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  'Mietvertrag mit falscher Laufzeit', '2026-08-01', 500, 'EUR',
  'be000000-0000-0000-0000-000000000013', 'bc000000-0000-0000-0000-000000000013',
  null, '2026-07-01'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_bad_term'), 'validation_failed', 'an end date before the start date is rejected');

insert into p2_d05_results (key, result)
select 'lease_bad_currency', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  'Mietvertrag mit Fantasiewaehrung', '2026-08-01', 500, 'eur',
  'be000000-0000-0000-0000-000000000014', 'bc000000-0000-0000-0000-000000000014'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_bad_currency'), 'validation_failed', 'a non-ISO currency code is rejected');

-- === STM-005 transitions and derived occupancy ========================

-- Skipping a stage is not allowed.
insert into p2_d05_results (key, result)
select 'lease_skip', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_1')::uuid,
  1, 'active', 'be000000-0000-0000-0000-000000000015',
  'bc000000-0000-0000-0000-000000000015'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_skip'), 'validation_failed', 'STM-005 rejects draft -> active');
select is((select result #>> '{error,current_status}' from p2_d05_results where key = 'lease_skip'), 'draft', 'the rejected transition reports the current status');

-- A stale expected version is a conflict that hands back the current entity.
insert into p2_d05_results (key, result)
select 'lease_stale', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_1')::uuid,
  99, 'reviewed', 'be000000-0000-0000-0000-000000000016',
  'bc000000-0000-0000-0000-000000000016'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_stale'), 'version_conflict', 'a stale expected version conflicts');
select is((select result #>> '{error,actual_version}' from p2_d05_results where key = 'lease_stale'), '1', 'the conflict reports the actual version');
select isnt((select result #>> '{error,current_entity,id}' from p2_d05_results where key = 'lease_stale'), null, 'the conflict carries the current entity');

-- Now activate it for real, and watch the unit follow.
insert into p2_d05_results (key, result)
select 'lease_1_active', pg_temp.activate_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_1')::uuid,
  'p2d05-lease-1'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_1_active'), 'true', 'the full STM-005 chain to active succeeds');
select is((select result #>> '{entity,status}' from p2_d05_results where key = 'lease_1_active'), 'active', 'the lease is active');
select is(
  (select result #>> '{entity,unit,status}' from p2_d05_results where key = 'lease_1_active'),
  'occupied',
  'AGG-004: activating a lease flips its unit to occupied'
);
select is(
  (select result #>> '{entity,unit,vacancy_since}' from p2_d05_results where key = 'lease_1_active'),
  null,
  'an occupied unit carries no vacancy start'
);

-- === OPN-DOM-001: several effective leases on ONE unit are VALID ======
--
-- This is the first of the two directions the decision demands. The unit already
-- has one active lease; a second, overlapping one must be accepted, because the
-- unit is let in parts (Teilflaechen-Vermietung).

insert into p2_d05_results (key, result)
select 'lease_2', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid,
  'Mietvertrag EG-links Teilflaeche 2', '2026-09-01', 410, 'EUR',
  'be000000-0000-0000-0000-000000000021', 'bc000000-0000-0000-0000-000000000021'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_2'), 'true', 'OPN-DOM-001: a second lease on an occupied unit can be created');

insert into p2_d05_results (key, result)
select 'lease_2_active', pg_temp.activate_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_2')::uuid,
  'p2d05-lease-2'
);
select is(
  (select result ->> 'ok' from p2_d05_results where key = 'lease_2_active'),
  'true',
  'OPN-DOM-001: a SECOND concurrently effective lease on the same unit is accepted'
);
-- Counted through RLS rather than via private.unit_effective_lease_count: that
-- helper is correctly revoked from authenticated, and asserting the same fact
-- from the client's own view is the stronger statement anyway.
select is(
  (select count(*)::integer from public.leases as lease
   where lease.unit_id
       = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid
     and lease.status = 'active'),
  2,
  'OPN-DOM-001: the unit now carries two concurrently effective leases'
);
select is(
  (select status::text from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid),
  'occupied',
  'AGG-004 reworded: occupied means AT LEAST ONE effective lease'
);

-- Ending ONE of the two must NOT vacate the unit. This is exactly where the
-- overridden default would have produced the wrong answer.
insert into p2_d05_results (key, result)
select 'lease_1_ended', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_1')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_1')::uuid),
  'ended', 'be000000-0000-0000-0000-000000000031',
  'bc000000-0000-0000-0000-000000000031', '2026-10-31'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_1_ended'), 'true', 'ending a lease succeeds');
select isnt((select result #>> '{entity,ended_at}' from p2_d05_results where key = 'lease_1_ended'), null, 'an ended lease carries its ended_at marker');
select is(
  (select result #>> '{entity,unit,status}' from p2_d05_results where key = 'lease_1_ended'),
  'occupied',
  'OPN-DOM-001: ending ONE of two effective leases leaves the unit occupied'
);
select is(
  (select count(*)::integer from public.leases as lease
   where lease.unit_id
       = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid
     and lease.status = 'active'),
  1,
  'one effective lease remains'
);

-- Ending the last one vacates it.
insert into p2_d05_results (key, result)
select 'lease_2_ended', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_2')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_2')::uuid),
  'ended', 'be000000-0000-0000-0000-000000000032',
  'bc000000-0000-0000-0000-000000000032'
);
select is(
  (select result #>> '{entity,unit,status}' from p2_d05_results where key = 'lease_2_ended'),
  'vacant',
  'AGG-004: ending the LAST effective lease vacates the unit'
);
select isnt(
  (select result #>> '{entity,unit,vacancy_since}' from p2_d05_results where key = 'lease_2_ended'),
  null,
  'the freshly vacated unit records when the vacancy started'
);

-- A terminal lease is terminal.
insert into p2_d05_results (key, result)
select 'lease_2_reopen', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_2')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_2')::uuid),
  'active', 'be000000-0000-0000-0000-000000000033',
  'bc000000-0000-0000-0000-000000000033'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_2_reopen'), 'validation_failed', 'STM-005: an ended lease cannot be reactivated');

-- An active lease is no longer editable in place.
insert into p2_d05_results (key, result)
select 'lease_3', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  'Mietvertrag EG-rechts', '2026-08-01', 780, 'EUR',
  'be000000-0000-0000-0000-000000000041', 'bc000000-0000-0000-0000-000000000041',
  'b8000000-0000-0000-0000-000000000001'
);
insert into p2_d05_results (key, result)
select 'lease_3_edit_draft', public.update_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid,
  1, '{"base_rent_monthly": 800}'::jsonb,
  'be000000-0000-0000-0000-000000000042', 'bc000000-0000-0000-0000-000000000042'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_3_edit_draft'), 'true', 'a draft lease is editable');
select is((select result #>> '{entity,base_rent_monthly}' from p2_d05_results where key = 'lease_3_edit_draft'), '800', 'the edit applied');

insert into p2_d05_results (key, result)
select 'lease_3_active', pg_temp.activate_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid,
  'p2d05-lease-3'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_3_active'), 'true', 'lease 3 reaches active');

insert into p2_d05_results (key, result)
select 'lease_3_edit_active', public.update_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid),
  '{"base_rent_monthly": 1200}'::jsonb,
  'be000000-0000-0000-0000-000000000043', 'bc000000-0000-0000-0000-000000000043'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_3_edit_active'), 'dependency_conflict', 'an active lease is not editable in place');

-- Unknown change keys are refused rather than silently ignored.
insert into p2_d05_results (key, result)
select 'lease_unknown_key', public.update_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid),
  '{"status": "ended"}'::jsonb,
  'be000000-0000-0000-0000-000000000044', 'bc000000-0000-0000-0000-000000000044'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_unknown_key'), 'validation_failed', 'update_lease refuses to smuggle a status change through changes');

-- Cancelling requires a reason and is allowed from a non-terminal state.
insert into p2_d05_results (key, result)
select 'lease_4', public.create_lease(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  'Mietvertrag der abgebrochen wird', '2026-08-01', 500, 'EUR',
  'be000000-0000-0000-0000-000000000051', 'bc000000-0000-0000-0000-000000000051'
);
insert into p2_d05_results (key, result)
select 'lease_4_cancel_no_reason', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_4')::uuid,
  1, 'cancelled', 'be000000-0000-0000-0000-000000000052',
  'bc000000-0000-0000-0000-000000000052'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_4_cancel_no_reason'), 'validation_failed', 'cancelling a lease without a reason is rejected');

insert into p2_d05_results (key, result)
select 'lease_4_cancel', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_4')::uuid,
  1, 'cancelled', 'be000000-0000-0000-0000-000000000053',
  'bc000000-0000-0000-0000-000000000053', null, 'Mieter hat abgesagt'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'lease_4_cancel'), 'true', 'STM-005: a draft lease can be cancelled with a reason');
select isnt((select result #>> '{entity,cancelled_at}' from p2_d05_results where key = 'lease_4_cancel'), null, 'a cancelled lease carries its cancelled_at marker');
select is(
  (select result #>> '{entity,unit,status}' from p2_d05_results where key = 'lease_4_cancel'),
  'occupied',
  'cancelling a draft lease does not disturb the occupancy from other leases'
);

-- A move-out date only belongs to ending a lease.
insert into p2_d05_results (key, result)
select 'lease_move_out_misplaced', public.transition_lease_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid,
  (select version from public.leases
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'lease_3')::uuid),
  'cancelled', 'be000000-0000-0000-0000-000000000054',
  'bc000000-0000-0000-0000-000000000054', '2026-12-31', 'Abbruch mit Auszugsdatum'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_move_out_misplaced'), 'validation_failed', 'a move-out date is refused on a non-ending transition');

-- === STM-003: offline is the only manual unit status edge =============

insert into p2_d05_results (key, result)
select 'unit_2_offline_no_reason', public.transition_unit_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  (select version from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid),
  'offline', 'be000000-0000-0000-0000-000000000061',
  'bc000000-0000-0000-0000-000000000061'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_2_offline_no_reason'), 'validation_failed', 'STM-003: taking a unit offline requires a reason');

-- occupied -> offline WITH an effective lease running: the fire-damage case the
-- header documents. offline is exempt from AGG-004 on purpose.
insert into p2_d05_results (key, result)
select 'unit_2_offline', public.transition_unit_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  (select version from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid),
  'offline', 'be000000-0000-0000-0000-000000000062',
  'bc000000-0000-0000-0000-000000000062', 'Wasserschaden, Einheit unbewohnbar'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'unit_2_offline'), 'true', 'STM-003: an occupied unit can go offline with a reason');
select is((select result #>> '{entity,status}' from p2_d05_results where key = 'unit_2_offline'), 'offline', 'the unit is offline');
select is((select result #>> '{entity,offline_reason}' from p2_d05_results where key = 'unit_2_offline'), 'Wasserschaden, Einheit unbewohnbar', 'the offline reason is stored');
-- The evidenced occupancy check STM-003 asks for.
select is(
  (select audit.new_values ->> 'effective_lease_count_at_transition'
   from public.audit_events as audit
   where audit.mutation_id = 'be000000-0000-0000-0000-000000000062'),
  '1',
  'STM-003: the offline transition audits the effective-lease count it checked'
);

-- Occupancy itself is not settable by a caller.
insert into p2_d05_results (key, result)
select 'unit_1_manual_occupied', public.transition_unit_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid,
  (select version from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid),
  'occupied', 'be000000-0000-0000-0000-000000000063',
  'bc000000-0000-0000-0000-000000000063'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_1_manual_occupied'), 'validation_failed', 'occupancy cannot be set directly; it is derived from leases');

-- Coming back from offline: the leases decide, and a contradicting request is
-- refused rather than quietly corrected.
insert into p2_d05_results (key, result)
select 'unit_2_back_wrong', public.transition_unit_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  (select version from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid),
  'vacant', 'be000000-0000-0000-0000-000000000064',
  'bc000000-0000-0000-0000-000000000064'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_2_back_wrong'), 'validation_failed', 'returning from offline to a status the leases contradict is refused');
select is((select result #>> '{error,derived_status}' from p2_d05_results where key = 'unit_2_back_wrong'), 'occupied', 'the refusal names the status the leases actually imply');

insert into p2_d05_results (key, result)
select 'unit_2_back', public.transition_unit_status(
  'b1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid,
  (select version from public.units
   where id = (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_2')::uuid),
  'occupied', 'be000000-0000-0000-0000-000000000065',
  'bc000000-0000-0000-0000-000000000065'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'unit_2_back'), 'true', 'a unit returns from offline to the status its leases imply');
select is((select result #>> '{entity,offline_reason}' from p2_d05_results where key = 'unit_2_back'), null, 'leaving offline clears the offline reason');

-- === Idempotency ======================================================

insert into p2_d05_results (key, result)
select 'unit_replay', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  '  EG-links  ', 'be000000-0000-0000-0000-000000000001',
  'bc000000-0000-0000-0000-000000000001',
  'apartment', '0', 68.5, 3, 1, 950, 1050, 'EUR'
);
select is((select result ->> 'ok' from p2_d05_results where key = 'unit_replay'), 'true', 'replaying a create with the same mutation id succeeds');
select is(
  (select (result #>> '{entity,id}') from p2_d05_results where key = 'unit_replay'),
  (select (result #>> '{entity,id}') from p2_d05_results where key = 'unit_1'),
  'the replay returns the original entity instead of creating a second unit'
);
select is(
  (select count(*)::integer from public.units
   where workspace_id = 'b1000000-0000-0000-0000-000000000001'),
  2,
  'the replay created no additional unit'
);

insert into p2_d05_results (key, result)
select 'unit_mutation_reuse', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'ANDERS', 'be000000-0000-0000-0000-000000000001',
  'bc000000-0000-0000-0000-000000000001'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_mutation_reuse'), 'mutation_conflict', 'reusing a mutation id for a different command conflicts');

-- === Audit trail ======================================================

select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'b1000000-0000-0000-0000-000000000001'
     and entity_type = 'unit' and action = 'unit.create'),
  2,
  'every unit creation wrote exactly one audit event'
);
select is(
  (select array_agg(distinct action order by action) from public.audit_events
   where workspace_id = 'b1000000-0000-0000-0000-000000000001'
     and entity_type = 'lease'),
  array['lease.create', 'lease.transition_status', 'lease.update'],
  'lease audit actions name every command that ran, not just a count'
);
select is(
  (select audit.old_values #>> '{status}' from public.audit_events as audit
   where audit.mutation_id = 'be000000-0000-0000-0000-000000000031'),
  'active',
  'the ending transition audits the previous lease status'
);
select is(
  (select audit.new_values #>> '{unit,status}' from public.audit_events as audit
   where audit.mutation_id = 'be000000-0000-0000-0000-000000000032'),
  'vacant',
  'the ending transition audits the resulting unit status'
);
select ok(
  (select bool_and(audit.actor_user_id = 'ba000000-0000-0000-0000-000000000001'
                   and audit.role_key = 'manager' and audit.source = 'rpc')
   from public.audit_events as audit
   where audit.workspace_id = 'b1000000-0000-0000-0000-000000000001'
     and audit.entity_type in ('unit', 'lease')),
  'leasing audit events carry actor, role and source'
);

reset role;

-- === Cross-workspace isolation ========================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'bb000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.units),
  0,
  'a manager of another workspace sees none of workspace A units'
);
select is(
  (select count(*)::integer from public.leases),
  0,
  'a manager of another workspace sees none of workspace A leases'
);

-- A foreign unit id must not be usable as a lease target. The id is taken from
-- the results table rather than from public.units on purpose: RLS would hide the
-- foreign row and the call would fail as a missing argument instead of proving
-- anything about workspace scoping.
insert into p2_d05_results (key, result)
select 'lease_foreign_unit', public.create_lease(
  'b2000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d05_results where key = 'unit_1')::uuid,
  'Fremdvertrag', '2026-08-01', 500, 'EUR',
  'be000000-0000-0000-0000-000000000071', 'bc000000-0000-0000-0000-000000000071'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'lease_foreign_unit'), 'not_found', 'a unit of another workspace is not a valid lease target');

-- Mutating workspace A from workspace B is forbidden, and reports as such
-- because the permission check precedes any lookup.
insert into p2_d05_results (key, result)
select 'unit_foreign_workspace', public.create_unit(
  'b1000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001',
  'FREMDZUGRIFF', 'be000000-0000-0000-0000-000000000072',
  'bc000000-0000-0000-0000-000000000072'
);
select is((select result #>> '{error,code}' from p2_d05_results where key = 'unit_foreign_workspace'), 'forbidden', 'creating a unit in a foreign workspace is forbidden');

reset role;

-- === Receipt hygiene ==================================================
--
-- Asserted as the owner because mutation_receipts carries no client grant at
-- all — clients never read their own receipts, they replay the command.

-- A rejected command must release its receipt, or the caller could never retry
-- with a corrected payload under the same mutation id.
select is(
  (select count(*)::integer from public.mutation_receipts
   where mutation_id = 'be000000-0000-0000-0000-000000000003'),
  0,
  'a rejected create releases its mutation receipt'
);
-- A succeeded command keeps its receipt: that is what makes the replay above
-- deterministic rather than a second insert.
select is(
  (select status from public.mutation_receipts
   where mutation_id = 'be000000-0000-0000-0000-000000000001'),
  'succeeded',
  'a successful create retains a succeeded receipt'
);

-- === AGG-004 as a structural invariant, both directions ===============
--
-- The gate the P2-D05 backlog entry asks for. These run as the table owner with
-- RLS and the RPCs entirely out of the picture, so what is proven is that the
-- invariant is enforced by the schema itself and not merely by well-behaved
-- callers. The triggers are deferred (so that a lease activation and its unit
-- flip may settle in either order inside one command), which is why each case
-- forces the check with SET CONSTRAINTS ALL IMMEDIATE.

-- Direction 1: `vacant` while an effective lease exists is invalid.
create function pg_temp.violate_vacant_with_effective_lease()
returns void
language plpgsql
as $$
begin
  update public.units
  set status = 'vacant'
  where id = (
    select lease.unit_id from public.leases as lease
    where lease.status = 'active'::public.lease_status
    limit 1
  );
  set constraints all immediate;
end;
$$;

select throws_ok(
  $$ select pg_temp.violate_vacant_with_effective_lease() $$,
  '23514',
  null,
  'AGG-004 direction 1: a vacant unit with an effective lease is rejected'
);

-- Direction 2: `occupied` without any effective lease is invalid.
create function pg_temp.violate_occupied_without_lease()
returns void
language plpgsql
as $$
declare
  v_unit_id uuid;
begin
  select unit.id into v_unit_id
  from public.units as unit
  where not exists (
    select 1 from public.leases as lease
    where lease.workspace_id = unit.workspace_id
      and lease.unit_id = unit.id
      and lease.status = 'active'::public.lease_status
  )
  limit 1;

  update public.units set status = 'occupied' where id = v_unit_id;
  set constraints all immediate;
end;
$$;

select throws_ok(
  $$ select pg_temp.violate_occupied_without_lease() $$,
  '23514',
  null,
  'AGG-004 direction 2: an occupied unit without any effective lease is rejected'
);

-- Direction 1 again, approached from the lease side: activating a lease under a
-- unit that is recorded as vacant is equally invalid. The invariant is enforced
-- on both tables, not just on units.
create function pg_temp.violate_activate_under_vacant_unit()
returns void
language plpgsql
as $$
declare
  v_lease_id uuid;
begin
  select lease.id into v_lease_id
  from public.leases as lease
  join public.units as unit
    on unit.workspace_id = lease.workspace_id and unit.id = lease.unit_id
  where lease.status = 'draft'::public.lease_status
    and unit.status = 'vacant'::public.unit_status
  limit 1;

  update public.leases set status = 'active' where id = v_lease_id;
  set constraints all immediate;
end;
$$;

-- A draft lease under a vacant unit is needed for that case; workspace B has no
-- units, so build the pair in workspace A as the owner.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values (
  'bf000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001', 'INVARIANT-PROBE', 'vacant',
  'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'
);
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status, start_date,
  base_rent_monthly, currency_code, created_by, updated_by
) values (
  'bf000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001', 'bf000000-0000-0000-0000-000000000001',
  'Probevertrag', 'draft', '2026-08-01', 500, 'EUR',
  'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$ select pg_temp.violate_activate_under_vacant_unit() $$,
  '23514',
  null,
  'AGG-004: activating a lease under a unit recorded as vacant is rejected'
);

-- And the positive control: the state the RPCs actually left behind satisfies
-- the invariant. Without this, the two throws_ok tests above would also pass
-- against a trigger that rejects everything.
select lives_ok(
  $$ set constraints all immediate $$,
  'AGG-004: the state produced by the RPCs satisfies the invariant'
);

-- offline is exempt, deliberately: a unit may be offline while a lease runs.
create function pg_temp.offline_with_effective_lease()
returns void
language plpgsql
as $$
begin
  update public.units
  set status = 'offline', offline_reason = 'Invariantentest'
  where id = (
    select lease.unit_id from public.leases as lease
    where lease.status = 'active'::public.lease_status
    limit 1
  );
  set constraints all immediate;
end;
$$;

select lives_ok(
  $$ select pg_temp.offline_with_effective_lease() $$,
  'STM-003: offline is exempt from the occupancy invariant, as documented'
);

-- === Protected columns and realtime ===================================

select throws_ok(
  $$ update public.units set workspace_id = 'b2000000-0000-0000-0000-000000000001'
     where id = 'bf000000-0000-0000-0000-000000000001' $$,
  '23000',
  null,
  'a unit cannot be moved to another workspace'
);
-- Re-pointed at a DIFFERENT unit than the one it already has: assigning the
-- current value would change nothing and the trigger would rightly stay quiet,
-- which would make this assertion vacuous.
select throws_ok(
  $$ update public.leases
     set unit_id = (select unit.id from public.units as unit
                    where unit.unit_code = 'EG-links')
     where id = 'bf000000-0000-0000-0000-000000000002' $$,
  '23000',
  null,
  'a lease cannot be re-pointed at another unit'
);

select ok(
  (select bool_and(published.count > 0)
   from (
     select count(*) as count
     from pg_publication_tables as publication
     where publication.pubname = 'supabase_realtime'
       and publication.schemaname = 'public'
       and publication.tablename in ('units', 'leases')
     group by publication.tablename
   ) as published),
  'both leasing aggregates are published for realtime invalidation'
);

select * from finish();

rollback;
