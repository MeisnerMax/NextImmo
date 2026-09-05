begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-OVERVIEW-DATA-01: the server-authoritative property overview.
--
-- The point of this package is honesty about coverage, so that is what is
-- proven here:
--   * the gate order holds (auth, AAL2, entity-scoped property.read);
--   * every section is permission-scoped on its own -- a section the caller
--     may not read reports `available: false` and NO numbers, never `0`;
--   * the counts are the stored states of the right property, and a
--     neighbouring property never leaks into them;
--   * nothing derived is published: no rate, no score, no valuation figure.

select plan(40);

select has_function('public', 'property_overview',
  'the overview read exists');
select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_overview'),
  true,
  'property_overview is security definer'
);
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_overview'),
  's'::"char",
  'it is stable: a read, never a mutation'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_overview'
     and acl.grantee = 'anon'::regrole),
  0,
  'anon cannot call it'
);

-- ---------------------------------------------------------------------------
-- Fixture: one workspace, two properties (B is the leak canary), four actors
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ov-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ov-viewer@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ov-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'ov-a', 'OV A');

select private.seed_workspace_role_catalog('e1000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), 'e1000000-0000-0000-0000-000000000001', pairing.user_id, role.id, 'active'
from (values
  ('e2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('e2000000-0000-0000-0000-000000000002'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = 'e1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'Überblick-Haus', 'Sichtstr. 1', '10115', 'Berlin', 'de', 'residential', 3,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e5000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'Nachbar-Haus', 'Sichtstr. 2', '10115', 'Berlin', 'de', 'residential', 9,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

-- Property A: two units (one occupied, one vacant); property B: one unit that
-- must never be counted for A.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, vacancy_since,
  created_by, updated_by
) values
  ('e6000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'A-01', 'occupied', null,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e6000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'A-02', 'vacant', current_date,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e6000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000002', 'B-01', 'vacant', current_date,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

-- Two open tickets on A, one of them overdue; one on B.
-- The schema ties a terminal status to a resolved marker, so the closed
-- fixture ticket carries one.
insert into public.maintenance_tickets (
  id, workspace_id, property_id, title, status, priority, due_at, resolved_at,
  created_by, updated_by
) values
  ('e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'Heizung', 'new', 'urgent',
   now() - interval '2 days', null,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e7000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'Fenster', 'triage', 'normal',
   now() + interval '10 days', null,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e7000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'Erledigt', 'archived', 'normal', null,
   now() - interval '1 day',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e7000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000002', 'Nachbar-Ticket', 'new', 'urgent', null, null,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

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

create or replace function pg_temp.overview(
  p_user uuid,
  p_aal text default 'aal2',
  p_property uuid default 'e5000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, p_aal);
  v_result := public.property_overview(
    'e1000000-0000-0000-0000-000000000001', p_property
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
  (select public.property_overview(
     'e1000000-0000-0000-0000-000000000001',
     'e5000000-0000-0000-0000-000000000001'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001', 'aal1')
     -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000003')
     -> 'error' ->> 'code'),
  'forbidden',
  'a non-member is refused'
);
select is(
  (select pg_temp.overview(
     'e2000000-0000-0000-0000-000000000001', 'aal2',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown property is not found, not forbidden'
);

-- ---------------------------------------------------------------------------
-- The admin sees every section with real counts
-- ---------------------------------------------------------------------------

select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001') ->> 'ok'),
  'true',
  'an admin reads the overview'
);
select isnt(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' ->> 'as_of'),
  null,
  'the payload states its own freshness'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'property' ->> 'name'),
  'Überblick-Haus',
  'the identity belongs to the requested property'
);

select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'leasing' ->> 'units_total')::integer),
  2,
  'units are counted for this property only'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'leasing' ->> 'units_occupied')::integer),
  1,
  'occupied units come from the stored status'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'leasing' ->> 'units_vacant')::integer),
  1,
  'vacant units come from the stored status'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'leasing' ->> 'leases_active')::integer),
  0,
  'no lease exists yet, and that is reported as zero rather than omitted'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'maintenance' ->> 'tickets_open')::integer),
  2,
  'archived tickets are not open, and the neighbour is not counted'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'maintenance' ->> 'tickets_overdue')::integer),
  1,
  'overdue means a past due date on an open ticket'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'maintenance' ->> 'tickets_urgent_open')::integer),
  1,
  'urgent counts the stored priority'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001', 'aal2',
     'e5000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'maintenance' ->> 'tickets_open')::integer),
  1,
  'the neighbouring property reports its own ticket, not A''s'
);

