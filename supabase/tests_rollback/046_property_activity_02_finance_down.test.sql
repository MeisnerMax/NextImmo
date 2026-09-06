begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-ACTIVITY-02 restores the three functions to their
-- PROPERTY-ACTIVITY-01 bodies. It creates and drops nothing.
--
-- That makes this rollback unusual: there is no object whose absence proves
-- the revert. All three functions must still be *there*, with the same
-- signatures and the same grants, and behaving as they did before -- which
-- means the two defects this package fixed are back. Asserting that they are
-- back is the point. A rollback that silently kept half of the change would
-- leave the schema in a state no migration describes.
--
-- The finance tables themselves belong to FINANCE-01 and must survive
-- untouched: this package only ever read them.

select plan(13);

-- The functions survive the revert -- this package replaced them, never
-- created them.
select has_function('public', 'property_activity',
  'the read port survives: PROPERTY-ACTIVITY-01 owns it');
select has_function('private', 'property_activity_taxonomy',
  'and the taxonomy');
select has_function('private', 'property_activity_rows',
  'and the property resolution');
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'property_activity'),
  's'::"char",
  'still stable, still a read'
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
  'and anon still cannot call it'
);
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
  'the helpers are still unreachable from a client'
);

-- The taxonomy is back to fourteen rows: finance is gone.
select is(
  (select count(*)::integer from private.property_activity_taxonomy()),
  14,
  'the taxonomy is back to its PROPERTY-ACTIVITY-01 size'
);
select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where entity_type = 'finance_ledger_entry'),
  0,
  'the finance entity type is gone with the migration that added it'
);
select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where required_permission = 'finance.read'),
  0,
  'and so is the permission it was gated on'
);

-- The finance schema belongs to FINANCE-01 and is only ever read from here.
select has_table('public', 'finance_ledger_entries',
  'the ledger survives: this package only joined it');
select has_column('public', 'finance_ledger_entries', 'property_id',
  'including the column the resolution keyed on');
select has_table('public', 'finance_accounts',
  'and the accounts this package deliberately left out of the chronicle');

-- The audit history is untouched by either direction of this migration.
select is(
  (select count(*)::integer
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'audit_events'
     and column_name in ('action', 'entity_type')),
  2,
  'the two columns the event key is built from survive: the revert changes '
  'how they are published, never what was written'
);

select * from finish();

rollback;
