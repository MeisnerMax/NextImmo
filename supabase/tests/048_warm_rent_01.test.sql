begin;

create extension if not exists pgtap with schema extensions;

-- WARM-RENT-01 (P-7).
--
-- The word is the specification. "Warmmiete" is Kaltmiete plus Nebenkosten
-- plus Heizkosten, and the two totals already in this codebase both get it
-- wrong: the legacy `warmRentMonthly` adds parking and omits heating, and
-- `rent_roll_snapshots.total_rent_monthly` does the same without ever claiming
-- the name. So the assertions that matter here are the **exclusions** and the
-- case where the sum exists but is not warm.
--
-- Every "a figure is produced" assertion has a counterpart where it must not
-- be. A function that always answered would pass half of this file.

select plan(23);

-- ---------------------------------------------------------------------------
-- Fixture: one property, six leases, one shape of the problem each.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a2200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'warm-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'warm-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('a2100000-0000-0000-0000-000000000001', 'warmrent', 'Warm Rent');
select private.seed_workspace_role_catalog('a2100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'a2400000-0000-0000-0000-000000000001',
  'a2100000-0000-0000-0000-000000000001',
  'a2200000-0000-0000-0000-000000000001',
  role.id, 'active'
from public.roles as role
where role.workspace_id = 'a2100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'a2500000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
  'Warmhaus', 'Warmweg 1', '10115', 'Berlin', 'de', 'residential', 6,
  'a2200000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
)
select
  ('a2600000-0000-0000-0000-00000000000' || n)::uuid,
  'a2100000-0000-0000-0000-000000000001',
  'a2500000-0000-0000-0000-000000000001',
  'A-0' || n, 'occupied',
  'a2200000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001'
from generate_series(1, 6) as n;

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, base_rent_monthly, currency_code, created_by, updated_by
)
select
  ('a2700000-0000-0000-0000-00000000000' || n)::uuid,
  'a2100000-0000-0000-0000-000000000001',
  'a2500000-0000-0000-0000-000000000001',
  ('a2600000-0000-0000-0000-00000000000' || n)::uuid,
  'Vertrag ' || n, 'active', date '2026-01-01', 1000, 'EUR',
  'a2200000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001'
from generate_series(1, 6) as n;

create or replace function pg_temp.component(
  p_lease text, p_type text, p_amount numeric,
  p_vat text default 'exempt', p_rate numeric default null,
  p_from date default date '2026-01-01', p_to date default null,
  p_currency text default 'EUR'
)
returns void
language sql
as $$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from, valid_to,
    amount, currency_code, vat_mode, vat_rate_percent, created_by, updated_by
  ) values (
    'a2100000-0000-0000-0000-000000000001',
    ('a2700000-0000-0000-0000-00000000000' || p_lease)::uuid,
    p_type::public.lease_component_type, p_from, p_to,
    p_amount, p_currency, p_vat::public.lease_component_vat_mode, p_rate,
    'a2200000-0000-0000-0000-000000000001',
    'a2200000-0000-0000-0000-000000000001'
  );
$$;

-- 1: the complete warm case, plus a parking and an `other` that must NOT count.
select pg_temp.component('1', 'base_rent', 800);
select pg_temp.component('1', 'service_charge_advance', 150);
select pg_temp.component('1', 'heating_advance', 90);
select pg_temp.component('1', 'parking', 60);
select pg_temp.component('1', 'other', 25);

-- 2: no heating ever recorded. A sum exists; it is not warm rent.
select pg_temp.component('2', 'base_rent', 800);
select pg_temp.component('2', 'service_charge_advance', 150);

-- 3: heating recorded once, ended, nothing since. A gap.
select pg_temp.component('3', 'base_rent', 800);
select pg_temp.component('3', 'heating_advance', 90,
                         p_to => date '2026-03-31');

-- 4: commercial, all net at 19 %.
select pg_temp.component('4', 'base_rent', 2000, 'net', 19);
select pg_temp.component('4', 'service_charge_advance', 300, 'net', 19);
select pg_temp.component('4', 'heating_advance', 200, 'net', 19);

-- 5: net beside exempt. The gross total is meaningful (both are payable once
-- tax is added where it applies); the NET total is not, because one of them is
-- already a payable figure.
select pg_temp.component('5', 'base_rent', 800, 'net', 19);
select pg_temp.component('5', 'heating_advance', 90);

-- 6 deliberately gets nothing.

create or replace function pg_temp.warm(p_lease text, p_as_of date)
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
      'sub', 'a2200000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.warm_rent_as_of(
    'a2100000-0000-0000-0000-000000000001'::uuid, p_as_of,
    ('a2700000-0000-0000-0000-00000000000' || p_lease)::uuid
  ) #> '{entity,leases,0}'
  into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

create or replace function pg_temp.warm_all(p_as_of date)
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
      'sub', 'a2200000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.warm_rent_as_of(
    'a2100000-0000-0000-0000-000000000001'::uuid, p_as_of, null,
    'a2500000-0000-0000-0000-000000000001'::uuid
  ) into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

create or replace function pg_temp.warm_forbidden()
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
      'sub', 'a2200000-0000-0000-0000-000000000002',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.warm_rent_as_of(
    'a2100000-0000-0000-0000-000000000001'::uuid, date '2026-06-30', null,
    'a2500000-0000-0000-0000-000000000001'::uuid
  ) into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'warm_rent_as_of', 'the warm rent read exists');
