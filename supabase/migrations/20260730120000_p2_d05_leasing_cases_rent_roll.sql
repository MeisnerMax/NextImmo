-- P2-D05 increment 2: the leasing pipeline and the rent roll (DOM-004, STM-004,
-- AGG-007), completing the leasing_operations cloud schema that increment 1
-- (20260730100000) started with units and leases.
--
-- The mutation surface reuses increment 1's shared plumbing verbatim —
-- private.leasing_command_gate / claim_leasing_mutation /
-- finish_leasing_mutation — rather than introducing a second trio: enveloped
-- {ok,entity}/{ok,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events, default-deny RLS, reject_protected_column_update,
-- and the P2-D01 claim-before-state-validation rule with receipt cleanup for
-- every mutation whose validation reads the state it is about to change. As in
-- increment 1, P2-D02, P2-D03 and P1-004 there is NO AAL2 gate: leasing cases
-- and rent rolls are ordinary workspace business data, gated by lease.read /
-- lease.manage.
--
-- ---------------------------------------------------------------------------
-- What this increment deliberately does NOT contain
-- ---------------------------------------------------------------------------
--
-- Increment 1's header announced lease_rent_schedule (periodic rent overrides,
-- the indexation input) for "the next increment". It is not here, and that is a
-- scope correction rather than an oversight:
--
--   * It is not part of the P2-D05 deliverable in
--     01_domain_expansion_backlog.md, which names units, tenants-as-Party-role,
--     leases, rent_roll_snapshots and the LeasingCase pipeline.
--   * The rent roll does not need it. A snapshot freezes the rent that is on the
--     lease at generation time, so a schedule of future steps changes nothing
--     about a snapshot's correctness. Where a schedule would matter is
--     forward-looking rent projection, which is a reporting concern (P2-D09) and
--     needs the indexation rules that OPN-DOM-003 has not settled.
--   * Building it "because it was mentioned" would add a table with no consumer
--     and an indexation semantic nobody has decided, which is the kind of debt
--     this whole phase exists to remove.
--
-- Also still out: co-tenancy (several jointly liable parties per lease) remains
-- the named gap increment 1 documented, and nothing here works around it.
--
-- ---------------------------------------------------------------------------
-- STM-004 as a real aggregate, and why the chain is strictly linear
-- ---------------------------------------------------------------------------
--
-- inquiry -> contact -> viewing -> documents_pending -> screening -> offer ->
-- contract_draft -> signed -> handover -> completed, with 'cancelled' as the
-- abort from any non-terminal state. That is exactly what 02_domain_map.md
-- documents, and it is implemented exactly: one step forward, or cancel.
--
-- There are deliberately NO backward transitions, because STM-004 lists none.
-- A failed screening or a withdrawn offer is a cancellation with a reason, and
-- the next attempt is a new case — which is also the honest data model, since a
-- reopened case would silently overwrite the history of why the first attempt
-- died. The pre-cancellation stage is not lost: it is the old_values of the
-- append-only audit row for the transition.
--
-- Three progression preconditions are enforced both in the RPC (so the caller
-- gets a typed, field-addressed error) and as CHECK constraints (so the state is
-- unreachable even if a future RPC forgets):
--
--   * a unit is required from 'offer' onward — you cannot offer an unnamed unit;
--   * a prospect party is required from 'screening' onward — you cannot screen an
--     anonymous prospect;
--   * a lease is required from 'signed' onward — 'signed' means a contract
--     exists, so it must point at one.
--
-- 'cancelled' is exempt from all three: cancelling forgets which stage the case
-- died at, so the preconditions cannot be re-derived from the row afterwards.
-- Enumerating the exempt statuses literally in the CHECKs (rather than calling a
-- rank function) keeps the constraints dump- and restore-order-safe.
--
-- The prospect is a Party (AGG-005 / P2-D02) but is NOT required to hold the
-- 'tenant' party role, unlike leases.tenant_party_id. party_role_type has no
-- 'prospect' value, and stamping an inquiry as a tenant would assert a
-- relationship that does not exist yet. The tenant role becomes mandatory at the
-- point a lease names the party, which create_lease already enforces.
--
-- ---------------------------------------------------------------------------
-- AGG-007: what "immutable" and "reproducible" are implemented as
-- ---------------------------------------------------------------------------
--
-- Immutable is structural, not conventional, following the domain_events pattern
-- from P2-D04: before-update and before-delete triggers raise on both the header
-- and the line table, and there is no UPDATE or DELETE policy for either. A
-- snapshot therefore has no version column and no updated_at/updated_by, because
-- a row that can never be written twice has nothing to hold an optimistic
-- concurrency token against; carrying one would advertise a second writer that
-- does not exist.
--
-- Reproducible is enforced by check constraints rather than trusted: the header's
-- unit_count must equal the sum of its three occupancy counters, and
-- total_rent_monthly must equal base + ancillary + parking. The pgTAP test
-- additionally recomputes every header total from the frozen lines.
--
-- A snapshot is deliberately NOT unique per (workspace, property, as_of_date).
-- AGG-007 requires that a snapshot be unchangeable, which is not the same claim
-- as "there may only ever be one per period". Uniqueness would be actively
-- harmful here: OPN-DOM-005 is still open, so there is no delete path anywhere in
-- this schema, and unique + immutable + undeletable means one bad run poisons
-- that reporting period forever with no lawful repair. Several snapshots per
-- period are allowed, each frozen, ordered by generated_at; picking "the current
-- one" is the reader's job and needs no schema support.
--
-- Lines freeze denormalised text (unit_code) and the unit's status on purpose:
-- renaming a unit or re-letting it later must not retroactively change what a
-- past rent roll said. That is the entire point of a snapshot.
--
-- ---------------------------------------------------------------------------
-- OPN-DOM-001 in the rent roll (decided 2026-07-29, default overridden)
-- ---------------------------------------------------------------------------
--
-- A unit may hold several concurrently effective leases, so the rent roll
-- aggregates PER UNIT over every lease effective on the reporting date: there is
-- exactly one line per unit and each money figure on it is a SUM, not a single
-- lease's value. effective_lease_count travels with the line so the sum is
-- auditable rather than mysterious — a line reading "2 leases, 2400" is
-- checkable; a bare "2400" is not. unique (snapshot_id, unit_id) is therefore
-- correct here and is not in tension with the decision: the decision forbids
-- constraining leases per unit, and this constrains LINES per unit, which is
-- what makes the per-unit figure a sum in the first place.
--
-- ---------------------------------------------------------------------------
-- "Effective on the reporting date" — why this differs from AGG-004 on purpose
-- ---------------------------------------------------------------------------
--
-- Increment 1 defined effective as status = 'active' and explicitly rejected a
-- date-based predicate. That reasoning was about a TRIGGER-enforced invariant:
-- triggers fire only on write, so a date predicate would let a stored 'occupied'
-- turn silently non-compliant at midnight and surface as the failure of some
-- unrelated later write.
--
-- A rent roll is the opposite kind of object: a computed, point-in-time report
-- that is evaluated exactly once, when it is generated. Here a date window is
-- not just safe but required — a rent roll "as of 2026-03-31" that counted a
-- lease starting in July would be wrong. So a lease contributes to a snapshot
-- when status = 'active' AND start_date <= as_of_date AND (end_date is null or
-- end_date >= as_of_date).
--
-- The visible consequence, stated rather than left to be discovered: a unit can
-- be 'occupied' by AGG-004 and still contribute 0.00 to a snapshot whose
-- as_of_date falls outside its lease's term. The line's frozen unit_status makes
-- that legible instead of looking like a calculation bug, and the pgTAP test pins
-- the case in both directions. generated_at is stored next to as_of_date for the
-- same reason: statuses are read when the snapshot runs, so the pair
-- (as_of_date, generated_at) is what makes a figure explainable later.
--
-- ---------------------------------------------------------------------------
-- Currency (DEC-011): no silent cross-currency sums
-- ---------------------------------------------------------------------------
--
-- Summing rents in different currencies is meaningless, and a snapshot that did
-- it would be confidently wrong. create_rent_roll_snapshot therefore derives the
-- currency from the contributing leases and refuses with a dedicated
-- 'currency_mismatch' error, listing the currencies it found, when there is more
-- than one. When no lease contributes at all (a fully vacant property, which
-- still deserves a rent roll of zeros) the currency cannot be derived, so it must
-- be passed explicitly; asking is honest, defaulting to EUR would invent data.

