begin;

create extension if not exists pgtap with schema extensions;

-- FINANCE-01a: chart of accounts, accounting periods, property actuals.
--
-- The assertions cluster around the three rules the schema is supposed to
-- enforce rather than merely document:
--
--   * a closed period does not move — not through the command, and not
--     through a direct write either;
--   * a figure that includes an open period says it is provisional;
--   * currencies never merge, and no net result is published at all, because
--     a net result is a formula and formulas need a version this increment
--     does not yet have.

select plan(60);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'finance_accounts', 'the chart of accounts exists');
select has_table('public', 'finance_periods', 'the period table exists');
select has_table('public', 'finance_ledger_entries', 'the ledger exists');

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname in (
       'finance_accounts', 'finance_periods', 'finance_ledger_entries'
     )),
  'row level security is on and forced for all three'
);

select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'public'
     and tablename in (
       'finance_accounts', 'finance_periods', 'finance_ledger_entries'
     )
     and cmd <> 'SELECT'),
  0,
  'no write policy: every mutation goes through an audited RPC'
);

select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in (
       'finance_accounts', 'finance_periods', 'finance_ledger_entries'
     )
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'authenticated may read and nothing more'
);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin-reader@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin-booker@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'fin-a', 'Finance A');

select private.seed_workspace_role_catalog('e1000000-0000-0000-0000-000000000001');

-- Reader: finance.read only. Booker: read + manage, but NOT close.
insert into public.roles (id, workspace_id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'fin_reader', 'Finance Reader'),
  ('e3000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'fin_booker', 'Finance Booker');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'e1000000-0000-0000-0000-000000000001',
       'e3000000-0000-0000-0000-000000000001', permission.id
from public.permissions as permission
where permission.key in ('property.read', 'finance.read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'e1000000-0000-0000-0000-000000000001',
       'e3000000-0000-0000-0000-000000000002', permission.id
from public.permissions as permission
where permission.key in ('property.read', 'finance.read', 'finance.manage');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'e1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('e4000000-0000-0000-0000-000000000001'::uuid, 'e2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('e4000000-0000-0000-0000-000000000002'::uuid, 'e2000000-0000-0000-0000-000000000002'::uuid, 'fin_reader'),
  ('e4000000-0000-0000-0000-000000000003'::uuid, 'e2000000-0000-0000-0000-000000000003'::uuid, 'fin_booker')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'e1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'Zahlenhaus', 'Bilanzweg 3', '10115', 'Berlin', 'de', 'residential', 1,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function pg_temp.as_user(p_user uuid, p_aal text default 'aal2')
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
end;
$$;

create or replace function pg_temp.as_postgres()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
end;
$$;

create or replace function pg_temp.call(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute p_sql into v_result;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

select pg_temp.as_user('e2000000-0000-0000-0000-000000000001');

select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '4000', 'Mieterträge', 'income',
    'e6000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001'
  ) ->> 'ok'),
  'true',
  'an admin opens an income account'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '5000', 'Betriebskosten', 'expense',
    'e6000000-0000-0000-0000-000000000002', 'e7000000-0000-0000-0000-000000000002'
  ) ->> 'ok'),
  'true',
  'and an expense account'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '4000', 'Doppelt', 'income',
    'e6000000-0000-0000-0000-000000000003', 'e7000000-0000-0000-0000-000000000003'
  ) -> 'error' ->> 'code'),
  'dependency_conflict',
  'a duplicate code is refused, not silently renamed'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '6000', 'Unfug', 'profit',
    'e6000000-0000-0000-0000-000000000004', 'e7000000-0000-0000-0000-000000000004'
  ) -> 'error' ->> 'code'),
  'validation_failed',
  'an unsupported account type is refused'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '7000', 'Ohne Typ', null,
    'e6000000-0000-0000-0000-000000000005', 'e7000000-0000-0000-0000-000000000005'
  ) -> 'error' ->> 'field'),
  'account_type',
  'and the refusal names the field'
);

-- Idempotency: the same mutation id and the same command replays.
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '4000', 'Mieterträge', 'income',
    'e6000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001'
  ) -> 'entity' ->> 'code'),
  '4000',
  'a retried create replays its receipt instead of failing on the unique code'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '4100', 'Anderes', 'income',
    'e6000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000009'
  ) -> 'error' ->> 'code'),
  'mutation_conflict',
  'the same mutation id with a different command is a conflict'
);

