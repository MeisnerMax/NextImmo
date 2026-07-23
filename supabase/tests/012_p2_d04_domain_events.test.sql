begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

-- ---------------------------------------------------------------------------
-- Schema, RLS and grants
-- ---------------------------------------------------------------------------

select has_table('public', 'domain_events', 'domain_events exists');
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.domain_events'::regclass),
  'domain_events has RLS enabled and forced'
);
select policies_are(
  'public', 'domain_events', array['domain_events_select_scoped'],
  'domain_events exposes exactly one scoped select policy'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public' and tablename = 'domain_events'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'domain_events has no insert/update/delete policy: append-only is structural'
);
select is(
  (select count(*)::integer from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'domain_events'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'no direct write grant on domain_events'
);

select has_column('public', 'domain_events', 'event_type', 'CTR-005 eventType');
select has_column('public', 'domain_events', 'schema_version', 'CTR-005 schemaVersion');
select has_column('public', 'domain_events', 'aggregate_id', 'CTR-005 aggregateId');
select has_column('public', 'domain_events', 'aggregate_version', 'CTR-005 aggregateVersion');
select has_column('public', 'domain_events', 'occurred_at', 'CTR-005 occurredAt');
select has_column('public', 'domain_events', 'actor_id', 'CTR-005 actorId');
select has_column('public', 'domain_events', 'correlation_id', 'CTR-005 correlationId');
select has_column('public', 'domain_events', 'payload', 'CTR-005 payload');
select has_column('public', 'domain_events', 'required_permission', 'per-event read gate');

select ok(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'publish_domain_event'),
  'publish_domain_event is a security definer'
);
select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name in (
       'publish_domain_event', 'reject_domain_event_change',
       'publish_document_link_event', 'publish_required_document_event'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated')),
  0,
  'no P2-D04 writing helper is executable by PUBLIC, anon or authenticated'
);

select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'private'
     and routine_name in (
       'domain_event_topic_workspace', 'domain_event_topic_permission'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'the topic parsers stay closed to PUBLIC and anon'
);

-- The regression this pins: the realtime.messages policy is evaluated as
-- `authenticated`, and a policy calling a function that role cannot execute
-- raises — which breaks realtime authorization for every subscription, not
-- just this one. Evaluating the helpers as the role is the only assertion that
-- catches it; checking them as superuser passes either way.
set local role authenticated;
select lives_ok(
  $$select private.domain_event_topic_workspace('workspace:10000000-0000-0000-0000-000000000001:document.read')$$,
  'authenticated can evaluate the topic workspace parser its policy depends on'
);
select lives_ok(
  $$select private.domain_event_topic_permission('workspace:10000000-0000-0000-0000-000000000001:document.read')$$,
  'authenticated can evaluate the topic permission parser its policy depends on'
);
reset role;

