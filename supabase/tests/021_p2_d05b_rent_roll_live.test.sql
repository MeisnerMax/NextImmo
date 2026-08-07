begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- === Surface ==========================================================

select has_function('public', 'rent_roll_live', array['uuid', 'uuid', 'date']);
select has_function('private', 'rent_roll_unit_currencies', array['uuid', 'uuid', 'date']);

select ok(
  (select function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   from pg_proc as function
   join pg_roles as owner on owner.oid = function.proowner
   where function.oid = 'public.rent_roll_live(uuid, uuid, date)'::regprocedure),
  'rent_roll_live is a hardened security-definer function'
);

-- A read is not a mutation: it must not be volatile, and it must not be
-- reachable anonymously.
select is(
  (select function.provolatile
   from pg_proc as function
   where function.oid = 'public.rent_roll_live(uuid, uuid, date)'::regprocedure),
  's'::"char",
  'rent_roll_live is stable — it computes, it does not write'
);
select ok(
  not has_function_privilege(
    'anon', 'public.rent_roll_live(uuid, uuid, date)', 'execute'
  ),
  'anon cannot read a rent roll'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.rent_roll_live(uuid, uuid, date)', 'execute'
  ),
  'authenticated may, subject to lease.read'
);

-- === Fixture ==========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05b-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('da000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05b-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'p2d05b-workspace', 'P2D05b Workspace');

insert into public.roles (id, workspace_id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('d3000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'nobody', 'No leasing rights');

insert into public.permissions (id, key, name) values
  ('d5000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('d5000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('d5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read')
on conflict (key) do nothing;

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'd1000000-0000-0000-0000-000000000001',
       'd3000000-0000-0000-0000-000000000001',
       permission.id
from public.permissions as permission
where permission.key in ('lease.read', 'lease.manage', 'workspace.read');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'active'),
  ('d6000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000002', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'd7000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000001',
  'Live Rent Roll Haus', 'Musterweg 1', '10115', 'Berlin', 'de', 'residential',
  'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'
);

create temporary table p2_d05b_results (key text primary key, result jsonb);
grant all on table p2_d05b_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

-- Two units: one let by two concurrent leases (OPN-DOM-001), one vacant.
insert into p2_d05b_results (key, result)
select 'unit_1', public.create_unit(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'EG-links', 'de000000-0000-0000-0000-000000000001',
  'dc000000-0000-0000-0000-000000000001', null, null, 60.0
);
insert into p2_d05b_results (key, result)
select 'unit_2', public.create_unit(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  'EG-rechts', 'de000000-0000-0000-0000-000000000002',
  'dc000000-0000-0000-0000-000000000002', null, null, 45.0
);

create function pg_temp.activate(p_lease_id uuid, p_seed text)
returns jsonb
language plpgsql
as $$
declare
  v_target public.lease_status;
  v_result jsonb;
  v_step integer := 0;
begin
  foreach v_target in array array[
    'reviewed'::public.lease_status, 'sent'::public.lease_status,
    'tenant_signed'::public.lease_status, 'landlord_signed'::public.lease_status,
    'active'::public.lease_status
  ] loop
    v_step := v_step + 1;
    v_result := public.transition_lease_status(
      'd1000000-0000-0000-0000-000000000001',
      p_lease_id,
      (select version from public.leases where id = p_lease_id),
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

insert into p2_d05b_results (key, result)
select 'lease_a', public.create_lease(
  'd1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'unit_1'),
  'Hauptvertrag', date '2026-01-01', 1000, 'EUR',
  'de000000-0000-0000-0000-000000000011', 'dc000000-0000-0000-0000-000000000011',
  null, null, null, null, 100, 50
);
insert into p2_d05b_results (key, result)
select 'lease_a_active', pg_temp.activate(
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'lease_a'),
  'lease-a'
);

insert into p2_d05b_results (key, result)
select 'lease_b', public.create_lease(
  'd1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'unit_1'),
  'Teilflaeche', date '2026-01-01', 250, 'EUR',
  'de000000-0000-0000-0000-000000000012', 'dc000000-0000-0000-0000-000000000012'
);
insert into p2_d05b_results (key, result)
select 'lease_b_active', pg_temp.activate(
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'lease_b'),
  'lease-b'
);

-- === The live read ====================================================

insert into p2_d05b_results (key, result)
select 'live', public.rent_roll_live(
  'd1000000-0000-0000-0000-000000000001',
  'd7000000-0000-0000-0000-000000000001',
  date '2026-03-31'
);

select is((select result ->> 'ok' from p2_d05b_results where key = 'live'), 'true', 'rent_roll_live answers without freezing anything');
select is((select result #>> '{entity,unit_count}' from p2_d05b_results where key = 'live'), '2', 'every unit of the property gets a line');
select is((select result #>> '{entity,occupied_unit_count}' from p2_d05b_results where key = 'live'), '1', 'occupancy is partitioned by unit status');
select is((select result #>> '{entity,vacant_unit_count}' from p2_d05b_results where key = 'live'), '1', 'the vacant unit is counted as vacant');
select is((select result #>> '{entity,currency_code}' from p2_d05b_results where key = 'live'), 'EUR', 'a single-currency property reports its currency');
select is((select (result #>> '{entity,total_rent_monthly}')::numeric from p2_d05b_results where key = 'live'), 1400::numeric, 'the total sums base, ancillary and parking over both leases');
select is((select jsonb_array_length(result #> '{entity,lines}') from p2_d05b_results where key = 'live'), 2, 'the document carries its lines');

-- OPN-DOM-001: one line per unit, carrying the sum of its concurrent leases.
select is(
  (select line ->> 'effective_lease_count'
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'live' and line ->> 'unit_code' = 'EG-links'),
  '2',
  'OPN-DOM-001: the unit with two effective leases has one line counting both'
);
select is(
  (select (line ->> 'base_rent_monthly')::numeric
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'live' and line ->> 'unit_code' = 'EG-links'),
  1250::numeric,
  'and its base rent is the sum, not one of the two'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'live' and line ->> 'unit_code' = 'EG-rechts'),
  0::numeric,
  'a vacant unit contributes zero rather than being omitted'
);

-- === Parity with the frozen document ==================================
--
-- The whole point of P2-D05b: live and frozen are computed from the same
-- helpers, so for the same date on unchanged data they must agree figure for
-- figure. If this ever fails, one of the two has drifted.

insert into p2_d05b_results (key, result)
select 'snapshot', public.create_rent_roll_snapshot(
  'd1000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
  date '2026-03-31', 'de000000-0000-0000-0000-000000000091',
  'dc000000-0000-0000-0000-000000000091'
);
select is((select result ->> 'ok' from p2_d05b_results where key = 'snapshot'), 'true', 'the same property can still be frozen');

select is(
  (select (live.result #> '{entity}') - 'computed_at' - 'currencies' - 'lines'
     || jsonb_build_object('x', 1)
   from p2_d05b_results as live where live.key = 'live'),
  (select (snap.result #> '{entity}')
     - 'id' - 'generated_at' - 'created_at' - 'created_by' - 'lines'
     || jsonb_build_object('x', 1)
   from p2_d05b_results as snap where snap.key = 'snapshot'),
  'live and frozen headers agree figure for figure for the same date'
);

select is(
  (select jsonb_agg(line - 'currency_code' - 'currencies' order by line ->> 'unit_code')
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'live'),
  (select jsonb_agg(line - 'id' order by line ->> 'unit_code')
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot'),
  'and so do their lines'
);

-- === The two helpers agree ===========================================
--
-- rent_roll_unit_currencies repeats the effective-lease predicate of
-- rent_roll_unit_rows. This pins that they say the same thing about every unit.

set local role postgres;
select is(
  (select count(*)::integer
   from private.rent_roll_unit_rows(
     'd1000000-0000-0000-0000-000000000001',
     'd7000000-0000-0000-0000-000000000001', date '2026-03-31'
   ) as unit_row
   join private.rent_roll_unit_currencies(
     'd1000000-0000-0000-0000-000000000001',
     'd7000000-0000-0000-0000-000000000001', date '2026-03-31'
   ) as unit_currency on unit_currency.unit_id = unit_row.unit_id
   where (unit_row.effective_lease_count > 0)
     <> (coalesce(array_length(unit_currency.currencies, 1), 0) > 0)),
  0,
  'a unit contributes rent exactly when it has contributing currencies'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

-- === Mixed currencies =================================================
--
-- A snapshot is refused (DEC-011). A live read cannot refuse to show the
-- property, so it answers with null totals and names the currencies.

insert into p2_d05b_results (key, result)
select 'lease_chf', public.create_lease(
  'd1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'unit_2'),
  'Vertrag in Franken', date '2026-01-01', 900, 'CHF',
  'de000000-0000-0000-0000-000000000021', 'dc000000-0000-0000-0000-000000000021'
);
insert into p2_d05b_results (key, result)
select 'lease_chf_active', pg_temp.activate(
  (select (result #>> '{entity,id}')::uuid from p2_d05b_results where key = 'lease_chf'),
  'lease-chf'
);

insert into p2_d05b_results (key, result)
select 'live_mixed', public.rent_roll_live(
  'd1000000-0000-0000-0000-000000000001',
  'd7000000-0000-0000-0000-000000000001',
  date '2026-03-31'
);

select is((select result ->> 'ok' from p2_d05b_results where key = 'live_mixed'), 'true', 'a mixed-currency property still gets a live answer');
select is((select result #>> '{entity,currencies}' from p2_d05b_results where key = 'live_mixed'), '["CHF", "EUR"]', 'and it names every currency it found');
select ok(
  (select result #> '{entity,total_rent_monthly}' = 'null'::jsonb
   from p2_d05b_results where key = 'live_mixed'),
  'the total is null rather than a cross-currency sum (DEC-011)'
);
select is(
  (select line ->> 'currency_code'
   from p2_d05b_results, jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'live_mixed' and line ->> 'unit_code' = 'EG-rechts'),
  'CHF',
  'a unit whose leases share a currency still reports it'
);

-- === Permissions and isolation ========================================

select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000002', true);
select is(
  (select public.rent_roll_live(
     'd1000000-0000-0000-0000-000000000001',
     'd7000000-0000-0000-0000-000000000001', date '2026-03-31'
   ) #>> '{error,code}'),
  'forbidden',
  'a member without lease.read is refused'
);

select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);
select is(
  (select public.rent_roll_live(
     'd1000000-0000-0000-0000-000000000001',
     'd7000000-0000-0000-0000-000000000009', date '2026-03-31'
   ) #>> '{error,code}'),
  'not_found',
  'a property of another workspace is not found, not leaked'
);
select is(
  (select public.rent_roll_live(
     'd1000000-0000-0000-0000-000000000001', null, date '2026-03-31'
   ) #>> '{error,code}'),
  'validation_failed',
  'missing arguments are refused before anything is read'
);

select * from finish();

rollback;
