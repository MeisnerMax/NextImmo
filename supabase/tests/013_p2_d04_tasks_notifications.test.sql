begin;

create extension if not exists pgtap with schema extensions;

select plan(57);

-- ---------------------------------------------------------------------------
-- Schema, RLS, grants
-- ---------------------------------------------------------------------------

select has_table('public', 'tasks', 'tasks exists');
select has_table('public', 'notifications', 'notifications exists');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.tasks'::regclass),
  'tasks has RLS enabled and forced'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.notifications'::regclass),
  'notifications has RLS enabled and forced'
);
select policies_are('public', 'tasks', array['tasks_select_task_read'], 'tasks has one scoped select policy');
select policies_are(
  'public', 'notifications', array['notifications_select_own_or_read'],
  'notifications has one recipient-or-read select policy'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public' and tablename in ('tasks', 'notifications')
     and cmd in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'no write policy on tasks or notifications: mutation is RPC-only'
);
select is(
  (select count(*)::integer from information_schema.table_privileges
   where table_schema = 'public' and table_name in ('tasks', 'notifications')
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'no direct write grant on tasks or notifications'
);

select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name in (
       'platform_command_gate', 'claim_platform_mutation', 'finish_platform_mutation',
       'task_snapshot', 'notification_snapshot', 'task_status_can_transition'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated')),
  0,
  'no platform helper is executable by PUBLIC, anon or authenticated'
);
select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_task', 'update_task', 'transition_task_status',
       'create_notification', 'mark_notification_read'
     )
     and grantee = 'authenticated' and privilege_type = 'EXECUTE'),
  5,
  'authenticated can execute exactly the five platform RPCs'
);

-- The AGG-019 ledger constraint.
select ok(
  (select indisunique from pg_index
   where indexrelid = 'public.tasks_generated_key_unique'::regclass),
  'tasks_generated_key_unique enforces one live task per generated key'
);

-- STM-012 matrix helper (checked here as superuser; authenticated has no grant).
select is(private.task_status_can_transition('open', 'in_progress'), true, 'open -> in_progress allowed');
select is(private.task_status_can_transition('open', 'done'), false, 'open -> done skipped is not allowed');
select is(private.task_status_can_transition('done', 'open'), true, 'done -> open reopen allowed');
select is(private.task_status_can_transition('archived', 'open'), false, 'archived is terminal');

-- ---------------------------------------------------------------------------
-- Fixture: one workspace, a manager (task+notification manage/read) and a
-- plain member (workspace.read only). A second workspace for isolation.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ca000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04b-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04b-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('c1000000-0000-0000-0000-000000000001', 'd04b-a', 'D04B A'),
  ('c1000000-0000-0000-0000-000000000002', 'd04b-b', 'D04B B');

insert into public.roles (id, workspace_id, key, name) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'member', 'Member');

