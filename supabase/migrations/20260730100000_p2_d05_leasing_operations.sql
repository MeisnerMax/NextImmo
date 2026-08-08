-- P2-D05: leasing_operations — cloud unit and lease contract (DOM-004, AGG-004,
-- AGG-006, STM-003, STM-005).
--
-- The mutation surface mirrors the P2-D03 documents_compliance vertical
-- (enveloped {ok,entity}/{ok,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events, default-deny RLS, reject_protected_column_update,
-- one shared command gate / claim / finish helper trio instead of per-RPC
-- boilerplate) and keeps the P2-D01 claim-before-state-validation rule with
-- receipt cleanup for every mutation that changes the state its own validation
-- reads. Like P2-D02, P2-D03 and P1-004 there is NO AAL2 gate: units and leases
-- are ordinary workspace business data, so access is gated by the lease.read /
-- lease.manage permissions.
--
-- Tenants are NOT a table here. AGG-005 already settled that tenant is a
-- relationship, not a separate person master, and P2-D02 shipped it:
-- party_role_type carries 'tenant', so leases.tenant_party_id references
-- public.parties and the tenant directory is the parties directory. The legacy
-- SQLite `tenants` table therefore has no cloud counterpart by design — the
-- dry-run mapper folds it into parties, it is not carried over.
--
-- ---------------------------------------------------------------------------
-- OPN-DOM-001 (decided 2026-07-29, documented default deliberately overridden)
-- ---------------------------------------------------------------------------
--
-- A unit MAY hold several concurrently effective leases (Teilflaechen-
-- Vermietung). The structural consequences are load-bearing here and are
-- implemented, not just noted:
--
--   * There is deliberately NO unique constraint — not even a partial one — on
--     "active lease per unit". Overlapping effective leases on one unit are a
--     valid state that the schema must accept. Any future index of the shape
--     `unique (workspace_id, unit_id) where status = 'active'` would be a
--     regression against a decided item, not a hardening.
--   * AGG-004 is implemented in its reworded form: `occupied` requires AT LEAST
--     ONE effective lease, `vacant` requires NONE. The pre-decision wording
--     ("verlangt einen wirksamen Mietvertrag") presumed the singular.
--   * AGG-006's closing clause in 02_domain_map.md ("konkurrierende aktive
--     Vertraege pro Einheit sind unzulaessig") is the same overridden default
--     expressed on the Lease aggregate rather than the Unit; it is reworded in
--     the same increment as this migration for consistency, and is not treated
--     as a second, still-open question.
--
-- Rent-roll aggregation per unit (each per-unit figure is a SUM over every
-- lease effective on the reporting date) is the other consequence; it lands
-- with rent_roll_snapshots in the next increment, not here.
--
-- ---------------------------------------------------------------------------
-- What "effective" means, and why it is status-based rather than date-based
-- ---------------------------------------------------------------------------
--
-- A lease is effective exactly when its STM-005 status is 'active'. The
-- tempting alternative — "start_date <= today and (end_date is null or
-- end_date >= today)" — was rejected deliberately: the AGG-004 invariant is
-- enforced by triggers, which only fire on write. A date-based predicate would
-- let a stored `occupied` become silently non-compliant at midnight when a
-- lease's end_date passed, and the violation would then surface as a failure of
-- whatever unrelated write happened to touch the row next. Status-based means
-- the invariant can only ever be broken by an explicit write that is itself
-- rejected. Date-driven expiry is a deliberate transition_lease_status call,
-- the same convention P2-D03 uses for document validity (documents carry
-- valid_until and an index for sweeps, but nothing auto-transitions them).
--
-- ---------------------------------------------------------------------------
-- STM-003's "occupied -> offline nur nach Vertrags-/Belegungspruefung"
-- ---------------------------------------------------------------------------
--
-- Read as: the transition must EXAMINE the lease situation, not that the unit
-- must be lease-free. The literal reading is unreachable — an `occupied` unit
-- by AGG-004 always has an effective lease, so a lease-free precondition would
-- make `occupied -> offline` a dead edge. The real case it exists for is a unit
-- becoming unusable while a lease still runs (fire, water damage, ordered
-- vacancy). Implemented as: `offline` is exempt from the AGG-004 occupancy
-- invariant, and transition_unit_status requires a reason for any transition
-- into `offline` plus records the effective-lease count at that moment in the
-- audit entry, so the "Pruefung" is evidenced rather than asserted. Leaving
-- `offline` recomputes the status from the leases that are effective then.
--
-- ---------------------------------------------------------------------------
-- Named gaps (stated, not improvised)
-- ---------------------------------------------------------------------------
--
--   * units.property_id references public.properties (id) only. A composite
--     (workspace_id, id) foreign key would be stronger, but public.properties
--     carries no such unique constraint and adding one is a change to an
--     existing table's structure; the RPCs therefore verify workspace
--     membership of the property explicitly before insert. This is the same gap
--     and the same resolution as P2-D07 (20260728120000, header note). Every
--     table this migration owns itself does carry (workspace_id, id), so the
--     units -> leases edge is a real composite foreign key.
--   * A lease carries at most one tenant party (leases.tenant_party_id),
--     matching the legacy single tenant_id. Co-tenancy (several jointly liable
--     parties on one lease) is a real thing this model cannot express; it is
--     not in the P2-D05 deliverable and is not silently half-built. Note that
--     this is independent of OPN-DOM-001: that decision is about several
--     LEASES per unit, which this migration does support.
--   * units.vacancy_since is auto-maintained on transitions into `vacant` but
--     is NOT constrained to be non-null for vacant units, even though
--     operations_data_quality_engine.dart flags exactly that combination. A
--     hard constraint would make legacy rows that are vacant with no vacancy
--     date unimportable without inventing a date. Cloud-native data is always
--     complete; imported data stays honest and keeps being reported by the
--     quality engine.
--   * lease_rent_schedule (periodic rent overrides, the indexation input) and
--     leasing_cases (STM-004) are not in this migration. They ship in the next
--     increment together with the rent roll that consumes them.

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

-- STM-003: vacant <-> occupied; vacant -> offline -> vacant; occupied -> offline
-- after an evidenced occupancy check (see header). vacant <-> occupied is not
-- driven by a caller — it is derived from the effective leases.
create type public.unit_status as enum (
  'vacant',
  'occupied',
  'offline'
);

-- STM-005: draft -> reviewed -> sent -> tenant_signed -> landlord_signed ->
-- active -> ended, with 'cancelled' as the abort from any non-terminal state.
create type public.lease_status as enum (
  'draft',
  'reviewed',
  'sent',
  'tenant_signed',
  'landlord_signed',
  'active',
  'ended',
  'cancelled'
);

