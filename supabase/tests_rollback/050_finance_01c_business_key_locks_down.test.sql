begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back FINANCE-01c restores `create_finance_account` and
-- `open_finance_period` to their FINANCE-01a bodies. It creates and drops
-- nothing.
--
-- That makes this rollback the same unusual shape as PROPERTY-ACTIVITY-02's:
-- there is no object whose absence proves the revert. Both functions must
-- still be there, with the same signatures, the same SECURITY DEFINER
-- property and the same grants -- and without the advisory lock, which means
-- the race this package closed is open again. Asserting that it is open again
-- is the point. A rollback that kept half the change would leave the schema
-- in a state no migration describes.
--
-- What the revert must not touch is anything else that locks. FINANCE-01b
-- locks on `kpi_key` and PROPERTY-MEDIA-DATA-01 locks per property; both
-- predate this package, neither is its property, and a revert that swept up
-- every advisory lock in the schema would silently reopen two more races.
--
-- The unique constraints are the other half of the honesty here. They are
-- FINANCE-01a's and survive in both directions: the lock was never what made
-- the key unique, only what turned a violation into a typed refusal.

select plan(14);

create or replace function pg_temp.body_of(p_schema text, p_name text)
returns text
language sql
as $$
  select function.prosrc
  from pg_proc as function
  join pg_namespace as namespace on namespace.oid = function.pronamespace
  where namespace.nspname = p_schema and function.proname = p_name;
$$;

-- The two functions survive the revert -- this package replaced them, never
-- created them.
select has_function('public', 'create_finance_account',
  'the account command survives: FINANCE-01a owns it');
select has_function('public', 'open_finance_period',
  'and the period command');

-- And they are back to checking the business key without holding it.
select is(
  (select strpos(pg_temp.body_of('public', 'create_finance_account'),
                 'pg_advisory_xact_lock')),
  0,
  'the account command no longer locks the code: the revert really did put '
  'the FINANCE-01a body back'
);
select is(
  (select strpos(pg_temp.body_of('public', 'open_finance_period'),
                 'pg_advisory_xact_lock')),
  0,
  'and the period command no longer locks the month'
);

-- The duplicate check itself is FINANCE-01a's and stays in both directions.
-- Without it a revert would not merely reopen the race, it would let a
-- duplicate through on a quiet system too.
select is(
  (select strpos(pg_temp.body_of('public', 'create_finance_account'),
                 'An account with this code already exists') > 0),
  true,
  'the typed duplicate refusal is FINANCE-01a''s and survives the revert'
);
select is(
  (select strpos(pg_temp.body_of('public', 'open_finance_period'),
                 'That period already exists') > 0),
  true,
  'as does the period''s'
);

-- Every other advisory lock in the schema belongs to another package.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'create_finance_kpi_definition', 'activate_finance_kpi_definition'
     )
     and strpos(function.prosrc, 'pg_advisory_xact_lock') > 0),
  2,
  'FINANCE-01b still locks on kpi_key: reverting this package is not '
  'reverting that one'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and strpos(function.prosrc, 'pg_advisory_xact_lock') > 0),
  4,
  'and exactly four public commands still lock -- the two kpi commands and '
  'the two property media paths that claim the cover'
);

-- The constraints the lock was protecting are untouched by either direction.
select col_is_unique('public', 'finance_accounts', array['workspace_id', 'code'],
  'the account code is still unique per workspace');
select col_is_unique('public', 'finance_periods',
  array['workspace_id', 'fiscal_year', 'period_month'],
  'and a fiscal month still exists at most once');

-- Signature, security property and grants are the same on both sides.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in ('create_finance_account', 'open_finance_period')
     and function.prosecdef),
  2,
  'both are still SECURITY DEFINER');
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname in ('create_finance_account', 'open_finance_period')
     and acl.grantee = 'anon'::regrole),
  0,
  'and anon still cannot call either');

-- The ledger this package only ever locked around is FINANCE-01a's and
-- outlives a revert of the locking.
select has_table('public', 'finance_accounts',
  'the accounts table survives: this package added no storage');
select has_table('public', 'finance_periods',
  'as does the periods table');

select * from finish();

rollback;
