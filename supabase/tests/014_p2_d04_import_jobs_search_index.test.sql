begin;

create extension if not exists pgtap with schema extensions;

select plan(71);

-- ---------------------------------------------------------------------------
-- Schema, RLS, grants
-- ---------------------------------------------------------------------------

select has_table('public', 'import_jobs', 'import_jobs exists');
select has_table('public', 'search_index', 'search_index exists');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.import_jobs'::regclass),
  'import_jobs has RLS enabled and forced'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.search_index'::regclass),
  'search_index has RLS enabled and forced'
);
select policies_are(
  'public', 'import_jobs', array['import_jobs_select_import_read'],
  'import_jobs has one scoped select policy'
);
select policies_are(
  'public', 'search_index', array['search_index_select_search_read'],
  'search_index has one scoped select policy'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public' and tablename in ('import_jobs', 'search_index')
     and cmd in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'no write policy on import_jobs or search_index: mutation is RPC-only'
);
select is(
  (select count(*)::integer from information_schema.table_privileges
   where table_schema = 'public' and table_name in ('import_jobs', 'search_index')
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'no direct write grant on import_jobs or search_index'
);
select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name in (
       'import_job_snapshot', 'search_index_snapshot', 'import_job_status_can_transition'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated')),
  0,
  'no new private helper is executable by PUBLIC, anon or authenticated'
);
select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_import_job', 'update_import_job', 'transition_import_job_status',
       'reindex_search_entry', 'remove_search_entry'
     )
     and grantee = 'authenticated' and privilege_type = 'EXECUTE'),
  5,
  'authenticated can execute exactly the five increment-3 RPCs'
);

-- ---------------------------------------------------------------------------
-- STM-013 matrix helper (checked here as superuser; authenticated has no grant).
-- ---------------------------------------------------------------------------

select is(private.import_job_status_can_transition('draft', 'validating'), true, 'draft -> validating allowed');
select is(private.import_job_status_can_transition('draft', 'ready'), false, 'draft -> ready skipped is not allowed');
select is(private.import_job_status_can_transition('validating', 'ready'), true, 'validating -> ready allowed');
select is(private.import_job_status_can_transition('validating', 'failed'), true, 'validating -> failed allowed');
select is(private.import_job_status_can_transition('running', 'completed'), true, 'running -> completed allowed');
select is(private.import_job_status_can_transition('completed', 'running'), false, 'completed is terminal');
select is(private.import_job_status_can_transition('failed', 'validating'), false, 'failed is terminal — retry is a new job');

-- ---------------------------------------------------------------------------
-- Fixture: workspace A with a manager (import + search manage/read) and a plain
-- member (workspace.read only); workspace B for isolation.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04c-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04c-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('a1000000-0000-0000-0000-000000000001', 'd04c-a', 'D04C A'),
  ('a1000000-0000-0000-0000-000000000002', 'd04c-b', 'D04C B');

insert into public.roles (id, workspace_id, key, name) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'member', 'Member');

