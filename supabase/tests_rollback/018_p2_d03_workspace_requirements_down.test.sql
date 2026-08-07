begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

-- Rolling back the workspace-requirement increment removes the workspace-wide
-- entry point and the extracted derivation helper.
select hasnt_function(
  'public', 'evaluate_workspace_document_requirements',
  array['uuid', 'text', 'uuid[]', 'boolean'],
  'rollback removes the workspace-wide requirement projection'
);
select hasnt_function(
  'private', 'document_requirement_state',
  array['timestamptz', 'timestamptz', 'uuid', 'public.document_status', 'date'],
  'rollback removes the extracted state derivation'
);

-- The P2-D03 contract underneath is untouched, and the per-entity projection
-- goes back to deriving the state inline — so it must still work, not just
-- still exist.
select has_function(
  'public', 'evaluate_document_requirements',
  array['uuid', 'text', 'uuid', 'text'],
  'rollback keeps the per-entity requirement projection'
);
select has_table(
  'public', 'required_documents', 'rollback keeps the required_documents table'
);
select ok(
  (select public.evaluate_document_requirements(
     '00000000-0000-0000-0000-000000000000',
     'property',
     '00000000-0000-0000-0000-000000000001'
   ) -> 'error' ->> 'code') = 'forbidden',
  'the restored per-entity projection still fails closed without a session'
);

select * from finish();

rollback;
