begin;

create extension if not exists pgtap with schema extensions;

-- AUDIT-01: the property audit trail read port.
--
-- An audit read is the one place where "it returns the right rows" is not
-- enough: it must also return the right *columns*, because the underlying row
-- carries form payloads and permission snapshots. So this file proves three
-- things in equal measure:
--
--   * the gate order, including the part that is easy to get wrong — holding
--     `audit.read` must not become a way around an entity scope;
--   * the projection, field by field, including that the value columns are
--     absent and only the changed field NAMES travel;
--   * the paging, because a trail that silently drops events is worse than one
--     that admits it has more.

select plan(32);

select has_function('public', 'property_audit_events',
  'the audit read port exists');
select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_audit_events'),
  true,
  'it is security definer: it re-derives both permissions itself'
);
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_audit_events'),
  's'::"char",
  'it is stable: an audit read never writes'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_audit_events'
     and acl.grantee = 'anon'::regrole),
  0,
  'anon cannot call it'
);
select has_index('public', 'audit_events', 'audit_events_entity_trail_idx',
  'the entity trail is a lookup, not a scan');
select has_index('public', 'audit_events', 'audit_events_parent_entity_trail_idx',
  'and so is the child-entity trail');

-- ---------------------------------------------------------------------------
-- Fixture: one workspace, two properties, four actors
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-analyst@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-scoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('a1000000-0000-0000-0000-000000000001', 'audit-a', 'Audit A');

select private.seed_workspace_role_catalog('a1000000-0000-0000-0000-000000000001');

-- Every catalogue role carries audit.read, so the "may read the property but
-- not its trail" case needs a role of its own. That combination is exactly
-- what the second gate exists for, and it has to be provable.
insert into public.roles (id, workspace_id, key, name) values (
  'a3000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',
  'property_only', 'Property Only'
);
insert into public.role_permissions (workspace_id, role_id, permission_id)
select
  'a1000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  permission.id
from public.permissions as permission
where permission.key = 'property.read';

-- The scoped member is an admin pinned to property A only.
insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'a1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('a4000000-0000-0000-0000-000000000001'::uuid, 'a2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('a4000000-0000-0000-0000-000000000002'::uuid, 'a2000000-0000-0000-0000-000000000002'::uuid, 'property_only'),
  ('a4000000-0000-0000-0000-000000000003'::uuid, 'a2000000-0000-0000-0000-000000000003'::uuid, 'admin')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'a1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
values ('a1000000-0000-0000-0000-000000000001',
        'a4000000-0000-0000-0000-000000000003',
        'property', 'a5000000-0000-0000-0000-000000000001');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('a5000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
   'Audit-Haus', 'Protokollweg 1', '10115', 'Berlin', 'de', 'residential', 3,
   'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001'),
  ('a5000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001',
   'Nachbar-Haus', 'Protokollweg 2', '10115', 'Berlin', 'de', 'residential', 3,
   'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001');

-- Property A: three own events plus one child event; property B one event that
-- must never appear in A's trail. `new_values` carries a value on purpose --
-- the read must strip it and keep only the field name.
insert into public.audit_events (
  id, workspace_id, actor_type, actor_user_id, actor_identifier, role_key,
  action, entity_type, entity_id, parent_entity_type, parent_entity_id, source,
  correlation_id, reason, old_values, new_values, created_at, updated_at
) values
  ('a6000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
   'user', 'a2000000-0000-0000-0000-000000000001', null, 'admin', 'property.created',
   'property', 'a5000000-0000-0000-0000-000000000001', null, null, 'rpc',
   'a7000000-0000-0000-0000-000000000001', 'Erstanlage', null,
   '{"name": "Audit-Haus"}'::jsonb,
   now() - interval '3 hours', now() - interval '3 hours'),
  ('a6000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001',
   'user', 'a2000000-0000-0000-0000-000000000001', null, 'admin', 'property.updated',
   'property', 'a5000000-0000-0000-0000-000000000001', null, null, 'rpc',
   'a7000000-0000-0000-0000-000000000002', null,
   '{"zip": "10115", "city": "Berlin"}'::jsonb,
   '{"zip": "10117", "city": "Berlin"}'::jsonb,
   now() - interval '2 hours', now() - interval '2 hours'),
  ('a6000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001',
   'service', null, 'system.emitter', null, 'unit.created', 'unit',
   'a8000000-0000-0000-0000-000000000001', 'property',
   'a5000000-0000-0000-0000-000000000001', 'job',
   'a7000000-0000-0000-0000-000000000003', null, null, null,
   now() - interval '1 hour', now() - interval '1 hour'),
  ('a6000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001',
   'user', 'a2000000-0000-0000-0000-000000000001', null, 'admin', 'property.archived',
   'property', 'a5000000-0000-0000-0000-000000000001', null, null, 'rpc',
   'a7000000-0000-0000-0000-000000000004', 'Verkauf', null, null,
   now() - interval '10 minutes', now() - interval '10 minutes'),
  ('a6000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001',
   'user', 'a2000000-0000-0000-0000-000000000001', null, 'admin', 'property.updated',
   'property', 'a5000000-0000-0000-0000-000000000002', null, null, 'rpc',
   'a7000000-0000-0000-0000-000000000005', null, null,
   '{"name": "Nachbar-Haus"}'::jsonb,
   now() - interval '5 minutes', now() - interval '5 minutes');

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

