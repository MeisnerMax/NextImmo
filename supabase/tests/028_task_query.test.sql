begin;

create extension if not exists pgtap with schema extensions;

-- TASK-QUERY-01 (B-1): the property roll-up on tasks, the count_tasks KPI RPC
-- and the search_index projection for the task-linkable sources.

select plan(51);

-- ---------------------------------------------------------------------------
-- Schema: the roll-up column, its guards and its indexes
-- ---------------------------------------------------------------------------

select has_column('public', 'tasks', 'property_id', 'tasks carries the property roll-up');
select col_type_is('public', 'tasks', 'property_id', 'uuid', 'the roll-up is a uuid');
select col_is_null('public', 'tasks', 'property_id', 'the roll-up is nullable (unlinked tasks)');

-- restrict, like every other property_id FK in the schema — set null would be
-- rejected by the protected-columns trigger anyway.
select is(
  (select confdeltype::text from pg_constraint
   where conname = 'tasks_property_id_fkey' and conrelid = 'public.tasks'::regclass),
  'r',
  'the roll-up FK restricts property deletion'
);

select has_index('public', 'tasks', 'tasks_property_idx', 'the roll-up filter index exists');
select has_index('public', 'tasks', 'tasks_due_idx', 'the due-sort keyset index exists');
select ok(
  (select indexdef like '%WHERE%due_at IS NOT NULL%' from pg_indexes
   where schemaname = 'public' and indexname = 'tasks_due_idx'),
  'the due-sort index is partial: tasks without a due date are a separate bucket'
);

select has_function('private', 'task_property_rollup',
  'the roll-up resolver exists');
select has_trigger('public', 'tasks', 'tasks_property_rollup', 'tasks compute the roll-up on insert');

-- count_tasks: reachable by authenticated, closed to anon and PUBLIC.
select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'public' and routine_name = 'count_tasks'
     and grantee = 'authenticated' and privilege_type = 'EXECUTE'),
  1,
  'authenticated can execute count_tasks'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   cross join lateral aclexplode(function.proacl) as acl
   where function.proname = 'count_tasks'
     and acl.privilege_type = 'EXECUTE'
     and acl.grantee in (0, 'anon'::regrole)),
  0,
  'neither anon nor PUBLIC can execute count_tasks'
);

-- The six projection triggers.
select has_trigger('public', 'properties', 'properties_search_index_sync', 'properties project into the search index');
select has_trigger('public', 'units', 'units_search_index_sync', 'units project into the search index');
select has_trigger('public', 'leases', 'leases_search_index_sync', 'leases project into the search index');
select has_trigger('public', 'parties', 'parties_search_index_sync', 'parties project into the search index');
select has_trigger('public', 'maintenance_tickets', 'maintenance_tickets_search_index_sync', 'tickets project into the search index');
select has_trigger('public', 'capex_projects', 'capex_projects_search_index_sync', 'capex projects project into the search index');

-- ---------------------------------------------------------------------------
-- Fixture: workspace A with a manager (task.*, search.read) and a plain
-- member (workspace.read); workspace B for isolation. One property with one
-- unit, one party.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b1-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('da000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b1-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('d1000000-0000-0000-0000-000000000001', 'b1-a', 'B1 A'),
  ('d1000000-0000-0000-0000-000000000002', 'b1-b', 'B1 B');

insert into public.roles (id, workspace_id, key, name) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'member', 'Member');

