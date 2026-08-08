begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

-- The tasks/notifications aggregates are removed by the down path…
select hasnt_table('public', 'tasks', 'tasks is removed by the down path');
select hasnt_table('public', 'notifications', 'notifications is removed by the down path');

select is(
  (select count(*)::integer from pg_type t
   join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typname in ('task_status', 'task_priority')),
  0,
  'the task enums are removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'create_task', 'update_task', 'transition_task_status',
       'create_notification', 'mark_notification_read'
     )),
  0,
  'every task/notification RPC is removed'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'platform_command_gate', 'claim_platform_mutation', 'finish_platform_mutation',
       'task_snapshot', 'notification_snapshot', 'task_status_can_transition'
     )),
  0,
  'every platform helper is removed'
);

-- …while the increment-1 envelope infrastructure it publishes through survives.
select has_table(
  'public', 'domain_events',
  'the P2-D04 increment-1 outbox survives the increment-2 rollback'
);

select * from finish();

rollback;
