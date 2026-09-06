begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-ASOF-01 / DEC-027.
--
-- Two behaviours that were never pinned, in opposite directions:
--
--   * a lease that has since ended must still count for a date it was in force
--     on. The old filter asked for the status *now*, so it did not;
--   * a lease running past its `end_date` while still `active` must count.
--     `end_date` is a plan, not a termination, and with no scheduler and an
--     `update_lease` that refuses to touch an active lease, that state is where
--     every fixed-term lease ends up.
--
-- Neither was covered before this file: removing the `end_date` filter from all
-- three helpers broke no assertion in the suite. That silence is the reason the
-- divergence with `property_leasing_summary` could live for a release.

select plan(24);

select has_function('private', 'lease_is_effective_on',
  'the shared effectiveness predicate exists');
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'lease_is_effective_on'),
  'i'::"char",
  'it is immutable: it reads no table and depends on no session state'
);
select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'lease_is_effective_on'
     and function.prosecdef),
  0,
  'and needs no security definer, so it adds nothing to the privileged surface'
);

-- ---------------------------------------------------------------------------
-- The predicate, in isolation.
-- ---------------------------------------------------------------------------

select ok(
  private.lease_is_effective_on(
    'active', date '2026-01-01', date '2026-06-30', null, null, date '2026-03-15'
  ),
  'an active lease is in force inside its term'
);
select ok(
  private.lease_is_effective_on(
    'active', date '2026-01-01', date '2026-06-30', null, null, date '2026-09-01'
  ),
  'and past its end_date too -- DEC-027: a planned end is not a termination'
);
select ok(
  private.lease_is_effective_on(
    'active', date '2026-01-01', null, null, null, date '2030-01-01'
  ),
  'an open-ended active lease is in force indefinitely'
);
select ok(
  not private.lease_is_effective_on(
    'active', date '2026-07-01', null, null, null, date '2026-03-15'
  ),
  'but never before it starts'
);

select ok(
  private.lease_is_effective_on(
    'ended', date '2026-01-01', date '2026-06-30', null,
    timestamptz '2026-07-02 09:00+00', date '2026-03-15'
  ),
  'an ended lease is in force for a date it covered -- this is the as-of gap'
);
select ok(
  not private.lease_is_effective_on(
    'ended', date '2026-01-01', date '2026-06-30', null,
    timestamptz '2026-07-02 09:00+00', date '2026-08-15'
  ),
  'and not for a date after it ended'
);
select ok(
  private.lease_is_effective_on(
    'ended', date '2026-01-01', date '2026-06-30', date '2026-08-31',
    timestamptz '2026-09-02 09:00+00', date '2026-08-15'
  ),
  'a recorded move-out date wins over end_date: the tenant stayed on'
);
select ok(
  not private.lease_is_effective_on(
    'ended', date '2026-01-01', null, null,
    timestamptz '2026-06-30 09:00+00', date '2026-08-15'
  ),
  'with neither date recorded, the transition timestamp bounds it'
);

select ok(
  not private.lease_is_effective_on(
    'draft', date '2026-01-01', null, null, null, date '2026-03-15'
  ),
  'a lease still in the signing chain was never let'
);
select ok(
  not private.lease_is_effective_on(
    'landlord_signed', date '2026-01-01', null, null, null, date '2026-03-15'
  ),
  'not even one signed by both sides but never activated'
);
select ok(
  not private.lease_is_effective_on(
    'cancelled', date '2026-01-01', date '2026-06-30', null, null, date '2026-03-15'
  ),
  'and a cancelled lease never was'
);

-- ---------------------------------------------------------------------------
-- Fixture: one property, three units, three leases of different shapes.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('f2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'asof-admin@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'asof', 'As Of');
select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'f4000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  role.id,
  'active'
from public.roles as role
where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
  'Stichtaghaus', 'Rueckschauweg 1', '10115', 'Berlin', 'de', 'residential', 3,
  'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'A-01', 'occupied',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f6000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'A-02', 'occupied',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f6000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'A-03', 'vacant',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

