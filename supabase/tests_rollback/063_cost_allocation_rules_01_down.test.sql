begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back COST-ALLOCATION-RULES-01 (P-2a).
--
-- The satellite was chosen over new columns on `finance_accounts` partly for
-- this moment: a table drops cleanly, and a column added to a live table does
-- not. So the assertions are mostly about the account tree still standing.
--
-- The enum gets its own check. A type left behind blocks the next forward
-- replay with "type already exists", which turns a revert into a wedge.

select plan(6);

select hasnt_table('public', 'finance_account_allocation_rules',
  'the rule satellite is gone');

select ok(
  (select count(*) = 0 from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname = 'cost_settlement_principle'),
  'and the settlement principle enum with it -- a type left behind blocks the '
  'next forward replay');

select hasnt_function('public', 'cost_allocation_rules', 'the read is gone');
select hasnt_function('public', 'set_cost_allocation_rule', 'and the write');

select has_table('public', 'finance_accounts',
  'the account tree stays. P2-D08 owns it, and this package only hung an '
  'attribute off it -- which is exactly why the attribute is a satellite and '
  'not a column');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.proname like '%allocation_rule%'),
  0,
  'and nothing allocation-shaped is left behind under another name');

select * from finish();
rollback;
