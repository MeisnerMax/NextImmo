begin;

create extension if not exists pgtap with schema extensions;

-- SERVICE-CHARGE-PREVIEW-01.
--
-- The first package in this programme that produces a number somebody could
-- put on a statement, so the assertions are written against the number rather
-- than against the shape of the answer.
--
-- Four claims carry it:
--
-- **The arithmetic is checkable.** 1000 EUR over 60/30/10 square metres is
-- 600/300/100, and every line carries its own numerator and denominator so a
-- reader can redo it. A line whose derivation is absent is not a line anybody
-- can argue with.
--
-- **The rounding difference is reported, not absorbed.** 1000 EUR over three
-- units is 333.33 three times and one cent left over. That cent is named at
-- the account, because deciding who carries it is a decision and this package
-- does not make it silently.
--
-- **What cannot be computed is refused by name, and its money stays visible.**
-- Six refusal reasons, each with the amount still counted in
-- `apportionable_not_distributed`. DEC-029: never sum around a gap. A
-- statement that drops an unresolvable position and totals the rest is worse
-- than none, because it looks complete.
--
-- **The two open modelling questions refuse rather than choose.** A basis
-- value that changes inside the period is `basis_changed_in_window` -- and the
-- same fixture distributes fine over a period the value does span, so the
-- refusal is a property of the window and not of the data. A part-let unit
-- reports `days_let` beside `days_in_window` and is not split between tenant
-- and owner.

select plan(57);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function(
  'public', 'property_service_charge_preview',
  array['uuid', 'uuid', 'date', 'date'],
  'the settlement preview exists');