select is(
  (select count(*)::integer from public.finance_accounts
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'),
  2,
  'exactly the two accepted accounts exist'
);

-- Cycle protection on the hierarchy.
select is(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    1, 'e6000000-0000-0000-0000-00000000000a', 'e7000000-0000-0000-0000-00000000000a',
    null, (select id from public.finance_accounts where code = '4000')
  ) ->> 'ok'),
  'true',
  'an account may be parented under another'
);
select is(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    1, 'e6000000-0000-0000-0000-00000000000b', 'e7000000-0000-0000-0000-00000000000b',
    null, (select id from public.finance_accounts where code = '5000')
  ) -> 'error' ->> 'code'),
  'dependency_conflict',
  'but not so that the chart of accounts closes into a cycle'
);
select is(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    99, 'e6000000-0000-0000-0000-00000000000c', 'e7000000-0000-0000-0000-00000000000c',
    'Neuer Name'
  ) -> 'error' ->> 'code'),
  'version_conflict',
  'a stale expected version is a conflict, and the current row travels back'
);
select ok(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    99, 'e6000000-0000-0000-0000-00000000000d', 'e7000000-0000-0000-0000-00000000000d',
    'Neuer Name'
  ) -> 'entity' ->> 'version' = '1'),
  'so the caller can retry against the version that is actually there'
);

-- ---------------------------------------------------------------------------
-- Periods
-- ---------------------------------------------------------------------------

select is(
  (select public.open_finance_period(
    'e1000000-0000-0000-0000-000000000001', 2026, 1,
    'e6000000-0000-0000-0000-000000000010', 'e7000000-0000-0000-0000-000000000010'
  ) -> 'entity' ->> 'status'),
  'open',
  'a new period starts open'
);
select is(
  (select public.open_finance_period(
    'e1000000-0000-0000-0000-000000000001', 2026, 2,
    'e6000000-0000-0000-0000-000000000011', 'e7000000-0000-0000-0000-000000000011'
  ) ->> 'ok'),
  'true',
  'and a second one'
);
select is(
  (select public.open_finance_period(
    'e1000000-0000-0000-0000-000000000001', 2026, 1,
    'e6000000-0000-0000-0000-000000000012', 'e7000000-0000-0000-0000-000000000012'
  ) -> 'error' ->> 'code'),
  'dependency_conflict',
  'a period exists once'
);
select is(
  (select public.open_finance_period(
    'e1000000-0000-0000-0000-000000000001', 2026, 13,
    'e6000000-0000-0000-0000-000000000013', 'e7000000-0000-0000-0000-000000000013'
  ) -> 'error' ->> 'code'),
  'validation_failed',
  'there is no thirteenth month'
);

-- ---------------------------------------------------------------------------
-- Ledger entries
-- ---------------------------------------------------------------------------

select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-15', 1000, 'EUR',
    'e6000000-0000-0000-0000-000000000020', 'e7000000-0000-0000-0000-000000000020'
  ) ->> 'ok'),
  'true',
  'income is booked into an open period'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-20', 250, 'EUR',
    'e6000000-0000-0000-0000-000000000021', 'e7000000-0000-0000-0000-000000000021'
  ) ->> 'ok'),
  'true',
  'and so is an expense'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 2),
    date '2026-02-10', 900, 'CHF',
    'e6000000-0000-0000-0000-000000000022', 'e7000000-0000-0000-0000-000000000022'
  ) ->> 'ok'),
  'true',
  'a second currency is booked as itself, not converted'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-15', 100, 'eur',
    'e6000000-0000-0000-0000-000000000023', 'e7000000-0000-0000-0000-000000000023'
  ) -> 'error' ->> 'field'),
  'currency_code',
  'a lowercase currency is refused rather than upper-cased on the caller''s behalf'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-15', null, 'EUR',
    'e6000000-0000-0000-0000-000000000024', 'e7000000-0000-0000-0000-000000000024'
  ) -> 'error' ->> 'field'),
  'amount',
  'and a missing amount is refused, never defaulted to zero'
);
select ok(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-25', -50, 'EUR',
    'e6000000-0000-0000-0000-000000000025', 'e7000000-0000-0000-0000-000000000025'
  ) ->> 'ok' = 'true'),
  'a negative amount is legitimate: a credit note is not a validation error'
);

-- A retired account takes no new bookings.
select ok(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    (select version from public.finance_accounts where code = '5000'),
    'e6000000-0000-0000-0000-000000000026', 'e7000000-0000-0000-0000-000000000026',
    null, null, false, false
  ) ->> 'ok' = 'true'),
  'an account can be retired'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-28', 10, 'EUR',
    'e6000000-0000-0000-0000-000000000027', 'e7000000-0000-0000-0000-000000000027'
  ) -> 'error' ->> 'code'),
  'not_found',
  'and a retired account takes no further bookings'
);
select ok(
  (select public.update_finance_account(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '5000'),
    (select version from public.finance_accounts where code = '5000'),
    'e6000000-0000-0000-0000-000000000028', 'e7000000-0000-0000-0000-000000000028',
    null, null, false, true
  ) ->> 'ok' = 'true'),
  'reactivating it is an ordinary update, not a resurrection ritual'
);

