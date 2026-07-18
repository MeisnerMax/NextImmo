begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select has_index(
  'public',
  'memberships',
  'memberships_user_id_status_idx',
  'membership lookup has a user and status index'
);
select has_index(
  'public',
  'memberships',
  'memberships_workspace_id_role_id_idx',
  'membership role foreign key has a supporting index'
);
select has_index(
  'public',
  'role_permissions',
  'role_permissions_permission_id_idx',
  'role permission foreign key has a supporting index'
);
select has_index(
  'public',
  'properties',
  'properties_workspace_id_id_idx',
  'property foreign key and complete workspace list have a supporting index'
);
select has_index(
  'public',
  'properties',
  'properties_workspace_id_id_not_archived_idx',
  'default property list has a partial workspace keyset index'
);

select is(
  (
    select array_agg(attribute.attname::text order by key.ordinality)
    from pg_index as index
    join pg_class as index_class on index_class.oid = index.indexrelid
    cross join lateral unnest(index.indkey) with ordinality as key(attnum, ordinality)
    join pg_attribute as attribute
      on attribute.attrelid = index.indrelid
      and attribute.attnum = key.attnum
    where index_class.relname = 'memberships_user_id_status_idx'
      and index.indrelid = 'public.memberships'::regclass
  ),
  array['user_id', 'status'],
  'membership lookup index uses the expected column order'
);

select is(
  (
    select array_agg(attribute.attname::text order by key.ordinality)
    from pg_index as index
    join pg_class as index_class on index_class.oid = index.indexrelid
    cross join lateral unnest(index.indkey) with ordinality as key(attnum, ordinality)
    join pg_attribute as attribute
      on attribute.attrelid = index.indrelid
      and attribute.attnum = key.attnum
    where index_class.relname = 'properties_workspace_id_id_not_archived_idx'
      and index.indrelid = 'public.properties'::regclass
  ),
  array['workspace_id', 'id'],
  'partial property index matches workspace keyset pagination'
);

select ok(
  (
    select pg_get_expr(index.indpred, index.indrelid) ~
      '^\(?status <> ''archived''::property_status\)?$'
    from pg_index as index
    join pg_class as index_class on index_class.oid = index.indexrelid
    where index_class.relname = 'properties_workspace_id_id_not_archived_idx'
      and index.indrelid = 'public.properties'::regclass
  ),
  'default property index excludes archived rows'
);

select ok(
  not exists (
    select 1
    from pg_constraint as foreign_key
    where foreign_key.contype = 'f'
      and foreign_key.connamespace = 'public'::regnamespace
      and not exists (
        select 1
        from pg_index as index
        where index.indrelid = foreign_key.conrelid
          and index.indisvalid
          and index.indisready
          and index.indnkeyatts >= cardinality(foreign_key.conkey)
          and not exists (
            select 1
            from generate_subscripts(foreign_key.conkey, 1) as position
            where index.indkey[position - 1] <>
              foreign_key.conkey[position]
          )
      )
  ),
  'all public foreign keys have a supporting leading-column index'
);

select is(
  (
    select count(*)::integer
    from pg_policies as policy
    where policy.schemaname = 'public'
      and policy.policyname in (
        'user_profiles_select_own',
        'permissions_select_authenticated'
      )
      and policy.cmd = 'SELECT'
      and policy.roles = array['authenticated']::name[]
  ),
  2,
  'hardened policies retain authenticated SELECT scope'
);

select is(
  (
    select count(*)::integer
    from pg_policies as policy
    where policy.schemaname = 'public'
      and policy.policyname in (
        'user_profiles_select_own',
        'permissions_select_authenticated'
      )
      and policy.qual like '%SELECT auth.uid()%'
  ),
  2,
  'direct auth uid policy checks use an initplan expression'
);

select * from finish();

rollback;
