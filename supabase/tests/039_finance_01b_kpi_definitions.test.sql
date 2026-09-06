begin;

create extension if not exists pgtap with schema extensions;

-- FINANCE-01b: versioned KPI definitions and the figures computed from them.
--
-- The assertions concentrate on the three properties the whole package exists
-- for:
--
--   * a definition is immutable, so a figure published under it stays
--     reproducible — the lines cannot be edited, only superseded;
--   * exactly one version of a key is active, so "the current definition of
--     NOI" always has an answer;
--   * a computed value carries its definition version, is per currency, and
--     says whether the periods behind it are final.

select plan(48);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'finance_kpi_definitions', 'definitions exist');
select has_table('public', 'finance_kpi_definition_lines', 'their lines exist');

select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'public'
     and tablename in (
       'finance_kpi_definitions', 'finance_kpi_definition_lines'
     )
     and cmd <> 'SELECT'),
  0,
  'no write policy: every mutation goes through an audited RPC'
);

select ok(
  (select indexdef like '%WHERE (status = %active%'
   from pg_indexes
   where schemaname = 'public'
     and indexname = 'finance_kpi_definitions_single_active_idx'),
  'the single-active rule is a partial unique index, not a convention'
);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('f2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kpi-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kpi-booker@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'kpi-a', 'KPI A');

select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000001');

-- A role that may book but not define: the separation this package rests on.
insert into public.roles (id, workspace_id, key, name) values (
  'f3000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'kpi_booker', 'Booker without definition rights'
);
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'f1000000-0000-0000-0000-000000000001',
       'f3000000-0000-0000-0000-000000000001', permission.id
from public.permissions as permission
where permission.key in ('property.read', 'finance.read', 'finance.manage');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'f1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('f4000000-0000-0000-0000-000000000001'::uuid, 'f2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('f4000000-0000-0000-0000-000000000002'::uuid, 'f2000000-0000-0000-0000-000000000002'::uuid, 'kpi_booker')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'Kennzahlenhaus', 'Formelweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   '4000', 'Mieterträge', 'income',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f6000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   '5000', 'Betriebskosten', 'expense',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  -- An expense the operator wants excluded from NOI. It is the reason account
  -- lines exist alongside class lines.
  ('f6000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001',
   '5900', 'Sonderaufwand', 'expense',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

insert into public.finance_periods (
  id, workspace_id, fiscal_year, period_month, created_by, updated_by
) values
  ('f7000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   2026, 1, 'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f7000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   2026, 2, 'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

insert into public.finance_ledger_entries (
  workspace_id, property_id, account_id, period_id, booked_on, amount,
  currency_code, created_by, updated_by
) values
  -- January, EUR: 1000 income, 250 ordinary expense, 100 special expense.
  ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
   'f6000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001',
   date '2026-01-10', 1000, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
   'f6000000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000001',
   date '2026-01-20', 250, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
   'f6000000-0000-0000-0000-000000000003', 'f7000000-0000-0000-0000-000000000001',
   date '2026-01-25', 100, 'EUR',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  -- February, CHF: a second currency on the same accounts.
  ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
   'f6000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000002',
   date '2026-02-10', 900, 'CHF',
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

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

-- Reads the KPIs as `p_user` and then restores the session the caller had.
--
-- The obvious implementation resets to postgres afterwards, which silently
-- unauthenticates every RPC in the rest of the file: the next command sees no
-- `auth.uid()` and answers `forbidden`, which looks like a permission bug in
-- the product rather than a bug in the test.
create or replace function pg_temp.kpis(
  p_user uuid default 'f2000000-0000-0000-0000-000000000001',
  p_aal text default 'aal2'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_role text := current_setting('role', true);
begin
  perform pg_temp.as_user(p_user, p_aal);
  v_result := public.property_finance_kpis(
    'f1000000-0000-0000-0000-000000000001',
    'f5000000-0000-0000-0000-000000000001'
  );
  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('role', coalesce(nullif(v_role, 'none'), 'postgres'), true);
  return v_result;
end;
$$;

create or replace function pg_temp.value_of(p_key text, p_currency text)
returns numeric
language sql
as $$
  select (entry ->> 'value')::numeric
  from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry
  where entry ->> 'kpi_key' = p_key
    and entry ->> 'currency_code' = p_currency;
$$;

-- ---------------------------------------------------------------------------
-- Nothing defined: the honest empty answer
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(pg_temp.kpis() -> 'values')),
  0,
  'with no definitions there are no figures'
);
select is(
  (select (pg_temp.kpis() ->> 'active_definitions')::integer),
  0,
  'and the payload says so, so a surface can tell "nothing defined" from '
  '"defined but nothing matched"'
);

-- ---------------------------------------------------------------------------
-- Permission separation
-- ---------------------------------------------------------------------------

select pg_temp.as_user('f2000000-0000-0000-0000-000000000002');
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    '[{"account_type": "income", "effect": "add"}]'::jsonb,
    'f8000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000001'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'finance.manage books figures but does not decide what they mean'
);

select pg_temp.as_user('f2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Creating a definition
-- ---------------------------------------------------------------------------

select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    '[]'::jsonb,
    'f8000000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000002'
  ) -> 'error' ->> 'field'),
  'lines',
  'a definition without lines computes nothing and is refused'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    '[{"account_type": "income", "account_id": "f6000000-0000-0000-0000-000000000001", "effect": "add"}]'::jsonb,
    'f8000000-0000-0000-0000-000000000003', 'f9000000-0000-0000-0000-000000000003'
  ) -> 'error' ->> 'field'),
  'lines',
  'a line names an account or a class, never both'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    '[{"account_type": "income", "effect": "weighted"}]'::jsonb,
    'f8000000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000004'
  ) -> 'error' ->> 'field'),
  'lines',
  'a line adds, subtracts or excludes — there is no weight'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'NOI', 'Net Operating Income',
    '[{"account_type": "income", "effect": "add"}]'::jsonb,
    'f8000000-0000-0000-0000-000000000005', 'f9000000-0000-0000-0000-000000000005'
  ) -> 'error' ->> 'field'),
  'kpi_key',
  'an upper-case key is refused rather than silently lower-cased'
);