create or replace function pg_temp.trail(
  p_user uuid,
  p_aal text default 'aal2',
  p_property uuid default 'a5000000-0000-0000-0000-000000000001',
  p_after_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, p_aal);
  v_result := public.property_audit_events(
    'a1000000-0000-0000-0000-000000000001', p_property,
    p_after_at, p_after_id, p_limit
  );
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  (select public.property_audit_events(
     'a1000000-0000-0000-0000-000000000001',
     'a5000000-0000-0000-0000-000000000001'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000004')
     -> 'error' ->> 'code'),
  'forbidden',
  'a non-member is refused'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000002')
     -> 'error' ->> 'message'),
  'Audit access is not permitted',
  'a member who may read the property but not the audit is refused, and told '
  'which of the two is missing'
);
select is(
  (select pg_temp.trail(
     'a2000000-0000-0000-0000-000000000003', 'aal2',
     'a5000000-0000-0000-0000-000000000002'
   ) -> 'error' ->> 'message'),
  'Property access is not permitted',
  'audit.read is no way around an entity scope: the scoped admin cannot read '
  'the neighbouring property''s trail'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000003') ->> 'ok'),
  'true',
  'the same scoped admin reads the property inside their scope'
);
select is(
  (select pg_temp.trail(
     'a2000000-0000-0000-0000-000000000001', 'aal2',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown property is not found, not forbidden'
);

-- ---------------------------------------------------------------------------
-- The trail itself
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events')),
  4,
  'three own events plus the child event, and nothing from the neighbour'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 0 ->> 'action'),
  'property.archived',
  'newest first'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 1 ->> 'action'),
  'unit.created',
  'a child entity appears in its property''s trail through parent_entity'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 1 ->> 'entity_type'),
  'unit',
  'and keeps its own entity type, so the row can name its target'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'a5000000-0000-0000-0000-000000000002'),
  0,
  'the neighbouring property''s event never appears'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 0 ->> 'reason'),
  'Verkauf',
  'the operator''s own justification travels: it is audit metadata'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 1 ->> 'actor_type'),
  'service',
  'a service actor is reported as one'
);
select is(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 1 ->> 'actor_identifier'),
  'system.emitter',
  'and names itself, since it has no user id'
);
select isnt(
  (select pg_temp.trail('a2000000-0000-0000-0000-000000000001')
     -> 'events' -> 0 ->> 'correlation_id'),
  null,
  'the correlation id travels, so one action can be followed across records'
);

-- ---------------------------------------------------------------------------
-- Redaction: names, never values
-- ---------------------------------------------------------------------------

select is(
  (select event -> 'changed_fields'
   from jsonb_array_elements(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'action' = 'property.updated'),
  '["city", "zip"]'::jsonb,
  'the changed field names travel, sorted and deduplicated across old and new'
);
select ok(
  (select bool_and(
     not (event ? 'old_values')
     and not (event ? 'new_values')
     and not (event ? 'scope_snapshot')
   )
   from jsonb_array_elements(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event),
  'no value column travels: not old, not new, not the scope snapshot'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event::text like '%10117%'),
  0,
  'the changed value itself appears nowhere in the payload'
);
select is(
  (select event -> 'changed_fields'
   from jsonb_array_elements(
     pg_temp.trail('a2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'action' = 'unit.created'),
  '[]'::jsonb,
  'an event that patched nothing reports an empty list, not null'
);

-- ---------------------------------------------------------------------------
-- Paging
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.trail(
       'a2000000-0000-0000-0000-000000000001', 'aal2',
       'a5000000-0000-0000-0000-000000000001', null, null, 2
     ) -> 'events')),
  2,
  'the limit is honoured'
);
select isnt(
  (select pg_temp.trail(
     'a2000000-0000-0000-0000-000000000001', 'aal2',
     'a5000000-0000-0000-0000-000000000001', null, null, 2
   ) -> 'next_cursor'),
  'null'::jsonb,
  'and a further page is announced rather than silently dropped'
);
select is(
  (select pg_temp.trail(
     'a2000000-0000-0000-0000-000000000001', 'aal2',
     'a5000000-0000-0000-0000-000000000001',
     ((pg_temp.trail(
        'a2000000-0000-0000-0000-000000000001', 'aal2',
        'a5000000-0000-0000-0000-000000000001', null, null, 2
      ) -> 'next_cursor' ->> 'occurred_at')::timestamptz),
     ((pg_temp.trail(
        'a2000000-0000-0000-0000-000000000001', 'aal2',
        'a5000000-0000-0000-0000-000000000001', null, null, 2
      ) -> 'next_cursor' ->> 'id')::uuid),
     2
   ) -> 'events' -> 0 ->> 'action'),
  'property.updated',
  'the next page continues where the first ended, with no overlap'
);
select is(
  (select pg_temp.trail(
     'a2000000-0000-0000-0000-000000000001', 'aal2',
     'a5000000-0000-0000-0000-000000000001', null, null, 500
   ) -> 'next_cursor'),
  'null'::jsonb,
  'an oversized limit is capped and still reports the truth about the end'
);
select is(
  (select jsonb_array_length(
     pg_temp.trail(
       'a2000000-0000-0000-0000-000000000001', 'aal2',
       'a5000000-0000-0000-0000-000000000001', null, null, 500
     ) -> 'events')),
  4,
  'and returns everything that is there'
);

-- The read leaves no trace: reading an audit trail is not itself a mutation,
-- and an audit log that grows when it is read cannot be reasoned about.
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'
     and action like '%read%'),
  0,
  'reading the trail writes no audit event of its own'
);

select * from finish();

rollback;
