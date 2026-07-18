create index if not exists memberships_user_id_status_idx
on public.memberships (user_id, status);

create index if not exists memberships_workspace_id_role_id_idx
on public.memberships (workspace_id, role_id);

create index if not exists role_permissions_permission_id_idx
on public.role_permissions (permission_id);

create index if not exists properties_workspace_id_id_idx
on public.properties (workspace_id, id);

create index if not exists properties_workspace_id_id_not_archived_idx
on public.properties (workspace_id, id)
where status <> 'archived'::public.property_status;

drop policy if exists user_profiles_select_own on public.user_profiles;
create policy user_profiles_select_own
on public.user_profiles
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists permissions_select_authenticated on public.permissions;
create policy permissions_select_authenticated
on public.permissions
for select
to authenticated
using ((select auth.uid()) is not null);
