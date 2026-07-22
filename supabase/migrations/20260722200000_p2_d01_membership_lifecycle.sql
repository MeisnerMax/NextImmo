-- P2-D01: identity_access full expansion — membership lifecycle (STM-001).
--
-- The P1 baseline already ships the four-state membership_status enum
-- (invited/active/suspended/revoked), default-deny RLS with an admin read
-- policy (security.manage), and entitlement-invalidation triggers on
-- memberships/role_permissions (P1-017). This migration adds the mutation
-- surface, mirroring the P1-004 property contract shape: security-definer
-- RPCs with an AAL2 gate, permission checks, optimistic versioning
-- (p_expected_version), idempotency (mutation_receipts), correlation ids and
-- append-only audit events.
--
-- Membership lifecycle on the membership row itself:
--   invite (existing auth user)  -> status 'invited'
--   accept (invitee)             -> 'invited' -> 'active'
--   suspend / reactivate (admin) -> 'active' <-> 'suspended'
--   revoke (admin, terminal)     -> 'invited'/'active'/'suspended' -> 'revoked'
--
-- Emails without an auth user cannot become memberships yet (clients hold no
-- service-role key, so auth.users rows cannot be pre-created): those go to
-- membership_invitations and are converted by the invitee's accept call on
-- first sign-in.

-- -----------------------------------------------------------------------------
-- membership_invitations: pre-auth staging for invited emails.
-- -----------------------------------------------------------------------------

create type public.membership_invitation_status as enum (
  'pending',
  'accepted',
  'revoked'
);

create table public.membership_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  email text not null,
  role_id uuid not null,
  status public.membership_invitation_status not null default 'pending',
  accepted_membership_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint membership_invitations_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint membership_invitations_workspace_role_fkey foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict,
  constraint membership_invitations_accepted_membership_fkey
    foreign key (workspace_id, accepted_membership_id)
    references public.memberships (workspace_id, id) on delete restrict,
  constraint membership_invitations_email_normalized_check check (
    email = lower(btrim(email))
    and char_length(email) between 3 and 320
    and position('@' in email) > 1
  ),
  constraint membership_invitations_accepted_pair_check check (
    (status = 'accepted'::public.membership_invitation_status)
      = (accepted_membership_id is not null)
  ),
  constraint membership_invitations_version_check check (version >= 1)
);

-- One live invitation per workspace/email; resolved invitations keep history.
create unique index membership_invitations_pending_unique
  on public.membership_invitations (workspace_id, email)
  where status = 'pending'::public.membership_invitation_status;

create index membership_invitations_workspace_role_idx
  on public.membership_invitations (workspace_id, role_id);

create index membership_invitations_accepted_membership_idx
  on public.membership_invitations (workspace_id, accepted_membership_id)
  where accepted_membership_id is not null;

create trigger membership_invitations_protected_columns
before update on public.membership_invitations
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'email', 'created_at', 'created_by'
);

alter table public.membership_invitations enable row level security;
alter table public.membership_invitations force row level security;

-- Admins manage invitations; there is no self-service read path by design —
-- a not-yet-registered invitee has no session, and a registered invitee uses
-- list_my_pending_invitations (security definer) instead of a broad policy.
create policy membership_invitations_select_security_manage
on public.membership_invitations
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'security.manage'));

revoke all on table public.membership_invitations from anon, authenticated;
grant select on table public.membership_invitations to authenticated;

-- -----------------------------------------------------------------------------
-- Members may always read their own membership rows (any status), so an
-- invited or suspended user can see where they stand. The existing P1-003
-- policy is replaced in place (same name, so pgTAP policies_are and the
-- single-permissive-policy shape stay intact): the previous
-- own-active-row-with-workspace.read clause is a strict subset of the new
-- own-row clause. Workspace/role details stay behind their existing
-- permission-gated policies.
-- -----------------------------------------------------------------------------

drop policy memberships_select_authorized on public.memberships;

create policy memberships_select_authorized
on public.memberships
for select
to authenticated
using (
  user_id = (select auth.uid())
  or private.has_workspace_permission(workspace_id, 'security.manage')
);

-- -----------------------------------------------------------------------------
-- Shared helpers (private): command envelope validation, AAL2 gate,
-- idempotency claim and audit write — one implementation for all five
-- membership RPCs instead of five copies of the P1-004 boilerplate.
-- -----------------------------------------------------------------------------