insert into public.permissions (id, key, name) values
  ('a3000000-0000-0000-0000-000000000001', 'import.read', 'Import Read'),
  ('a3000000-0000-0000-0000-000000000002', 'import.manage', 'Import Manage'),
  ('a3000000-0000-0000-0000-000000000003', 'search.read', 'Search Read'),
  ('a3000000-0000-0000-0000-000000000004', 'search.reindex', 'Search Reindex'),
  ('a3000000-0000-0000-0000-000000000005', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', id
from public.permissions
where key in ('import.read', 'import.manage', 'search.read', 'search.reindex', 'workspace.read');
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', id
from public.permissions where key = 'workspace.read';

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('a4000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'active'),
  ('a4000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'active');

-- A workspace-B import job the workspace-A manager must never see (isolation).
insert into public.import_jobs (
  id, workspace_id, source_kind, target_scope, created_by, updated_by
) values (
  'a5000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002',
  'csv', 'properties', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001'
);

-- ---------------------------------------------------------------------------
-- AGG-020 as a structural invariant (checked as superuser, direct DML).
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.import_jobs (workspace_id, source_kind, target_scope, status, created_by, updated_by)
     values ('a1000000-0000-0000-0000-000000000001', 'csv', 'x', 'ready',
             'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a job cannot reach ready without dry_run and reconciliation'
);
select throws_ok(
  $$ insert into public.import_jobs (workspace_id, source_kind, target_scope, status, error_report, created_by, updated_by)
     values ('a1000000-0000-0000-0000-000000000001', 'csv', 'x', 'failed', null,
             'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a failed job cannot exist without an error report'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- ---------------------------------------------------------------------------
-- import_jobs lifecycle (STM-013)
-- ---------------------------------------------------------------------------

select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000001', 'csv', 'properties',
    'd6000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
    p_mapping => '{"col":"a"}'::jsonb
  ) ->> 'ok',
  'true',
  'a manager creates an import job'
);
select is(
  (select status::text from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  'draft',
  'a new import job starts in draft (STM-013)'
);

-- mutation_id replay: identical call returns the same job, no duplicate.
select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000001', 'csv', 'properties',
    'd6000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000001',
    p_mapping => '{"col":"a"}'::jsonb
  ) ->> 'ok',
  'true',
  'an identical create replays as success'
);
select is(
  (select count(*)::integer from public.import_jobs
   where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  1,
  'the replay created no duplicate job'
);

select is(
  public.update_import_job(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'd6000000-0000-0000-0000-000000000002', 'd7000000-0000-0000-0000-000000000002',
    '{"mapping": {"col": "b"}}'::jsonb
  ) ->> 'ok',
  'true',
  'a draft mapping can be edited'
);
select is(
  (select version::text from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  '2',
  'the edit bumped the version'
);
select is(
  public.update_import_job(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version + 50 from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'd6000000-0000-0000-0000-000000000003', 'd7000000-0000-0000-0000-000000000003',
    '{"mapping": {"col": "c"}}'::jsonb
  ) -> 'error' ->> 'code',
  'version_conflict',
  'a stale version is rejected'
);

select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'validating', 'd6000000-0000-0000-0000-000000000004', 'd7000000-0000-0000-0000-000000000004'
  ) ->> 'ok',
  'true',
  'draft -> validating'
);
select is(
  (select status::text from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  'validating',
  'the job is now validating'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'ready', 'd6000000-0000-0000-0000-000000000005', 'd7000000-0000-0000-0000-000000000005'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'validating -> ready without evidence is rejected (AGG-020)'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'ready', 'd6000000-0000-0000-0000-000000000006', 'd7000000-0000-0000-0000-000000000006',
    p_dry_run => '{"manifest":"m"}'::jsonb, p_reconciliation => '{"rows":3}'::jsonb
  ) ->> 'ok',
  'true',
  'validating -> ready with dry-run and reconciliation'
);
select is(
  (select status::text from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  'ready',
  'the job is now ready'
);
select is(
  (select reconciliation ->> 'rows' from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  '3',
  'the reconciliation is attached to the job'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'running', 'd6000000-0000-0000-0000-000000000007', 'd7000000-0000-0000-0000-000000000007'
  ) ->> 'ok',
  'true',
  'ready -> running'
);
select is(
  (select started_at is not null from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  true,
  'the run recorded a start stamp'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'completed', 'd6000000-0000-0000-0000-000000000008', 'd7000000-0000-0000-0000-000000000008'
  ) ->> 'ok',
  'true',
  'running -> completed'
);
select is(
  (select status::text from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  'completed',
  'the job is now completed'
);
select is(
  (select finished_at is not null from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  true,
  'the terminal job recorded a finish stamp'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'running', 'd6000000-0000-0000-0000-000000000009', 'd7000000-0000-0000-0000-000000000009'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a completed job is terminal — no transition out'
);

-- A second job for the no-op / coherence / draft-only checks.
select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000001', 'csv', 'units',
    'd6000000-0000-0000-0000-000000000010', 'd7000000-0000-0000-0000-000000000010'
  ) ->> 'ok',
  'true',
  'a second draft import job is created'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'units' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'units' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'draft', 'd6000000-0000-0000-0000-000000000011', 'd7000000-0000-0000-0000-000000000011'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a no-op transition to the same status is rejected'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'units' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'units' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'validating', 'd6000000-0000-0000-0000-000000000012', 'd7000000-0000-0000-0000-000000000012',
    p_dry_run => '{"manifest":"m"}'::jsonb
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a pre-commit artifact may not ride the wrong transition'
);
select is(
  public.update_import_job(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'properties' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'd6000000-0000-0000-0000-000000000013', 'd7000000-0000-0000-0000-000000000013',
    '{"mapping": {"col": "z"}}'::jsonb
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a non-draft job cannot be edited'
);

-- A third job to reach the failure state.
select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000001', 'csv', 'leases',
    'd6000000-0000-0000-0000-000000000014', 'd7000000-0000-0000-0000-000000000014'
  ) ->> 'ok',
  'true',
  'a third draft import job is created'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'validating', 'd6000000-0000-0000-0000-000000000015', 'd7000000-0000-0000-0000-000000000015'
  ) ->> 'ok',
  'true',
  'the third job enters validating'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'failed', 'd6000000-0000-0000-0000-000000000016', 'd7000000-0000-0000-0000-000000000016',
    p_error_report => '{"issues":["bad row"]}'::jsonb
  ) ->> 'ok',
  'true',
  'validating -> failed with an error report'
);
select is(
  (select status::text from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  'failed',
  'the third job is now failed'
);
select is(
  (select error_report ->> 'issues' is not null from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  true,
  'the failure carries its error report'
);
select is(
  public.transition_import_job_status(
    'a1000000-0000-0000-0000-000000000001',
    (select id from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    (select version from public.import_jobs where target_scope = 'leases' and workspace_id = 'a1000000-0000-0000-0000-000000000001'),
    'validating', 'd6000000-0000-0000-0000-000000000017', 'd7000000-0000-0000-0000-000000000017'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'a failed job is terminal — retry is a new job'
);

-- ---------------------------------------------------------------------------
-- Workspace isolation and audit coverage (still the A manager)
-- ---------------------------------------------------------------------------

select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000002', 'csv', 'foreign',
    'd6000000-0000-0000-0000-000000000018', 'd7000000-0000-0000-0000-000000000018'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a non-member cannot create an import job in another workspace'
);
select is(
  (select count(*)::integer from public.import_jobs where workspace_id = 'a1000000-0000-0000-0000-000000000002'),
  0,
  'the foreign-workspace import job is invisible under RLS'
);

-- ---------------------------------------------------------------------------
-- search_index — the derived, non-authoritative projection
-- ---------------------------------------------------------------------------

select is(
  public.reindex_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'property',
    'a9000000-0000-0000-0000-000000000001', 'Musterstrasse 1', 'Berlin'
  ) ->> 'ok',
  'true',
  'a manager reindexes a search entry'
);
select is(
  (select title from public.search_index
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'
     and entity_type = 'property' and entity_id = 'a9000000-0000-0000-0000-000000000001'),
  'Musterstrasse 1',
  'the entry is indexed'
);
select is(
  public.reindex_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'property',
    'a9000000-0000-0000-0000-000000000001', 'Musterstrasse 1a', 'Berlin'
  ) ->> 'ok',
  'true',
  'reindexing the same entity is an upsert'
);
select is(
  (select count(*)::integer from public.search_index
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'
     and entity_type = 'property' and entity_id = 'a9000000-0000-0000-0000-000000000001'),
  1,
  'the upsert kept a single row (last writer wins)'
);
select is(
  (select title from public.search_index
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'
     and entity_type = 'property' and entity_id = 'a9000000-0000-0000-0000-000000000001'),
  'Musterstrasse 1a',
  'the reindex overwrote the title'
);
select is(
  public.reindex_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'not_an_entity',
    'a9000000-0000-0000-0000-000000000002', 'x'
  ) -> 'error' ->> 'code',
  'validation_failed',
  'an unknown entity type is rejected'
);
select is(
  public.reindex_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'unit',
    'a9000000-0000-0000-0000-000000000003', 'Einheit 3'
  ) ->> 'ok',
  'true',
  'a second entry is indexed for the remove tests'
);
select is(
  public.remove_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'unit', 'a9000000-0000-0000-0000-000000000003'
  ) -> 'entity' ->> 'removed',
  'true',
  'removing a present entry reports removed'
);
select is(
  public.remove_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'unit', 'a9000000-0000-0000-0000-000000000003'
  ) -> 'entity' ->> 'removed',
  'false',
  'removing an absent entry is an idempotent success'
);