-- -----------------------------------------------------------------------------
-- STM-004 enum
-- -----------------------------------------------------------------------------

create type public.leasing_case_status as enum (
  'inquiry',
  'contact',
  'viewing',
  'documents_pending',
  'screening',
  'offer',
  'contract_draft',
  'signed',
  'handover',
  'completed',
  'cancelled'
);

-- -----------------------------------------------------------------------------
-- leasing_cases: the letting pipeline aggregate. Replaces the UI-only status
-- strings the legacy screens carried (part of FTR-024) with a workspace-scoped,
-- versioned, audited row whose state machine is enforced server-side.
-- -----------------------------------------------------------------------------

create table public.leasing_cases (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  unit_id uuid,
  prospect_party_id uuid,
  lease_id uuid,
  case_name text not null,
  status public.leasing_case_status not null default 'inquiry',
  source text not null default 'other',
  opened_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint leasing_cases_workspace_id_key unique (workspace_id, id),
  constraint leasing_cases_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  -- Same composite-FK gap as increment 1: public.properties carries no
  -- (workspace_id, id) unique constraint, so the RPCs verify workspace
  -- membership of the property explicitly instead.
  constraint leasing_cases_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint leasing_cases_unit_fkey foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  constraint leasing_cases_prospect_fkey foreign key (workspace_id, prospect_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint leasing_cases_lease_fkey foreign key (workspace_id, lease_id)
    references public.leases (workspace_id, id) on delete restrict,
  constraint leasing_cases_name_check check (
    char_length(btrim(case_name)) between 1 and 200
  ),
  constraint leasing_cases_source_check check (
    source in ('portal', 'email', 'phone', 'walk_in', 'referral', 'other')
  ),
  constraint leasing_cases_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  -- STM-004 terminal-state markers: exactly the terminal status carries its
  -- timestamp, so "is this case closed" has one answer, not two.
  constraint leasing_cases_completed_marker_check check (
    (status = 'completed') = (completed_at is not null)
  ),
  constraint leasing_cases_cancelled_marker_check check (
    (status = 'cancelled') = (cancelled_at is not null)
  ),
  -- Progression preconditions (see header). 'cancelled' is exempt from all three
  -- because cancelling forgets the stage the case died at.
  constraint leasing_cases_unit_required_check check (
    unit_id is not null
    or status in (
      'inquiry', 'contact', 'viewing', 'documents_pending', 'screening',
      'cancelled'
    )
  ),
  constraint leasing_cases_prospect_required_check check (
    prospect_party_id is not null
    or status in (
      'inquiry', 'contact', 'viewing', 'documents_pending', 'cancelled'
    )
  ),
  constraint leasing_cases_lease_required_check check (
    lease_id is not null
    or status in (
      'inquiry', 'contact', 'viewing', 'documents_pending', 'screening', 'offer',
      'contract_draft', 'cancelled'
    )
  ),
  constraint leasing_cases_version_check check (version >= 1)
);

create index leasing_cases_workspace_idx on public.leasing_cases (workspace_id);
-- property_id leads so this index also covers leasing_cases_property_fkey, the
-- same shape and reasoning as units_property_idx in increment 1.
create index leasing_cases_property_idx
  on public.leasing_cases (property_id, workspace_id);
create index leasing_cases_unit_idx
  on public.leasing_cases (workspace_id, unit_id)
  where unit_id is not null;
create index leasing_cases_prospect_idx
  on public.leasing_cases (workspace_id, prospect_party_id)
  where prospect_party_id is not null;
create index leasing_cases_lease_idx
  on public.leasing_cases (workspace_id, lease_id)
  where lease_id is not null;
create index leasing_cases_status_idx on public.leasing_cases (workspace_id, status);
-- The pipeline board reads open cases oldest-first; terminal cases are excluded.
create index leasing_cases_open_idx
  on public.leasing_cases (workspace_id, opened_at)
  where status not in ('completed', 'cancelled');

create trigger leasing_cases_protected_columns
before update on public.leasing_cases
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'opened_at', 'created_at', 'created_by'
);

