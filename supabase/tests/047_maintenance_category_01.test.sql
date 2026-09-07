begin;

create extension if not exists pgtap with schema extensions;

-- MAINTENANCE-CATEGORY-01 (V-3).
--
-- The filter is small; the decision behind it is not, and that is what most of
-- these assertions pin.
--
-- `category` stays **free text**. The tempting alternative — an enum — would
-- be the tidier schema and the worse product: a workspace that has been
-- categorising its tickets its own way would have that vocabulary rejected by
-- a migration, and this filter exists to make sense of what is already there.
-- The local demo data proves the point on its own: it uses `electrical`,
-- `elevator`, `hvac` and `water`, none of which appear in the curated list the
-- client carries.
--
-- So the filter must **not** validate against a list, and the assertions below
-- say so out loud: an unknown category matches nothing rather than raising.

select plan(16);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('f1200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'category-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('f1200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'category-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1100000-0000-0000-0000-000000000001', 'category', 'Category');
select private.seed_workspace_role_catalog('f1100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'f1400000-0000-0000-0000-000000000001',
  'f1100000-0000-0000-0000-000000000001',
  'f1200000-0000-0000-0000-000000000001',
  role.id, 'active'
from public.roles as role
where role.workspace_id = 'f1100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('f1500000-0000-0000-0000-000000000001', 'f1100000-0000-0000-0000-000000000001',
   'Kategoriehaus', 'Kategorieweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001'),
  ('f1500000-0000-0000-0000-000000000002', 'f1100000-0000-0000-0000-000000000001',
   'Zweithaus', 'Kategorieweg 2', '10115', 'Berlin', 'de', 'residential', 1,
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001');

-- Two categories on one property, a third on the other. The split matters:
-- the census is workspace-wide on purpose, and a per-property census would
-- pass every assertion but the last one.
insert into public.maintenance_tickets (
  id, workspace_id, property_id, title, category, status, priority,
  reported_at, created_by, updated_by
) values
  ('f1600000-0000-0000-0000-000000000001', 'f1100000-0000-0000-0000-000000000001',
   'f1500000-0000-0000-0000-000000000001', 'Heizung tropft', 'hvac',
   'new', 'normal', now(),
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001'),
  ('f1600000-0000-0000-0000-000000000002', 'f1100000-0000-0000-0000-000000000001',
   'f1500000-0000-0000-0000-000000000001', 'Fenster klemmt', 'defect',
   'new', 'normal', now(),
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001'),
  ('f1600000-0000-0000-0000-000000000003', 'f1100000-0000-0000-0000-000000000001',
   'f1500000-0000-0000-0000-000000000001', 'Zweite Heizung', 'hvac',
   'new', 'high', now(),
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001'),
  ('f1600000-0000-0000-0000-000000000004', 'f1100000-0000-0000-0000-000000000001',
   'f1500000-0000-0000-0000-000000000002', 'Aufzug steht', 'elevator',
   'new', 'urgent', now(),
   'f1200000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_user(p_user uuid, p_statement text)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  execute p_statement into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

create or replace function pg_temp.ws_count(p_category text)
returns integer
language sql
as $$
  select jsonb_array_length(
    pg_temp.as_user(
      'f1200000-0000-0000-0000-000000000001',
      format(
        $q$select public.workspace_maintenance_tickets(
          %L::uuid, null, null, %L)$q$,
        'f1100000-0000-0000-0000-000000000001', p_category
      )
    ) -> 'entity'
  );
$$;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'maintenance_ticket_categories',
  'the vocabulary census exists');

select ok(
  (select count(*) > 0 from pg_indexes
   where schemaname = 'public'
     and indexname = 'maintenance_tickets_category_idx'),
  'and the predicate has an index');

select ok(
  (select indexdef like '%workspace_id%' from pg_indexes
   where schemaname = 'public'
     and indexname = 'maintenance_tickets_category_idx'),
  'composite with workspace_id, not on category alone: every read is '
  'workspace-scoped, so a single-column index would be scanned across tenants '
  'and discarded');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in ('maintenance_tickets',
                              'workspace_maintenance_tickets')),
  2,
  'each list function exists exactly once -- the parameter was added by drop '
  'and recreate, not by an overload that would make the call ambiguous');

-- ---------------------------------------------------------------------------
-- The filter
-- ---------------------------------------------------------------------------

select is(pg_temp.ws_count(null), 4,
  'no category filter returns every ticket');

select is(pg_temp.ws_count('hvac'), 2,
  'a category filter narrows the list');

select is(pg_temp.ws_count('defect'), 1,
  'and a different one narrows it differently');

select is(pg_temp.ws_count('  hvac  '), 2,
  'the argument is trimmed -- the column is trimmed by its own CHECK, and a '
  'filter that only matched untrimmed input would look broken rather than '
  'strict');

select is(pg_temp.ws_count('gibtsnicht'), 0,
  'a category nobody used matches nothing. It is NOT refused: the server does '
  'not know the vocabulary and must not pretend to');

select is(pg_temp.ws_count('HVAC'), 0,
  'matching is exact, not case-folded -- two spellings are two categories, '
  'and the census is where that becomes visible');

select is(
  jsonb_array_length(
    pg_temp.as_user(
      'f1200000-0000-0000-0000-000000000001',
      $q$select public.maintenance_tickets(
        'f1100000-0000-0000-0000-000000000001'::uuid,
        'f1500000-0000-0000-0000-000000000001'::uuid,
        null, null, null, 'hvac')$q$
    ) -> 'entity'
  ),
  2, 'the property-scoped list filters the same way');

-- ---------------------------------------------------------------------------
-- The census
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(
    pg_temp.as_user(
      'f1200000-0000-0000-0000-000000000001',
      $q$select public.maintenance_ticket_categories(
        'f1100000-0000-0000-0000-000000000001'::uuid)$q$
    ) -> 'entity'
  ),
  3, 'the census reports each distinct category once');

select is(
  pg_temp.as_user(
    'f1200000-0000-0000-0000-000000000001',
    $q$select public.maintenance_ticket_categories(
      'f1100000-0000-0000-0000-000000000001'::uuid)$q$
  ) #> '{entity,0}',
  jsonb_build_object('category', 'defect', 'ticket_count', 1),
  'with its count, ordered by name');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      pg_temp.as_user(
        'f1200000-0000-0000-0000-000000000001',
        $q$select public.maintenance_ticket_categories(
          'f1100000-0000-0000-0000-000000000001'::uuid)$q$
      ) -> 'entity'
    ) as entry
    where entry ->> 'category' = 'elevator'
  ),
  'and it spans the workspace, not one property: `elevator` exists only on the '
  'second property, and a per-property census would make the same filter mean '
  'two different things on two screens');

-- ---------------------------------------------------------------------------
-- Permission
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user(
    'f1200000-0000-0000-0000-000000000002',
    $q$select public.maintenance_ticket_categories(
      'f1100000-0000-0000-0000-000000000001'::uuid)$q$
  ) #>> '{error,code}',
  'forbidden',
  'the census is gated like the list it describes -- otherwise it would leak '
  'what a workspace works on to someone who may not see a single ticket');

select is(
  pg_temp.as_user(
    'f1200000-0000-0000-0000-000000000002',
    $q$select public.workspace_maintenance_tickets(
      'f1100000-0000-0000-0000-000000000001'::uuid, null, null, 'hvac')$q$
  ) #>> '{error,code}',
  'forbidden',
  'and so is the filtered list');

select * from finish();
rollback;