select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    ('[{"account_type": "expense", "effect": "add"},'
     '{"account_type": "expense", "effect": "subtract"}]')::jsonb,
    'f8000000-0000-0000-0000-00000000000a', 'f9000000-0000-0000-0000-00000000000a'
  ) -> 'error' ->> 'field'),
  'lines',
  'a class named twice would contradict itself, and "the account line wins" '
  'would have no single answer'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    ('[{"account_id": "f6000000-0000-0000-0000-000000000003", "effect": "add"},'
     '{"account_id": "f6000000-0000-0000-0000-000000000003", "effect": "exclude"}]')::jsonb,
    'f8000000-0000-0000-0000-00000000000b', 'f9000000-0000-0000-0000-00000000000b'
  ) -> 'error' ->> 'field'),
  'lines',
  'and so would an account named twice'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    ('[{"account_type": "income", "effect": "add"},'
     '{"account_type": "expense", "effect": "subtract"}]')::jsonb,
    'f8000000-0000-0000-0000-000000000007', 'f9000000-0000-0000-0000-000000000007'
  ) -> 'entity' ->> 'definition_version'),
  '1',
  'the first definition of a key is version 1'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'Net Operating Income',
    ('[{"account_type": "income", "effect": "add"},'
     '{"account_type": "expense", "effect": "subtract"}]')::jsonb,
    'f8000000-0000-0000-0000-000000000007', 'f9000000-0000-0000-0000-000000000007'
  ) -> 'entity' ->> 'definition_version'),
  '1',
  'and a retry replays it instead of minting version 2'
);
select is(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'noi', 'NOI ohne Sonderaufwand',
    ('[{"account_type": "income", "effect": "add"},'
     '{"account_type": "expense", "effect": "subtract"},'
     '{"account_id": "f6000000-0000-0000-0000-000000000003", "effect": "exclude"}]')::jsonb,
    'f8000000-0000-0000-0000-000000000008', 'f9000000-0000-0000-0000-000000000008'
  ) -> 'entity' ->> 'definition_version'),
  '2',
  'a revised meaning is a new version, never an edit'
);
select is(
  (select status::text from public.finance_kpi_definitions
   where kpi_key = 'noi' and definition_version = 1),
  'draft',
  'a new definition starts as a draft: creating it is not adopting it'
);