alter table public.leasing_cases enable row level security;
alter table public.leasing_cases force row level security;

create policy leasing_cases_select_lease_read
on public.leasing_cases
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.leasing_cases from anon, authenticated;
grant select on table public.leasing_cases to authenticated;

-- -----------------------------------------------------------------------------
-- rent_roll_snapshots: the frozen header. No version / updated_* columns — see
-- the AGG-007 block in the header.
-- -----------------------------------------------------------------------------

create table public.rent_roll_snapshots (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  as_of_date date not null,
  currency_code text not null,
  generated_at timestamptz not null default now(),
  unit_count integer not null,
  occupied_unit_count integer not null,
  vacant_unit_count integer not null,
  offline_unit_count integer not null,
  effective_lease_count integer not null,
  total_base_rent_monthly numeric not null,
  total_ancillary_charges_monthly numeric not null,
  total_parking_other_charges_monthly numeric not null,
  total_rent_monthly numeric not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint rent_roll_snapshots_workspace_id_key unique (workspace_id, id),
  constraint rent_roll_snapshots_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint rent_roll_snapshots_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint rent_roll_snapshots_currency_code_check check (
    currency_code ~ '^[A-Z]{3}$'
  ),
  constraint rent_roll_snapshots_counts_check check (
    unit_count >= 0
    and occupied_unit_count >= 0
    and vacant_unit_count >= 0
    and offline_unit_count >= 0
    and effective_lease_count >= 0
  ),
  -- Reproducibility as structure, part 1: the occupancy counters must partition
  -- the units, so an occupancy rate computed from this header cannot be
  -- internally inconsistent.
  constraint rent_roll_snapshots_counts_partition_check check (
    unit_count = occupied_unit_count + vacant_unit_count + offline_unit_count
  ),
  constraint rent_roll_snapshots_totals_check check (
    total_base_rent_monthly >= 0
    and total_base_rent_monthly <> 'NaN'::numeric
    and total_ancillary_charges_monthly >= 0
    and total_ancillary_charges_monthly <> 'NaN'::numeric
    and total_parking_other_charges_monthly >= 0
    and total_parking_other_charges_monthly <> 'NaN'::numeric
    and total_rent_monthly >= 0
    and total_rent_monthly <> 'NaN'::numeric
  ),
  -- Reproducibility as structure, part 2: the headline figure is exactly the sum
  -- of its components.
  constraint rent_roll_snapshots_total_sum_check check (
    total_rent_monthly = total_base_rent_monthly
      + total_ancillary_charges_monthly
      + total_parking_other_charges_monthly
  )
);

create index rent_roll_snapshots_workspace_idx
  on public.rent_roll_snapshots (workspace_id);
-- The rent-roll history of one property, newest first, is the read this table
-- exists for; property_id leads so it also covers the property FK.
create index rent_roll_snapshots_property_as_of_idx
  on public.rent_roll_snapshots (property_id, workspace_id, as_of_date desc, generated_at desc);

-- -----------------------------------------------------------------------------
-- rent_roll_snapshot_lines: one frozen row per unit. Each money figure is a SUM
-- over the leases effective on as_of_date (OPN-DOM-001).
-- -----------------------------------------------------------------------------

