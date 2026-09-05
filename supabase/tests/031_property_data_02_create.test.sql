begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-DATA-02: create_property.
--
-- The property lifecycle was list/getById/update only. Archiving and restoring
-- already ride the audited tombstone path of update_property (DEBT-012), so
-- this package adds exactly one verb: creating a property.
--
-- What is proven here:
--   * the surface exists, is security definer, and no client role but
--     `authenticated` may call it;
--   * the gate order holds -- unauthenticated, then AAL2, then
--     `property.create`; a member with property.update but no property.create
--     is refused;
--   * field validation mirrors the table constraints and names the field,
--     while a well-formed but uppercased code is normalized rather than
--     rejected;
--   * a created property is a draft, audited append-only, and readable back;
--   * idempotency: the same mutation id replays the same property instead of
--     creating a second one, a different payload under the same id conflicts;
--   * no hard delete verb was introduced.

select plan(33);

-- ---------------------------------------------------------------------------
-- Surface and grants
-- ---------------------------------------------------------------------------

select has_function('public', 'create_property',
  'create_property exists');
select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'create_property'),
  true,
  'create_property is security definer'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'create_property'
     and acl.grantee = 'anon'::regrole),
  0,
  'anon cannot call create_property'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'create_property'
     and acl.grantee = 'authenticated'::regrole),
  1,
  'authenticated may call create_property'
);

-- No hard delete slipped in with this package.
select hasnt_function('public', 'delete_property',
  'no hard delete verb exists; archiving stays the restorable tombstone');

-- ---------------------------------------------------------------------------
-- Fixture: one workspace, four users on the seeded role bundles
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pd02-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('d2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pd02-analyst@example.test', '', now(), '{}', '{}', now(), now()),
  ('d2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pd02-viewer@example.test', '', now(), '{}', '{}', now(), now()),
  ('d2000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pd02-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'pd02-a', 'PD02 A');

select private.seed_workspace_role_catalog('d1000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), 'd1000000-0000-0000-0000-000000000001', pairing.user_id, role.id, 'active'
from (values
  ('d2000000-0000-0000-0000-000000000001'::uuid, 'manager'),
  ('d2000000-0000-0000-0000-000000000002'::uuid, 'analyst'),
  ('d2000000-0000-0000-0000-000000000003'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = 'd1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

-- The seeder is the only path into the catalog: an empty database stays empty
-- by design, so the new key is proven here rather than before the fixture.
select is(
  (select count(*)::integer from public.permissions where key = 'property.create'),
  1,
  'the seeder puts property.create into the canonical catalog'
);

-- The seeded bundles carry the intended grants.
select is(
  (select count(*)::integer
   from public.role_permissions as role_permission
   join public.roles as role on role.id = role_permission.role_id
   join public.permissions as permission on permission.id = role_permission.permission_id
   where role.workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and role.key = 'manager'
     and permission.key = 'property.create'),
  1,
  'the seeder grants property.create to manager'
);
select is(
  (select count(*)::integer
   from public.role_permissions as role_permission
   join public.roles as role on role.id = role_permission.role_id
   join public.permissions as permission on permission.id = role_permission.permission_id
   where role.workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and role.key = 'analyst'
     and permission.key = 'property.create'),
  0,
  'the seeder withholds property.create from analyst'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function pg_temp.act_as(p_user uuid, p_aal text)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
end;
$$;

create or replace function pg_temp.reset_actor()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
end;
$$;

-- The correlation id feeds the idempotency hash, so it is derived from the
-- mutation id: a replay then reuses it exactly like a real client retry does.
create or replace function pg_temp.create_call(
  p_user uuid,
  p_aal text,
  p_name text,
  p_mutation uuid,
  p_country text default 'de',
  p_type text default 'residential',
  p_units integer default 0,
  p_zip text default '10115'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, p_aal);
  v_result := public.create_property(
    'd1000000-0000-0000-0000-000000000001',
    p_mutation,
    p_mutation,
    p_name,
    'Neubaustr. 5',
    p_zip,
    'Berlin',
    p_country,
    p_type,
    null,
    p_units,
    null,
    null,
    null,
    'pgTAP fixture'
  );
  perform pg_temp.reset_actor();
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gate order: authentication, then AAL2, then permission
-- ---------------------------------------------------------------------------

select is(
  (select public.create_property(
     'd1000000-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
     'Kein Actor', 'Neubaustr. 5', '10115', 'Berlin', 'de', 'residential'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal1', 'AAL1 Haus',
     'd3000000-0000-0000-0000-0000000000b1'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused even with property.create'
);

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000002', 'aal2', 'Analyst Haus',
     'd3000000-0000-0000-0000-0000000000b2'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'analyst holds property.update but may not create'
);

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000003', 'aal2', 'Viewer Haus',
     'd3000000-0000-0000-0000-0000000000b3'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'viewer may not create'
);

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000004', 'aal2', 'Fremd Haus',
     'd3000000-0000-0000-0000-0000000000b4'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'a non-member may not create in this workspace'
);

select is(
  (select count(*)::integer from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'),
  0,
  'no refused call wrote a row'
);

-- ---------------------------------------------------------------------------
-- Validation, field-accurate
-- ---------------------------------------------------------------------------

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', '   ',
     'd3000000-0000-0000-0000-0000000000a0'
   ) -> 'error' ->> 'field'),
  'name',
  'a blank name fails on the name field'
);
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Land Haus',
     'd3000000-0000-0000-0000-0000000000a1', 'd'
   ) -> 'error' ->> 'field'),
  'country',
  'a too-short country code fails on the country field'
);
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Land Haus',
     'd3000000-0000-0000-0000-0000000000a2', 'de!'
   ) -> 'error' ->> 'field'),
  'country',
  'a country code with illegal characters fails on the country field'
);
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Typ Haus',
     'd3000000-0000-0000-0000-0000000000a3', 'de', 'Mixed Use'
   ) -> 'error' ->> 'field'),
  'property_type',
  'a property type with a space fails on the property_type field'
);
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Einheiten Haus',
     'd3000000-0000-0000-0000-0000000000a4', 'de', 'residential', -1
   ) -> 'error' ->> 'field'),
  'units',
  'negative units fail on the units field'
);
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'PLZ Haus',
     'd3000000-0000-0000-0000-0000000000a5', 'de', 'residential', 0, '   '
   ) -> 'error' ->> 'field'),
  'zip',
  'a blank postal code fails on the zip field'
);

