begin;

create extension if not exists pgtap with schema extensions;

select plan(62);

select functions_are(
  'private',
  array[
    'broadcast_membership_entitlement_change',
    'broadcast_role_permission_entitlement_change',
    'apply_valuation_factors',
    'assert_unit_occupancy',
    'capex_project_snapshot',
    'capex_project_status_transition_allowed',
    'claim_document_mutation',
    'claim_leasing_mutation',
    'claim_maintenance_mutation',
    'claim_membership_mutation',
    'claim_party_mutation',
    'claim_valuation_mutation',
    'contractor_details_snapshot',
    'document_command_gate',
    'document_entity_ref_state',
    'document_requirement_state',
    'document_link_snapshot',
    'document_snapshot',
    'document_storage_workspace',
    'document_type_snapshot',
    'document_version_snapshot',
    'domain_event_topic_permission',
    'domain_event_topic_workspace',
    'emit_task_notification',
    'finish_document_mutation',
    'finish_leasing_mutation',
    'finish_maintenance_mutation',
    'finish_membership_mutation',
    'finish_party_mutation',
    'finish_valuation_mutation',
    'has_entity_scope',
    'has_scoped_entity_permission',
    'has_workspace_permission',
    'import_job_snapshot',
    'import_job_status_can_transition',
    'claim_platform_mutation',
    'finish_platform_mutation',
    'is_aal2',
    'is_active_workspace_member',
    'is_current_active_membership',
    'lease_snapshot',
    'lease_status_is_effective',
    'lease_status_transition_allowed',
    'leases_assert_occupancy',
    'leasing_case_snapshot',
    'leasing_case_stage_rank',
    'leasing_case_status_is_terminal',
    'leasing_case_transition_allowed',
    'leasing_command_gate',
    'leasing_property_in_workspace',
    'maintenance_command_gate',
    'maintenance_contractor_party_valid',
    'maintenance_ticket_snapshot',
    'maintenance_ticket_status_transition_allowed',
    'membership_command_gate',
    'membership_invitation_snapshot',
    'membership_snapshot',
    'notification_snapshot',
    'operations_signal_state_snapshot',
    'party_command_gate',
    'party_role_snapshot',
    'party_snapshot',
    'platform_command_gate',
    'prepare_audit_event',
    'properties_apply_delete_marker',
    'publish_document_link_event',
    'publish_domain_event',
    'publish_required_document_event',
    'reject_audit_event_change',
    'reject_domain_event_change',
    'reject_protected_column_update',
    'reject_rent_roll_change',
    'rent_roll_currencies',
    'rent_roll_snapshot_document',
    'rent_roll_snapshot_header',
    'rent_roll_unit_currencies',
    'rent_roll_unit_rows',
    'required_document_snapshot',
    'search_index_discard',
    'search_index_project',
    'search_index_snapshot',
    'search_index_sync_party',
    'search_index_sync_property',
    'search_index_sync_source',
    'send_entitlement_revalidation',
    'sync_unit_occupancy',
    'task_property_rollup',
    'task_snapshot',
    'task_status_can_transition',
    'tasks_apply_property_rollup',
    'tasks_emit_notifications',
    'unit_effective_lease_count',
    'unit_snapshot',
    'units_assert_occupancy',
    'update_property_core',
    'validate_valuation_factor_payload',
    'valuation_case_detail',
    'valuation_case_snapshot',
    'valuation_command_gate',
    'valuation_factor_set',
    'valuation_factor_snapshot',
    'valuation_status_can_transition',
    'would_remove_last_security_manager'
  ],
  'private function inventory is complete'
);

select policies_are('public', 'workspaces', array['workspaces_select_workspace_read']);
select policies_are('public', 'user_profiles', array['user_profiles_select_own']);
select policies_are('public', 'memberships', array['memberships_select_authorized']);
select policies_are('public', 'roles', array['roles_select_workspace_read']);
select policies_are('public', 'permissions', array['permissions_select_authenticated']);
select policies_are('public', 'role_permissions', array['role_permissions_select_workspace_read']);
select policies_are('public', 'entity_scopes', array['entity_scopes_select_authorized']);
select policies_are('public', 'audit_events', array['audit_events_select_audit_read']);
select policies_are('public', 'mutation_receipts', array[]::text[]);

select ok(
  bool_and(policy.cmd = 'SELECT' and policy.roles = array['authenticated']::name[]),
  'all P1-003 policies are authenticated SELECT policies'
)
from pg_policies as policy
where policy.schemaname = 'public'
  and policy.tablename in (
    'workspaces', 'user_profiles', 'memberships', 'roles', 'permissions',
    'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
  );

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
      and grantee = 'authenticated'
      and privilege_type = 'SELECT'
  ),
  8,
  'authenticated has SELECT on exactly eight baseline tables'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
      and grantee in ('anon', 'authenticated')
      and privilege_type <> 'SELECT'
  ),
  0,
  'client roles have no DML grants'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'workspaces', 'user_profiles', 'roles', 'permissions', 'memberships',
        'role_permissions', 'entity_scopes', 'audit_events', 'mutation_receipts'
      )
      and grantee = 'anon'
  ),
  0,
  'anon has no baseline table grants'
);

