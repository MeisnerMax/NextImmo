begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- =============================================================================
-- P2-D03 follow-up increment: the workspace-wide requirement projection
-- (Wave 2, Arbeitspaket 2). Asserts the surface, the server-side authorization,
-- the three sources of the evaluated entity set, and that the two projections
-- share one state derivation instead of drifting.
-- =============================================================================

-- === Schema surface ===================================================

select has_function(
  'public', 'evaluate_workspace_document_requirements',
  array['uuid', 'text', 'uuid[]', 'boolean'],
  'workspace-wide requirement projection exists'
);
select has_function(
  'private', 'document_requirement_state',
  array['timestamptz', 'timestamptz', 'uuid', 'public.document_status', 'date'],
  'the shared DUP-011 state derivation exists'
);

select ok(
  (select function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname = 'evaluate_workspace_document_requirements'),
  'the workspace projection is a postgres security definer with a fixed search path'
);

select ok(
  not has_function_privilege(
    'anon', 'public.evaluate_workspace_document_requirements(uuid, text, uuid[], boolean)', 'execute'
  ),
  'anon cannot execute the workspace projection'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.evaluate_workspace_document_requirements(uuid, text, uuid[], boolean)',
    'execute'
  ),
  'authenticated may execute the workspace projection'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'private.document_requirement_state(timestamptz, timestamptz, uuid, public.document_status, date)',
    'execute'
  ),
  'the shared derivation stays private to the server'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ba000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03w-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('ba000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03w-viewer@example.test', '', now(), '{}', '{}', now(), now()),
  ('bb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03w-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('b1000000-0000-0000-0000-000000000001', 'p2d03w-workspace-a', 'P2D03W Workspace A'),
  ('b2000000-0000-0000-0000-000000000001', 'p2d03w-workspace-b', 'P2D03W Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('b3000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('b3000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer A'),
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('b5000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('b5000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read')
on conflict (key) do nothing;

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', permission.id
from public.permissions as permission
where permission.key in ('document.read', 'workspace.read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'b1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002', permission.id
from public.permissions as permission
where permission.key = 'workspace.read';

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', permission.id
from public.permissions as permission
where permission.key in ('document.read', 'workspace.read');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('b6000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'active'),
  ('b6000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000002', 'active'),
  ('b6000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'active');

insert into public.document_types (
  id, workspace_id, key, name, entity_type, created_by, updated_by
) values
  ('b7000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'energy_certificate', 'Energieausweis', 'property', 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b7000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'purchase_contract', 'Kaufvertrag', 'property', 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b7000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001', 'floor_plan', 'Grundriss', 'property', 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001');

-- A workspace-wide rule (every property needs an energy certificate) and an
-- instance rule bound to one object only.
insert into public.required_documents (
  id, workspace_id, entity_type, entity_id, scope_key, document_type_id,
  is_mandatory, created_by, updated_by
) values
  ('b8000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'property', null, null, 'b7000000-0000-0000-0000-000000000001', true, 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('b8000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'property', 'b9000000-0000-0000-0000-000000000001', null, 'b7000000-0000-0000-0000-000000000002', true, 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  -- A scoped rule: not evaluable workspace-wide without foreign vocabulary.
  ('b8000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001', 'property', null, 'residential', 'b7000000-0000-0000-0000-000000000003', true, 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001');

-- Object 1 is known through its instance rule; object 2 only through a document
-- link; object 3 is known to neither and must be supplied by the caller.
insert into public.documents (
  id, workspace_id, title, document_type_id, status, current_version_no,
  created_by, updated_by
) values
  ('bc000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Energieausweis Objekt 2', 'b7000000-0000-0000-0000-000000000001', 'verified', 1, 'ba000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001');

insert into public.document_links (
  id, workspace_id, document_id, entity_type, entity_id, created_by
) values
  ('bd000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'bc000000-0000-0000-0000-000000000001', 'property', 'b9000000-0000-0000-0000-000000000002', 'ba000000-0000-0000-0000-000000000001');

create temporary table p2_d03w_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d03w_results to authenticated;

-- === Authorization ====================================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'ba000000-0000-0000-0000-000000000002', true);

insert into p2_d03w_results (key, result)
select 'viewer', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001'
);

reset role;
select is(
  (select result -> 'error' ->> 'code' from p2_d03w_results where key = 'viewer'),
  'forbidden',
  'a member without document.read is refused server-side'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'bb000000-0000-0000-0000-000000000001', true);

insert into p2_d03w_results (key, result)
select 'outsider', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001'
);

reset role;
select is(
  (select result -> 'error' ->> 'code' from p2_d03w_results where key = 'outsider'),
  'forbidden',
  'a member of another workspace cannot project this workspace'
);

-- === Validation =======================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ba000000-0000-0000-0000-000000000001', true);

insert into p2_d03w_results (key, result)
select 'no_workspace', public.evaluate_workspace_document_requirements(null);

insert into p2_d03w_results (key, result)
select 'bad_entity_type', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001', 'spaceship'
);

insert into p2_d03w_results (key, result)
select 'ids_without_type', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001',
  null,
  array['b9000000-0000-0000-0000-000000000003'::uuid]
);

-- === Projection =======================================================

insert into p2_d03w_results (key, result)
select 'all', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001'
);

insert into p2_d03w_results (key, result)
select 'with_supplied', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001',
  'property',
  array[
    'b9000000-0000-0000-0000-000000000001'::uuid,
    'b9000000-0000-0000-0000-000000000002'::uuid,
    'b9000000-0000-0000-0000-000000000003'::uuid
  ]
);

insert into p2_d03w_results (key, result)
select 'only_unmet', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001',
  'property',
  array[
    'b9000000-0000-0000-0000-000000000001'::uuid,
    'b9000000-0000-0000-0000-000000000002'::uuid,
    'b9000000-0000-0000-0000-000000000003'::uuid
  ],
  true
);

insert into p2_d03w_results (key, result)
select 'other_type', public.evaluate_workspace_document_requirements(
  'b1000000-0000-0000-0000-000000000001', 'lease'
);

-- The per-entity RPC, for the equivalence assertion below.
insert into p2_d03w_results (key, result)
select 'per_entity_2', public.evaluate_document_requirements(
  'b1000000-0000-0000-0000-000000000001',
  'property',
  'b9000000-0000-0000-0000-000000000002'
);

reset role;

select is(
  (select result -> 'error' ->> 'code' from p2_d03w_results where key = 'no_workspace'),
  'validation_failed',
  'a missing workspace is rejected'
);
select is(
  (select result -> 'error' ->> 'code' from p2_d03w_results where key = 'bad_entity_type'),
  'validation_failed',
  'an unknown entity type is rejected instead of silently returning nothing'
);
select is(
  (select result -> 'error' ->> 'code' from p2_d03w_results where key = 'ids_without_type'),
  'validation_failed',
  'entity ids without an entity type are rejected'
);

select ok(
  (select (result ->> 'ok')::boolean from p2_d03w_results where key = 'all'),
  'a member with document.read gets the workspace projection'
);

-- Without caller-supplied ids: object 1 via its instance rule, object 2 via its
-- document link. Object 3 is unknown to this module and must not appear.
select is(
  (select count(distinct row -> 'entity_id')::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'),
  2,
  'entities are discovered from instance rules and document links alone'
);
select is(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'
     and row ->> 'entity_id' = 'b9000000-0000-0000-0000-000000000003'),
  0,
  'an object with neither a rule nor a document is not invented'
);

-- The workspace rule applies to every discovered entity, the instance rule only
-- to its own.
select is(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'
     and row ->> 'document_type_key' = 'energy_certificate'),
  2,
  'a workspace-wide rule is evaluated once per discovered entity'
);
select is(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'
     and row ->> 'document_type_key' = 'purchase_contract'),
  1,
  'an instance rule is evaluated only for its own entity'
);
select is(
  (select row ->> 'is_instance_rule'
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'
     and row ->> 'document_type_key' = 'purchase_contract'),
  'true',
  'instance rules are marked as such in the projection'
);