-- resolve_document_content_ref may no longer be stable: it writes now.
select ok(
  (select provolatile = 'v' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolve_document_content_ref'),
  'resolve_document_content_ref is volatile so it may record access'
);

-- ---------------------------------------------------------------------------
-- Topic parsing fails closed
-- ---------------------------------------------------------------------------

select is(
  private.domain_event_topic_workspace('workspace:10000000-0000-0000-0000-000000000001:document.read'),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'a well formed topic yields its workspace'
);
select is(
  private.domain_event_topic_workspace('workspace:nicht-uuid:document.read'),
  null,
  'a malformed workspace segment fails closed'
);
select is(
  private.domain_event_topic_workspace('entitlements:10000000-0000-0000-0000-000000000001'),
  null,
  'a foreign topic namespace fails closed'
);
select is(
  private.domain_event_topic_workspace(null),
  null,
  'a null topic fails closed'
);
select is(
  private.domain_event_topic_permission('workspace:10000000-0000-0000-0000-000000000001:document.read'),
  'document.read',
  'a well formed topic yields its permission'
);
select is(
  private.domain_event_topic_permission('workspace:10000000-0000-0000-0000-000000000001:DROP TABLE'),
  null,
  'a permission segment that is not a normalised key fails closed'
);
select is(
  private.domain_event_topic_permission('workspace:10000000-0000-0000-0000-000000000001'),
  null,
  'a topic without a permission segment fails closed'
);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('aa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd04-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('b1000000-0000-0000-0000-000000000001', 'd04-a', 'D04 A'),
  ('b1000000-0000-0000-0000-000000000002', 'd04-b', 'D04 B');

insert into public.roles (id, workspace_id, key, name) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'manager', 'Manager'),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer');

insert into public.permissions (id, key, name) values
  ('b3000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('b3000000-0000-0000-0000-000000000002', 'document.manage', 'Document Manage'),
  ('b3000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000002'),
  ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000003'),
  -- The viewer holds workspace.read only: it must never see a document event.
  ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('b4000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'active'),
  ('b4000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'b5000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'D04 Objekt', 'Teststrasse 1', '10115', 'Berlin', 'de', 'residential',
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

insert into public.document_types (
  id, workspace_id, key, name, entity_type, created_by, updated_by
) values (
  'b6000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'mietvertrag', 'Mietvertrag', 'property',
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

insert into public.documents (
  id, workspace_id, document_type_id, title, status, current_version_no,
  created_by, updated_by
) values (
  'b7000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000001', 'Mietvertrag', 'available', 1,
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

insert into public.document_versions (
  id, workspace_id, document_id, version_no, storage_bucket, storage_object_path,
  content_hash, byte_size, mime_type, content_confirmed_at, created_by, updated_by
) values (
  'b8000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001', 1, 'documents',
  'b1000000-0000-0000-0000-000000000001/b7000000-0000-0000-0000-000000000001/1/v.pdf',
  extensions.digest('inhalt', 'sha256'), 6, 'application/pdf', now(),
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

-- ---------------------------------------------------------------------------
-- Cross-table invalidation: the gap P2-D03 named
-- ---------------------------------------------------------------------------

insert into public.document_links (
  id, workspace_id, document_id, entity_type, entity_id, created_by
) values (
  'b9000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'b7000000-0000-0000-0000-000000000001', 'property',
  'b5000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.linked'
     and aggregate_id = 'b7000000-0000-0000-0000-000000000001'),
  1,
  'linking a document publishes an envelope without touching the documents row'
);
select is(
  (select required_permission from public.domain_events where event_type = 'document.linked'),
  'document.read',
  'the link envelope inherits the source aggregate read gate'
);
select is(
  (select payload->>'entity_id' from public.domain_events where event_type = 'document.linked'),
  'b5000000-0000-0000-0000-000000000001',
  'the envelope points at the affected entity'
);
select is(
  (select version from public.documents where id = 'b7000000-0000-0000-0000-000000000001'),
  1::bigint,
  'publishing never moves the parent optimistic-concurrency token'
);

delete from public.document_links
where id = 'b9000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.unlinked'),
  1,
  'unlinking publishes too: an AFTER DELETE trigger sees the whole row'
);
select is(
  (select payload->>'entity_id' from public.domain_events where event_type = 'document.unlinked'),
  'b5000000-0000-0000-0000-000000000001',
  'the delete envelope carries the workspace-scoped payload a WAL delete could not'
);

insert into public.required_documents (
  id, workspace_id, entity_type, entity_id, document_type_id, created_by, updated_by
) values (
  'ba000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'property', 'b5000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000001',
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.requirement_changed'),
  1,
  'a requirement rule change publishes an envelope'
);

update public.required_documents
set retired_at = now(), updated_at = now()
where id = 'ba000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.requirement_changed'),
  2,
  'retiring a rule publishes as well'
);
-- Deliberately counted, not ordered by occurred_at: now() is transaction
-- scoped, so every envelope raised inside one transaction shares a timestamp
-- and occurred_at cannot order them. Clients that need ordering must use
-- aggregate_version, not the clock.
select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.requirement_changed'
     and payload->>'retired' = 'true'),
  1,
  'the envelope states the retired flag so a client knows what changed'
);

-- ---------------------------------------------------------------------------
-- Append-only is enforced, not merely unpoliced
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update public.domain_events set event_type = 'tampered'$$,
  'P0001',
  'domain_events is append-only',
  'domain_events rejects updates'
);
select throws_ok(
  $$delete from public.domain_events$$,
  'P0001',
  'domain_events is append-only',
  'domain_events rejects deletes'
);

-- ---------------------------------------------------------------------------
-- Per-access recording of downloads (the second P2-D03 gap)
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  (
    select public.resolve_document_content_ref(
      'b1000000-0000-0000-0000-000000000001',
      'b7000000-0000-0000-0000-000000000001'
    ) ->> 'ok'
  ),
  'true',
  'a permitted caller still resolves content'
);