insert into public.permissions (id, key, name) values
  ('c3000000-0000-0000-0000-000000000001', 'task.read', 'Task Read'),
  ('c3000000-0000-0000-0000-000000000002', 'task.manage', 'Task Manage'),
  ('c3000000-0000-0000-0000-000000000003', 'notification.read', 'Notification Read'),
  ('c3000000-0000-0000-0000-000000000004', 'notification.manage', 'Notification Manage'),
  ('c3000000-0000-0000-0000-000000000005', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', id
from public.permissions where key in ('task.read', 'task.manage', 'notification.read', 'notification.manage', 'workspace.read');
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', id
from public.permissions where key = 'workspace.read';

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('c4000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'active'),
  ('c4000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000002', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"ca000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- ---------------------------------------------------------------------------
-- create_task and the two idempotency layers
-- ---------------------------------------------------------------------------

select is(
  public.create_task(
    'c1000000-0000-0000-0000-000000000001', 'Heizung prüfen',
    'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001',
    p_priority => 'high'
  ) ->> 'ok',
  'true',
  'a manager creates a task'
);
select is(
  (select status::text from public.tasks where title = 'Heizung prüfen'),
  'open',
  'a new task starts open (STM-012)'
);

-- mutation_id replay: identical call returns the same task, no duplicate.
select is(
  (public.create_task(
    'c1000000-0000-0000-0000-000000000001', 'Heizung prüfen',
    'c5000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001',
    p_priority => 'high'
  ) -> 'entity' ->> 'id'),
  (select id::text from public.tasks where title = 'Heizung prüfen'),
  'replaying the same mutation_id returns the same task'
);
select is(
  (select count(*)::integer from public.tasks where title = 'Heizung prüfen'),
  1,
  'the mutation_id replay created no duplicate'
);

-- AGG-019: generated_key idempotency across different mutation_ids.
select is(
  public.create_task(
    'c1000000-0000-0000-0000-000000000001', 'Wartung Q3',
    'c5000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-000000000002',
    p_generated_key => 'maint:prop-1:2026-Q3'
  ) ->> 'ok',
  'true',
  'a recurring task is generated with a business key'
);
select is(
  (public.create_task(
    'c1000000-0000-0000-0000-000000000001', 'Wartung Q3 (erneut)',
    'c5000000-0000-0000-0000-000000000003', 'c6000000-0000-0000-0000-000000000003',
    p_generated_key => 'maint:prop-1:2026-Q3'
  ) -> 'entity' ->> 'id'),
  (select id::text from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
  'AGG-019: a fresh mutation_id with the same generated_key returns the existing task'
);
select is(
  (select count(*)::integer from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
  1,
  'AGG-019: no duplicate for a repeated generated_key'
);

-- ---------------------------------------------------------------------------
-- STM-012 transitions
-- ---------------------------------------------------------------------------

-- Drive one task through the lifecycle.
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    1, 'in_progress',
    'c5000000-0000-0000-0000-000000000010', 'c6000000-0000-0000-0000-000000000010'
  ) -> 'entity' ->> 'status',
  'in_progress',
  'open -> in_progress transitions'
);
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    2, 'done',
    'c5000000-0000-0000-0000-000000000011', 'c6000000-0000-0000-0000-000000000011'
  ) -> 'entity' ->> 'status',
  'done',
  'in_progress -> done transitions'
);
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    3, 'done',
    'c5000000-0000-0000-0000-000000000012', 'c6000000-0000-0000-0000-000000000012'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a no-op transition to the same status is rejected'
);
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    3, 'blocked',
    'c5000000-0000-0000-0000-000000000013', 'c6000000-0000-0000-0000-000000000013'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'done -> blocked is rejected by the matrix'
);
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    3, 'archived',
    'c5000000-0000-0000-0000-000000000014', 'c6000000-0000-0000-0000-000000000014'
  ) -> 'entity' ->> 'status',
  'archived',
  'done -> archived transitions'
);
select ok(
  (select archived_at is not null from public.tasks where title = 'Heizung prüfen'),
  'archiving stamps archived_at'
);
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Heizung prüfen'),
    4, 'open',
    'c5000000-0000-0000-0000-000000000015', 'c6000000-0000-0000-0000-000000000015'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'an archived task cannot be revived (terminal)'
);

-- Stale version conflict carries the current entity.
select is(
  public.transition_task_status(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
    99, 'in_progress',
    'c5000000-0000-0000-0000-000000000016', 'c6000000-0000-0000-0000-000000000016'
  ) -> 'error' ->> 'code',
  'version_conflict',
  'a stale expected_version is a version_conflict'
);

