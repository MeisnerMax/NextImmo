\set ON_ERROR_STOP on

with table_fingerprints as (
  select
    'auth.users' as table_name,
    count(*)::bigint as row_count,
    encode(
      sha256(convert_to(
        coalesce(
          string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text),
          ''
        ),
        'UTF8'
      )),
      'hex'
    ) as row_checksum
  from auth.users as row_value

  union all

  select
    format('public.%s', table_name),
    row_count,
    row_checksum
  from (
    select
      'audit_events' as table_name,
      count(*)::bigint as row_count,
      encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') as row_checksum
    from public.audit_events as row_value
    union all
    select 'entity_scopes', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.entity_scopes as row_value
    union all
    select 'memberships', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.memberships as row_value
    union all
    select 'mutation_receipts', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.mutation_receipts as row_value
    union all
    select 'permissions', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.permissions as row_value
    union all
    select 'properties', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.properties as row_value
    union all
    select 'role_permissions', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.role_permissions as row_value
    union all
    select 'roles', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.roles as row_value
    union all
    select 'user_profiles', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.user_profiles as row_value
    union all
    select 'workspaces', count(*)::bigint, encode(sha256(convert_to(coalesce(string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text), ''), 'UTF8')), 'hex') from public.workspaces as row_value
  ) as public_tables

  union all

  select
    'supabase_migrations.schema_migrations',
    count(*)::bigint,
    encode(
      sha256(convert_to(
        coalesce(
          string_agg(to_jsonb(row_value)::text, E'\n' order by to_jsonb(row_value)::text),
          ''
        ),
        'UTF8'
      )),
      'hex'
    )
  from supabase_migrations.schema_migrations as row_value
),
invariants as (
  select
    count(*) = 10
      and bool_and(c.relrowsecurity)
      and bool_and(c.relforcerowsecurity) as rls_ok
  from pg_class as c
  join pg_namespace as n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'audit_events',
      'entity_scopes',
      'memberships',
      'mutation_receipts',
      'permissions',
      'properties',
      'role_permissions',
      'roles',
      'user_profiles',
      'workspaces'
    )
),
invalid_constraints as (
  select count(*) as invalid_count
  from pg_constraint as constraint_value
  join pg_namespace as namespace_value
    on namespace_value.oid = constraint_value.connamespace
  where namespace_value.nspname in ('public', 'private')
    and not constraint_value.convalidated
),
realtime_contract as (
  select count(*) = 1 as realtime_ok
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename = 'properties'
)
select
  sum(table_fingerprints.row_count)::text
  || '|'
  || encode(
    sha256(convert_to(
      string_agg(
        table_fingerprints.table_name
        || ':'
        || table_fingerprints.row_count::text
        || ':'
        || table_fingerprints.row_checksum,
        E'\n'
        order by table_fingerprints.table_name
      ),
      'UTF8'
    )),
    'hex'
  )
  || '|'
  || case
    when invariants.rls_ok
      and invalid_constraints.invalid_count = 0
      and realtime_contract.realtime_ok
    then 'ok'
    else 'invalid'
  end
from table_fingerprints
cross join invariants
cross join invalid_constraints
cross join realtime_contract
group by
  invariants.rls_ok,
  invalid_constraints.invalid_count,
  realtime_contract.realtime_ok;