create function private.membership_command_gate(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text
)
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

  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for membership mutations'
      )
    );
  end if;

  if p_workspace_id is null or p_mutation_id is null or p_correlation_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Command identifiers are required'
      )
    );
  end if;

  if p_reason is not null
     and char_length(btrim(p_reason)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Reason must contain at most 2000 characters',
        'field', 'reason'
      )
    );
  end if;

  return null;
end;
$$;

alter function private.membership_command_gate(uuid, uuid, uuid, text)
  owner to postgres;
revoke all on function private.membership_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- Claims the mutation id for this command. Returns null when the caller owns
-- a fresh receipt (proceed), otherwise the deterministic replay result:
-- the recorded success payload, a mutation_conflict, or in_progress.
create function private.claim_membership_mutation(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_request_hash bytea,
  p_entity_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_replayed jsonb;
begin
  insert into public.mutation_receipts (
    workspace_id, mutation_id, request_hash, status, created_by, updated_by
  ) values (
    p_workspace_id, p_mutation_id, p_request_hash, 'pending', v_actor_id, v_actor_id
  )
  on conflict (workspace_id, mutation_id) do nothing
  returning id into v_inserted_receipt_id;

  if v_inserted_receipt_id is not null then
    return null;
  end if;

  select receipt.*
  into v_receipt
  from public.mutation_receipts as receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.mutation_id = p_mutation_id
  for update;

  if v_receipt.request_hash is distinct from p_request_hash then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'mutation_conflict',
        'message', 'Mutation id was used with a different command'
      )
    );
  end if;

  if v_receipt.status = 'succeeded' then
    select audit.new_values
    into v_replayed
    from public.audit_events as audit
    where audit.workspace_id = p_workspace_id
      and audit.mutation_id = p_mutation_id
      and audit.entity_type = p_entity_type;

    if v_replayed is null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'infrastructure_failure',
          'message', 'Successful mutation result is unavailable'
        )
      );
    end if;

    return jsonb_build_object('ok', true, 'entity', v_replayed);
  end if;

  return jsonb_build_object(
    'ok', false,
    'error', jsonb_build_object(
      'code', 'in_progress',
      'message', 'Mutation is already in progress'
    )
  );
end;
$$;

alter function private.claim_membership_mutation(uuid, uuid, bytea, text)
  owner to postgres;
revoke all on function private.claim_membership_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_membership_mutation(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role_key text;
begin
  select role.key
  into v_role_key
  from public.memberships as membership
  join public.roles as role
    on role.workspace_id = membership.workspace_id
    and role.id = membership.role_id
  where membership.workspace_id = p_workspace_id
    and membership.user_id = v_actor_id
    and membership.status = 'active'::public.membership_status;

  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, role_key, scope_snapshot,
    action, entity_type, entity_id, source, correlation_id, mutation_id,
    reason, old_values, new_values, created_by, updated_by
  ) values (
    p_workspace_id, 'user', v_actor_id, v_role_key,
    jsonb_build_object('workspace_id', p_workspace_id),
    p_action, p_entity_type, p_entity_id, 'rpc', p_correlation_id,
    p_mutation_id, p_reason, p_old_values, p_new_values,
    v_actor_id, v_actor_id
  );

  update public.mutation_receipts
  set
    status = 'succeeded',
    result_entity_type = p_entity_type,
    result_entity_id = p_entity_id,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id
    and mutation_id = p_mutation_id;
end;
$$;

alter function private.finish_membership_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_membership_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

-- Refuses transitions that would leave the workspace without an active member
-- holding security.manage (the workspace would become unmanageable).
create function private.would_remove_last_security_manager(
  p_workspace_id uuid,
  p_membership_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    -- The targeted membership currently is an active security.manage holder …
    select 1
    from public.memberships as target
    join public.role_permissions as target_grant
      on target_grant.workspace_id = target.workspace_id
      and target_grant.role_id = target.role_id
    join public.permissions as target_permission
      on target_permission.id = target_grant.permission_id
    where target.workspace_id = p_workspace_id
      and target.id = p_membership_id
      and target.status = 'active'::public.membership_status
      and target_permission.key = 'security.manage'
  ) and not exists (
    -- … and no other active membership in the workspace also holds it.
    select 1
    from public.memberships as other
    join public.role_permissions as other_grant
      on other_grant.workspace_id = other.workspace_id
      and other_grant.role_id = other.role_id
    join public.permissions as other_permission
      on other_permission.id = other_grant.permission_id
    where other.workspace_id = p_workspace_id
      and other.id <> p_membership_id
      and other.status = 'active'::public.membership_status
      and other_permission.key = 'security.manage'
  );