-- update_task
select is(
  public.update_task(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
    1, 'c5000000-0000-0000-0000-000000000017', 'c6000000-0000-0000-0000-000000000017',
    jsonb_build_object('assigned_to', 'ca000000-0000-0000-0000-000000000002', 'priority', 'high')
  ) -> 'entity' ->> 'assigned_to',
  'ca000000-0000-0000-0000-000000000002',
  'a task is reassigned to an active member'
);
select is(
  public.update_task(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
    2, 'c5000000-0000-0000-0000-000000000018', 'c6000000-0000-0000-0000-000000000018',
    jsonb_build_object('assigned_to', 'ca000000-0000-0000-0000-000000000009')
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a task cannot be assigned to a non-member'
);
select is(
  public.update_task(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where generated_key = 'maint:prop-1:2026-Q3'),
    2, 'c5000000-0000-0000-0000-000000000019', 'c6000000-0000-0000-0000-000000000019',
    jsonb_build_object('status', 'done')
  ) -> 'error' ->> 'code',
  'validation_failed',
  'update_task refuses to move status: that is the state machine only'
);

-- ---------------------------------------------------------------------------
-- Notification fan-out
-- ---------------------------------------------------------------------------

select is(
  (public.create_notification(
    'c1000000-0000-0000-0000-000000000001',
    array['ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002']::uuid[],
    'task.assigned', 'Neue Aufgabe',
    'c5000000-0000-0000-0000-000000000020', 'c6000000-0000-0000-0000-000000000020'
  ) -> 'entity' ->> 'recipient_count'),
  '2',
  'one fan-out call reports two recipients'
);
select is(
  (select count(*)::integer from public.notifications where kind = 'task.assigned'),
  2,
  'fan-out created one row per recipient'
);
select is(
  (select count(distinct recipient_user_id)::integer from public.notifications where kind = 'task.assigned'),
  2,
  'each recipient got their own notification'
);

-- Fan-out replay: same mutation_id does not double-insert.
select is(
  public.create_notification(
    'c1000000-0000-0000-0000-000000000001',
    array['ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002']::uuid[],
    'task.assigned', 'Neue Aufgabe',
    'c5000000-0000-0000-0000-000000000020', 'c6000000-0000-0000-0000-000000000020'
  ) ->> 'ok',
  'true',
  'replaying the fan-out mutation succeeds'
);
select is(
  (select count(*)::integer from public.notifications where kind = 'task.assigned'),
  2,
  'the fan-out replay created no extra rows'
);

-- Capture both recipients' notification ids while the manager (notification.read)
-- can see them, so the cross-recipient test below can reference a row the
-- recipient predicate — and RLS — would otherwise hide.
create temporary table _notif_ids on commit drop as
select recipient_user_id, id from public.notifications where kind = 'task.assigned';

