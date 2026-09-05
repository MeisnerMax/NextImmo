begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back AUDIT-01 removes one read function and two indexes.
--
-- The interesting part of this rollback is what it must leave alone. The audit
-- table and its policy predate the read port by three phases and hold the only
-- record of every mutation this system has made; a revert that took any of
-- that with it would destroy evidence, not undo a feature.

select plan(10);

select hasnt_function('public', 'property_audit_events',
  'the read port is removed');
select is(
  (select count(*)::integer
   from pg_indexes
   where schemaname = 'public'
     and tablename = 'audit_events'
     and indexname in (
       'audit_events_entity_trail_idx',
       'audit_events_parent_entity_trail_idx'
     )),
  0,
  'and so are the two indexes it added'
);

-- The table, its append-only shape and its policy survive untouched.
select has_table('public', 'audit_events', 'the audit table survives');
select has_column('public', 'audit_events', 'old_values', 'old_values survives');
select has_column('public', 'audit_events', 'new_values', 'new_values survives');
select has_column(
  'public', 'audit_events', 'parent_entity_id',
  'the parent reference the trail read on survives'
);
select ok(
  (select count(*) > 0
   from pg_policies
   where schemaname = 'public'
     and tablename = 'audit_events'
     and policyname = 'audit_events_select_audit_read'),
  'the audit.read policy that predates this package is untouched'
);
select ok(
  (select relrowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public' and class.relname = 'audit_events'),
  'row level security stays on'
);

-- The package introduced no permission of its own, so none can linger, and
-- audit.read must still be the catalogue key it always was.
select is(
  (select count(*)::integer from public.permissions
   where key in ('audit.trail.read', 'property.audit.read')),
  0,
  'no audit-specific permission was ever introduced'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname like '%audit%'
     and function.prosecdef),
  0,
  'no other privileged audit function is left behind'
);

select * from finish();

rollback;
