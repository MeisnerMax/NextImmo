begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-COMPONENTS-01c / DEC-029, owner decision of 2026-09-07.
--
-- The decision asked for two things on the write side and only one shipped: no
-- overlap per type (an EXCLUSION constraint, migration 54) and no gap inside
-- the term. The second is now a **reported state** rather than a write veto,
-- because a strict check would reject the first component of every type — the
-- first period can never cover a whole term.
--
-- So the thing under test is a claim about absence, and absence is where a
-- test is easiest to write badly. Two rules followed throughout:
--
--   * every "reports a gap" assertion is paired with a "reports no gap" one on
--     the same shape of data, so a function that always claimed a gap would
--     fail;
--   * the boundary cases are the assertions, not the happy path. Periods that
--     touch must not produce a phantom gap of zero days, and a fixed-term
--     lease must not be called incomplete for its own future.

select plan(19);

-- ---------------------------------------------------------------------------
-- Fixture: one property, four leases, each carrying one shape of coverage.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e1200000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'coverage-admin@example.test', '', now(), '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name) values
  ('e1100000-0000-0000-0000-000000000001', 'coverage', 'Coverage');
select private.seed_workspace_role_catalog('e1100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'e1400000-0000-0000-0000-000000000001',
  'e1100000-0000-0000-0000-000000000001',
  'e1200000-0000-0000-0000-000000000001',
  role.id, 'active'
from public.roles as role
where role.workspace_id = 'e1100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'e1500000-0000-0000-0000-000000000001', 'e1100000-0000-0000-0000-000000000001',
  'Deckungshaus', 'Deckungsweg 1', '10115', 'Berlin', 'de', 'residential', 4,
  'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
)
select
  ('e1600000-0000-0000-0000-00000000000' || n)::uuid,
  'e1100000-0000-0000-0000-000000000001',
  'e1500000-0000-0000-0000-000000000001',
  'A-0' || n, 'occupied',
  'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001'
from generate_series(1, 4) as n;

-- All four leases start on the same day and are open-ended, so the coverage
-- window is identical and the differences below are only about components.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, base_rent_monthly, currency_code, created_by, updated_by
)
select
  ('e1700000-0000-0000-0000-00000000000' || n)::uuid,
  'e1100000-0000-0000-0000-000000000001',
  'e1500000-0000-0000-0000-000000000001',
  ('e1600000-0000-0000-0000-00000000000' || n)::uuid,
  'Vertrag ' || n, 'active', date '2026-01-01', 1000, 'EUR',
  'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001'
from generate_series(1, 4) as n;

-- Lease 1: complete. Two periods that TOUCH, covering the term without a hole.
insert into public.lease_components (
  workspace_id, lease_id, component_type, valid_from, valid_to,
  amount, currency_code, created_by, updated_by
) values
  ('e1100000-0000-0000-0000-000000000001', 'e1700000-0000-0000-0000-000000000001',
   'base_rent', date '2026-01-01', date '2026-03-31', 1000, 'EUR',
   'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001'),
  ('e1100000-0000-0000-0000-000000000001', 'e1700000-0000-0000-0000-000000000001',
   'base_rent', date '2026-04-01', null, 1050, 'EUR',
   'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001');

-- Lease 2: a hole in the middle, and the component is in force again today.
insert into public.lease_components (
  workspace_id, lease_id, component_type, valid_from, valid_to,
  amount, currency_code, created_by, updated_by
) values
  ('e1100000-0000-0000-0000-000000000001', 'e1700000-0000-0000-0000-000000000002',
   'base_rent', date '2026-01-01', date '2026-02-28', 1000, 'EUR',
   'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001'),
  ('e1100000-0000-0000-0000-000000000001', 'e1700000-0000-0000-0000-000000000002',
   'base_rent', date '2026-04-01', null, 1000, 'EUR',
   'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001');

-- Lease 3: recorded and then ended. Nothing covers today.
insert into public.lease_components (
  workspace_id, lease_id, component_type, valid_from, valid_to,
  amount, currency_code, created_by, updated_by
) values
  ('e1100000-0000-0000-0000-000000000001', 'e1700000-0000-0000-0000-000000000003',
   'parking', date '2026-01-01', date '2026-05-31', 50, 'EUR',
   'e1200000-0000-0000-0000-000000000001', 'e1200000-0000-0000-0000-000000000001');

-- Lease 4 deliberately gets no components at all.

