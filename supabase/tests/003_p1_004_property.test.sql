begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

select has_type('public', 'property_status', 'property status enum exists');
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum
   where enum.enumtypid = 'public.property_status'::regtype),
  array['draft', 'active', 'archived'],
  'property status enum has the contract labels'
);
select has_table('public', 'properties', 'properties exists');
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.properties'::regclass
      and conname = 'properties_notes_check'
  ),
  'property notes have a database length constraint'
);
select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text']
);
select policies_are('public', 'properties', array['properties_select_property_read']);

select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   where class.oid = 'public.properties'::regclass),
  'properties enables and forces RLS'
);

select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'properties'
     and grantee = 'authenticated'
     and privilege_type = 'SELECT'),
  1,
  'authenticated receives SELECT only'
);

select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'properties'
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no property DML grants'
);

select ok(
  function.prosecdef
  and function.provolatile = 'v'
  and owner.rolname = 'postgres'
  and function.proconfig @> array['search_path=""']::text[],
  'update RPC is a volatile postgres security definer with fixed search path'
)
from pg_proc as function
join pg_namespace as namespace on namespace.oid = function.pronamespace
join pg_roles as owner on owner.oid = function.proowner
where namespace.nspname = 'public'
  and function.proname = 'update_property';

select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'update_property'
     and grantee = 'authenticated'
     and privilege_type = 'EXECUTE'),
  1,
  'authenticated can execute update RPC'
);

select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'update_property'
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute update RPC'
);

