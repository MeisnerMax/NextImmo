\set ON_ERROR_STOP on

create function public.p1_017_set_property_read(grant_access boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_permission_id uuid;
begin
  select permission.id
  into strict target_permission_id
  from public.permissions as permission
  where permission.key = 'property.read';

  if grant_access then
    insert into public.role_permissions (
      workspace_id,
      role_id,
      permission_id
    ) values (
      '17000000-0000-0000-0000-000000000001',
      '17000000-0000-0000-0000-000000000002',
      target_permission_id
    ) on conflict do nothing;
  else
    delete from public.role_permissions
    where workspace_id = '17000000-0000-0000-0000-000000000001'
      and role_id = '17000000-0000-0000-0000-000000000002'
      and permission_id = target_permission_id;
  end if;
end;
$$;

alter function public.p1_017_set_property_read(boolean) owner to postgres;
revoke all on function public.p1_017_set_property_read(boolean)
from public, anon;
grant execute on function public.p1_017_set_property_read(boolean)
to authenticated;

create function public.p1_017_set_membership_active(active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.memberships
  set
    status = case
      when active then 'active'::public.membership_status
      else 'suspended'::public.membership_status
    end,
    updated_at = now(),
    version = version + 1
  where workspace_id = '17000000-0000-0000-0000-000000000001'
    and user_id = 'a7000000-0000-0000-0000-000000000001';
end;
$$;

alter function public.p1_017_set_membership_active(boolean) owner to postgres;
revoke all on function public.p1_017_set_membership_active(boolean)
from public, anon;
grant execute on function public.p1_017_set_membership_active(boolean)
to authenticated;
