-- P2-D05a: operations_signals — server-side derivation of operational alerts
-- and data-quality signals for leasing_operations (Wave 3, Befund 1 + Befund 3
-- in 04c_wave3_leasing_operations.md).
--
-- ---------------------------------------------------------------------------
-- Why this exists (Befund 1)
-- ---------------------------------------------------------------------------
--
-- The legacy `operations_repo.dart` / `operations_data_quality_engine.dart`
-- compute alerts and data-quality issues on every read from the local SQLite
-- units/leases/tenants tables; only the human acknowledgement is persisted
-- (`operations_alert_states`, overwritten with no audit/version). Decided
-- 2026-08-04: the derivation moves fully into Postgres. The client reads
-- signals, it does not compute them. This deliberately accepts the
-- RISK-QA-001 drift risk between this SQL and the Dart engine that keeps
-- running for SQLite mode; the parity test named in Befund 1 (Dart-side,
-- `test/features/operations_signals/operations_signals_parity_test.dart`)
-- is the control for that risk, not this migration.
--
-- ---------------------------------------------------------------------------
-- Which legacy signal types survive the cloud schema, and which do not
-- ---------------------------------------------------------------------------
--
-- The legacy engine has ~17 issue/alert types. Several of them describe a
-- data state that the cloud schema (P2-D05 20260730100000, P2-D02
-- 20260722220000) already makes structurally impossible, so porting them
-- would be dead code that can never fire — named here instead of silently
-- dropped:
--
--   * missing_unit_code, missing_lease_name, missing_tenant_display_name:
--     units_code_check / leases_name_check / parties_display_name_check
--     already require a non-empty value.
--   * orphan_lease_unit, orphan_lease_tenant: leases_unit_fkey /
--     leases_tenant_party_fkey are real foreign keys with `on delete
--     restrict`; an orphan cannot exist.
--   * lease_end_before_start: leases_term_check enforces end_date >=
--     start_date at write time.
--   * deposit_below_zero: leases_deposit_check enforces >= 0.
--   * invalid_payment_day: leases_payment_day_check enforces 1..28 (cloud is
--     even stricter than the legacy 1..31).
--   * occupied_without_active_lease, vacant_with_active_lease: AGG-004 is a
--     trigger-enforced invariant here (private.assert_unit_occupancy), not a
--     read-time check — the contradiction these types describe cannot be
--     written.
--   * overlapping_leases: OPN-DOM-001 (2026-07-29) reversed the documented
--     default and made several concurrently effective leases on one unit a
--     valid state. This is no longer a defect to report.
--
-- What remains is exactly the set of things the cloud schema deliberately
-- still allows to be wrong, because constraining them would either lose
-- legacy/imported data (vacancy_since, see the P2-D05 header) or because they
-- are cross-entity facts no CHECK constraint can express (tenant contact
-- completeness, rent-roll freshness):
--
--   lease_expiry, vacancy_missing_since, vacancy_aged, offline_missing_reason,
--   missing_tenant_contact, stale_rent_roll.
--
-- ---------------------------------------------------------------------------
-- Stable keys (Befund 1, point 2)
-- ---------------------------------------------------------------------------
--
-- The legacy alert id concatenates the message text, so a wording change
-- silently orphans every acknowledgement. Here the key is
-- `signal_type || unit_id || lease_id || tenant_party_id` — content, never
-- display text — computed identically by the read function and stored as a
-- generated column on operations_signal_states so an upsert cannot drift from
-- what the read side reports.
--
-- ---------------------------------------------------------------------------
-- Why the write side reuses P2-D05's private helpers instead of new ones
-- ---------------------------------------------------------------------------
--
-- private.leasing_command_gate / private.claim_leasing_mutation /
-- private.finish_leasing_mutation (20260730100000) are already parametric on
-- entity_type and carry no unit/lease-specific assumption; this migration
-- reuses all three for entity_type 'operations_signal_state' rather than
-- duplicating the gate/claim/finish trio a fourth time. Only a snapshot
-- helper is new, because the shape being snapshotted is new.
--
-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
--
-- Signals are derived from units/leases (lease.read / lease.manage), so this
-- migration introduces no new permission key — it reads with `lease.read` and
-- writes acknowledgements with `lease.manage`, matching the rest of P2-D05.

-- -----------------------------------------------------------------------------
-- operations_signal_states: the only persisted state — the human reaction to
-- a computed signal. The signal itself is never stored.
-- -----------------------------------------------------------------------------

