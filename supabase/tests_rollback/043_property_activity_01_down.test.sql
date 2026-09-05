begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-ACTIVITY-01 removes one read function and the two
-- private helpers behind it.
--
-- The package added no table, no column, no policy, no permission and no
-- index. Everything it published was derived from `audit_events` and the
-- domain tables that already existed, which makes this rollback almost
-- entirely a test of restraint: the chronicle goes, the history stays.
--
-- The one thing worth asserting loudly is that `property_audit_events`
-- survives untouched. The activity read deliberately did not widen it — who
-- may see which fields of a lease changed is a disclosure decision the spec
-- defers to a security review — so a revert must not be able to disturb it
-- either.

select plan(12);

create or replace function pg_temp.has_public_table(p_name text)
returns boolean
language sql
as $$
  select exists (
    select 1 from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relname = p_name
      and class.relkind = 'r'
  );
$$;

select hasnt_function('public', 'property_activity',
  'the activity read port is removed');
select hasnt_function('private', 'property_activity_taxonomy',
  'and the taxonomy behind it');
select hasnt_function('private', 'property_activity_rows',
  'and the property resolution');

-- The history itself and the audit read port survive.
select has_table('public', 'audit_events', 'the audit table survives');
select has_function('public', 'property_audit_events',
  'and the AUDIT-01 read port, which this package never changed');
select has_column('public', 'audit_events', 'entity_type',
  'the column the taxonomy keyed on survives');
select has_column('public', 'audit_events', 'actor_type',
  'and the actor type an activity row reported');
select ok(
  (select count(*) > 0
   from pg_policies
   where schemaname = 'public'
     and tablename = 'audit_events'
     and policyname = 'audit_events_select_audit_read'),
  'the audit.read policy is untouched'
);

-- The domain tables the resolution joined are other packages' property.
select ok(
  (select bool_and(pg_temp.has_public_table(name))
   from unnest(array[
     'units', 'leases', 'leasing_cases', 'rent_roll_snapshots',
     'maintenance_tickets', 'capex_projects', 'tasks', 'documents',
     'document_links', 'valuation_cases', 'property_media'
   ]) as name),
  'every domain table the resolution read survives: it only ever joined them'
);

-- No permission, no index, no policy of its own can linger.
select is(
  (select count(*)::integer from public.permissions
   where key in ('activity.read', 'property.activity.read')),
  0,
  'no activity permission was ever introduced, so none can linger'
);
select is(
  (select count(*)::integer
   from pg_indexes
   where schemaname = 'public'
     and indexname like '%activity%'),
  0,
  'and no index of its own'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.proname like '%activity%'),
  0,
  'nothing named activity is left behind in either schema'
);

select * from finish();

rollback;