-- Caller-supplied ids add exactly the objects this module cannot see itself.
select is(
  (select count(distinct row -> 'entity_id')::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'with_supplied'),
  3,
  'caller-supplied entity ids extend the evaluated set'
);

-- Derived states, computed server-side.
select is(
  (select row ->> 'state'
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'with_supplied'
     and row ->> 'entity_id' = 'b9000000-0000-0000-0000-000000000002'
     and row ->> 'document_type_key' = 'energy_certificate'),
  'satisfied',
  'a linked verified document satisfies its requirement'
);
select is(
  (select row ->> 'state'
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'with_supplied'
     and row ->> 'entity_id' = 'b9000000-0000-0000-0000-000000000003'
     and row ->> 'document_type_key' = 'energy_certificate'),
  'missing',
  'an object without the required document reports missing'
);

-- p_only_unmet drops satisfied rows and keeps everything still outstanding.
select is(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'only_unmet'
     and row ->> 'state' = 'satisfied'),
  0,
  'only_unmet drops satisfied requirements'
);
select ok(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'only_unmet') > 0,
  'only_unmet keeps the outstanding requirements'
);

-- Scoped rules are reported, not silently dropped.
select is(
  (select (result ->> 'scoped_rule_count')::integer
   from p2_d03w_results where key = 'all'),
  1,
  'scoped rules this pass cannot evaluate are counted, not hidden'
);
select is(
  (select count(*)::integer
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'all'
     and row ->> 'document_type_key' = 'floor_plan'),
  0,
  'a scoped rule is left to the per-entity projection'
);

-- An entity type with no rules yields an empty projection, not an error.
select is(
  (select result -> 'requirements' from p2_d03w_results where key = 'other_type'),
  '[]'::jsonb,
  'an entity type without rules projects empty rather than failing'
);

-- One derivation, two entry points: the workspace projection and the per-entity
-- RPC must agree on the same entity.
select is(
  (select array_agg(row ->> 'state' order by row ->> 'document_type_key')
   from p2_d03w_results,
        jsonb_array_elements(result -> 'requirements') as row
   where key = 'with_supplied'
     and row ->> 'entity_id' = 'b9000000-0000-0000-0000-000000000002'),
  (select array_agg(row ->> 'state' order by row ->> 'document_type_key')
   from p2_d03w_results,
        jsonb_array_elements(result -> 'entity') as row
   where key = 'per_entity_2'),
  'both projections derive the same states for the same entity'
);

select * from finish();

rollback;
