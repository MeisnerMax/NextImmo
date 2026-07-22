\set ON_ERROR_STOP on

begin;

select set_config('p1_021.property_count', :'property_count', true);
select set_config('p1_021.warmup_runs', :'warmup_runs', true);
select set_config('p1_021.measured_runs', :'measured_runs', true);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '21000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'p1-021-profile@example.test',
  extensions.crypt('NexImmo-Local-Profile-Only!', extensions.gen_salt('bf')),
  now(), '', '', '', '', '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name)
values ('21000000-0000-0000-0000-000000000002', 'p1-021-profile', 'P1-021 Profile');

insert into public.roles (id, workspace_id, key, name)
values (
  '21000000-0000-0000-0000-000000000003',
  '21000000-0000-0000-0000-000000000002',
  'property_manager',
  'Property Manager'
);

insert into public.permissions (id, key, name) values
  ('21000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read'),
  ('21000000-0000-0000-0000-000000000005', 'property.read', 'Property Read'),
  ('21000000-0000-0000-0000-000000000006', 'property.update', 'Property Update');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select
  '21000000-0000-0000-0000-000000000002'::uuid,
  '21000000-0000-0000-0000-000000000003'::uuid,
  permission.id
from public.permissions as permission
where permission.key in ('workspace.read', 'property.read', 'property.update');

insert into public.memberships (workspace_id, user_id, role_id, status)
values (
  '21000000-0000-0000-0000-000000000002',
  '21000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000003',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, notes, status, created_by, updated_by, deleted_at
)
select
  md5('p1-021-property-' || series)::uuid,
  '21000000-0000-0000-0000-000000000002'::uuid,
  'Profile Property ' || series,
  'Profile Street ' || series,
  lpad((10000 + (series % 89999))::text, 5, '0'),
  'Berlin',
  'de',
  'office',
  series % 200,
  repeat('profile-note-', 8),
  case
    when series % 10 = 0 then 'archived'::public.property_status
    else 'active'::public.property_status
  end,
  '21000000-0000-0000-0000-000000000001'::uuid,
  '21000000-0000-0000-0000-000000000001'::uuid,
  case when series % 10 = 0 then now() else null end
from generate_series(
  1,
  current_setting('p1_021.property_count')::integer
) as fixture(series);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values (
  '21000000-0000-0000-0000-000000000007',
  '21000000-0000-0000-0000-000000000002',
  'RPC Profile Property',
  'Profile Street RPC',
  '10115',
  'Berlin',
  'de',
  'office',
  1,
  'active',
  '21000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001'
);

analyze public.memberships;
analyze public.role_permissions;
analyze public.properties;

create temporary table p1_021_samples (
  profile text not null,
  sample_index integer not null,
  planning_ms numeric not null,
  execution_ms numeric not null,
  plan jsonb not null
);

grant insert, select on table p1_021_samples to authenticated;

create function pg_temp.capture_p1_021_profile(
  profile_name text,
  statement text,
  sample_number integer
)
returns void
language plpgsql
as $$
declare
  captured_plan jsonb;
begin
  execute 'explain (analyze, buffers, format json) ' || statement
    into captured_plan;

  insert into pg_temp.p1_021_samples (
    profile,
    sample_index,
    planning_ms,
    execution_ms,
    plan
  ) values (
    profile_name,
    sample_number,
    (captured_plan -> 0 ->> 'Planning Time')::numeric,
    (captured_plan -> 0 ->> 'Execution Time')::numeric,
    captured_plan
  );
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '21000000-0000-0000-0000-000000000001',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

do $$
declare
  run_number integer;
  sample_number integer;
  warmups integer := current_setting('p1_021.warmup_runs')::integer;
  measurements integer := current_setting('p1_021.measured_runs')::integer;
  property_version bigint;