$$;

alter function private.would_remove_last_security_manager(uuid, uuid)
  owner to postgres;
revoke all on function private.would_remove_last_security_manager(uuid, uuid)
  from public, anon, authenticated;

create function private.membership_snapshot(membership public.memberships)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', membership.id,
    'workspace_id', membership.workspace_id,
    'user_id', membership.user_id,
    'role_id', membership.role_id,
    'status', membership.status,
    'created_at', membership.created_at,
    'updated_at', membership.updated_at,
    'created_by', membership.created_by,
    'updated_by', membership.updated_by,
    'version', membership.version
  );
$$;

alter function private.membership_snapshot(public.memberships)
  owner to postgres;
revoke all on function private.membership_snapshot(public.memberships)
  from public, anon, authenticated;

create function private.membership_invitation_snapshot(
  invitation public.membership_invitations
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', invitation.id,
    'workspace_id', invitation.workspace_id,
    'email', invitation.email,
    'role_id', invitation.role_id,
    'status', invitation.status,
    'accepted_membership_id', invitation.accepted_membership_id,
    'created_at', invitation.created_at,
    'updated_at', invitation.updated_at,
    'created_by', invitation.created_by,
    'updated_by', invitation.updated_by,
    'version', invitation.version
  );
$$;

alter function private.membership_invitation_snapshot(public.membership_invitations)
  owner to postgres;
revoke all on function private.membership_invitation_snapshot(public.membership_invitations)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- invite_workspace_member: admin invites an email with a role. Resolves to a
-- membership in status 'invited' when the email already has an auth user,
-- otherwise to a pending membership_invitations row.
-- -----------------------------------------------------------------------------

create function public.invite_workspace_member(
  p_workspace_id uuid,
  p_email text,
  p_role_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_email text;
  v_target_user_id uuid;
  v_request_hash bytea;
  v_claim jsonb;
  v_membership public.memberships%rowtype;
  v_invitation public.membership_invitations%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.membership_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_email is null or p_role_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Email and role are required'
      )
    );
  end if;

  v_email := lower(btrim(p_email));
  if char_length(v_email) not between 3 and 320 or position('@' in v_email) <= 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Email is invalid', 'field', 'email'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Membership management is not permitted')
    );
  end if;

  if not exists (
    select 1 from public.roles as role
    where role.workspace_id = p_workspace_id and role.id = p_role_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Role not found')
    );
  end if;

  select auth_user.id
  into v_target_user_id
  from auth.users as auth_user
  where lower(auth_user.email) = v_email
  limit 1;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'invite_workspace_member',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'email', v_email,
        'role_id', p_role_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: a successful invite creates the
  -- very membership/invitation the checks below reject, so replays must
  -- resolve from the receipt.
  v_claim := private.claim_membership_mutation(
    p_workspace_id, p_mutation_id, v_request_hash,
    case when v_target_user_id is null then 'membership_invitation' else 'membership' end
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_target_user_id is not null and exists (
    select 1 from public.memberships as membership
    where membership.workspace_id = p_workspace_id
      and membership.user_id = v_target_user_id
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The user already has a membership in this workspace'
      )
    );
  end if;

  if v_target_user_id is null and exists (
    select 1 from public.membership_invitations as invitation
    where invitation.workspace_id = p_workspace_id
      and invitation.email = v_email
      and invitation.status = 'pending'::public.membership_invitation_status
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A pending invitation for this email already exists'
      )
    );
  end if;

  if v_target_user_id is not null then
    insert into public.memberships (
      workspace_id, user_id, role_id, status, created_by, updated_by
    ) values (
      p_workspace_id, v_target_user_id, p_role_id,
      'invited'::public.membership_status, v_actor_id, v_actor_id
    )
    returning * into v_membership;

    v_new_values := private.membership_snapshot(v_membership);
    perform private.finish_membership_mutation(
      p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
      'membership.invite', 'membership', v_membership.id, null, v_new_values
    );
    return jsonb_build_object('ok', true, 'entity', v_new_values);
  end if;

  insert into public.membership_invitations (
    workspace_id, email, role_id, created_by, updated_by
  ) values (
    p_workspace_id, v_email, p_role_id, v_actor_id, v_actor_id
  )
  returning * into v_invitation;

  v_new_values := private.membership_invitation_snapshot(v_invitation);
  perform private.finish_membership_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'membership_invitation.invite', 'membership_invitation', v_invitation.id,
    null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.invite_workspace_member(uuid, text, uuid, uuid, uuid, text)
  owner to postgres;