-- -----------------------------------------------------------------------------
-- units: the rentable subdivision of a property. Carries the workflow columns
-- the legacy SQLite table already had (vacancy, marketing, renovation), because
-- they are not derivable from leases and dropping them would lose data the
-- operations screens rely on.
--
-- `area_sqm` is the honest name for what the legacy column calls `sqft`: the
-- value is rendered as m² in the existing UI (units_screen.dart, unit subtitle),
-- so the legacy name is a misnomer rather than a unit difference. The dry-run
-- mapper carries it across 1:1 with no conversion.
-- -----------------------------------------------------------------------------

create table public.units (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  unit_code text not null,
  unit_type text,
  status public.unit_status not null default 'vacant',
  floor text,
  area_sqm numeric,
  rooms numeric,
  bathrooms numeric,
  target_rent_monthly numeric,
  market_rent_monthly numeric,
  currency_code text,
  vacancy_since date,
  vacancy_reason text,
  offline_reason text,
  marketing_status text,
  renovation_status text,
  expected_ready_date date,
  next_action text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint units_workspace_id_key unique (workspace_id, id),
  constraint units_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  -- See header: composite FK is impossible against public.properties today.
  constraint units_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint units_code_unique unique (workspace_id, property_id, unit_code),
  constraint units_code_check check (
    char_length(btrim(unit_code)) between 1 and 100
    and unit_code = btrim(unit_code)
  ),
  constraint units_unit_type_check check (
    unit_type is null or char_length(btrim(unit_type)) between 1 and 100
  ),
  constraint units_floor_check check (
    floor is null or char_length(btrim(floor)) between 1 and 50
  ),
  constraint units_area_check check (
    area_sqm is null or (area_sqm > 0 and area_sqm <= 1000000 and area_sqm <> 'NaN'::numeric)
  ),
  constraint units_rooms_check check (
    rooms is null or (rooms >= 0 and rooms <= 1000 and rooms <> 'NaN'::numeric)
  ),
  constraint units_bathrooms_check check (
    bathrooms is null or (bathrooms >= 0 and bathrooms <= 1000 and bathrooms <> 'NaN'::numeric)
  ),
  constraint units_target_rent_check check (
    target_rent_monthly is null
    or (target_rent_monthly >= 0 and target_rent_monthly <> 'NaN'::numeric)
  ),
  constraint units_market_rent_check check (
    market_rent_monthly is null
    or (market_rent_monthly >= 0 and market_rent_monthly <> 'NaN'::numeric)
  ),
  -- DEC-011: a money amount never exists without its currency.
  constraint units_currency_code_check check (
    currency_code is null or currency_code ~ '^[A-Z]{3}$'
  ),
  constraint units_currency_required_check check (
    currency_code is not null
    or (target_rent_monthly is null and market_rent_monthly is null)
  ),
  constraint units_vacancy_reason_check check (
    vacancy_reason is null or char_length(vacancy_reason) <= 2000
  ),
  constraint units_offline_reason_check check (
    offline_reason is null or char_length(offline_reason) <= 2000
  ),
  -- A unit that is not offline carries no offline reason: the column describes
  -- the current state, it is not a history field.
  constraint units_offline_reason_state_check check (
    offline_reason is null or status = 'offline'
  ),
  constraint units_marketing_status_check check (
    marketing_status is null or char_length(btrim(marketing_status)) between 1 and 100
  ),
  constraint units_renovation_status_check check (
    renovation_status is null or char_length(btrim(renovation_status)) between 1 and 100
  ),
  constraint units_next_action_check check (
    next_action is null or char_length(next_action) <= 2000
  ),
  constraint units_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  constraint units_version_check check (version >= 1)
);

create index units_workspace_idx on public.units (workspace_id);
-- property_id leads so this index also covers units_property_fkey; the workspace
-- column follows, which serves the workspace-scoped "units of this property"
-- lookup equally well because both predicates are equalities (same shape and
-- reasoning as valuation_cases_property_idx in P2-D07).
create index units_property_idx on public.units (property_id, workspace_id);
create index units_status_idx on public.units (workspace_id, status);
-- Vacancy dashboards read vacant units ordered by how long they have been empty.
create index units_vacancy_since_idx
  on public.units (workspace_id, vacancy_since)
  where status = 'vacant';

create trigger units_protected_columns
before update on public.units
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'created_at', 'created_by'
);

alter table public.units enable row level security;
alter table public.units force row level security;

create policy units_select_lease_read
on public.units
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.units from anon, authenticated;
grant select on table public.units to authenticated;

-- -----------------------------------------------------------------------------
-- leases: the contract aggregate. Money is numeric + currency (DEC-011).
-- Deliberately no unique constraint tying an active lease to a unit — see the
-- OPN-DOM-001 block in the header.
-- -----------------------------------------------------------------------------

create table public.leases (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  unit_id uuid not null,
  tenant_party_id uuid,
  lease_name text not null,
  status public.lease_status not null default 'draft',
  start_date date not null,
  end_date date,
  move_in_date date,
  move_out_date date,
  signed_date date,
  notice_date date,
  renewal_option_date date,
  break_option_date date,
  base_rent_monthly numeric not null,
  ancillary_charges_monthly numeric,
  parking_other_charges_monthly numeric,
  currency_code text not null,
  security_deposit numeric,
  payment_day_of_month integer,
  billing_frequency text not null default 'monthly',
  rent_free_period_months integer,
  ended_at timestamptz,
  cancelled_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint leases_workspace_id_key unique (workspace_id, id),
  constraint leases_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint leases_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint leases_unit_fkey foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  constraint leases_tenant_party_fkey foreign key (workspace_id, tenant_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint leases_name_check check (
    char_length(btrim(lease_name)) between 1 and 200
  ),
  constraint leases_term_check check (
    end_date is null or end_date >= start_date
  ),
  constraint leases_move_out_check check (
    move_out_date is null or move_in_date is null or move_out_date >= move_in_date
  ),
  constraint leases_base_rent_check check (
    base_rent_monthly >= 0 and base_rent_monthly <> 'NaN'::numeric
  ),
  constraint leases_ancillary_check check (
    ancillary_charges_monthly is null
    or (ancillary_charges_monthly >= 0 and ancillary_charges_monthly <> 'NaN'::numeric)
  ),
  constraint leases_parking_check check (
    parking_other_charges_monthly is null
    or (parking_other_charges_monthly >= 0
        and parking_other_charges_monthly <> 'NaN'::numeric)
  ),
  constraint leases_currency_code_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint leases_deposit_check check (
    security_deposit is null
    or (security_deposit >= 0 and security_deposit <> 'NaN'::numeric)
  ),
  constraint leases_payment_day_check check (
    payment_day_of_month is null or payment_day_of_month between 1 and 28
  ),
  constraint leases_billing_frequency_check check (
    billing_frequency in ('monthly', 'quarterly', 'semiannual', 'annual')
  ),
  constraint leases_rent_free_check check (
    rent_free_period_months is null or rent_free_period_months between 0 and 120
  ),
  constraint leases_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  -- STM-005 terminal-state markers: exactly the terminal status carries its
  -- timestamp, so "is this lease over" has one answer, not two.
  constraint leases_ended_marker_check check (
    (status = 'ended') = (ended_at is not null)
  ),
  constraint leases_cancelled_marker_check check (
    (status = 'cancelled') = (cancelled_at is not null)
  ),
  constraint leases_version_check check (version >= 1)
);

create index leases_workspace_idx on public.leases (workspace_id);
-- property_id leads so this index also covers leases_property_fkey (see the
-- units_property_idx note).
create index leases_property_idx on public.leases (property_id, workspace_id);
create index leases_unit_idx on public.leases (workspace_id, unit_id);
create index leases_tenant_idx
  on public.leases (workspace_id, tenant_party_id)
  where tenant_party_id is not null;
create index leases_status_idx on public.leases (workspace_id, status);
-- The occupancy invariant and the rent roll both read the effective leases of a
-- unit. This partial index is the hot path for both; it is NOT unique, on
-- purpose (OPN-DOM-001).
create index leases_unit_effective_idx
  on public.leases (workspace_id, unit_id)
  where status = 'active';
-- Expiry / renewal sweeps read running leases by term end.
create index leases_end_date_idx
  on public.leases (workspace_id, end_date)
  where end_date is not null and status = 'active';

create trigger leases_protected_columns
before update on public.leases
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'unit_id', 'created_at', 'created_by'
);