begin
  for run_number in 1..(warmups + measurements) loop
    sample_number := run_number - warmups;

    perform pg_temp.capture_p1_021_profile(
      'property_summary_keyset',
      $statement$
        select id, workspace_id, name, address_line1, zip, city, status, version
        from public.properties
        where workspace_id = '21000000-0000-0000-0000-000000000002'::uuid
          and status <> 'archived'::public.property_status
          and id > '00000000-0000-0000-0000-000000000000'::uuid
        order by id
        limit 51
      $statement$,
      sample_number
    );

    perform pg_temp.capture_p1_021_profile(
      'active_memberships',
      $statement$
        select id, workspace_id, user_id, role_id, status, version
        from public.memberships
        where user_id = '21000000-0000-0000-0000-000000000001'::uuid
          and status = 'active'::public.membership_status
        order by workspace_id, id
      $statement$,
      sample_number
    );

    perform pg_temp.capture_p1_021_profile(
      'workspace_projection',
      $statement$
        select id, key, name, archived_at, version
        from public.workspaces
        where id = '21000000-0000-0000-0000-000000000002'::uuid
      $statement$,
      sample_number
    );

    perform pg_temp.capture_p1_021_profile(
      'role_permissions',
      $statement$
        select workspace_id, role_id, permission_id
        from public.role_permissions
        where workspace_id = '21000000-0000-0000-0000-000000000002'::uuid
          and role_id = '21000000-0000-0000-0000-000000000003'::uuid
        order by permission_id
      $statement$,
      sample_number
    );

    select version
    into property_version
    from public.properties
    where id = '21000000-0000-0000-0000-000000000007'::uuid;

    perform pg_temp.capture_p1_021_profile(
      'property_update_rpc',
      format(
        $statement$
          select public.update_property(
            '21000000-0000-0000-0000-000000000002'::uuid,
            '21000000-0000-0000-0000-000000000007'::uuid,
            %s,
            %L::uuid,
            %L::uuid,
            %L::jsonb,
            null
          )
        $statement$,
        property_version,
        md5('p1-021-mutation-' || run_number)::uuid,
        md5('p1-021-correlation-' || run_number)::uuid,
        jsonb_build_object('name', 'RPC Profile ' || run_number)::text
      ),
      sample_number
    );
  end loop;

  if not exists (
    select 1
    from public.memberships
    where user_id = '21000000-0000-0000-0000-000000000001'::uuid
      and status = 'active'::public.membership_status
  ) or not exists (
    select 1
    from public.properties
    where workspace_id = '21000000-0000-0000-0000-000000000002'::uuid
      and status <> 'archived'::public.property_status
  ) then
    raise exception 'P1-021 authenticated fixture validation failed.';
  end if;
end;
$$;

reset role;

select jsonb_build_object(
  'contract_version', 1,
  'environment', 'local',
  'acceptance_gate', false,
  'captured_at_utc', to_char(
    clock_timestamp() at time zone 'utc',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  ),
  'migration_head', (
    select max(version)
    from supabase_migrations.schema_migrations
  ),
  'configuration', jsonb_build_object(
    'property_count', current_setting('p1_021.property_count')::integer,
    'warmup_runs', current_setting('p1_021.warmup_runs')::integer,
    'measured_runs', current_setting('p1_021.measured_runs')::integer
  ),
  'profiles', (
    select jsonb_object_agg(
      aggregate.profile,
      jsonb_build_object(
        'samples', aggregate.samples,
        'planning_ms_p50', aggregate.planning_ms_p50,
        'planning_ms_p95', aggregate.planning_ms_p95,
        'planning_ms_p99', aggregate.planning_ms_p99,
        'execution_ms_min', aggregate.execution_ms_min,
        'execution_ms_p50', aggregate.execution_ms_p50,
        'execution_ms_p95', aggregate.execution_ms_p95,
        'execution_ms_p99', aggregate.execution_ms_p99,
        'execution_ms_max', aggregate.execution_ms_max,
        'representative_plan', aggregate.representative_plan
      )
      order by aggregate.profile
    )
    from (
      select
        sample.profile,
        count(*)::integer as samples,
        percentile_cont(0.50) within group (order by sample.planning_ms)
          as planning_ms_p50,
        percentile_cont(0.95) within group (order by sample.planning_ms)
          as planning_ms_p95,
        percentile_cont(0.99) within group (order by sample.planning_ms)
          as planning_ms_p99,
        min(sample.execution_ms) as execution_ms_min,
        percentile_cont(0.50) within group (order by sample.execution_ms)
          as execution_ms_p50,
        percentile_cont(0.95) within group (order by sample.execution_ms)
          as execution_ms_p95,
        percentile_cont(0.99) within group (order by sample.execution_ms)
          as execution_ms_p99,
        max(sample.execution_ms) as execution_ms_max,
        (array_agg(sample.plan order by sample.sample_index))[1]
          as representative_plan
      from pg_temp.p1_021_samples as sample
      where sample.sample_index > 0
      group by sample.profile
    ) as aggregate
  )
)::text;

rollback;
