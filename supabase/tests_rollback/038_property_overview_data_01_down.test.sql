begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-OVERVIEW-DATA-01 removes exactly one read function.
-- The package adds no table, no column, no policy and no permission, so there
-- is nothing else it could leave behind -- and every source it reads from
-- predates it and must survive untouched.

select plan(9);

select hasnt_function('public', 'property_overview',
  'the overview read is removed');

-- Every source table the read used predates this package.
select has_table('public', 'properties', 'properties survives');
select has_table('public', 'units', 'units survives');
select has_table('public', 'leases', 'leases survives');
select has_table('public', 'maintenance_tickets', 'maintenance_tickets survives');
select has_table('public', 'capex_projects', 'capex_projects survives');
select has_table('public', 'tasks', 'tasks survives');
select has_table('public', 'required_documents', 'required_documents survives');

-- The package introduced no permission of its own, so none can linger.
select is(
  (select count(*)::integer from public.permissions
   where key in ('property.overview', 'overview.read')),
  0,
  'no overview-specific permission was ever introduced'
);

select * from finish();

rollback;