-- ---------------------------------------------------------------------------
-- Closing
-- ---------------------------------------------------------------------------

select pg_temp.as_user('e2000000-0000-0000-0000-000000000003');
select is(
  (select public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 1),
    'closed', 1,
    'e6000000-0000-0000-0000-000000000030', 'e7000000-0000-0000-0000-000000000030'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'a member who may book may not declare a period final'
);

select pg_temp.as_user('e2000000-0000-0000-0000-000000000001');
select is(
  (select public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 1),
    'closed', 1,
    'e6000000-0000-0000-0000-000000000031', 'e7000000-0000-0000-0000-000000000031'
  ) -> 'entity' ->> 'status'),
  'closed',
  'finance.close closes it'
);
select ok(
  (select (public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 2),
    'closed', 1,
    'e6000000-0000-0000-0000-000000000032', 'e7000000-0000-0000-0000-000000000032'
  ) -> 'entity' ->> 'closed_at') is not null),
  'and the closing timestamp travels with the status, never separately'
);
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-31', 500, 'EUR',
    'e6000000-0000-0000-0000-000000000033', 'e7000000-0000-0000-0000-000000000033'
  ) -> 'error' ->> 'code'),
  'dependency_conflict',
  'a closed period takes no further entries'
);

-- The trigger is the backstop, not the command. Prove it separately, as a
-- writer that bypasses the RPC entirely.
select pg_temp.as_postgres();
select throws_ok(
  $$insert into public.finance_ledger_entries (
      workspace_id, property_id, account_id, period_id, booked_on, amount,
      currency_code, created_by, updated_by
    ) values (
      'e1000000-0000-0000-0000-000000000001',
      'e5000000-0000-0000-0000-000000000001',
      (select id from public.finance_accounts where code = '4000'),
      (select id from public.finance_periods where period_month = 1),
      date '2026-01-31', 500, 'EUR',
      'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'a direct write into a closed period is rejected by the invariant, not just '
  'by the command'
);
-- Back to the admin session the closing tests below need.
select pg_temp.as_user('e2000000-0000-0000-0000-000000000001');

select is(
  (select public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 1),
    'open', 2,
    'e6000000-0000-0000-0000-000000000034', 'e7000000-0000-0000-0000-000000000034'
  ) -> 'error' ->> 'field'),
  'reason',
  'reopening a closed period requires a reason: it changes numbers people '
  'have already reported on'
);
select is(
  (select public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 1),
    'open', 2,
    'e6000000-0000-0000-0000-000000000035', 'e7000000-0000-0000-0000-000000000035',
    'Nachbuchung Nebenkosten'
  ) -> 'entity' ->> 'status'),
  'open',
  'with one it reopens'
);
select ok(
  (select (period.closed_at is null and period.closed_by is null)
   from public.finance_periods as period where period.period_month = 1),
  'and the closing marker is cleared with it, so the terminal state has one '
  'answer'
);
select is(
  (select public.transition_finance_period_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.finance_periods where period_month = 1),
    'open', 3,
    'e6000000-0000-0000-0000-000000000036', 'e7000000-0000-0000-0000-000000000036',
    'Nochmal'
  ) -> 'error' ->> 'code'),
  'validation_failed',
  'reopening an open period is not a no-op, it is a mistake worth reporting'
);

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

