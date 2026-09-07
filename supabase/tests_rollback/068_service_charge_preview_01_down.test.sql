begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back SERVICE-CHARGE-PREVIEW-01.
--
-- This package adds one function and nothing else: no table, no type, no
-- policy, no replaced body. A revert is therefore the easiest kind to get
-- wrong by omission, because "the function is gone" would also be true of a
-- migration that had silently dropped half the schema on the way out.
--
-- So the assertions run in both directions. The preview is gone; the four
-- things it read are still standing; and the public SECURITY DEFINER
-- inventory is back at the number the forward test moved it off. That last
-- one is what catches a revert that took something else with it.

select plan(7);

select hasnt_function(
  'public', 'property_service_charge_preview',
  'the settlement preview is gone');

-- Everything it read, it only read. A settlement that could be computed from
-- these is a later decision; losing any of them here would be this migration
-- reverting somebody else's work.
select has_function(
  'private', 'allocation_basis_resolution',
  'the basis resolution it called still stands');

select has_table('public', 'allocation_keys',
  'the distribution keys it applied are untouched');

select has_table('public', 'finance_ledger_entries',
  'the bookings it distributed are untouched');

select has_table('public', 'finance_account_allocation_rules',
  'and the apportionability rules it classified by');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef),
  109,
  'the public SECURITY DEFINER inventory is back at 109: this package added '
  'exactly one function, and the revert took exactly that one');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'workspace_finance_periods', 'property_finance_ledger_entries',
       'allocation_keys_as_of', 'unit_basis_values_as_of'
     )),
  4,
  'and the four reads a settlement is built on are all still there -- named '
  'individually, because a count alone would be satisfied by four of the '
  'wrong functions');

select * from finish();
rollback;
