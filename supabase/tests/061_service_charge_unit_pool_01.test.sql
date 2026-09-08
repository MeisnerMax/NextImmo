begin;

create extension if not exists pgtap with schema extensions;

-- SERVICE-CHARGE-UNIT-POOL-01.
--
-- `SERVICE-CHARGE-PREVIEW-01` refused three of the four narrowing cost-pool
-- scopes — `building`, `entrance`, `meter_group` — because this schema has no
-- entity for them. It said nothing about the fourth. A key on a `unit`-scoped
-- pool with any basis other than `direct` fell through to the general branch,
-- resolved the basis over the WHOLE property, and spread one flat's cost over
-- the building. No refusal, no hint, and a derivation on every line that looks
-- exactly as convincing as a correct one.
--
-- The fixture is built so that the two behaviours cannot be confused: three
-- units of 60/30/10 square metres, and 1000 EUR on a pool scoped to the
-- 60-square-metre one. Spread by area that is 600/300/100; assigned to the
-- pool's unit it is 1000/0/0. Any assertion that passes under one fails under
-- the other.
--
-- The other direction is asserted too: a key with no cost pool at all still
-- distributes over the property, so the fix cannot pass by assigning
-- everything to one unit everywhere.

select plan(12);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('77200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'unitpool-admin@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('77100000-0000-0000-0000-000000000001', 'unitpool', 'Einheitspool');
select private.seed_workspace_role_catalog(
  '77100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '77100000-0000-0000-0000-000000000001',
       '77200000-0000-0000-0000-000000000001', role.id, 'active'
from public.roles as role
where role.workspace_id = '77100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('77500000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001',
   'Poolhaus', 'Poolweg 1', '10115', 'Berlin', 'de', 'residential', 3,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

-- 60 + 30 + 10 = 100. The pool below names the 60 one.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm,
  created_by, updated_by
) values
  ('77600000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001', 'P-01', 'occupied', 60,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001'),
  ('77600000-0000-0000-0000-000000000002',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001', 'P-02', 'occupied', 30,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001'),
  ('77600000-0000-0000-0000-000000000003',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001', 'P-03', 'occupied', 10,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('77300000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001',
   '4200', 'Balkonsanierung P-01', 'expense',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001'),
  ('77300000-0000-0000-0000-000000000002',
   '77100000-0000-0000-0000-000000000001',
   '4210', 'Gartenpflege', 'expense',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

insert into public.finance_account_allocation_rules (
  finance_account_id, workspace_id, allocatable, settlement_principle,
  created_by, updated_by
) values
  ('77300000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001', true, 'performance',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001'),
  ('77300000-0000-0000-0000-000000000002',
   '77100000-0000-0000-0000-000000000001', true, 'performance',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

-- The pool names exactly one unit. That is its whole meaning.
insert into public.cost_pools (
  id, workspace_id, property_id, unit_id, pool_key, name, scope,
  created_by, updated_by
) values
  ('77a00000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001',
   '77600000-0000-0000-0000-000000000001',
   'p-01-balkon', 'Balkon P-01', 'unit',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

-- The key that used to spread: a unit-scoped pool with an AREA basis. Nothing
-- about it is unusual — a workspace that pools a cost on one flat and leaves
-- the property's default basis in place writes exactly this.
insert into public.allocation_keys (
  id, workspace_id, property_id, finance_account_id, cost_pool_id, basis,
  explanation, valid_from, valid_to, created_by, updated_by
) values
  ('77800000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001',
   '77300000-0000-0000-0000-000000000001',
   '77a00000-0000-0000-0000-000000000001', 'area_sqm',
   'Kostenstelle Balkon P-01.',
   date '2020-01-01', null,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

-- The control: same basis, no pool, so it must still spread over the property.
insert into public.allocation_keys (
  id, workspace_id, property_id, finance_account_id, basis,
  explanation, valid_from, valid_to, created_by, updated_by
) values
  ('77800000-0000-0000-0000-000000000002',
   '77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001',
   '77300000-0000-0000-0000-000000000002', 'area_sqm',
   'Gartenpflege nach Flaeche.',
   date '2020-01-01', null,
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

insert into public.finance_periods (
  id, workspace_id, fiscal_year, period_month, status, created_by, updated_by
) values
  ('77900000-0000-0000-0000-000000000001',
   '77100000-0000-0000-0000-000000000001', 2026, 1, 'open',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

insert into public.finance_ledger_entries (
  workspace_id, property_id, account_id, period_id, booked_on, amount,
  currency_code, created_by, updated_by
) values
  ('77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001',
   '77300000-0000-0000-0000-000000000001',
   '77900000-0000-0000-0000-000000000001', date '2026-01-10', 1000, 'EUR',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001'),
  ('77100000-0000-0000-0000-000000000001',
   '77500000-0000-0000-0000-000000000001',
   '77300000-0000-0000-0000-000000000002',
   '77900000-0000-0000-0000-000000000001', date '2026-01-11', 500, 'EUR',
   '77200000-0000-0000-0000-000000000001',
   '77200000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_user(
  p_user uuid, p_statement text, p_aal text default 'aal2'
)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated',
                      'aal', p_aal)::text,
    true
  );
  execute p_statement into v;
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

create or replace function pg_temp.preview()
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    '77200000-0000-0000-0000-000000000001',
    $q$select public.property_service_charge_preview(
      '77100000-0000-0000-0000-000000000001'::uuid,
      '77500000-0000-0000-0000-000000000001'::uuid,
      '2026-01-01'::date, '2026-01-31'::date)$q$
  );
$$;

create or replace function pg_temp.amount(
  p_unit_code text, p_account_code text
)
returns numeric
language sql
as $$
  select coalesce((
    select (line ->> 'amount')::numeric
    from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'units') as unit,
         jsonb_array_elements(unit -> 'lines') as line
    where unit ->> 'unit_code' = p_unit_code
      and line ->> 'account_code' = p_account_code
  ), 0);
$$;

-- ---------------------------------------------------------------------------
-- The defect: one flat's cost belongs to one flat
-- ---------------------------------------------------------------------------

select is(
  pg_temp.amount('P-01', '4200'),
  1000.00,
  'a cost pooled on one unit is assigned to that unit in full -- before this '
  'migration it was 600.00, its area share of the building');

select is(
  pg_temp.amount('P-02', '4200'),
  0::numeric,
  'and the neighbour carries none of it -- it used to carry 300.00');

select is(
  pg_temp.amount('P-03', '4200'),
  0::numeric,
  'nor the third -- it used to carry 100.00, and all three figures together '
  'looked exactly as plausible as the correct one');

select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4200'),
  1,
  'the cost produces exactly one line, not three');

-- ---------------------------------------------------------------------------
-- And the general case still distributes
-- ---------------------------------------------------------------------------

select is(
  pg_temp.amount('P-01', '4210'),
  300.00,
  'a key with no cost pool still spreads over the property: 500 over 60 of '
  '100 square metres');

select is(
  pg_temp.amount('P-02', '4210'),
  150.00,
  'and 30 of 100 is 150');

select is(
  pg_temp.amount('P-03', '4210'),
  50.00,
  'and 10 of 100 is 50 -- paired with the four assertions above, so the fix '
  'cannot pass by assigning everything to one unit everywhere');

-- ---------------------------------------------------------------------------
-- The line says what it did
-- ---------------------------------------------------------------------------

select is(
  (select line ->> 'numerator'
   from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4200'),
  null,
  'the assigned line carries no numerator: nothing was divided, and a 1-over-1 '
  'derivation would claim a distribution that did not happen');

select is(
  (select line ->> 'basis'
   from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4200'),
  'area_sqm',
  'while the key''s own basis stays visible -- it is what the workspace wrote, '
  'even though a single-unit scope makes it irrelevant to the amount');

select is(
  (select account ->> 'rounding_difference'
   from jsonb_array_elements(
          pg_temp.preview() -> 'entity' -> 'accounts') as account
   where account ->> 'account_code' = '4200'),
  '0.00',
  'and the assignment leaves no rounding difference behind');

-- ---------------------------------------------------------------------------
-- Totals
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview() -> 'entity' -> 'totals' ->> 'distributed',
  '1500.00',
  'both costs reached the units');

select is(
  (select sum((unit ->> 'total')::numeric)
   from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'units') as unit),
  1500.00,
  'and the unit totals add back to them -- an assignment that dropped the '
  'other two units'' lines would satisfy the per-line assertions above and '
  'fail here');

select * from finish();
rollback;