select ok(
  (select function.prosecdef
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  'as security definer, like every other read in this schema');

select ok(
  (select function.proconfig @> array['search_path=""']::text[]
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_service_charge_preview'),
  'with an empty search_path');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('76200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'scp-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('76200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'scp-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('76100000-0000-0000-0000-000000000001', 'scp', 'Abrechnung');
select private.seed_workspace_role_catalog(
  '76100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '76100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('76200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('76200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '76100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('76500000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   'Abrechnungshaus A', 'Abrechnungsweg 1', '10115', 'Berlin', 'de',
   'residential', 3,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76500000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001',
   'Abrechnungshaus B', 'Abrechnungsweg 2', '10115', 'Berlin', 'de',
   'residential', 1,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Haus C exists for the key-selection cases alone: one unit, so the
  -- denominators are trivial and the assertions are about which key was
  -- chosen rather than about arithmetic.
  ('76500000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001',
   'Abrechnungshaus C', 'Abrechnungsweg 3', '10115', 'Berlin', 'de',
   'residential', 1,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

-- 60 + 30 + 10 = 100 square metres, so an area share is a figure a reader can
-- verify in their head. That is the point of the fixture, not a convenience.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm,
  created_by, updated_by
) values
  ('76600000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001', 'A-01', 'occupied', 60,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76600000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001', 'A-02', 'occupied', 30,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76600000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001', 'A-03', 'vacant', 10,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76600000-0000-0000-0000-000000000004',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000002', 'B-01', 'occupied', 100,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76600000-0000-0000-0000-000000000005',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003', 'C-01', 'occupied', 50,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

-- The analyst sees Haus A only, which is what makes the entity gate
-- observable: a membership with no scope rows is unrestricted.
insert into public.entity_scopes (
  workspace_id, membership_id, entity_type, entity_id, created_by
)
select '76100000-0000-0000-0000-000000000001', membership.id, 'property',
       '76500000-0000-0000-0000-000000000001',
       '76200000-0000-0000-0000-000000000001'
from public.memberships as membership
where membership.workspace_id = '76100000-0000-0000-0000-000000000001'
  and membership.user_id = '76200000-0000-0000-0000-000000000002';

-- A-01 was let for January and empty afterwards. Question 2 in one row.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, ended_at, base_rent_monthly, currency_code,
  created_by, updated_by
) values
  ('76700000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76600000-0000-0000-0000-000000000001',
   'A-01 Mietvertrag', 'ended', date '2026-01-01', date '2026-01-31',
   timestamptz '2026-01-31 23:59:00+00', 800, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('76300000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   '4300', 'Muellabfuhr', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001',
   '4310', 'Gartenpflege', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001',
   '4400', 'Heizung', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000004',
   '76100000-0000-0000-0000-000000000001',
   '4500', 'Kabelanschluss', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000005',
   '76100000-0000-0000-0000-000000000001',
   '4600', 'Wasser', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000006',
   '76100000-0000-0000-0000-000000000001',
   '4900', 'Instandhaltung', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- 4950 gets no rule at all: the unclassified case, which is not the same as
  -- a rule saying false.
  ('76300000-0000-0000-0000-000000000007',
   '76100000-0000-0000-0000-000000000001',
   '4950', 'Verwaltung', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Rent, booked to the same ledger and with no allocation rule either. It is
  -- the shape that would otherwise be indistinguishable from an unclassified
  -- cost, and it is 12000 EUR of it.
  ('76300000-0000-0000-0000-000000000008',
   '76100000-0000-0000-0000-000000000001',
   '4000', 'Mietertraege', 'income',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- The two key-selection cases on Haus C.
  ('76300000-0000-0000-0000-000000000009',
   '76100000-0000-0000-0000-000000000001',
   '4700', 'Aufzug', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000010',
   '76100000-0000-0000-0000-000000000001',
   '4800', 'Winterdienst', 'expense',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

insert into public.finance_account_allocation_rules (
  finance_account_id, workspace_id, allocatable, settlement_principle,
  created_by, updated_by
) values
  ('76300000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000004',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000005',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000006',
   '76100000-0000-0000-0000-000000000001', false, null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000009',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76300000-0000-0000-0000-000000000010',
   '76100000-0000-0000-0000-000000000001', true, 'performance',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

-- A property-scoped pool on Haus C. It exists so that two keys for the same
-- cost type can be valid at once: the exclusion constraint on
-- `allocation_keys` coalesces `cost_pool_id` into its key, so a pool-bound key
-- and an unbound one do not collide.
insert into public.cost_pools (
  id, workspace_id, property_id, pool_key, name, scope, created_by, updated_by
) values
  ('76a00000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   'c-haupt', 'Hauptkostenstelle C', 'property',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

insert into public.allocation_keys (
  id, workspace_id, property_id, finance_account_id, basis, explanation,
  valid_from, valid_to, created_by, updated_by
) values
  ('76800000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000001', 'area_sqm',
   'Nach Wohnflaeche in Quadratmetern (§ 556a Abs. 1 Satz 1 BGB).',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76800000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000002', 'unit_count',
   'Zu gleichen Teilen je Wohneinheit.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76800000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000003', 'consumption',
   'Nach erfasstem Verbrauch.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76800000-0000-0000-0000-000000000005',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000005', 'persons',
   'Nach der Zahl der im Haushalt gemeldeten Personen.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Haus C: the catch-all. `finance_account_id` null means "every cost type
  -- that has no key of its own".
  ('76800000-0000-0000-0000-000000000006',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   null, 'area_sqm',
   'Auffangschluessel Haus C: nach Flaeche.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Two keys for 4700, both covering the whole period, differing only in
  -- their cost pool. Legal per the exclusion constraint; ambiguous for a
  -- statement, which cites exactly one.
  ('76800000-0000-0000-0000-000000000007',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000009', 'area_sqm',
   'Aufzug nach Flaeche.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- 4800 has a key of its own for January only. A catch-all covers the rest
  -- of the period, and falling back to it would ignore what was agreed for
  -- January.
  ('76800000-0000-0000-0000-000000000009',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000010', 'unit_count',
   'Winterdienst im Januar: zu gleichen Teilen.',
   date '2026-01-01', date '2026-01-31',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

insert into public.allocation_keys (
  id, workspace_id, property_id, finance_account_id, cost_pool_id, basis,
  explanation, valid_from, valid_to, created_by, updated_by
) values
  ('76800000-0000-0000-0000-000000000008',
   '76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000009',
   '76a00000-0000-0000-0000-000000000001', 'unit_count',
   'Aufzug je Einheit.',
   date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

-- Three person counts, one convention. A-01 changes on 1 February: the same
-- data resolves for January and refuses for January-February, which is what
-- makes the refusal a property of the window rather than of the figures.
insert into public.unit_basis_values (
  workspace_id, unit_id, basis, value, convention, valid_from, valid_to,
  created_by, updated_by
) values
  ('76100000-0000-0000-0000-000000000001',
   '76600000-0000-0000-0000-000000000001', 'persons', 3,
   'Gemeldete Personen', date '2026-01-01', date '2026-01-31',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76600000-0000-0000-0000-000000000001', 'persons', 2,
   'Gemeldete Personen', date '2026-02-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76600000-0000-0000-0000-000000000002', 'persons', 1,
   'Gemeldete Personen', date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76600000-0000-0000-0000-000000000003', 'persons', 1,
   'Gemeldete Personen', date '2020-01-01', null,
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

-- Open to begin with: a trigger refuses an entry into a closed period, so the
-- fixture books first and closes afterwards -- which is the order a workspace
-- works in anyway.
insert into public.finance_periods (
  id, workspace_id, fiscal_year, period_month, status,
  created_by, updated_by
) values
  ('76900000-0000-0000-0000-000000000001',
   '76100000-0000-0000-0000-000000000001', 2026, 1, 'open',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76900000-0000-0000-0000-000000000002',
   '76100000-0000-0000-0000-000000000001', 2026, 2, 'open',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76900000-0000-0000-0000-000000000003',
   '76100000-0000-0000-0000-000000000001', 2026, 3, 'open',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

insert into public.finance_ledger_entries (
  workspace_id, property_id, account_id, period_id, booked_on, amount,
  currency_code, created_by, updated_by
) values
  -- Area: 1000 over 60/30/10 -> 600/300/100, no remainder.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000001',
   '76900000-0000-0000-0000-000000000001', date '2026-01-10', 1000, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Unit count: 1000 over 3 -> 333.33 each and one cent left over.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000002',
   '76900000-0000-0000-0000-000000000001', date '2026-01-15', 1000, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Persons: 500 over 3/1/1 -> 300/100/100 in January.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000005',
   '76900000-0000-0000-0000-000000000001', date '2026-01-12', 500, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000006',
   '76900000-0000-0000-0000-000000000001', date '2026-01-20', 500, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000007',
   '76900000-0000-0000-0000-000000000001', date '2026-01-25', 300, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000003',
   '76900000-0000-0000-0000-000000000002', date '2026-02-05', 800, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000004',
   '76900000-0000-0000-0000-000000000002', date '2026-02-10', 200, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- The rent, in the same ledger, in the same window, on an income account
  -- with no rule of its own.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000001',
   '76300000-0000-0000-0000-000000000008',
   '76900000-0000-0000-0000-000000000001', date '2026-01-03', 12000, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Haus C: one cost type with no key of its own, and two with the awkward
  -- ones.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000001',
   '76900000-0000-0000-0000-000000000001', date '2026-01-08', 200, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000009',
   '76900000-0000-0000-0000-000000000001', date '2026-01-09', 300, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000003',
   '76300000-0000-0000-0000-000000000010',
   '76900000-0000-0000-0000-000000000001', date '2026-01-14', 400, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  -- Haus B books the same month in two currencies.
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000002',
   '76300000-0000-0000-0000-000000000001',
   '76900000-0000-0000-0000-000000000001', date '2026-01-10', 100, 'EUR',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001'),
  ('76100000-0000-0000-0000-000000000001',
   '76500000-0000-0000-0000-000000000002',
   '76300000-0000-0000-0000-000000000001',
   '76900000-0000-0000-0000-000000000001', date '2026-01-11', 100, 'CHF',
   '76200000-0000-0000-0000-000000000001',
   '76200000-0000-0000-0000-000000000001');

update public.finance_periods
set status = 'closed',
    closed_at = now(),
    closed_by = '76200000-0000-0000-0000-000000000001'
where workspace_id = '76100000-0000-0000-0000-000000000001'
  and period_month in (1, 2);

create or replace function pg_temp.as_user(
  p_user uuid,
  p_statement text,
  p_aal text default 'aal2'
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

create or replace function pg_temp.preview(
  p_from date default '2026-01-01',
  p_to date default '2026-02-28',
  p_property uuid default '76500000-0000-0000-0000-000000000001',
  p_user uuid default '76200000-0000-0000-0000-000000000001',
  p_aal text default 'aal2'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.property_service_charge_preview(
        %L::uuid, %L::uuid, %L::date, %L::date)$q$,
      '76100000-0000-0000-0000-000000000001', p_property, p_from, p_to
    ),
    p_aal
  );
$$;

-- The line for one unit and one account, which is what every arithmetic
-- assertion below actually looks at.
create or replace function pg_temp.line(
  p_unit_code text,
  p_account_code text,
  p_from date default '2026-01-01',
  p_to date default '2026-02-28'
)
returns jsonb
language sql
as $$
  select line
  from jsonb_array_elements(
         pg_temp.preview(p_from, p_to) -> 'entity' -> 'units') as unit,
       jsonb_array_elements(unit -> 'lines') as line
  where unit ->> 'unit_code' = p_unit_code
    and line ->> 'account_code' = p_account_code;
$$;

create or replace function pg_temp.account(
  p_account_code text,
  p_from date default '2026-01-01',
  p_to date default '2026-02-28'
)
returns jsonb
language sql
as $$
  select account
  from jsonb_array_elements(
         pg_temp.preview(p_from, p_to) -> 'entity' -> 'accounts') as account
  where account ->> 'account_code' = p_account_code;
$$;

create or replace function pg_temp.account_c(
  p_account_code text,
  p_from date default '2026-01-01',
  p_to date default '2026-02-28'
)
returns jsonb
language sql
as $$
  select account
  from jsonb_array_elements(
         pg_temp.preview(p_from, p_to,
                         '76500000-0000-0000-0000-000000000003')
           -> 'entity' -> 'accounts') as account
  where account ->> 'account_code' = p_account_code;
$$;

create or replace function pg_temp.unit(
  p_unit_code text,
  p_from date default '2026-01-01',
  p_to date default '2026-02-28'
)
returns jsonb
language sql
as $$
  select unit
  from jsonb_array_elements(
         pg_temp.preview(p_from, p_to) -> 'entity' -> 'units') as unit
  where unit ->> 'unit_code' = p_unit_code;
$$;

-- ---------------------------------------------------------------------------
-- Who may ask
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview(p_aal => 'aal1') -> 'error' ->> 'message',
  'AAL2 is required for finance reads',
  'DEC-025: a single factor does not open a settlement');

select is(
  pg_temp.preview(
    p_property => '76500000-0000-0000-0000-000000000002',
    p_user => '76200000-0000-0000-0000-000000000002'
  ) -> 'error' ->> 'code',
  'forbidden',
  'and the analyst scoped to Haus A cannot settle Haus B');

select is(
  pg_temp.preview(p_user => '76200000-0000-0000-0000-000000000002')
    -> 'ok',
  'true'::jsonb,
  'while Haus A answers for the same analyst -- paired so the refusal above '
  'is the scope and not the role');

-- ---------------------------------------------------------------------------
-- The period has to be a period
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview(date '2026-01-15', date '2026-02-28') -> 'error' ->> 'code',
  'validation_failed',
  'a period that does not start on the first of a month is refused: the '
  'booking periods of this schema are calendar months');

select is(
  pg_temp.preview(date '2026-01-01', date '2026-02-15') -> 'error' ->> 'code',
  'validation_failed',
  'and so is one that does not end on the last of a month');

select is(
  pg_temp.preview(date '2026-03-01', date '2026-01-31') -> 'error' ->> 'field',
  'to',
  'a period that ends before it starts names the field that is wrong');

select is(
  pg_temp.preview(date '-infinity', date '2026-01-31') -> 'error' ->> 'code',
  'validation_failed',
  'and an infinite date is refused rather than raising 22003 out of the '
  'arithmetic below');

-- ---------------------------------------------------------------------------
-- The number
-- ---------------------------------------------------------------------------

select is(
  pg_temp.line('A-01', '4300') ->> 'amount',
  '600.00',
  '1000 EUR over 60 of 100 square metres is 600 -- the whole point of the '
  'package, and the one assertion that would make every other one pointless '
  'if it were wrong');

select is(
  pg_temp.line('A-02', '4300') ->> 'amount',
  '300.00',
  'and 30 of 100 is 300');

select is(
  pg_temp.line('A-03', '4300') ->> 'amount',
  '100.00',
  'and 10 of 100 is 100 -- the three sum back to the booked amount');

select is(
  pg_temp.line('A-01', '4300') ->> 'numerator',
  '60',
  'the line carries its own numerator, so the figure can be redone');

select is(
  pg_temp.line('A-01', '4300') ->> 'denominator',
  '100',
  'and its denominator');

select is(
  pg_temp.line('A-01', '4300') ->> 'explanation',
  'Nach Wohnflaeche in Quadratmetern (§ 556a Abs. 1 Satz 1 BGB).',
  'and the explanation of the key, which DEC-014 makes one of the four '
  'particulars an operating-cost statement cannot be valid without');

select is(
  pg_temp.account('4300') ->> 'rounding_difference',
  '0.00',
  'an exact division leaves nothing over');

-- ---------------------------------------------------------------------------
-- The cent that does not divide
-- ---------------------------------------------------------------------------

select is(
  pg_temp.line('A-01', '4310') ->> 'amount',
  '333.33',
  '1000 EUR over three units is 333.33');

select is(
  pg_temp.account('4310') ->> 'rounding_difference',
  '0.01',
  'and the cent that is left is reported at the account rather than pushed '
  'onto one unit, because who carries it is a decision');

select is(
  (select sum((line ->> 'amount')::numeric)
   from jsonb_array_elements(
          pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4310'),
  999.99,
  'the lines plus the reported difference are the booked amount -- stated as '
  'a sum so the two assertions above cannot both drift together');

-- ---------------------------------------------------------------------------
-- What is refused, and where its money went
-- ---------------------------------------------------------------------------

select is(
  pg_temp.account('4900') ->> 'allocatable',
  'false',
  'a cost type classified as not apportionable is reported');

select is(
  (select count(*)::integer
   from jsonb_array_elements(
          pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4900'),
  0,
  'and appears in no line');

select is(
  pg_temp.preview() -> 'entity' -> 'totals' ->> 'not_apportionable',
  '500.00',
  'while its amount stays visible in its own total');

select is(
  pg_temp.account('4950') -> 'refusal' ->> 'reason',
  'unclassified',
  'a cost type nobody has classified is refused as unclassified -- not as '
  'not apportionable, which is a decision somebody made');

select is(
  pg_temp.preview() -> 'entity' -> 'totals' ->> 'unclassified',
  '300.00',
  'and its amount is counted separately, because it is the work standing '
  'between these bookings and a complete statement');

select is(
  pg_temp.account('4400') -> 'refusal' ->> 'reason',
  'no_meters',
  'a consumption key refuses by name until P-4 brings meters');

select is(
  pg_temp.account('4500') -> 'refusal' ->> 'reason',
  'no_key',
  'and a cost type with no distribution key refuses as such -- a statement '
  'without an explanation of the key is formally void, so there is nothing '
  'to fall back on');

select is(
  pg_temp.preview() -> 'entity' -> 'totals'
    ->> 'apportionable_not_distributed',
  '1500.00',
  'the three refused apportionable amounts stay in a total of their own: '
  'DEC-029, never sum around a gap');

select is(
  pg_temp.preview() -> 'entity' -> 'totals' ->> 'distributed',
  '2000.00',
  'and the distributed total counts only what actually reached a unit -- '
  'paired with the line above so neither can absorb the other');

-- ---------------------------------------------------------------------------
-- Rent is not a cost
-- ---------------------------------------------------------------------------

select is(
  pg_temp.account('4000'),
  null,
  'an income account with bookings in the period does not appear at all: a '
  'service-charge statement settles costs, and rent is not one');

select is(
  pg_temp.preview() -> 'entity' -> 'totals' ->> 'unclassified',
  '300.00',
  'so the unclassified total is still the 300 EUR of unclassified *cost* -- '
  'without the filter the 12000 EUR of rent would sit here as an open task '
  'that is not one');

select is(
  (select count(*)::integer
   from jsonb_array_elements(
          pg_temp.preview() -> 'entity' -> 'units') as unit,
        jsonb_array_elements(unit -> 'lines') as line
   where line ->> 'account_code' = '4000'),
  0,
  'and no unit is charged a share of the rent');

-- ---------------------------------------------------------------------------
-- Question 1: a basis that changed inside the period
-- ---------------------------------------------------------------------------

select is(
  pg_temp.account('4600') -> 'refusal' ->> 'reason',
  'basis_changed_in_window',
  'a person count that changes on 1 February refuses for a January-February '
  'settlement: whether the period is measured at a reference date or weighted '
  'over time changes the amount and is not decided here');

select is(
  pg_temp.account('4600', date '2026-01-01', date '2026-01-31')
    -> 'distributed',
  'true'::jsonb,
  'and the same figures distribute over January, which the value does span '
  '-- so the refusal is a property of the window, not of the data');

select is(
  pg_temp.line('A-01', '4600', date '2026-01-01', date '2026-01-31')
    ->> 'amount',
  '300.00',
  '500 EUR over 3 of 5 persons is 300');

select is(
  pg_temp.line('A-02', '4600', date '2026-01-01', date '2026-01-31')
    ->> 'amount',
  '100.00',
  'and 1 of 5 is 100');

-- ---------------------------------------------------------------------------
-- Question 2: a unit that was let for part of the period
-- ---------------------------------------------------------------------------

select is(
  pg_temp.unit('A-01') ->> 'days_let',
  '31',
  'A-01 was let for 31 of the 59 days');

select is(
  pg_temp.unit('A-01') ->> 'days_in_window',
  '59',
  'and the period says how long it is, so the reader can see the question');

select is(
  pg_temp.unit('A-03') ->> 'days_let',
  '0',
  'A-03 was let for none of them -- paired so the count above is not simply '
  'the length of the period');

select is(
  pg_temp.unit('A-03') ->> 'total',
  '433.33',
  'and the empty unit still carries its share: who bears it is exactly the '
  'question this package refuses to answer, so nothing is taken off here');

-- ---------------------------------------------------------------------------
-- The unit total is the sum of its own lines
-- ---------------------------------------------------------------------------

select is(
  pg_temp.unit('A-01') ->> 'total',
  '933.33',
  '600 from the area key plus 333.33 from the unit-count key');

select is(
  (select sum((unit ->> 'total')::numeric)
   from jsonb_array_elements(
          pg_temp.preview() -> 'entity' -> 'units') as unit),
  1999.99,
  'and the unit totals add up to the distributed amount less the reported '
  'rounding difference');

-- ---------------------------------------------------------------------------
-- Provisional, and the covered periods
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview() -> 'entity' -> 'is_provisional',
  'false'::jsonb,
  'a settlement over two closed periods is not provisional');

select is(
  pg_temp.preview(date '2026-01-01', date '2026-03-31')
    -> 'entity' -> 'is_provisional',
  'true'::jsonb,
  'and one that reaches into an open period is -- paired so the flag is not '
  'simply always false');

select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.preview() -> 'entity' -> 'periods')),
  2,
  'the covered periods are named, so a reader can see what was included');

select is(
  pg_temp.preview() -> 'entity' -> 'is_preview',
  'true'::jsonb,
  'and the answer says on its face that it is not a statement: nothing here '
  'is stored, versioned or deliverable');

-- ---------------------------------------------------------------------------
-- Which key governs, when more than one could
-- ---------------------------------------------------------------------------

select is(
  pg_temp.account_c('4300') -> 'distributed',
  'true'::jsonb,
  'a cost type with no key of its own is distributed by the catch-all key');

select is(
  pg_temp.account_c('4300') -> 'key' ->> 'explanation',
  'Auffangschluessel Haus C: nach Flaeche.',
  'and cites that key by its explanation -- paired with the two refusals '
  'below, so neither of them passes by the catch-all never being reached');

select is(
  pg_temp.account_c('4700') -> 'refusal' ->> 'reason',
  'ambiguous_key',
  'two keys valid for the whole period refuse rather than one of them being '
  'picked: the exclusion constraint coalesces cost_pool_id, so both are legal '
  'and a limit 1 would have chosen arbitrarily');

select is(
  pg_temp.account_c('4700') -> 'distributed',
  'false'::jsonb,
  'and nothing is distributed under either of them');

select is(
  pg_temp.account_c('4800') -> 'refusal' ->> 'reason',
  'key_not_stable_in_window',
  'a key written for this cost type that covers only January refuses for a '
  'January-February period -- it does not fall back to the catch-all, which '
  'would ignore what was agreed for January');

select is(
  pg_temp.account_c('4800', date '2026-01-01', date '2026-01-31')
    -> 'key' ->> 'explanation',
  'Winterdienst im Januar: zu gleichen Teilen.',
  'while over January the same data uses that very key -- so the refusal is '
  'a property of the window, not of the key');

-- ---------------------------------------------------------------------------
-- Two currencies have no total
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview(
    p_property => '76500000-0000-0000-0000-000000000002'
  ) -> 'error' ->> 'field',
  'currency',
  'a period holding two currencies is refused outright rather than summed: '
  'adding them would invent an exchange rate');

-- ---------------------------------------------------------------------------
-- Nothing booked is not an error
-- ---------------------------------------------------------------------------

select is(
  pg_temp.preview(date '2026-03-01', date '2026-03-31') -> 'ok',
  'true'::jsonb,
  'a period with no bookings answers');

select is(
  pg_temp.preview(date '2026-03-01', date '2026-03-31')
    -> 'entity' -> 'totals' ->> 'distributed',
  '0',
  'with a distributed total of zero');

select is(
  (select count(*)::integer
   from jsonb_array_elements(
          pg_temp.preview(date '2026-03-01', date '2026-03-31')
            -> 'entity' -> 'units')),
  3,
  'and the units still listed, so an empty statement reads as "nothing was '
  'booked" rather than as "this property has no units"');

select is(
  pg_temp.preview(date '2026-03-01', date '2026-03-31')
    -> 'entity' ->> 'currency_code',
  null,
  'and no currency is claimed, because none was booked');

select * from finish();
rollback;