create table public.rent_roll_snapshot_lines (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  snapshot_id uuid not null,
  unit_id uuid not null,
  unit_code text not null,
  unit_status public.unit_status not null,
  area_sqm numeric,
  effective_lease_count integer not null,
  base_rent_monthly numeric not null,
  ancillary_charges_monthly numeric not null,
  parking_other_charges_monthly numeric not null,
  total_rent_monthly numeric not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint rent_roll_snapshot_lines_workspace_id_key unique (workspace_id, id),
  constraint rent_roll_snapshot_lines_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint rent_roll_snapshot_lines_snapshot_fkey
    foreign key (workspace_id, snapshot_id)
    references public.rent_roll_snapshots (workspace_id, id) on delete restrict,
  constraint rent_roll_snapshot_lines_unit_fkey
    foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  -- Exactly one line per unit: this is what makes the per-unit figure a sum
  -- rather than one lease's value. See the OPN-DOM-001 block in the header for
  -- why this does not contradict the decision.
  constraint rent_roll_snapshot_lines_unit_unique unique (snapshot_id, unit_id),
  constraint rent_roll_snapshot_lines_code_check check (
    char_length(btrim(unit_code)) between 1 and 100
  ),
  constraint rent_roll_snapshot_lines_area_check check (
    area_sqm is null or (area_sqm > 0 and area_sqm <> 'NaN'::numeric)
  ),
  constraint rent_roll_snapshot_lines_count_check check (
    effective_lease_count >= 0
  ),
  constraint rent_roll_snapshot_lines_totals_check check (
    base_rent_monthly >= 0
    and base_rent_monthly <> 'NaN'::numeric
    and ancillary_charges_monthly >= 0
    and ancillary_charges_monthly <> 'NaN'::numeric
    and parking_other_charges_monthly >= 0
    and parking_other_charges_monthly <> 'NaN'::numeric
    and total_rent_monthly >= 0
    and total_rent_monthly <> 'NaN'::numeric
  ),
  constraint rent_roll_snapshot_lines_total_sum_check check (
    total_rent_monthly = base_rent_monthly
      + ancillary_charges_monthly
      + parking_other_charges_monthly
  ),
  -- A line with no effective lease carries no rent. Keeps "why is this zero"
  -- answerable from the row itself. The converse is deliberately NOT asserted: a
  -- lease at 0.00 rent is a real thing (rent-free period, caretaker flat).
  constraint rent_roll_snapshot_lines_vacancy_consistency_check check (
    effective_lease_count > 0 or total_rent_monthly = 0
  )
);

create index rent_roll_snapshot_lines_snapshot_idx
  on public.rent_roll_snapshot_lines (workspace_id, snapshot_id);
create index rent_roll_snapshot_lines_unit_idx
  on public.rent_roll_snapshot_lines (workspace_id, unit_id);

-- -----------------------------------------------------------------------------
-- AGG-007 immutability: structural, following the P2-D04 domain_events pattern.
-- There is no update or delete path and no UPDATE/DELETE policy either.
-- -----------------------------------------------------------------------------

create function private.reject_rent_roll_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'rent roll snapshots are immutable (AGG-007)'
    using errcode = 'P0001';
end;
$$;

alter function private.reject_rent_roll_change() owner to postgres;
revoke all on function private.reject_rent_roll_change()
  from public, anon, authenticated;

create trigger rent_roll_snapshots_reject_update
before update on public.rent_roll_snapshots
for each row execute function private.reject_rent_roll_change();

create trigger rent_roll_snapshots_reject_delete
before delete on public.rent_roll_snapshots
for each row execute function private.reject_rent_roll_change();

create trigger rent_roll_snapshot_lines_reject_update
before update on public.rent_roll_snapshot_lines
for each row execute function private.reject_rent_roll_change();

create trigger rent_roll_snapshot_lines_reject_delete
before delete on public.rent_roll_snapshot_lines
for each row execute function private.reject_rent_roll_change();

alter table public.rent_roll_snapshots enable row level security;
alter table public.rent_roll_snapshots force row level security;

create policy rent_roll_snapshots_select_lease_read
on public.rent_roll_snapshots
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.rent_roll_snapshots from anon, authenticated;
grant select on table public.rent_roll_snapshots to authenticated;

alter table public.rent_roll_snapshot_lines enable row level security;
alter table public.rent_roll_snapshot_lines force row level security;

create policy rent_roll_snapshot_lines_select_lease_read
on public.rent_roll_snapshot_lines
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.rent_roll_snapshot_lines from anon, authenticated;
grant select on table public.rent_roll_snapshot_lines to authenticated;

-- -----------------------------------------------------------------------------
-- STM-004 stage order and the transition rule
-- -----------------------------------------------------------------------------