revoke all on function public.invite_workspace_member(uuid, text, uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.invite_workspace_member(uuid, text, uuid, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- list_my_pending_invitations: self-service read for the signed-in user —
-- their 'invited' memberships and pending email invitations, with workspace
-- and role names (which their RLS could not otherwise see yet).
-- -----------------------------------------------------------------------------

create function public.list_my_pending_invitations()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(pending order by pending ->> 'created_at'),
    '[]'::jsonb
  )
  from (
    select jsonb_build_object(
      'kind', 'membership',
      'membership_id', membership.id,
      'workspace_id', workspace.id,
      'workspace_name', workspace.name,
      'role_key', role.key,
      'role_name', role.name,
      'created_at', membership.created_at,
      'version', membership.version
    ) as pending
    from public.memberships as membership
    join public.workspaces as workspace on workspace.id = membership.workspace_id
    join public.roles as role
      on role.workspace_id = membership.workspace_id
      and role.id = membership.role_id
    where membership.user_id = auth.uid()
      and membership.status = 'invited'::public.membership_status

    union all

    select jsonb_build_object(
      'kind', 'invitation',
      'invitation_id', invitation.id,
      'workspace_id', workspace.id,
      'workspace_name', workspace.name,
      'role_key', role.key,
      'role_name', role.name,
      'created_at', invitation.created_at,
      'version', invitation.version
    ) as pending
    from public.membership_invitations as invitation
    join public.workspaces as workspace on workspace.id = invitation.workspace_id
    join public.roles as role
      on role.workspace_id = invitation.workspace_id
      and role.id = invitation.role_id
    join auth.users as auth_user
      on lower(auth_user.email) = invitation.email
    where auth_user.id = auth.uid()
      and invitation.status = 'pending'::public.membership_invitation_status
  ) as pending_rows;
$$;

alter function public.list_my_pending_invitations() owner to postgres;
revoke all on function public.list_my_pending_invitations()
  from public, anon, authenticated;
grant execute on function public.list_my_pending_invitations() to authenticated;

-- -----------------------------------------------------------------------------
-- accept_workspace_invitation: the signed-in invitee activates their own
-- pending membership ('invited' -> 'active') or converts their pending email
-- invitation into an active membership.
-- -----------------------------------------------------------------------------

create function public.accept_workspace_invitation(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_email text;
  v_membership public.memberships%rowtype;
  v_invitation public.membership_invitations%rowtype;
  v_request_hash bytea;
  v_claim jsonb;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.membership_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  select lower(auth_user.email)
  into v_email
  from auth.users as auth_user
  where auth_user.id = v_actor_id;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'accept_workspace_invitation',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before any state-dependent validation: the accept itself changes
  -- the state being validated, so a replayed mutation id must resolve from
  -- the receipt, not from re-validation against the already-changed state.
  v_claim := private.claim_membership_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'membership'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select membership.*
  into v_membership
  from public.memberships as membership
  where membership.workspace_id = p_workspace_id
    and membership.user_id = v_actor_id
  for update;

  if not found then
    select invitation.*
    into v_invitation
    from public.membership_invitations as invitation
    where invitation.workspace_id = p_workspace_id
      and invitation.email = v_email
      and invitation.status = 'pending'::public.membership_invitation_status
    for update;

    if not found then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object('code', 'not_found', 'message', 'No pending invitation found')
      );
    end if;
  elsif v_membership.status <> 'invited'::public.membership_status then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The membership is not awaiting acceptance'
      )
    );
  end if;

  if v_membership.id is not null then
    v_old_values := private.membership_snapshot(v_membership);

    update public.memberships as membership
    set
      status = 'active'::public.membership_status,
      updated_at = v_now,
      updated_by = v_actor_id,
      version = membership.version + 1
    where membership.id = v_membership.id
    returning * into v_membership;
  else
    insert into public.memberships (
      workspace_id, user_id, role_id, status, created_by, updated_by
    ) values (
      p_workspace_id, v_actor_id, v_invitation.role_id,
      'active'::public.membership_status, v_invitation.created_by, v_actor_id
    )
    returning * into v_membership;

    update public.membership_invitations as invitation
    set
      status = 'accepted'::public.membership_invitation_status,
      accepted_membership_id = v_membership.id,
      updated_at = v_now,
      updated_by = v_actor_id,
      version = invitation.version + 1
    where invitation.id = v_invitation.id;

    v_old_values := null;
  end if;

  v_new_values := private.membership_snapshot(v_membership);
  perform private.finish_membership_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'membership.accept', 'membership', v_membership.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.accept_workspace_invitation(uuid, uuid, uuid, text)
  owner to postgres;
