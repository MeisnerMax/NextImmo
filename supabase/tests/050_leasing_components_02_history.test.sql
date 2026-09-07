begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-COMPONENTS-02 (V-2b): the components over time.
--
-- Most of this file is about **which absences count as gaps**. That is the
-- only judgement the function makes, and getting it wrong in either direction
-- ruins the feature: report every absence and the screen is a wall of false
-- alarms nobody reads; report none and a real hole in a contract stays
-- invisible, which is what V-2 set out to fix.
--
-- The rule under test: a hole *between* two recorded periods is a gap. The
-- time before the first period is not — nothing was ever claimed about it, and
-- a lease that predates the entry of its components is the normal state of a
-- migrated tenancy. The time after an open-ended period is not either, because
-- there is no after.
--
-- The fixture is built so each of those three cases exists at once, on the
-- same lease. A fixture with only the gap would pass a function that called
-- everything a gap.

select plan(25);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'lease_component_history',
  'the history read exists');

select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_component_history'),
  true,
  'it is security definer');

select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'lease_component_history'),
  's'::"char",
  'and stable: a read');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'lease_component_history'
     and acl.grantee::oid in ('anon'::regrole::oid, 0)),
  0,
  'neither anon nor PUBLIC can call it');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('21200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'history-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('21200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'history-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('21100000-0000-0000-0000-000000000001', 'history', 'History');
select private.seed_workspace_role_catalog('21100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '21100000-0000-0000-0000-000000000001',
       '21200000-0000-0000-0000-000000000001', role.id, 'active'
from public.roles as role
where role.workspace_id = '21100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('21500000-0000-0000-0000-000000000001', '21100000-0000-0000-0000-000000000001',
   'Historienhaus', 'Chronikweg 1', '10115', 'Berlin', 'de', 'residential', 2,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('21600000-0000-0000-0000-000000000001', '21100000-0000-0000-0000-000000000001',
   '21500000-0000-0000-0000-000000000001', 'H-01', 'occupied',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  ('21600000-0000-0000-0000-000000000002', '21100000-0000-0000-0000-000000000001',
   '21500000-0000-0000-0000-000000000001', 'H-02', 'occupied',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001');

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  ('21700000-0000-0000-0000-000000000001', '21100000-0000-0000-0000-000000000001',
   '21500000-0000-0000-0000-000000000001', '21600000-0000-0000-0000-000000000001',
   'Historie', 'active', date '2024-01-01', null, null, null, 1000, 'EUR',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  -- The leak canary. Its component must never appear in the first lease's
  -- history, and it is the only base_rent row with amount 999.
  ('21700000-0000-0000-0000-000000000002', '21100000-0000-0000-0000-000000000001',
   '21500000-0000-0000-0000-000000000001', '21600000-0000-0000-0000-000000000002',
   'Nachbar', 'active', date '2024-01-01', null, null, null, 999, 'EUR',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001');

-- base_rent: three periods with one interior hole, and an open end.
--   [2024-01-01, 2024-06-30]  ... hole ...  [2025-01-01, today+60]  [today+61, ∞)
-- The hole is the only gap the function may report: the time before 2024 and
-- the time after today+61 are not gaps.
insert into public.lease_components (
  workspace_id, lease_id, component_type, valid_from, valid_to,
  amount, currency_code, vat_mode, vat_rate_percent, note, created_by, updated_by
) values
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'base_rent', date '2024-01-01', date '2024-06-30', 800, 'EUR', 'exempt', null,
   'Erstmiete',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'base_rent', date '2025-01-01', current_date + 60, 900, 'EUR', 'exempt', null, null,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  -- Entered in advance. A future period is exactly the thing the as-of read
  -- cannot show, and one of the reasons this package exists.
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'base_rent', current_date + 61, null, 950, 'EUR', 'exempt', null, 'Erhöhung',
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  -- One open-ended period, nothing before it: no gaps at all.
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'service_charge_advance', date '2025-01-01', null, 150, 'EUR', 'exempt', null, null,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  -- Two touching periods: adjacent is not a gap, and the half-open internal
  -- representation is what makes that true.
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'heating_advance', date '2025-01-01', date '2025-12-31', 60, 'EUR', 'exempt', null, null,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000001',
   'heating_advance', date '2026-01-01', null, 70, 'EUR', 'net', 19, null,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001'),
  ('21100000-0000-0000-0000-000000000001', '21700000-0000-0000-0000-000000000002',
   'base_rent', date '2024-01-01', null, 999, 'EUR', 'exempt', null, null,
   '21200000-0000-0000-0000-000000000001', '21200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function pg_temp.history(
  p_user uuid,
  p_lease uuid default '21700000-0000-0000-0000-000000000001',
  p_workspace uuid default '21100000-0000-0000-0000-000000000001'
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
                      'aal', 'aal2')::text,
    true
  );
  v := public.lease_component_history(p_workspace, p_lease);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

-- The entry for one component type.
create or replace function pg_temp.type_of(p_type text)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(
    pg_temp.history('21200000-0000-0000-0000-000000000001')
      #> '{entity,component_types}'
  ) as entry
  where entry ->> 'component_type' = p_type;
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  pg_temp.history('21200000-0000-0000-0000-000000000002') #>> '{error,code}',
  'forbidden',
  'a caller without lease.read is refused');

select is(
  pg_temp.history('21200000-0000-0000-0000-000000000001', null) #>> '{error,field}',
  'leaseId',
  'the lease is required. A property-scoped history would return every period '
  'of every component of every lease in a building, and unlike the as-of read '
  'there is no date to bound it with');

select is(
  pg_temp.history(
    '21200000-0000-0000-0000-000000000001',
    '21700000-0000-0000-0000-000000000009'
  ) #>> '{error,code}',
  'not_found',
  'an unknown lease is not found');

-- ---------------------------------------------------------------------------
-- The periods
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(
    pg_temp.history('21200000-0000-0000-0000-000000000001')
      #> '{entity,component_types}'
  ),
  3,
  'three types have history on this lease. A type never recorded is absent '
  'entirely rather than present and empty -- nothing was claimed about it');

select is(
  jsonb_array_length(pg_temp.type_of('base_rent') -> 'periods'),
  3,
  'base rent has three periods. The as-of read can only ever show one of them, '
  'which is the whole reason for this function');

select is(
  pg_temp.type_of('base_rent') #> '{periods,0,amount}',
  to_jsonb(800.00),
  'ordered oldest first');

select is(
  pg_temp.type_of('base_rent') #>> '{periods,0,valid_to}',
  '2024-06-30',
  'valid_to comes back inclusive, as the column stores it and as a contract '
  'reads. The internal range is half-open, and leaking that would move every '
  'end date in the UI by a day');

select is(
  pg_temp.type_of('base_rent') #> '{periods,2,note}',
  to_jsonb('Erhöhung'::text),
  'the note travels with the period that carries it');

select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.type_of('base_rent') -> 'periods') as period
   where (period ->> 'in_force')::boolean),
  1,
  'exactly one period is in force. More than one would mean the exclusion '
  'constraint had been circumvented');

select is(
  (select period ->> 'amount'
   from jsonb_array_elements(pg_temp.type_of('base_rent') -> 'periods') as period
   where (period ->> 'in_force')::boolean),
  '900.00',
  'and it is the middle one -- the one the as-of read would have returned');

select is(
  (pg_temp.type_of('base_rent') #>> '{periods,2,in_force}')::boolean,
  false,
  'the future period is returned but not marked in force. Showing it is the '
  'point; treating it as current would be a rent rise applied early');

select is(
  pg_temp.type_of('heating_advance') #> '{periods,1,vat_rate_percent}',
  to_jsonb(19.00),
  'VAT mode and rate travel with the period, so a change of tax treatment is '
  'visible as the dated event it was');

-- ---------------------------------------------------------------------------
-- Gaps: the only judgement this function makes
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(pg_temp.type_of('base_rent') -> 'gaps'),
  1,
  'one gap on base rent');

select is(
  pg_temp.type_of('base_rent') #>> '{gaps,0,from}',
  '2024-07-01',
  'it starts the day after the period before it ends');

select is(
  pg_temp.type_of('base_rent') #>> '{gaps,0,to}',
  '2024-12-31',
  'and ends the day before the next one starts, inclusive like every other '
  'date in the payload');

select is(
  pg_temp.type_of('service_charge_advance') -> 'gaps',
  '[]'::jsonb,
  'a single open-ended period has no gaps. The years before 2025 are not a '
  'gap: nothing was ever claimed about them, and a lease that predates the '
  'entry of its components is the normal state of a migrated tenancy');

select is(
  pg_temp.type_of('heating_advance') -> 'gaps',
  '[]'::jsonb,
  'two touching periods have no gap between them either -- 2025-12-31 to '
  '2026-01-01 is adjacency, not a hole, and only the half-open internal '
  'representation makes that come out right');

select ok(
  not exists (
    select 1
    from jsonb_array_elements(pg_temp.type_of('base_rent') -> 'gaps') as gap
    where (gap ->> 'from')::date > current_date
  ),
  'nothing after the open-ended last period is reported as a gap. There is no '
  'after an open end, and a function that reported one would put every lease '
  'permanently in the red');

-- ---------------------------------------------------------------------------
-- Scope
-- ---------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from jsonb_array_elements(pg_temp.type_of('base_rent') -> 'periods') as period
    where period ->> 'amount' = '999.00'
  ),
  'the neighbouring lease''s component does not leak in');

select is(
  jsonb_array_length(
    pg_temp.history(
      '21200000-0000-0000-0000-000000000001',
      '21700000-0000-0000-0000-000000000002'
    ) #> '{entity,component_types}'
  ),
  1,
  'and asking for that lease returns its own single type');

select is(
  pg_temp.history('21200000-0000-0000-0000-000000000001')
    #>> '{entity,property_id}',
  '21500000-0000-0000-0000-000000000001',
  'the property travels with the answer, so a caller need not join to find it');

select * from finish();
rollback;
