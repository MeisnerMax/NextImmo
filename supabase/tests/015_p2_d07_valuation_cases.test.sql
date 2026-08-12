begin;

create extension if not exists pgtap with schema extensions;

select plan(84);

-- === Schema surface ===================================================

select has_table('public', 'valuation_cases', 'valuation_cases table exists');
select has_table('public', 'valuation_factors', 'valuation_factors table exists');
select has_table('public', 'valuation_method_results', 'valuation_method_results table exists');
select has_table('public', 'market_value_opinions', 'market_value_opinions table exists');
select has_table('public', 'valuation_reference_data', 'valuation_reference_data table exists');
select has_type('public', 'valuation_case_kind', 'case kind enum exists');
select has_type('public', 'valuation_case_status', 'case status enum exists');
select has_type('public', 'valuation_factor_provenance', 'factor provenance enum exists');
select has_type('public', 'valuation_confidence_band', 'confidence band enum exists');
select has_type('public', 'valuation_method_kind', 'method kind enum exists');
select has_type('public', 'valuation_dcf_terminal', 'dcf terminal enum exists');

select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.valuation_case_status'::regtype),
  array['draft', 'in_review', 'approved', 'archived'],
  'valuation_case_status carries the lifecycle labels'
);
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum
   where enum.enumtypid = 'public.valuation_factor_provenance'::regtype),
  array['user_provided', 'derived', 'suggested_default', 'accepted', 'missing'],
  'valuation_factor_provenance carries the provenance vocabulary'
);
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.valuation_method_kind'::regtype),
  array[
    'income_approach_de', 'cost_approach_de', 'comparison_approach',
    'discounted_cash_flow', 'direct_capitalization'
  ],
  'valuation_method_kind carries the five methods'
);

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in (
     'public.valuation_cases'::regclass, 'public.valuation_factors'::regclass,
     'public.valuation_method_results'::regclass,
     'public.market_value_opinions'::regclass,
     'public.valuation_reference_data'::regclass
   )),
  'all P2-D07 tables enable and force RLS'
);
select policies_are('public', 'valuation_cases', array['valuation_cases_select_valuation_read']);
select policies_are('public', 'valuation_factors', array['valuation_factors_select_valuation_read']);
select policies_are('public', 'valuation_method_results', array['valuation_method_results_select_valuation_read']);
select policies_are('public', 'market_value_opinions', array['market_value_opinions_select_valuation_read']);
select policies_are('public', 'valuation_reference_data', array['valuation_reference_data_select_valuation_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in (
       'valuation_cases', 'valuation_factors', 'valuation_method_results',
       'market_value_opinions', 'valuation_reference_data'
     )
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no valuation DML grants'
);