revoke all on function public.accept_workspace_invitation(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.accept_workspace_invitation(uuid, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- update_membership_status: admin transitions per STM-001. Allowed:
--   invited -> revoked (cancel), active -> suspended, suspended -> active,
--   active -> revoked, suspended -> revoked. 'revoked' is terminal;
--   'invited' -> 'active' is reserved for the invitee's accept call.
-- -----------------------------------------------------------------------------

create function public.update_membership_status(
  p_workspace_id uuid,
  p_membership_id uuid,
  p_new_status public.membership_status,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_membership public.memberships%rowtype;
  v_request_hash bytea;
  v_claim jsonb;
  v_old_values jsonb;
  v_new_values jsonb;
  v_transition_allowed boolean;
  v_action text;
  v_now timestamptz := now();
begin
  v_gate := private.membership_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_membership_id is null or p_new_status is null
     or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Membership, target status and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Membership management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_membership_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'membership_id', p_membership_id,
        'new_status', p_new_status,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the transition changes the very
  -- status being validated, so replays must resolve from the receipt.
  v_claim := private.claim_membership_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'membership'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select membership.*
  into v_membership
  from public.memberships as membership
  where membership.workspace_id = p_workspace_id
    and membership.id = p_membership_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Membership not found')
    );
  end if;

  v_transition_allowed := case
    when v_membership.status = 'invited'::public.membership_status
      then p_new_status = 'revoked'::public.membership_status
    when v_membership.status = 'active'::public.membership_status
      then p_new_status in (
        'suspended'::public.membership_status,
        'revoked'::public.membership_status
      )
    when v_membership.status = 'suspended'::public.membership_status
      then p_new_status in (
        'active'::public.membership_status,
        'revoked'::public.membership_status
      )
    else false
  end;

  if not v_transition_allowed then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'Transition %s -> %s is not allowed', v_membership.status, p_new_status
        )
      )
    );
  end if;

  if p_new_status in (
       'suspended'::public.membership_status,
       'revoked'::public.membership_status
     )
     and private.would_remove_last_security_manager(p_workspace_id, p_membership_id) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The last active security manager of a workspace cannot be suspended or revoked'
      )
    );
  end if;

  if v_membership.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Membership version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_membership.version,
        'current_entity', private.membership_snapshot(v_membership)
      )
    );
  end if;

  v_old_values := private.membership_snapshot(v_membership);

  update public.memberships as membership
  set
    status = p_new_status,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = membership.version + 1
  where membership.id = p_membership_id
  returning * into v_membership;

  v_new_values := private.membership_snapshot(v_membership);
  v_action := case p_new_status
    when 'suspended'::public.membership_status then 'membership.suspend'
    when 'revoked'::public.membership_status then 'membership.revoke'
    else 'membership.reactivate'
  end;

  perform private.finish_membership_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    v_action, 'membership', v_membership.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.update_membership_status(
  uuid, uuid, public.membership_status, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.update_membership_status(
  uuid, uuid, public.membership_status, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.update_membership_status(
  uuid, uuid, public.membership_status, bigint, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- change_membership_role: admin reassigns the member's role.
-- -----------------------------------------------------------------------------

create function public.change_membership_role(
  p_workspace_id uuid,
  p_membership_id uuid,
  p_new_role_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_membership public.memberships%rowtype;
  v_request_hash bytea;
  v_claim jsonb;
  v_old_values jsonb;
  v_new_values jsonb;
  v_new_role_grants_security_manage boolean;
  v_now timestamptz := now();
begin
  v_gate := private.membership_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_membership_id is null or p_new_role_id is null
     or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Membership, role and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Membership management is not permitted')
    );
  end if;

  if not exists (
    select 1 from public.roles as role
    where role.workspace_id = p_workspace_id and role.id = p_new_role_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Role not found')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'change_membership_role',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'membership_id', p_membership_id,
        'new_role_id', p_new_role_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the change assigns the very
  -- role the same-role check below rejects, so replays must resolve from
  -- the receipt.
  v_claim := private.claim_membership_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'membership'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select membership.*
  into v_membership
  from public.memberships as membership
  where membership.workspace_id = p_workspace_id
    and membership.id = p_membership_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Membership not found')
    );
  end if;

  if v_membership.role_id = p_new_role_id then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The membership already has this role'
      )
    );
  end if;

  select exists (
    select 1
    from public.role_permissions as role_permission
    join public.permissions as permission
      on permission.id = role_permission.permission_id
    where role_permission.workspace_id = p_workspace_id
      and role_permission.role_id = p_new_role_id
      and permission.key = 'security.manage'
  ) into v_new_role_grants_security_manage;

  if not v_new_role_grants_security_manage
     and private.would_remove_last_security_manager(p_workspace_id, p_membership_id) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The last active security manager of a workspace cannot lose the managing role'
      )
    );
  end if;

  if v_membership.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Membership version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_membership.version,
        'current_entity', private.membership_snapshot(v_membership)
      )
    );
  end if;

  v_old_values := private.membership_snapshot(v_membership);

  update public.memberships as membership
  set
    role_id = p_new_role_id,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = membership.version + 1
  where membership.id = p_membership_id
  returning * into v_membership;

  v_new_values := private.membership_snapshot(v_membership);
  perform private.finish_membership_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'membership.role_change', 'membership', v_membership.id,
    v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.change_membership_role(
  uuid, uuid, uuid, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.change_membership_role(
  uuid, uuid, uuid, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.change_membership_role(
  uuid, uuid, uuid, bigint, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- revoke_workspace_invitation: admin cancels a pending email invitation.
-- (Cancelling an 'invited' membership goes through update_membership_status.)
-- -----------------------------------------------------------------------------

create function public.revoke_workspace_invitation(
  p_workspace_id uuid,
  p_invitation_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_invitation public.membership_invitations%rowtype;
  v_request_hash bytea;
  v_claim jsonb;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.membership_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_invitation_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Invitation and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Membership management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'revoke_workspace_invitation',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'invitation_id', p_invitation_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the revoke resolves the very
  -- pending state validated below, so replays must resolve from the receipt.
  v_claim := private.claim_membership_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'membership_invitation'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select invitation.*
  into v_invitation
  from public.membership_invitations as invitation
  where invitation.workspace_id = p_workspace_id
    and invitation.id = p_invitation_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Invitation not found')
    );
  end if;

  if v_invitation.status <> 'pending'::public.membership_invitation_status then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only pending invitations can be revoked'
      )
    );
  end if;

  if v_invitation.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Invitation version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_invitation.version,
        'current_entity', private.membership_invitation_snapshot(v_invitation)
      )
    );
  end if;

  v_old_values := private.membership_invitation_snapshot(v_invitation);

  update public.membership_invitations as invitation
  set
    status = 'revoked'::public.membership_invitation_status,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = invitation.version + 1
  where invitation.id = p_invitation_id
  returning * into v_invitation;

  v_new_values := private.membership_invitation_snapshot(v_invitation);
  perform private.finish_membership_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'membership_invitation.revoke', 'membership_invitation', v_invitation.id,
    v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.revoke_workspace_invitation(
  uuid, uuid, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.revoke_workspace_invitation(
  uuid, uuid, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.revoke_workspace_invitation(
  uuid, uuid, bigint, uuid, uuid, text
) to authenticated;
