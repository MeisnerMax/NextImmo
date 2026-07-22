begin;

create extension if not exists pgtap with schema extensions;

select plan(69);

-- === Schema surface ===================================================

select has_table('public', 'membership_invitations', 'membership_invitations exists');
select has_type('public', 'membership_invitation_status', 'invitation status enum exists');
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum
   where enum.enumtypid = 'public.membership_invitation_status'::regtype),
  array['pending', 'accepted', 'revoked'],
  'invitation status enum has the contract labels'
);
select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   where class.oid = 'public.membership_invitations'::regclass),
  'membership_invitations enables and forces RLS'
);
select policies_are('public', 'memberships', array['memberships_select_authorized']);
select policies_are(
  'public', 'membership_invitations',
  array['membership_invitations_select_security_manage']
);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'membership_invitations'
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no invitation DML grants'
);

select has_function('public', 'invite_workspace_member', array['uuid', 'text', 'uuid', 'uuid', 'uuid', 'text']);
select has_function('public', 'list_my_pending_invitations', '{}'::text[]);
select has_function('public', 'accept_workspace_invitation', array['uuid', 'uuid', 'uuid', 'text']);
select has_function('public', 'update_membership_status', array['uuid', 'uuid', 'public.membership_status', 'bigint', 'uuid', 'uuid', 'text']);
select has_function('public', 'change_membership_role', array['uuid', 'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text']);
select has_function('public', 'revoke_workspace_invitation', array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text']);

select ok(
  (select bool_and(
     function.prosecdef
     and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in (
       'invite_workspace_member', 'list_my_pending_invitations',
       'accept_workspace_invitation', 'update_membership_status',
       'change_membership_role', 'revoke_workspace_invitation'
     )),
  'membership RPCs are postgres security definers with fixed search path'
);

select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'invite_workspace_member', 'list_my_pending_invitations',
       'accept_workspace_invitation', 'update_membership_status',
       'change_membership_role', 'revoke_workspace_invitation'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute membership RPCs'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ea000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-admin-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-viewer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-existing@example.test', '', now(), '{}', '{}', now(), now()),
  ('eb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d01-admin-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'p2d01-workspace-a', 'P2D01 Workspace A'),
  ('e2000000-0000-0000-0000-000000000001', 'p2d01-workspace-b', 'P2D01 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('e3000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer A'),
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('e5000000-0000-0000-0000-000000000001', 'security.manage', 'Security Manage'),
  ('e5000000-0000-0000-0000-000000000002', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000002'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e6000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'active'),
  ('e6000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'active'),
  ('e6000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'active');

create temporary table p2_d01_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d01_results to authenticated;

-- === AAL2 gate ========================================================

select set_config('request.jwt.claims', '{"aal":"aal1"}', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'p2d01-existing@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001'
  ) #>> '{error,code}',
  'forbidden',
  'membership mutations require AAL2'
);

reset role;
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);

-- === Invite an existing auth user -> membership status invited ========

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d01_results (key, result)
select 'invite_existing', public.invite_workspace_member(
  'e1000000-0000-0000-0000-000000000001', 'P2D01-Existing@example.test ',
  'e3000000-0000-0000-0000-000000000002',
  'ee000000-0000-0000-0000-000000000002', 'ec000000-0000-0000-0000-000000000002',
  'invite existing user'
);

select is((select result ->> 'ok' from p2_d01_results where key = 'invite_existing'), 'true', 'inviting an existing auth user succeeds');
select is(
  (select result #>> '{entity,status}' from p2_d01_results where key = 'invite_existing'),
  'invited',
  'existing-user invite creates a membership in status invited'
);

reset role;
select is(
  (select status from public.memberships where user_id = 'ea000000-0000-0000-0000-000000000003'),
  'invited'::public.membership_status,
  'invited membership row is stored'
);
select is(
  (select count(*)::integer from public.audit_events where action = 'membership.invite'),
  1,
  'invite writes one membership.invite audit event'
);

-- === Invitee view: own row, pending list, but no workspace access =====

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);

select is((select count(*)::integer from public.memberships), 1, 'invited user sees exactly their own membership row');
select is(
  (select jsonb_array_length(public.list_my_pending_invitations())),
  1,
  'invited user sees one pending invitation'
);
select is(
  (select public.list_my_pending_invitations() #>> '{0,kind}'),
  'membership',
  'pending entry is the invited membership'
);
select is(
  (select public.list_my_pending_invitations() #>> '{0,workspace_name}'),
  'P2D01 Workspace A',
  'pending entry names the workspace the invitee could not otherwise read'
);
select is((select count(*)::integer from public.workspaces), 0, 'invited status grants no workspace access');

-- === Accept: invited -> active, idempotent ============================

insert into p2_d01_results (key, result)
select 'accept', public.accept_workspace_invitation(
  'e1000000-0000-0000-0000-000000000001',
  'ee000000-0000-0000-0000-000000000003', 'ec000000-0000-0000-0000-000000000003',
  'accept invitation'
);

select is((select result #>> '{entity,status}' from p2_d01_results where key = 'accept'), 'active', 'accept activates the membership');
select is((select (result #>> '{entity,version}')::bigint from p2_d01_results where key = 'accept'), 2::bigint, 'accept increments the membership version');
select is(
  public.accept_workspace_invitation(
    'e1000000-0000-0000-0000-000000000001',
    'ee000000-0000-0000-0000-000000000003', 'ec000000-0000-0000-0000-000000000003',
    'accept invitation'
  ),
  (select result from p2_d01_results where key = 'accept'),
  'accept replay returns the identical result'
);
select is((select count(*)::integer from public.workspaces), 1, 'accepted member gains workspace access via the role');

reset role;
select is(
  (select count(*)::integer from public.audit_events where action = 'membership.accept'),
  1,
  'accept writes exactly one audit event despite the replay'
);

-- === Authorization and two-workspace isolation ========================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000002', true);

select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'someone@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000004', 'ec000000-0000-0000-0000-000000000004'
  ) #>> '{error,code}',
  'forbidden',
  'a member without security.manage cannot invite'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'eb000000-0000-0000-0000-000000000001', true);

select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'someone@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000005', 'ec000000-0000-0000-0000-000000000005'
  ) #>> '{error,code}',
  'forbidden',
  'a foreign workspace admin cannot invite across workspaces'
);
select is(
  (select count(*)::integer from public.memberships
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'),
  0,
  'a foreign workspace admin sees no workspace A memberships'
);

-- === Email invitation path (no auth user yet) =========================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d01_results (key, result)
select 'invite_email', public.invite_workspace_member(
  'e1000000-0000-0000-0000-000000000001', 'p2d01-newcomer@example.test',
  'e3000000-0000-0000-0000-000000000002',
  'ee000000-0000-0000-0000-000000000006', 'ec000000-0000-0000-0000-000000000006',
  'invite unknown email'
);

select is((select result ->> 'ok' from p2_d01_results where key = 'invite_email'), 'true', 'inviting an unknown email succeeds');
select is(
  (select result #>> '{entity,email}' from p2_d01_results where key = 'invite_email'),
  'p2d01-newcomer@example.test',
  'unknown email creates a pending invitation entity'
);
select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'p2d01-newcomer@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000007', 'ec000000-0000-0000-0000-000000000007'
  ) #>> '{error,code}',
  'validation_failed',
  'a duplicate pending invitation is rejected'
);
select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'p2d01-admin-a@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000008', 'ec000000-0000-0000-0000-000000000008'
  ) #>> '{error,code}',
  'validation_failed',
  'inviting an existing member is rejected'
);
select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'p2d01-role-check@example.test',
    'e4000000-0000-0000-0000-000000000001',
    'ee000000-0000-0000-0000-000000000009', 'ec000000-0000-0000-0000-000000000009'
  ) #>> '{error,code}',
  'not_found',
  'a foreign workspace role cannot be assigned'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'eb000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.membership_invitations
   where workspace_id = 'e1000000-0000-0000-0000-000000000001'),
  0,
  'a foreign workspace admin sees no workspace A invitations'
);

-- === Revoke and re-issue the email invitation =========================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

select is(
  public.revoke_workspace_invitation(
    'e1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d01_results where key = 'invite_email'),
    99,
    'ee000000-0000-0000-0000-000000000010', 'ec000000-0000-0000-0000-000000000010'
  ) #>> '{error,code}',
  'version_conflict',
  'a stale invitation version returns a structured conflict'
);

insert into p2_d01_results (key, result)
select 'revoke_invitation', public.revoke_workspace_invitation(
  'e1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d01_results where key = 'invite_email'),
  1,
  'ee000000-0000-0000-0000-000000000011', 'ec000000-0000-0000-0000-000000000011',
  'cancel invitation'
);

select is(
  (select result #>> '{entity,status}' from p2_d01_results where key = 'revoke_invitation'),
  'revoked',
  'a pending invitation can be revoked'
);

insert into p2_d01_results (key, result)
select 'invite_email2', public.invite_workspace_member(
  'e1000000-0000-0000-0000-000000000001', 'p2d01-newcomer@example.test',
  'e3000000-0000-0000-0000-000000000002',
  'ee000000-0000-0000-0000-000000000012', 'ec000000-0000-0000-0000-000000000012',
  're-invite after revoke'
);

select is((select result ->> 'ok' from p2_d01_results where key = 'invite_email2'), 'true', 'a revoked email can be re-invited');

-- === Newcomer signs up and accepts ====================================

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ea000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'p2d01-newcomer@example.test', '', now(),
  '{}', '{}', now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000004', true);

select is(
  (select public.list_my_pending_invitations() #>> '{0,kind}'),
  'invitation',
  'the newcomer sees their pending email invitation'
);

insert into p2_d01_results (key, result)
select 'accept_email', public.accept_workspace_invitation(
  'e1000000-0000-0000-0000-000000000001',
  'ee000000-0000-0000-0000-000000000013', 'ec000000-0000-0000-0000-000000000013',
  'accept email invitation'
);

select is((select result #>> '{entity,status}' from p2_d01_results where key = 'accept_email'), 'active', 'accepting an email invitation creates an active membership');

reset role;
select ok(
  (select invitation.status = 'accepted'::public.membership_invitation_status
     and invitation.accepted_membership_id =
       (select (result #>> '{entity,id}')::uuid from p2_d01_results where key = 'accept_email')
   from public.membership_invitations as invitation
   where invitation.id =
     (select (result #>> '{entity,id}')::uuid from p2_d01_results where key = 'invite_email2')),
  'the accepted invitation links its resulting membership'
);

-- === Status transitions (STM-001) =====================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d01_results (key, result)
select 'suspend', public.update_membership_status(
  'e1000000-0000-0000-0000-000000000001',
  'e6000000-0000-0000-0000-000000000002',
  'suspended'::public.membership_status,
  1,
  'ee000000-0000-0000-0000-000000000014', 'ec000000-0000-0000-0000-000000000014',
  'suspend viewer'
);

select is((select result #>> '{entity,status}' from p2_d01_results where key = 'suspend'), 'suspended', 'active membership can be suspended');
select is(
  public.update_membership_status(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000002',
    'suspended'::public.membership_status,
    1,
    'ee000000-0000-0000-0000-000000000014', 'ec000000-0000-0000-0000-000000000014',
    'suspend viewer'
  ),
  (select result from p2_d01_results where key = 'suspend'),
  'suspend replay returns the identical result'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000002', true);

select is((select count(*)::integer from public.workspaces), 0, 'a suspended member loses workspace access');
select ok(
  (select count(*) = 1
     and bool_and(status = 'suspended'::public.membership_status)
   from public.memberships),
  'a suspended member still sees their own membership status'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d01_results (key, result)
select 'reactivate', public.update_membership_status(
  'e1000000-0000-0000-0000-000000000001',
  'e6000000-0000-0000-0000-000000000002',
  'active'::public.membership_status,
  2,
  'ee000000-0000-0000-0000-000000000015', 'ec000000-0000-0000-0000-000000000015',
  'reactivate viewer'
);

select is((select result #>> '{entity,status}' from p2_d01_results where key = 'reactivate'), 'active', 'suspended membership can be reactivated');

select is(
  public.update_membership_status(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000002',
    'invited'::public.membership_status,
    3,
    'ee000000-0000-0000-0000-000000000016', 'ec000000-0000-0000-0000-000000000016'
  ) #>> '{error,code}',
  'validation_failed',
  'a membership cannot transition back to invited'
);

select is(
  public.update_membership_status(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000002',
    'revoked'::public.membership_status,
    99,
    'ee000000-0000-0000-0000-000000000017', 'ec000000-0000-0000-0000-000000000017'
  ) #>> '{error,code}',
  'version_conflict',
  'a stale membership version returns a structured conflict'
);

insert into p2_d01_results (key, result)
select 'revoke', public.update_membership_status(
  'e1000000-0000-0000-0000-000000000001',
  'e6000000-0000-0000-0000-000000000002',
  'revoked'::public.membership_status,
  3,
  'ee000000-0000-0000-0000-000000000018', 'ec000000-0000-0000-0000-000000000018',
  'revoke viewer'
);

select is((select result #>> '{entity,status}' from p2_d01_results where key = 'revoke'), 'revoked', 'active membership can be revoked');

select is(
  public.update_membership_status(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000002',
    'active'::public.membership_status,
    4,
    'ee000000-0000-0000-0000-000000000019', 'ec000000-0000-0000-0000-000000000019'
  ) #>> '{error,code}',
  'validation_failed',
  'revoked is terminal'
);

select is(
  public.invite_workspace_member(
    'e1000000-0000-0000-0000-000000000001', 'p2d01-viewer-a@example.test',
    'e3000000-0000-0000-0000-000000000002',
    'ee000000-0000-0000-0000-000000000020', 'ec000000-0000-0000-0000-000000000020'
  ) #>> '{error,code}',
  'validation_failed',
  'a revoked member cannot be re-invited while the membership row remains'
);

reset role;
select is(
  (select count(*)::integer from public.audit_events
   where action in ('membership.suspend', 'membership.reactivate', 'membership.revoke')),
  3,
  'each admin transition writes its own audit action'
);

-- === Last-admin guard =================================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

select is(
  public.update_membership_status(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000001',
    'revoked'::public.membership_status,
    1,
    'ee000000-0000-0000-0000-000000000021', 'ec000000-0000-0000-0000-000000000021'
  ) #>> '{error,code}',
  'validation_failed',
  'the last security manager cannot be revoked'
);
select is(
  public.change_membership_role(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000002',
    1,
    'ee000000-0000-0000-0000-000000000022', 'ec000000-0000-0000-0000-000000000022'
  ) #>> '{error,code}',
  'validation_failed',
  'the last security manager cannot lose the managing role'
);

-- === Role change ======================================================

select is(
  public.change_membership_role(
    'e1000000-0000-0000-0000-000000000001',
    (select membership.id from public.memberships as membership
     where membership.user_id = 'ea000000-0000-0000-0000-000000000003'),
    'e4000000-0000-0000-0000-000000000001',
    2,
    'ee000000-0000-0000-0000-000000000023', 'ec000000-0000-0000-0000-000000000023'
  ) #>> '{error,code}',
  'not_found',
  'a foreign workspace role cannot be assigned via role change'
);
select is(
  public.change_membership_role(
    'e1000000-0000-0000-0000-000000000001',
    (select membership.id from public.memberships as membership
     where membership.user_id = 'ea000000-0000-0000-0000-000000000003'),
    'e3000000-0000-0000-0000-000000000002',
    2,
    'ee000000-0000-0000-0000-000000000024', 'ec000000-0000-0000-0000-000000000024'
  ) #>> '{error,code}',
  'validation_failed',
  'assigning the current role is rejected'
);

insert into p2_d01_results (key, result)
select 'role_change', public.change_membership_role(
  'e1000000-0000-0000-0000-000000000001',
  (select membership.id from public.memberships as membership
   where membership.user_id = 'ea000000-0000-0000-0000-000000000003'),
  'e3000000-0000-0000-0000-000000000001',
  2,
  'ee000000-0000-0000-0000-000000000025', 'ec000000-0000-0000-0000-000000000025',
  'promote to manager'
);

select is(
  (select result #>> '{entity,role_id}' from p2_d01_results where key = 'role_change'),
  'e3000000-0000-0000-0000-000000000001',
  'the membership role can be reassigned'
);
select is(
  (select (result #>> '{entity,version}')::bigint from p2_d01_results where key = 'role_change'),
  3::bigint,
  'role change increments the version'
);

reset role;
select is(
  (select count(*)::integer from public.audit_events where action = 'membership.role_change'),
  1,
  'role change writes one audit event'
);

-- === With a second manager, the first may step down ===================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

select is(
  public.change_membership_role(
    'e1000000-0000-0000-0000-000000000001',
    'e6000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000002',
    1,
    'ee000000-0000-0000-0000-000000000026', 'ec000000-0000-0000-0000-000000000026',
    'step down'
  ) ->> 'ok',
  'true',
  'a manager can step down once another active manager exists'
);

-- === Direct DML and anonymous access stay closed ======================

select throws_ok(
  $$update public.memberships
    set status = 'revoked'
    where id = 'e6000000-0000-0000-0000-000000000003'$$,
  '42501', null, 'authenticated direct membership UPDATE is denied'
);
select throws_ok(
  $$insert into public.membership_invitations (
      workspace_id, email, role_id, created_by, updated_by
    ) values (
      'e1000000-0000-0000-0000-000000000001', 'direct@example.test',
      'e3000000-0000-0000-0000-000000000002',
      'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'
    )$$,
  '42501', null, 'authenticated direct invitation INSERT is denied'
);

reset role;
set local role anon;

select throws_ok(
  $$select public.invite_workspace_member(
      'e1000000-0000-0000-0000-000000000001', 'anon@example.test',
      'e3000000-0000-0000-0000-000000000002',
      'ee000000-0000-0000-0000-000000000027', 'ec000000-0000-0000-0000-000000000027'
    )$$,
  '42501', null, 'anon cannot execute membership RPCs'
);
select throws_ok(
  $$select * from public.membership_invitations$$,
  '42501', null, 'anon cannot select invitations'
);

reset role;

select is(
  (select count(*)::integer from public.mutation_receipts where status = 'pending'),
  0,
  'no failed membership command leaves a pending receipt behind'
);

select * from finish();

rollback;