-- Rank of a pipeline stage. 'cancelled' is off the chain and gets 0, so no
-- forward step can ever target it by arithmetic — cancelling is its own rule.
create function private.leasing_case_stage_rank(
  case_status public.leasing_case_status
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case case_status
    when 'inquiry' then 1
    when 'contact' then 2
    when 'viewing' then 3
    when 'documents_pending' then 4
    when 'screening' then 5
    when 'offer' then 6
    when 'contract_draft' then 7
    when 'signed' then 8
    when 'handover' then 9
    when 'completed' then 10
    when 'cancelled' then 0
  end;
$$;

alter function private.leasing_case_stage_rank(public.leasing_case_status)
  owner to postgres;
revoke all on function private.leasing_case_stage_rank(public.leasing_case_status)
  from public, anon, authenticated;

create function private.leasing_case_status_is_terminal(
  case_status public.leasing_case_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case_status in (
    'completed'::public.leasing_case_status,
    'cancelled'::public.leasing_case_status
  );
$$;

alter function private.leasing_case_status_is_terminal(public.leasing_case_status)
  owner to postgres;
revoke all on function private.leasing_case_status_is_terminal(
  public.leasing_case_status
) from public, anon, authenticated;

-- One step forward along the chain, or cancel from any non-terminal state.
-- Nothing leaves a terminal state, and there are no backward edges (see header).
create function private.leasing_case_transition_allowed(
  from_status public.leasing_case_status,
  to_status public.leasing_case_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when private.leasing_case_status_is_terminal(from_status) then false
    when to_status = 'cancelled'::public.leasing_case_status then true
    else private.leasing_case_stage_rank(to_status)
       = private.leasing_case_stage_rank(from_status) + 1
  end;
$$;

alter function private.leasing_case_transition_allowed(
  public.leasing_case_status, public.leasing_case_status
) owner to postgres;
revoke all on function private.leasing_case_transition_allowed(
  public.leasing_case_status, public.leasing_case_status
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Row snapshots for the audit trail and the RPC envelopes
-- -----------------------------------------------------------------------------

create function private.leasing_case_snapshot(leasing_case public.leasing_cases)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', leasing_case.id,
    'workspace_id', leasing_case.workspace_id,
    'property_id', leasing_case.property_id,
    'unit_id', leasing_case.unit_id,
    'prospect_party_id', leasing_case.prospect_party_id,
    'lease_id', leasing_case.lease_id,
    'case_name', leasing_case.case_name,
    'status', leasing_case.status,
    'source', leasing_case.source,
    'opened_at', leasing_case.opened_at,
    'completed_at', leasing_case.completed_at,
    'cancelled_at', leasing_case.cancelled_at,
    'notes', leasing_case.notes,
    'created_at', leasing_case.created_at,
    'updated_at', leasing_case.updated_at,
    'created_by', leasing_case.created_by,
    'updated_by', leasing_case.updated_by,
    'version', leasing_case.version
  );
$$;

alter function private.leasing_case_snapshot(public.leasing_cases) owner to postgres;
revoke all on function private.leasing_case_snapshot(public.leasing_cases)
  from public, anon, authenticated;

create function private.rent_roll_snapshot_header(
  snapshot public.rent_roll_snapshots
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', snapshot.id,
    'workspace_id', snapshot.workspace_id,
    'property_id', snapshot.property_id,
    'as_of_date', snapshot.as_of_date,
    'currency_code', snapshot.currency_code,
    'generated_at', snapshot.generated_at,
    'unit_count', snapshot.unit_count,
    'occupied_unit_count', snapshot.occupied_unit_count,
    'vacant_unit_count', snapshot.vacant_unit_count,
    'offline_unit_count', snapshot.offline_unit_count,
    'effective_lease_count', snapshot.effective_lease_count,
    'total_base_rent_monthly', snapshot.total_base_rent_monthly,
    'total_ancillary_charges_monthly', snapshot.total_ancillary_charges_monthly,
    'total_parking_other_charges_monthly',
      snapshot.total_parking_other_charges_monthly,
    'total_rent_monthly', snapshot.total_rent_monthly,
    'created_at', snapshot.created_at,
    'created_by', snapshot.created_by
  );
$$;

alter function private.rent_roll_snapshot_header(public.rent_roll_snapshots)
  owner to postgres;
revoke all on function private.rent_roll_snapshot_header(
  public.rent_roll_snapshots
) from public, anon, authenticated;

-- The full frozen artefact: header plus its lines, unit_code-ordered so two
-- reads of the same snapshot are byte-identical. This is what the RPC returns
-- AND what the audit row stores, so an idempotent replay hands back exactly the
-- same document as the original call rather than a header-only stub.
create function private.rent_roll_snapshot_document(
  p_workspace_id uuid,
  p_snapshot_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.rent_roll_snapshot_header(snapshot) || jsonb_build_object(
    'lines',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id,
            'unit_id', line.unit_id,
            'unit_code', line.unit_code,
            'unit_status', line.unit_status,
            'area_sqm', line.area_sqm,
            'effective_lease_count', line.effective_lease_count,
            'base_rent_monthly', line.base_rent_monthly,
            'ancillary_charges_monthly', line.ancillary_charges_monthly,
            'parking_other_charges_monthly', line.parking_other_charges_monthly,
            'total_rent_monthly', line.total_rent_monthly
          )
          order by line.unit_code
        )
        from public.rent_roll_snapshot_lines as line
        where line.workspace_id = p_workspace_id
          and line.snapshot_id = p_snapshot_id
      ),
      '[]'::jsonb
    )
  )
  from public.rent_roll_snapshots as snapshot
  where snapshot.workspace_id = p_workspace_id
    and snapshot.id = p_snapshot_id;
$$;

