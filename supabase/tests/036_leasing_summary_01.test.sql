begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-SUMMARY-01: the server-side lease roll and vacancy exposure.
--
-- Every number here is a definition, so the tests are mostly about which
-- definition. Three of them matter more than the rest:
--
--   * coverage travels with the sum — a square-metre total that silently omits
--     units without a recorded area would be worse than no total;
--   * currencies never merge — one row per currency, because adding EUR to CHF
--     produces a number that is wrong in both;
--   * open-ended leases are their own count, not "not expiring".

select plan(32);

select has_function('public', 'property_leasing_summary',
  'the leasing summary exists');
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_leasing_summary'),
  's'::"char",
  'it is stable: a read, never a mutation'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_leasing_summary'
     and acl.grantee = 'anon'::regrole),
  0,
  'anon cannot call it'
);

-- ---------------------------------------------------------------------------
-- Fixture: one property with six units and five leases
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lease-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('c2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lease-nolease@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('c1000000-0000-0000-0000-000000000001', 'lease-a', 'Lease A');

select private.seed_workspace_role_catalog('c1000000-0000-0000-0000-000000000001');

-- A role with property.read but without lease.read, so the second gate has
-- something to refuse.
insert into public.roles (id, workspace_id, key, name) values (
  'c3000000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000001',
  'property_only', 'Property Only'
);
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'c1000000-0000-0000-0000-000000000001',
       'c3000000-0000-0000-0000-000000000001',
       permission.id
from public.permissions as permission
where permission.key = 'property.read';

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'c1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('c4000000-0000-0000-0000-000000000001'::uuid, 'c2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('c4000000-0000-0000-0000-000000000002'::uuid, 'c2000000-0000-0000-0000-000000000002'::uuid, 'property_only')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'c1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('c5000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'Mietshaus', 'Vertragsweg 1', '10115', 'Berlin', 'de', 'residential', 6,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001');

-- Six units. AGG-004 is an assertion, not a sync: nothing flips a unit for
-- you outside the lease command path, so the fixture states both halves and
-- the deferred constraint trigger checks they agree. A-01..A-04 are occupied
-- and each gets an active lease below; A-05 holds only an ended lease and
-- A-06 none at all, so both are vacant, which is what the vacancy numbers are
-- measured on.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm, vacancy_since,
  created_by, updated_by
) values
  ('c6000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-01', 'occupied', 80, null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  -- No recorded area: the coverage counter has something to report.
  ('c6000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-02', 'occupied', null, null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c6000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-03', 'occupied', 50, null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c6000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-04', 'occupied', 30, null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c6000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-05', 'vacant', 60,
   (now() at time zone 'utc')::date - 100,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  -- Vacant with no recorded start: reported separately, never as "since
  -- today".
  ('c6000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'A-06', 'vacant', 40, null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001');

-- Leases: one ending in 20 days, one in 120, one open-ended, one already
-- expired but still active, one ended (must not count anywhere). The four
-- active ones occupy A-01..A-04; the ended one sits on A-05, which therefore
-- stays vacant.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status, start_date,
  end_date, notice_date, renewal_option_date, break_option_date,
  base_rent_monthly, currency_code, ended_at, created_by, updated_by
) values
  ('c7000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001',
   'Kurz', 'active', (now() at time zone 'utc')::date - 300,
   (now() at time zone 'utc')::date + 20,
   (now() at time zone 'utc')::date + 10, null, null,
   1000, 'EUR', null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000002',
   'Mittel', 'active', (now() at time zone 'utc')::date - 300,
   (now() at time zone 'utc')::date + 120,
   null, (now() at time zone 'utc')::date + 45, null,
   1200, 'EUR', null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000003',
   'Unbefristet', 'active', (now() at time zone 'utc')::date - 500,
   null, null, null, (now() at time zone 'utc')::date + 60,
   900, 'CHF', null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000004',
   'Abgelaufen', 'active', (now() at time zone 'utc')::date - 800,
   (now() at time zone 'utc')::date - 30, null, null, null,
   800, 'EUR', null,
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000005',
   'Beendet', 'ended', (now() at time zone 'utc')::date - 900,
   (now() at time zone 'utc')::date - 400, null, null, null,
   5000, 'EUR', now() - interval '400 days',
   'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------

create or replace function pg_temp.summary(
  p_user uuid,
  p_aal text default 'aal2',
  p_property uuid default 'c5000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
  v_result := public.property_leasing_summary(
    'c1000000-0000-0000-0000-000000000001', p_property
  );
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  (select public.property_leasing_summary(
     'c1000000-0000-0000-0000-000000000001',
     'c5000000-0000-0000-0000-000000000001'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.summary('c2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.summary('c2000000-0000-0000-0000-000000000002')
     -> 'error' ->> 'message'),
  'Leasing access is not permitted',
  'a member who may read the property but not its leases is refused, and told '
  'which of the two is missing'
);
select is(
  (select pg_temp.summary(
     'c2000000-0000-0000-0000-000000000001', 'aal2',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown property is not found, not forbidden'
);

-- ---------------------------------------------------------------------------
-- Units and coverage
-- ---------------------------------------------------------------------------

select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'total')::integer),
  6,
  'every unit of the property is counted'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'vacant')::integer),
  2,
  'vacancy comes from the stored status'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'area_sqm_total')::numeric),
  260::numeric,
  'areas are summed where they are recorded'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'area_sqm_vacant')::numeric),
  100::numeric,
  'and split by the same stored status'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'area_sqm_occupied')::numeric),
  160::numeric,
  'the occupied area excludes the unit that has none recorded'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ->> 'units_without_area')::integer),
  1,
  'the coverage travels with the sum: one unit has no recorded area'
);
select ok(
  (select not (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'units' ? 'occupancy_rate')),
  'no occupancy rate: by unit and by area are different numbers, and choosing '
  'between them is not this package''s decision'
);

