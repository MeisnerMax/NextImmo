begin;

create extension if not exists pgtap with schema extensions;

select plan(68);

-- === Schema surface ===================================================

select has_table('public', 'parties', 'parties table exists');
select has_table('public', 'party_roles', 'party_roles table exists');
select has_table('public', 'party_contractor_details', 'contractor satellite exists');
select has_table('public', 'party_aliases', 'party_aliases table exists');
select has_type('public', 'party_type', 'party_type enum exists');
select has_type('public', 'party_role_type', 'party_role_type enum exists');
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.party_type'::regtype),
  array['person', 'organization'],
  'party_type enum has the contract labels'
);
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.party_role_type'::regtype),
  array['tenant', 'contractor', 'buyer', 'bank', 'company'],
  'party_role_type enum has the contract labels'
);

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in (
     'public.parties'::regclass, 'public.party_roles'::regclass,
     'public.party_contractor_details'::regclass, 'public.party_aliases'::regclass
   )),
  'all P2-D02 tables enable and force RLS'
);
select policies_are('public', 'parties', array['parties_select_party_read']);
select policies_are('public', 'party_roles', array['party_roles_select_party_read']);
select policies_are('public', 'party_contractor_details', array['party_contractor_details_select_party_read']);
select policies_are('public', 'party_aliases', array['party_aliases_select_party_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('parties', 'party_roles', 'party_contractor_details', 'party_aliases')
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no party DML grants'
);

select has_function('public', 'create_party', array['uuid', 'text', 'text', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'text']);
select has_function('public', 'update_party', array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text']);
select has_function('public', 'assign_party_role', array['uuid', 'uuid', 'text', 'uuid', 'uuid', 'timestamptz', 'timestamptz', 'jsonb', 'text']);
select has_function('public', 'end_party_role', array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'timestamptz', 'text']);
select has_function('public', 'merge_parties', array['uuid', 'uuid', 'uuid', 'bigint', 'bigint', 'uuid', 'uuid', 'text']);
select has_function('public', 'detect_party_duplicates', array['uuid', 'text', 'text', 'text']);

select ok(
  (select bool_and(
     function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in (
       'create_party', 'update_party', 'assign_party_role',
       'end_party_role', 'merge_parties', 'detect_party_duplicates'
     )),
  'party RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_party', 'update_party', 'assign_party_role',
       'end_party_role', 'merge_parties', 'detect_party_duplicates'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute party RPCs'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d02-admin-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d02-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fa000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d02-viewer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d02-admin-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('f1000000-0000-0000-0000-000000000001', 'p2d02-workspace-a', 'P2D02 Workspace A'),
  ('f2000000-0000-0000-0000-000000000001', 'p2d02-workspace-b', 'P2D02 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('f3000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('f3000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('f3000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer A'),
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('f5000000-0000-0000-0000-000000000001', 'party.read', 'Party Read'),
  ('f5000000-0000-0000-0000-000000000002', 'party.manage', 'Party Manage'),
  ('f5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000003'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000003'),
  ('f1000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000003', 'f5000000-0000-0000-0000-000000000003'),
  ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001'),
  ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002'),
  ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'active'),
  ('f6000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000002', 'active'),
  ('f6000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000003', 'f3000000-0000-0000-0000-000000000003', 'active'),
  ('f6000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'active');

create temporary table p2_d02_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d02_results to authenticated;

-- === create_party =====================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);

insert into p2_d02_results (key, result)
select 'create_alice', public.create_party(
  'f1000000-0000-0000-0000-000000000001', 'person', '  Alice Example  ',
  'fe000000-0000-0000-0000-000000000001', 'fc000000-0000-0000-0000-000000000001',
  null, 'Alice@Example.test', '+49 30 111', null, 'create alice'
);

select is((select result ->> 'ok' from p2_d02_results where key = 'create_alice'), 'true', 'create_party succeeds');
select is((select result #>> '{entity,display_name}' from p2_d02_results where key = 'create_alice'), 'Alice Example', 'display name is trimmed');
select is((select result #>> '{entity,email}' from p2_d02_results where key = 'create_alice'), 'alice@example.test', 'email is normalized');
select is((select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'create_alice'), 1::bigint, 'a new party starts at version 1');

-- A reader without party.manage cannot create.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
select is(
  public.create_party(
    'f1000000-0000-0000-0000-000000000001', 'person', 'Blocked',
    'fe000000-0000-0000-0000-000000000002', 'fc000000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'a member without party.manage cannot create a party'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select is(
  public.create_party(
    'f1000000-0000-0000-0000-000000000001', 'alien', 'Bad Type',
    'fe000000-0000-0000-0000-000000000003', 'fc000000-0000-0000-0000-000000000003'
  ) #>> '{error,code}',
  'validation_failed',
  'an unknown party type is rejected'
);

-- A second party sharing Alice's email/phone, for duplicate detection later.
insert into p2_d02_results (key, result)
select 'create_bob', public.create_party(
  'f1000000-0000-0000-0000-000000000001', 'person', 'Bob Builder',
  'fe000000-0000-0000-0000-000000000004', 'fc000000-0000-0000-0000-000000000004',
  null, 'bob@example.test', '004930111', null, null
);
select is((select result ->> 'ok' from p2_d02_results where key = 'create_bob'), 'true', 'a second party is created');

-- === update_party =====================================================

insert into p2_d02_results (key, result)
select 'update_alice', public.update_party(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
  1,
  'fe000000-0000-0000-0000-000000000005', 'fc000000-0000-0000-0000-000000000005',
  jsonb_build_object('legal_name', 'Alice Example GmbH', 'phone', '+49 30 999'),
  'update alice'
);
select is((select result #>> '{entity,legal_name}' from p2_d02_results where key = 'update_alice'), 'Alice Example GmbH', 'update applies the legal name');
select is((select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'update_alice'), 2::bigint, 'update increments the version');

select is(
  public.update_party(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
    1,
    'fe000000-0000-0000-0000-000000000006', 'fc000000-0000-0000-0000-000000000006',
    jsonb_build_object('phone', '+49 30 000')
  ) #>> '{error,code}',
  'version_conflict',
  'a stale party version returns a structured conflict'
);

select is(
  public.update_party(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
    1,
    'fe000000-0000-0000-0000-000000000005', 'fc000000-0000-0000-0000-000000000005',
    jsonb_build_object('legal_name', 'Alice Example GmbH', 'phone', '+49 30 999'),
    'update alice'
  ),
  (select result from p2_d02_results where key = 'update_alice'),
  'an update replay returns the identical result'
);

-- === assign_party_role + contractor satellite =========================

insert into p2_d02_results (key, result)
select 'assign_tenant', public.assign_party_role(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
  'tenant',
  'fe000000-0000-0000-0000-000000000007', 'fc000000-0000-0000-0000-000000000007',
  null, null, null, 'assign tenant role'
);
select is((select result #>> '{entity,role_type}' from p2_d02_results where key = 'assign_tenant'), 'tenant', 'a tenant role is assigned');

select is(
  public.assign_party_role(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
    'tenant',
    'fe000000-0000-0000-0000-000000000008', 'fc000000-0000-0000-0000-000000000008'
  ) #>> '{error,code}',
  'validation_failed',
  'a second open role of the same type is rejected'
);

insert into p2_d02_results (key, result)
select 'assign_contractor', public.assign_party_role(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob'),
  'contractor',
  'fe000000-0000-0000-0000-000000000009', 'fc000000-0000-0000-0000-000000000009',
  null, null,
  jsonb_build_object('trade_category', 'Plumbing', 'hourly_rate', 85.5, 'rating_quality', 4.5),
  'assign contractor role'
);
select is((select result #>> '{entity,role_type}' from p2_d02_results where key = 'assign_contractor'), 'contractor', 'a contractor role is assigned');

reset role;
select is(
  (select trade_category from public.party_contractor_details
   where party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob')),
  'Plumbing',
  'the contractor satellite row is written'
);
select is(
  (select hourly_rate from public.party_contractor_details
   where party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob')),
  85.5::numeric,
  'the contractor hourly rate is stored as numeric'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select is(
  public.assign_party_role(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
    'buyer',
    'fe000000-0000-0000-0000-000000000010', 'fc000000-0000-0000-0000-000000000010',
    null, null,
    jsonb_build_object('trade_category', 'Plumbing')
  ) #>> '{error,code}',
  'validation_failed',
  'role details are rejected on a non-contractor role'
);

-- === end_party_role ===================================================

insert into p2_d02_results (key, result)
select 'end_tenant', public.end_party_role(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'assign_tenant'),
  1,
  'fe000000-0000-0000-0000-000000000011', 'fc000000-0000-0000-0000-000000000011',
  null, 'end tenant role'
);
select isnt((select result #>> '{entity,valid_until}' from p2_d02_results where key = 'end_tenant'), null, 'ending a role sets valid_until');
select is((select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'end_tenant'), 2::bigint, 'ending a role increments its version');
select is(
  public.end_party_role(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'assign_tenant'),
    2,
    'fe000000-0000-0000-0000-000000000012', 'fc000000-0000-0000-0000-000000000012'
  ) #>> '{error,code}',
  'validation_failed',
  'a role that is already time-bound cannot be ended again'
);

-- Re-assigning the tenant role is allowed once the prior one is closed.
select is(
  public.assign_party_role(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_alice'),
    'tenant',
    'fe000000-0000-0000-0000-000000000013', 'fc000000-0000-0000-0000-000000000013'
  ) ->> 'ok',
  'true',
  'a fresh open role can be assigned after the prior one is closed'
);

-- === Duplicate detection ==============================================

-- Alice and Bob share no email, but a probe on Bob's email/phone matches Bob.
select is(
  (select jsonb_array_length(
     (public.detect_party_duplicates(
       'f1000000-0000-0000-0000-000000000001', 'Someone Else', 'BOB@example.test', null
     )) -> 'entity')),
  1,
  'duplicate detection matches on normalized email'
);
select is(
  (public.detect_party_duplicates(
    'f1000000-0000-0000-0000-000000000001', 'Someone Else', 'bob@example.test', null
  )) #>> '{entity,0,match_email}',
  'true',
  'the email match reason is reported'
);
select is(
  (select jsonb_array_length(
     (public.detect_party_duplicates(
       'f1000000-0000-0000-0000-000000000001', 'bob builder', null, null
     )) -> 'entity')),
  1,
  'duplicate detection matches on normalized display name'
);
select is(
  (select jsonb_array_length(
     (public.detect_party_duplicates(
       'f1000000-0000-0000-0000-000000000001', null, null, '0049 30 111'
     )) -> 'entity')),
  1,
  'duplicate detection matches on normalized phone digits'
);
select is(
  (public.detect_party_duplicates(
    'f1000000-0000-0000-0000-000000000001', null, null, null
  )) #>> '{error,code}',
  'validation_failed',
  'duplicate detection requires at least one probe attribute'
);

-- === Merge ============================================================

-- Create a duplicate of Bob, give it a role and contractor details, then merge
-- it into the canonical Bob.
insert into p2_d02_results (key, result)
select 'create_bob_dup', public.create_party(
  'f1000000-0000-0000-0000-000000000001', 'organization', 'Bob Builder Ltd',
  'fe000000-0000-0000-0000-000000000014', 'fc000000-0000-0000-0000-000000000014',
  'Bob Builder Limited', 'bob.dup@example.test', '004930222', null, null
);
insert into p2_d02_results (key, result)
select 'assign_dup_bank', public.assign_party_role(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup'),
  'bank',
  'fe000000-0000-0000-0000-000000000015', 'fc000000-0000-0000-0000-000000000015'
);

insert into p2_d02_results (key, result)
select 'merge', public.merge_parties(
  'f1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob'),
  (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup'),
  (select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'create_bob'),
  1,
  'fe000000-0000-0000-0000-000000000016', 'fc000000-0000-0000-0000-000000000016',
  'merge duplicate bob'
);
select is((select result ->> 'ok' from p2_d02_results where key = 'merge'), 'true', 'a merge succeeds');

reset role;
select ok(
  (select party.deleted_at is not null
     and party.merged_into_party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob')
   from public.parties as party
   where party.id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup')),
  'the merged source is tombstoned and points at the target'
);
select is(
  (select count(*)::integer from public.party_roles as role
   where role.party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob')
     and role.role_type = 'bank' and role.valid_until is not null),
  1,
  'the source role is re-pointed onto the target and closed'
);
select is(
  (select count(*)::integer from public.party_roles as role
   where role.party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup')),
  0,
  'no role remains attached to the tombstoned source'
);
select is(
  (select alias_display_name from public.party_aliases
   where source_party_id = (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup')),
  'Bob Builder Ltd',
  'the source identity is recorded as an alias of the target'
);
select is(
  (select count(*)::integer from public.audit_events where action = 'party.merge'),
  1,
  'a merge writes one party.merge audit event'
);
select ok(
  (select (result #>> '{entity,version}')::bigint > (select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'create_bob')
   from p2_d02_results where key = 'merge'),
  'the surviving target version is bumped by the merge'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000001', true);
select is(
  public.merge_parties(
    'f1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob'),
    (select (result #>> '{entity,id}')::uuid from p2_d02_results where key = 'create_bob_dup'),
    (select (result #>> '{entity,version}')::bigint from p2_d02_results where key = 'create_bob'),
    1,
    'fe000000-0000-0000-0000-000000000016', 'fc000000-0000-0000-0000-000000000016',
    'merge duplicate bob'
  ),
  (select result from p2_d02_results where key = 'merge'),
  'a merge replay returns the identical result'
);

-- The tombstoned source no longer surfaces as a duplicate candidate.
select is(
  (select jsonb_array_length(
     (public.detect_party_duplicates(
       'f1000000-0000-0000-0000-000000000001', 'Bob Builder Ltd', null, null
     )) -> 'entity')),
  0,
  'a merged party is excluded from duplicate detection'
);

-- === Role-scoped read + permission isolation ==========================

-- A reader (party.read, no manage) can list roles filtered by type.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::integer from public.party_roles where role_type = 'contractor'),
  1,
  'a reader can role-scope the party_roles read'
);
select ok(
  (select count(*) >= 2 from public.parties),
  'a reader with party.read sees the workspace parties'
);

-- A viewer without party.read sees nothing (default deny).
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fa000000-0000-0000-0000-000000000003', true);
select is((select count(*)::integer from public.parties), 0, 'a member without party.read sees no parties');
select is((select count(*)::integer from public.party_roles), 0, 'a member without party.read sees no roles');

-- === Two-workspace isolation ==========================================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.parties), 0, 'a foreign workspace admin sees no workspace A parties');
select is(
  public.create_party(
    'f1000000-0000-0000-0000-000000000001', 'person', 'Cross Workspace',
    'fe000000-0000-0000-0000-000000000017', 'fc000000-0000-0000-0000-000000000017'
  ) #>> '{error,code}',
  'forbidden',
  'a foreign workspace admin cannot create a party in workspace A'
);

-- === Direct DML and anonymous access stay closed ======================

select throws_ok(
  $$update public.parties set display_name = 'hack'
    where workspace_id = 'f1000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'authenticated direct party UPDATE is denied'
);
select throws_ok(
  $$insert into public.party_roles (workspace_id, party_id, role_type, created_by, updated_by)
    values ('f1000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-000000000001', 'tenant',
            'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'authenticated direct role INSERT is denied'
);

reset role;
set local role anon;
select throws_ok(
  $$select public.create_party(
      'f1000000-0000-0000-0000-000000000001', 'person', 'Anon',
      'fe000000-0000-0000-0000-000000000018', 'fc000000-0000-0000-0000-000000000018'
    )$$,
  '42501', null, 'anon cannot execute party RPCs'
);
select throws_ok(
  $$select * from public.parties$$,
  '42501', null, 'anon cannot select parties'
);

reset role;
select is(
  (select count(*)::integer from public.mutation_receipts where status = 'pending'),
  0,
  'no failed party command leaves a pending receipt behind'
);

select * from finish();

rollback;