create or replace function pg_temp.coverage(p_lease uuid, p_as_of date)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', 'e1200000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.lease_components_as_of(
    'e1100000-0000-0000-0000-000000000001'::uuid, p_as_of, p_lease
  ) #> '{entity,coverage}'
  into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

create or replace function pg_temp.type_of(
  p_lease uuid, p_as_of date, p_type text
)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(pg_temp.coverage(p_lease, p_as_of) -> 0 -> 'types')
    as entry
  where entry ->> 'component_type' = p_type;
$$;

-- ---------------------------------------------------------------------------
-- The envelope carries coverage at all
-- ---------------------------------------------------------------------------

select isnt(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000001', date '2026-06-30'),
  null,
  'the read reports coverage beside the components');

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000001', date '2026-06-30')
    -> 0 ->> 'window_from',
  '2026-01-01',
  'the window starts at the lease start');

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000001', date '2026-06-30')
    -> 0 ->> 'window_to',
  '2026-06-30',
  'and ends at the queried date, inclusive');

-- ---------------------------------------------------------------------------
-- Complete, and complete for the right reason
-- ---------------------------------------------------------------------------

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000001', date '2026-06-30')
    -> 0 -> 'complete',
  to_jsonb(true),
  'two periods that touch leave no gap');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000001', date '2026-06-30',
                  'base_rent') -> 'gap_count',
  to_jsonb(0),
  'and the count agrees -- an off-by-one on the half-open range would show up '
  'here as a phantom gap of zero days');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000001', date '2026-06-30',
                  'base_rent') -> 'in_force',
  to_jsonb(true),
  'the open-ended period is in force on the queried date');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000001', date '2026-06-30',
                  'base_rent') -> 'open_gap_from',
  'null'::jsonb,
  'and there is no gap reaching the queried date');

-- ---------------------------------------------------------------------------
-- A hole in the middle
-- ---------------------------------------------------------------------------

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000002', date '2026-06-30')
    -> 0 -> 'complete',
  to_jsonb(false),
  'a month nobody recorded makes the lease incomplete');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000002', date '2026-06-30',
                  'base_rent') ->> 'first_gap_from',
  '2026-03-01',
  'the gap starts the day after the first period ends');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000002', date '2026-06-30',
                  'base_rent') ->> 'first_gap_to',
  '2026-03-31',
  'and ends the day before the next one starts');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000002', date '2026-06-30',
                  'base_rent') -> 'in_force',
  to_jsonb(true),
  'while the type IS in force today -- which is exactly the case a reader '
  'would otherwise take for complete');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000002', date '2026-06-30',
                  'base_rent') -> 'open_gap_from',
  'null'::jsonb,
  'the hole is closed, so nothing is open at the queried date');

-- ---------------------------------------------------------------------------
-- Recorded, then ended
-- ---------------------------------------------------------------------------

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000003', date '2026-06-30',
                  'parking') -> 'in_force',
  to_jsonb(false),
  'an ended component is not in force');

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000003', date '2026-06-30',
                  'parking') ->> 'open_gap_from',
  '2026-06-01',
  'and the gap it left is reported as reaching the queried date -- the '
  'actionable half: unrecorded since June and still');

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000003', date '2026-06-30')
    -> 0 -> 'complete',
  to_jsonb(false),
  'so the lease is incomplete even though nothing is missing from the middle');

-- ---------------------------------------------------------------------------
-- What is NOT reported, and why
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.coverage('e1700000-0000-0000-0000-000000000003',
                      date '2026-06-30') -> 0 -> 'types')),
  1,
  'a type that was never recorded for this lease is absent, not reported as a '
  'gap: nothing was claimed about it, so there is nothing to be incomplete '
  'about (the DEC-029 per-type boundary)');

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000004', date '2026-06-30'),
  '[]'::jsonb,
  'a lease with no components at all reports no coverage rather than an empty '
  'shell that reads as complete');

-- ---------------------------------------------------------------------------
-- The future is not a gap
-- ---------------------------------------------------------------------------

select is(
  pg_temp.type_of('e1700000-0000-0000-0000-000000000003', date '2026-04-30',
                  'parking') -> 'gap_count',
  to_jsonb(0),
  'queried inside the recorded period, the same component has no gap at all -- '
  'the window follows the question, not the calendar');

select is(
  pg_temp.coverage('e1700000-0000-0000-0000-000000000003', date '2026-04-30')
    -> 0 ->> 'window_to',
  '2026-04-30',
  'and the window ends there, so a period recorded later cannot make an '
  'earlier date look incomplete');

select * from finish();
rollback;
