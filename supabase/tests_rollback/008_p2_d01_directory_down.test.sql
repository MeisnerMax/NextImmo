begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- Rolling back the member-directory migration removes only its RPC.
select hasnt_function('public', 'list_workspace_members', array['uuid']);

-- The P2-D01 membership lifecycle layer underneath remains intact.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'invite_workspace_member', 'list_my_pending_invitations',
       'accept_workspace_invitation', 'update_membership_status',
       'change_membership_role', 'revoke_workspace_invitation'
     )),
  6,
  'P2-D01 membership lifecycle RPCs remain'
);
select has_table('public', 'membership_invitations', 'P2-D01 invitations table remains');
select has_function(
  'private', 'has_workspace_permission', array['uuid', 'text'],
  'P1-003 permission helper remains'
);

select * from finish();

rollback;
