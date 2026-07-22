begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- P2-D01 membership lifecycle artifacts are removed on the down path.
select hasnt_table('public', 'membership_invitations', 'P2-D01 invitations table is removed');
select hasnt_type('public', 'membership_invitation_status', 'P2-D01 invitation status enum is removed');
select hasnt_function('private', 'membership_command_gate', array['uuid', 'uuid', 'uuid', 'text']);
select hasnt_function('private', 'claim_membership_mutation', array['uuid', 'uuid', 'bytea', 'text']);
select hasnt_function(
  'private', 'finish_membership_mutation',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'uuid', 'jsonb', 'jsonb']
);
select hasnt_function('private', 'would_remove_last_security_manager', array['uuid', 'uuid']);
select hasnt_function('private', 'membership_snapshot', array['public.memberships']);
select hasnt_function('private', 'membership_invitation_snapshot', array['public.membership_invitations']);
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
  0,
  'P2-D01 membership RPCs are removed'
);

-- The layers underneath remain intact.
select has_table('public', 'memberships', 'P1-002 memberships remains');
select has_function(
  'public', 'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-004 update RPC remains'
);
select has_function(
  'private', 'properties_apply_delete_marker', '{}'::text[],
  'DEBT-012 delete-marker function remains'
);
select policies_are('public', 'memberships', array['memberships_select_authorized']);

select * from finish();

rollback;
