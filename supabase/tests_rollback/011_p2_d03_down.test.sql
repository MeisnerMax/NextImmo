begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- P2-D03 documents_compliance artifacts are removed on the down path.
select hasnt_table('public', 'document_types', 'P2-D03 document_types table is removed');
select hasnt_table('public', 'documents', 'P2-D03 documents table is removed');
select hasnt_table('public', 'document_versions', 'P2-D03 document_versions table is removed');
select hasnt_table('public', 'document_links', 'P2-D03 document_links table is removed');
select hasnt_table('public', 'required_documents', 'P2-D03 required_documents table is removed');
select hasnt_type('public', 'document_status', 'P2-D03 document_status enum is removed');
select hasnt_type('public', 'document_verification_status', 'P2-D03 verification enum is removed');
select hasnt_type('public', 'document_link_entity_type', 'P2-D03 link entity enum is removed');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'document_command_gate', 'claim_document_mutation', 'finish_document_mutation',
       'document_snapshot', 'document_version_snapshot', 'document_link_snapshot',
       'document_type_snapshot', 'required_document_snapshot',
       'document_storage_workspace', 'document_entity_ref_state'
     )),
  0,
  'P2-D03 private helpers are removed'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'upsert_document_type', 'create_document', 'add_document_version',
       'confirm_document_content', 'verify_document_version',
       'transition_document_status', 'link_document', 'unlink_document',
       'upsert_required_document', 'evaluate_document_requirements',
       'resolve_document_content_ref'
     )),
  0,
  'P2-D03 document RPCs are removed'
);

-- Storage down-path contract, asserted as it actually behaves rather than as one
-- might wish. `supabase migration down` recreates schema from the migrations but
-- restores table data from a dump, so the bucket ROW (data) outlives the
-- rollback while the policies (schema) do not. The security-relevant property is
-- therefore not "the bucket is gone" but "whatever survives is inert": a private
-- bucket with zero policies is unreachable by any client role, and the migration
-- re-asserts `public = false` on replay.
select is(
  (select count(*)::integer
   from pg_policy as policy
   where policy.polrelid = 'storage.objects'::regclass),
  0,
  'P2-D03 storage.objects policies are removed'
);
select ok(
  not exists (select 1 from storage.buckets where id = 'documents' and public),
  'a documents bucket surviving the rollback is never public'
);

-- The layers underneath remain intact.
select has_table('public', 'parties', 'P2-D02 parties table remains');
select has_function(
  'private', 'has_workspace_permission', array['uuid', 'text'],
  'P1-003 permission helper remains'
);

select * from finish();

rollback;
