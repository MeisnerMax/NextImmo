begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

select has_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'AAL-protected property update RPC exists'
);
select has_function(
  'private',
  'update_property_core',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'property update core is private'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name = 'update_property_core'
     and grantee in ('PUBLIC', 'anon', 'authenticated')),
  0,
  'client roles cannot bypass the AAL wrapper'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name = 'update_property'
     and grantee = 'authenticated'
     and privilege_type = 'EXECUTE'),
  1,
  'authenticated can execute only the public update entry point'
);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'properties'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  0,
  'direct property mutations remain denied to client roles'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1500000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'p1-015@example.test', '', now(), '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name) values
  ('11500000-0000-0000-0000-000000000001', 'p1-015-a', 'P1-015 A'),
  ('21500000-0000-0000-0000-000000000001', 'p1-015-b', 'P1-015 B');

insert into public.roles (id, workspace_id, key, name) values (
  '11500000-0000-0000-0000-000000000002',
  '11500000-0000-0000-0000-000000000001',
  'property_manager', 'Property Manager'
);

insert into public.permissions (id, key, name) values
  ('31500000-0000-0000-0000-000000000001', 'property.read', 'Property Read'),
  ('31500000-0000-0000-0000-000000000002', 'property.update', 'Property Update');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('11500000-0000-0000-0000-000000000001', '11500000-0000-0000-0000-000000000002', '31500000-0000-0000-0000-000000000001'),
  ('11500000-0000-0000-0000-000000000001', '11500000-0000-0000-0000-000000000002', '31500000-0000-0000-0000-000000000002');

insert into public.memberships (workspace_id, user_id, role_id, status) values (
  '11500000-0000-0000-0000-000000000001',
  'a1500000-0000-0000-0000-000000000001',
  '11500000-0000-0000-0000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values
  (
    '71500000-0000-0000-0000-000000000001',
    '11500000-0000-0000-0000-000000000001',
    'Property A', 'A Street 1', '10115', 'Berlin', 'de', 'office', 1, 'active',
    'a1500000-0000-0000-0000-000000000001',
    'a1500000-0000-0000-0000-000000000001'
  ),
  (
    '72500000-0000-0000-0000-000000000001',
    '21500000-0000-0000-0000-000000000001',
    'Property B', 'B Street 1', '20095', 'Hamburg', 'de', 'office', 1, 'active',
    'a1500000-0000-0000-0000-000000000001',
    'a1500000-0000-0000-0000-000000000001'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1500000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"a1500000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);

select is((select count(*)::integer from public.properties), 1, 'AAL1 retains authorized reads');
select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000001',
    '91500000-0000-0000-0000-000000000001',
    '{"name":"AAL1 denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'AAL1 property update is denied'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1500000-0000-0000-0000-000000000001","role":"authenticated","aal":"unexpected"}',
  true
);
select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000002',
    '91500000-0000-0000-0000-000000000002',
    '{"name":"Unknown denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'unknown AAL fails closed'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1500000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000003',
    '91500000-0000-0000-0000-000000000003',
    '{"name":"Missing denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'missing AAL fails closed'
);

reset role;
select is((select name from public.properties where id = '71500000-0000-0000-0000-000000000001'), 'Property A', 'denied attempts do not mutate the property');
select is((select count(*)::integer from public.mutation_receipts), 0, 'denied attempts create no receipt');
select is((select count(*)::integer from public.audit_events), 0, 'denied attempts create no audit event');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1500000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"a1500000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000010',
    '91500000-0000-0000-0000-000000000010',
    '{"name":"AAL2 accepted"}'::jsonb
  ) #>> '{property,name}',
  'AAL2 accepted',
  'AAL2 property update succeeds'
);
select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000010',
    '91500000-0000-0000-0000-000000000010',
    '{"name":"AAL2 accepted"}'::jsonb
  ) #>> '{property,version}',
  '2',
  'AAL2 retry returns the original result'
);
select is(
  public.update_property(
    '21500000-0000-0000-0000-000000000001',
    '72500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000011',
    '91500000-0000-0000-0000-000000000011',
    '{"name":"Cross-tenant denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'AAL2 does not bypass workspace permission checks'
);
select throws_ok(
  $$update public.properties
    set name = 'Direct AAL2 denied'
    where id = '71500000-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct AAL2 update remains denied'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1500000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);
select is(
  public.update_property(
    '11500000-0000-0000-0000-000000000001',
    '71500000-0000-0000-0000-000000000001', 1,
    '61500000-0000-0000-0000-000000000010',
    '91500000-0000-0000-0000-000000000010',
    '{"name":"AAL2 accepted"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'AAL1 cannot replay an AAL2 mutation receipt'
);

reset role;
select is((select version from public.properties where id = '71500000-0000-0000-0000-000000000001'), 2::bigint, 'retry changes the property once');
select is((select count(*)::integer from public.audit_events), 1, 'retry writes exactly one audit event');
select is((select count(*)::integer from public.mutation_receipts where status = 'succeeded'), 1, 'retry leaves exactly one successful receipt');
select is((select name from public.properties where id = '72500000-0000-0000-0000-000000000001'), 'Property B', 'cross-tenant property remains unchanged');

select * from finish();

rollback;