alter table public.leases enable row level security;
alter table public.leases force row level security;

create policy leases_select_lease_read
on public.leases
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.leases from anon, authenticated;
grant select on table public.leases to authenticated;

-- -----------------------------------------------------------------------------
-- AGG-004 occupancy invariant (OPN-DOM-001 wording)
--
-- Enforced by triggers on BOTH tables rather than only inside the RPCs, so the
-- invariant holds against direct SQL, a future RPC that forgets, and a data
-- import. The RPCs still validate up front and return a proper envelope; these
-- triggers are the backstop that makes AGG-004 structural.
-- -----------------------------------------------------------------------------

create function private.lease_status_is_effective(lease_status public.lease_status)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lease_status = 'active'::public.lease_status;
$$;

alter function private.lease_status_is_effective(public.lease_status) owner to postgres;

create function private.unit_effective_lease_count(
  p_workspace_id uuid,
  p_unit_id uuid
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.unit_id = p_unit_id
    and private.lease_status_is_effective(lease.status);
$$;

alter function private.unit_effective_lease_count(uuid, uuid) owner to postgres;
revoke all on function private.unit_effective_lease_count(uuid, uuid)
  from public, anon, authenticated;

-- Raises when a unit's stored status contradicts its effective leases.
-- 'offline' is exempt by design — see the STM-003 block in the header.
create function private.assert_unit_occupancy(
  p_workspace_id uuid,
  p_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.unit_status;
  v_count integer;
begin
  select unit.status
  into v_status
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id;

  if v_status is null or v_status = 'offline'::public.unit_status then
    return;
  end if;

  v_count := private.unit_effective_lease_count(p_workspace_id, p_unit_id);

  if v_status = 'occupied'::public.unit_status and v_count = 0 then
    raise exception
      'AGG-004: unit % is occupied without any effective lease', p_unit_id
      using errcode = '23514';
  end if;

  if v_status = 'vacant'::public.unit_status and v_count > 0 then
    raise exception
      'AGG-004: unit % is vacant but has % effective lease(s)', p_unit_id, v_count
      using errcode = '23514';
  end if;
end;
$$;

alter function private.assert_unit_occupancy(uuid, uuid) owner to postgres;
revoke all on function private.assert_unit_occupancy(uuid, uuid)
  from public, anon, authenticated;

create function private.units_assert_occupancy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_unit_occupancy(new.workspace_id, new.id);
  return null;
end;
$$;

alter function private.units_assert_occupancy() owner to postgres;

create function private.leases_assert_occupancy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_unit_occupancy(new.workspace_id, new.unit_id);
  return null;
end;
$$;

alter function private.leases_assert_occupancy() owner to postgres;

-- Deferrable so that a single transaction may activate a lease and flip the
-- unit to occupied in either order without tripping over itself.
create constraint trigger units_occupancy_invariant
after insert or update of status on public.units
deferrable initially deferred
for each row execute function private.units_assert_occupancy();

create constraint trigger leases_occupancy_invariant
after insert or update of status on public.leases
deferrable initially deferred
for each row execute function private.leases_assert_occupancy();

-- Recomputes vacant/occupied from the effective leases. Never touches an
-- offline unit: offline is a deliberate operational state that outranks the
-- derived occupancy, and clobbering it here would silently undo an operator's
-- decision the next time any lease of that unit changed.
create function private.sync_unit_occupancy(
  p_workspace_id uuid,
  p_unit_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit public.units%rowtype;
  v_target public.unit_status;
begin
  select *
  into v_unit
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id
  for update;

  if v_unit.id is null or v_unit.status = 'offline'::public.unit_status then
    return;
  end if;

  v_target := case
    when private.unit_effective_lease_count(p_workspace_id, p_unit_id) > 0
      then 'occupied'::public.unit_status
    else 'vacant'::public.unit_status
  end;

  if v_target = v_unit.status then
    return;
  end if;

  update public.units
  set
    status = v_target,
    vacancy_since = case
      when v_target = 'vacant'::public.unit_status then coalesce(vacancy_since, current_date)
      else null
    end,
    vacancy_reason = case
      when v_target = 'vacant'::public.unit_status then vacancy_reason
      else null
    end,
    updated_at = now(),
    updated_by = p_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id
    and id = p_unit_id;
end;
$$;

alter function private.sync_unit_occupancy(uuid, uuid, uuid) owner to postgres;
revoke all on function private.sync_unit_occupancy(uuid, uuid, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Shared command plumbing: gate, idempotency claim, audit + receipt finish, and
-- row snapshots — one implementation for all leasing mutation RPCs
-- (P2-D01/P2-D02/P2-D03 shape).
-- -----------------------------------------------------------------------------

create function private.leasing_command_gate(
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

alter function private.leasing_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.leasing_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function private.claim_leasing_mutation(
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

alter function private.claim_leasing_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_leasing_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_leasing_mutation(
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

alter function private.finish_leasing_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_leasing_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

create function private.unit_snapshot(unit public.units)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', unit.id,
    'workspace_id', unit.workspace_id,
    'property_id', unit.property_id,
    'unit_code', unit.unit_code,
    'unit_type', unit.unit_type,
    'status', unit.status,
    'floor', unit.floor,
    'area_sqm', unit.area_sqm,
    'rooms', unit.rooms,
    'bathrooms', unit.bathrooms,
    'target_rent_monthly', unit.target_rent_monthly,
    'market_rent_monthly', unit.market_rent_monthly,
    'currency_code', unit.currency_code,
    'vacancy_since', unit.vacancy_since,
    'vacancy_reason', unit.vacancy_reason,
    'offline_reason', unit.offline_reason,
    'marketing_status', unit.marketing_status,
    'renovation_status', unit.renovation_status,
    'expected_ready_date', unit.expected_ready_date,
    'next_action', unit.next_action,
    'notes', unit.notes,
    'created_at', unit.created_at,
    'updated_at', unit.updated_at,
    'created_by', unit.created_by,
    'updated_by', unit.updated_by,
    'version', unit.version
  );
$$;

alter function private.unit_snapshot(public.units) owner to postgres;

create function private.lease_snapshot(lease public.leases)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', lease.id,
    'workspace_id', lease.workspace_id,
    'property_id', lease.property_id,
    'unit_id', lease.unit_id,
    'tenant_party_id', lease.tenant_party_id,
    'lease_name', lease.lease_name,
    'status', lease.status,
    'start_date', lease.start_date,
    'end_date', lease.end_date,
    'move_in_date', lease.move_in_date,
    'move_out_date', lease.move_out_date,
    'signed_date', lease.signed_date,
    'notice_date', lease.notice_date,
    'renewal_option_date', lease.renewal_option_date,
    'break_option_date', lease.break_option_date,
    'base_rent_monthly', lease.base_rent_monthly,
    'ancillary_charges_monthly', lease.ancillary_charges_monthly,
    'parking_other_charges_monthly', lease.parking_other_charges_monthly,
    'currency_code', lease.currency_code,
    'security_deposit', lease.security_deposit,
    'payment_day_of_month', lease.payment_day_of_month,
    'billing_frequency', lease.billing_frequency,
    'rent_free_period_months', lease.rent_free_period_months,
    'ended_at', lease.ended_at,
    'cancelled_at', lease.cancelled_at,
    'notes', lease.notes,
    'created_at', lease.created_at,
    'updated_at', lease.updated_at,
    'created_by', lease.created_by,
    'updated_by', lease.updated_by,
    'version', lease.version
  );
$$;

alter function private.lease_snapshot(public.leases) owner to postgres;

-- Verifies that a property id belongs to the workspace. Needed because
-- units/leases cannot carry a composite foreign key to public.properties (see
-- header) — this is the explicit check that stands in for it.
create function private.leasing_property_in_workspace(
  p_workspace_id uuid,
  p_property_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.properties as property
    where property.id = p_property_id
      and property.workspace_id = p_workspace_id
      and property.deleted_at is null
  );
$$;

alter function private.leasing_property_in_workspace(uuid, uuid) owner to postgres;
revoke all on function private.leasing_property_in_workspace(uuid, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_unit
-- -----------------------------------------------------------------------------

create function public.create_unit(
  p_workspace_id uuid,
  p_property_id uuid,
  p_unit_code text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_unit_type text default null,
  p_floor text default null,
  p_area_sqm numeric default null,
  p_rooms numeric default null,
  p_bathrooms numeric default null,
  p_target_rent_monthly numeric default null,
  p_market_rent_monthly numeric default null,
  p_currency_code text default null,
  p_marketing_status text default null,
  p_renovation_status text default null,
  p_expected_ready_date date default null,
  p_next_action text default null,
  p_notes text default null,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_unit public.units%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Property is required',
        'field', 'property_id'
      )
    );
  end if;

  if p_unit_code is null
     or char_length(btrim(p_unit_code)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unit code is required',
        'field', 'unit_code'
      )
    );
  end if;

  if p_area_sqm is not null and (p_area_sqm <= 0 or p_area_sqm > 1000000) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Area must be a positive value',
        'field', 'area_sqm'
      )
    );
  end if;

  if (p_target_rent_monthly is not null or p_market_rent_monthly is not null)
     and p_currency_code is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A rent amount requires a currency',
        'field', 'currency_code'
      )
    );
  end if;

  if p_currency_code is not null and p_currency_code !~ '^[A-Z]{3}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Currency must be a three-letter ISO code',
        'field', 'currency_code'
      )
    );
  end if;

  if coalesce(p_target_rent_monthly, 0) < 0 or coalesce(p_market_rent_monthly, 0) < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Rent must not be negative',
        'field', 'target_rent_monthly'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Unit management is not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_unit',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'unit_code', btrim(p_unit_code),
        'unit_type', p_unit_type,
        'floor', p_floor,
        'area_sqm', p_area_sqm,
        'rooms', p_rooms,
        'bathrooms', p_bathrooms,
        'target_rent_monthly', p_target_rent_monthly,
        'market_rent_monthly', p_market_rent_monthly,
        'currency_code', p_currency_code,
        'marketing_status', p_marketing_status,
        'renovation_status', p_renovation_status,
        'expected_ready_date', p_expected_ready_date,
        'next_action', p_next_action,
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'unit'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if exists (
    select 1 from public.units as existing
    where existing.workspace_id = p_workspace_id
      and existing.property_id = p_property_id
      and existing.unit_code = btrim(p_unit_code)
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A unit with this code already exists for the property',
        'field', 'unit_code'
      )
    );
  end if;

  -- A new unit starts vacant with today as the vacancy start: it has no lease
  -- yet, and AGG-004 would reject any other initial status.
  insert into public.units (
    workspace_id, property_id, unit_code, unit_type, status, floor, area_sqm,
    rooms, bathrooms, target_rent_monthly, market_rent_monthly, currency_code,
    vacancy_since, marketing_status, renovation_status, expected_ready_date,
    next_action, notes, created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, btrim(p_unit_code),
    nullif(btrim(coalesce(p_unit_type, '')), ''), 'vacant',
    nullif(btrim(coalesce(p_floor, '')), ''), p_area_sqm, p_rooms, p_bathrooms,
    p_target_rent_monthly, p_market_rent_monthly, p_currency_code,
    current_date,
    nullif(btrim(coalesce(p_marketing_status, '')), ''),
    nullif(btrim(coalesce(p_renovation_status, '')), ''),
    p_expected_ready_date, nullif(p_next_action, ''), nullif(p_notes, ''),
    v_actor_id, v_actor_id
  )
  returning * into v_unit;

  v_new_values := private.unit_snapshot(v_unit);

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'unit.create', 'unit', v_unit.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_unit(
  uuid, uuid, text, uuid, uuid, text, text, numeric, numeric, numeric,
  numeric, numeric, text, text, text, date, text, text, text
) owner to postgres;
revoke all on function public.create_unit(
  uuid, uuid, text, uuid, uuid, text, text, numeric, numeric, numeric,
  numeric, numeric, text, text, text, date, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_unit(
  uuid, uuid, text, uuid, uuid, text, text, numeric, numeric, numeric,
  numeric, numeric, text, text, text, date, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_unit: attribute changes only. Status is NOT settable here — occupancy
-- is derived from leases and `offline` goes through transition_unit_status,
-- which is the surface that demands and audits a reason.
-- -----------------------------------------------------------------------------

create function public.update_unit(
  p_workspace_id uuid,
  p_unit_id uuid,
  p_expected_version bigint,
  p_changes jsonb,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_old public.units%rowtype;
  v_new public.units%rowtype;
  v_unknown_keys text[];
  v_code text;
  v_target_rent numeric;
  v_market_rent numeric;
  v_currency text;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_unit_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unit id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object' or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'No changes supplied', 'field', 'changes'
      )
    );
  end if;

  select array_agg(change_key)
  into v_unknown_keys
  from jsonb_object_keys(p_changes) as change_key
  where change_key not in (
    'unit_code', 'unit_type', 'floor', 'area_sqm', 'rooms', 'bathrooms',
    'target_rent_monthly', 'market_rent_monthly', 'currency_code',
    'vacancy_reason', 'marketing_status', 'renovation_status',
    'expected_ready_date', 'next_action', 'notes'
  );

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unsupported change keys: ' || array_to_string(v_unknown_keys, ', '),
        'field', 'changes'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Unit management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_unit',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'unit_id', p_unit_id,
        'expected_version', p_expected_version,
        'changes', p_changes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'unit'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Unit version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.unit_snapshot(v_old)
      )
    );
  end if;

  v_code := case
    when p_changes ? 'unit_code' then btrim(coalesce(p_changes ->> 'unit_code', ''))
    else v_old.unit_code
  end;

  if char_length(v_code) not between 1 and 100 then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unit code is required',
        'field', 'unit_code'
      )
    );
  end if;

  if v_code <> v_old.unit_code and exists (
    select 1 from public.units as existing
    where existing.workspace_id = p_workspace_id
      and existing.property_id = v_old.property_id
      and existing.unit_code = v_code
      and existing.id <> p_unit_id
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A unit with this code already exists for the property',
        'field', 'unit_code'
      )
    );
  end if;

  v_target_rent := case
    when p_changes ? 'target_rent_monthly'
      then (p_changes ->> 'target_rent_monthly')::numeric
    else v_old.target_rent_monthly
  end;
  v_market_rent := case
    when p_changes ? 'market_rent_monthly'
      then (p_changes ->> 'market_rent_monthly')::numeric
    else v_old.market_rent_monthly
  end;
  v_currency := case
    when p_changes ? 'currency_code' then nullif(btrim(coalesce(p_changes ->> 'currency_code', '')), '')
    else v_old.currency_code
  end;

  if (v_target_rent is not null or v_market_rent is not null) and v_currency is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A rent amount requires a currency',
        'field', 'currency_code'
      )
    );
  end if;

  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Currency must be a three-letter ISO code',
        'field', 'currency_code'
      )
    );
  end if;

  if coalesce(v_target_rent, 0) < 0 or coalesce(v_market_rent, 0) < 0 then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Rent must not be negative',
        'field', 'target_rent_monthly'
      )
    );
  end if;

  if (case when p_changes ? 'area_sqm' then (p_changes ->> 'area_sqm')::numeric
           else v_old.area_sqm end) is not null
     and (case when p_changes ? 'area_sqm' then (p_changes ->> 'area_sqm')::numeric
               else v_old.area_sqm end) <= 0 then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Area must be a positive value',
        'field', 'area_sqm'
      )
    );
  end if;

  update public.units as unit
  set
    unit_code = v_code,
    unit_type = case
      when p_changes ? 'unit_type'
        then nullif(btrim(coalesce(p_changes ->> 'unit_type', '')), '')
      else unit.unit_type
    end,
    floor = case
      when p_changes ? 'floor' then nullif(btrim(coalesce(p_changes ->> 'floor', '')), '')
      else unit.floor
    end,
    area_sqm = case
      when p_changes ? 'area_sqm' then (p_changes ->> 'area_sqm')::numeric
      else unit.area_sqm
    end,
    rooms = case
      when p_changes ? 'rooms' then (p_changes ->> 'rooms')::numeric
      else unit.rooms
    end,
    bathrooms = case
      when p_changes ? 'bathrooms' then (p_changes ->> 'bathrooms')::numeric
      else unit.bathrooms
    end,
    target_rent_monthly = v_target_rent,
    market_rent_monthly = v_market_rent,
    currency_code = v_currency,
    vacancy_reason = case
      when p_changes ? 'vacancy_reason'
        then nullif(btrim(coalesce(p_changes ->> 'vacancy_reason', '')), '')
      else unit.vacancy_reason
    end,
    marketing_status = case
      when p_changes ? 'marketing_status'
        then nullif(btrim(coalesce(p_changes ->> 'marketing_status', '')), '')
      else unit.marketing_status
    end,
    renovation_status = case
      when p_changes ? 'renovation_status'
        then nullif(btrim(coalesce(p_changes ->> 'renovation_status', '')), '')
      else unit.renovation_status
    end,
    expected_ready_date = case
      when p_changes ? 'expected_ready_date'
        then nullif(p_changes ->> 'expected_ready_date', '')::date
      else unit.expected_ready_date
    end,
    next_action = case
      when p_changes ? 'next_action' then nullif(p_changes ->> 'next_action', '')
      else unit.next_action
    end,
    notes = case
      when p_changes ? 'notes' then nullif(p_changes ->> 'notes', '')
      else unit.notes
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = unit.version + 1
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'unit.update', 'unit', p_unit_id,
    private.unit_snapshot(v_old), private.unit_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.unit_snapshot(v_new));