select is(
  (select count(*)::integer from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'),
  0,
  'no rejected validation wrote a row'
);

-- ---------------------------------------------------------------------------
-- The happy path
-- ---------------------------------------------------------------------------

create or replace function pg_temp.first_mutation()
returns uuid
language sql
as $$ select 'd3000000-0000-0000-0000-000000000001'::uuid $$;

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Manager Haus',
     pg_temp.first_mutation()
   ) ->> 'ok'),
  'true',
  'a manager with aal2 creates a property'
);

-- A well-formed but uppercased code is normalized, not rejected: the stored
-- value always satisfies the table normalization constraint either way.
select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Normalisiert Haus',
     'd3000000-0000-0000-0000-0000000000c1', 'DE'
   ) ->> 'ok'),
  'true',
  'a well-formed uppercase country code is accepted'
);
select is(
  (select country from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Normalisiert Haus'),
  'de',
  'the uppercase country code is stored normalized'
);

select is(
  (select status::text from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Manager Haus'),
  'draft',
  'a new property starts as a draft, not active'
);

select is(
  (select deleted_at from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Manager Haus'),
  null,
  'a new property carries no tombstone marker'
);

select is(
  (select version from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Manager Haus'),
  1::bigint,
  'a new property starts at version 1'
);

select is(
  (select created_by from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Manager Haus'),
  'd2000000-0000-0000-0000-000000000001'::uuid,
  'the actor is recorded as creator'
);

select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and action = 'property.create'
     and entity_type = 'property'
     and old_values is null
     and new_values is not null),
  2,
  'each creation records exactly one append-only audit event'
);

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Manager Haus',
     pg_temp.first_mutation()
   ) ->> 'ok'),
  'true',
  'replaying the same mutation id succeeds'
);

select is(
  (select count(*)::integer from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and name = 'Manager Haus'),
  1,
  'the replay returned the same property instead of creating a second one'
);

select is(
  (select pg_temp.create_call(
     'd2000000-0000-0000-0000-000000000001', 'aal2', 'Anderes Haus',
     pg_temp.first_mutation()
   ) -> 'error' ->> 'code'),
  'mutation_conflict',
  'the same mutation id with a different payload is a conflict'
);

select is(
  (select count(*)::integer from public.properties
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'),
  2,
  'the conflicting replay wrote no row: only the two intended properties exist'
);

select * from finish();

rollback;
