begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-ACTIVITY-01.
--
-- The interesting assertions here are about exclusion, not inclusion. A
-- chronicle is easy to make look good by showing everything; the work is in
-- what it refuses to show and how honestly it says so.
--
--   * a record the caller may not read contributes no row, server-side;
--   * the payload names the domains the caller *can* see, and never counts the
--     events it withheld;
--   * an entity type the taxonomy does not know is dropped, not guessed at;
--   * no values, no changed field names, no `reason`;
--   * an actor is named only for a caller who already holds the audit trail.

select plan(35);

select has_function('public', 'property_activity',
  'the activity read port exists');
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_activity'),
  's'::"char",
  'it is stable: a read, never a mutation'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_activity'
     and acl.grantee = 'anon'::regrole),
  0,
  'anon cannot call it'
);

-- The taxonomy is a code contract, not workspace data.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'private'
     and function.proname in (
       'property_activity_taxonomy', 'property_activity_rows'
     )
     and acl.grantee in ('anon'::regrole, 'authenticated'::regrole)),
  0,
  'the taxonomy and the property resolution are unreachable from a client'
);
select ok(
  (select bool_and(taxonomy.required_permission in (
     'property.read', 'lease.read', 'maintenance.read', 'capex.read',
     'task.read', 'document.read', 'valuation.read'
   ))
   from private.property_activity_taxonomy() as taxonomy),
  'every mapped entity type names a real domain read permission'
);
select ok(
  (select count(*) = count(distinct entity_type)
   from private.property_activity_taxonomy()),
  'no entity type is mapped twice, so no row can pick up two permissions'
);

-- ---------------------------------------------------------------------------
-- Fixture: one property, one member per permission shape, events in six
-- domains plus two that must never appear.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'act-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('d2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'act-property-only@example.test', '', now(), '{}', '{}', now(), now()),
  ('d2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'act-actor@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'act-a', 'Activity A');

select private.seed_workspace_role_catalog('d1000000-0000-0000-0000-000000000001');

-- A role that may read the property and nothing else. It is the whole point of
-- the per-row gate: this member must see property events and no others.
insert into public.roles (id, workspace_id, key, name) values (
  'd3000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000001',
  'property_only', 'Property Only'
);
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'd1000000-0000-0000-0000-000000000001',
       'd3000000-0000-0000-0000-000000000001',
       permission.id
