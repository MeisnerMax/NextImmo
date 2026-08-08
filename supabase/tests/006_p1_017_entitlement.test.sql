begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

select ok(
  exists (
    select 1
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polname = 'entitlement_broadcast_receive_own'
  ),
  'own entitlement broadcast policy exists'
);
select ok(
  (
    select polcmd = 'r'
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polname = 'entitlement_broadcast_receive_own'
  ),
  'entitlement broadcast policy is select-only'
);
select ok(
  (
    select pg_get_expr(policy.polqual, policy.polrelid) like '%realtime.topic()%'
    from pg_policy as policy
    where policy.polrelid = 'realtime.messages'::regclass
      and policy.polname = 'entitlement_broadcast_receive_own'
  ),
  'entitlement broadcast policy binds the realtime topic'
);
select ok(
  (
    select pg_get_expr(policy.polqual, policy.polrelid) like '%auth.uid()%'
    from pg_policy as policy
    where policy.polrelid = 'realtime.messages'::regclass
      and policy.polname = 'entitlement_broadcast_receive_own'
  ),
  'entitlement broadcast policy binds the authenticated user'
);
select has_function(
  'private',
  'send_entitlement_revalidation',
  array['uuid', 'uuid', 'text'],
  'private entitlement sender exists'
);
select function_returns(
  'private',
  'send_entitlement_revalidation',
  array['uuid', 'uuid', 'text'],
  'void',
  'private entitlement sender returns void'
);
select isnt(
  has_function_privilege(
    'authenticated',
    'private.send_entitlement_revalidation(uuid, uuid, text)',
    'EXECUTE'
  ),
  true,
  'clients cannot execute the entitlement sender'
);
select ok(
  (
    select procedure.prosecdef
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname = 'send_entitlement_revalidation'
  ),
  'entitlement sender is security definer'
);
select ok(
  pg_get_functiondef('private.send_entitlement_revalidation(uuid, uuid, text)'::regprocedure)
    like '%realtime.send(%',
  'entitlement sender uses database broadcast'
);
select ok(
  pg_get_functiondef('private.send_entitlement_revalidation(uuid, uuid, text)'::regprocedure)
    like '%entitlements:%',
  'entitlement sender uses a user-scoped topic'
);
select has_trigger(
  'public',
  'memberships',
  'memberships_entitlement_broadcast',
  'membership entitlement trigger exists'
);
select has_trigger(
  'public',
  'role_permissions',
  'role_permissions_entitlement_broadcast',
  'role permission entitlement trigger exists'
);
select ok(
  pg_get_functiondef('private.broadcast_membership_entitlement_change()'::regprocedure)
    like '%new.status is not distinct from old.status%',
  'membership trigger detects status changes'
);
select ok(
  pg_get_functiondef('private.broadcast_membership_entitlement_change()'::regprocedure)
    like '%new.role_id is not distinct from old.role_id%',
  'membership trigger detects role changes'
);
select ok(
  pg_get_functiondef('private.broadcast_role_permission_entitlement_change()'::regprocedure)
    like '%public.memberships%',
  'role permission trigger targets affected memberships'
);
select ok(
  pg_get_functiondef('private.broadcast_role_permission_entitlement_change()'::regprocedure)
    like '%membership.status = ''active''%',
  'role permission trigger targets active memberships only'
);

select * from finish();
rollback;