insert into public.permissions (id, key, name) values
  ('d3000000-0000-0000-0000-000000000001', 'task.read', 'Task Read'),
  ('d3000000-0000-0000-0000-000000000002', 'task.manage', 'Task Manage'),
  ('d3000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read'),
  ('d3000000-0000-0000-0000-000000000004', 'search.read', 'Search Read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'd1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', id
from public.permissions where key in ('task.read', 'task.manage', 'workspace.read', 'search.read');
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'd1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002', id
from public.permissions where key = 'workspace.read';

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('d4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'active'),
  ('d4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('d5000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'Haus Nord', 'Nordstr. 1', '10115', 'Berlin', 'de', 'residential',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  ('d5000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002',
   'Fremdes Haus', 'Weitweg 9', '20095', 'Hamburg', 'de', 'residential',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

insert into public.units (id, workspace_id, property_id, unit_code, created_by, updated_by) values
  ('d6000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'd5000000-0000-0000-0000-000000000001', 'WE 01',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001'),
  ('d6000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002',
   'd5000000-0000-0000-0000-000000000002', 'WE B1',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

insert into public.parties (id, workspace_id, party_type, display_name, created_by, updated_by) values
  ('d7000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'person', 'Max Mieter',
   'da000000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- The projection: fixture inserts already ran through the triggers
-- ---------------------------------------------------------------------------

select is(
  (select title from public.search_index
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and entity_type = 'property' and entity_id = 'd5000000-0000-0000-0000-000000000001'),
  'Haus Nord',
  'a property projects its name'
);
select is(
  (select title from public.search_index
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and entity_type = 'unit' and entity_id = 'd6000000-0000-0000-0000-000000000001'),
  'WE 01',
  'a unit projects its code'
);
select is(
  (select title from public.search_index
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and entity_type = 'party' and entity_id = 'd7000000-0000-0000-0000-000000000001'),
  'Max Mieter',
  'a party projects its display name'
);

-- A rename re-projects.
update public.properties set name = 'Haus Nord (saniert)'
where id = 'd5000000-0000-0000-0000-000000000001';
select is(
  (select title from public.search_index
   where entity_type = 'property' and entity_id = 'd5000000-0000-0000-0000-000000000001'),
  'Haus Nord (saniert)',
  'a property rename re-projects the title'
);

-- A retired party leaves the index (merge implies deleted_at per the parties
-- constraint).
update public.parties
set deleted_at = now()
where id = 'd7000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::integer from public.search_index
   where entity_type = 'party' and entity_id = 'd7000000-0000-0000-0000-000000000001'),
  0,
  'a soft-deleted party is discarded from the index'
);

-- ---------------------------------------------------------------------------
-- The roll-up, driven through the real RPC as the manager
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"da000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'Dach prüfen',
    'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
    p_entity_type => 'property', p_entity_id => 'd5000000-0000-0000-0000-000000000001',
    p_due_at => '2026-09-10T09:00:00Z'
  ) -> 'entity' ->> 'property_id',
  'd5000000-0000-0000-0000-000000000001',
  'a property-linked task rolls up to the property itself (and the snapshot carries it)'
);

select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'Zähler ablesen WE 01',
    'e5000000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-000000000002',
    p_entity_type => 'unit', p_entity_id => 'd6000000-0000-0000-0000-000000000001',
    p_assigned_to => 'da000000-0000-0000-0000-000000000002',
    p_due_at => '2026-09-20T09:00:00Z'
  ) -> 'entity' ->> 'property_id',
  'd5000000-0000-0000-0000-000000000001',
  'a unit-linked task rolls up to the parent property'
);

select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'Ablage sortieren',
    'e5000000-0000-0000-0000-000000000003', 'e6000000-0000-0000-0000-000000000003'
  ) -> 'entity' ->> 'property_id',
  null::text,
  'an unlinked task carries no roll-up'
);

-- A link into another workspace must not leak that workspace's property id.
select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'Fremde Einheit',
    'e5000000-0000-0000-0000-000000000004', 'e6000000-0000-0000-0000-000000000004',
    p_entity_type => 'unit', p_entity_id => 'd6000000-0000-0000-0000-000000000002'
  ) -> 'entity' ->> 'property_id',
  null::text,
  'a foreign-workspace entity rolls up to null, never to a foreign property'
);

-- Titles for the escaping test.
select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'A_B Sonderfall',
    'e5000000-0000-0000-0000-000000000005', 'e6000000-0000-0000-0000-000000000005'
  ) ->> 'ok', 'true', 'escape fixture task A_B'
);
select is(
  public.create_task(
    'd1000000-0000-0000-0000-000000000001', 'AxB Sonderfall',
    'e5000000-0000-0000-0000-000000000006', 'e6000000-0000-0000-0000-000000000006'
  ) ->> 'ok', 'true', 'escape fixture task AxB'
);

-- One task leaves `open` so the status filter has something to distinguish.
select is(
  public.transition_task_status(
    'd1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Ablage sortieren'),
    1, 'in_progress',
    'e5000000-0000-0000-0000-000000000007', 'e6000000-0000-0000-0000-000000000007'
  ) -> 'entity' ->> 'status',
  'in_progress',
  'fixture transition to in_progress'
);

reset role;
reset request.jwt.claims;

-- The roll-up is server-owned: even a definer path must not move it.
select throws_ok(
  $$update public.tasks set property_id = null
    where title = 'Dach prüfen'$$,
  '23000',
  'property_id is immutable on public.tasks',
  'the roll-up column is protected against updates'
);

