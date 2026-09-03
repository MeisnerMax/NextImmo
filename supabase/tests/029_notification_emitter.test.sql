begin;

create extension if not exists pgtap with schema extensions;

-- NOTIFICATION-EMITTER-01 (B-2): the four V1 task events, emitted server-side
-- inside the task mutation (§6.3 E-T1/E-T2/E-T5/E-T6), with AS-1 self-notify
-- filtering and the AS-3 unread dedupe.
--
-- The RPCs run as the acting user (authenticated + JWT claims); every
-- assertion runs as postgres, because the fixture role deliberately holds NO
-- notification permission at all — the emitter must work without one (B11),
-- and RLS would otherwise hide the very rows under test.

select plan(35);

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from pg_enum
   join pg_type on pg_type.oid = pg_enum.enumtypid
   where pg_type.typname = 'document_link_entity_type'
     and pg_enum.enumlabel = 'task'),
  1,
  'the registry carries the task value'
);

select has_trigger('public', 'tasks', 'tasks_emit_notifications',
  'tasks emit their notification events');

select has_index('public', 'notifications', 'notifications_unread_dedupe_idx',
  'the AS-3 dedupe probe has its partial index');

select ok(
  (select pg_get_constraintdef(oid) ~ 'task' from pg_constraint
   where conname = 'tasks_entity_not_task_check'
     and conrelid = 'public.tasks'::regclass),
  'a task must not link a task'
);

-- The gate publishes the command context for same-transaction triggers.
select ok(
  (select pg_get_functiondef(function.oid) ~ 'neximmo.correlation_id'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'platform_command_gate'),
  'the command gate records the correlation id for the emitter'
);

-- ---------------------------------------------------------------------------
-- Fixture: manager M creates, editor Y takes over from editor X. All three
-- hold task.manage/task.read and NO notification permission.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ea000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b2-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b2-editor-x@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b2-editor-y@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'b2-a', 'B2 A');

insert into public.roles (id, workspace_id, key, name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'editor', 'Editor');

insert into public.permissions (id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'task.read', 'Task Read'),
  ('e3000000-0000-0000-0000-000000000002', 'task.manage', 'Task Manage');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', id
from public.permissions;

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'active'),
  ('e4000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'active'),
  ('e4000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001', 'active');

-- ---------------------------------------------------------------------------
-- E-T1 at creation, AS-1, replay safety
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"ea000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
set local role authenticated;

select is(
  public.create_task(
    'e1000000-0000-0000-0000-000000000001', 'Zähler ablesen',
    'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
    p_assigned_to => 'ea000000-0000-0000-0000-000000000002'
  ) ->> 'ok',
  'true',
  'manager creates a task assigned to X'
);

-- Replaying the exact same mutation must not emit again.
select is(
  public.create_task(
    'e1000000-0000-0000-0000-000000000001', 'Zähler ablesen',
    'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
    p_assigned_to => 'ea000000-0000-0000-0000-000000000002'
  ) ->> 'ok',
  'true',
  'the mutation replay still succeeds'
);

-- AS-1: self-assignment at creation notifies nobody.
select is(
  public.create_task(
    'e1000000-0000-0000-0000-000000000001', 'Eigenbeleg prüfen',
    'e5000000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-000000000002',
    p_assigned_to => 'ea000000-0000-0000-0000-000000000001'
  ) ->> 'ok',
  'true',
  'manager creates a self-assigned task'
);

reset role;

select is(
  (select count(*)::integer from public.notifications
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and recipient_user_id = 'ea000000-0000-0000-0000-000000000002'
     and kind = 'task.assigned'),
  1,
  'E-T1: the assignee is notified at creation, exactly once across the replay'
);

select is(
  (select notification.title from public.notifications as notification
   where notification.recipient_user_id = 'ea000000-0000-0000-0000-000000000002'
     and notification.kind = 'task.assigned'),
  'Zähler ablesen',
  'the notification carries the task title'
);

select is(
  (select notification.entity_type::text from public.notifications as notification
   where notification.recipient_user_id = 'ea000000-0000-0000-0000-000000000002'
     and notification.kind = 'task.assigned'),
  'task',
  'the notification addresses the task itself'
);

select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000001'),
  0,
  'AS-1: the acting user is never notified'
);

-- The emitter audits with the command's own correlation id, without spending
-- the unique (workspace, mutation_id) slot.
select is(
  (select audit.correlation_id from public.audit_events as audit
   where audit.action = 'notification.emitted'
     and audit.parent_entity_type = 'task'),
  'e6000000-0000-0000-0000-000000000001'::uuid,
  'the emission audit row carries the task command correlation id'
);
select is(
  (select audit.mutation_id from public.audit_events as audit
   where audit.action = 'notification.emitted'),
  null::uuid,
  'the emission audit row leaves the mutation slot to the task command'
);

-- The coarse inbox invalidation fires.
select is(
  (select count(*)::integer from public.domain_events
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and event_type = 'notification.fanned_out'),
  1,
  'the emission publishes the notification.read invalidation event'
);

-- ---------------------------------------------------------------------------
-- E-T2/E-T1 on reassignment; a plain edit stays silent
-- ---------------------------------------------------------------------------

set local role authenticated;

