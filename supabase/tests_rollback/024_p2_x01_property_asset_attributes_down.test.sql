begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- P2-X01-AP4 asset attributes are removed on the down path. The migration is
-- purely additive, so the down path must leave the P1-004 property contract and
-- the DEBT-012 tombstone exactly as they were before it ran.

select hasnt_column('public', 'properties', 'land_area', 'land_area is removed');
select hasnt_column('public', 'properties', 'residential_area', 'residential_area is removed');
select hasnt_column('public', 'properties', 'commercial_area', 'commercial_area is removed');
select hasnt_column('public', 'properties', 'parking_spots', 'parking_spots is removed');
select hasnt_column('public', 'properties', 'owner_company', 'owner_company is removed');
select hasnt_column('public', 'properties', 'purchase_date', 'purchase_date is removed');
select hasnt_column('public', 'properties', 'purchase_price', 'purchase_price is removed');
select hasnt_column('public', 'properties', 'notary', 'notary is removed');
select hasnt_column('public', 'properties', 'seller', 'seller is removed');
select hasnt_column('public', 'properties', 'land_registry_details', 'land_registry_details is removed');
select hasnt_column('public', 'properties', 'parcel', 'parcel is removed');
select hasnt_column('public', 'properties', 'energy_certificate', 'energy_certificate is removed');
select hasnt_column('public', 'properties', 'insurance_details', 'insurance_details is removed');
select hasnt_column('public', 'properties', 'tax_assignment', 'tax_assignment is removed');

-- The contracts underneath remain intact.
select has_table('public', 'properties', 'P1-004 properties remains');
select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-004 update RPC remains'
);
select has_column('public', 'properties', 'deleted_by', 'DEBT-012 tombstone marker remains');
select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.properties'::regclass),
  'row level security remains enabled and forced'
);

select * from finish();

rollback;