select is(
  (select count(*)::integer
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'properties'),
  0,
  'properties is not added to Realtime publication'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a0000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'viewer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager-a-2@example.test', '', now(), '{}', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'updater-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('b0000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('10000000-0000-0000-0000-000000000101', 'property-workspace-a', 'Property Workspace A'),
  ('20000000-0000-0000-0000-000000000101', 'property-workspace-b', 'Property Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('11000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', 'manager', 'Manager A'),
  ('11000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000101', 'viewer', 'Viewer A'),
  ('11000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000101', 'updater', 'Updater A'),
  ('21000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('30000000-0000-0000-0000-000000000101', 'property.read', 'Property Read'),
  ('30000000-0000-0000-0000-000000000102', 'property.update', 'Property Update'),
  ('30000000-0000-0000-0000-000000000103', 'audit.read', 'Audit Read');

insert into public.role_permissions (id, workspace_id, role_id, permission_id) values
  ('41000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000101'),
  ('41000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000102'),
  ('41000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000103'),
  ('41000000-0000-0000-0000-000000000104', '10000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000102', '30000000-0000-0000-0000-000000000101'),
  ('41000000-0000-0000-0000-000000000105', '10000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000103', '30000000-0000-0000-0000-000000000102'),
  ('42000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', '21000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000101'),
  ('42000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000101', '21000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000102');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('51000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000101', 'active'),
  ('51000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000102', '11000000-0000-0000-0000-000000000102', 'active'),
  ('51000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000103', '11000000-0000-0000-0000-000000000101', 'active'),
  ('51000000-0000-0000-0000-000000000104', '10000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000104', '11000000-0000-0000-0000-000000000103', 'active'),
  ('52000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 'b0000000-0000-0000-0000-000000000101', '21000000-0000-0000-0000-000000000101', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, address_line2, zip, city, country,
  property_type, units, sqft, year_built, notes, status, created_by, updated_by
) values
  (
    '71000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101',
    'Property A', 'Main Street 1', null, '10115', 'Berlin', 'de', 'multifamily',
    10, 10000, 1998, 'Initial', 'active',
    'a0000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000101'
  ),
  (
    '72000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101',
    'Property B', 'Other Street 2', null, '20095', 'Hamburg', 'de', 'office',
    2, 5000, 2005, null, 'active',
    'b0000000-0000-0000-0000-000000000101', 'b0000000-0000-0000-0000-000000000101'
  );

create temporary table p1_004_results (
  key text primary key,
  result jsonb not null
);
grant all on table p1_004_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select is((select count(*)::integer from public.properties), 1, 'manager reads one workspace property');
select is(
  (select count(*)::integer from public.properties where id = '72000000-0000-0000-0000-000000000101'),
  0,
  'manager cannot read a foreign property'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '72000000-0000-0000-0000-000000000101',
    1,
    '61000000-0000-0000-0000-000000000101',
    '91000000-0000-0000-0000-000000000101',
    '{"name":"Hidden"}'::jsonb
  ) #>> '{error,code}',
  'not_found',
  'workspace mismatch is fail-closed as not found'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000102', true);

select is((select count(*)::integer from public.properties), 1, 'viewer can read workspace properties');
select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    1,
    '61000000-0000-0000-0000-000000000102',
    '91000000-0000-0000-0000-000000000102',
    '{"name":"Denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'viewer cannot update properties'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000104', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    1,
    '61000000-0000-0000-0000-000000000111',
    '91000000-0000-0000-0000-000000000111',
    '{"name":"Hidden update"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'update-only role cannot use the RPC to read property data'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000101', true);

select is(
  (select id from public.properties),
  '72000000-0000-0000-0000-000000000101'::uuid,
  'second workspace manager reads only own property'
);

reset role;
set local role anon;

select throws_ok(
  $$select * from public.properties$$,
  '42501', null, 'anon cannot select properties'
);
select throws_ok(
  $$select public.update_property(
      '10000000-0000-0000-0000-000000000101',
      '71000000-0000-0000-0000-000000000101',
      1,
      '61000000-0000-0000-0000-000000000103',
      '91000000-0000-0000-0000-000000000103',
      '{"name":"Denied"}'::jsonb
    )$$,
  '42501', null, 'anon cannot execute update RPC'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select throws_ok(
  $$update public.properties
    set name = 'Direct DML'
    where id = '71000000-0000-0000-0000-000000000101'$$,
  '42501', null, 'authenticated direct property UPDATE is denied'
);

insert into p1_004_results (key, result)
select 'success', public.update_property(
  '10000000-0000-0000-0000-000000000101',
  '71000000-0000-0000-0000-000000000101',
  1,
  '61000000-0000-0000-0000-000000000104',
  '91000000-0000-0000-0000-000000000104',
  '{
    "name":"Property A Updated",
    "address_line1":"Main Street 10",
    "address_line2":null,
    "zip":"10117",
    "city":"Berlin",
    "country":"de",
    "property_type":"mixed_use",
    "units":12,
    "sqft":12000.5,
    "year_built":2000,
    "notes":"Updated",
    "status":"active"
  }'::jsonb,
  'contract test'
);

select is((select result ->> 'ok' from p1_004_results where key = 'success'), 'true', 'manager update succeeds');
select is((select (result #>> '{property,version}')::bigint from p1_004_results where key = 'success'), 2::bigint, 'success result increments version once');
select is((select version from public.properties), 2::bigint, 'stored property version increments once');
select is((select updated_by from public.properties), 'a0000000-0000-0000-0000-000000000101'::uuid, 'actor is always auth.uid');
select is((select count(*)::integer from public.audit_events), 1, 'success writes exactly one audit event');
select is((select actor_user_id from public.audit_events), 'a0000000-0000-0000-0000-000000000101'::uuid, 'audit actor is auth.uid');

reset role;
select is((select count(*)::integer from public.mutation_receipts where status = 'succeeded'), 1, 'success marks one receipt succeeded');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    1,
    '61000000-0000-0000-0000-000000000104',
    '91000000-0000-0000-0000-000000000104',
    '{
      "name":"Property A Updated",
      "address_line1":"Main Street 10",
      "address_line2":null,
      "zip":"10117",
      "city":"Berlin",
      "country":"de",
      "property_type":"mixed_use",
      "units":12,
      "sqft":12000.5,
      "year_built":2000,
      "notes":"Updated",
      "status":"active"
    }'::jsonb,
    'contract test'
  ),
  (select result from p1_004_results where key = 'success'),
  'same mutation and hash returns the identical success result'
);

select is((select version from public.properties), 2::bigint, 'retry does not increment version');
select is((select count(*)::integer from public.audit_events), 1, 'retry does not duplicate audit');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000103', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    1,
    '61000000-0000-0000-0000-000000000104',
    '91000000-0000-0000-0000-000000000104',
    '{
      "name":"Property A Updated",
      "address_line1":"Main Street 10",
      "address_line2":null,
      "zip":"10117",
      "city":"Berlin",
      "country":"de",
      "property_type":"mixed_use",
      "units":12,
      "sqft":12000.5,
      "year_built":2000,
      "notes":"Updated",
      "status":"active"
    }'::jsonb,
    'contract test'
  ) #>> '{error,code}',
  'mutation_conflict',
  'another actor cannot replay a mutation result'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000104',
    '91000000-0000-0000-0000-000000000104',
    '{"name":"Different"}'::jsonb,
    'contract test'
  ) #>> '{error,code}',
  'mutation_conflict',
  'same mutation id with another hash conflicts'
);

insert into p1_004_results (key, result)
select 'stale', public.update_property(
  '10000000-0000-0000-0000-000000000101',
  '71000000-0000-0000-0000-000000000101',
  1,
  '61000000-0000-0000-0000-000000000105',
  '91000000-0000-0000-0000-000000000105',
  '{"name":"Stale"}'::jsonb
);

