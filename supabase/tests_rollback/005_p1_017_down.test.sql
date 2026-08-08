begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

select has_table('public', 'memberships', 'P1-017 rollback keeps memberships');
select has_table(
  'public',
  'role_permissions',
  'P1-017 rollback keeps role permissions'
);
select hasnt_function(
  'private',
  'send_entitlement_revalidation',
  array['uuid', 'uuid', 'text'],
  'P1-017 rollback removes the entitlement sender'
);
select hasnt_trigger(
  'public',
  'memberships',
  'memberships_entitlement_broadcast',
  'P1-017 rollback removes the membership trigger'
);
select hasnt_trigger(
  'public',
  'role_permissions',
  'role_permissions_entitlement_broadcast',
  'P1-017 rollback removes the role permission trigger'
);
select ok(
  not exists (
    select 1
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polname = 'entitlement_broadcast_receive_own'
  ),
  'P1-017 rollback removes the entitlement broadcast policy'
);

select * from finish();
rollback;