create or replace function pg_temp.actuals(
  p_user uuid,
  p_aal text default 'aal2',
  p_property uuid default 'e5000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.as_user(p_user, p_aal);
  v_result := public.property_finance_actuals(
    'e1000000-0000-0000-0000-000000000001', p_property
  );
  perform pg_temp.as_postgres();
  return v_result;
end;
$$;

select pg_temp.as_postgres();
select is(
  (select public.property_finance_actuals(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.actuals('e2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.actuals(
     'e2000000-0000-0000-0000-000000000001', 'aal2',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown property is not found, not forbidden'
);

select is(
  (select (entry ->> 'amount')::numeric
   from jsonb_array_elements(
     pg_temp.actuals('e2000000-0000-0000-0000-000000000001') -> 'accounts'
   ) as entry
   where entry ->> 'account_code' = '4000'
     and entry ->> 'currency_code' = 'EUR'),
  1000::numeric,
  'the EUR income of that account is summed'
);
select is(
  (select (entry ->> 'amount')::numeric
   from jsonb_array_elements(
     pg_temp.actuals('e2000000-0000-0000-0000-000000000001') -> 'accounts'
   ) as entry
   where entry ->> 'account_code' = '4000'
     and entry ->> 'currency_code' = 'CHF'),
  900::numeric,
  'and the CHF income of the same account is its own row'
);
select is(
  (select (entry ->> 'amount')::numeric
   from jsonb_array_elements(
     pg_temp.actuals('e2000000-0000-0000-0000-000000000001') -> 'accounts'
   ) as entry
   where entry ->> 'account_code' = '5000'),
  200::numeric,
  'the expense account nets its credit note: 250 booked, 50 credited'
);
select ok(
  (select not (pg_temp.actuals('e2000000-0000-0000-0000-000000000001')
     ? 'net_result')),
  'no net result: that is a formula, and a formula needs a definition version '
  'this increment does not have'
);
select ok(
  (select not (pg_temp.actuals('e2000000-0000-0000-0000-000000000001')
     ? 'noi')),
  'and no NOI, for the same reason'
);
select ok(
  (select (pg_temp.actuals('e2000000-0000-0000-0000-000000000001')
     -> 'is_provisional')::boolean),
  'the figures are provisional while any covered period is open'
);
select is(
  (select (pg_temp.actuals('e2000000-0000-0000-0000-000000000001')
     ->> 'open_periods')::integer),
  1,
  'and the count of open periods says how provisional'
);
select is(
  (select (pg_temp.actuals('e2000000-0000-0000-0000-000000000001')
     ->> 'covered_periods')::integer),
  2,
  'against the periods actually covered'
);
select is(
  (select entry ->> 'status'
   from jsonb_array_elements(
     pg_temp.actuals('e2000000-0000-0000-0000-000000000001') -> 'periods'
   ) as entry
   where (entry ->> 'period_month')::integer = 2),
  'closed',
  'each covered period reports its own status'
);

-- A property with no bookings is empty, not zero-valued.
insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('e5000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'Leerhaus', 'Bilanzweg 5', '10115', 'Berlin', 'de', 'residential', 1,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

select is(
  (select jsonb_array_length(
     pg_temp.actuals(
       'e2000000-0000-0000-0000-000000000001', 'aal2',
       'e5000000-0000-0000-0000-000000000002'
     ) -> 'accounts')),
  0,
  'a property with no bookings has no account rows'
);
select ok(
  (select not (pg_temp.actuals(
     'e2000000-0000-0000-0000-000000000001', 'aal2',
     'e5000000-0000-0000-0000-000000000002'
   ) -> 'is_provisional')::boolean),
  'and nothing to be provisional about'
);

-- ---------------------------------------------------------------------------
-- Permissions on the read and the writes
-- ---------------------------------------------------------------------------

select is(
  (select pg_temp.actuals('e2000000-0000-0000-0000-000000000002')
     ->> 'ok'),
  'true',
  'finance.read is enough to read the actuals'
);

select pg_temp.as_user('e2000000-0000-0000-0000-000000000002');
select is(
  (select public.record_finance_ledger_entry(
    'e1000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    (select id from public.finance_accounts where code = '4000'),
    (select id from public.finance_periods where period_month = 1),
    date '2026-01-16', 10, 'EUR',
    'e6000000-0000-0000-0000-000000000040', 'e7000000-0000-0000-0000-000000000040'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'but not to book'
);
select is(
  (select public.create_finance_account(
    'e1000000-0000-0000-0000-000000000001', '9000', 'Verboten', 'expense',
    'e6000000-0000-0000-0000-000000000041', 'e7000000-0000-0000-0000-000000000041'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'nor to open an account'
);
select pg_temp.as_postgres();

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

select ok(
  (select count(*) >= 3
   from public.audit_events
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and entity_type = 'finance_ledger_entry'),
  'every booking left an audit record'
);
select is(
  (select count(*)::integer
   from public.audit_events
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and entity_type = 'finance_period'
     and action = 'transition'),
  3,
  'and so did every close and reopen that actually happened'
);
select ok(
  (select bool_and(event.reason is not null)
   from public.audit_events as event
   where event.workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and event.entity_type = 'finance_period'
     and event.action = 'transition'
     and (event.new_values ->> 'status') = 'open'),
  'a reopen carries the operator''s reason into the trail, which is the whole '
  'point of demanding one'
);

select * from finish();

rollback;
