-- SECURITY-AAL-ENFORCEMENT-01
--
-- Threat model: a compromised password alone must not expose workspace
-- business data. The password is the first factor; workspace business data
-- requires a verified second factor (aal2).
--
-- DEC-016 accepted AAL2 for privileged capabilities (memberships, roles,
-- security administration) and said "the exact capability matrix may be
-- extended later". This migration performs that extension: the boundary now
-- covers the whole workspace business surface, read and write. See the
-- DEC-016 amendment in docs/architecture/phase_0/11_decision_register.md.
--
-- Where the boundary lives, and why there:
--
--   private.has_workspace_permission   -- 38 of 41 policies and 62 of 65 RPCs
--                                         reach it, so one predicate closes
--                                         the read surface and most of the
--                                         write surface at once.
--   the six unguarded *_command_gate   -- the remaining write entry points.
--                                         membership_command_gate already
--                                         carries its own check and is left
--                                         byte-for-byte alone.
--   four policies                      -- these never reach the helper: two
--                                         are OR-shaped with a self-referential
--                                         disjunct, two are purely
--                                         self-referential.
--   list_my_pending_invitations        -- the one RPC that reaches neither a
--                                         helper nor a gate.
--
-- Deliberately NOT gated (the aal1 bootstrap surface): the whole GoTrue
-- factor/challenge/verify API, which the client uses to reach aal2 in the
-- first place and which does not run through these policies at all, and
-- public.user_profiles, which answers only about the caller's own identity
-- and carries no workspace data.
--
-- private.has_scoped_entity_permission needs no change: its first conjunct is
-- has_workspace_permission, and AND short-circuits, so it inherits the
-- boundary. Adding a second check there would cost a call per row for nothing.

-- === The predicate =======================================================
--
-- SECURITY INVOKER on purpose. It reads request GUCs through auth.jwt() and
-- needs no elevated privilege, so it gets none. That also keeps it out of the
-- SR-09 inventory of privileged private helpers.
--
-- `is not distinct from` rather than `=` so a NULL claim is false rather than
-- NULL: a policy expression that evaluates to NULL denies, but a NULL that
-- flows into a larger OR expression does not. Verified fail-closed against
-- aal1, aal3, JSON null, numeric, array, object, 'AAL2', 'aal2 ', a missing
-- key, an empty GUC and a scalar claims document.

create function private.is_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select (auth.jwt() ->> 'aal') is not distinct from 'aal2';
$$;

alter function private.is_aal2() owner to postgres;
revoke all on function private.is_aal2() from public, anon, authenticated;

-- Mandatory, not optional: four policies below name this function directly and
-- are evaluated as the calling role. Without the grant those policies do not
-- deny -- they raise, and every subscription and read against those tables
-- fails.
grant execute on function private.is_aal2() to authenticated;

-- === The central permission helper =======================================
--
-- The assurance check goes first so an aal1 request never pays for the
-- membership/role/permission join. This helper is called once per candidate
-- row, so the ordering is a cost decision as much as a clarity one.

