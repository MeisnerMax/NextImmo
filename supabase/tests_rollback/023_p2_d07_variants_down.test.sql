begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- Rolling back the variant step removes the grouping and its command…
select hasnt_column(
  'public', 'valuation_cases', 'variant_group_id',
  'the variant group column is removed by the down path'
);
select hasnt_column(
  'public', 'valuation_cases', 'variant_label',
  'the variant label column is removed by the down path'
);
select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_valuation_variant'),
  0,
  'the variant RPC is removed'
);

-- …while the valuation aggregate it extends survives.
select has_table(
  'public', 'valuation_cases',
  'the valuation aggregate survives the variant rollback'
);

select * from finish();

rollback;
