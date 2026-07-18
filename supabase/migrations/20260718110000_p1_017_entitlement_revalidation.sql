create policy entitlement_broadcast_receive_own
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) =
    'entitlements:' || (select auth.uid())::text
);

create function private.send_entitlement_revalidation(
  target_user_id uuid,
  target_workspace_id uuid,
  reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'user_id', target_user_id,
      'workspace_id', target_workspace_id,
      'reason', reason
    ),
    'revalidate',
    'entitlements:' || target_user_id::text,
    true
  );
exception
  when others then
    raise warning 'Entitlement broadcast unavailable; periodic revalidation remains active.';
end;
$$;

alter function private.send_entitlement_revalidation(uuid, uuid, text)
owner to postgres;
revoke all on function private.send_entitlement_revalidation(uuid, uuid, text)
from public, anon, authenticated;

create function private.broadcast_membership_entitlement_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_workspace_id uuid;
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status
    and new.role_id is not distinct from old.role_id then
    return null;
  end if;

  target_user_id := coalesce(new.user_id, old.user_id);
  target_workspace_id := coalesce(new.workspace_id, old.workspace_id);
  perform private.send_entitlement_revalidation(
    target_user_id,
    target_workspace_id,
    'membership_changed'
  );
  return null;
end;
$$;

alter function private.broadcast_membership_entitlement_change()
owner to postgres;
revoke all on function private.broadcast_membership_entitlement_change()
from public, anon, authenticated;

create trigger memberships_entitlement_broadcast
after insert or update or delete on public.memberships
for each row execute function private.broadcast_membership_entitlement_change();

create function private.broadcast_role_permission_entitlement_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target record;
begin
  for target in
    select distinct membership.user_id, membership.workspace_id
    from public.memberships as membership
    where membership.status = 'active'::public.membership_status
      and (
        (
          tg_op <> 'INSERT'
          and membership.workspace_id = old.workspace_id
          and membership.role_id = old.role_id
        )
        or (
          tg_op <> 'DELETE'
          and membership.workspace_id = new.workspace_id
          and membership.role_id = new.role_id
        )
      )
  loop
    perform private.send_entitlement_revalidation(
      target.user_id,
      target.workspace_id,
      'role_permissions_changed'
    );
  end loop;
  return null;
end;
$$;

alter function private.broadcast_role_permission_entitlement_change()
owner to postgres;
revoke all on function private.broadcast_role_permission_entitlement_change()
from public, anon, authenticated;

create trigger role_permissions_entitlement_broadcast
after insert or update or delete on public.role_permissions
for each row execute function private.broadcast_role_permission_entitlement_change();