-- AGG-004 is an assertion, not a sync: the fixture sets both sides itself.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  -- Still running, and past its planned end. The DEC-027 case.
  ('f7000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000001',
   'Abgelaufen, laeuft weiter', 'active',
   date '2025-01-01', date '2025-12-31', null, null,
   1000.00, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  -- Ran January to June 2026 and has since ended. The as-of case.
  ('f7000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000002',
   'Beendet', 'ended',
   date '2026-01-01', date '2026-06-30', null, timestamptz '2026-07-02 09:00+00',
   700.00, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  -- Never activated. Must never appear.
  ('f7000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000003',
   'Nur Entwurf', 'draft',
   date '2026-01-01', null, null, null,
   500.00, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

create or replace function pg_temp.roll(p_as_of date)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', 'f2000000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.rent_roll_live(
    'f1000000-0000-0000-0000-000000000001',
    'f5000000-0000-0000-0000-000000000001',
    p_as_of
  ) into v_result;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Through the read port.
-- ---------------------------------------------------------------------------

select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from jsonb_array_elements(pg_temp.roll(date '2026-03-15') #> '{entity,lines}') as line
   where line ->> 'unit_code' = 'A-01'),
  1000.00::numeric,
  'a lease past its end_date carries its rent -- it was excluded before DEC-027'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from jsonb_array_elements(pg_temp.roll(date '2026-03-15') #> '{entity,lines}') as line
   where line ->> 'unit_code' = 'A-02'),
  700.00::numeric,
  'and a since-ended lease carries its rent for a date it covered'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from jsonb_array_elements(pg_temp.roll(date '2026-03-15') #> '{entity,lines}') as line
   where line ->> 'unit_code' = 'A-03'),
  0::numeric,
  'a draft contributes nothing, whatever its dates say'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from jsonb_array_elements(pg_temp.roll(date '2026-09-15') #> '{entity,lines}') as line
   where line ->> 'unit_code' = 'A-02'),
  0::numeric,
  'the ended lease drops out for a date after it ended'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from jsonb_array_elements(pg_temp.roll(date '2024-06-01') #> '{entity,lines}') as line
   where line ->> 'unit_code' = 'A-01'),
  0::numeric,
  'and nothing counts before it starts -- the start bound is unchanged'
);

select is(
  (pg_temp.roll(date '2026-03-15') #>> '{entity,total_rent_monthly}')::numeric,
  1700.00::numeric,
  'the property total is the sum of both, in one currency'
);
select is(
  (pg_temp.roll(date '2026-09-15') #>> '{entity,total_rent_monthly}')::numeric,
  1000.00::numeric,
  'and follows the reference date rather than today'
);

-- ---------------------------------------------------------------------------
-- The currency helpers ask the same question, so a snapshot cannot disagree
-- with the live view about which leases exist. P2-D05b built that guarantee by
-- sharing the helpers; this keeps it.
-- ---------------------------------------------------------------------------

select is(
  private.rent_roll_currencies(
    'f1000000-0000-0000-0000-000000000001',
    'f5000000-0000-0000-0000-000000000001',
    date '2026-03-15'
  ),
  array['EUR'],
  'the currency scan sees the same leases the rows do'
);
select is(
  (select currencies
   from private.rent_roll_unit_currencies(
     'f1000000-0000-0000-0000-000000000001',
     'f5000000-0000-0000-0000-000000000001',
     date '2026-03-15'
   )
   where unit_id = 'f6000000-0000-0000-0000-000000000002'),
  array['EUR'],
  'and so does the per-unit scan, for the ended lease too'
);
select is(
  (select currencies
   from private.rent_roll_unit_currencies(
     'f1000000-0000-0000-0000-000000000001',
     'f5000000-0000-0000-0000-000000000001',
     date '2026-09-15'
   )
   where unit_id = 'f6000000-0000-0000-0000-000000000002'),
  '{}'::text[],
  'which means a cross-currency refusal cannot be triggered by a lease the '
  'rows would not have counted'
);

select * from finish();

rollback;
