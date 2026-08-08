begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

select has_function(
  'private', 'has_entity_scope', array['uuid', 'text', 'uuid'],
  'entity-scope helper exists'
);
select has_function(
  'private', 'has_scoped_entity_permission',
  array['uuid', 'text', 'text', 'uuid'],
  'permission-and-scope helper exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.entity_scopes'::regclass
      and conname = 'entity_scopes_supported_entity_type_check'
  ),
  'entity scopes accept only supported target types'
);
select ok(
  pg_get_expr(policy.polqual, policy.polrelid) like '%has_scoped_entity_permission%',
  'property RLS combines permission and entity scope'
)
from pg_policy as policy
where policy.polrelid = 'public.properties'::regclass
  and policy.polname = 'properties_select_property_read';
select has_function(
  'private', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'unscoped property command is private'
);
select has_function(
  'public', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'public property command remains stable'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a0000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'unscoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000403', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'portfolio@example.test', '', now(), '{}', '{}', now(), now()),
  ('b0000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'foreign@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('10000000-0000-0000-0000-000000000401', 'scope-workspace-a', 'Scope Workspace A'),
  ('20000000-0000-0000-0000-000000000401', 'scope-workspace-b', 'Scope Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('11000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401', 'manager', 'Manager A'),
  ('21000000-0000-0000-0000-000000000401', '20000000-0000-0000-0000-000000000401', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('30000000-0000-0000-0000-000000000401', 'property.read', 'Property Read'),
  ('30000000-0000-0000-0000-000000000402', 'property.update', 'Property Update');

insert into public.role_permissions (id, workspace_id, role_id, permission_id) values
  ('41000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401', '11000000-0000-0000-0000-000000000401', '30000000-0000-0000-0000-000000000401'),
  ('41000000-0000-0000-0000-000000000402', '10000000-0000-0000-0000-000000000401', '11000000-0000-0000-0000-000000000401', '30000000-0000-0000-0000-000000000402'),
  ('42000000-0000-0000-0000-000000000401', '20000000-0000-0000-0000-000000000401', '21000000-0000-0000-0000-000000000401', '30000000-0000-0000-0000-000000000401'),
  ('42000000-0000-0000-0000-000000000402', '20000000-0000-0000-0000-000000000401', '21000000-0000-0000-0000-000000000401', '30000000-0000-0000-0000-000000000402');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('51000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401', 'a0000000-0000-0000-0000-000000000401', '11000000-0000-0000-0000-000000000401', 'active'),
  ('51000000-0000-0000-0000-000000000402', '10000000-0000-0000-0000-000000000401', 'a0000000-0000-0000-0000-000000000402', '11000000-0000-0000-0000-000000000401', 'active'),
  ('51000000-0000-0000-0000-000000000403', '10000000-0000-0000-0000-000000000401', 'a0000000-0000-0000-0000-000000000403', '11000000-0000-0000-0000-000000000401', 'active'),
  ('52000000-0000-0000-0000-000000000401', '20000000-0000-0000-0000-000000000401', 'b0000000-0000-0000-0000-000000000401', '21000000-0000-0000-0000-000000000401', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country,
  property_type, units, status, created_by, updated_by
) values
  ('71000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401', 'Allowed A', 'Street 1', '10115', 'Berlin', 'de', 'office', 1, 'active', 'a0000000-0000-0000-0000-000000000401', 'a0000000-0000-0000-0000-000000000401'),
  ('71000000-0000-0000-0000-000000000402', '10000000-0000-0000-0000-000000000401', 'Denied A', 'Street 2', '10115', 'Berlin', 'de', 'office', 1, 'active', 'a0000000-0000-0000-0000-000000000401', 'a0000000-0000-0000-0000-000000000401'),
  ('72000000-0000-0000-0000-000000000401', '20000000-0000-0000-0000-000000000401', 'Foreign B', 'Street 3', '20095', 'Hamburg', 'de', 'office', 1, 'active', 'b0000000-0000-0000-0000-000000000401', 'b0000000-0000-0000-0000-000000000401');

insert into public.entity_scopes (
  id, workspace_id, membership_id, entity_type, entity_id
) values
  ('61000000-0000-0000-0000-000000000401', '10000000-0000-0000-0000-000000000401', '51000000-0000-0000-0000-000000000401', 'property', '71000000-0000-0000-0000-000000000401'),
  ('61000000-0000-0000-0000-000000000403', '10000000-0000-0000-0000-000000000401', '51000000-0000-0000-0000-000000000403', 'portfolio', '81000000-0000-0000-0000-000000000401');

select throws_ok(
  $$insert into public.entity_scopes (
      workspace_id, membership_id, entity_type, entity_id
    ) values (
      '10000000-0000-0000-0000-000000000401',
      '51000000-0000-0000-0000-000000000402',
      'unknown',
      '71000000-0000-0000-0000-000000000402'
    )$$,
  '23514', null,
  'unknown scope types fail closed at write time'
);

select set_config('request.jwt.claims', '{"aal":"aal2"}', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000402', true);
select is((select count(*)::integer from public.properties), 2, 'unscoped member reads its workspace');
select is((select count(*)::integer from public.properties where workspace_id = '20000000-0000-0000-0000-000000000401'), 0, 'unscoped member reads no foreign workspace');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000401', true);
select is((select count(*)::integer from public.properties), 1, 'property-scoped member reads one allowed property');
select is((select count(*)::integer from public.properties where id = '71000000-0000-0000-0000-000000000402'), 0, 'property-scoped member cannot read a sibling property');
select ok(private.has_entity_scope('10000000-0000-0000-0000-000000000401', 'property', '71000000-0000-0000-0000-000000000401'), 'exact property scope matches');
select ok(not private.has_entity_scope('10000000-0000-0000-0000-000000000401', 'property', '71000000-0000-0000-0000-000000000402'), 'missing property scope denies');
select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000401', '71000000-0000-0000-0000-000000000401', 1,
    '91000000-0000-0000-0000-000000000401', '92000000-0000-0000-0000-000000000401',
    '{"name":"Allowed Updated"}'::jsonb
  ) ->> 'ok',
  'true',
  'scoped property update succeeds'
);
select is(
  public.update_property(
    '10000000-0000-0000-0000-000000000401', '71000000-0000-0000-0000-000000000402', 1,
    '91000000-0000-0000-0000-000000000402', '92000000-0000-0000-0000-000000000402',
    '{"name":"Must Stay Hidden"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'out-of-scope property update is forbidden'
);

reset role;
select is((select name from public.properties where id = '71000000-0000-0000-0000-000000000402'), 'Denied A', 'denied mutation leaves data unchanged');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000403', true);
select ok(private.has_entity_scope('10000000-0000-0000-0000-000000000401', 'portfolio', '81000000-0000-0000-0000-000000000401'), 'exact portfolio scope matches');
select ok(not private.has_entity_scope('10000000-0000-0000-0000-000000000401', 'property', '71000000-0000-0000-0000-000000000401'), 'portfolio scope does not imply property access without a mapping');
select is((select count(*)::integer from public.properties), 0, 'portfolio-only scope exposes no property without a mapping');
select ok(not private.has_entity_scope('10000000-0000-0000-0000-000000000401', 'unknown', '71000000-0000-0000-0000-000000000401'), 'unknown target type is denied');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000401', true);
select is((select count(*)::integer from public.properties), 1, 'second workspace sees only its own property');

select * from finish();
rollback;