end;
$$;

alter function public.update_unit(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  owner to postgres;
revoke all on function public.update_unit(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.update_unit(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- transition_unit_status: the ONLY caller-facing status surface for units, and
-- it only ever moves a unit into or out of `offline` (STM-003's manual edges).
-- vacant <-> occupied is derived from leases and therefore not offered here —
-- offering it would invite a caller to set a status the AGG-004 trigger would
-- then reject, which is a worse API than not having it.
-- -----------------------------------------------------------------------------

create function public.transition_unit_status(
  p_workspace_id uuid,
  p_unit_id uuid,
  p_expected_version bigint,
  p_target_status public.unit_status,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_old public.units%rowtype;
  v_new public.units%rowtype;
  v_effective_leases integer;
  v_resolved public.unit_status;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_unit_id is null or p_expected_version is null or p_target_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unit id, expected version and target status are required'
      )
    );
  end if;

  -- Moving INTO offline is an operational decision that must be justified:
  -- STM-003 demands an occupancy check, and a recorded reason plus the audited
  -- effective-lease count is what makes that check evidenced instead of implied.
  if p_target_status = 'offline'::public.unit_status
     and (p_reason is null or char_length(btrim(p_reason)) = 0) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Taking a unit offline requires a reason',
        'field', 'reason'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Unit management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_unit_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'unit_id', p_unit_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'unit'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Unit version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.unit_snapshot(v_old)
      )
    );
  end if;

  v_effective_leases := private.unit_effective_lease_count(p_workspace_id, p_unit_id);

  -- STM-003 permits exactly two manual edges: into offline from anywhere, and
  -- back out of offline. Everything else is derived.
  if p_target_status = 'offline'::public.unit_status then
    if v_old.status = 'offline'::public.unit_status then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Unit is already offline',
          'field', 'target_status'
        )
      );
    end if;
    v_resolved := 'offline'::public.unit_status;
  else
    if v_old.status <> 'offline'::public.unit_status then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Occupancy is derived from leases; only the offline state is set directly',
          'field', 'target_status'
        )
      );
    end if;

    -- Returning from offline: the truth is whatever the leases say now, so an
    -- explicit 'occupied'/'vacant' request is honoured only if it matches.
    v_resolved := case
      when v_effective_leases > 0 then 'occupied'::public.unit_status
      else 'vacant'::public.unit_status
    end;

    if p_target_status <> v_resolved then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Requested status contradicts the effective leases of the unit',
          'field', 'target_status',
          'effective_lease_count', v_effective_leases,
          'derived_status', v_resolved
        )
      );
    end if;
  end if;

  update public.units as unit
  set
    status = v_resolved,
    offline_reason = case
      when v_resolved = 'offline'::public.unit_status then btrim(p_reason)
      else null
    end,
    vacancy_since = case
      when v_resolved = 'vacant'::public.unit_status then coalesce(unit.vacancy_since, current_date)
      when v_resolved = 'occupied'::public.unit_status then null
      else unit.vacancy_since
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = unit.version + 1
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'unit.transition_status', 'unit', p_unit_id,
    private.unit_snapshot(v_old),
    private.unit_snapshot(v_new)
      || jsonb_build_object('effective_lease_count_at_transition', v_effective_leases)
  );
  return jsonb_build_object('ok', true, 'entity', private.unit_snapshot(v_new));
