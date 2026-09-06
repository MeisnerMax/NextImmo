begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-ASOF-01b returns three functions to their previous
-- bodies and narrows one CHECK constraint back to six signal types.
--
-- Like its predecessor this package creates no object, so there is nothing
-- whose absence proves the revert except the constraint value itself. What the
-- assertions establish is that both defects are back and that nothing else
-- moved: the summary asks about status alone again, the expiry ladder bounds
-- itself at today again, and the tables belong to P2-D05/P2-D05a as before.
--
-- One thing this rollback must NOT do is disturb the AAL rework: the current
-- `public.operations_signals` comes from `20260812100000`, and reverting to it
-- has to leave that migration's permission ordering in place.

select plan(12);

-- The signal type is gone from both places that knew it.
select is(
  (select count(*)::integer
   from pg_constraint
   where conrelid = 'public.operations_signal_states'::regclass
     and conname = 'operations_signal_states_type_check'
     and pg_get_constraintdef(oid) like '%lease_expired_open%'),
  0,
  'the table constraint no longer accepts the new signal type'
);
select is(
  (select count(*)::integer
   from pg_constraint
   where conrelid = 'public.operations_signal_states'::regclass
     and conname = 'operations_signal_states_type_check'),
  1,
  'and the constraint still exists rather than having been dropped'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_expired_open%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'update_operations_signal_status'),
  'the acknowledgement validator does not know it either'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_expired_open%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'operations_signals'),
  'and the read no longer produces it'
);

-- Both defects are back, which is what a revert of this package means.
select ok(
  (select pg_get_functiondef(function.oid) like '%end_date >= current_date%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'operations_signals'),
  'the expiry ladder bounds itself at today again, so an expired lease drops '
  'out of it'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%lease_is_effective_on%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_leasing_summary'),
  'and the leasing summary asks about status alone again, without a start bound'
);

-- The AAL rework this package had to reproduce verbatim is intact.
select ok(
  (select
     strpos(def, 'has_workspace_permission') > 0
     and strpos(def, 'has_workspace_permission') < strpos(def, 'leasing_property_in_workspace')
   from (
     select pg_get_functiondef(function.oid) as def
     from pg_proc as function
     join pg_namespace as namespace on namespace.oid = function.pronamespace
     where namespace.nspname = 'public' and function.proname = 'operations_signals'
   ) as source),
  'the permission check still runs before the property probe -- the ordering '
  '20260812100000 introduced so an unauthorized caller cannot use the error to '
  'learn whether a property exists. Reverting this package must land on that '
  'version, not on the P2-D05a original which probed first'
);

-- Everything else belongs to other packages.
select has_function('public', 'operations_signals', 'the signals read survives');
select has_function('public', 'update_operations_signal_status',
  'and the acknowledgement command');
select has_function('public', 'property_leasing_summary',
  'and the leasing summary');
select has_table('public', 'operations_signal_states',
  'the acknowledgement table survives: this package only widened a constraint '
  'on it');
select has_table('public', 'leases', 'and the lease table it reads');

select * from finish();

rollback;