select is(
  public.create_notification(
    'c1000000-0000-0000-0000-000000000001', array[]::uuid[], 'task.assigned', 'Leer',
    'c5000000-0000-0000-0000-000000000021', 'c6000000-0000-0000-0000-000000000021'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'an empty recipient set is rejected, not a silent success'
);
select is(
  public.create_notification(
    'c1000000-0000-0000-0000-000000000001',
    array['ca000000-0000-0000-0000-000000000009']::uuid[], 'task.assigned', 'Fremd',
    'c5000000-0000-0000-0000-000000000022', 'c6000000-0000-0000-0000-000000000022'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a notification to a non-member is rejected'
);

-- ---------------------------------------------------------------------------
-- mark_notification_read: recipient scoping and idempotency
-- ---------------------------------------------------------------------------

-- The member marks their own read.
set local request.jwt.claims = '{"sub":"ca000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
select ok(
  (public.mark_notification_read(
    'c1000000-0000-0000-0000-000000000001',
    (select id from public.notifications where recipient_user_id = 'ca000000-0000-0000-0000-000000000002' and kind = 'task.assigned'),
    'c5000000-0000-0000-0000-000000000030', 'c6000000-0000-0000-0000-000000000030'
  ) -> 'entity' ->> 'read_at') is not null,
  'a recipient marks their own notification read'
);
-- A member cannot mark someone else's notification read. The id comes from the
-- out-of-band capture (RLS would hide it), and the recipient predicate in the
-- RPC then reads it as not_found rather than confirming it exists.
select is(
  public.mark_notification_read(
    'c1000000-0000-0000-0000-000000000001',
    (select id from _notif_ids where recipient_user_id = 'ca000000-0000-0000-0000-000000000001'),
    'c5000000-0000-0000-0000-000000000031', 'c6000000-0000-0000-0000-000000000031'
  ) -> 'error' ->> 'code',
  'not_found',
  'a member cannot mark another member''s notification read'
);

-- ---------------------------------------------------------------------------
-- Read scoping
-- ---------------------------------------------------------------------------

-- The plain member (workspace.read only) sees only their own notifications,
-- and no tasks at all.
select is(
  (select count(*)::integer from public.notifications),
  1,
  'a member without notification.read sees only their own notifications'
);
select is(
  (select count(*)::integer from public.tasks),
  0,
  'a member without task.read sees no tasks'
);

-- The manager (notification.read) sees the whole feed.
set local request.jwt.claims = '{"sub":"ca000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
select ok(
  (select count(*) from public.notifications) >= 2,
  'a holder of notification.read sees the whole feed'
);
select ok(
  (select count(*) from public.tasks) >= 2,
  'a holder of task.read sees the tasks'
);

-- Permission denial for a manage-less caller.
set local request.jwt.claims = '{"sub":"ca000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
select is(
  public.create_task(
    'c1000000-0000-0000-0000-000000000001', 'Sollte scheitern',
    'c5000000-0000-0000-0000-000000000040', 'c6000000-0000-0000-0000-000000000040'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a member without task.manage cannot create a task'
);
select is(
  public.create_notification(
    'c1000000-0000-0000-0000-000000000001',
    array['ca000000-0000-0000-0000-000000000001']::uuid[], 'x.y', 'nope',
    'c5000000-0000-0000-0000-000000000041', 'c6000000-0000-0000-0000-000000000041'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a member without notification.manage cannot fan out'
);

-- ---------------------------------------------------------------------------
-- Append-only audit and protected columns
-- ---------------------------------------------------------------------------

-- Assert audit as superuser: the manager fixture holds no audit.read, so the
-- audit_events RLS policy correctly hides the rows from it.
reset role;
reset request.jwt.claims;
select ok(
  (select count(*) from public.audit_events
   where entity_type = 'task' and action = 'task.create') >= 1,
  'task creation writes an append-only audit row'
);
select ok(
  (select count(*) from public.audit_events
   where entity_type = 'notification_batch' and action = 'notification.fan_out') = 1,
  'a fan-out writes a single batch audit row'
);

-- generated_key is a protected column: the trigger rejects any rewrite of the
-- AGG-019 ledger key.
select throws_ok(
  $$update public.tasks set generated_key = 'tampered'
    where generated_key = 'maint:prop-1:2026-Q3'$$,
  '23000',
  null,
  'generated_key is a protected column: the AGG-019 ledger key cannot be rewritten'
);

-- ---------------------------------------------------------------------------
-- Domain events published through the increment-1 helper
-- ---------------------------------------------------------------------------

select ok(
  (select count(*) from public.domain_events where event_type = 'task.created') >= 1,
  'creating a task publishes task.created through publish_domain_event'
);
select ok(
  (select count(*) from public.domain_events where event_type = 'task.status_changed') >= 1,
  'a transition publishes task.status_changed'
);
select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'notification.fanned_out' and required_permission = 'notification.read'),
  1,
  'a fan-out publishes exactly one coarse, permission-scoped envelope'
);

-- ---------------------------------------------------------------------------
-- Two-workspace isolation and anon denial
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"ca000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
select is(
  public.create_task(
    'c1000000-0000-0000-0000-000000000002', 'Fremder Workspace',
    'c5000000-0000-0000-0000-000000000050', 'c6000000-0000-0000-0000-000000000050'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a manager cannot create a task in a workspace it does not belong to'
);
reset role;
reset request.jwt.claims;

set local role anon;
select throws_ok(
  $$select count(*) from public.tasks$$, '42501', null, 'anon cannot read tasks'
);
select throws_ok(
  $$select count(*) from public.notifications$$, '42501', null, 'anon cannot read notifications'
);
reset role;

select * from finish();

rollback;
