begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- ---------------------------------------------------------------- primitives

select has_function(
  'private',
  'has_entity_scope',
  array['uuid', 'text', 'uuid'],
  'entity scope primitive exists'
);
select has_function(
  'private',
  'has_scoped_entity_permission',
  array['uuid', 'text', 'text', 'uuid'],
  'scoped permission primitive exists'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name in ('has_entity_scope', 'has_scoped_entity_permission')
     and grantee in ('PUBLIC', 'anon')),
  0,
  'anonymous callers cannot execute the scope primitives'
);

-- ------------------------------------------------------------------ fixtures

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ab010000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ph-01@example.test', '', now(), '{}', '{}', now(), now()
);

insert into public.workspaces (id, key, name) values
  ('1b010000-0000-4000-8000-000000000001', 'ph-01-a', 'PH-01 A'),
  ('2b010000-0000-4000-8000-000000000001', 'ph-01-b', 'PH-01 B');

insert into public.roles (id, workspace_id, key, name) values (
  '1b010000-0000-4000-8000-000000000002',
  '1b010000-0000-4000-8000-000000000001',
  'property_manager', 'Property Manager'
);

-- property.delete exists but is deliberately never granted: it is the
-- "permission missing while scope matches" case.
insert into public.permissions (id, key, name) values
  ('3b010000-0000-4000-8000-000000000001', 'property.read', 'Property Read'),
  ('3b010000-0000-4000-8000-000000000002', 'property.update', 'Property Update'),
  ('3b010000-0000-4000-8000-000000000003', 'property.delete', 'Property Delete');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('1b010000-0000-4000-8000-000000000001', '1b010000-0000-4000-8000-000000000002', '3b010000-0000-4000-8000-000000000001'),
  ('1b010000-0000-4000-8000-000000000001', '1b010000-0000-4000-8000-000000000002', '3b010000-0000-4000-8000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values (
  '4b010000-0000-4000-8000-000000000001',
  '1b010000-0000-4000-8000-000000000001',
  'ab010000-0000-4000-8000-000000000001',
  '1b010000-0000-4000-8000-000000000002',
  'active'
);

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values
  ('7b010000-0000-4000-8000-000000000001', '1b010000-0000-4000-8000-000000000001',
   'Property A', 'A Street 1', '10115', 'Berlin', 'de', 'office', 1, 'active',
   'ab010000-0000-4000-8000-000000000001', 'ab010000-0000-4000-8000-000000000001'),
  ('7b010000-0000-4000-8000-000000000002', '1b010000-0000-4000-8000-000000000001',
   'Property B', 'B Street 2', '10117', 'Berlin', 'de', 'office', 1, 'active',
   'ab010000-0000-4000-8000-000000000001', 'ab010000-0000-4000-8000-000000000001'),
  ('7b010000-0000-4000-8000-000000000003', '2b010000-0000-4000-8000-000000000001',
   'Foreign Property', 'C Street 3', '20095', 'Hamburg', 'de', 'office', 1, 'active',
   'ab010000-0000-4000-8000-000000000001', 'ab010000-0000-4000-8000-000000000001');

-- --------------------------------------------------------------- schema guard

select lives_ok(
  $$insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
    values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
            'property', '7b010000-0000-4000-8000-000000000001')$$,
  'property is an accepted entity scope type'
);

-- portfolio is NOT accepted yet. The baseline names it, but this schema has no
-- portfolios table and no property-to-portfolio relationship, so a portfolio
-- scope row could be written and could never match -- silently turning a
-- restriction into a total denial. It is allowed together with the table and
-- the inheritance rule in P2-D09.
select throws_ok(
  $$insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
    values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
            'portfolio', '7b010000-0000-4000-8000-000000000002')$$,
  '23514',
  null,
  'portfolio is rejected until the portfolios domain ships'
);
select throws_ok(
  $$insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
    values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
            'unit', '7b010000-0000-4000-8000-000000000002')$$,
  '23514',
  null,
  'unit is rejected: child entities inherit from their property'
);
select throws_ok(
  $$insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
    values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
            'lease', '7b010000-0000-4000-8000-000000000002')$$,
  '23514',
  null,
  'lease is rejected: child entities inherit from their property'
);
select throws_ok(
  $$insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
    values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
            'nonsense', '7b010000-0000-4000-8000-000000000002')$$,
  '23514',
  null,
  'an unknown entity type fails closed at the schema'
);

-- The fixture above already created one scope row, so the membership is now
-- restricted. Remove it again to exercise the unrestricted default first.
delete from public.entity_scopes
where membership_id = '4b010000-0000-4000-8000-000000000001';

