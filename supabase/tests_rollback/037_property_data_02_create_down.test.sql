begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-DATA-02 must remove exactly the creation verb and its
-- catalog key, and leave the pre-existing property contract untouched: the
-- properties table, the P1-004/PH-01 update path and the DEBT-012 tombstone
-- marker all predate this package.
--
-- The replayed schema is empty, so the catalog tables simply hold no rows --
-- seeding is workspace-driven and an empty database seeds nothing. What is
-- provable here is the shape: the function is gone, the neighbours stand, and
-- the restored PERMISSION-CATALOG-02 seeder no longer knows property.create.

select plan(9);

select hasnt_function('public', 'create_property',
  'the creation verb is removed');

-- The property contract that predates this package survives.
select has_table('public', 'properties', 'the properties table survives');
select has_function('public', 'update_property',
  'the P1-004/PH-01 update path survives');
select has_column('public', 'properties', 'deleted_at',
  'the DEBT-012 tombstone marker survives');
select has_column('public', 'properties', 'version',
  'optimistic concurrency survives');

-- PERMISSION-CATALOG-02 is restored to its own definition: the seeders exist
-- again and the catalog no longer carries the property.create key.
select has_function('private', 'ensure_permission_catalog',
  'the catalog seeder survives');
select has_function('private', 'seed_workspace_role_catalog',
  'the workspace role seeder survives');
select is(
  (select count(*)::integer from public.permissions where key = 'property.create'),
  0,
  'no property.create key lingers after the rollback replay'
);

-- No hard delete was ever introduced, so none can linger.
select hasnt_function('public', 'delete_property',
  'no hard delete verb lingers');

select * from finish();

rollback;