end;
$$;

alter function public.transition_unit_status(
  uuid, uuid, bigint, public.unit_status, uuid, uuid, text
) owner to postgres;
revoke all on function public.transition_unit_status(
  uuid, uuid, bigint, public.unit_status, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.transition_unit_status(
  uuid, uuid, bigint, public.unit_status, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- create_lease: always starts in 'draft'. Activation is a separate, audited
-- transition, because that is the write that changes occupancy.
-- -----------------------------------------------------------------------------

create function public.create_lease(
  p_workspace_id uuid,
  p_unit_id uuid,
  p_lease_name text,
  p_start_date date,
  p_base_rent_monthly numeric,
  p_currency_code text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_tenant_party_id uuid default null,
  p_end_date date default null,
  p_move_in_date date default null,
  p_signed_date date default null,
  p_ancillary_charges_monthly numeric default null,
  p_parking_other_charges_monthly numeric default null,
  p_security_deposit numeric default null,
  p_payment_day_of_month integer default null,
  p_billing_frequency text default 'monthly',
  p_rent_free_period_months integer default null,
  p_notes text default null,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_unit public.units%rowtype;
  v_lease public.leases%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_unit_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unit is required', 'field', 'unit_id'
      )
    );
  end if;

  if p_lease_name is null
     or char_length(btrim(p_lease_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Lease name is required',
        'field', 'lease_name'
      )
    );
  end if;

  if p_start_date is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Start date is required',
        'field', 'start_date'
      )
    );
  end if;

  if p_end_date is not null and p_end_date < p_start_date then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'End date must not precede start date',
        'field', 'end_date'
      )
    );
  end if;

  if p_base_rent_monthly is null or p_base_rent_monthly < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Base rent must not be negative',
        'field', 'base_rent_monthly'
      )
    );
  end if;

  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Currency must be a three-letter ISO code',
        'field', 'currency_code'
      )
    );
  end if;

  if p_payment_day_of_month is not null
     and p_payment_day_of_month not between 1 and 28 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Payment day must be between 1 and 28',
        'field', 'payment_day_of_month'
      )
    );
  end if;

  if coalesce(p_billing_frequency, 'monthly')
     not in ('monthly', 'quarterly', 'semiannual', 'annual') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported billing frequency',
        'field', 'billing_frequency'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Lease management is not permitted'
      )
    );
  end if;

  select *
  into v_unit
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = p_unit_id;

  if v_unit.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found')
    );
  end if;

  -- The tenant is a Party role (AGG-005 / P2-D02), so a lease may only name a
  -- party that actually carries the tenant role. A live directory entry that is
  -- merged away is not a valid tenant either.
  if p_tenant_party_id is not null then
    if not exists (
      select 1 from public.parties as party
      where party.workspace_id = p_workspace_id
        and party.id = p_tenant_party_id
        and party.deleted_at is null
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object('code', 'not_found', 'message', 'Tenant party not found')
      );
    end if;

    if not exists (
      select 1 from public.party_roles as party_role
      where party_role.workspace_id = p_workspace_id
        and party_role.party_id = p_tenant_party_id
        and party_role.role_type = 'tenant'::public.party_role_type
        and party_role.valid_until is null
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', 'The party does not hold an open tenant role',
          'field', 'tenant_party_id'
        )
      );
    end if;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_lease',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'unit_id', p_unit_id,
        'lease_name', btrim(p_lease_name),
        'start_date', p_start_date,
        'end_date', p_end_date,
        'move_in_date', p_move_in_date,
        'signed_date', p_signed_date,
        'base_rent_monthly', p_base_rent_monthly,
        'ancillary_charges_monthly', p_ancillary_charges_monthly,
        'parking_other_charges_monthly', p_parking_other_charges_monthly,
        'currency_code', p_currency_code,
        'security_deposit', p_security_deposit,
        'payment_day_of_month', p_payment_day_of_month,
        'billing_frequency', coalesce(p_billing_frequency, 'monthly'),
        'rent_free_period_months', p_rent_free_period_months,
        'tenant_party_id', p_tenant_party_id,
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'lease'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.leases (
    workspace_id, property_id, unit_id, tenant_party_id, lease_name, status,
    start_date, end_date, move_in_date, signed_date, base_rent_monthly,
    ancillary_charges_monthly, parking_other_charges_monthly, currency_code,
    security_deposit, payment_day_of_month, billing_frequency,
    rent_free_period_months, notes, created_by, updated_by
  ) values (
    p_workspace_id, v_unit.property_id, p_unit_id, p_tenant_party_id,
    btrim(p_lease_name), 'draft', p_start_date, p_end_date, p_move_in_date,
    p_signed_date, p_base_rent_monthly, p_ancillary_charges_monthly,
    p_parking_other_charges_monthly, p_currency_code, p_security_deposit,
    p_payment_day_of_month, coalesce(p_billing_frequency, 'monthly'),
    p_rent_free_period_months, nullif(p_notes, ''), v_actor_id, v_actor_id
  )
  returning * into v_lease;

  v_new_values := private.lease_snapshot(v_lease);

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'lease.create', 'lease', v_lease.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_lease(
  uuid, uuid, text, date, numeric, text, uuid, uuid, uuid, date, date, date,
  numeric, numeric, numeric, integer, text, integer, text, text
) owner to postgres;
revoke all on function public.create_lease(
  uuid, uuid, text, date, numeric, text, uuid, uuid, uuid, date, date, date,
  numeric, numeric, numeric, integer, text, integer, text, text
) from public, anon, authenticated;
grant execute on function public.create_lease(
  uuid, uuid, text, date, numeric, text, uuid, uuid, uuid, date, date, date,
  numeric, numeric, numeric, integer, text, integer, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_lease: attribute changes only, and only while the lease has not yet
-- become binding. Once a lease is active or terminal, its commercial terms are
-- not editable in place — a change of terms is a new lease (or, later, an
-- indexation entry in lease_rent_schedule). Status changes go through
-- transition_lease_status.
-- -----------------------------------------------------------------------------

create function public.update_lease(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_expected_version bigint,
  p_changes jsonb,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_old public.leases%rowtype;
  v_new public.leases%rowtype;
  v_unknown_keys text[];
  v_start date;
  v_end date;
  v_tenant uuid;
  v_editable_states public.lease_status[] := array[
    'draft'::public.lease_status,
    'reviewed'::public.lease_status,
    'sent'::public.lease_status
  ];
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_lease_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Lease id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object' or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'No changes supplied', 'field', 'changes'
      )
    );
  end if;

  select array_agg(change_key)
  into v_unknown_keys
  from jsonb_object_keys(p_changes) as change_key
  where change_key not in (
    'lease_name', 'tenant_party_id', 'start_date', 'end_date', 'move_in_date',
    'signed_date', 'notice_date', 'renewal_option_date', 'break_option_date',
    'base_rent_monthly', 'ancillary_charges_monthly',
    'parking_other_charges_monthly', 'security_deposit',
    'payment_day_of_month', 'billing_frequency', 'rent_free_period_months',
    'notes'
  );

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unsupported change keys: ' || array_to_string(v_unknown_keys, ', '),
        'field', 'changes'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Lease management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_lease',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'lease_id', p_lease_id,
        'expected_version', p_expected_version,
        'changes', p_changes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'lease'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.id = p_lease_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Lease not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Lease version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.lease_snapshot(v_old)
      )
    );
  end if;

  if not (v_old.status = any (v_editable_states)) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'A lease past the sent stage is no longer editable in place',
        'field', 'status',
        'current_status', v_old.status
      )
    );
  end if;

  v_start := case
    when p_changes ? 'start_date' then (p_changes ->> 'start_date')::date
    else v_old.start_date
  end;
  v_end := case
    when p_changes ? 'end_date' then nullif(p_changes ->> 'end_date', '')::date
    else v_old.end_date
  end;

  if v_start is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Start date is required',
        'field', 'start_date'
      )
    );
  end if;

  if v_end is not null and v_end < v_start then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'End date must not precede start date',
        'field', 'end_date'
      )
    );
  end if;

  if (case when p_changes ? 'base_rent_monthly'
           then (p_changes ->> 'base_rent_monthly')::numeric
           else v_old.base_rent_monthly end) < 0 then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Base rent must not be negative',
        'field', 'base_rent_monthly'
      )
    );
  end if;

  v_tenant := case
    when p_changes ? 'tenant_party_id'
      then nullif(p_changes ->> 'tenant_party_id', '')::uuid
    else v_old.tenant_party_id
  end;

  if v_tenant is not null and v_tenant is distinct from v_old.tenant_party_id then
    if not exists (
      select 1 from public.parties as party
      where party.workspace_id = p_workspace_id
        and party.id = v_tenant
        and party.deleted_at is null
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object('code', 'not_found', 'message', 'Tenant party not found')
      );
    end if;

    if not exists (
      select 1 from public.party_roles as party_role
      where party_role.workspace_id = p_workspace_id
        and party_role.party_id = v_tenant
        and party_role.role_type = 'tenant'::public.party_role_type
        and party_role.valid_until is null
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', 'The party does not hold an open tenant role',
          'field', 'tenant_party_id'
        )
      );
    end if;
  end if;

  if (case when p_changes ? 'billing_frequency'
           then coalesce(p_changes ->> 'billing_frequency', '')
           else v_old.billing_frequency end)
     not in ('monthly', 'quarterly', 'semiannual', 'annual') then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported billing frequency',
        'field', 'billing_frequency'
      )
    );
  end if;

  update public.leases as lease
  set
    lease_name = case
      when p_changes ? 'lease_name' then btrim(coalesce(p_changes ->> 'lease_name', ''))
      else lease.lease_name
    end,
    tenant_party_id = v_tenant,
    start_date = v_start,
    end_date = v_end,
    move_in_date = case
      when p_changes ? 'move_in_date' then nullif(p_changes ->> 'move_in_date', '')::date
      else lease.move_in_date
    end,
    signed_date = case
      when p_changes ? 'signed_date' then nullif(p_changes ->> 'signed_date', '')::date
      else lease.signed_date
    end,
    notice_date = case
      when p_changes ? 'notice_date' then nullif(p_changes ->> 'notice_date', '')::date
      else lease.notice_date
    end,
    renewal_option_date = case
      when p_changes ? 'renewal_option_date'
        then nullif(p_changes ->> 'renewal_option_date', '')::date
      else lease.renewal_option_date
    end,
    break_option_date = case
      when p_changes ? 'break_option_date'
        then nullif(p_changes ->> 'break_option_date', '')::date
      else lease.break_option_date
    end,
    base_rent_monthly = case
      when p_changes ? 'base_rent_monthly' then (p_changes ->> 'base_rent_monthly')::numeric
      else lease.base_rent_monthly
    end,
    ancillary_charges_monthly = case
      when p_changes ? 'ancillary_charges_monthly'
        then nullif(p_changes ->> 'ancillary_charges_monthly', '')::numeric
      else lease.ancillary_charges_monthly
    end,
    parking_other_charges_monthly = case
      when p_changes ? 'parking_other_charges_monthly'
        then nullif(p_changes ->> 'parking_other_charges_monthly', '')::numeric
      else lease.parking_other_charges_monthly
    end,
    security_deposit = case
      when p_changes ? 'security_deposit'
        then nullif(p_changes ->> 'security_deposit', '')::numeric
      else lease.security_deposit
    end,
    payment_day_of_month = case
      when p_changes ? 'payment_day_of_month'
        then nullif(p_changes ->> 'payment_day_of_month', '')::integer
      else lease.payment_day_of_month
    end,
    billing_frequency = case
      when p_changes ? 'billing_frequency' then p_changes ->> 'billing_frequency'
      else lease.billing_frequency
    end,
    rent_free_period_months = case
      when p_changes ? 'rent_free_period_months'
        then nullif(p_changes ->> 'rent_free_period_months', '')::integer
      else lease.rent_free_period_months
    end,
    notes = case
      when p_changes ? 'notes' then nullif(p_changes ->> 'notes', '')
      else lease.notes
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = lease.version + 1
  where lease.workspace_id = p_workspace_id
    and lease.id = p_lease_id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'lease.update', 'lease', p_lease_id,
    private.lease_snapshot(v_old), private.lease_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.lease_snapshot(v_new));