select is((select result #>> '{error,code}' from p1_004_results where key = 'stale'), 'version_conflict', 'stale update returns structured conflict');
select is((select (result #>> '{error,current_property,version}')::bigint from p1_004_results where key = 'stale'), 2::bigint, 'version conflict includes current property');
select is((select version from public.properties), 2::bigint, 'stale update leaves property unchanged');

reset role;
select is(
  (select count(*)::integer
   from public.mutation_receipts
   where mutation_id = '61000000-0000-0000-0000-000000000105'),
  0,
  'stale update leaves no persistent receipt'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000106',
    '91000000-0000-0000-0000-000000000106',
    '{"unknown":"value"}'::jsonb
  ) #>> '{error,code}',
  'validation_failed',
  'unknown change keys fail validation'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000107',
    '91000000-0000-0000-0000-000000000107',
    '{"status":"invalid"}'::jsonb
  ) #>> '{error,code}',
  'validation_failed',
  'invalid DTO values fail validation'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000108',
    '91000000-0000-0000-0000-000000000108',
    '{"workspace_id":"20000000-0000-0000-0000-000000000101"}'::jsonb
  ) #>> '{error,code}',
  'validation_failed',
  'workspace cannot be changed through the RPC'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000109',
    '91000000-0000-0000-0000-000000000109',
    '{"units":"many"}'::jsonb
  ) #>> '{error,code}',
  'validation_failed',
  'invalid numeric JSON types return structured validation'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000112',
    '91000000-0000-0000-0000-000000000112',
    jsonb_build_object('notes', repeat('n', 10001))
  ) #>> '{error,code}',
  'validation_failed',
  'oversized notes fail validation'
);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000113',
    '91000000-0000-0000-0000-000000000113',
    '{"name":"Reason limit"}'::jsonb,
    repeat('r', 2001)
  ) #>> '{error,code}',
  'validation_failed',
  'oversized audit reason fails validation'
);

reset role;

insert into public.mutation_receipts (
  workspace_id, mutation_id, request_hash, status, created_by, updated_by
)
select
  '10000000-0000-0000-0000-000000000101',
  '61000000-0000-0000-0000-000000000110',
  extensions.digest(
    convert_to(
      jsonb_build_object(
        'actor_id', 'a0000000-0000-0000-0000-000000000101'::uuid,
        'workspace_id', '10000000-0000-0000-0000-000000000101'::uuid,
        'property_id', '71000000-0000-0000-0000-000000000101'::uuid,
        'expected_version', 2::bigint,
        'correlation_id', '91000000-0000-0000-0000-000000000110'::uuid,
        'reason', null,
        'changes', '{"name":"Pending"}'::jsonb
      )::text,
      'UTF8'
    ),
    'sha256'
  ),
  'pending',
  'a0000000-0000-0000-0000-000000000101',
  'a0000000-0000-0000-0000-000000000101';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000101', true);

select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000101',
    '71000000-0000-0000-0000-000000000101',
    2,
    '61000000-0000-0000-0000-000000000110',
    '91000000-0000-0000-0000-000000000110',
    '{"name":"Pending"}'::jsonb
  ) #>> '{error,code}',
  'in_progress',
  'matching pending receipt returns deterministic in-progress result'
);

reset role;
delete from public.mutation_receipts
where mutation_id = '61000000-0000-0000-0000-000000000110';

select throws_ok(
  $$update public.properties
    set workspace_id = '20000000-0000-0000-0000-000000000101'
    where id = '71000000-0000-0000-0000-000000000101'$$,
  '23000', null, 'workspace is immutable through the shared trigger'
);

select is(
  (select count(*)::integer
   from jsonb_object_keys((select old_values from public.audit_events)) as keys(key)
   where key not in (
     'id', 'workspace_id', 'name', 'address_line1', 'address_line2', 'zip', 'city',
     'country', 'property_type', 'units', 'sqft', 'year_built', 'notes', 'status',
     'created_at', 'updated_at', 'created_by', 'updated_by', 'version', 'deleted_at'
   )),
  0,
  'audit old values use an explicit allowlist'
);

select is(
  (select count(*)::integer
   from jsonb_object_keys((select new_values from public.audit_events)) as keys(key)
   where key not in (
     'id', 'workspace_id', 'name', 'address_line1', 'address_line2', 'zip', 'city',
     'country', 'property_type', 'units', 'sqft', 'year_built', 'notes', 'status',
     'created_at', 'updated_at', 'created_by', 'updated_by', 'version', 'deleted_at'
   )),
  0,
  'audit new values use an explicit allowlist'
);

select * from finish();

rollback;
