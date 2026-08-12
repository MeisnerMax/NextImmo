begin;

create extension if not exists pgtap with schema extensions;

select plan(127);

-- === Schema surface ===================================================

select has_table('public', 'document_types', 'document_types table exists');
select has_table('public', 'documents', 'documents table exists');
select has_table('public', 'document_versions', 'document_versions table exists');
select has_table('public', 'document_links', 'document_links table exists');
select has_table('public', 'required_documents', 'required_documents table exists');
select has_type('public', 'document_status', 'document_status enum exists');
select has_type('public', 'document_verification_status', 'verification enum exists');
select has_type('public', 'document_link_entity_type', 'link entity type enum exists');

-- STM-008 vocabulary, in the documented order.
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.document_status'::regtype),
  array['uploaded', 'processing', 'available', 'verified', 'superseded', 'archived', 'rejected'],
  'document_status carries the STM-008 labels'
);
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.document_verification_status'::regtype),
  array['pending', 'verified', 'rejected'],
  'document_verification_status has the contract labels'
);

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in (
     'public.document_types'::regclass, 'public.documents'::regclass,
     'public.document_versions'::regclass, 'public.document_links'::regclass,
     'public.required_documents'::regclass
   )),
  'all P2-D03 tables enable and force RLS'
);
select policies_are('public', 'document_types', array['document_types_select_document_read']);
select policies_are('public', 'documents', array['documents_select_document_read']);
select policies_are('public', 'document_versions', array['document_versions_select_document_read']);
select policies_are('public', 'document_links', array['document_links_select_document_read']);
select policies_are('public', 'required_documents', array['required_documents_select_document_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in (
       'document_types', 'documents', 'document_versions', 'document_links',
       'required_documents'
     )
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no document DML grants'
);

select has_function('public', 'upsert_document_type', array['uuid', 'text', 'text', 'text', 'uuid', 'uuid', 'integer', 'boolean', 'text']);
select has_function('public', 'create_document', array['uuid', 'text', 'text', 'text', 'bigint', 'text', 'uuid', 'uuid', 'uuid', 'text', 'date', 'date', 'date', 'text', 'text']);
select has_function('public', 'add_document_version', array['uuid', 'uuid', 'bigint', 'text', 'text', 'bigint', 'text', 'uuid', 'uuid', 'text', 'text']);
select has_function('public', 'confirm_document_content', array['uuid', 'uuid', 'integer', 'bigint', 'uuid', 'uuid', 'text']);
select has_function('public', 'verify_document_version', array['uuid', 'uuid', 'integer', 'bigint', 'text', 'uuid', 'uuid', 'text', 'text']);
select has_function('public', 'transition_document_status', array['uuid', 'uuid', 'bigint', 'text', 'uuid', 'uuid', 'uuid', 'text']);
select has_function('public', 'link_document', array['uuid', 'uuid', 'text', 'uuid', 'uuid', 'uuid', 'text', 'text']);
select has_function('public', 'unlink_document', array['uuid', 'uuid', 'uuid', 'uuid', 'text']);
select has_function('public', 'upsert_required_document', array['uuid', 'text', 'uuid', 'uuid', 'uuid', 'uuid', 'text', 'boolean', 'date', 'integer', 'uuid', 'text', 'boolean', 'boolean', 'text', 'boolean', 'text']);
select has_function('public', 'evaluate_document_requirements', array['uuid', 'text', 'uuid', 'text']);
select has_function('public', 'resolve_document_content_ref', array['uuid', 'uuid', 'integer']);

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
       'upsert_document_type', 'create_document', 'add_document_version',
       'confirm_document_content', 'verify_document_version',
       'transition_document_status', 'link_document', 'unlink_document',
       'upsert_required_document', 'evaluate_document_requirements',
       'resolve_document_content_ref'
     )),
  'document RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'upsert_document_type', 'create_document', 'add_document_version',
       'confirm_document_content', 'verify_document_version',
       'transition_document_status', 'link_document', 'unlink_document',
       'upsert_required_document', 'evaluate_document_requirements',
       'resolve_document_content_ref'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute document RPCs'
);

-- === Private Storage bucket ===========================================