-- ------------------------------------------------- scope primitive semantics

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ab010000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"ab010000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select ok(
  private.has_entity_scope(
    '1b010000-0000-4000-8000-000000000001', 'property',
    '7b010000-0000-4000-8000-000000000001'),
  'a membership without any scope rows keeps workspace-wide access'
);
select ok(
  not private.has_entity_scope(
    '1b010000-0000-4000-8000-000000000001', 'unit',
    '7b010000-0000-4000-8000-000000000001'),
  'an unsupported entity type is denied even without scope rows'
);
select ok(
  not private.has_entity_scope(
    '2b010000-0000-4000-8000-000000000001', 'property',
    '7b010000-0000-4000-8000-000000000003'),
  'a workspace without membership is denied'
);

select is(
  (select count(*)::integer from public.properties),
  2,
  'unscoped membership reads every permitted property in its workspace'
);

reset role;
insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
values ('1b010000-0000-4000-8000-000000000001', '4b010000-0000-4000-8000-000000000001',
        'property', '7b010000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ab010000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"ab010000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select ok(
  private.has_entity_scope(
    '1b010000-0000-4000-8000-000000000001', 'property',
    '7b010000-0000-4000-8000-000000000001'),
  'a matching scope grants access'
);
select ok(
  not private.has_entity_scope(
    '1b010000-0000-4000-8000-000000000001', 'property',
    '7b010000-0000-4000-8000-000000000002'),
  'once scoped, a non-matching property is denied'
);

-- -------------------------------------------- permission and scope combined

select ok(
  private.has_scoped_entity_permission(
    '1b010000-0000-4000-8000-000000000001', 'property.read', 'property',
    '7b010000-0000-4000-8000-000000000001'),
  'permission true and scope true grants'
);
select ok(
  not private.has_scoped_entity_permission(
    '1b010000-0000-4000-8000-000000000001', 'property.read', 'property',
    '7b010000-0000-4000-8000-000000000002'),
  'permission true and scope false denies'
);
select ok(
  not private.has_scoped_entity_permission(
    '1b010000-0000-4000-8000-000000000001', 'property.delete', 'property',
    '7b010000-0000-4000-8000-000000000001'),
  'a scope never substitutes for a missing workspace permission'
);

-- --------------------------------------------------------- property SELECT

select is(
  (select count(*)::integer from public.properties),
  1,
  'a scoped membership reads only the scoped property'
);
select is(
  (select name from public.properties),
  'Property A',
  'the visible property is the scoped one'
);
select is(
  (select count(*)::integer from public.properties
   where id = '7b010000-0000-4000-8000-000000000003'),
  0,
  'a foreign workspace stays invisible'
);

-- --------------------------------------------------------- property UPDATE

select is(
  public.update_property(
    '1b010000-0000-4000-8000-000000000001',
    '7b010000-0000-4000-8000-000000000002', 1,
    '6b010000-0000-4000-8000-000000000001',
    '9b010000-0000-4000-8000-000000000001',
    '{"name":"Out of scope"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'updating an out-of-scope property is denied'
);
select is(
  public.update_property(
    '1b010000-0000-4000-8000-000000000001',
    '7b010000-0000-4000-8000-000000000001', 1,
    '6b010000-0000-4000-8000-000000000002',
    '9b010000-0000-4000-8000-000000000002',
    '{"name":"Property A2"}'::jsonb
  ) #>> '{ok}',
  'true',
  'AAL2 with permission and scope updates the scoped property'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ab010000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);
select is(
  public.update_property(
    '1b010000-0000-4000-8000-000000000001',
    '7b010000-0000-4000-8000-000000000001', 2,
    '6b010000-0000-4000-8000-000000000003',
    '9b010000-0000-4000-8000-000000000003',
    '{"name":"AAL1 denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'AAL1 stays denied after the scope guard was added'
);

-- ------------------------------------------------------ revoked membership

reset role;
update public.memberships
   set status = 'revoked'
 where id = '4b010000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ab010000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"ab010000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select ok(
  not private.has_entity_scope(
    '1b010000-0000-4000-8000-000000000001', 'property',
    '7b010000-0000-4000-8000-000000000001'),
  'a revoked membership loses its scope match'
);
select is(
  (select count(*)::integer from public.properties),
  0,
  'a revoked membership reads nothing'
);
select is(
  public.update_property(
    '1b010000-0000-4000-8000-000000000001',
    '7b010000-0000-4000-8000-000000000001', 2,
    '6b010000-0000-4000-8000-000000000004',
    '9b010000-0000-4000-8000-000000000004',
    '{"name":"Revoked denied"}'::jsonb
  ) #>> '{error,code}',
  'forbidden',
  'a revoked membership cannot update'
);

reset role;
select is(
  (select name from public.properties where id = '7b010000-0000-4000-8000-000000000001'),
  'Property A2',
  'only the one permitted update was applied'
);
select is(
  (select name from public.properties where id = '7b010000-0000-4000-8000-000000000002'),
  'Property B',
  'the out-of-scope property was never mutated'
);

select * from finish();
rollback;