select ok(
  bool_and(
    function.prosecdef
    and function.provolatile = 's'
    and owner.rolname = 'postgres'
    and owner.rolbypassrls
    and function.proconfig @> array['search_path=""']::text[]
  ),
  'P1-003 helpers are stable security definers owned by postgres with fixed search path'
)
from pg_proc as function
join pg_namespace as namespace on namespace.oid = function.pronamespace
join pg_roles as owner on owner.oid = function.proowner
where namespace.nspname = 'private'
  and function.proname in (
    'is_active_workspace_member',
    'has_workspace_permission',
    'is_current_active_membership'
  );

select ok(
  bool_and(
    pg_get_functiondef(function.oid) like '%public.memberships%'
    and pg_get_functiondef(function.oid) not like '% FROM memberships%'
  ),
  'P1-003 helpers use qualified membership references'
)
from pg_proc as function
join pg_namespace as namespace on namespace.oid = function.pronamespace
where namespace.nspname = 'private'
  and function.proname in (
    'is_active_workspace_member',
    'has_workspace_permission',
    'is_current_active_membership'
  );

select is(
  (
    select count(*)::integer
    from information_schema.routine_privileges
    where specific_schema = 'private'
      and routine_name in (
        'is_active_workspace_member',
        'has_workspace_permission',
        'is_current_active_membership'
      )
      and grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
  ),
  3,
  'authenticated can execute exactly the three P1-003 helpers'
);

select is(
  (
    select count(*)::integer
    from information_schema.routine_privileges
    where specific_schema = 'private'
      and routine_name in (
        'is_active_workspace_member',
        'has_workspace_permission',
        'is_current_active_membership'
      )
      and grantee in ('PUBLIC', 'anon')
  ),
  0,
  'PUBLIC and anon cannot execute P1-003 helpers'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.test', '', now(), '{}', '{}', now(), now()),
  ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.test', '', now(), '{}', '{}', now(), now()),
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended@example.test', '', now(), '{}', '{}', now(), now()),
  ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'missing@example.test', '', now(), '{}', '{}', now(), now()),
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('10000000-0000-0000-0000-000000000001', 'workspace-a', 'Workspace A'),
  ('20000000-0000-0000-0000-000000000001', 'workspace-b', 'Workspace B');

insert into public.user_profiles (id, user_id, display_name) values
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'User A'),
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'User B'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Suspended'),
  ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Missing Permission'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Security Manager');