reset role;
reset request.jwt.claims;

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.content_accessed'
     and actor_id = 'aa000000-0000-0000-0000-000000000001'),
  1,
  'resolving content records who accessed it'
);
select is(
  (select payload->>'version_no' from public.domain_events
   where event_type = 'document.content_accessed'),
  '1',
  'the access envelope names the version that was resolved'
);
select is(
  (select count(*)::integer from public.audit_events
   where action like 'document.content%'),
  0,
  'access recording stays out of audit_events, which records mutations only'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (
    select public.resolve_document_content_ref(
      'b1000000-0000-0000-0000-000000000001',
      'b7000000-0000-0000-0000-000000000001'
    ) -> 'error' ->> 'code'
  ),
  'forbidden',
  'a caller without document.read is still refused'
);

reset role;
reset request.jwt.claims;

select is(
  (select count(*)::integer from public.domain_events
   where event_type = 'document.content_accessed'),
  1,
  'a refused resolve records nothing'
);

-- ---------------------------------------------------------------------------
-- Read scoping: the envelope must not leak what the reader may not see
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-000000000001","role":"authenticated"}';

select ok(
  (select count(*) from public.domain_events) > 0,
  'a holder of document.read sees the document envelopes'
);

set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::integer from public.domain_events),
  0,
  'a workspace member without document.read sees no document envelope at all'
);

select throws_ok(
  $$insert into public.domain_events (
      workspace_id, event_type, aggregate_type, required_permission, correlation_id
    ) values (
      'b1000000-0000-0000-0000-000000000001', 'fake.event', 'document',
      'workspace.read', extensions.gen_random_uuid()
    )$$,
  '42501',
  null,
  'a client cannot forge an envelope'
);

reset role;
reset request.jwt.claims;

set local role anon;
-- Stronger than "sees no rows": anon holds no select grant at all, so the
-- table is not even reachable.
select throws_ok(
  $$select count(*) from public.domain_events$$,
  '42501',
  null,
  'anon cannot read the event stream at all'
);
reset role;

-- ---------------------------------------------------------------------------
-- Envelope constraints
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select private.publish_domain_event(
      p_workspace_id => 'b1000000-0000-0000-0000-000000000001',
      p_event_type => 'NotNormalised',
      p_aggregate_type => 'document',
      p_required_permission => 'document.read',
      p_correlation_id => extensions.gen_random_uuid()
    )$$,
  '23514',
  null,
  'an event type that is not a normalised key is rejected'
);

select throws_ok(
  $$select private.publish_domain_event(
      p_workspace_id => 'b1000000-0000-0000-0000-000000000001',
      p_event_type => 'document.linked',
      p_aggregate_type => 'document',
      p_required_permission => 'Document Read',
      p_correlation_id => extensions.gen_random_uuid()
    )$$,
  '23514',
  null,
  'a required permission that is not a normalised key is rejected'
);

select throws_ok(
  $$select private.publish_domain_event(
      p_workspace_id => 'b1000000-0000-0000-0000-000000000001',
      p_event_type => 'document.linked',
      p_aggregate_type => 'document',
      p_required_permission => 'document.read',
      p_correlation_id => extensions.gen_random_uuid(),
      p_payload => jsonb_build_object('blob', repeat('x', 5000))
    )$$,
  '23514',
  null,
  'an oversized payload is rejected: the envelope is a pointer, not a copy'
);

select lives_ok(
  $$select private.publish_domain_event(
      p_workspace_id => 'b1000000-0000-0000-0000-000000000001',
      p_event_type => 'task.assigned',
      p_aggregate_type => 'task',
      p_required_permission => 'workspace.read',
      p_correlation_id => extensions.gen_random_uuid(),
      p_aggregate_id => extensions.gen_random_uuid(),
      p_aggregate_version => 3
    )$$,
  'any domain may publish through the same envelope'
);

select is(
  (select aggregate_version from public.domain_events where event_type = 'task.assigned'),
  3::bigint,
  'the envelope carries the aggregate version for ordering'
);

-- A foreign workspace never sees another workspace's stream.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aa000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (select count(*)::integer from public.domain_events
   where workspace_id = 'b1000000-0000-0000-0000-000000000002'),
  0,
  'two-workspace isolation holds on the event stream'
);
reset role;
reset request.jwt.claims;

select * from finish();

rollback;
