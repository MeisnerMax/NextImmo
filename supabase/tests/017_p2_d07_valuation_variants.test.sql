begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- === Schema surface ===================================================

select has_column('public', 'valuation_cases', 'variant_group_id', 'variant group column exists');
select has_column('public', 'valuation_cases', 'variant_label', 'variant label column exists');
select has_function(
  'public',
  'create_valuation_variant',
  array['uuid', 'uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'text']
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'create_valuation_variant'
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute the variant RPC'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d07v-manager@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'p2d07v-workspace', 'P2D07 Variants');

insert into public.roles (id, workspace_id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager');

insert into public.permissions (id, key, name) values
  ('d5000000-0000-0000-0000-000000000001', 'valuation.read', 'Valuation Read'),
  ('d5000000-0000-0000-0000-000000000002', 'valuation.manage', 'Valuation Manage'),
  ('d5000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read'),
  -- audit.read so the audit assertion reads through RLS rather than around it.
  ('d5000000-0000-0000-0000-000000000005', 'audit.read', 'Audit Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000004'),
  ('d1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000005');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'd7000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
  'Objekt V', 'Variantenweg 1', '10115', 'Berlin', 'de', 'residential',
  'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'
);

create temporary table p2_d07v_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d07v_results to authenticated;

-- The pair moves together: half a grouping is not storable.
select throws_ok(
  $$insert into public.valuation_cases (
      workspace_id, property_id, title, kind, variant_group_id,
      created_by, updated_by
    ) values (
      'd1000000-0000-0000-0000-000000000001',
      'd7000000-0000-0000-0000-000000000001',
      'Halb gruppiert', 'holding', gen_random_uuid(),
      'da000000-0000-0000-0000-000000000001',
      'da000000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'a group without a label violates the pair check'
);

-- === Creating a variant ===============================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

insert into p2_d07v_results (key, result)
select 'base', public.create_valuation_case(
  'd1000000-0000-0000-0000-000000000001',
  'd7000000-0000-0000-0000-000000000001',
  'Musterfall', 'holding',
  'de000000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
  null, 'exit_cap', null, '{}'::jsonb, 3,
  jsonb_build_array(
    jsonb_build_object(
      'factor_id', 'grossRentAnnual', 'label', 'Rohertrag',
      'provenance', 'user_provided', 'value', 60000
    ),
    jsonb_build_object(
      'factor_id', 'liegenschaftszinssatz', 'label', 'Liegenschaftszinssatz',
      'provenance', 'suggested_default', 'value', 0.035,
      'source', 'Referenztabelle'
    )
  )
);

select is(
  (select result #>> '{entity,variant_group_id}' from p2_d07v_results where key = 'base'),
  null,
  'a fresh case belongs to no group'
);

insert into p2_d07v_results (key, result)
select 'variant', public.create_valuation_variant(
  'd1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'base'),
  'Konservativ',
  'de000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-000000000002',
  'Basis',
  null,
  'Variante zum Vergleich'
);

select is(
  (select result #>> '{ok}' from p2_d07v_results where key = 'variant'),
  'true',
  'a variant can be created from a case'
);
select is(
  (select result #>> '{entity,variant_label}' from p2_d07v_results where key = 'variant'),
  'Konservativ',
  'the variant carries its name'
);
select is(
  (select variant_label from public.valuation_cases
   where id = (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'base')),
  'Basis',
  'the source is named inside the new group'
);
select is(
  (select count(distinct variant_group_id)::integer from public.valuation_cases
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and variant_group_id is not null),
  1,
  'both cases share one group'
);
select is(
  (select count(*)::integer from public.valuation_factors
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'variant')),
  2,
  'the factors are copied into the variant'
);
select is(
  (select provenance::text from public.valuation_factors
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'variant')
     and factor_id = 'liegenschaftszinssatz'),
  'suggested_default',
  'an unconfirmed suggestion stays unconfirmed in the copy'
);
select is(
  (select count(*)::integer from public.valuation_method_results
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'variant')),
  0,
  'the variant starts without a report — no borrowed result'
);
select is(
  (select status::text from public.valuation_cases
   where id = (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'variant')),
  'draft',
  'the variant starts as a draft'
);

-- === Guards ===========================================================

select is(
  public.create_valuation_variant(
    'd1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'base'),
    'Konservativ',
    'de000000-0000-0000-0000-000000000003', 'dc000000-0000-0000-0000-000000000003'
  ) #>> '{error,code}',
  'validation_failed',
  'a duplicate variant name in one group is rejected'
);
select is(
  public.create_valuation_variant(
    'd1000000-0000-0000-0000-000000000001',
    'd7000000-0000-0000-0000-00000000ffff',
    'Irgendwas',
    'de000000-0000-0000-0000-000000000004', 'dc000000-0000-0000-0000-000000000004'
  ) #>> '{error,code}',
  'not_found',
  'an unknown source case is not found'
);
select is(
  public.create_valuation_variant(
    'd1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'base'),
    '   ',
    'de000000-0000-0000-0000-000000000005', 'dc000000-0000-0000-0000-000000000005'
  ) #>> '{error,code}',
  'validation_failed',
  'a blank variant name is rejected'
);

-- Idempotency: the same mutation id replays instead of forking the group.
select is(
  public.create_valuation_variant(
    'd1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07v_results where key = 'base'),
    'Konservativ',
    'de000000-0000-0000-0000-000000000002', 'dc000000-0000-0000-0000-000000000002',
    'Basis',
    null,
    'Variante zum Vergleich'
  ) #>> '{entity,id}',
  (select result #>> '{entity,id}' from p2_d07v_results where key = 'variant'),
  'a replayed mutation id returns the same variant'
);
select is(
  (select count(*)::integer from public.valuation_cases
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'),
  2,
  'the replay created no third case'
);

select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and action = 'valuation_case.variant_create'),
  1,
  'creating a variant is audited under its own action'
);

reset role;

select * from finish();

rollback;
