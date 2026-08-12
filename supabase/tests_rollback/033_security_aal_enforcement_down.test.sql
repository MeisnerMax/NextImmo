begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- Rolling back SECURITY-AAL-ENFORCEMENT-01 must remove the assurance predicate
-- and every place that reaches for it, and must leave the two guards that
-- predate this package untouched: membership_command_gate keeps its own inline
-- aal2 check, and update_property keeps its own wrapper. A rollback that took
-- either of those with it would silently drop the DEC-016 boundary that was
-- already in force before this migration.

select hasnt_function('private', 'is_aal2', array[]::text[],
  'the assurance predicate is removed');

select is(
  (select count(*)::integer
   from pg_proc
   join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
   where pg_namespace.nspname = 'private'
     and pg_proc.proname = 'has_workspace_permission'
     and pg_get_functiondef(pg_proc.oid) ~ 'is_aal2'),
  0,
  'the central permission helper no longer reaches the predicate'
);

-- Exactly one, not zero: membership_command_gate predates this package.
select is(
  (select count(*)::integer
   from pg_proc
   join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
   where pg_namespace.nspname = 'private'
     and pg_proc.proname like '%command_gate'
     and pg_get_functiondef(pg_proc.oid) ~ 'aal2'),
  1,
  'only the pre-existing membership gate still enforces aal2'
);

select is(
  (select pg_get_expr(polqual, polrelid)
   from pg_policy where polname = 'memberships_select_authorized'),
  '((user_id = ( SELECT auth.uid() AS uid)) OR private.has_workspace_permission(workspace_id, ''security.manage''::text))',
  'the membership SELECT policy is back to its OR-shaped form'
);

select is(
  (select pg_get_expr(polqual, polrelid)
   from pg_policy where polname = 'notifications_select_own_or_read'),
  '((recipient_user_id = ( SELECT auth.uid() AS uid)) OR private.has_workspace_permission(workspace_id, ''notification.read''::text))',
  'the notification SELECT policy is back to its OR-shaped form'
);

select is(
  (select pg_get_expr(polqual, polrelid)
   from pg_policy where polname = 'permissions_select_authenticated'),
  '(( SELECT auth.uid() AS uid) IS NOT NULL)',
  'the permission catalogue policy is back to authenticated-only'
);

select is(
  (select pg_get_expr(polqual, polrelid)
   from pg_policy where polname = 'entitlement_broadcast_receive_own'),
  '((extension = ''broadcast''::text) AND (( SELECT realtime.topic() AS topic) = (''entitlements:''::text || (( SELECT auth.uid() AS uid))::text)))',
  'the entitlement broadcast policy is back to uid-only'
);

-- The H1 reordering is reverted with the rest: the probe runs first again.
select ok(
  (select strpos(pg_get_functiondef(pg_proc.oid), 'leasing_property_in_workspace')
        < strpos(pg_get_functiondef(pg_proc.oid), 'has_workspace_permission')
   from pg_proc
   join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
   where pg_namespace.nspname = 'public' and pg_proc.proname = 'operations_signals'),
  'the operations signal probe runs before authorization again'
);

select is(
  (select count(*)::integer
   from pg_proc
   join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
   where pg_namespace.nspname = 'public'
     and pg_proc.proname = 'list_my_pending_invitations'
     and pg_get_functiondef(pg_proc.oid) ~ 'is_aal2'),
  0,
  'the pending invitation listing no longer reaches the predicate'
);

select * from finish();

rollback;