select ok(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'warm_rent_as_of'),
  'security definer, so the permission check inside it is the boundary');

-- ---------------------------------------------------------------------------
-- The composition, which is the whole point
-- ---------------------------------------------------------------------------

select is(
  pg_temp.warm('1', date '2026-06-30') ->> 'net_monthly',
  '1040.00',
  'warm rent is base + service charge + heating: 800 + 150 + 90');

select is(
  pg_temp.warm('1', date '2026-06-30') -> 'included_types',
  '["base_rent", "service_charge_advance", "heating_advance"]'::jsonb,
  'and names exactly those three, in the enum order -- which is the order a '
  'rent statement reads, not alphabetical');

select ok(
  not (pg_temp.warm('1', date '2026-06-30') -> 'included_types'
       @> '["parking"]'::jsonb),
  'parking is excluded -- it is a service a tenant may or may not buy, and '
  'including it would make two identical flats differ by whether one rents a '
  'garage. Both totals already in this codebase get this wrong');

select ok(
  not (pg_temp.warm('1', date '2026-06-30') -> 'included_types'
       @> '["other"]'::jsonb),
  'and so is `other`: it absorbs whatever the four named types do not, some of '
  'which belongs in warm rent and some of which does not, and the type does '
  'not say which');

select is(
  pg_temp.warm('1', date '2026-06-30') -> 'is_warm',
  to_jsonb(true), 'with heating present, the figure is warm rent');

-- ---------------------------------------------------------------------------
-- A sum that exists and is not warm rent
-- ---------------------------------------------------------------------------

select is(
  pg_temp.warm('2', date '2026-06-30') ->> 'net_monthly',
  '950.00',
  'without heating the parts still add up');

select is(
  pg_temp.warm('2', date '2026-06-30') -> 'is_warm',
  to_jsonb(false),
  'but it is NOT warm rent -- a total without heating is a cold rent plus '
  'service charges, and the caller must be able to tell');

select is(
  pg_temp.warm('2', date '2026-06-30') -> 'absent_types',
  '["heating_advance"]'::jsonb,
  'and the missing piece is named, so a screen can say which');

select is(
  pg_temp.warm('2', date '2026-06-30') -> 'gap_types',
  '[]'::jsonb,
  'never recorded is not a gap: nothing was ever claimed about heating here');

-- ---------------------------------------------------------------------------
-- A gap withholds the figure entirely
-- ---------------------------------------------------------------------------

select is(
  pg_temp.warm('3', date '2026-06-30') -> 'gap_types',
  '["heating_advance"]'::jsonb,
  'heating was recorded and then ended, so this date is a gap');

select is(
  pg_temp.warm('3', date '2026-06-30') -> 'net_monthly',
  'null'::jsonb,
  'and the figure is withheld -- DEC-029: never sum around a gap. Base rent '
  'alone would have been a plausible, wrong number');

select is(
  pg_temp.warm('3', date '2026-02-28') ->> 'net_monthly',
  '890.00',
  'while the same lease answers for a date the heating still covered');

-- ---------------------------------------------------------------------------
-- VAT
-- ---------------------------------------------------------------------------

select is(
  pg_temp.warm('4', date '2026-06-30') ->> 'net_monthly',
  '2500.00', 'an all-net lease reports its net total');

select is(
  pg_temp.warm('4', date '2026-06-30') ->> 'gross_monthly',
  '2975.00', 'and the gross, rounded to the currency scale (2500 + 19 %)');

select is(
  pg_temp.warm('5', date '2026-06-30') -> 'net_monthly',
  'null'::jsonb,
  'net beside exempt has no net total: one of the two is already a payable '
  'figure, and adding them would produce neither');

select is(
  pg_temp.warm('5', date '2026-06-30') ->> 'gross_monthly',
  '1042.00',
  'the gross total is still meaningful and is reported: 800 + 19 % plus the '
  'exempt 90. Withholding it too would have been the lazy symmetry');

select throws_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from,
    amount, currency_code, vat_mode, created_by, updated_by
  ) values (
    'a2100000-0000-0000-0000-000000000001',
    'a2700000-0000-0000-0000-000000000006',
    'base_rent', date '2026-01-01', 500, 'EUR', 'net',
    'a2200000-0000-0000-0000-000000000001',
    'a2200000-0000-0000-0000-000000000001'
  )
$$, '23514', null,
  'and a net amount with no rate cannot reach the table at all -- the CHECK '
  'from LEASING-COMPONENTS-01 makes that state unrepresentable, so the '
  'gross-is-null branch above is defence against a newer server rather than '
  'against this one');

-- ---------------------------------------------------------------------------
-- Nothing recorded, and the boundaries
-- ---------------------------------------------------------------------------

select is(
  pg_temp.warm('6', date '2026-06-30') -> 'net_monthly',
  'null'::jsonb,
  'a lease with no components has no warm rent, not a zero');

select is(
  pg_temp.warm('6', date '2026-06-30') -> 'absent_types',
  '["base_rent", "service_charge_advance", "heating_advance"]'::jsonb,
  'and says all three are missing rather than reporting an empty success');

select is(
  (select jsonb_array_length(
     pg_temp.warm_all(date '2026-06-30') #> '{entity,leases}')
  ),
  6, 'the property-scoped read spans every effective lease');

select is(
  pg_temp.warm_forbidden() #>> '{error,code}',
  'forbidden',
  'and a caller without lease.read is refused rather than shown a rent roll');

select * from finish();
rollback;
