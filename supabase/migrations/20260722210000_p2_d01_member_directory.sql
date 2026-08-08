-- P2-D01: identity_access full expansion — workspace member directory.
--
-- The admin members UI needs each member's display name (public.user_profiles)
-- and email (auth.users) alongside their role and lifecycle status. Neither the
-- profile nor the auth.users email is reachable through the invitee's or an
-- admin's row-level security, so this read goes through a security-definer RPC
-- gated on security.manage, mirroring list_my_pending_invitations (P2-D01
-- increment 1). It is a read, so there is no AAL2 gate, no mutation receipt and
-- no audit event — only the permission check.
--
-- The result uses the same {ok,entity}/{ok,error:{code}} envelope as the
-- membership mutation RPCs so the adapter can surface a forbidden read
-- distinctly from an empty directory.

create function public.list_workspace_members(p_workspace_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'validation_failed', 'message', 'Workspace is required')
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Member directory access is not permitted'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'entity', coalesce(
      (
        select jsonb_agg(entry order by sort_created_at, sort_membership_id)
        from (
          select
            jsonb_build_object(
              'membership_id', membership.id,
              'workspace_id', membership.workspace_id,
              'user_id', membership.user_id,
              'role_id', membership.role_id,
              'role_key', role.key,
              'role_name', role.name,
              'display_name', profile.display_name,
              'email', auth_user.email,
              'status', membership.status,
              'created_at', membership.created_at,
              'updated_at', membership.updated_at,
              'version', membership.version
            ) as entry,
            membership.created_at as sort_created_at,
            membership.id as sort_membership_id
          from public.memberships as membership
          join public.roles as role
            on role.workspace_id = membership.workspace_id
            and role.id = membership.role_id
          left join public.user_profiles as profile
            on profile.user_id = membership.user_id
          left join auth.users as auth_user
            on auth_user.id = membership.user_id
          where membership.workspace_id = p_workspace_id
        ) as directory_rows
      ),
      '[]'::jsonb
    )
  );
end;
$$;

alter function public.list_workspace_members(uuid) owner to postgres;
revoke all on function public.list_workspace_members(uuid)
  from public, anon, authenticated;
grant execute on function public.list_workspace_members(uuid) to authenticated;
