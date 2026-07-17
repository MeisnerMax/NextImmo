create function private.is_active_workspace_member(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships as membership
    where membership.workspace_id = target_workspace_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'::public.membership_status
  );
$$;

create function private.has_workspace_permission(target_workspace_id uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships as membership
    join public.role_permissions as role_permission
      on role_permission.workspace_id = membership.workspace_id
      and role_permission.role_id = membership.role_id
    join public.permissions as permission
      on permission.id = role_permission.permission_id
    where membership.workspace_id = target_workspace_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'::public.membership_status
      and permission.key = permission_key
  );
$$;

create function private.is_current_active_membership(target_workspace_id uuid, target_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships as membership
    where membership.workspace_id = target_workspace_id
      and membership.id = target_membership_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'::public.membership_status
  );
$$;

alter function private.is_active_workspace_member(uuid) owner to postgres;
alter function private.has_workspace_permission(uuid, text) owner to postgres;
alter function private.is_current_active_membership(uuid, uuid) owner to postgres;

revoke all on function private.is_active_workspace_member(uuid) from public, anon, authenticated;
revoke all on function private.has_workspace_permission(uuid, text) from public, anon, authenticated;
revoke all on function private.is_current_active_membership(uuid, uuid) from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;

grant usage on schema private to authenticated;
grant execute on function private.is_active_workspace_member(uuid) to authenticated;
grant execute on function private.has_workspace_permission(uuid, text) to authenticated;
grant execute on function private.is_current_active_membership(uuid, uuid) to authenticated;

create policy workspaces_select_workspace_read
on public.workspaces
for select
to authenticated
using (private.has_workspace_permission(id, 'workspace.read'));

create policy user_profiles_select_own
on public.user_profiles
for select
to authenticated
using (user_id = auth.uid());

create policy memberships_select_authorized
on public.memberships
for select
to authenticated
using (
  (
    private.is_current_active_membership(workspace_id, id)
    and private.has_workspace_permission(workspace_id, 'workspace.read')
  )
  or private.has_workspace_permission(workspace_id, 'security.manage')
);

create policy roles_select_workspace_read
on public.roles
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'workspace.read'));

create policy permissions_select_authenticated
on public.permissions
for select
to authenticated
using (auth.uid() is not null);

create policy role_permissions_select_workspace_read
on public.role_permissions
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'workspace.read'));

create policy entity_scopes_select_authorized
on public.entity_scopes
for select
to authenticated
using (
  (
    private.is_current_active_membership(workspace_id, membership_id)
    and private.has_workspace_permission(workspace_id, 'workspace.read')
  )
  or private.has_workspace_permission(workspace_id, 'security.manage')
);

create policy audit_events_select_audit_read
on public.audit_events
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'audit.read'));

revoke all on table
  public.workspaces,
  public.user_profiles,
  public.roles,
  public.permissions,
  public.memberships,
  public.role_permissions,
  public.entity_scopes,
  public.audit_events,
  public.mutation_receipts
from anon, authenticated;

grant select on table
  public.workspaces,
  public.user_profiles,
  public.roles,
  public.permissions,
  public.memberships,
  public.role_permissions,
  public.entity_scopes,
  public.audit_events
to authenticated;
