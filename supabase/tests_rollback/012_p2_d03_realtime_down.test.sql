begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- Rolling back the document realtime migration removes only the publication
-- entry.
select is(
  (select count(*)::integer
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'documents'),
  0,
  'P2-D03 rollback removes documents from the Realtime publication'
);

-- The P2-D03 contract underneath remains intact.
select has_table('public', 'documents', 'P2-D03 rollback keeps the documents table');
select has_table(
  'public', 'document_versions', 'P2-D03 rollback keeps the document_versions table'
);
select has_function(
  'public', 'confirm_document_content',
  array['uuid', 'uuid', 'integer', 'bigint', 'uuid', 'uuid', 'text'],
  'P2-D03 rollback keeps the content confirmation RPC'
);

select * from finish();

rollback;