alter function private.rent_roll_snapshot_document(uuid, uuid) owner to postgres;
revoke all on function private.rent_roll_snapshot_document(uuid, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- The rent-roll aggregation, defined exactly once
-- -----------------------------------------------------------------------------

-- One row per unit of the property, with its money figures summed over the
-- leases effective on p_as_of_date. Extracted as a set-returning helper rather
-- than inlined twice (once for the header totals, once for the lines) so the
-- definition of "effective" and the shape of the sum cannot drift apart between
-- the header and the rows it is supposed to summarise.
create function private.rent_roll_unit_rows(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns table (
  unit_id uuid,
  unit_code text,
  unit_status public.unit_status,
  area_sqm numeric,
  effective_lease_count integer,
  base_rent_monthly numeric,
  ancillary_charges_monthly numeric,
  parking_other_charges_monthly numeric,
  total_rent_monthly numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    unit.id,
    unit.unit_code,
    unit.status,
    unit.area_sqm,
    coalesce(effective.lease_count, 0)::integer,
    coalesce(effective.base_rent, 0)::numeric,
    coalesce(effective.ancillary, 0)::numeric,
    coalesce(effective.parking, 0)::numeric,
    (
      coalesce(effective.base_rent, 0)
      + coalesce(effective.ancillary, 0)
      + coalesce(effective.parking, 0)
    )::numeric
  from public.units as unit
  left join lateral (
    select
      count(*) as lease_count,
      sum(lease.base_rent_monthly) as base_rent,
      sum(coalesce(lease.ancillary_charges_monthly, 0)) as ancillary,
      sum(coalesce(lease.parking_other_charges_monthly, 0)) as parking
    from public.leases as lease
    where lease.workspace_id = unit.workspace_id
      and lease.unit_id = unit.id
      and lease.status = 'active'::public.lease_status
      and lease.start_date <= p_as_of_date
      and (lease.end_date is null or lease.end_date >= p_as_of_date)
  ) as effective on true
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;
$$;

alter function private.rent_roll_unit_rows(uuid, uuid, date) owner to postgres;
revoke all on function private.rent_roll_unit_rows(uuid, uuid, date)
  from public, anon, authenticated;

-- The distinct currencies of the leases that will contribute to a snapshot.
-- Used to refuse a cross-currency sum before any row is written.
create function private.rent_roll_currencies(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    array_agg(distinct lease.currency_code order by lease.currency_code),
    '{}'::text[]
  )
  from public.leases as lease
  join public.units as unit
    on unit.workspace_id = lease.workspace_id
    and unit.id = lease.unit_id
  where lease.workspace_id = p_workspace_id
    and unit.property_id = p_property_id
    and lease.status = 'active'::public.lease_status
    and lease.start_date <= p_as_of_date
    and (lease.end_date is null or lease.end_date >= p_as_of_date);
$$;

alter function private.rent_roll_currencies(uuid, uuid, date) owner to postgres;
revoke all on function private.rent_roll_currencies(uuid, uuid, date)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_leasing_case: always starts at 'inquiry'. Advancing is a separate,
-- audited transition.
-- -----------------------------------------------------------------------------

create function public.create_leasing_case(
  p_workspace_id uuid,
  p_property_id uuid,
  p_case_name text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_unit_id uuid default null,
  p_prospect_party_id uuid default null,
  p_source text default 'other',
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
  v_case public.leasing_cases%rowtype;
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

  if p_case_name is null
     or char_length(btrim(p_case_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Case name is required',
        'field', 'case_name'
      )
    );
  end if;

  if coalesce(p_source, 'other')
     not in ('portal', 'email', 'phone', 'walk_in', 'referral', 'other') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported lead source',
        'field', 'source'
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

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  -- A named unit must belong to the same property; a leasing case that points at
  -- another property's unit is not a data-entry slip worth tolerating.
  if p_unit_id is not null then
    if not exists (
      select 1 from public.units as unit
      where unit.workspace_id = p_workspace_id
        and unit.id = p_unit_id
        and unit.property_id = p_property_id
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Unit not found for this property',
          'field', 'unit_id'
        )
      );
    end if;
  end if;

  -- The prospect is a Party but needs no 'tenant' role yet — see the header.
  if p_prospect_party_id is not null then
    if not exists (
      select 1 from public.parties as party
      where party.workspace_id = p_workspace_id
        and party.id = p_prospect_party_id
        and party.deleted_at is null
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Prospect party not found',
          'field', 'prospect_party_id'
        )
      );
    end if;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_leasing_case',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'unit_id', p_unit_id,
        'prospect_party_id', p_prospect_party_id,
        'case_name', btrim(p_case_name),
        'source', coalesce(p_source, 'other'),
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'leasing_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.leasing_cases (
    workspace_id, property_id, unit_id, prospect_party_id, case_name, status,
    source, notes, created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, p_unit_id, p_prospect_party_id,
    btrim(p_case_name), 'inquiry', coalesce(p_source, 'other'),
    nullif(p_notes, ''), v_actor_id, v_actor_id
  )
  returning * into v_case;

  v_new_values := private.leasing_case_snapshot(v_case);

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'leasing_case.create', 'leasing_case', v_case.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_leasing_case(
  uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, text
) owner to postgres;
revoke all on function public.create_leasing_case(
  uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_leasing_case(
  uuid, uuid, text, uuid, uuid, uuid, uuid, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_leasing_case: attribute changes only, and only while the case is still
-- open. Status changes go through transition_leasing_case_status. Once a case is
-- completed or cancelled it is history and is not edited in place.
--
-- unit_id and prospect_party_id are editable here on purpose: an early enquiry
-- routinely changes the unit it is about, and the prospect is often identified
-- only after first contact. They are NOT nullable back to null once the stage
-- requires them — that would walk the row into a state its own CHECK forbids.
-- -----------------------------------------------------------------------------

create function public.update_leasing_case(
  p_workspace_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_case_name text default null,
  p_unit_id uuid default null,
  p_prospect_party_id uuid default null,
  p_source text default null,
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
  v_old public.leasing_cases%rowtype;
  v_new public.leasing_cases%rowtype;
  v_next_unit_id uuid;
  v_next_prospect_id uuid;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_case_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id and expected version are required'
      )
    );
  end if;

  if p_case_name is not null
     and char_length(btrim(p_case_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Case name is required',
        'field', 'case_name'
      )
    );
  end if;

  if p_source is not null
     and p_source not in ('portal', 'email', 'phone', 'walk_in', 'referral', 'other') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported lead source',
        'field', 'source'
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
        'command', 'update_leasing_case',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'case_id', p_case_id,
        'expected_version', p_expected_version,
        'case_name', p_case_name,
        'unit_id', p_unit_id,
        'prospect_party_id', p_prospect_party_id,
        'source', p_source,
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'leasing_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.leasing_cases as leasing_case
  where leasing_case.workspace_id = p_workspace_id
    and leasing_case.id = p_case_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Leasing case not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Leasing case version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.leasing_case_snapshot(v_old)
      )
    );
  end if;

  if private.leasing_case_status_is_terminal(v_old.status) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format('A %s leasing case is not editable', v_old.status),
        'field', 'status',
        'current_status', v_old.status
      )
    );
  end if;

  v_next_unit_id := coalesce(p_unit_id, v_old.unit_id);
  v_next_prospect_id := coalesce(p_prospect_party_id, v_old.prospect_party_id);

  if p_unit_id is not null and p_unit_id is distinct from v_old.unit_id then
    if not exists (
      select 1 from public.units as unit
      where unit.workspace_id = p_workspace_id
        and unit.id = p_unit_id
        and unit.property_id = v_old.property_id
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Unit not found for this property',
          'field', 'unit_id'
        )
      );
    end if;
  end if;

  if p_prospect_party_id is not null
     and p_prospect_party_id is distinct from v_old.prospect_party_id then
    if not exists (
      select 1 from public.parties as party
      where party.workspace_id = p_workspace_id
        and party.id = p_prospect_party_id
        and party.deleted_at is null
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Prospect party not found',
          'field', 'prospect_party_id'
        )
      );
    end if;
  end if;

  update public.leasing_cases as leasing_case
  set
    case_name = coalesce(btrim(p_case_name), leasing_case.case_name),
    unit_id = v_next_unit_id,
    prospect_party_id = v_next_prospect_id,
    source = coalesce(p_source, leasing_case.source),
    notes = case
      when p_notes is null then leasing_case.notes
      else nullif(p_notes, '')
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = leasing_case.version + 1
  where leasing_case.workspace_id = p_workspace_id
    and leasing_case.id = p_case_id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'leasing_case.update', 'leasing_case', v_new.id,
    private.leasing_case_snapshot(v_old), private.leasing_case_snapshot(v_new)
  );
  return jsonb_build_object(
    'ok', true, 'entity', private.leasing_case_snapshot(v_new)
  );