end;
$$;

alter function public.update_lease(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  owner to postgres;
revoke all on function public.update_lease(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.update_lease(uuid, uuid, bigint, jsonb, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- transition_lease_status: STM-005. Activation and termination are the writes
-- that move occupancy, so this is also where sync_unit_occupancy runs. Because
-- the AGG-004 triggers are deferred, the lease row and the unit row settle
-- together at commit rather than fighting over the order.
-- -----------------------------------------------------------------------------

create function private.lease_status_transition_allowed(
  p_from public.lease_status,
  p_to public.lease_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    -- Abort edge: any non-terminal state may be cancelled.
    when p_to = 'cancelled'::public.lease_status
      then p_from not in (
        'ended'::public.lease_status, 'cancelled'::public.lease_status
      )
    when p_from = 'draft'::public.lease_status
      then p_to = 'reviewed'::public.lease_status
    when p_from = 'reviewed'::public.lease_status
      then p_to = 'sent'::public.lease_status
    when p_from = 'sent'::public.lease_status
      then p_to = 'tenant_signed'::public.lease_status
    when p_from = 'tenant_signed'::public.lease_status
      then p_to = 'landlord_signed'::public.lease_status
    when p_from = 'landlord_signed'::public.lease_status
      then p_to = 'active'::public.lease_status
    when p_from = 'active'::public.lease_status
      then p_to = 'ended'::public.lease_status
    else false
  end;
$$;

alter function private.lease_status_transition_allowed(
  public.lease_status, public.lease_status
) owner to postgres;

create function public.transition_lease_status(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_expected_version bigint,
  p_target_status public.lease_status,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_move_out_date date default null,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_old public.leases%rowtype;
  v_new public.leases%rowtype;
  v_unit_before public.units%rowtype;
  v_unit_after public.units%rowtype;
  v_now timestamptz;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_lease_id is null or p_expected_version is null or p_target_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Lease id, expected version and target status are required'
      )
    );
  end if;

  -- Cancelling a lease is an abort; it must say why.
  if p_target_status = 'cancelled'::public.lease_status
     and (p_reason is null or char_length(btrim(p_reason)) = 0) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Cancelling a lease requires a reason',
        'field', 'reason'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Lease management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_lease_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'lease_id', p_lease_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'move_out_date', p_move_out_date,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'lease'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.id = p_lease_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Lease not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Lease version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.lease_snapshot(v_old)
      )
    );
  end if;

  if not private.lease_status_transition_allowed(v_old.status, p_target_status) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'STM-005 does not allow %s -> %s', v_old.status, p_target_status
        ),
        'field', 'target_status',
        'current_status', v_old.status
      )
    );
  end if;

  if p_move_out_date is not null
     and p_target_status <> 'ended'::public.lease_status then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A move-out date only belongs to ending a lease',
        'field', 'move_out_date'
      )
    );
  end if;

  if p_move_out_date is not null
     and v_old.move_in_date is not null
     and p_move_out_date < v_old.move_in_date then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Move-out date must not precede move-in date',
        'field', 'move_out_date'
      )
    );
  end if;

  select *
  into v_unit_before
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = v_old.unit_id;

  v_now := now();

  update public.leases as lease
  set
    status = p_target_status,
    move_out_date = coalesce(p_move_out_date, lease.move_out_date),
    ended_at = case
      when p_target_status = 'ended'::public.lease_status then v_now
      else null
    end,
    cancelled_at = case
      when p_target_status = 'cancelled'::public.lease_status then v_now
      else null
    end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = lease.version + 1
  where lease.workspace_id = p_workspace_id
    and lease.id = p_lease_id
  returning * into v_new;

  -- Occupancy follows the leases. With OPN-DOM-001 this is genuinely a count,
  -- not a flag: ending one of several effective leases leaves the unit occupied.
  perform private.sync_unit_occupancy(p_workspace_id, v_old.unit_id, v_actor_id);

  select *
  into v_unit_after
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.id = v_old.unit_id;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'lease.transition_status', 'lease', p_lease_id,
    private.lease_snapshot(v_old)
      || jsonb_build_object('unit', private.unit_snapshot(v_unit_before)),
    private.lease_snapshot(v_new)
      || jsonb_build_object('unit', private.unit_snapshot(v_unit_after))
  );
  return jsonb_build_object(
    'ok', true,
    'entity', private.lease_snapshot(v_new)
      || jsonb_build_object('unit', private.unit_snapshot(v_unit_after))
  );
end;
$$;

alter function public.transition_lease_status(
  uuid, uuid, bigint, public.lease_status, uuid, uuid, date, text
) owner to postgres;
revoke all on function public.transition_lease_status(
  uuid, uuid, bigint, public.lease_status, uuid, uuid, date, text
) from public, anon, authenticated;
grant execute on function public.transition_lease_status(
  uuid, uuid, bigint, public.lease_status, uuid, uuid, date, text
) to authenticated;