create or replace function private.has_workspace_permission(target_workspace_id uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_aal2() and exists (
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

-- === The six command gates that had no assurance check ===================
--
-- private.membership_command_gate is intentionally untouched: it already
-- enforces aal2 with its own inline check, that check is pinned by
-- 026 SR-12 and by the rollback suite, and rewriting it to call the new
-- predicate would trade a proven guard for a cosmetic one.

create or replace function private.document_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for document mutations'
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

create or replace function private.leasing_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for leasing mutations'
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

create or replace function private.maintenance_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for maintenance mutations'
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

create or replace function private.party_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for party mutations'
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

create or replace function private.platform_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for platform mutations'
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

create or replace function private.valuation_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
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

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for valuation mutations'
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

-- === The four policies that never reach the helper =======================
--
-- Two are OR-shaped: the self-referential disjunct let an aal1 caller keep
-- reading its own membership and notification rows -- including notification
-- title, body and entity references -- no matter what the helper does. The
-- assurance check is therefore hoisted out in front of the whole disjunction,
-- and the parentheses matter: AND binds tighter than OR, so `is_aal2() AND a
-- OR b` would leave b wide open. 027 asserts the aal2 cross-tenant result of
-- each rewritten policy so a mis-parenthesised hoist cannot pass unnoticed.
--
-- (select private.is_aal2()) rather than a bare call so the planner hoists it
-- into an InitPlan and evaluates it once per query instead of once per row.

drop policy memberships_select_authorized on public.memberships;
create policy memberships_select_authorized
  on public.memberships
  for select
  to authenticated
  using (
    (select private.is_aal2())
    and (
      user_id = (select auth.uid())
      or private.has_workspace_permission(workspace_id, 'security.manage')
    )
  );

drop policy notifications_select_own_or_read on public.notifications;
create policy notifications_select_own_or_read
  on public.notifications
  for select
  to authenticated
  using (
    (select private.is_aal2())
    and (
      recipient_user_id = (select auth.uid())
      or private.has_workspace_permission(workspace_id, 'notification.read')
    )
  );

-- The permission catalogue is workspace-independent, but it is read only as
-- part of the workspace bootstrap, which is an aal2 path. Gating it costs the
-- client nothing and keeps the capability vocabulary out of reach of a
-- password-only session.
drop policy permissions_select_authenticated on public.permissions;
create policy permissions_select_authenticated
  on public.permissions
  for select
  to authenticated
  using (
    (select auth.uid()) is not null
    and (select private.is_aal2())
  );

-- The entitlement broadcast carries revocation signals for the caller's own
-- session. At aal1 there is nothing left to revoke access to, so the topic
-- follows the same boundary as the data it protects.
drop policy entitlement_broadcast_receive_own on realtime.messages;
create policy entitlement_broadcast_receive_own
  on realtime.messages
  for select
  to authenticated
  using (
    extension = 'broadcast'
    and (select realtime.topic()) = ('entitlements:' || (select auth.uid())::text)
    and (select private.is_aal2())
  );

-- === H1: authorization before the existence probe ========================
--
-- private.leasing_property_in_workspace is SECURITY DEFINER and reads
-- public.properties with RLS bypassed. In these three RPCs it ran *before*
-- the permission check, so the response distinguished "this property exists
-- in that workspace" (forbidden) from "it does not" (not_found) for any
-- authenticated caller -- an existence oracle for the (workspace, property)
-- relation, across tenants.
--
-- Only the probe and the permission block are swapped. Nothing else in these
-- function bodies changes; they are reproduced verbatim from the catalogue.
--
-- The other seven callers of the probe were checked and already run the
-- permission check first, so they are not touched.

CREATE OR REPLACE FUNCTION public.capex_projects(p_workspace_id uuid, p_property_id uuid, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_projects jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id and property id are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'capex.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'CapEx projects are not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  select coalesce(jsonb_agg(private.capex_project_snapshot(project)
                            order by project.created_at desc), '[]'::jsonb)
  into v_projects
  from public.capex_projects as project
  where project.workspace_id = p_workspace_id
    and project.property_id = p_property_id
    and (p_status is null or project.status::text = p_status);

  return jsonb_build_object('ok', true, 'entity', v_projects);
end;
$function$;

CREATE OR REPLACE FUNCTION public.maintenance_tickets(p_workspace_id uuid, p_property_id uuid, p_unit_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_priority text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tickets jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id and property id are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  select coalesce(jsonb_agg(private.maintenance_ticket_snapshot(ticket)
                            order by ticket.reported_at desc), '[]'::jsonb)
  into v_tickets
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and ticket.property_id = p_property_id
    and (p_unit_id is null or ticket.unit_id = p_unit_id)
    and (p_status is null or ticket.status::text = p_status)
    and (p_priority is null or ticket.priority = p_priority);

  return jsonb_build_object('ok', true, 'entity', v_tickets);
end;
$function$;

CREATE OR REPLACE FUNCTION public.operations_signals(p_workspace_id uuid, p_property_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_signals jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id and property id are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Operations signals are not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  with raw_signals as (
    -- lease_expiry: active lease, effective end date within 180 days.
    select
      'lease_expiry'::text as signal_type,
      case
        when (lease.end_date - current_date) <= 30 then 'critical'
        when (lease.end_date - current_date) <= 90 then 'warning'
        else 'info'
      end as severity,
      format(
        'Lease %s expires in %s days.', lease.lease_name,
        (lease.end_date - current_date)
      ) as message,
      'Review renewal, notice and follow-up actions for this lease.'
        as recommended_action,
      lease.unit_id as unit_id,
      lease.id as lease_id,
      lease.tenant_party_id as tenant_party_id
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      and lease.status = 'active'::public.lease_status
      and lease.end_date is not null
      and lease.end_date >= current_date
      and (lease.end_date - current_date) <= 180

    union all

    -- vacancy_missing_since: named gap in the P2-D05 header — vacant units are
    -- not constrained to carry a vacancy_since, imported data can lack one.
    select
      'vacancy_missing_since', 'warning',
      format('Unit %s is vacant without a vacancy date.', unit.unit_code),
      'Set the vacancy start date so vacancy aging can be tracked.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is null

    union all

    -- vacancy_aged: matches the legacy 45-day threshold.
    select
      'vacancy_aged', 'warning',
      format(
        'Unit %s has been vacant for %s days.', unit.unit_code,
        (current_date - unit.vacancy_since)
      ),
      'Review marketing status, target rent and next action for this vacancy.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is not null
      and (current_date - unit.vacancy_since) >= 45

    union all

    -- offline_missing_reason: units_offline_reason_state_check only forbids a
    -- reason on a non-offline unit, it does not require one when offline.
    select
      'offline_missing_reason', 'critical',
      format('Unit %s is offline without a reason.', unit.unit_code),
      'Add the offline reason before the unit disappears from normal operations.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'offline'::public.unit_status
      and (unit.offline_reason is null or char_length(btrim(unit.offline_reason)) = 0)

    union all

    -- missing_tenant_contact: active lease with no tenant party, or a tenant
    -- party missing email or phone.
    select
      'missing_tenant_contact', 'warning',
      format('Lease %s is missing tenant email or phone.', lease.lease_name),
      'Complete tenant contact details before the next operational handoff.',
      lease.unit_id, lease.id, lease.tenant_party_id
    from public.leases as lease
    left join public.parties as party
      on party.workspace_id = lease.workspace_id and party.id = lease.tenant_party_id
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      and lease.status = 'active'::public.lease_status
      and (
        lease.tenant_party_id is null
        or coalesce(btrim(party.email), '') = ''
        or coalesce(btrim(party.phone), '') = ''
      )

    union all

    -- stale_rent_roll: property-level, no unit/lease/tenant reference.
    -- Matches the legacy ~92-day freshness window (RentRoll snapshots are
    -- roughly quarterly), now on the real as_of_date instead of a periodKey.
    select
      'stale_rent_roll', 'warning',
      'Rent roll is missing or older than the accepted freshness window.',
      'Generate a new rent roll snapshot for the current period.',
      null::uuid, null::uuid, null::uuid
    where not exists (
      select 1
      from public.rent_roll_snapshots as snapshot
      where snapshot.workspace_id = p_workspace_id
        and snapshot.property_id = p_property_id
        and snapshot.as_of_date >= current_date - 92
    )
  ),
  keyed as (
    select
      raw.*,
      raw.signal_type || ':' || coalesce(raw.unit_id::text, '-')
        || ':' || coalesce(raw.lease_id::text, '-')
        || ':' || coalesce(raw.tenant_party_id::text, '-') as signal_key
    from raw_signals as raw
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'signal_key', keyed.signal_key,
        'type', keyed.signal_type,
        'severity', keyed.severity,
        'message', keyed.message,
        'recommended_action', keyed.recommended_action,
        'property_id', p_property_id,
        'unit_id', keyed.unit_id,
        'lease_id', keyed.lease_id,
        'tenant_party_id', keyed.tenant_party_id,
        'status', coalesce(state.status, 'open'),
        'resolution_note', state.resolution_note,
        'status_version', state.version,
        'status_updated_at', state.updated_at
      )
      order by
        case keyed.severity when 'critical' then 0 when 'warning' then 1 else 2 end,
        keyed.message
    ),
    '[]'::jsonb
  )
  into v_signals
  from keyed
  left join public.operations_signal_states as state
    on state.workspace_id = p_workspace_id
    and state.property_id = p_property_id
    and state.signal_key = keyed.signal_key;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object('computed_at', now(), 'signals', v_signals)
  );
end;
$function$;

-- === The one RPC that reaches neither a helper nor a gate ================
--
-- list_my_pending_invitations authorizes purely on auth.uid() and returns
-- workspace and role names for pending invitations. Its contract is a bare
-- JSON array, not the {ok, error} envelope, so the guard returns an empty
-- array rather than an error envelope -- changing the shape would be a
-- client-visible break, and the client is out of scope for this package.
-- accept_workspace_invitation is already aal2-gated, so nothing actionable
-- is lost at aal1.

CREATE OR REPLACE FUNCTION public.list_my_pending_invitations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when private.is_aal2() then (
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
      ) as pending_rows
  ) else '[]'::jsonb end;
$function$;