end;
$$;

alter function public.update_leasing_case(
  uuid, uuid, bigint, uuid, uuid, text, uuid, uuid, text, text, text
) owner to postgres;
revoke all on function public.update_leasing_case(
  uuid, uuid, bigint, uuid, uuid, text, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.update_leasing_case(
  uuid, uuid, bigint, uuid, uuid, text, uuid, uuid, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- transition_leasing_case_status: the STM-004 state machine. One step forward or
-- cancel; the progression preconditions are checked here so the caller gets a
-- field-addressed error rather than a constraint violation.
-- -----------------------------------------------------------------------------

create function public.transition_leasing_case_status(
  p_workspace_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_target_status public.leasing_case_status,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_lease_id uuid default null,
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
  v_old public.leasing_cases%rowtype;
  v_new public.leasing_cases%rowtype;
  v_next_lease_id uuid;
  v_target_rank integer;
  v_now timestamptz;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_case_id is null or p_expected_version is null or p_target_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id, expected version and target status are required'
      )
    );
  end if;

  -- Aborting a leasing case must say why; the reason is the only record of what
  -- went wrong, since there is no backward edge that would explain it later.
  if p_target_status = 'cancelled'::public.leasing_case_status
     and (p_reason is null or char_length(btrim(p_reason)) = 0) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Cancelling a leasing case requires a reason',
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
        'command', 'transition_leasing_case_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'case_id', p_case_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'lease_id', p_lease_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'leasing_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.leasing_cases as leasing_case
  where leasing_case.workspace_id = p_workspace_id
    and leasing_case.id = p_case_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Leasing case not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Leasing case version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.leasing_case_snapshot(v_old)
      )
    );
  end if;

  if not private.leasing_case_transition_allowed(v_old.status, p_target_status) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'STM-004 does not allow %s -> %s', v_old.status, p_target_status
        ),
        'field', 'target_status',
        'current_status', v_old.status
      )
    );
  end if;

  v_next_lease_id := coalesce(p_lease_id, v_old.lease_id);
  v_target_rank := private.leasing_case_stage_rank(p_target_status);

  -- A named lease must belong to this workspace and, when the case names a unit,
  -- to that same unit: 'signed' claims a contract exists for THIS letting.
  if p_lease_id is not null and p_lease_id is distinct from v_old.lease_id then
    if not exists (
      select 1 from public.leases as lease
      where lease.workspace_id = p_workspace_id
        and lease.id = p_lease_id
        and (v_old.unit_id is null or lease.unit_id = v_old.unit_id)
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found',
          'message', 'Lease not found for this leasing case',
          'field', 'lease_id'
        )
      );
    end if;
  end if;

  -- Progression preconditions. Cancelling is exempt: it ends the case wherever
  -- it stands and must never be blocked by a missing forward-stage field.
  if p_target_status <> 'cancelled'::public.leasing_case_status then
    if v_target_rank >= private.leasing_case_stage_rank(
         'screening'::public.leasing_case_status
       )
       and v_old.prospect_party_id is null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Screening and everything after it need a prospect party',
          'field', 'prospect_party_id',
          'current_status', v_old.status
        )
      );
    end if;

    if v_target_rank >= private.leasing_case_stage_rank(
         'offer'::public.leasing_case_status
       )
       and v_old.unit_id is null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'An offer and everything after it need a unit',
          'field', 'unit_id',
          'current_status', v_old.status
        )
      );
    end if;

    if v_target_rank >= private.leasing_case_stage_rank(
         'signed'::public.leasing_case_status
       )
       and v_next_lease_id is null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A signed case must name the lease it produced',
          'field', 'lease_id',
          'current_status', v_old.status
        )
      );
    end if;
  end if;

  v_now := now();

  update public.leasing_cases as leasing_case
  set
    status = p_target_status,
    lease_id = v_next_lease_id,
    completed_at = case
      when p_target_status = 'completed'::public.leasing_case_status then v_now
      else null
    end,
    cancelled_at = case
      when p_target_status = 'cancelled'::public.leasing_case_status then v_now
      else null
    end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = leasing_case.version + 1
  where leasing_case.workspace_id = p_workspace_id
    and leasing_case.id = p_case_id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'leasing_case.transition', 'leasing_case', v_new.id,
    private.leasing_case_snapshot(v_old), private.leasing_case_snapshot(v_new)
  );
  return jsonb_build_object(
    'ok', true, 'entity', private.leasing_case_snapshot(v_new)
  );
end;
$$;