create table public.operations_signal_states (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  signal_type text not null,
  unit_id uuid,
  lease_id uuid,
  tenant_party_id uuid,
  -- Generated, not client-supplied: the read function computes the identical
  -- expression, so the two sides cannot drift into different keys for the
  -- same (type, entities) triple.
  signal_key text generated always as (
    signal_type || ':' || coalesce(unit_id::text, '-')
      || ':' || coalesce(lease_id::text, '-')
      || ':' || coalesce(tenant_party_id::text, '-')
  ) stored,
  status text not null default 'open',
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint operations_signal_states_workspace_id_key unique (workspace_id, id),
  constraint operations_signal_states_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint operations_signal_states_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint operations_signal_states_unit_fkey foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  constraint operations_signal_states_lease_fkey foreign key (workspace_id, lease_id)
    references public.leases (workspace_id, id) on delete restrict,
  constraint operations_signal_states_tenant_fkey foreign key (workspace_id, tenant_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint operations_signal_states_type_check check (
    signal_type in (
      'lease_expiry', 'vacancy_missing_since', 'vacancy_aged',
      'offline_missing_reason', 'missing_tenant_contact', 'stale_rent_roll'
    )
  ),
  constraint operations_signal_states_status_check check (
    status in ('open', 'dismissed', 'resolved')
  ),
  constraint operations_signal_states_note_check check (
    resolution_note is null or char_length(resolution_note) <= 4000
  ),
  -- One acknowledgement per (property, signal). Uses the generated key rather
  -- than the raw nullable columns directly, because SQL unique constraints
  -- treat NULL <> NULL: without this, every stale_rent_roll row (which has no
  -- unit/lease/tenant) would collide on nothing and duplicate freely.
  constraint operations_signal_states_key_unique
    unique (workspace_id, property_id, signal_key),
  constraint operations_signal_states_version_check check (version >= 1)
);

create index operations_signal_states_workspace_idx
  on public.operations_signal_states (workspace_id);
create index operations_signal_states_property_idx
  on public.operations_signal_states (property_id, workspace_id);
-- P1-015: every foreign key needs a leading-column supporting index. The
-- three entity references are optional (most signal types carry only one or
-- two), so each index is partial on "this reference is set" — the same shape
-- as leases_tenant_idx in P2-D05.
create index operations_signal_states_unit_idx
  on public.operations_signal_states (workspace_id, unit_id)
  where unit_id is not null;
create index operations_signal_states_lease_idx
  on public.operations_signal_states (workspace_id, lease_id)
  where lease_id is not null;
create index operations_signal_states_tenant_idx
  on public.operations_signal_states (workspace_id, tenant_party_id)
  where tenant_party_id is not null;

create trigger operations_signal_states_protected_columns
before update on public.operations_signal_states
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'signal_type', 'unit_id', 'lease_id',
  'tenant_party_id', 'created_at', 'created_by'
);

alter table public.operations_signal_states enable row level security;
alter table public.operations_signal_states force row level security;

create policy operations_signal_states_select_lease_read
on public.operations_signal_states
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.operations_signal_states from anon, authenticated;
grant select on table public.operations_signal_states to authenticated;

-- -----------------------------------------------------------------------------
-- private.operations_signal_state_snapshot: audit/version-conflict payload
-- shape, mirrors private.unit_snapshot / private.lease_snapshot.
-- -----------------------------------------------------------------------------

create function private.operations_signal_state_snapshot(
  state public.operations_signal_states
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', state.id,
    'workspace_id', state.workspace_id,
    'property_id', state.property_id,
    'signal_type', state.signal_type,
    'unit_id', state.unit_id,
    'lease_id', state.lease_id,
    'tenant_party_id', state.tenant_party_id,
    'signal_key', state.signal_key,
    'status', state.status,
    'resolution_note', state.resolution_note,
    'created_at', state.created_at,
    'updated_at', state.updated_at,
    'created_by', state.created_by,
    'updated_by', state.updated_by,
    'version', state.version
  );
$$;

alter function private.operations_signal_state_snapshot(public.operations_signal_states)
  owner to postgres;

-- -----------------------------------------------------------------------------
-- operations_signals: the read side. Computes every signal type for one
-- property and left-joins the persisted acknowledgement (default 'open' when
-- none exists yet). Enveloped {ok,...}/{ok,error:{code}} for a distinct
-- forbidden signal, matching list_workspace_members / rent_roll_live.
-- -----------------------------------------------------------------------------

