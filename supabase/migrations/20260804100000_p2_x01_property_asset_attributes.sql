-- P2-X01-AP4: asset attributes required for the legacy property cutover.
--
-- The AP4 data cutover reconciles the local SQLite core into the Supabase
-- workspace. A read-only comparison of the source against the P1-004 property
-- contract showed that 19 of 20 source rows carry at least one asset attribute
-- that has no target column, so the deterministic dry-run rejected them as
-- `mapping.unmapped_field` rather than silently dropping real data. Migrating
-- would therefore either lose owner, purchase and area facts or produce an
-- empty workspace presented as a completed cutover.
--
-- This migration closes that gap additively. It only adds nullable columns to
-- `public.properties`; it does not touch the P1-004 mutation core, the
-- optimistic-versioning contract, the tombstone semantics of DEBT-012, or any
-- existing constraint. Row-level security is unchanged: the table policies are
-- row-scoped and the grants are table-wide, so the new columns inherit
-- `property.read` gating and the default-deny posture without new policies.
--
-- The columns are descriptive asset master data, deliberately not reachable
-- through `public.update_property`: that RPC keeps its explicit P1-004 change
-- set, so this migration adds no new client-writable surface. They are
-- populated by the AP4 bootstrap/import path and read by the property screens.

alter table public.properties
  add column land_area numeric,
  add column residential_area numeric,
  add column commercial_area numeric,
  add column parking_spots integer,
  add column owner_company text,
  add column purchase_date timestamptz,
  add column purchase_price numeric,
  add column notary text,
  add column seller text,
  add column land_registry_details text,
  add column parcel text,
  add column energy_certificate text,
  add column insurance_details text,
  add column tax_assignment text;

-- Areas and money are non-negative and must never be NaN, matching the
-- existing `properties_sqft_check` shape. Zero is allowed (an asset can
-- genuinely have no commercial area); negative values are not.
alter table public.properties
  add constraint properties_land_area_check check (
    land_area is null or (land_area >= 0 and land_area <> 'NaN'::numeric)
  ),
  add constraint properties_residential_area_check check (
    residential_area is null
    or (residential_area >= 0 and residential_area <> 'NaN'::numeric)
  ),
  add constraint properties_commercial_area_check check (
    commercial_area is null
    or (commercial_area >= 0 and commercial_area <> 'NaN'::numeric)
  ),
  add constraint properties_parking_spots_check check (
    parking_spots is null or parking_spots >= 0
  ),
  add constraint properties_purchase_price_check check (
    purchase_price is null
    or (purchase_price >= 0 and purchase_price <> 'NaN'::numeric)
  );

-- Free-text master data uses the same bounded-text shape as the P1-004
-- columns: null or a non-empty, length-bounded value. This rejects the
-- whitespace-only strings the legacy core allows, which is why the dry-run
-- mapper trims and maps empty text to null before the import.
alter table public.properties
  add constraint properties_owner_company_check check (
    owner_company is null
    or char_length(btrim(owner_company)) between 1 and 200
  ),
  add constraint properties_notary_check check (
    notary is null or char_length(btrim(notary)) between 1 and 200
  ),
  add constraint properties_seller_check check (
    seller is null or char_length(btrim(seller)) between 1 and 200
  ),
  add constraint properties_land_registry_details_check check (
    land_registry_details is null
    or char_length(land_registry_details) between 1 and 10000
  ),
  add constraint properties_parcel_check check (
    parcel is null or char_length(btrim(parcel)) between 1 and 200
  ),
  add constraint properties_energy_certificate_check check (
    energy_certificate is null
    or char_length(energy_certificate) between 1 and 10000
  ),
  add constraint properties_insurance_details_check check (
    insurance_details is null
    or char_length(insurance_details) between 1 and 10000
  ),
  add constraint properties_tax_assignment_check check (
    tax_assignment is null
    or char_length(tax_assignment) between 1 and 10000
  );

comment on column public.properties.land_area is
  'Plot area in square metres. Legacy source column land_area.';
comment on column public.properties.residential_area is
  'Residential floor area in square metres. Legacy source column '
  'residential_area.';
comment on column public.properties.commercial_area is
  'Commercial floor area in square metres. Legacy source column '
  'commercial_area.';
comment on column public.properties.parking_spots is
  'Number of parking spaces belonging to the asset.';
comment on column public.properties.owner_company is
  'Legal owner entity of the asset as recorded in the legacy core.';
comment on column public.properties.purchase_date is
  'Acquisition date. Migrated from the legacy epoch-millis column, so it is '
  'stored as timestamptz to stay lossless rather than truncated to a date.';
comment on column public.properties.purchase_price is
  'Acquisition price in the workspace currency.';
comment on column public.properties.notary is
  'Notary of the acquisition transaction.';
comment on column public.properties.seller is
  'Seller of the acquisition transaction.';
comment on column public.properties.land_registry_details is
  'Land registry reference details (Grundbuch).';
comment on column public.properties.parcel is
  'Cadastral parcel reference (Flurstueck).';
comment on column public.properties.energy_certificate is
  'Energy performance certificate details.';
comment on column public.properties.insurance_details is
  'Insurance policy details for the asset.';
comment on column public.properties.tax_assignment is
  'Tax assignment / tax office reference for the asset.';
