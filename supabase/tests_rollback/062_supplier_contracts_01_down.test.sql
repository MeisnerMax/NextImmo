begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back SUPPLIER-CONTRACTS-01 (P-3).
--
-- A table and four functions, all created here, so the revert is the clean
-- kind. The assertions that matter are about what it must not take with it.
--
-- This package points at `public.parties` and `public.properties` and reuses
-- P2-D02's mutation plumbing. None of that is its property: reverting it must
-- leave the supplier directory, the properties and every other party command
-- exactly as they were, because a framework contract is a thing *about* a
-- supplier and not the supplier itself.

select plan(8);

select hasnt_table('public', 'supplier_contracts', 'the contract table is gone');

select hasnt_function('public', 'supplier_contracts_as_of', 'the read is gone');
select hasnt_function('public', 'create_supplier_contract', 'as is create');
select hasnt_function('public', 'update_supplier_contract', 'and update');
select hasnt_function('public', 'end_supplier_contract', 'and end');

select has_table('public', 'parties',
  'the supplier directory stays. A contract is a thing about a supplier, not '
  'the supplier -- and P2-D02 owns the party');

select has_function('private', 'claim_party_mutation',
  'and the shared mutation plumbing stays: reused here with the '
  'supplier_contract entity type, created by P2-D02');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.proname like '%supplier_contract%'),
  0,
  'and nothing contract-shaped is left behind under another name -- including '
  'the private deadline helper, which is this package''s and has no other '
  'caller');

select * from finish();
rollback;