-- ---------------------------------------------------------------------------
-- Immutability
-- ---------------------------------------------------------------------------

select pg_temp.as_postgres();
select throws_ok(
  $$update public.finance_kpi_definition_lines set effect = 'add'
    where definition_id = (
      select id from public.finance_kpi_definitions
      where kpi_key = 'noi' and definition_version = 1
    )$$,
  '23514',
  null,
  'a definition line cannot be edited, even by a direct writer'
);
select throws_ok(
  $$delete from public.finance_kpi_definition_lines
    where definition_id = (
      select id from public.finance_kpi_definitions
      where kpi_key = 'noi' and definition_version = 1
    )$$,
  '23514',
  null,
  'nor removed'
);
select pg_temp.as_user('f2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Activation
-- ---------------------------------------------------------------------------

select is(
  (select public.activate_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 1),
    1, 'f8000000-0000-0000-0000-000000000010', 'f9000000-0000-0000-0000-000000000010'
  ) -> 'entity' ->> 'status'),
  'active',
  'a draft version can be adopted'
);
select ok(
  (select (definition.activated_at is not null and definition.activated_by is not null)
   from public.finance_kpi_definitions as definition
   where definition.kpi_key = 'noi' and definition.definition_version = 1),
  'and the adoption marker travels with the status'
);
select is(
  (select public.activate_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 1),
    (select version from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 1),
    'f8000000-0000-0000-0000-000000000011', 'f9000000-0000-0000-0000-000000000011'
  ) -> 'error' ->> 'code'),
  'validation_failed',
  'adopting the version that is already adopted is a mistake worth reporting'
);

-- ---------------------------------------------------------------------------
-- The computation, under version 1
-- ---------------------------------------------------------------------------

select is(
  pg_temp.value_of('noi', 'EUR'),
  650::numeric,
  'version 1: 1000 income minus 350 of expense, both classes, one currency'
);
select is(
  pg_temp.value_of('noi', 'CHF'),
  900::numeric,
  'the CHF bookings are their own figure, never converted'
);
select is(
  (select jsonb_array_length(pg_temp.kpis() -> 'values')),
  2,
  'two currencies, two rows — and no third row totalling them'
);
select is(
  (select entry ->> 'definition_version'
   from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry
   where entry ->> 'currency_code' = 'EUR'),
  '1',
  'every figure names the definition version it was computed under'
);
select ok(
  (select bool_and(entry ? 'kpi_key' and entry ? 'name')
   from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry),
  'and the key and the human name it was published as'
);
select ok(
  (select (pg_temp.kpis() -> 'is_provisional')::boolean),
  'both periods are open, so the figures are provisional'
);

-- ---------------------------------------------------------------------------
-- Switching versions changes the figure, and says which one produced it
-- ---------------------------------------------------------------------------

select is(
  (select public.activate_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 2),
    1, 'f8000000-0000-0000-0000-000000000012', 'f9000000-0000-0000-0000-000000000012'
  ) -> 'entity' ->> 'status'),
  'active',
  'version 2 can be adopted in its turn'
);
select is(
  (select status::text from public.finance_kpi_definitions
   where kpi_key = 'noi' and definition_version = 1),
  'retired',
  'and the previous version is retired in the same breath'
);
select is(
  (select count(*)::integer from public.finance_kpi_definitions
   where kpi_key = 'noi'
     and status = 'active'::public.finance_kpi_status),
  1,
  'exactly one version of a key is ever active'
);
select ok(
  (select definition.id is not null
   from public.finance_kpi_definitions as definition
   where definition.kpi_key = 'noi' and definition.definition_version = 1),
  'the retired version stays readable: a figure published under it must stay '
  'explicable'
);
select is(
  (select public.activate_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 1),
    (select version from public.finance_kpi_definitions
     where kpi_key = 'noi' and definition_version = 1),
    'f8000000-0000-0000-0000-000000000013', 'f9000000-0000-0000-0000-000000000013'
  ) -> 'error' ->> 'code'),
  'dependency_conflict',
  'a retired version is not reactivated; a new version is created instead'
);

