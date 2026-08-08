-- PH-01-T04: Entity scopes are an optional, narrowing allowlist.
-- No scope rows means workspace-wide access. Once a membership has at least
-- one row, only an explicit supported entity match is allowed.

alter table public.entity_scopes
add constraint entity_scopes_supported_entity_type_check
check (entity_type in ('property', 'portfolio'));

create function private.has_entity_scope(
  target_workspace_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
begin
  if auth.uid() is null
     or target_workspace_id is null
     or target_entity_id is null
     or target_entity_type not in ('property', 'portfolio') then
    return false;
  end if;

  select membership.id
  into v_membership_id
  from public.memberships as membership
  where membership.workspace_id = target_workspace_id
    and membership.user_id = auth.uid()
    and membership.status = 'active'::public.membership_status;

  if v_membership_id is null then
    return false;
  end if;

  if not exists (
    select 1
    from public.entity_scopes as scope
    where scope.workspace_id = target_workspace_id
      and scope.membership_id = v_membership_id
  ) then
    return true;
  end if;

  return exists (
    select 1
    from public.entity_scopes as scope
    where scope.workspace_id = target_workspace_id
      and scope.membership_id = v_membership_id
      and scope.entity_type = target_entity_type
      and scope.entity_id = target_entity_id
  );
end;
$$;

create function private.has_scoped_entity_permission(
  target_workspace_id uuid,
  permission_key text,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_workspace_permission(target_workspace_id, permission_key)
    and private.has_entity_scope(
      target_workspace_id,
      target_entity_type,
      target_entity_id
    );
$$;

alter function private.has_entity_scope(uuid, text, uuid) owner to postgres;
alter function private.has_scoped_entity_permission(uuid, text, text, uuid)
  owner to postgres;

revoke all on function private.has_entity_scope(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.has_scoped_entity_permission(uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function private.has_entity_scope(uuid, text, uuid)
  to authenticated;
grant execute on function private.has_scoped_entity_permission(uuid, text, text, uuid)
  to authenticated;

drop policy properties_select_property_read on public.properties;
create policy properties_select_property_read
on public.properties
for select
to authenticated
using (
  private.has_scoped_entity_permission(
    workspace_id,
    'property.read',
    'property',
    id
  )
);

-- Keep the original command implementation private and put the scope check in
-- front of it. This also prevents a successful mutation receipt from replaying
-- property data after the actor's entity scope was revoked.
alter function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  set schema private;
revoke all on function private.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  from public, anon, authenticated;

create function public.update_property(
  p_workspace_id uuid,
  p_property_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_changes jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     )
     or not private.has_scoped_entity_permission(
       p_workspace_id, 'property.update', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Property update is not permitted'
      )
    );
  end if;

  return private.update_property(
    p_workspace_id,
    p_property_id,
    p_expected_version,
    p_mutation_id,
    p_correlation_id,
    p_changes,
    p_reason
  );
end;
$$;

alter function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  owner to postgres;
revoke all on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  to authenticated;