alter function public.transition_leasing_case_status(
  uuid, uuid, bigint, public.leasing_case_status, uuid, uuid, uuid, text
) owner to postgres;
revoke all on function public.transition_leasing_case_status(
  uuid, uuid, bigint, public.leasing_case_status, uuid, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.transition_leasing_case_status(
  uuid, uuid, bigint, public.leasing_case_status, uuid, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- create_rent_roll_snapshot: freeze the rent roll of one property as of a date.
--
-- There is no update or transition counterpart, by design (AGG-007): the only
-- lawful operation on a snapshot is creating another one. p_currency_code is
-- required exactly when it cannot be derived, i.e. when no lease contributes.
-- -----------------------------------------------------------------------------

create function public.create_rent_roll_snapshot(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_currency_code text default null,
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
  v_currencies text[];
  v_currency text;
  v_snapshot public.rent_roll_snapshots%rowtype;
  v_document jsonb;
  v_unit_count integer;
  v_occupied integer;
  v_vacant integer;
  v_offline integer;
  v_lease_count integer;
  v_base numeric;
  v_ancillary numeric;
  v_parking numeric;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null or p_as_of_date is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Property and as-of date are required'
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

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Lease management is not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  v_currencies := private.rent_roll_currencies(
    p_workspace_id, p_property_id, p_as_of_date
  );

  -- No silent cross-currency sum (DEC-011). This is checked before the claim so a
  -- mismatch does not burn the mutation id: it is a property of the data, not of
  -- this command, and retrying the same id after fixing the leases is legitimate.
  if array_length(v_currencies, 1) > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'currency_mismatch',
        'message', 'The contributing leases do not share one currency',
        'field', 'currency_code',
        'currencies', to_jsonb(v_currencies)
      )
    );
  end if;

  if array_length(v_currencies, 1) = 1 then
    v_currency := v_currencies[1];

    if p_currency_code is not null and p_currency_code <> v_currency then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'currency_mismatch',
          'message', 'The requested currency is not the currency of the leases',
          'field', 'currency_code',
          'currencies', to_jsonb(v_currencies)
        )
      );
    end if;
  else
    -- Nothing contributes, so nothing implies a currency. Guessing here would
    -- invent data on an otherwise all-zero report.
    if p_currency_code is null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'No effective lease implies a currency; pass one explicitly',
          'field', 'currency_code'
        )
      );
    end if;

    v_currency := p_currency_code;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_rent_roll_snapshot',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'as_of_date', p_as_of_date,
        'currency_code', v_currency,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'rent_roll_snapshot'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- The header totals and the lines come from one definition of the aggregation
  -- (private.rent_roll_unit_rows), evaluated twice in the same transaction and
  -- therefore against the same snapshot of the data.
  select
    count(*)::integer,
    count(*) filter (
      where unit_row.unit_status = 'occupied'::public.unit_status
    )::integer,
    count(*) filter (
      where unit_row.unit_status = 'vacant'::public.unit_status
    )::integer,
    count(*) filter (
      where unit_row.unit_status = 'offline'::public.unit_status
    )::integer,
    coalesce(sum(unit_row.effective_lease_count), 0)::integer,
    coalesce(sum(unit_row.base_rent_monthly), 0)::numeric,
    coalesce(sum(unit_row.ancillary_charges_monthly), 0)::numeric,
    coalesce(sum(unit_row.parking_other_charges_monthly), 0)::numeric
  into
    v_unit_count, v_occupied, v_vacant, v_offline, v_lease_count,
    v_base, v_ancillary, v_parking
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row;

  insert into public.rent_roll_snapshots (
    workspace_id, property_id, as_of_date, currency_code, unit_count,
    occupied_unit_count, vacant_unit_count, offline_unit_count,
    effective_lease_count, total_base_rent_monthly,
    total_ancillary_charges_monthly, total_parking_other_charges_monthly,
    total_rent_monthly, created_by
  ) values (
    p_workspace_id, p_property_id, p_as_of_date, v_currency, v_unit_count,
    v_occupied, v_vacant, v_offline, v_lease_count, v_base, v_ancillary,
    v_parking, v_base + v_ancillary + v_parking, v_actor_id
  )
  returning * into v_snapshot;

  insert into public.rent_roll_snapshot_lines (
    workspace_id, snapshot_id, unit_id, unit_code, unit_status, area_sqm,
    effective_lease_count, base_rent_monthly, ancillary_charges_monthly,
    parking_other_charges_monthly, total_rent_monthly, created_by
  )
  select
    p_workspace_id, v_snapshot.id, unit_row.unit_id, unit_row.unit_code,
    unit_row.unit_status, unit_row.area_sqm, unit_row.effective_lease_count,
    unit_row.base_rent_monthly, unit_row.ancillary_charges_monthly,
    unit_row.parking_other_charges_monthly, unit_row.total_rent_monthly,
    v_actor_id
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row;

  v_document := private.rent_roll_snapshot_document(p_workspace_id, v_snapshot.id);

  -- The audited new_values is the whole frozen document, lines included, so an
  -- idempotent replay returns exactly what the first call returned. That makes
  -- the audit row large for a big property; that is the intended trade, because
  -- the snapshot IS the audited artefact and a header-only audit would not let
  -- anyone reconstruct what was reported.
  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'rent_roll_snapshot.create', 'rent_roll_snapshot', v_snapshot.id,
    null, v_document
  );
  return jsonb_build_object('ok', true, 'entity', v_document);
end;
$$;

alter function public.create_rent_roll_snapshot(
  uuid, uuid, date, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.create_rent_roll_snapshot(
  uuid, uuid, date, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_rent_roll_snapshot(
  uuid, uuid, date, uuid, uuid, text, text
) to authenticated;