select is(
  pg_temp.value_of('noi', 'EUR'),
  750::numeric,
  'version 2 excludes the special expense: the account line governs the entry '
  'its class line would otherwise have caught'
);
select is(
  (select entry ->> 'definition_version'
   from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry
   where entry ->> 'currency_code' = 'EUR'),
  '2',
  'and the figure now names version 2'
);
select is(
  (select (entry ->> 'entries')::integer
   from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry
   where entry ->> 'currency_code' = 'EUR'),
  2,
  'and the excluded entry is not counted among the entries behind the figure: '
  'it is not part of it'
);

-- ---------------------------------------------------------------------------
-- A definition that matches nothing
-- ---------------------------------------------------------------------------

select ok(
  (select public.create_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001', 'equity.ratio', 'Eigenkapitalquote',
    '[{"account_type": "equity", "effect": "add"}]'::jsonb,
    'f8000000-0000-0000-0000-000000000014', 'f9000000-0000-0000-0000-000000000014'
  ) ->> 'ok' = 'true'),
  'a definition over an unused account class is legitimate'
);
select ok(
  (select public.activate_finance_kpi_definition(
    'f1000000-0000-0000-0000-000000000001',
    (select id from public.finance_kpi_definitions where kpi_key = 'equity.ratio'),
    1, 'f8000000-0000-0000-0000-000000000015', 'f9000000-0000-0000-0000-000000000015'
  ) ->> 'ok' = 'true'),
  'and can be adopted'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.kpis() -> 'values') as entry
   where entry ->> 'kpi_key' = 'equity.ratio'),
  0,
  'it yields no row rather than a zero: nothing was booked to it'
);
select is(
  (select (pg_temp.kpis() ->> 'active_definitions')::integer),
  2,
  'but the active count still reports it, so "defined and unmatched" is '
  'distinguishable from "undefined"'
);

-- ---------------------------------------------------------------------------
-- Closing a period settles the figures
-- ---------------------------------------------------------------------------

select ok(
  (select public.transition_finance_period_status(
    'f1000000-0000-0000-0000-000000000001',
    'f7000000-0000-0000-0000-000000000001', 'closed', 1,
    'f8000000-0000-0000-0000-000000000016', 'f9000000-0000-0000-0000-000000000016'
  ) ->> 'ok' = 'true'),
  'January closes'
);
select ok(
  (select (pg_temp.kpis() -> 'is_provisional')::boolean),
  'February is still open, so the figures stay provisional'
);
select ok(
  (select public.transition_finance_period_status(
    'f1000000-0000-0000-0000-000000000001',
    'f7000000-0000-0000-0000-000000000002', 'closed', 1,
    'f8000000-0000-0000-0000-000000000017', 'f9000000-0000-0000-0000-000000000017'
  ) ->> 'ok' = 'true'),
  'February closes too'
);
select ok(
  (select not (pg_temp.kpis() -> 'is_provisional')::boolean),
  'and only then do the figures stop being provisional'
);

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select pg_temp.as_postgres();
select is(
  (select public.property_finance_kpis(
    'f1000000-0000-0000-0000-000000000001',
    'f5000000-0000-0000-0000-000000000001'
  ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.kpis('f2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

select ok(
  (select count(*) >= 3
   from public.audit_events
   where workspace_id = 'f1000000-0000-0000-0000-000000000001'
     and entity_type = 'finance_kpi_definition'),
  'every definition and every adoption left an audit record'
);
select ok(
  (select (event.new_values -> 'lines') is not null
   from public.audit_events as event
   where event.workspace_id = 'f1000000-0000-0000-0000-000000000001'
     and event.entity_type = 'finance_kpi_definition'
     and event.action = 'create'
   limit 1),
  'and the audited snapshot carries the lines, so the meaning of a figure is '
  'recoverable from the trail alone'
);

select * from finish();

rollback;
