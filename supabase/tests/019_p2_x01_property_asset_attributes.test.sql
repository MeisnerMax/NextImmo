begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

-- =============================================================================
-- P2-X01-AP4: the asset attributes required for the legacy property cutover.
-- Asserts that the 14 columns exist with lossless types, that the value
-- constraints reject the shapes the legacy core tolerates, and that the
-- addition stays additive: unchanged RLS posture, unchanged table grants, and
-- an unchanged P1-004 mutation core.
-- =============================================================================

-- === Column surface ===================================================

select has_column('public', 'properties', 'land_area', 'land_area exists');
select has_column('public', 'properties', 'residential_area', 'residential_area exists');
select has_column('public', 'properties', 'commercial_area', 'commercial_area exists');
select has_column('public', 'properties', 'parking_spots', 'parking_spots exists');
select has_column('public', 'properties', 'owner_company', 'owner_company exists');
select has_column('public', 'properties', 'purchase_date', 'purchase_date exists');
select has_column('public', 'properties', 'purchase_price', 'purchase_price exists');
select has_column('public', 'properties', 'notary', 'notary exists');
select has_column('public', 'properties', 'seller', 'seller exists');
select has_column('public', 'properties', 'land_registry_details', 'land_registry_details exists');
select has_column('public', 'properties', 'parcel', 'parcel exists');
select has_column('public', 'properties', 'energy_certificate', 'energy_certificate exists');
select has_column('public', 'properties', 'insurance_details', 'insurance_details exists');
select has_column('public', 'properties', 'tax_assignment', 'tax_assignment exists');

-- Types are chosen to be lossless against the legacy source: REAL to numeric,
-- INTEGER to integer, epoch-millis to timestamptz rather than a truncated date.

select col_type_is('public', 'properties', 'land_area', 'numeric', 'land_area is numeric');
select col_type_is('public', 'properties', 'residential_area', 'numeric', 'residential_area is numeric');
select col_type_is('public', 'properties', 'commercial_area', 'numeric', 'commercial_area is numeric');
select col_type_is('public', 'properties', 'parking_spots', 'integer', 'parking_spots is integer');
select col_type_is('public', 'properties', 'owner_company', 'text', 'owner_company is text');
select col_type_is('public', 'properties', 'purchase_date', 'timestamp with time zone', 'purchase_date keeps the source time component');
select col_type_is('public', 'properties', 'purchase_price', 'numeric', 'purchase_price is numeric');
select col_type_is('public', 'properties', 'notary', 'text', 'notary is text');
select col_type_is('public', 'properties', 'seller', 'text', 'seller is text');
select col_type_is('public', 'properties', 'land_registry_details', 'text', 'land_registry_details is text');
select col_type_is('public', 'properties', 'parcel', 'text', 'parcel is text');
select col_type_is('public', 'properties', 'energy_certificate', 'text', 'energy_certificate is text');
select col_type_is('public', 'properties', 'insurance_details', 'text', 'insurance_details is text');
select col_type_is('public', 'properties', 'tax_assignment', 'text', 'tax_assignment is text');

-- === Fixtures =========================================================

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'asset-attributes', 'Asset Attributes');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country,
  property_type, units, status, created_by, updated_by
) values (
  'e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'Attribute Target', 'Asset Street 1', '10115', 'Berlin', 'de', 'multifamily',
  4, 'active',
  'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001'
);

-- === Value constraints ================================================
-- All 14 columns stay nullable: the cutover must not invent values it does not
-- have, and an unmigrated attribute is null rather than a placeholder.

select lives_ok(
  $$update public.properties
      set land_area = null, residential_area = null, commercial_area = null,
          parking_spots = null, owner_company = null, purchase_date = null,
          purchase_price = null, notary = null, seller = null,
          land_registry_details = null, parcel = null,
          energy_certificate = null, insurance_details = null,
          tax_assignment = null
    where id = 'e7000000-0000-0000-0000-000000000001'$$,
  'every asset attribute is nullable'
);

select lives_ok(
  $$update public.properties
      set land_area = 5050.0, residential_area = 2050.84, commercial_area = 0,
          parking_spots = 12, owner_company = '613 Investment Group GmbH',
          purchase_date = '2024-03-01T00:00:00Z', purchase_price = 1300000.0,
          notary = 'Notariat Mitte', seller = 'Verkaeufer GmbH',
          land_registry_details = 'Blatt 4711', parcel = 'Flur 3, Flurstueck 12',
          energy_certificate = 'B, 78 kWh', insurance_details = 'Police 12345',
          tax_assignment = 'Finanzamt Mitte'
    where id = 'e7000000-0000-0000-0000-000000000001'$$,
  'a fully populated legacy asset row is accepted'
);

select throws_ok(
  $$update public.properties set land_area = -1
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'negative land_area is rejected'
);
select throws_ok(
  $$update public.properties set land_area = 'NaN'::numeric
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'NaN land_area is rejected'
);
select throws_ok(
  $$update public.properties set residential_area = -1
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'negative residential_area is rejected'
);
select throws_ok(
  $$update public.properties set commercial_area = -1
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'negative commercial_area is rejected'
);
select throws_ok(
  $$update public.properties set parking_spots = -1
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'negative parking_spots is rejected'
);
select throws_ok(
  $$update public.properties set purchase_price = -1
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'negative purchase_price is rejected'
);
select throws_ok(
  $$update public.properties set owner_company = '   '
     where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'whitespace-only owner_company is rejected'
);

-- === Unchanged security posture =======================================
-- The columns are added to a table whose policies are row-scoped and whose
-- grants are table-wide, so they must inherit the existing posture rather than
-- open a new surface.

select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.properties'::regclass),
  'row level security stays enabled and forced'
);
select ok(
  has_table_privilege('authenticated', 'public.properties', 'select'),
  'authenticated keeps the P1-004 read grant'
);
select ok(
  not has_table_privilege('authenticated', 'public.properties', 'insert'),
  'authenticated still cannot insert properties directly'
);
select ok(
  not has_table_privilege('anon', 'public.properties', 'select'),
  'anon still cannot read properties'
);

-- The asset attributes are deliberately not client-writable: update_property
-- keeps its P1-004 signature and explicit change set, so this migration adds
-- no new mutation surface.
select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'the P1-004 update RPC is unchanged'
);

select * from finish();

rollback;
