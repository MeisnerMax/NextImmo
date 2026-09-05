begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back FINANCE-01a removes the three finance tables, their types,
-- their commands and their helpers.
--
-- Unlike the read-only packages before it, this rollback destroys data: the
-- chart of accounts, every period and every booking go with it. That is the
-- correct behaviour for a down migration of a table-creating package, and it
-- is the reason the deploy path is a one-way forward push (the rollback proofs
-- live here in CI and never run against staging).
--
-- What the revert must not touch is the permission catalogue *seeder*. It is
-- shared state: PERMISSION-CATALOG-02 owns it, PROPERTY-DATA-02 extended it,
-- and this package extended it again. A revert that dropped the function, or
-- restored a version without `property.create`, would silently un-grant a
-- capability that belongs to a different package.

select plan(14);

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
     'finance_accounts', 'finance_periods', 'finance_ledger_entries'
   ]) as name),
  'the three finance tables are removed'
);

select hasnt_function('public', 'create_finance_account',
  'the account command is removed');
select hasnt_function('public', 'update_finance_account',
  'and its update');
select hasnt_function('public', 'open_finance_period',
  'the period command is removed');
select hasnt_function('public', 'transition_finance_period_status',
  'and its transition');
select hasnt_function('public', 'record_finance_ledger_entry',
  'the booking command is removed');
select hasnt_function('public', 'property_finance_actuals',
  'and the read');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname like 'finance%'),
  0,
  'no private finance helper is left behind'
);
select is(
  (select count(*)::integer
   from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname in (
       'finance_account_type', 'finance_period_status', 'finance_entry_source'
     )),
  0,
  'and no orphaned enum type'
);

-- The shared permission catalogue survives, and survives *correctly*.
select has_function('private', 'ensure_permission_catalog',
  'the shared permission catalogue seeder survives');
select has_function('private', 'seed_workspace_role_catalog',
  'and the shared role seeder');
select is(
  (select count(*)::integer from public.permissions
   where key like 'finance.%'),
  0,
  'the three finance keys are gone from the catalogue'
);
-- Asserted on the function body rather than on seeded rows: an empty database
-- has no permissions at all, but the seeder must still know the key it is
-- supposed to seed. This is the assertion that catches a revert restoring a
-- pre-PROPERTY-DATA-02 catalogue.
select ok(
  (select pg_get_functiondef(function.oid) like '%property.create%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'ensure_permission_catalog'),
  'and the seeder still carries property.create, which belongs to a different '
  'package'
);
select is(
  (select count(*)::integer from public.role_permissions as role_permission
   join public.permissions as permission
     on permission.id = role_permission.permission_id
   where permission.key like 'finance.%'),
  0,
  'and no finance grant lingers on any role'
);

select * from finish();

rollback;