-- ---------------------------------------------------------------------------
-- count_tasks: semantics mirror the list read
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"da000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

select is(
  public.count_tasks('d1000000-0000-0000-0000-000000000001') -> 'entity' ->> 'count',
  '6',
  'the unfiltered count sees all six live tasks'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_statuses => array['open']
  ) -> 'entity' ->> 'count',
  '5',
  'the status filter takes several values'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_statuses => array['open', 'in_progress']
  ) -> 'entity' ->> 'count',
  '6',
  'a multi-status filter is a union'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_assigned_to => 'da000000-0000-0000-0000-000000000002'
  ) -> 'entity' ->> 'count',
  '1',
  'the assignee filter counts one queue'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_unassigned_only => true
  ) -> 'entity' ->> 'count',
  '5',
  'unassigned-only counts the complement'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_due_from => '2026-09-05T00:00:00Z',
    p_due_until => '2026-09-15T00:00:00Z'
  ) -> 'entity' ->> 'count',
  '1',
  'the due range is half-open: from inclusive, until exclusive'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_without_due => true
  ) -> 'entity' ->> 'count',
  '4',
  'without-due counts the no-date bucket'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_property_id => 'd5000000-0000-0000-0000-000000000001'
  ) -> 'entity' ->> 'count',
  '2',
  'the property filter uses the roll-up: the property task and the unit task'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_entity_type => 'unit', p_entity_id => 'd6000000-0000-0000-0000-000000000001'
  ) -> 'entity' ->> 'count',
  '1',
  'the entity filter scopes to one workflow entity'
);

select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_title_query => 'A_B'
  ) -> 'entity' ->> 'count',
  '1',
  'ilike wildcards in the title query are escaped: A_B does not match AxB'
);

-- Validation refusals.
select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_statuses => array['open', 'not-a-status']
  ) -> 'error' ->> 'field',
  'status',
  'an unknown status value is a validation failure, not a cast error'
);
select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_without_due => true, p_due_from => '2026-09-05T00:00:00Z'
  ) -> 'error' ->> 'field',
  'due_at',
  'without-due and a due range are mutually exclusive'
);
select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_assigned_to => 'da000000-0000-0000-0000-000000000002', p_unassigned_only => true
  ) -> 'error' ->> 'field',
  'assigned_to',
  'an assignee filter and unassigned-only are mutually exclusive'
);
select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_entity_type => 'unit'
  ) -> 'error' ->> 'field',
  'entity_type',
  'an entity filter needs both a type and an id'
);
select is(
  public.count_tasks(
    'd1000000-0000-0000-0000-000000000001',
    p_entity_type => 'no_such_type', p_entity_id => 'd6000000-0000-0000-0000-000000000001'
  ) -> 'error' ->> 'field',
  'entity_type',
  'an unregistered entity type is a validation failure'
);

-- The manager can resolve the projected names through the client read surface.
select is(
  (select count(*)::integer from public.search_index
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'
     and entity_id in ('d5000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001')),
  2,
  'search.read resolves the property and unit names for the task center'
);

-- Cross-workspace: membership in A grants nothing in B.
select is(
  public.count_tasks('d1000000-0000-0000-0000-000000000002') -> 'error' ->> 'code',
  'forbidden',
  'counting a foreign workspace is forbidden'
);

-- The member without task.read is refused — the count can never disagree with
-- the list the caller is not allowed to read.
set local request.jwt.claims = '{"sub":"da000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
select is(
  public.count_tasks('d1000000-0000-0000-0000-000000000001') -> 'error' ->> 'code',
  'forbidden',
  'a member without task.read cannot count tasks'
);
select is(
  (select count(*)::integer from public.search_index
   where workspace_id = 'd1000000-0000-0000-0000-000000000001'),
  0,
  'a member without search.read resolves no names'
);

-- DEC-025: aal1 stays outside the business surface, count included.
set local request.jwt.claims = '{"sub":"da000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';
select is(
  public.count_tasks('d1000000-0000-0000-0000-000000000001') -> 'error' ->> 'code',
  'forbidden',
  'an aal1 session cannot count tasks'
);

-- No identity, no answer.
set local request.jwt.claims = '{"role":"authenticated","aal":"aal2"}';
select is(
  public.count_tasks('d1000000-0000-0000-0000-000000000001') -> 'error' ->> 'message',
  'Authentication required',
  'an identity-less caller is refused before any gate'
);

reset role;
reset request.jwt.claims;

select * from finish();

rollback;
