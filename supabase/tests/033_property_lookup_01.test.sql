begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-LOOKUP-01: workspace-wide property search.
--
-- The security claim of this package is that the search adds no read path: it
-- is a filter on the table read whose RLS policy already decides who sees
-- which property. A claim like that is only worth what its tests are, so most
-- of what follows drives the search as four different callers and checks that
-- each one finds exactly what the list would have shown them:
--
--   * a full member finds their own workspace and never the neighbouring one;
--   * an entity-scoped member finds only the property their scope names, even
--     when a perfectly matching property sits next to it;
--   * a non-member and an `aal1` session find nothing at all.
--
-- The rest pins the column itself: generated, not writable, and holding what
-- the spec named (name, both address lines, zip, city) and nothing more.

select plan(24);

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

select has_column(
  'public', 'properties', 'search_text',
  'properties carries the search column'
);
select is(
  (select is_generated
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'properties'
     and column_name = 'search_text'),
  'ALWAYS',
  'it is generated, so it cannot drift from the row'
);
select ok(
  (select count(*) > 0
   from pg_extension as extension
   join pg_namespace as namespace on namespace.oid = extension.extnamespace
   where extension.extname = 'pg_trgm' and namespace.nspname = 'extensions'),
  'pg_trgm is installed in the extensions schema'
);
select has_index(
  'public', 'properties', 'properties_search_text_trgm_idx',
  'the trigram index exists, so an infix match is not a scan'
);

-- ---------------------------------------------------------------------------
-- Fixture: two workspaces, three properties, three actors
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('f2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lookup-full@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lookup-scoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lookup-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'lookup-a', 'Lookup A'),
  ('f1000000-0000-0000-0000-000000000002', 'lookup-b', 'Lookup B');

select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000001');
select private.seed_workspace_role_catalog('f1000000-0000-0000-0000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'f4000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  role.id,
  'active'
from public.roles as role
where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
  and role.key = 'manager';

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'f4000000-0000-0000-0000-000000000002',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000002',
  role.id,
  'active'
from public.roles as role
where role.workspace_id = 'f1000000-0000-0000-0000-000000000001'
  and role.key = 'viewer';

-- Atlas Haus and Atlas Kontor both match "atlas"; the second one is what the
-- entity scope must hide. The Lookup B property matches too and belongs to
-- another workspace entirely.
insert into public.properties (
  id, workspace_id, name, address_line1, address_line2, zip, city, country,
  property_type, units, created_by, updated_by
) values
  ('f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'Atlas Haus', 'Musterstraße 1', 'Aufgang B', '10115', 'Berlin', 'de',
   'residential', 4,
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f5000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'Atlas Kontor', 'Sichtweg 2', null, '20095', 'Hamburg', 'de',
   'office', 9,
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001'),
  ('f5000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000002',
   'Atlas Turm', 'Fremdstraße 3', null, '10115', 'Berlin', 'de',
   'office', 2,
   'f2000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- The column holds exactly what the spec named
-- ---------------------------------------------------------------------------

select is(
  (select search_text from public.properties
   where id = 'f5000000-0000-0000-0000-000000000001'),
  'atlas haus musterstraße 1 aufgang b 10115 berlin',
  'name, both address lines, zip and city, lower-cased'
);
select is(
  (select search_text from public.properties
   where id = 'f5000000-0000-0000-0000-000000000002'),
  'atlas kontor sichtweg 2  20095 hamburg',
  'a missing address line leaves the rest searchable'
);
select ok(
  (select search_text not like '%office%' from public.properties
   where id = 'f5000000-0000-0000-0000-000000000002'),
  'the property type is not searchable text: it is a filter, not a name'
);
select throws_ok(
  $$update public.properties set search_text = 'injected'
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  '428C9',
  null,
  'nobody can write the column, not even the owner'
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

-- Exactly the shape the client sends: the RLS-governed table read, filtered by
-- one lower-cased infix term per token, ordered by the contract's `id ASC`.
create or replace function pg_temp.search(
  p_user uuid,
  p_terms text[],
  p_aal text default 'aal2'
)
returns text[]
language plpgsql
as $$
declare
  v_names text[];
begin
  perform pg_temp.act_as(p_user, p_aal);
  select coalesce(array_agg(property.name order by property.id), '{}')
  into v_names
  from public.properties as property
  where not exists (
    select 1
    from unnest(p_terms) as term
    where property.search_text not like '%' || term || '%'
  );
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v_names;
end;
$$;

-- ---------------------------------------------------------------------------
-- A full member searches their own workspace, and only theirs
-- ---------------------------------------------------------------------------

select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas']),
  array['Atlas Haus', 'Atlas Kontor'],
  'a matching term finds every permitted property in the workspace'
);
select ok(
  not (pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas'])
       @> array['Atlas Turm']),
  'the identically named property in another workspace never appears'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['10115']),
  array['Atlas Haus'],
  'the zip is searchable'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['hamburg']),
  array['Atlas Kontor'],
  'the city is searchable'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['musterstra']),
  array['Atlas Haus'],
  'a partial street name is enough'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['aufgang']),
  array['Atlas Haus'],
  'the second address line is searchable'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas', 'hamburg']),
  array['Atlas Kontor'],
  'two terms narrow: every one of them must match'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas', 'lissabon']),
  '{}'::text[],
  'a term nothing matches yields nothing, never a partial match'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['%']),
  array['Atlas Haus', 'Atlas Kontor'],
  'a wildcard term is not a way out of the workspace'
);

-- ---------------------------------------------------------------------------
-- An entity-scoped member searches inside their scope only
-- ---------------------------------------------------------------------------

insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
values ('f1000000-0000-0000-0000-000000000001',
        'f4000000-0000-0000-0000-000000000002',
        'property', 'f5000000-0000-0000-0000-000000000001');

select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000002', array['atlas']),
  array['Atlas Haus'],
  'the scoped member finds their property'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000002', array['kontor']),
  '{}'::text[],
  'and cannot reach the neighbouring property by searching for it'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000002', array['hamburg']),
  '{}'::text[],
  'not by its city either: the scope holds for every term'
);

-- ---------------------------------------------------------------------------
-- Everyone else finds nothing
-- ---------------------------------------------------------------------------

select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000003', array['atlas']),
  '{}'::text[],
  'a non-member finds nothing'
);
select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas'], 'aal1'),
  '{}'::text[],
  'an aal1 session finds nothing: DEC-025 holds for the search too'
);
select is(
  (select array_agg(policy.policyname::text order by policy.policyname)
   from pg_policies as policy
   where policy.schemaname = 'public'
     and policy.tablename = 'properties'
     and policy.cmd = 'SELECT'),
  array['properties_select_property_read'],
  'the search adds no second read policy: it filters the one that exists'
);

-- ---------------------------------------------------------------------------
-- Archived properties follow the existing filter, not a new rule
-- ---------------------------------------------------------------------------

-- The tombstone marker travels with the status (DEBT-012); the fixture sets
-- both so the row is archived the way the contract archives it.
update public.properties
set status = 'archived', deleted_at = now()
where id = 'f5000000-0000-0000-0000-000000000002';

select is(
  pg_temp.search('f2000000-0000-0000-0000-000000000001', array['atlas']),
  array['Atlas Haus', 'Atlas Kontor'],
  'archiving does not hide a row from the search; includeArchived does that, '
  'and it is the caller''s filter'
);

select * from finish();

rollback;