insert into public.roles (id, workspace_id, key, name) values
  ('11000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('11000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'empty', 'Empty A'),
  ('11000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'security-manager', 'Security Manager A'),
  ('21000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'reader', 'Reader B');

insert into public.permissions (id, key, name) values
  ('30000000-0000-0000-0000-000000000001', 'workspace.read', 'Workspace Read'),
  ('30000000-0000-0000-0000-000000000002', 'security.manage', 'Security Manage'),
  ('30000000-0000-0000-0000-000000000003', 'audit.read', 'Audit Read');

insert into public.role_permissions (id, workspace_id, role_id, permission_id) values
  ('41000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'),
  ('41000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003'),
  ('41000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000002'),
  ('42000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('51000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'active'),
  ('52000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'active'),
  ('51000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'suspended'),
  ('51000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000002', 'active'),
  ('51000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000003', 'active');

insert into public.entity_scopes (id, workspace_id, membership_id, entity_type, entity_id) values
  ('61000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 'property', '71000000-0000-0000-0000-000000000001'),
  ('61000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', 'property', '71000000-0000-0000-0000-000000000002'),
  ('61000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003', 'property', '71000000-0000-0000-0000-000000000003'),
  ('62000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'property', '72000000-0000-0000-0000-000000000001');

insert into public.audit_events (
  id, workspace_id, actor_type, actor_identifier, action, entity_type, source, correlation_id
) values
  ('81000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'system', 'pgtap', 'workspace.read', 'workspace', 'database', '91000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'system', 'pgtap', 'workspace.read', 'workspace', 'database', '92000000-0000-0000-0000-000000000001');

insert into public.mutation_receipts (id, workspace_id, mutation_id, request_hash) values
  ('a2000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', decode(repeat('ab', 32), 'hex')),
  ('b2000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', decode(repeat('cd', 32), 'hex'));

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

select ok(private.is_active_workspace_member('10000000-0000-0000-0000-000000000001'), 'user A is active in workspace A');
select isnt(private.is_active_workspace_member('20000000-0000-0000-0000-000000000001'), true, 'user A is not active in workspace B');
select ok(private.has_workspace_permission('10000000-0000-0000-0000-000000000001', 'workspace.read'), 'user A has workspace.read in A');
select isnt(private.has_workspace_permission('10000000-0000-0000-0000-000000000001', 'security.manage'), true, 'missing permission denies');
select ok(private.is_current_active_membership('10000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001'), 'current active membership matches');
select isnt(private.is_current_active_membership('20000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001'), true, 'foreign membership id does not match');

select is((select count(*)::integer from public.workspaces), 1, 'user A sees one workspace');
select is((select id from public.workspaces), '10000000-0000-0000-0000-000000000001'::uuid, 'user A sees only workspace A');
select is((select count(*)::integer from public.user_profiles), 1, 'user A sees only own profile');
select is((select count(*)::integer from public.memberships), 1, 'workspace reader sees only own active membership');
select is((select count(*)::integer from public.roles), 3, 'user A sees roles only in workspace A');
select is((select count(*)::integer from public.role_permissions), 3, 'user A sees role permissions only in workspace A');
select is((select count(*)::integer from public.permissions), 3, 'authenticated user sees global permission catalog');
select is((select count(*)::integer from public.entity_scopes), 1, 'user A sees only own active scope');
select is((select count(*)::integer from public.audit_events), 1, 'user A sees audit for workspace A only');
select is((select count(*)::integer from public.workspaces where id = '20000000-0000-0000-0000-000000000001'), 0, 'known foreign workspace id is invisible');
select is((select count(*)::integer from public.memberships where id = '52000000-0000-0000-0000-000000000001'), 0, 'known foreign membership id is invisible');
select is((select count(*)::integer from public.entity_scopes where id = '62000000-0000-0000-0000-000000000001'), 0, 'known foreign scope id is invisible');

select throws_ok(
  $$insert into public.workspaces (key, name) values ('denied', 'Denied')$$,
  '42501', null, 'authenticated INSERT is denied'
);
select throws_ok(
  $$update public.workspaces set name = 'Denied' where id = '10000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'authenticated UPDATE is denied'
);
select throws_ok(
  $$delete from public.workspaces where id = '10000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'authenticated DELETE is denied'
);
select throws_ok(
  $$insert into public.audit_events (
      workspace_id, actor_type, actor_identifier, action, entity_type, source, correlation_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'system', 'client',
      'audit.write', 'workspace', 'client', '93000000-0000-0000-0000-000000000001'
    )$$,
  '42501', null, 'client audit INSERT is denied'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

select is((select id from public.workspaces), '20000000-0000-0000-0000-000000000001'::uuid, 'user B sees only workspace B');
select is((select count(*)::integer from public.roles), 1, 'user B cannot see workspace A roles');
select is((select count(*)::integer from public.audit_events), 0, 'workspace.read without audit.read denies audit');
select is((select count(*)::integer from public.workspaces where id = '10000000-0000-0000-0000-000000000001'), 0, 'user B cannot probe workspace A id');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);

select isnt(private.is_active_workspace_member('10000000-0000-0000-0000-000000000001'), true, 'suspended membership is inactive');
select is((select count(*)::integer from public.workspaces), 0, 'suspended user sees no workspace');
-- P2-D01: members always see their own membership row (any status) so a
-- suspended or invited user can see where they stand; nothing beyond it.
select ok(
  (select count(*) = 1
     and bool_and(user_id = 'c0000000-0000-0000-0000-000000000001'::uuid)
   from public.memberships),
  'suspended user sees exactly their own membership row'
);
select is((select count(*)::integer from public.roles), 0, 'suspended user sees no roles');
select is((select count(*)::integer from public.entity_scopes), 0, 'suspended user sees no scopes');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);

select ok(private.is_active_workspace_member('10000000-0000-0000-0000-000000000001'), 'permissionless user remains an active member');
select is((select count(*)::integer from public.workspaces), 0, 'active membership without workspace.read is denied');
-- P2-D01: own-row visibility does not depend on a permission; foreign
-- memberships stay hidden without security.manage.
select ok(
  (select count(*) = 1
     and bool_and(user_id = 'd0000000-0000-0000-0000-000000000001'::uuid)
   from public.memberships),
  'active member without permissions sees exactly their own membership row'
);
select is((select count(*)::integer from public.entity_scopes), 0, 'own scope without workspace.read is hidden');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);

select is((select count(*)::integer from public.workspaces), 0, 'security.manage alone does not grant workspace read');
select is((select count(*)::integer from public.memberships), 4, 'security manager sees workspace A memberships');
select is((select count(*)::integer from public.entity_scopes), 3, 'security manager sees workspace A scopes');
select is((select count(*)::integer from public.memberships where workspace_id = '20000000-0000-0000-0000-000000000001'), 0, 'security manager cannot see workspace B memberships');

reset role;
set local role anon;

select throws_ok(
  $$select * from public.workspaces$$,
  '42501', null, 'anon SELECT is denied'
);
select throws_ok(
  $$insert into public.workspaces (key, name) values ('anon-denied', 'Denied')$$,
  '42501', null, 'anon INSERT is denied'
);
select throws_ok(
  $$update public.workspaces set name = 'Denied'$$,
  '42501', null, 'anon UPDATE is denied'
);
select throws_ok(
  $$delete from public.workspaces$$,
  '42501', null, 'anon DELETE is denied'
);
select throws_ok(
  $$select private.is_active_workspace_member('10000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'anon helper execution is denied'
);

reset role;

select * from finish();

rollback;
