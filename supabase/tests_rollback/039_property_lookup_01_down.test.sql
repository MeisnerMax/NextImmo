begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-LOOKUP-01 removes one generated column and its index.
--
-- The package deliberately added no read path, so the interesting part of this
-- rollback is what it must NOT have taken with it: the property row, its
-- policy, and every column the search text was derived from. A rollback that
-- quietly dropped `address_line2` along with the column that concatenates it
-- would be a data loss disguised as a revert.

select plan(11);

select hasnt_column(
  'public', 'properties', 'search_text',
  'the search column is removed'
);
select is(
  (select count(*)::integer
   from pg_indexes
   where schemaname = 'public'
     and tablename = 'properties'
     and indexname = 'properties_search_text_trgm_idx'),
  0,
  'and so is its index'
);

-- The source columns predate this package and must survive it.
select has_column('public', 'properties', 'name', 'name survives');
select has_column('public', 'properties', 'address_line1', 'address_line1 survives');
select has_column('public', 'properties', 'address_line2', 'address_line2 survives');
select has_column('public', 'properties', 'zip', 'zip survives');
select has_column('public', 'properties', 'city', 'city survives');

-- So does the policy the search was filtering, unchanged.
select is(
  (select array_agg(policy.policyname::text order by policy.policyname)
   from pg_policies as policy
   where policy.schemaname = 'public'
     and policy.tablename = 'properties'
     and policy.cmd = 'SELECT'),
  array['properties_select_property_read'],
  'the one read policy is untouched'
);
select ok(
  (select count(*) > 0
   from pg_policies
   where schemaname = 'public'
     and tablename = 'properties'
     and policyname = 'properties_select_property_read'
     and qual like '%has_scoped_entity_permission%'),
  'and still routes through the scoped permission check'
);

-- No permission and no function was ever introduced, so none can linger.
select is(
  (select count(*)::integer from public.permissions
   where key in ('property.search', 'property.lookup')),
  0,
  'no search-specific permission was ever introduced'
);
select hasnt_function(
  'public', 'search_properties',
  'no search function was ever introduced: the search is a filter'
);

select * from finish();

rollback;
