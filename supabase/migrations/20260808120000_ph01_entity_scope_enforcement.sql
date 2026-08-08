-- PH-01: entity scopes become an optional, narrowing allowlist.
--
-- Baseline decided 2026-08-08 (DEC-SEC-002, partial):
--
--   * A membership with no scope rows keeps workspace-wide access. Scopes are
--     a restriction, not a grant -- adding the first row is what narrows.
--   * Once a membership has at least one scope row, only an explicit match is
--     allowed. Everything else is denied.
--   * A scope never replaces a missing workspace permission. Both must hold.
--
-- Allowlist is `property` only. The decision also names `portfolio`, but this
-- schema has no portfolios table and no property-to-portfolio relationship --
-- the value exists solely as an unmigrated entry in
-- `document_link_entity_type`. Allowing it here would create a row that can be
-- written but can never match, silently turning a "restrict to a portfolio"
-- intent into "see nothing at all". `portfolio` is added together with the
-- table and the inheritance rule when P2-D09 ships them.
--
-- Child entities (units, leases, maintenance_tickets, capex_projects,
-- documents) deliberately get no scopes of their own; per the baseline their
-- access follows the parent property. Their RLS is untouched here -- enforcing
-- the inheritance is a separate security increment.

-- Refuse to constrain data that would not satisfy the constraint. Existing
-- rows are never deleted or rewritten to make a migration pass.
do $$
declare
  v_unsupported text;
begin
  select string_agg(distinct scope.entity_type, ', ' order by scope.entity_type)
  into v_unsupported
  from public.entity_scopes as scope
  where scope.entity_type <> 'property';

  if v_unsupported is not null then
    raise exception using
      errcode = 'check_violation',
      message = format(
        'PH-01 cannot apply the entity_scopes allowlist: unsupported entity_type values present (%s)',
        v_unsupported
      ),
      hint = 'Reclassify or remove these scope rows deliberately; this migration will not rewrite them.';
  end if;
end
$$;

alter table public.entity_scopes
add constraint entity_scopes_supported_entity_type_check
check (entity_type in ('property'));

-- Fail closed on every axis: no session, no workspace, no target, an
-- unsupported type, or no active membership all deny before any scope row is
-- consulted.
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
     or target_entity_type is null
     or target_entity_type <> 'property' then
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

  -- No scope rows at all: this membership is not restricted.
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

-- Permission AND scope. private.has_workspace_permission stays the single
-- canonical permission check; this only narrows it.
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

-- The AAL2 wrapper from P1-015 stays exactly where it is and keeps calling
-- private.update_property_core. The scope guard is added inside it rather than
-- by wrapping the wrapper: a third layer would rename nothing but make the
-- chain harder to reason about, and the AAL2 test asserts update_property_core
-- by name.
--
-- Order matters. Authentication, then AAL2, then permission-and-scope, then
-- the core. Checking the scope before delegating also stops a stored mutation
-- receipt from replaying property data to an actor whose scope was revoked
-- after the original write.
create or replace function public.update_property(
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
        'message', 'AAL2 is required for property updates'
      )
    );
  end if;

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

  return private.update_property_core(
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
