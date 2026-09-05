begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-MEDIA-DATA-01 removes the metadata table, its two
-- enums, the two RPCs and the storage policies.
--
-- The bucket row deliberately survives, and that is not an oversight:
-- `migration down` rebuilds the schema from migrations but restores table
-- *data* from a dump, so `storage.buckets` outlives the replay. A revert that
-- dropped the bucket would delete uploaded files, which is a data loss dressed
-- up as undoing a feature. What must go is the *access*: with the policies
-- gone, the bucket is unreachable by any client, which is the correct
-- fail-closed state for a feature that no longer exists.

select plan(11);

select hasnt_table('public', 'property_media', 'the metadata table is removed');
select hasnt_function(
  'public', 'register_property_media', 'the registration RPC is removed'
);
select hasnt_function(
  'public', 'update_property_media', 'the update RPC is removed'
);
select is(
  (select count(*)::integer
   from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname in ('property_media_kind', 'property_media_status')),
  0,
  'and so are its enums'
);
select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname like 'property_media_bucket_%'),
  0,
  'no storage policy is left behind: the bucket becomes unreachable rather '
  'than half-guarded'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname like 'property_media%'),
  0,
  'and no private helper of this package survives'
);

-- Everything the package built on predates it and must be untouched.
select has_table('public', 'properties', 'properties survives');
select has_table('public', 'audit_events', 'the audit trail survives');
select has_table('public', 'mutation_receipts', 'the receipts survive');
select ok(
  (select count(*) > 0
   from pg_policies
   where schemaname = 'public'
     and tablename = 'properties'
     and policyname = 'properties_select_property_read'),
  'the property read policy is untouched'
);

-- The package introduced no permission of its own, so none can linger.
select is(
  (select count(*)::integer from public.permissions
   where key in ('media.read', 'media.manage', 'property.media.manage')),
  0,
  'no media-specific permission was ever introduced'
);

select * from finish();

rollback;