-- ---------------------------------------------------------------------------
-- Coverage: a section the caller may not read carries no numbers
-- ---------------------------------------------------------------------------

-- The viewer bundle holds property.read, lease.read, task.read, document.read
-- and valuation.read, but neither maintenance.read nor capex.read.
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002') ->> 'ok'),
  'true',
  'a viewer reads the overview'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'maintenance' ->> 'available'),
  'false',
  'maintenance is unavailable without maintenance.read'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'maintenance' ->> 'tickets_open'),
  null,
  'an unavailable section reports NO number, not zero'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'maintenance' ->> 'permission'),
  'maintenance.read',
  'it names the capability it would need'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'capex' ->> 'available'),
  'false',
  'capex is unavailable without capex.read'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'leasing' ->> 'available'),
  'true',
  'leasing is available to the viewer, who holds lease.read'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'leasing' ->> 'units_total')::integer),
  2,
  'and it carries the same real numbers'
);

-- ---------------------------------------------------------------------------
-- Nothing derived is published
-- ---------------------------------------------------------------------------

select ok(
  (select not (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'leasing' ? 'occupancy_rate')),
  'no occupancy rate: that definition belongs to the lease roll projection'
);
select ok(
  (select not (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'valuation' ? 'value')),
  'no valuation figure: which number is the value is a METHOD-GOV-01 decision'
);
select ok(
  (select not (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' ? 'financial')),
  'no financial section: it waits for P2-D08'
);
select ok(
  (select not (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' ? 'activity')),
  'no activity section: it waits for the AUDIT-01 read port'
);

-- ---------------------------------------------------------------------------
-- Attention: the server picks it, scores it and orders it
-- ---------------------------------------------------------------------------

-- Property A carries exactly three attention-worthy facts: one overdue
-- ticket (critical), one urgent open ticket (warning) and one vacant unit
-- (info). Nothing else in the fixture is late, blocked or escalated.
select is(
  (select jsonb_array_length(pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'attention')),
  3,
  'attention lists exactly the facts that are late, urgent or standing'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'attention' -> 0 ->> 'type'),
  'tickets_overdue',
  'the most severe fact leads'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'attention' -> 0 ->> 'severity'),
  'critical',
  'severity is assigned by the server'
);
select is(
  (select (pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'attention' -> 0 ->> 'count')::integer),
  1,
  'the entry carries the count it stands for'
);
select is(
  (select pg_temp.overview('e2000000-0000-0000-0000-000000000001')
     -> 'overview' -> 'attention' -> 0 ->> 'domain'),
  'operations',
  'and the domain that owns the drilldown'
);
select is(
  (select array_agg(entry ->> 'severity' order by position)
   from jsonb_array_elements(
     pg_temp.overview('e2000000-0000-0000-0000-000000000001')
       -> 'overview' -> 'attention'
   ) with ordinality as ordered(entry, position)),
  array['critical', 'warning', 'info']::text[],
  'the order is the server''s: critical before warning before info'
);
select ok(
  (select bool_and(not (entry ? 'score'))
   from jsonb_array_elements(
     pg_temp.overview('e2000000-0000-0000-0000-000000000001')
       -> 'overview' -> 'attention'
   ) as entry),
  'no score travels with an entry: the client must not re-rank it'
);

-- The viewer cannot read maintenance, so the overdue ticket must not reach
-- them through the attention list either -- that would disclose the very
-- record the section already withholds.
select is(
  (select jsonb_array_length(pg_temp.overview('e2000000-0000-0000-0000-000000000002')
     -> 'overview' -> 'attention')),
  1,
  'the viewer sees attention only from the sections they may read'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.overview('e2000000-0000-0000-0000-000000000002')
       -> 'overview' -> 'attention'
   ) as entry
   where entry ->> 'type' like 'tickets%'),
  0,
  'the withheld maintenance record does not leak through attention'
);

-- The read leaves no trace: it is a read, and reads write no audit rows.
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and entity_type = 'property'),
  0,
  'reading the overview writes no audit event'
);

select * from finish();

rollback;
