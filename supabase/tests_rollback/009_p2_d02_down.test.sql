begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- P2-D02 contacts_parties artifacts are removed on the down path.
select hasnt_table('public', 'parties', 'P2-D02 parties table is removed');
select hasnt_table('public', 'party_roles', 'P2-D02 party_roles table is removed');
select hasnt_table('public', 'party_contractor_details', 'P2-D02 contractor satellite is removed');
select hasnt_table('public', 'party_aliases', 'P2-D02 party_aliases table is removed');
select hasnt_type('public', 'party_type', 'P2-D02 party_type enum is removed');
select hasnt_type('public', 'party_role_type', 'P2-D02 party_role_type enum is removed');
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname in (
       'party_command_gate', 'claim_party_mutation', 'finish_party_mutation',
       'party_snapshot', 'party_role_snapshot', 'contractor_details_snapshot'
     )),
  0,
  'P2-D02 private helpers are removed'
);
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'create_party', 'update_party', 'assign_party_role',
       'end_party_role', 'merge_parties', 'detect_party_duplicates'
     )),
  0,
  'P2-D02 party RPCs are removed'
);

-- The layers underneath remain intact.
select has_table('public', 'membership_invitations', 'P2-D01 invitations table remains');
select has_function('public', 'list_workspace_members', array['uuid'], 'P2-D01 directory RPC remains');
select has_function(
  'public', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-004 update RPC remains'
);
select has_function(
  'private', 'has_workspace_permission', array['uuid', 'text'],
  'P1-003 permission helper remains'
);

select * from finish();

rollback;