from public.permissions as permission
where permission.key = 'property.read';

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'd1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('d4000000-0000-0000-0000-000000000001'::uuid, 'd2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('d4000000-0000-0000-0000-000000000002'::uuid, 'd2000000-0000-0000-0000-000000000002'::uuid, 'property_only'),
  ('d4000000-0000-0000-0000-000000000003'::uuid, 'd2000000-0000-0000-0000-000000000003'::uuid, 'admin')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'd1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('d5000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'Chronikhaus', 'Verlaufweg 2', '10115', 'Berlin', 'de', 'residential', 1,
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001'),
  -- A second property, so "scoped to this property" is actually tested.
  ('d5000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
   'Nachbarhaus', 'Verlaufweg 4', '10115', 'Berlin', 'de', 'residential', 1,
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'd5000000-0000-0000-0000-000000000001', 'A-01', 'vacant',
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001'),
  ('d6000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
   'd5000000-0000-0000-0000-000000000002', 'B-01', 'vacant',
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001');

insert into public.maintenance_tickets (
  id, workspace_id, property_id, title, category, status, priority,
  created_by, updated_by
) values
  ('d7000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'd5000000-0000-0000-0000-000000000001', 'Heizung', 'hvac', 'triage', 'normal',
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Audit rows: one per domain, plus the two that must never surface.
-- ---------------------------------------------------------------------------

insert into public.audit_events (
  id, workspace_id, actor_type, actor_user_id, actor_identifier, role_key,
  scope_snapshot, action, entity_type, entity_id, source, correlation_id,
  mutation_id, reason, old_values, new_values, created_at, created_by,
  updated_by
) values
  -- property, by the admin themselves
  ('d8000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'user', 'd2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'update', 'property', 'd5000000-0000-0000-0000-000000000001', 'rpc',
   'd9000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001',
   'Adresse korrigiert', '{"city": "Bonn"}', '{"city": "Berlin"}',
   now() - interval '5 hours',
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001'),
  -- unit -> leasing, by somebody else
  ('d8000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001',
   'user', 'd2000000-0000-0000-0000-000000000003', null, 'admin', '{}',
   'create', 'unit', 'd6000000-0000-0000-0000-000000000001', 'rpc',
   'd9000000-0000-0000-0000-000000000002', 'da000000-0000-0000-0000-000000000002',
   'Erstaufnahme', null, '{"unit_code": "A-01"}',
   now() - interval '4 hours',
   'd2000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000003'),
  -- maintenance ticket -> maintenance
  ('d8000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001',
   'user', 'd2000000-0000-0000-0000-000000000003', null, 'admin', '{}',
   'transition', 'maintenance_ticket', 'd7000000-0000-0000-0000-000000000001', 'rpc',
   'd9000000-0000-0000-0000-000000000003', 'da000000-0000-0000-0000-000000000003',
   null, '{"status": "draft"}', '{"status": "open"}',
   now() - interval '3 hours',
   'd2000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000003'),
  -- a unit of the NEIGHBOURING property: right workspace, wrong building
  ('d8000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001',
   'user', 'd2000000-0000-0000-0000-000000000003', null, 'admin', '{}',
   'create', 'unit', 'd6000000-0000-0000-0000-000000000002', 'rpc',
   'd9000000-0000-0000-0000-000000000004', 'da000000-0000-0000-0000-000000000004',
   null, null, '{"unit_code": "B-01"}',
   now() - interval '2 hours',
   'd2000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000003'),
  -- a membership change: workspace administration, not property history, and
  -- not in the taxonomy
  ('d8000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001',
   'user', 'd2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'update', 'membership', 'd4000000-0000-0000-0000-000000000002', 'rpc',
   'd9000000-0000-0000-0000-000000000005', 'da000000-0000-0000-0000-000000000005',
   null, null, '{"role_key": "viewer"}',
   now() - interval '1 hour',
   'd2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001'),
  -- a system actor
  ('d8000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000001',
   'system', null, 'retention-job', null, '{}',
   'update', 'property', 'd5000000-0000-0000-0000-000000000001', 'job',
   'd9000000-0000-0000-0000-000000000006', 'da000000-0000-0000-0000-000000000006',
   null, null, '{"status": "active"}',
   now() - interval '30 minutes',
   null, null);

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------

create or replace function pg_temp.activity(
  p_user uuid,
  p_aal text default 'aal2',
  p_property uuid default 'd5000000-0000-0000-0000-000000000001',
  p_domains text[] default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
  v_result := public.property_activity(
    'd1000000-0000-0000-0000-000000000001', p_property,
    p_domains, p_from, p_to, null, null, p_limit
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
  (select public.property_activity(
     'd1000000-0000-0000-0000-000000000001',
     'd5000000-0000-0000-0000-000000000001'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.activity('d2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.activity(
     'd2000000-0000-0000-0000-000000000001', 'aal2',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown property is not found, not forbidden'
);
select is(
  (select pg_temp.activity(
     'd2000000-0000-0000-0000-000000000001', 'aal2',
     'd5000000-0000-0000-0000-000000000001', null,
     now(), now() - interval '1 day'
   ) -> 'error' ->> 'code'),
  'validation_failed',
  'a period that ends before it starts is refused, not silently swapped'
);

-- ---------------------------------------------------------------------------
-- Scope
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events')),
  4,
  'the admin sees the four events that belong to this property'
);
select ok(
  (select not bool_or(
     event ->> 'entity_id' = 'd6000000-0000-0000-0000-000000000002')
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event),
  'the neighbouring property''s unit never appears: same workspace is not the '
  'same building'
);
select ok(
  (select not bool_or(event ->> 'entity_type' = 'membership')
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event),
  'an entity type the taxonomy does not know is dropped, never guessed at'
);
select is(
  (select pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     -> 'events' -> 0 ->> 'entity_type'),
  'property',
  'newest first: the system update on the property leads'
);
select is(
  (select pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     -> 'events' -> 0 ->> 'actor_type'),
  'system',
  'and a system actor is reported as one'
);

-- ---------------------------------------------------------------------------
-- Per-row permission
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.activity('d2000000-0000-0000-0000-000000000002') -> 'events')),
  2,
  'a member with only property.read sees the two property events'
);
select ok(
  (select bool_and(event ->> 'domain' = 'property')
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000002') -> 'events'
   ) as event),
  'and nothing from a domain they cannot read — the filter is server-side'
);
select is(
  (select pg_temp.activity('d2000000-0000-0000-0000-000000000002')
     -> 'visible_domains'),
  '["property"]'::jsonb,
  'the payload names the domains this caller covers, so a partial timeline '
  'says so'
);
select ok(
  (select not (pg_temp.activity('d2000000-0000-0000-0000-000000000002')
     ? 'hidden_count')),
  'and never counts what it withheld: a tally of other people''s records is '
  'still a disclosure'
);
select ok(
  (select (pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     -> 'visible_domains') @> '["leasing", "maintenance", "property"]'::jsonb),
  'an admin covers the domains their role actually grants'
);

-- ---------------------------------------------------------------------------
-- What a row may say
-- ---------------------------------------------------------------------------

select ok(
  (select bool_and(
     not (event ? 'reason')
     and not (event ? 'old_values')
     and not (event ? 'new_values')
     and not (event ? 'changed_fields')
     and not (event ? 'scope_snapshot')
   )
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event),
  'no values, no changed field names and no reason: activity is not the audit '
  'trail with a friendlier font'
);
select is(
  (select event ->> 'event_key'
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'd7000000-0000-0000-0000-000000000001'),
  'maintenance_ticket.transition',
  'the event key is built from the stored columns, so a new action shows up '
  'as a key instead of vanishing'
);
select is(
  (select event ->> 'domain'
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'd6000000-0000-0000-0000-000000000001'),
  'leasing',
  'a unit change is a leasing event, because that is the gate it sits behind'
);

-- ---------------------------------------------------------------------------
-- Actor visibility
-- ---------------------------------------------------------------------------

select ok(
  (select (pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     -> 'actor_names_visible')::boolean),
  'an admin holds audit.read, so actors may be named'
);
select is(
  (select event ->> 'actor_user_id'
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'd6000000-0000-0000-0000-000000000001'),
  'd2000000-0000-0000-0000-000000000003',
  'and the id travels for them — it is the same id the audit trail publishes'
);
select ok(
  (select not (pg_temp.activity('d2000000-0000-0000-0000-000000000002')
     -> 'actor_names_visible')::boolean),
  'a member without audit.read may not name actors'
);
select ok(
  (select bool_and(event ->> 'actor_user_id' is null)
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000002') -> 'events'
   ) as event),
  'so no actor id reaches them, even though the rows carry one'
);
select ok(
  (select bool_and(event ? 'actor_is_self')
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000002') -> 'events'
   ) as event),
  'what they do get is whether it was them: identity about oneself needs no '
  'approval'
);
select ok(
  (select (event -> 'actor_is_self')::boolean
   from jsonb_array_elements(
     pg_temp.activity('d2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'd5000000-0000-0000-0000-000000000001'
     and event ->> 'action' = 'update'
     and event ->> 'actor_type' = 'user'),
  'the admin''s own change is marked as theirs'
);

-- ---------------------------------------------------------------------------
-- Filters and paging
-- ---------------------------------------------------------------------------

select is(
  (select jsonb_array_length(
     pg_temp.activity(
       'd2000000-0000-0000-0000-000000000001', 'aal2',
       'd5000000-0000-0000-0000-000000000001', array['leasing']
     ) -> 'events')),
  1,
  'a domain filter narrows to that domain'
);
select is(
  (select jsonb_array_length(
     pg_temp.activity(
       'd2000000-0000-0000-0000-000000000002', 'aal2',
       'd5000000-0000-0000-0000-000000000001', array['leasing']
     ) -> 'events')),
  0,
  'asking for a domain you cannot read returns an empty timeline rather than '
  'a refusal — the coverage list already explains why'
);
select is(
  (select jsonb_array_length(
     pg_temp.activity(
       'd2000000-0000-0000-0000-000000000001', 'aal2',
       'd5000000-0000-0000-0000-000000000001', null,
       now() - interval '90 minutes'
     ) -> 'events')),
  1,
  'a period start excludes what happened before it'
);
select ok(
  (select pg_temp.activity(
     'd2000000-0000-0000-0000-000000000001', 'aal2',
     'd5000000-0000-0000-0000-000000000001', null, null, null, 2
   ) -> 'next_cursor' is not null),
  'a full page reports a cursor'
);
select ok(
  (select pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     -> 'next_cursor' = 'null'::jsonb),
  'and a short page reports none, rather than one that returns nothing'
);
select ok(
  (select (pg_temp.activity('d2000000-0000-0000-0000-000000000001')
     ->> 'as_of')::timestamptz > now() - interval '1 minute'),
  'the payload states when it was produced'
);

select * from finish();

rollback;
