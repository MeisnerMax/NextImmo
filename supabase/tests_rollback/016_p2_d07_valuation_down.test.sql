begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- The P2-D07 valuation aggregate is removed by the down path…
select hasnt_table('public', 'valuation_cases', 'valuation_cases is removed by the down path');
select hasnt_table('public', 'valuation_factors', 'valuation_factors is removed by the down path');
select hasnt_table(
  'public', 'valuation_method_results',
  'valuation_method_results is removed by the down path'
);
select hasnt_table(
  'public', 'market_value_opinions',
  'market_value_opinions is removed by the down path'
);

select is(
  (select count(*)::integer from pg_type t
   join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public'
     and t.typname in (
       'valuation_case_kind', 'valuation_case_status', 'valuation_factor_provenance',
       'valuation_confidence_band', 'valuation_method_kind', 'valuation_dcf_terminal'
     )),
  0,
  'every valuation enum is removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'create_valuation_case', 'update_valuation_case', 'upsert_valuation_factors',
       'transition_valuation_case_status', 'publish_valuation_report',
       'upsert_valuation_reference_data'
     )),
  0,
  'every valuation RPC is removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'valuation_command_gate', 'claim_valuation_mutation',
       'finish_valuation_mutation', 'valuation_case_snapshot',
       'valuation_case_detail', 'valuation_status_can_transition',
       'apply_valuation_factors'
     )),
  0,
  'the valuation private helpers are removed'
);

-- …while the aggregates it builds on survive.
select has_table(
  'public', 'properties',
  'the P1-004 property aggregate survives the valuation rollback'
);

select * from finish();

rollback;