select is(
  (select public from storage.buckets where id = 'documents'),
  false,
  'the documents bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'documents'),
  52428800::bigint,
  'the documents bucket carries the configured size limit'
);
select is(
  (select array_agg(policy.polname::text order by policy.polname)
   from pg_policy as policy
   where policy.polrelid = 'storage.objects'::regclass),
  array['documents_bucket_insert_document_manage', 'documents_bucket_select_document_read'],
  'storage.objects carries exactly the two document policies'
);
-- The absence of UPDATE/DELETE policies is what makes "versions are never
-- overwritten" structural rather than conventional.
select is(
  (select count(*)::integer
   from pg_policy as policy
   where policy.polrelid = 'storage.objects'::regclass
     and policy.polcmd in ('w', 'd', '*')),
  0,
  'no update or delete policy exists on storage.objects'
);
select is(
  private.document_storage_workspace('a1000000-0000-0000-0000-000000000001/doc/1/f.pdf'),
  'a1000000-0000-0000-0000-000000000001'::uuid,
  'the storage workspace parser reads the leading segment'
);
select is(
  private.document_storage_workspace('not-a-uuid/doc/1/f.pdf'),
  null::uuid,
  'a malformed object prefix parses to null and therefore fails closed'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('aa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('aa000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03-viewer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ab000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d03-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('a1000000-0000-0000-0000-000000000001', 'p2d03-workspace-a', 'P2D03 Workspace A'),
  ('a2000000-0000-0000-0000-000000000001', 'p2d03-workspace-b', 'P2D03 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('a3000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('a3000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'viewer', 'Viewer A'),
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('a5000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('a5000000-0000-0000-0000-000000000002', 'document.manage', 'Document Manage'),
  ('a5000000-0000-0000-0000-000000000003', 'document.verify', 'Document Verify'),
  ('a5000000-0000-0000-0000-000000000004', 'workspace.read', 'Workspace Read'),
  ('a5000000-0000-0000-0000-000000000005', 'audit.read', 'Audit Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- Manager A: read + manage + verify.
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001'),
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000002'),
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000003'),
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000004'),
  -- audit.read so the audit-trail assertions below read through RLS rather than
  -- around it.
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005'),
  -- Reader A: read only — may see documents, may neither manage nor verify.
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000001'),
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000004'),
  -- Viewer A: no document permission at all.
  ('a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000004'),
  ('a2000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001'),
  ('a2000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000002'),
  ('a2000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000004');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('a6000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'active'),
  ('a6000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000002', 'active'),
  ('a6000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000003', 'active'),
  ('a6000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values (
  'a7000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
  'aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'
);

-- Storage objects, written as postgres (the storage service's own role) so the
-- policies below are exercised purely as a read path.
insert into storage.objects (bucket_id, name, metadata) values
  ('documents', 'a1000000-0000-0000-0000-000000000001/doc-1/1/expose.pdf', '{"size": 1024}'::jsonb),
  ('documents', 'a1000000-0000-0000-0000-000000000001/doc-1/2/expose-v2.pdf', '{"size": 2048}'::jsonb),
  ('documents', 'a1000000-0000-0000-0000-000000000001/doc-2/1/kaufvertrag.pdf', '{"size": 512}'::jsonb),
  ('documents', 'a1000000-0000-0000-0000-000000000001/doc-3/1/grundbuch.pdf', '{"size": 300}'::jsonb),
  ('documents', 'a1000000-0000-0000-0000-000000000001/doc-4/1/energie.pdf', '{"size": 200}'::jsonb),
  ('documents', 'a2000000-0000-0000-0000-000000000001/doc-b/1/fremd.pdf', '{"size": 999}'::jsonb),
  ('documents', 'not-a-uuid/doc-x/1/stray.pdf', '{"size": 111}'::jsonb);

create temporary table p2_d03_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d03_results to authenticated;

-- === Document type registry ===========================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);

insert into p2_d03_results (key, result)
select 'type_expose', public.upsert_document_type(
  'a1000000-0000-0000-0000-000000000001', '  Expose  ', 'Exposé', 'property',
  'ae000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  null, true, 'seed expose type'
);
select is((select result ->> 'ok' from p2_d03_results where key = 'type_expose'), 'true', 'upsert_document_type creates a type');
select is((select result #>> '{entity,key}' from p2_d03_results where key = 'type_expose'), 'expose', 'the type key is normalized');

insert into p2_d03_results (key, result)
select 'type_grundbuch', public.upsert_document_type(
  'a1000000-0000-0000-0000-000000000001', 'grundbuchauszug', 'Grundbuchauszug', 'property',
  'ae000000-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-000000000002'
);
insert into p2_d03_results (key, result)
select 'type_energie', public.upsert_document_type(
  'a1000000-0000-0000-0000-000000000001', 'energieausweis', 'Energieausweis', 'property',
  'ae000000-0000-0000-0000-000000000003', 'ac000000-0000-0000-0000-000000000003', 120
);
insert into p2_d03_results (key, result)
select 'type_flurkarte', public.upsert_document_type(
  'a1000000-0000-0000-0000-000000000001', 'flurkarte', 'Flurkarte', 'property',
  'ae000000-0000-0000-0000-000000000004', 'ac000000-0000-0000-0000-000000000004'
);
select is(
  (select count(*)::integer from public.document_types
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  4,
  'the workspace type registry holds four types'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000002', true);
select is(
  public.upsert_document_type(
    'a1000000-0000-0000-0000-000000000001', 'blocked', 'Blocked', 'property',
    'ae000000-0000-0000-0000-00000000000a', 'ac000000-0000-0000-0000-00000000000a'
  ) #>> '{error,code}',
  'forbidden',
  'a member without document.manage cannot maintain the type registry'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);
select is(
  public.upsert_document_type(
    'a1000000-0000-0000-0000-000000000001', 'Not A Key!', 'Bad', 'property',
    'ae000000-0000-0000-0000-00000000000b', 'ac000000-0000-0000-0000-00000000000b'
  ) #>> '{error,code}',
  'validation_failed',
  'an unnormalizable type key is rejected'
);

-- === create_document ==================================================

insert into p2_d03_results (key, result)
select 'create_doc1', public.create_document(
  'a1000000-0000-0000-0000-000000000001',
  '  Expose Objekt A  ',
  'a1000000-0000-0000-0000-000000000001/doc-1/1/expose.pdf',
  repeat('a', 64),
  1024,
  'application/pdf',
  'ae000000-0000-0000-0000-000000000010', 'ac000000-0000-0000-0000-000000000010',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_expose'),
  'expose.pdf', null, null, null, null, 'initial upload'
);

select is((select result ->> 'ok' from p2_d03_results where key = 'create_doc1'), 'true', 'create_document succeeds');
select is((select result #>> '{entity,title}' from p2_d03_results where key = 'create_doc1'), 'Expose Objekt A', 'the title is trimmed');
select is((select result #>> '{entity,status}' from p2_d03_results where key = 'create_doc1'), 'uploaded', 'a new document starts in the uploaded state');
select is((select (result #>> '{entity,current_version_no}')::integer from p2_d03_results where key = 'create_doc1'), 1, 'a new document starts at content version 1');
select is((select (result #>> '{entity,version}')::bigint from p2_d03_results where key = 'create_doc1'), 1::bigint, 'a new document starts at row version 1');
select is(
  (select result #>> '{entity,current_version,content_hash}' from p2_d03_results where key = 'create_doc1'),
  repeat('a', 64),
  'the content hash round-trips as lowercase hex'
);
select is(
  (select result #>> '{entity,current_version,verification_status}' from p2_d03_results where key = 'create_doc1'),
  'pending',
  'a fresh version is unverified'
);
select is(
  (select result #>> '{entity,current_version,content_confirmed_at}' from p2_d03_results where key = 'create_doc1'),
  null,
  'a fresh version is unconfirmed'
);

-- A path outside the caller's workspace prefix cannot be registered: this is the
-- database-side half of the storage isolation.
select is(
  public.create_document(
    'a1000000-0000-0000-0000-000000000001', 'Fremdpfad',
    'a2000000-0000-0000-0000-000000000001/doc-b/1/fremd.pdf',
    repeat('c', 64), 10, 'application/pdf',
    'ae000000-0000-0000-0000-000000000011', 'ac000000-0000-0000-0000-000000000011'
  ) #>> '{error,code}',
  'validation_failed',
  'a storage path outside the workspace prefix is rejected'
);
select is(
  public.create_document(
    'a1000000-0000-0000-0000-000000000001', 'Traversal',
    'a1000000-0000-0000-0000-000000000001/../a2000000-0000-0000-0000-000000000001/x.pdf',
    repeat('c', 64), 10, 'application/pdf',
    'ae000000-0000-0000-0000-000000000012', 'ac000000-0000-0000-0000-000000000012'
  ) #>> '{error,code}',
  'validation_failed',
  'a traversal segment in the storage path is rejected'
);
select is(
  public.create_document(
    'a1000000-0000-0000-0000-000000000001', 'Bad hash',
    'a1000000-0000-0000-0000-000000000001/doc-z/1/x.pdf',
    'NOTAHASH', 10, 'application/pdf',
    'ae000000-0000-0000-0000-000000000013', 'ac000000-0000-0000-0000-000000000013'
  ) #>> '{error,code}',
  'validation_failed',
  'a non-sha256 content hash is rejected'
);
select is(
  public.create_document(
    'a1000000-0000-0000-0000-000000000001', 'Doppelter Pfad',
    'a1000000-0000-0000-0000-000000000001/doc-1/1/expose.pdf',
    repeat('d', 64), 10, 'application/pdf',
    'ae000000-0000-0000-0000-000000000014', 'ac000000-0000-0000-0000-000000000014'
  ) #>> '{error,code}',
  'validation_failed',
  'a storage object can back only one document version'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000002', true);
select is(
  public.create_document(
    'a1000000-0000-0000-0000-000000000001', 'Blocked',
    'a1000000-0000-0000-0000-000000000001/doc-y/1/x.pdf',
    repeat('e', 64), 10, 'application/pdf',
    'ae000000-0000-0000-0000-000000000015', 'ac000000-0000-0000-0000-000000000015'
  ) #>> '{error,code}',
  'forbidden',
  'a member without document.manage cannot create a document'
);

-- === upload -> verify -> supersede lifecycle (STM-008) ================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);

insert into p2_d03_results (key, result)
select 'confirm_doc1', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  1, 1,
  'ae000000-0000-0000-0000-000000000020', 'ac000000-0000-0000-0000-000000000020',
  'upload verified'
);
select is((select result #>> '{entity,status}' from p2_d03_results where key = 'confirm_doc1'), 'available', 'a confirmed upload becomes available');
select is((select result #>> '{entity,content_verified}' from p2_d03_results where key = 'confirm_doc1'), 'true', 'the confirmation reports a verified upload');
select isnt((select result #>> '{entity,current_version,content_confirmed_at}' from p2_d03_results where key = 'confirm_doc1'), null, 'the confirmed version records a confirmation timestamp');

-- Verification requires document.verify, which the reader does not hold.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000002', true);
select is(
  public.verify_document_version(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
    1, 2, 'verified',
    'ae000000-0000-0000-0000-000000000021', 'ac000000-0000-0000-0000-000000000021'
  ) #>> '{error,code}',
  'forbidden',
  'document.read alone does not permit verification'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);

insert into p2_d03_results (key, result)
select 'verify_doc1', public.verify_document_version(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  1, 2, 'verified',
  'ae000000-0000-0000-0000-000000000022', 'ac000000-0000-0000-0000-000000000022',
  'Sichtprüfung ok'
);
select is((select result #>> '{entity,verification_status}' from p2_d03_results where key = 'verify_doc1'), 'verified', 'the version records the verification outcome');
select is((select result #>> '{entity,document,status}' from p2_d03_results where key = 'verify_doc1'), 'verified', 'a verified current version lifts the document to verified');
select isnt((select result #>> '{entity,verified_by}' from p2_d03_results where key = 'verify_doc1'), null, 'the verifier is recorded');

-- Superseding a version never overwrites it.
insert into p2_d03_results (key, result)
select 'version2_doc1', public.add_document_version(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  3,
  'a1000000-0000-0000-0000-000000000001/doc-1/2/expose-v2.pdf',
  repeat('b', 64), 2048, 'application/pdf',
  'ae000000-0000-0000-0000-000000000023', 'ac000000-0000-0000-0000-000000000023',
  'expose-v2.pdf', 'corrected floor plan'
);
select is((select (result #>> '{entity,version_no}')::integer from p2_d03_results where key = 'version2_doc1'), 2, 'the new content version is numbered 2');
select is((select result #>> '{entity,document,status}' from p2_d03_results where key = 'version2_doc1'), 'uploaded', 'new content returns the document to uploaded');
select is(
  (select verification_status::text from public.document_versions
   where document_id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1')
     and version_no = 1),
  'verified',
  'the superseded version keeps its verification outcome'
);
select is(
  (select superseded_by_version_no from public.document_versions
   where document_id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1')
     and version_no = 1),
  2,
  'the previous version points at its successor'
);
select is(
  (select encode(content_hash, 'hex') from public.document_versions
   where document_id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1')
     and version_no = 1),
  repeat('a', 64),
  'the superseded version keeps its original content hash'
);
select is(
  (select count(*)::integer from public.document_versions
   where document_id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1')),
  2,
  'both content versions survive'
);

-- An unconfirmed version cannot be verified.
select is(
  public.verify_document_version(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
    2, 4, 'verified',
    'ae000000-0000-0000-0000-000000000024', 'ac000000-0000-0000-0000-000000000024'
  ) #>> '{error,code}',
  'validation_failed',
  'only an available document can be verified'
);

insert into p2_d03_results (key, result)
select 'confirm2_doc1', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  2, 4,
  'ae000000-0000-0000-0000-000000000025', 'ac000000-0000-0000-0000-000000000025'
);
select is((select result #>> '{entity,status}' from p2_d03_results where key = 'confirm2_doc1'), 'available', 'the second version confirms to available');

-- === Upload verification failure path (MIG-BND-003) ===================

insert into p2_d03_results (key, result)
select 'create_ghost', public.create_document(
  'a1000000-0000-0000-0000-000000000001', 'Fehlende Datei',
  'a1000000-0000-0000-0000-000000000001/doc-ghost/1/missing.pdf',
  repeat('f', 64), 4096, 'application/pdf',
  'ae000000-0000-0000-0000-000000000030', 'ac000000-0000-0000-0000-000000000030'
);
insert into p2_d03_results (key, result)
select 'confirm_ghost', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_ghost'),
  1, 1,
  'ae000000-0000-0000-0000-000000000031', 'ac000000-0000-0000-0000-000000000031'
);
select is(
  (select result #>> '{entity,status}' from p2_d03_results where key = 'confirm_ghost'),
  'rejected',
  'a declared upload with no storage object is rejected, not published'
);
select is(
  (select result #>> '{entity,current_version,content_confirmed_at}' from p2_d03_results where key = 'confirm_ghost'),
  null,
  'a rejected upload records no confirmation timestamp'
);

-- A size mismatch is also refused: doc-2's object is 512 bytes.
insert into p2_d03_results (key, result)
select 'create_mismatch', public.create_document(
  'a1000000-0000-0000-0000-000000000001', 'Groessen-Mismatch',
  'a1000000-0000-0000-0000-000000000001/doc-2/1/kaufvertrag.pdf',
  repeat('9', 64), 99999, 'application/pdf',
  'ae000000-0000-0000-0000-000000000032', 'ac000000-0000-0000-0000-000000000032'
);
insert into p2_d03_results (key, result)
select 'confirm_mismatch', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_mismatch'),
  1, 1,
  'ae000000-0000-0000-0000-000000000033', 'ac000000-0000-0000-0000-000000000033'
);
select is(
  (select result #>> '{entity,status}' from p2_d03_results where key = 'confirm_mismatch'),
  'rejected',
  'a byte-size mismatch against the stored object is rejected'
);

-- === Supersede and archive transitions (STM-008 matrix) ===============

insert into p2_d03_results (key, result)
select 'create_doc3', public.create_document(
  'a1000000-0000-0000-0000-000000000001', 'Grundbuchauszug',
  'a1000000-0000-0000-0000-000000000001/doc-3/1/grundbuch.pdf',
  repeat('3', 64), 300, 'application/pdf',
  'ae000000-0000-0000-0000-000000000040', 'ac000000-0000-0000-0000-000000000040',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_grundbuch'),
  'grundbuch.pdf'
);
insert into p2_d03_results (key, result)
select 'confirm_doc3', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
  1, 1,
  'ae000000-0000-0000-0000-000000000041', 'ac000000-0000-0000-0000-000000000041'
);
insert into p2_d03_results (key, result)
select 'verify_doc3', public.verify_document_version(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
  1, 2, 'verified',
  'ae000000-0000-0000-0000-000000000042', 'ac000000-0000-0000-0000-000000000042'
);

-- A rejected document is not an eligible successor.
select is(
  public.transition_document_status(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
    5, 'superseded',
    'ae000000-0000-0000-0000-000000000043', 'ac000000-0000-0000-0000-000000000043',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_ghost')
  ) #>> '{error,code}',
  'validation_failed',
  'a rejected document cannot supersede another'
);

insert into p2_d03_results (key, result)
select 'supersede_doc1', public.transition_document_status(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  5, 'superseded',
  'ae000000-0000-0000-0000-000000000044', 'ac000000-0000-0000-0000-000000000044',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
  'replaced by the notarized copy'
);
select is((select result #>> '{entity,status}' from p2_d03_results where key = 'supersede_doc1'), 'superseded', 'an available document can be superseded');
select is(
  (select result #>> '{entity,superseded_by_document_id}' from p2_d03_results where key = 'supersede_doc1'),
  (select result #>> '{entity,id}' from p2_d03_results where key = 'create_doc3'),
  'the successor is recorded on the superseded document'
);

select is(
  public.add_document_version(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
    6, 'a1000000-0000-0000-0000-000000000001/doc-1/3/x.pdf',
    repeat('7', 64), 1, 'application/pdf',
    'ae000000-0000-0000-0000-000000000045', 'ac000000-0000-0000-0000-000000000045'
  ) #>> '{error,code}',
  'validation_failed',
  'a superseded document accepts no further versions'
);

insert into p2_d03_results (key, result)
select 'archive_doc1', public.transition_document_status(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
  6, 'archived',
  'ae000000-0000-0000-0000-000000000046', 'ac000000-0000-0000-0000-000000000046',
  null, 'retention block'
);
select is((select result #>> '{entity,status}' from p2_d03_results where key = 'archive_doc1'), 'archived', 'a superseded document can be archived');
select isnt((select result #>> '{entity,archived_at}' from p2_d03_results where key = 'archive_doc1'), null, 'archiving stamps archived_at');

-- Archived is terminal.
select is(
  public.transition_document_status(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc1'),
    7, 'archived',
    'ae000000-0000-0000-0000-000000000047', 'ac000000-0000-0000-0000-000000000047'
  ) #>> '{error,code}',
  'validation_failed',
  'archived is a terminal state'
);
select is(
  public.transition_document_status(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    3, 'available',
    'ae000000-0000-0000-0000-000000000048', 'ac000000-0000-0000-0000-000000000048'
  ) #>> '{error,code}',
  'validation_failed',
  'only supersede and archive are commandable transitions'
);
select is(
  public.transition_document_status(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    99, 'archived',
    'ae000000-0000-0000-0000-000000000049', 'ac000000-0000-0000-0000-000000000049'
  ) #>> '{error,code}',
  'version_conflict',
  'a stale expected version conflicts'
);

-- === Links (DocumentLinkPort) =========================================

insert into p2_d03_results (key, result)
select 'link_doc3', public.link_document(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
  'property', 'a7000000-0000-0000-0000-000000000001',
  'ae000000-0000-0000-0000-000000000050', 'ac000000-0000-0000-0000-000000000050',
  'onboarding'
);
select is((select result ->> 'ok' from p2_d03_results where key = 'link_doc3'), 'true', 'a document links to a migrated entity');

select is(
  public.link_document(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    'property', 'a7000000-0000-0000-0000-000000000001',
    'ae000000-0000-0000-0000-000000000051', 'ac000000-0000-0000-0000-000000000051'
  ) #>> '{error,code}',
  'validation_failed',
  'the same link is not created twice'
);
select is(
  public.link_document(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    'lease', 'a7000000-0000-0000-0000-000000000001',
    'ae000000-0000-0000-0000-000000000052', 'ac000000-0000-0000-0000-000000000052'
  ) #>> '{error,code}',
  'dependency_conflict',
  'linking to an unmigrated domain reports a dependency conflict'
);
select is(
  public.link_document(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    'property', 'a7000000-0000-0000-0000-0000000000ff',
    'ae000000-0000-0000-0000-000000000053', 'ac000000-0000-0000-0000-000000000053'
  ) #>> '{error,code}',
  'not_found',
  'linking to a missing entity reports not_found'
);

insert into p2_d03_results (key, result)
select 'link_doc4_tmp', public.link_document(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_ghost'),
  'workspace', 'a1000000-0000-0000-0000-000000000001',
  'ae000000-0000-0000-0000-000000000054', 'ac000000-0000-0000-0000-000000000054'
);
select is(
  public.unlink_document(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'link_doc4_tmp'),
    'ae000000-0000-0000-0000-000000000055', 'ac000000-0000-0000-0000-000000000055'
  ) ->> 'ok',
  'true',
  'unlink_document removes the link'
);
select is(
  (select count(*)::integer from public.document_links
   where id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'link_doc4_tmp')),
  0,
  'the unlinked row is gone'
);

-- === Requirement policy + DUP-011 projection ==========================

-- Workspace-wide rule for every property: an expose is mandatory.
insert into p2_d03_results (key, result)
select 'req_grundbuch', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_grundbuch'),
  'ae000000-0000-0000-0000-000000000060', 'ac000000-0000-0000-0000-000000000060'
);
select is((select result #>> '{entity,is_mandatory}' from p2_d03_results where key = 'req_grundbuch'), 'true', 'a requirement defaults to mandatory');
select is((select result #>> '{entity,entity_id}' from p2_d03_results where key = 'req_grundbuch'), null, 'a workspace-wide rule carries no entity id');

insert into p2_d03_results (key, result)
select 'req_energie', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_energie'),
  'ae000000-0000-0000-0000-000000000061', 'ac000000-0000-0000-0000-000000000061',
  'a7000000-0000-0000-0000-000000000001'
);
insert into p2_d03_results (key, result)
select 'req_flurkarte', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_flurkarte'),
  'ae000000-0000-0000-0000-000000000062', 'ac000000-0000-0000-0000-000000000062',
  'a7000000-0000-0000-0000-000000000001'
);

-- An expired document: valid_until already in the past.
insert into p2_d03_results (key, result)
select 'create_doc4', public.create_document(
  'a1000000-0000-0000-0000-000000000001', 'Energieausweis',
  'a1000000-0000-0000-0000-000000000001/doc-4/1/energie.pdf',
  repeat('4', 64), 200, 'application/pdf',
  'ae000000-0000-0000-0000-000000000063', 'ac000000-0000-0000-0000-000000000063',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_energie'),
  'energie.pdf', (current_date - 400), (current_date - 1)
);
insert into p2_d03_results (key, result)
select 'confirm_doc4', public.confirm_document_content(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc4'),
  1, 1,
  'ae000000-0000-0000-0000-000000000064', 'ac000000-0000-0000-0000-000000000064'
);
insert into p2_d03_results (key, result)
select 'link_doc4', public.link_document(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc4'),
  'property', 'a7000000-0000-0000-0000-000000000001',
  'ae000000-0000-0000-0000-000000000065', 'ac000000-0000-0000-0000-000000000065'
);

insert into p2_d03_results (key, result)
select 'eval_1', public.evaluate_document_requirements(
  'a1000000-0000-0000-0000-000000000001', 'property',
  'a7000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d03_results where key = 'eval_1'), 'true', 'the requirement projection is readable');
select is(
  (select jsonb_array_length(result -> 'entity') from p2_d03_results where key = 'eval_1'),
  3,
  'workspace-wide and instance rules are evaluated together'
);
select is(
  (select item ->> 'state' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_1' and item ->> 'document_type_key' = 'grundbuchauszug'),
  'satisfied',
  'a linked verified document satisfies its requirement'
);
select is(
  (select item ->> 'state' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_1' and item ->> 'document_type_key' = 'energieausweis'),
  'expired',
  'a linked document past its validity end reports expired'
);
select is(
  (select item ->> 'state' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_1' and item ->> 'document_type_key' = 'flurkarte'),
  'missing',
  'a requirement with no document reports missing'
);
select is(
  (select item ->> 'is_instance_rule' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_1' and item ->> 'document_type_key' = 'grundbuchauszug'),
  'false',
  'the projection distinguishes workspace rules from instance requirements'
);

-- The legacy checklist state "angefordert" survives as requested_at.
insert into p2_d03_results (key, result)
select 'req_flurkarte_requested', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_flurkarte'),
  'ae000000-0000-0000-0000-000000000066', 'ac000000-0000-0000-0000-000000000066',
  'a7000000-0000-0000-0000-000000000001', null, true, null, null, null, null, true
);
insert into p2_d03_results (key, result)
select 'eval_2', public.evaluate_document_requirements(
  'a1000000-0000-0000-0000-000000000001', 'property',
  'a7000000-0000-0000-0000-000000000001'
);
select is(
  (select item ->> 'state' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_2' and item ->> 'document_type_key' = 'flurkarte'),
  'requested',
  'the legacy "angefordert" state survives as a requested requirement'
);

-- The legacy checklist state "nicht_relevant" survives as an audited waiver.
select is(
  public.upsert_required_document(
    'a1000000-0000-0000-0000-000000000001', 'property',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_flurkarte'),
    'ae000000-0000-0000-0000-000000000067', 'ac000000-0000-0000-0000-000000000067',
    'a7000000-0000-0000-0000-000000000001', null, true, null, null, null, null, false, true, null
  ) #>> '{error,code}',
  'validation_failed',
  'a waiver without a reason is rejected'
);
insert into p2_d03_results (key, result)
select 'req_flurkarte_waived', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_flurkarte'),
  'ae000000-0000-0000-0000-000000000068', 'ac000000-0000-0000-0000-000000000068',
  'a7000000-0000-0000-0000-000000000001', null, true, null, null, null, null, false, true,
  'Flurstueck unbebaut'
);
select isnt((select result #>> '{entity,waived_by}' from p2_d03_results where key = 'req_flurkarte_waived'), null, 'the waiver records its actor');
insert into p2_d03_results (key, result)
select 'eval_3', public.evaluate_document_requirements(
  'a1000000-0000-0000-0000-000000000001', 'property',
  'a7000000-0000-0000-0000-000000000001'
);
select is(
  (select item ->> 'state' from p2_d03_results, jsonb_array_elements(result -> 'entity') as item
   where key = 'eval_3' and item ->> 'document_type_key' = 'flurkarte'),
  'waived',
  'the legacy "nicht_relevant" state survives as a waived requirement'
);
select is(
  (select action from public.audit_events
   where mutation_id = 'ae000000-0000-0000-0000-000000000068'),
  'required_document.waive',
  'waiving a requirement is audited as its own action'
);

-- Retiring drops the rule out of the projection entirely.
insert into p2_d03_results (key, result)
select 'req_flurkarte_retired', public.upsert_required_document(
  'a1000000-0000-0000-0000-000000000001', 'property',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'type_flurkarte'),
  'ae000000-0000-0000-0000-000000000069', 'ac000000-0000-0000-0000-000000000069',
  'a7000000-0000-0000-0000-000000000001', null, true, null, null, null, null, false, false, null, true
);
insert into p2_d03_results (key, result)
select 'eval_4', public.evaluate_document_requirements(
  'a1000000-0000-0000-0000-000000000001', 'property',
  'a7000000-0000-0000-0000-000000000001'
);
select is(
  (select jsonb_array_length(result -> 'entity') from p2_d03_results where key = 'eval_4'),
  2,
  'a retired requirement leaves the projection'
);
select is(
  (select action from public.audit_events
   where mutation_id = 'ae000000-0000-0000-0000-000000000069'),
  'required_document.retire',
  'retiring a requirement is audited as its own action'
);

-- === SignedUrlPort input ==============================================

insert into p2_d03_results (key, result)
select 'ref_doc3', public.resolve_document_content_ref(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3')
);
select is(
  (select result #>> '{entity,storage_object_path}' from p2_d03_results where key = 'ref_doc3'),
  'a1000000-0000-0000-0000-000000000001/doc-3/1/grundbuch.pdf',
  'the content ref resolves the current version path'
);
select is(
  (select result #>> '{entity,storage_bucket}' from p2_d03_results where key = 'ref_doc3'),
  'documents',
  'the content ref names the private bucket'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000003', true);
select is(
  public.resolve_document_content_ref(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3')
  ) #>> '{error,code}',
  'forbidden',
  'a member without document.read cannot resolve content refs'
);
select is(
  public.evaluate_document_requirements(
    'a1000000-0000-0000-0000-000000000001', 'property',
    'a7000000-0000-0000-0000-000000000001'
  ) #>> '{error,code}',
  'forbidden',
  'a member without document.read cannot read the requirement projection'
);

-- === Workspace-scoped storage isolation ===============================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'documents'
     and name like 'a1000000-0000-0000-0000-000000000001/%'),
  5,
  'a document.read member sees the objects under its own workspace prefix'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'documents'
     and name like 'a2000000-0000-0000-0000-000000000001/%'),
  0,
  'objects under another workspace prefix are invisible'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'documents' and name like 'not-a-uuid/%'),
  0,
  'objects with a malformed prefix are invisible to everyone'
);

-- Versions are never overwritten or removed from the client side: the absence
-- of UPDATE/DELETE policies makes both no-ops rather than mutations.
with attempted as (
  update storage.objects
  set metadata = '{"size": 1}'::jsonb
  where bucket_id = 'documents'
    and name = 'a1000000-0000-0000-0000-000000000001/doc-1/1/expose.pdf'
  returning 1
)
select is((select count(*)::integer from attempted), 0, 'an authenticated client cannot overwrite a stored object');

-- Deletion is refused outright by Storage's own statement-level guard, which is
-- strictly stronger than the missing DELETE policy: it fires before RLS can even
-- filter the row set.
select throws_ok(
  $$delete from storage.objects
    where bucket_id = 'documents'
      and name = 'a1000000-0000-0000-0000-000000000001/doc-1/1/expose.pdf'$$,
  '42501',
  null,
  'an authenticated client cannot delete a stored object'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000003', true);
select is(
  (select count(*)::integer from storage.objects where bucket_id = 'documents'),
  0,
  'a member without document.read sees no objects at all'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'documents'
     and name like 'a1000000-0000-0000-0000-000000000001/%'),
  0,
  'the other workspace cannot see workspace A objects'
);
select is(
  (select count(*)::integer from public.documents
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'),
  0,
  'the other workspace cannot see workspace A documents'
);
select is(
  public.resolve_document_content_ref(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3')
  ) #>> '{error,code}',
  'forbidden',
  'the other workspace cannot resolve workspace A content refs'
);

-- === Idempotency and receipts =========================================

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);

insert into p2_d03_results (key, result)
select 'replay_link', public.link_document(
  'a1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc4'),
  'property', 'a7000000-0000-0000-0000-000000000001',
  'ae000000-0000-0000-0000-000000000065', 'ac000000-0000-0000-0000-000000000065'
);
select is(
  (select result from p2_d03_results where key = 'replay_link'),
  (select result from p2_d03_results where key = 'link_doc4'),
  'replaying a mutation id returns the identical recorded result'
);
select is(
  (select count(*)::integer from public.document_links
   where document_id = (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc4')),
  1,
  'a replayed link is not duplicated'
);
select is(
  public.link_document(
    'a1000000-0000-0000-0000-000000000001',
    (select (result #>> '{entity,id}')::uuid from p2_d03_results where key = 'create_doc3'),
    'workspace', 'a1000000-0000-0000-0000-000000000001',
    'ae000000-0000-0000-0000-000000000065', 'ac000000-0000-0000-0000-000000000099'
  ) #>> '{error,code}',
  'mutation_conflict',
  'reusing a mutation id for a different command conflicts'
);

reset role;
select is(
  (select count(*)::integer from public.mutation_receipts
   where workspace_id = 'a1000000-0000-0000-0000-000000000001' and status <> 'succeeded'),
  0,
  'no pending receipts survive a rejected post-claim validation'
);
select is(
  (select count(*)::integer from public.audit_events
   where workspace_id = 'a1000000-0000-0000-0000-000000000001'
     and entity_type in (
       'document', 'document_version', 'document_link', 'document_type',
       'required_document'
     )),
  (select count(*)::integer from public.mutation_receipts
   where workspace_id = 'a1000000-0000-0000-0000-000000000001' and status = 'succeeded'),
  'every succeeded document mutation left exactly one audit event'
);

-- === Immutability and direct DML ======================================

select throws_ok(
  $$update public.document_versions
    set content_hash = decode(repeat('0', 64), 'hex')
    where version_no = 1$$,
  '23000',
  null,
  'the content hash of a stored version is immutable'
);
select throws_ok(
  $$update public.document_versions
    set storage_object_path = 'x'
    where version_no = 1$$,
  '23000',
  null,
  'the storage path of a stored version is immutable'
);
select throws_ok(
  $$update public.documents set workspace_id = gen_random_uuid()$$,
  '23000',
  null,
  'a document cannot change workspace'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$insert into public.documents (workspace_id, title, created_by, updated_by)
    values ('a1000000-0000-0000-0000-000000000001', 'Direct', auth.uid(), auth.uid())$$,
  '42501',
  null,
  'a client cannot insert documents directly'
);
select throws_ok(
  $$insert into public.document_links (
      workspace_id, document_id, entity_type, entity_id, created_by
    ) values (
      'a1000000-0000-0000-0000-000000000001', gen_random_uuid(), 'property',
      'a7000000-0000-0000-0000-000000000001', auth.uid()
    )$$,
  '42501',
  null,
  'a client cannot insert document links directly'
);

reset role;
set local role anon;
-- anon holds no grant at all on the document tables, so it is refused before RLS
-- is even consulted.
select throws_ok(
  $$select count(*) from public.documents$$,
  '42501',
  null,
  'anon has no grant on documents'
);
-- storage.objects does carry the Supabase default anon grants, so there the
-- default-deny RLS is what has to hold.
select is(
  (select count(*)::integer from storage.objects where bucket_id = 'documents'),
  0,
  'anon sees no stored objects'
);

reset role;

select * from finish();

rollback;
