begin;

create extension if not exists pgtap with schema extensions;

-- FINANCE-BOOKINGS-01.
--
-- Two things carry this package.
--
-- **A booking must land in the period it says it does.** Until now
-- `record_finance_ledger_entry` checked the account, the property, the unit,
-- the lease and whether the period was open — and never that `booked_on` fell
-- inside the period. A cost dated 2024-03-15 was accepted into 2026/01.
-- Everything downstream groups by period, so that is a wrong number in every
-- read built on it, silently. Asserted in both directions: a date outside is
-- refused by name, a date inside is accepted.
--
-- **What was booked has to be visible.** `property_finance_actuals` sums per
-- account and reports `entries` as a count. Without a row-level read there is
-- no way to notice a mis-booking — and no way to fix one either, because
-- there is no update, no delete and no reversal. The only remedy is a
-- compensating counter-booking, which is why the amount is signed and why
-- this test asserts that a negative amount is accepted rather than treated as
-- an error.
--
-- The period list matters for a duller reason: `open_finance_period` refuses a
-- duplicate with `dependency_conflict` and deliberately carries no entity, so
-- without a list a client could not discover a period it had not itself just
-- opened. The command was write-only in practice.

select plan(28);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('75200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'book-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('75200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'book-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('75100000-0000-0000-0000-000000000001', 'book', 'Book');
select private.seed_workspace_role_catalog('75100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '75100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('75200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('75200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '75100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('75500000-0000-0000-0000-000000000001', '75100000-0000-0000-0000-000000000001',
   'Buchhaus A', 'Buchweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001'),
  ('75500000-0000-0000-0000-000000000002', '75100000-0000-0000-0000-000000000001',
   'Buchhaus B', 'Buchweg 2', '10115', 'Berlin', 'de', 'residential', 1,
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm,
  created_by, updated_by
) values
  ('75600000-0000-0000-0000-000000000001', '75100000-0000-0000-0000-000000000001',
   '75500000-0000-0000-0000-000000000001', 'A-01', 'occupied', 50,
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001');

-- The analyst is scoped to Buchhaus A only, which is what makes the entity
-- gate on the entry read observable.
insert into public.entity_scopes (
  workspace_id, membership_id, entity_type, entity_id, created_by
)
select '75100000-0000-0000-0000-000000000001', membership.id, 'property',
       '75500000-0000-0000-0000-000000000001',
       '75200000-0000-0000-0000-000000000001'
from public.memberships as membership
where membership.workspace_id = '75100000-0000-0000-0000-000000000001'
  and membership.user_id = '75200000-0000-0000-0000-000000000002';

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('75300000-0000-0000-0000-000000000001', '75100000-0000-0000-0000-000000000001',
   '4300', 'Hausmeister', 'expense',
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001'),
  -- Deliberately left unclassified: the read must report `allocatable` as
  -- null for it, which is not the same as false.
  ('75300000-0000-0000-0000-000000000002', '75100000-0000-0000-0000-000000000001',
   '4900', 'Instandhaltung', 'expense',
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001');

insert into public.finance_account_allocation_rules (
  finance_account_id, workspace_id, allocatable, settlement_principle,
  created_by, updated_by
) values
  ('75300000-0000-0000-0000-000000000001', '75100000-0000-0000-0000-000000000001',
   true, 'performance',
   '75200000-0000-0000-0000-000000000001', '75200000-0000-0000-0000-000000000001');

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

create or replace function pg_temp.periods(
  p_include_closed boolean default true,
  p_user uuid default '75200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.workspace_finance_periods(%L::uuid, %L::boolean)$q$,
      '75100000-0000-0000-0000-000000000001', p_include_closed
    )
  );
$$;

create or replace function pg_temp.book(
  p_booked_on date,
  p_amount numeric default 1000,
  p_account uuid default '75300000-0000-0000-0000-000000000001',
  p_property uuid default '75500000-0000-0000-0000-000000000001',
  p_month integer default 1,
  p_user uuid default '75200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.record_finance_ledger_entry(
        %L::uuid, %L::uuid, %L::uuid,
        (select id from public.finance_periods
         where workspace_id = %L::uuid and period_month = %s),
        %L::date, %s, 'EUR', %L::uuid, %L::uuid, 'Test', null, null, null)$q$,
      '75100000-0000-0000-0000-000000000001', p_property, p_account,
      '75100000-0000-0000-0000-000000000001', p_month,
      p_booked_on, p_amount, gen_random_uuid(), gen_random_uuid()
    )
  );
$$;

create or replace function pg_temp.entries(
  p_property uuid default '75500000-0000-0000-0000-000000000001',
  p_user uuid default '75200000-0000-0000-0000-000000000001',
  p_account uuid default null,
  p_limit integer default 100,
  p_period uuid default null
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.property_finance_ledger_entries(
        %L::uuid, %L::uuid, %L::uuid, %L::uuid, %s)$q$,
      '75100000-0000-0000-0000-000000000001', p_property,
      p_period, p_account, coalesce(p_limit::text, 'null')
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- A period can be found, not only opened
-- ---------------------------------------------------------------------------

select is(
  pg_temp.periods() -> 'entity' ->> 'total_count',
  '0',
  'a fresh workspace has no accounting periods');

select is(
  pg_temp.as_user('75200000-0000-0000-0000-000000000001',
    format(
      $q$select public.open_finance_period(%L::uuid, 2026, 1, %L::uuid, %L::uuid)$q$,
      '75100000-0000-0000-0000-000000000001',
      gen_random_uuid(), gen_random_uuid()))
    -> 'entity' ->> 'status',
  'open',
  'and one can be opened');

select is(
  pg_temp.periods() -> 'entity' ->> 'total_count',
  '1',
  'after which the list finds it -- before this package a period could only '
  'be discovered by trying to open it again, and that refusal carries no '
  'entity');

select is(
  (select entry ->> 'entry_count'
   from jsonb_array_elements(pg_temp.periods() -> 'entity' -> 'periods') as entry),
  '0',
  'with nothing booked into it yet');

-- ---------------------------------------------------------------------------
-- The correctness fix: a booking lands in its own period
-- ---------------------------------------------------------------------------

select is(
  pg_temp.book(date '2024-03-15') -> 'error' ->> 'field',
  'booked_on',
  'a cost dated in 2024 is refused for the 2026/01 period -- it used to be '
  'accepted, and every figure downstream groups by period');

select is(
  pg_temp.book(date '2026-02-03') -> 'error' ->> 'field',
  'booked_on',
  'and so is one dated in the right year but the wrong month');

select ok(
  (pg_temp.book(date '2026-02-03') -> 'error' ->> 'message')
    like '%2026-02-03%2026-01%',
  'the refusal names both dates, so the reader can see which one is wrong');

select is(
  pg_temp.book(date '2026-01-15') -> 'ok',
  'true'::jsonb,
  'a date inside the period is accepted -- paired with the two above so '
  'neither passes by the command refusing everything');

select is(
  (select entry ->> 'entry_count'
   from jsonb_array_elements(pg_temp.periods() -> 'entity' -> 'periods') as entry),
  '1',
  'and the period list now counts it');

-- ---------------------------------------------------------------------------
-- What was booked is visible, because it cannot be corrected
-- ---------------------------------------------------------------------------

select is(
  pg_temp.entries() -> 'entity' ->> 'total_count',
  '1',
  'the entry read returns the booking line by line');

select is(
  (select entry ->> 'account_code'
   from jsonb_array_elements(pg_temp.entries() -> 'entity' -> 'entries') as entry),
  '4300',
  'naming the cost type, so the line reads without a second round trip');

select is(
  (select entry ->> 'allocatable'
   from jsonb_array_elements(pg_temp.entries() -> 'entity' -> 'entries') as entry),
  'true',
  'and whether that cost may be passed on to tenants');

-- There is no update, no delete and no reversal command. The only remedy for
-- a mis-booking is a compensating counter-booking, which is why the amount is
-- signed -- and why this assertion is a feature rather than a curiosity.
select is(
  pg_temp.book(date '2026-01-15', -1000) -> 'ok',
  'true'::jsonb,
  'a negative amount is accepted: it is the only correction path this schema '
  'has, since a booking can never be edited or deleted');

select is(
  pg_temp.entries() -> 'entity' ->> 'total_count',
  '2',
  'and the counter-booking stands beside the original rather than replacing '
  'it -- the trail keeps both');

select is(
  pg_temp.book(date '2026-01-20', 500,
               '75300000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'a cost on an unclassified type can be booked');

select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.entries() -> 'entity' -> 'entries') as entry
   where entry -> 'allocatable' = 'null'::jsonb),
  1,
  'and reads as null rather than false: nobody has decided whether it may be '
  'passed on, which is not the same as deciding that it may not');

-- ---------------------------------------------------------------------------
-- The filters and the cap, which decide what a reader is actually looking at
-- ---------------------------------------------------------------------------

-- Three entries stand at this point: two on 4300 (1000 and -1000, both
-- 2026-01-15) and one on 4900 (500, 2026-01-20).

select is(
  pg_temp.entries(p_account => '75300000-0000-0000-0000-000000000002')
    -> 'entity' ->> 'total_count',
  '1',
  'the account filter narrows the read to one cost type');

select is(
  (select entry ->> 'account_code'
   from jsonb_array_elements(
     pg_temp.entries(p_account => '75300000-0000-0000-0000-000000000002')
       -> 'entity' -> 'entries') as entry),
  '4900',
  'and returns that one rather than the first row of an unfiltered read');

select is(
  pg_temp.entries() -> 'entity' ->> 'total_count',
  '3',
  'while the unfiltered read still finds all three -- paired so neither of '
  'the two above passes by the filter being ignored');

select is(
  pg_temp.entries(p_limit => 1) -> 'entity' ->> 'returned_count',
  '1',
  'the cap limits what comes back');

select is(
  pg_temp.entries(p_limit => 1) -> 'entity' ->> 'total_count',
  '3',
  'but the total still counts every matching row: a page that reported its '
  'own length as the total would read as the whole ledger');

select is(
  (select entry ->> 'booked_on'
   from jsonb_array_elements(
     pg_temp.entries(p_limit => 1) -> 'entity' -> 'entries') as entry),
  '2026-01-20',
  'and a capped page holds the newest booking, which is what the surface '
  'tells the reader it is showing');

select is(
  pg_temp.entries(p_limit => 0) -> 'entity' ->> 'returned_count',
  '1',
  'a cap of zero is clamped to one rather than returning an empty ledger '
  'that would read as "nothing is booked here"');

-- ---------------------------------------------------------------------------
-- Closing a period, and finding it afterwards
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user('75200000-0000-0000-0000-000000000001',
    format(
      $q$select public.transition_finance_period_status(
        %L::uuid,
        (select id from public.finance_periods where period_month = 1),
        'closed',
        (select version from public.finance_periods where period_month = 1),
        %L::uuid, %L::uuid, 'Monatsabschluss')$q$,
      '75100000-0000-0000-0000-000000000001',
      gen_random_uuid(), gen_random_uuid()))
    -> 'entity' ->> 'status',
  'closed',
  'a period can be closed');

select is(
  pg_temp.periods(false) -> 'entity' ->> 'total_count',
  '0',
  'and the open-only list then finds nothing');

select is(
  pg_temp.periods(true) -> 'entity' ->> 'total_count',
  '1',
  'while the full list still finds it -- paired so neither passes by the '
  'filter being absent');

-- ---------------------------------------------------------------------------
-- Who may see what
-- ---------------------------------------------------------------------------

select is(
  pg_temp.entries(p_user => '75200000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'the analyst is scoped to Buchhaus A and may read its bookings');

select is(
  pg_temp.entries('75500000-0000-0000-0000-000000000002',
                  '75200000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'forbidden',
  'and Buchhaus B is refused them before any of its spending is returned');

select * from finish();
rollback;