create function public.operations_signals(
  p_workspace_id uuid,
  p_property_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
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
$$;

alter function public.operations_signals(uuid, uuid) owner to postgres;
revoke all on function public.operations_signals(uuid, uuid) from public, anon, authenticated;
grant execute on function public.operations_signals(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- update_operations_signal_status: the only write. Upserts the ack state,
-- versioned + audited. p_expected_version = null means "no state row exists
-- yet"; a non-null mismatch (including "row does not exist") is a
-- version_conflict, matching the update_property/transition_unit_status
-- vocabulary.
-- -----------------------------------------------------------------------------

create function public.update_operations_signal_status(
  p_workspace_id uuid,
  p_property_id uuid,
  p_signal_type text,
  p_status text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_unit_id uuid default null,
  p_lease_id uuid default null,
  p_tenant_party_id uuid default null,
  p_expected_version bigint default null,
  p_reason text default null,
  p_resolution_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_signal_key text;
  v_old public.operations_signal_states%rowtype;
  v_new public.operations_signal_states%rowtype;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null or p_signal_type is null or p_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Property id, signal type and status are required'
      )
    );
  end if;

  if p_signal_type not in (
    'lease_expiry', 'vacancy_missing_since', 'vacancy_aged',
    'offline_missing_reason', 'missing_tenant_contact', 'stale_rent_roll'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown signal type', 'field', 'signal_type'
      )
    );
  end if;

  if p_status not in ('open', 'dismissed', 'resolved') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown status', 'field', 'status'
      )
    );
  end if;

  if p_resolution_note is not null and char_length(p_resolution_note) > 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Resolution note must contain at most 4000 characters',
        'field', 'resolution_note'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Operations signal management is not permitted'
      )
    );
  end if;

  if p_unit_id is not null and not exists (
    select 1 from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_unit_id
      and unit.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found', 'field', 'unit_id')
    );
  end if;

  if p_lease_id is not null and not exists (
    select 1 from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.id = p_lease_id
      and lease.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Lease not found', 'field', 'lease_id')
    );
  end if;

  if p_tenant_party_id is not null and not exists (
    select 1 from public.parties as party
    where party.workspace_id = p_workspace_id and party.id = p_tenant_party_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Party not found', 'field', 'tenant_party_id'
      )
    );
  end if;

  v_signal_key := p_signal_type || ':' || coalesce(p_unit_id::text, '-')
    || ':' || coalesce(p_lease_id::text, '-')
    || ':' || coalesce(p_tenant_party_id::text, '-');

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_operations_signal_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'signal_key', v_signal_key,
        'expected_version', p_expected_version,
        'status', p_status,
        'resolution_note', p_resolution_note,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'operations_signal_state'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.operations_signal_states as state
  where state.workspace_id = p_workspace_id
    and state.property_id = p_property_id
    and state.signal_key = v_signal_key
  for update;

  if v_old.id is null then
    if p_expected_version is not null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'version_conflict',
          'message', 'Signal state does not exist yet',
          'expected_version', p_expected_version,
          'actual_version', null
        )
      );
    end if;

    insert into public.operations_signal_states (
      workspace_id, property_id, signal_type, unit_id, lease_id, tenant_party_id,
      status, resolution_note, created_by, updated_by
    ) values (
      p_workspace_id, p_property_id, p_signal_type, p_unit_id, p_lease_id, p_tenant_party_id,
      p_status, p_resolution_note, v_actor_id, v_actor_id
    )
    returning * into v_new;

    perform private.finish_leasing_mutation(
      p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
      'operations_signal.update_status', 'operations_signal_state', v_new.id,
      null, private.operations_signal_state_snapshot(v_new)
    );
    return jsonb_build_object('ok', true, 'entity', private.operations_signal_state_snapshot(v_new));
  end if;

  if p_expected_version is null or v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Signal state version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.operations_signal_state_snapshot(v_old)
      )
    );
  end if;

  update public.operations_signal_states as state
  set
    status = p_status,
    resolution_note = p_resolution_note,
    updated_at = now(),
    updated_by = v_actor_id,
    version = state.version + 1
  where state.workspace_id = p_workspace_id
    and state.id = v_old.id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'operations_signal.update_status', 'operations_signal_state', v_new.id,
    private.operations_signal_state_snapshot(v_old),
    private.operations_signal_state_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.operations_signal_state_snapshot(v_new));
end;
$$;

alter function public.update_operations_signal_status(
  uuid, uuid, text, text, uuid, uuid, uuid, uuid, uuid, bigint, text, text
) owner to postgres;
revoke all on function public.update_operations_signal_status(
  uuid, uuid, text, text, uuid, uuid, uuid, uuid, uuid, bigint, text, text
) from public, anon, authenticated;
grant execute on function public.update_operations_signal_status(
  uuid, uuid, text, text, uuid, uuid, uuid, uuid, uuid, bigint, text, text
) to authenticated;
