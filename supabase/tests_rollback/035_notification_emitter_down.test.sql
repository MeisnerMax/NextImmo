begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back NOTIFICATION-EMITTER-01 must remove the emitter trigger, both
-- helpers, the dedupe index, the no-self-linking constraint and the registry's
-- task value, and must restore the command gate to its silent P2-D04 shape —
-- while leaving everything the emitter merely used (notifications,
-- audit_events, publish_domain_event, the TASK-QUERY-01 roll-up) untouched.

select plan(9);

select is(
  (select count(*)::integer
   from pg_enum
   join pg_type on pg_type.oid = pg_enum.enumtypid
   where pg_type.typname = 'document_link_entity_type'
     and pg_enum.enumlabel = 'task'),
  0,
  'the registry no longer carries the task value'
);

select hasnt_function('private', 'emit_task_notification',
  'the emitter helper is removed');
select hasnt_function('private', 'tasks_emit_notifications',
  'the emitter trigger function is removed');

select is(
  (select count(*)::integer from pg_trigger
   where tgname = 'tasks_emit_notifications'),
  0,
  'the emitter trigger is removed'
);

select is(
  (select count(*)::integer from pg_indexes
   where schemaname = 'public'
     and indexname = 'notifications_unread_dedupe_idx'),
  0,
  'the dedupe index is removed'
);

select is(
  (select count(*)::integer from pg_constraint
   where conname = 'tasks_entity_not_task_check'),
  0,
  'the no-self-linking guard is removed'
);

select ok(
  (select pg_get_functiondef(function.oid) !~ 'neximmo'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'platform_command_gate'),
  'the command gate no longer publishes emitter context'
);

-- The surfaces the emitter wrote to predate it and stay.
select has_table('public', 'notifications', 'notifications survive');

-- The TASK-QUERY-01 roll-up (one migration earlier) is untouched.
select has_column('public', 'tasks', 'property_id',
  'the B-1 roll-up survives the B-2 rollback');

select * from finish();

rollback;