select is(
  public.update_task(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen'),
    1,
    'e5000000-0000-0000-0000-000000000003', 'e6000000-0000-0000-0000-000000000003',
    '{"assigned_to": "ea000000-0000-0000-0000-000000000003"}'::jsonb
  ) ->> 'ok',
  'true',
  'manager reassigns the task from X to Y'
);

select is(
  public.update_task(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen'),
    2,
    'e5000000-0000-0000-0000-000000000004', 'e6000000-0000-0000-0000-000000000004',
    '{"title": "Zähler ablesen (Haus Nord)"}'::jsonb
  ) ->> 'ok',
  'true',
  'a plain edit succeeds'
);

reset role;

select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000002'
     and kind = 'task.unassigned'),
  1,
  'E-T2: the previous assignee is told to stop'
);
select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000003'
     and kind = 'task.assigned'),
  1,
  'E-T1: the new assignee is told to start'
);
select is(
  (select count(*)::integer from public.notifications),
  3,
  'an edit without assignment or status change emits nothing'
);

-- ---------------------------------------------------------------------------
-- E-T5/E-T6 as the assignee, AS-3 unread dedupe
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"ea000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
set local role authenticated;

select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    3, 'in_progress',
    'e5000000-0000-0000-0000-000000000005', 'e6000000-0000-0000-0000-000000000005'
  ) ->> 'ok',
  'true',
  'Y starts working'
);
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    4, 'blocked',
    'e5000000-0000-0000-0000-000000000006', 'e6000000-0000-0000-0000-000000000006'
  ) ->> 'ok',
  'true',
  'Y blocks the task'
);
-- AS-3: unblock and re-block while the first task.blocked is still unread.
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    5, 'in_progress',
    'e5000000-0000-0000-0000-000000000007', 'e6000000-0000-0000-0000-000000000007'
  ) ->> 'ok', 'true', 'Y unblocks'
);
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    6, 'blocked',
    'e5000000-0000-0000-0000-000000000008', 'e6000000-0000-0000-0000-000000000008'
  ) ->> 'ok', 'true', 'Y blocks again'
);

reset role;

select is(
  (select count(*)::integer from public.notifications
   where kind in ('task.blocked', 'task.done')
     and recipient_user_id <> 'ea000000-0000-0000-0000-000000000001'),
  0,
  'status events go to the creator only, never a distribution list (AS-5)'
);
select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000001'
     and kind = 'task.blocked'),
  1,
  'E-T5 with AS-3: one unread task.blocked, the repeat is suppressed'
);

-- Reading the notification re-arms the triple.
set local request.jwt.claims = '{"sub":"ea000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
set local role authenticated;
select is(
  public.mark_notification_read(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.notifications
     where recipient_user_id = 'ea000000-0000-0000-0000-000000000001'
       and kind = 'task.blocked'),
    'e5000000-0000-0000-0000-000000000009', 'e6000000-0000-0000-0000-000000000009'
  ) ->> 'ok',
  'true',
  'the creator reads the blockade notice'
);

set local request.jwt.claims = '{"sub":"ea000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    7, 'in_progress',
    'e5000000-0000-0000-0000-00000000000a', 'e6000000-0000-0000-0000-00000000000a'
  ) ->> 'ok', 'true', 'Y unblocks once more'
);
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    8, 'blocked',
    'e5000000-0000-0000-0000-00000000000b', 'e6000000-0000-0000-0000-00000000000b'
  ) ->> 'ok', 'true', 'Y blocks a third time'
);
select is(
  public.transition_task_status(
    'e1000000-0000-0000-0000-000000000001',
    (select id from public.tasks where title = 'Zähler ablesen (Haus Nord)'),
    9, 'done',
    'e5000000-0000-0000-0000-00000000000c', 'e6000000-0000-0000-0000-00000000000c'
  ) ->> 'ok', 'true', 'Y finishes the task'
);

reset role;

select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000001'
     and kind = 'task.blocked'),
  2,
  'AS-3: after a read, a repeat is news again'
);
select is(
  (select count(*)::integer from public.notifications
   where recipient_user_id = 'ea000000-0000-0000-0000-000000000001'
     and kind = 'task.done'),
  1,
  'E-T6: the creator learns the task is done'
);

-- Every emission left its append-only trace with the mutation slot untouched.
select is(
  (select count(*)::integer from public.audit_events
   where action = 'notification.emitted' and mutation_id is not null),
  0,
  'no emission audit row ever claims a mutation id'
);
select is(
  (select count(*)::integer from public.audit_events
   where action = 'notification.emitted'),
  (select count(*)::integer from public.notifications),
  'every emitted notification has exactly one audit row'
);

-- A task must not link a task: the registry value exists for notifications,
-- not for task contexts. The client never offers it; a hand-crafted call
-- fails on the constraint.
set local request.jwt.claims = '{"sub":"ea000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
set local role authenticated;
select throws_ok(
  $$select public.create_task(
    'e1000000-0000-0000-0000-000000000001', 'Verbotener Link',
    'e5000000-0000-0000-0000-00000000000d', 'e6000000-0000-0000-0000-00000000000d',
    p_entity_type => 'task',
    p_entity_id => 'e5000000-0000-0000-0000-000000000099'
  )$$,
  '23514',
  null,
  'a task linking a task fails on tasks_entity_not_task_check'
);

reset role;
reset request.jwt.claims;

select * from finish();

rollback;