-- ---------------------------------------------------------------------------
-- Vacancy duration
-- ---------------------------------------------------------------------------

select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'vacancy' ->> 'longest_vacancy_days')::integer),
  100,
  'the longest vacancy is measured from the stored date'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'vacancy' ->> 'vacant_without_since')::integer),
  1,
  'a vacancy with no recorded start is reported as such, not as vacant since '
  'today'
);

-- ---------------------------------------------------------------------------
-- The lease roll
-- ---------------------------------------------------------------------------

select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' ->> 'active')::integer),
  4,
  'the ended lease is not active'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' ->> 'open_ended')::integer),
  1,
  'an open-ended lease is its own count, not "not expiring"'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' ->> 'expired_open')::integer),
  1,
  'a lease past its end date but still active is exposure, not history'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' -> 'windows' -> 0 ->> 'expiring')::integer),
  1,
  'one contract runs out inside 30 days'
);
select is(
  (select pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' -> 'windows' -> 0 ->> 'label'),
  '30 Tage',
  'the window carries its own label, so a client renders the server''s '
  'definition'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' -> 'windows' -> 2 ->> 'expiring')::integer),
  2,
  'windows are cumulative: 180 days contains the 30-day contract as well'
);
select is(
  (select jsonb_array_length(pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' -> 'windows')),
  4,
  'four windows, fixed by the server'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'lease_roll' -> 'windows' -> 3 ->> 'expiring')::integer),
  2,
  'the expired lease is not counted as expiring in a future window'
);

-- ---------------------------------------------------------------------------
-- Decisions: dates the lease carries, never a score
-- ---------------------------------------------------------------------------

select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'decisions' ->> 'notice_due')::integer),
  1,
  'a notice date inside the window is a decision to take'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'decisions' ->> 'renewal_option')::integer),
  1,
  'so is a renewal option'
);
select is(
  (select (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'decisions' ->> 'break_option')::integer),
  1,
  'and a break option'
);
select ok(
  (select not (pg_temp.summary('c2000000-0000-0000-0000-000000000001')
     -> 'summary' -> 'decisions' ? 'renewal_risk')),
  'no renewal risk: a score needs an explained signal contract, and deriving '
  'one from an end date is exactly the invention that is ruled out'
);

-- ---------------------------------------------------------------------------
-- Rent roll: one row per currency
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.summary('c2000000-0000-0000-0000-000000000001')
       -> 'summary' -> 'rent_roll')),
  2,
  'two currencies, two rows: EUR and CHF are never added together'
);
select is(
  (select (entry ->> 'monthly_base')::numeric
   from jsonb_array_elements(
     pg_temp.summary('c2000000-0000-0000-0000-000000000001')
       -> 'summary' -> 'rent_roll'
   ) as entry
   where entry ->> 'currency_code' = 'EUR'),
  3000::numeric,
  'the EUR row sums the three active EUR leases and nothing else'
);
select is(
  (select (entry ->> 'monthly_base')::numeric
   from jsonb_array_elements(
     pg_temp.summary('c2000000-0000-0000-0000-000000000001')
       -> 'summary' -> 'rent_roll'
   ) as entry
   where entry ->> 'currency_code' = 'CHF'),
  900::numeric,
  'and the CHF lease stays in its own row: 3000 EUR and 900 CHF are not 3900 '
  'of anything'
);
select ok(
  (select bool_and(not (entry ? 'leases_without_rent'))
   from jsonb_array_elements(
     pg_temp.summary('c2000000-0000-0000-0000-000000000001')
       -> 'summary' -> 'rent_roll'
   ) as entry),
  'no rent-coverage counter: the schema requires a rent on every lease, so '
  'the field could only ever be zero'
);

select * from finish();

rollback;