-- ---------------------------------------------------------------------------
-- Append-only audit and published domain events (asserted as superuser: the
-- manager fixture holds no audit.read, so audit_events RLS hides the rows).
-- ---------------------------------------------------------------------------

reset role;
reset request.jwt.claims;
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'a1000000-0000-0000-0000-000000000001' and action = 'import_job.create'),
  3,
  'each successful create wrote exactly one audit row'
);
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'a1000000-0000-0000-0000-000000000001' and action ~ '^search'),
  0,
  'a derived reindex writes no audit record'
);
select ok(
  (select count(*) from public.domain_events where event_type = 'import_job.created') >= 1,
  'creating an import job publishes import_job.created'
);
select ok(
  (select count(*) from public.domain_events where event_type = 'import_job.status_changed') >= 1,
  'a transition publishes import_job.status_changed'
);

-- ---------------------------------------------------------------------------
-- Permission scoping — the plain member (workspace.read only)
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"d1000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

select is(
  public.create_import_job(
    'a1000000-0000-0000-0000-000000000001', 'csv', 'members-cannot',
    'd6000000-0000-0000-0000-000000000020', 'd7000000-0000-0000-0000-000000000020'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a member without import.manage cannot create an import job'
);
select is(
  (select count(*)::integer from public.import_jobs where workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  0,
  'a member without import.read sees no import jobs'
);
select is(
  public.reindex_search_entry(
    'a1000000-0000-0000-0000-000000000001', 'property',
    'a9000000-0000-0000-0000-000000000009', 'nope'
  ) -> 'error' ->> 'code',
  'forbidden',
  'a member without search.reindex cannot reindex'
);
select is(
  (select count(*)::integer from public.search_index where workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  0,
  'a member without search.read sees no search entries'
);

-- ---------------------------------------------------------------------------
-- Direct DML and anon denial
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.import_jobs (workspace_id, source_kind, target_scope, created_by, updated_by)
     values ('a1000000-0000-0000-0000-000000000001', 'csv', 'x',
             'd1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002') $$,
  '42501',
  null,
  'authenticated cannot write import_jobs directly'
);
select throws_ok(
  $$ insert into public.search_index (workspace_id, entity_type, entity_id, title, created_by, updated_by)
     values ('a1000000-0000-0000-0000-000000000001', 'property', 'a9000000-0000-0000-0000-000000000009', 't',
             'd1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002') $$,
  '42501',
  null,
  'authenticated cannot write search_index directly'
);

set local role anon;

select throws_ok(
  $$ select * from public.import_jobs $$,
  '42501',
  null,
  'anon cannot read import_jobs'
);
select throws_ok(
  $$ select * from public.search_index $$,
  '42501',
  null,
  'anon cannot read search_index'
);

reset role;

select * from finish();

rollback;
