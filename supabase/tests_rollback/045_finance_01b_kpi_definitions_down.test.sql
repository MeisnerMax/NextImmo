begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back FINANCE-01b removes the definition tables, their two enums, the
-- two commands and the computed read.
--
-- Like every table-creating package this destroys data: the definitions go,
-- and with them the record of what any published figure meant. That is the
-- correct behaviour for a down migration and the reason the deploy path is a
-- one-way forward push.
--
-- What the revert must not touch is FINANCE-01a. The ledger — accounts,
-- periods, bookings — is a different package's property and outlives the
-- opinions computed from it. A revert that took the bookings with the formulas
-- would delete the facts along with the interpretation.

select plan(13);

create or replace function pg_temp.has_public_table(p_name text)
returns boolean
language sql
as $$
  select exists (
    select 1 from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relname = p_name
      and class.relkind = 'r'
  );
$$;

select ok(
  (select not bool_or(pg_temp.has_public_table(name))
   from unnest(array[
     'finance_kpi_definitions', 'finance_kpi_definition_lines'
   ]) as name),
  'the definition tables are removed'
);
select hasnt_function('public', 'create_finance_kpi_definition',
  'the definition command is removed');
select hasnt_function('public', 'activate_finance_kpi_definition',
  'and the activation command');
select hasnt_function('public', 'property_finance_kpis',
  'and the computed read');
select hasnt_function('private', 'finance_kpi_definition_snapshot',
  'and the snapshot helper');
select hasnt_function('private', 'finance_kpi_lines_immutable',
  'and the immutability trigger function');
select is(
  (select count(*)::integer
   from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname in ('finance_kpi_status', 'finance_kpi_line_effect')),
  0,
  'and both enums, with no orphan left behind'
);

-- FINANCE-01a survives whole: the facts outlive the interpretation.
select ok(
  (select bool_and(pg_temp.has_public_table(name))
   from unnest(array[
     'finance_accounts', 'finance_periods', 'finance_ledger_entries'
   ]) as name),
  'the ledger tables survive: a revert of the formulas is not a revert of the '
  'bookings'
);
select has_function('public', 'property_finance_actuals',
  'and the actuals read, which never depended on a definition');
select has_function('public', 'record_finance_ledger_entry',
  'and the booking command');
select has_function('private', 'finance_command_gate',
  'and the shared finance command gate');
select is(
  (select count(*)::integer from public.permissions
   where key in ('finance.read', 'finance.manage', 'finance.close')),
  (select case when exists (select 1 from public.permissions) then 3 else 0 end),
  'the three finance permissions belong to FINANCE-01a and stay'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.proname like '%kpi%'),
  0,
  'nothing named kpi is left behind in either schema'
);

select * from finish();

rollback;