select has_function('public', 'create_valuation_case', array['uuid', 'uuid', 'text', 'text', 'uuid', 'uuid', 'uuid', 'text', 'text[]', 'jsonb', 'integer', 'jsonb', 'text']);
select has_function('public', 'update_valuation_case', array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text', 'uuid', 'boolean', 'text', 'text[]', 'jsonb', 'integer', 'text']);
select has_function('public', 'upsert_valuation_factors', array['uuid', 'uuid', 'bigint', 'jsonb', 'uuid', 'uuid', 'text[]', 'text']);
select has_function('public', 'transition_valuation_case_status', array['uuid', 'uuid', 'bigint', 'text', 'uuid', 'uuid', 'text']);
select has_function('public', 'publish_valuation_report', array['uuid', 'uuid', 'bigint', 'jsonb', 'jsonb', 'uuid', 'uuid', 'text']);
select has_function('public', 'upsert_valuation_reference_data', array['uuid', 'text', 'jsonb', 'uuid', 'uuid', 'text', 'text']);

select ok(
  (select bool_and(
     function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in (
       'create_valuation_case', 'update_valuation_case', 'upsert_valuation_factors',
       'transition_valuation_case_status', 'publish_valuation_report',
       'upsert_valuation_reference_data'
     )),
  'valuation RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_valuation_case', 'update_valuation_case', 'upsert_valuation_factors',
       'transition_valuation_case_status', 'publish_valuation_report',
       'upsert_valuation_reference_data'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute valuation RPCs'
);

select ok(
  (select count(*) = 1
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'valuation_cases'),
  'valuation_cases is published for realtime invalidation'
);

-- === Status machine ===================================================

select ok(
  private.valuation_status_can_transition('draft', 'in_review'),
  'draft may go into review'
);
select ok(
  private.valuation_status_can_transition('in_review', 'approved'),
  'a reviewed case may be approved'
);
select ok(
  private.valuation_status_can_transition('in_review', 'draft'),
  'a review may be sent back to draft'
);
select ok(
  not private.valuation_status_can_transition('approved', 'draft'),
  'an approved case never reopens'
);
select ok(
  not private.valuation_status_can_transition('archived', 'draft'),
  'archived is terminal'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ca000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d07-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d07-approver-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d07-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('cb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d07-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('c1000000-0000-0000-0000-000000000001', 'p2d07-workspace-a', 'P2D07 Workspace A'),
  ('c2000000-0000-0000-0000-000000000001', 'p2d07-workspace-b', 'P2D07 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('c3000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'approver', 'Approver A'),
  ('c3000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('c5000000-0000-0000-0000-000000000001', 'valuation.read', 'Valuation Read'),
  ('c5000000-0000-0000-0000-000000000002', 'valuation.manage', 'Valuation Manage'),
  ('c5000000-0000-0000-0000-000000000003', 'valuation.approve', 'Valuation Approve'),
  ('c5000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read'),
  ('c5000000-0000-0000-0000-000000000005', 'audit.read', 'Audit Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- Manager A: read + manage, deliberately NOT approve.
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000004'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000005'),
  -- Approver A: read + manage + approve.
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000002'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000003'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000004'),
  -- Reader A: read only.
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000003', 'c5000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000003', 'c5000000-0000-0000-0000-000000000004'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000004');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('c6000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'active'),
  ('c6000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'active'),
  ('c6000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000003', 'active'),
  ('c6000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('c7000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001',
   'Objekt B', 'Nebenstrasse 2', '20095', 'Hamburg', 'de', 'residential',
   'cb000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001');

create temporary table p2_d07_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d07_results to authenticated;

-- === Storage-level invariants =========================================

select throws_ok(
  $$insert into public.valuation_cases (
      workspace_id, property_id, title, kind, created_by, updated_by
    ) values (
      'c1000000-0000-0000-0000-000000000001',
      'c7000000-0000-0000-0000-000000000001',
      '   ', 'holding',
      'ca000000-0000-0000-0000-000000000001',
      'ca000000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'a blank title violates the title check'
);

-- === Create ===========================================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

insert into p2_d07_results (key, result)
select 'create_case', public.create_valuation_case(
  'c1000000-0000-0000-0000-000000000001',
  'c7000000-0000-0000-0000-000000000001',
  '  Musterfall MFH  ',
  'holding',
  'ce000000-0000-0000-0000-000000000001',
  'cc000000-0000-0000-0000-000000000001',
  null,
  'exit_cap',
  null,
  '{}'::jsonb,
  3,
  jsonb_build_array(
    jsonb_build_object(
      'factor_id', 'grossRentAnnual', 'label', 'Rohertrag',
      'provenance', 'user_provided', 'value', 60000, 'unit', 'EUR',
      'confidence', 'high'
    ),
    jsonb_build_object(
      'factor_id', 'liegenschaftszinssatz', 'label', 'Liegenschaftszinssatz',
      'provenance', 'suggested_default', 'value', 0.035,
      'source', 'Referenztabelle', 'confidence', 'low'
    ),
    jsonb_build_object(
      'factor_id', 'sachwertfaktor', 'label', 'Sachwertfaktor',
      'provenance', 'missing', 'value', null
    )
  ),
  'Ersterfassung'
);

select is(
  (select result #>> '{ok}' from p2_d07_results where key = 'create_case'),
  'true',
  'a manager can create a valuation case'
);
select is(
  (select result #>> '{entity,title}' from p2_d07_results where key = 'create_case'),
  'Musterfall MFH',
  'the title is trimmed'
);
select is(
  (select (result #>> '{entity,version}')::bigint from p2_d07_results where key = 'create_case'),
  1::bigint,
  'a fresh case starts at version 1'
);
select is(
  (select jsonb_array_length(result #> '{entity,factors}') from p2_d07_results where key = 'create_case'),
  3,
  'the initial factor set is written in the same command'
);
select is(
  (select provenance::text from public.valuation_factors
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')
     and factor_id = 'liegenschaftszinssatz'),
  'suggested_default',
  'an unconfirmed suggestion is stored as unconfirmed'
);
select is(
  (select value from public.valuation_factors
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')
     and factor_id = 'sachwertfaktor'),
  null::numeric,
  'a missing factor carries no number'
);

-- A missing factor may not smuggle in a value, and a usable one may not omit it.
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    'Ungueltig', 'holding',
    'ce000000-0000-0000-0000-00000000000a', 'cc000000-0000-0000-0000-00000000000a',
    null, 'exit_cap', null, '{}'::jsonb, 3,
    jsonb_build_array(jsonb_build_object(
      'factor_id', 'capRate', 'label', 'Kapitalisierungszins',
      'provenance', 'missing', 'value', 0.05
    ))
  ) #>> '{error,code}',
  'validation_failed',
  'a missing factor with a value is rejected'
);
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    'Ungueltig', 'holding',
    'ce000000-0000-0000-0000-00000000000b', 'cc000000-0000-0000-0000-00000000000b',
    null, 'exit_cap', null, '{}'::jsonb, 3,
    jsonb_build_array(jsonb_build_object(
      'factor_id', 'capRate', 'label', 'Kapitalisierungszins',
      'provenance', 'user_provided'
    ))
  ) #>> '{error,code}',
  'validation_failed',
  'a usable factor without a value is rejected'
);
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    'Ungueltig', 'holding',
    'ce000000-0000-0000-0000-00000000000c', 'cc000000-0000-0000-0000-00000000000c',
    null, 'exit_cap', array['ertragswert']::text[]
  ) #>> '{error,code}',
  'validation_failed',
  'an unknown method is rejected'
);
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000002',
    'Fremdes Objekt', 'holding',
    'ce000000-0000-0000-0000-00000000000d', 'cc000000-0000-0000-0000-00000000000d'
  ) #>> '{error,code}',
  'not_found',
  'a property from another workspace is not found'
);

-- Idempotency: the same mutation id replays the stored result.
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    '  Musterfall MFH  ', 'holding',
    'ce000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
    null, 'exit_cap', null, '{}'::jsonb, 3,
    jsonb_build_array(
      jsonb_build_object(
        'factor_id', 'grossRentAnnual', 'label', 'Rohertrag',
        'provenance', 'user_provided', 'value', 60000, 'unit', 'EUR',
        'confidence', 'high'
      ),
      jsonb_build_object(
        'factor_id', 'liegenschaftszinssatz', 'label', 'Liegenschaftszinssatz',
        'provenance', 'suggested_default', 'value', 0.035,
        'source', 'Referenztabelle', 'confidence', 'low'
      ),
      jsonb_build_object(
        'factor_id', 'sachwertfaktor', 'label', 'Sachwertfaktor',
        'provenance', 'missing', 'value', null
      )
    ),
    'Ersterfassung'
  ) #>> '{entity,id}',
  (select result #>> '{entity,id}' from p2_d07_results where key = 'create_case'),
  'a replayed mutation id returns the same case'
);
select is(
  (select count(*)::integer from public.valuation_cases
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'),
  1,
  'the replay created no second case'
);
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    'Anderer Titel', 'holding',
    'ce000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001'
  ) #>> '{error,code}',
  'mutation_conflict',
  'reusing a mutation id with a different payload conflicts'
);

-- === Permissions ======================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000003', true);
select is(
  public.create_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    'Vom Leser', 'holding',
    'ce000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'a read-only member cannot create a case'
);
select is(
  (select count(*)::integer from public.valuation_cases),
  1,
  'a reader still sees the workspace case through RLS'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from public.valuation_cases),
  0,
  'a member of another workspace sees nothing'
);
select is(
  public.upsert_valuation_factors(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    1,
    jsonb_build_array(jsonb_build_object(
      'factor_id', 'capRate', 'label', 'Kapitalisierungszins',
      'provenance', 'user_provided', 'value', 0.05
    )),
    'ce000000-0000-0000-0000-000000000003', 'cc000000-0000-0000-0000-000000000003'
  ) #>> '{error,code}',
  'forbidden',
  'a foreign workspace member cannot write factors'
);

-- === Factors ==========================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

insert into p2_d07_results (key, result)
select 'accept_suggestion', public.upsert_valuation_factors(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
  1,
  jsonb_build_array(jsonb_build_object(
    'factor_id', 'liegenschaftszinssatz', 'label', 'Liegenschaftszinssatz',
    'provenance', 'accepted', 'value', 0.035, 'source', 'Referenztabelle',
    'confidence', 'medium'
  )),
  'ce000000-0000-0000-0000-000000000004', 'cc000000-0000-0000-0000-000000000004',
  '{}'::text[],
  'Vorschlag bestaetigt'
);

select is(
  (select result #>> '{ok}' from p2_d07_results where key = 'accept_suggestion'),
  'true',
  'confirming a suggestion is an ordinary audited factor write'
);
select is(
  (select (result #>> '{entity,version}')::bigint from p2_d07_results where key = 'accept_suggestion'),
  2::bigint,
  'a factor write moves the case version'
);
select is(
  (select provenance::text from public.valuation_factors
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')
     and factor_id = 'liegenschaftszinssatz'),
  'accepted',
  'the confirmed suggestion is now accepted'
);
select is(
  public.upsert_valuation_factors(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    1,
    jsonb_build_array(jsonb_build_object(
      'factor_id', 'capRate', 'label', 'Kapitalisierungszins',
      'provenance', 'user_provided', 'value', 0.05
    )),
    'ce000000-0000-0000-0000-000000000005', 'cc000000-0000-0000-0000-000000000005'
  ) #>> '{error,code}',
  'version_conflict',
  'a stale factor write is rejected'
);
select is(
  public.upsert_valuation_factors(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    2,
    '[]'::jsonb,
    'ce000000-0000-0000-0000-000000000006', 'cc000000-0000-0000-0000-000000000006'
  ) #>> '{error,code}',
  'validation_failed',
  'a factor command with nothing to write is rejected'
);

insert into p2_d07_results (key, result)
select 'remove_factor', public.upsert_valuation_factors(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
  2,
  '[]'::jsonb,
  'ce000000-0000-0000-0000-000000000007', 'cc000000-0000-0000-0000-000000000007',
  array['sachwertfaktor']::text[]
);

select is(
  (select jsonb_array_length(result #> '{entity,factors}') from p2_d07_results where key = 'remove_factor'),
  2,
  'removing a factor is a legitimate write'
);

-- The value/provenance rule is a constraint, not merely a command check: even a
-- direct write as the owning role cannot store a missing factor with a number.
reset role;
select throws_ok(
  format(
    $$insert into public.valuation_factors (
        workspace_id, valuation_case_id, factor_id, label, provenance, value,
        created_by, updated_by
      ) values (
        'c1000000-0000-0000-0000-000000000001', %L, 'schmuggel', 'Schmuggel',
        'missing', 0.05,
        'ca000000-0000-0000-0000-000000000001',
        'ca000000-0000-0000-0000-000000000001'
      )$$,
    (select result #>> '{entity,id}' from p2_d07_results where key = 'create_case')
  ),
  '23514',
  null,
  'a missing factor with a value is rejected by the check constraint'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

-- === Report ===========================================================

insert into p2_d07_results (key, result)
select 'publish', public.publish_valuation_report(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
  3,
  jsonb_build_array(
    jsonb_build_object(
      'method', 'income_approach_de', 'is_available', true,
      'amount', 1091313, 'confidence', 'high',
      'breakdown', jsonb_build_array(jsonb_build_object('label', 'Ertragswert')),
      'assumptions', '[]'::jsonb
    ),
    jsonb_build_object(
      'method', 'cost_approach_de', 'is_available', false,
      'missing_factors', jsonb_build_array(
        jsonb_build_object('factor_id', 'sachwertfaktor', 'label', 'Sachwertfaktor')
      ),
      'reasons', '[]'::jsonb
    )
  ),
  jsonb_build_object(
    'is_available', true, 'amount', 1091313, 'confidence', 'high',
    'weights', jsonb_build_object('income_approach_de', 1.0),
    'rationale', 'Nur das Ertragswertverfahren war verfuegbar.'
  ),
  'ce000000-0000-0000-0000-000000000008', 'cc000000-0000-0000-0000-000000000008'
);

select is(
  (select result #>> '{ok}' from p2_d07_results where key = 'publish'),
  'true',
  'a report can be published'
);
select is(
  (select count(*)::integer from public.valuation_method_results
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')),
  2,
  'both method results are stored, available and unavailable alike'
);
select is(
  (select amount from public.valuation_method_results
   where method = 'cost_approach_de'),
  null::numeric,
  'the unavailable method is stored without a number'
);
select is(
  (select is_available from public.market_value_opinions
   where valuation_case_id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')),
  true,
  'the reconciled Verkehrswert is stored'
);
select is(
  (select (result #>> '{entity,computed_from_version}')::bigint from p2_d07_results where key = 'publish'),
  3::bigint,
  'the report records the factor version it was computed from'
);
select is(
  (select count(*)::integer from public.valuation_cases
   where id = (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case')
     and version = 3),
  1,
  'publishing does not move the case version'
);
select is(
  public.publish_valuation_report(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    3,
    jsonb_build_array(jsonb_build_object(
      'method', 'comparison_approach', 'is_available', false, 'amount', 900000,
      'reasons', jsonb_build_array('Keine Vergleichsobjekte')
    )),
    jsonb_build_object('is_available', false, 'rationale', 'nicht ermittelbar'),
    'ce000000-0000-0000-0000-000000000009', 'cc000000-0000-0000-0000-000000000009'
  ) #>> '{error,code}',
  'validation_failed',
  'an unavailable method result may not carry an amount'
);
select is(
  public.publish_valuation_report(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    1,
    jsonb_build_array(jsonb_build_object(
      'method', 'comparison_approach', 'is_available', false,
      'reasons', jsonb_build_array('Keine Vergleichsobjekte')
    )),
    jsonb_build_object('is_available', false, 'rationale', 'nicht ermittelbar'),
    'ce000000-0000-0000-0000-00000000000e', 'cc000000-0000-0000-0000-00000000000e'
  ) #>> '{error,code}',
  'version_conflict',
  'a report computed from a stale factor set is rejected'
);

-- === Lifecycle ========================================================

insert into p2_d07_results (key, result)
select 'to_review', public.transition_valuation_case_status(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
  3, 'in_review',
  'ce000000-0000-0000-0000-000000000010', 'cc000000-0000-0000-0000-000000000010'
);

select is(
  (select result #>> '{entity,status}' from p2_d07_results where key = 'to_review'),
  'in_review',
  'a manager can send a case into review'
);
select is(
  public.transition_valuation_case_status(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    4, 'approved',
    'ce000000-0000-0000-0000-000000000011', 'cc000000-0000-0000-0000-000000000011'
  ) #>> '{error,code}',
  'forbidden',
  'manage alone does not permit approval'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000002', true);

insert into p2_d07_results (key, result)
select 'approve', public.transition_valuation_case_status(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
  4, 'approved',
  'ce000000-0000-0000-0000-000000000012', 'cc000000-0000-0000-0000-000000000012',
  'Freigabe nach Pruefung'
);

select is(
  (select result #>> '{entity,status}' from p2_d07_results where key = 'approve'),
  'approved',
  'an approver can approve the case'
);
select ok(
  (select (result #>> '{entity,approved_at}') is not null from p2_d07_results where key = 'approve'),
  'approval stamps approved_at'
);
select is(
  public.upsert_valuation_factors(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    5,
    jsonb_build_array(jsonb_build_object(
      'factor_id', 'capRate', 'label', 'Kapitalisierungszins',
      'provenance', 'user_provided', 'value', 0.05
    )),
    'ce000000-0000-0000-0000-000000000013', 'cc000000-0000-0000-0000-000000000013'
  ) #>> '{error,code}',
  'approved_immutable',
  'an approved case rejects factor edits with its own error code'
);
select is(
  public.update_valuation_case(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    5,
    'ce000000-0000-0000-0000-000000000014', 'cc000000-0000-0000-0000-000000000014',
    'Neuer Titel'
  ) #>> '{error,code}',
  'approved_immutable',
  'an approved case rejects configuration edits'
);
select is(
  public.publish_valuation_report(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    5,
    jsonb_build_array(jsonb_build_object(
      'method', 'income_approach_de', 'is_available', true, 'amount', 1,
      'confidence', 'low'
    )),
    jsonb_build_object(
      'is_available', true, 'amount', 1, 'confidence', 'low', 'rationale', 'neu'
    ),
    'ce000000-0000-0000-0000-000000000015', 'cc000000-0000-0000-0000-000000000015'
  ) #>> '{error,code}',
  'approved_immutable',
  'an approved case keeps the report it was approved with'
);
select is(
  public.transition_valuation_case_status(
    'c1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d07_results where key = 'create_case'),
    5, 'draft',
    'ce000000-0000-0000-0000-000000000016', 'cc000000-0000-0000-0000-000000000016'
  ) #>> '{error,code}',
  'validation_failed',
  'an approved case cannot be reopened'
);

-- === Reference data ===================================================

insert into p2_d07_results (key, result)
select 'reference', public.upsert_valuation_reference_data(
  'c1000000-0000-0000-0000-000000000001',
  '  Liegenschaftszins.Wohnen  ',
  jsonb_build_object('min', 0.03, 'typical', 0.035, 'max', 0.045),
  'ce000000-0000-0000-0000-000000000017', 'cc000000-0000-0000-0000-000000000017',
  'Gutachterausschuss 2026'
);

select is(
  (select result #>> '{entity,key}' from p2_d07_results where key = 'reference'),
  'liegenschaftszins.wohnen',
  'a reference key is normalized'
);
select is(
  public.upsert_valuation_reference_data(
    'c1000000-0000-0000-0000-000000000001',
    'Kein Key!',
    jsonb_build_object('x', 1),
    'ce000000-0000-0000-0000-000000000018', 'cc000000-0000-0000-0000-000000000018'
  ) #>> '{error,code}',
  'validation_failed',
  'an invalid reference key is rejected'
);
select is(
  (select (public.upsert_valuation_reference_data(
     'c1000000-0000-0000-0000-000000000001',
     'liegenschaftszins.wohnen',
     jsonb_build_object('min', 0.031, 'typical', 0.036, 'max', 0.046),
     'ce000000-0000-0000-0000-000000000019', 'cc000000-0000-0000-0000-000000000019'
   ) #>> '{entity,version}')::bigint),
  2::bigint,
  'overriding an existing reference entry bumps its version'
);

-- === Audit trail ======================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and action = 'valuation_case.create'),
  1,
  'creating a case writes exactly one audit event'
);
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and action = 'valuation_case.factors_upsert'),
  2,
  'every factor write is audited'
);
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and action = 'valuation_case.approved'),
  1,
  'the approval is audited under its own action'
);
select is(
  (select reason from public.audit_events
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and action = 'valuation_case.approved'),
  'Freigabe nach Pruefung',
  'the approval reason is retained'
);
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and action = 'valuation_report.publish'),
  1,
  'publishing a report is audited'
);

reset role;

select * from finish();

rollback;
