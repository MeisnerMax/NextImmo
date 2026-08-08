-- P2-D07 (Welle 5): valuation_cases — the cloud contract for the rewritten
-- enterprise valuation engine (ImmoWertV Normverfahren + Investmentverfahren,
-- provenance-tagged factors, reconciled Verkehrswert).
--
-- The mutation surface mirrors the P2-D02/P2-D03/P2-D04 verticals exactly:
-- enveloped {ok,entity}/{ok:false,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events, default-deny RLS, reject_protected_column_update,
-- and one shared command gate / claim / finish helper trio instead of per-RPC
-- boilerplate. Claim-before-state-validation with receipt cleanup applies here
-- too. Like P1-004 and P2-D02/D03 there is NO AAL2 gate: valuations are
-- ordinary workspace business data, gated by valuation.read / valuation.manage
-- / valuation.approve.
--
-- What is specific to this domain, and why the schema — not just the client —
-- enforces it:
--
--   * **A factor carries its provenance.** valuation_factors.provenance is an
--     enum, and the value/provenance check constraint makes "missing" and "has
--     a number" mutually exclusive at the storage layer. An unconfirmed
--     suggested_default is stored *as* unconfirmed; nothing in this migration
--     can launder it into a usable value.
--   * **"Nicht ermittelbar" is a stored outcome, not an absence.** A method
--     result row with is_available = false must have a null amount and carries
--     its missing factors/reasons; a row with is_available = true must have an
--     amount and a confidence band. The same holds for market_value_opinions.
--     There is no code path in this migration that can write a substituted
--     number, which is the whole point of the rewrite.
--   * **An approved case is a record (AGG-014).** Every write path checks the
--     status first and returns the dedicated 'approved_immutable' error code —
--     deliberately distinct from 'forbidden', because the caller may well hold
--     the permission; the record is closed. A revision is a new case.
--
-- Publishing a report does NOT bump valuation_cases.version. The report is a
-- deterministic projection of the case's factors, so a re-publish must not move
-- the client's concurrency token underneath an in-flight factor edit; instead
-- publish_valuation_report *validates* p_expected_version and rejects a stale
-- publish outright. Replays resolve through the mutation receipt as everywhere
-- else.
--
-- Named gaps (stated, not improvised):
--   * scenario_id has no foreign key: the scenarios aggregate has not been
--     migrated yet (it is the remaining half of the original P2-D07 scope). It
--     is a nullable uuid until then, and the RPCs do not pretend to validate it.
--   * property_id references public.properties (id) only. A composite
--     (workspace_id, id) foreign key would be stronger, but public.properties
--     carries no such unique constraint and adding one is a change to an
--     existing table's structure; the RPCs therefore verify workspace
--     membership of the property explicitly before insert.
--   * Comparables (the Vergleichswertverfahren inputs) are not stored here.
--     They belong to the `comps` aggregate, which is still outstanding in
--     P2-D07; until it ships, the comparison approach is fed client-side and a
--     case that relies on it reports "nicht ermittelbar" when it is not.

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

-- Consolidates the legacy acquisition / renovation / disposition module
-- services (DUP-012): one subject, one row, one kind.
create type public.valuation_case_kind as enum (
  'acquisition',
  'holding',
  'renovation',
  'disposition'
);

-- Lifecycle: draft -> in_review -> approved -> archived, in_review may fall
-- back to draft, and archived is terminal.
create type public.valuation_case_status as enum (
  'draft',
  'in_review',
  'approved',
  'archived'
);

create type public.valuation_factor_provenance as enum (
  'user_provided',
  'derived',
  'suggested_default',
  'accepted',
  'missing'
);

create type public.valuation_confidence_band as enum (
  'high',
  'medium',
  'low',
  'unknown'
);

create type public.valuation_method_kind as enum (
  'income_approach_de',
  'cost_approach_de',
  'comparison_approach',
  'discounted_cash_flow',
  'direct_capitalization'
);

create type public.valuation_dcf_terminal as enum ('exit_cap', 'gordon_growth');

-- -----------------------------------------------------------------------------
-- valuation_cases: the aggregate.
-- -----------------------------------------------------------------------------

create table public.valuation_cases (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  scenario_id uuid,
  title text not null,
  kind public.valuation_case_kind not null,
  status public.valuation_case_status not null default 'draft',
  dcf_terminal public.valuation_dcf_terminal not null default 'exit_cap',
  enabled_methods public.valuation_method_kind[] not null default array[
    'income_approach_de',
    'cost_approach_de',
    'comparison_approach',
    'discounted_cash_flow',
    'direct_capitalization'
  ]::public.valuation_method_kind[],
  weight_overrides jsonb not null default '{}'::jsonb,
  minimum_comparables integer not null default 3,
  approved_at timestamptz,
  approved_by uuid,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint valuation_cases_workspace_id_key unique (workspace_id, id),
  constraint valuation_cases_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint valuation_cases_property_id_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint valuation_cases_title_check check (
    char_length(btrim(title)) between 1 and 300
  ),
  constraint valuation_cases_methods_check check (
    array_length(enabled_methods, 1) between 1 and 5
  ),
  constraint valuation_cases_weights_check check (
    jsonb_typeof(weight_overrides) = 'object'
  ),
  constraint valuation_cases_minimum_comparables_check check (
    minimum_comparables between 1 and 50
  ),
  constraint valuation_cases_approved_check check (
    (status = 'approved') = (approved_at is not null)
    and (approved_at is null) = (approved_by is null)
  ),
  constraint valuation_cases_archived_check check (
    (status = 'archived') = (archived_at is not null)
  ),
  constraint valuation_cases_version_check check (version >= 1)
);

create index valuation_cases_workspace_idx on public.valuation_cases (workspace_id);
-- property_id leads so this index also covers valuation_cases_property_id_fkey;
-- the workspace column follows, which serves the workspace-scoped "cases of this
-- property" lookup equally well because both predicates are equalities.
create index valuation_cases_property_idx
  on public.valuation_cases (property_id, workspace_id);
create index valuation_cases_status_idx
  on public.valuation_cases (workspace_id, status);
-- The keyset list order: updated_at desc, id desc.
create index valuation_cases_keyset_idx
  on public.valuation_cases (workspace_id, updated_at desc, id desc);

create trigger valuation_cases_protected_columns
before update on public.valuation_cases
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'created_at', 'created_by'
);

alter table public.valuation_cases enable row level security;
alter table public.valuation_cases force row level security;

create policy valuation_cases_select_valuation_read
on public.valuation_cases
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'valuation.read'));

revoke all on table public.valuation_cases from anon, authenticated;
grant select on table public.valuation_cases to authenticated;

-- -----------------------------------------------------------------------------
-- valuation_factors: the provenance-tagged inputs. One row per (case, factor).
-- -----------------------------------------------------------------------------

create table public.valuation_factors (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  valuation_case_id uuid not null,
  factor_id text not null,
  label text not null,
  provenance public.valuation_factor_provenance not null,
  value numeric(20, 6),
  unit text,
  source text,
  note text,
  confidence public.valuation_confidence_band not null default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint valuation_factors_workspace_id_key unique (workspace_id, id),
  constraint valuation_factors_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint valuation_factors_case_fkey
    foreign key (workspace_id, valuation_case_id)
    references public.valuation_cases (workspace_id, id) on delete cascade,
  constraint valuation_factors_unique unique (workspace_id, valuation_case_id, factor_id),
  constraint valuation_factors_factor_id_check check (
    factor_id = btrim(factor_id)
    and char_length(factor_id) between 1 and 100
  ),
  constraint valuation_factors_label_check check (
    char_length(btrim(label)) between 1 and 200
  ),
  -- The honesty invariant at storage level: a missing factor has no number, and
  -- anything that is not missing must have one.
  constraint valuation_factors_value_provenance_check check (
    (provenance = 'missing') = (value is null)
  ),
  constraint valuation_factors_version_check check (version >= 1)
);

create index valuation_factors_case_idx
  on public.valuation_factors (workspace_id, valuation_case_id);

create trigger valuation_factors_protected_columns
before update on public.valuation_factors
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'valuation_case_id', 'factor_id', 'created_at', 'created_by'
);

alter table public.valuation_factors enable row level security;
alter table public.valuation_factors force row level security;

create policy valuation_factors_select_valuation_read
on public.valuation_factors
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'valuation.read'));

revoke all on table public.valuation_factors from anon, authenticated;
grant select on table public.valuation_factors to authenticated;

-- -----------------------------------------------------------------------------
-- valuation_method_results: what each method concluded in the last published
-- report — a value with its trail, or an explicit unavailability with reasons.
-- -----------------------------------------------------------------------------

create table public.valuation_method_results (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  valuation_case_id uuid not null,
  method public.valuation_method_kind not null,
  is_available boolean not null,
  amount numeric(20, 2),
  confidence public.valuation_confidence_band,
  breakdown jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  missing_factors jsonb not null default '[]'::jsonb,
  reasons jsonb not null default '[]'::jsonb,
  computed_from_version bigint not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint valuation_method_results_workspace_id_key unique (workspace_id, id),
  constraint valuation_method_results_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint valuation_method_results_case_fkey
    foreign key (workspace_id, valuation_case_id)
    references public.valuation_cases (workspace_id, id) on delete cascade,
  constraint valuation_method_results_unique
    unique (workspace_id, valuation_case_id, method),
  -- Available means a number and a band; unavailable means no number at all.
  constraint valuation_method_results_availability_check check (
    (is_available and amount is not null and confidence is not null)
    or (not is_available and amount is null)
  ),
  constraint valuation_method_results_json_check check (
    jsonb_typeof(breakdown) = 'array'
    and jsonb_typeof(assumptions) = 'array'
    and jsonb_typeof(missing_factors) = 'array'
    and jsonb_typeof(reasons) = 'array'
  ),
  -- An unavailable result must say why.
  constraint valuation_method_results_reason_check check (
    is_available
    or jsonb_array_length(missing_factors) > 0
    or jsonb_array_length(reasons) > 0
  ),
  constraint valuation_method_results_version_check check (computed_from_version >= 1)
);

create index valuation_method_results_case_idx
  on public.valuation_method_results (workspace_id, valuation_case_id);

create trigger valuation_method_results_protected_columns
before update on public.valuation_method_results
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'valuation_case_id', 'method', 'created_at', 'created_by'
);

alter table public.valuation_method_results enable row level security;
alter table public.valuation_method_results force row level security;

create policy valuation_method_results_select_valuation_read
on public.valuation_method_results
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'valuation.read'));

revoke all on table public.valuation_method_results from anon, authenticated;
grant select on table public.valuation_method_results to authenticated;

-- -----------------------------------------------------------------------------
-- market_value_opinions: the reconciled Verkehrswert of a case, or the recorded
-- statement that none could be concluded. One live row per case.
-- -----------------------------------------------------------------------------

create table public.market_value_opinions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  valuation_case_id uuid not null,
  is_available boolean not null,
  amount numeric(20, 2),
  confidence public.valuation_confidence_band,
  weights jsonb not null default '{}'::jsonb,
  rationale text not null,
  unavailable_methods jsonb not null default '[]'::jsonb,
  computed_from_version bigint not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint market_value_opinions_workspace_id_key unique (workspace_id, id),
  constraint market_value_opinions_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint market_value_opinions_case_fkey
    foreign key (workspace_id, valuation_case_id)
    references public.valuation_cases (workspace_id, id) on delete cascade,
  constraint market_value_opinions_case_unique
    unique (workspace_id, valuation_case_id),
  constraint market_value_opinions_availability_check check (
    (is_available and amount is not null and confidence is not null)
    or (not is_available and amount is null)
  ),
  constraint market_value_opinions_json_check check (
    jsonb_typeof(weights) = 'object'
    and jsonb_typeof(unavailable_methods) = 'array'
  ),
  constraint market_value_opinions_rationale_check check (
    char_length(btrim(rationale)) between 1 and 4000
  ),
  constraint market_value_opinions_version_check check (computed_from_version >= 1)
);

create trigger market_value_opinions_protected_columns
before update on public.market_value_opinions
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'valuation_case_id', 'created_at', 'created_by'
);

alter table public.market_value_opinions enable row level security;
alter table public.market_value_opinions force row level security;

create policy market_value_opinions_select_valuation_read
on public.market_value_opinions
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'valuation.read'));

revoke all on table public.market_value_opinions from anon, authenticated;
grant select on table public.market_value_opinions to authenticated;

-- -----------------------------------------------------------------------------
-- valuation_reference_data: workspace-overridable reference tables (NHK,
-- Bewirtschaftungskosten, Liegenschaftszins-/Sachwertfaktor-Spannen).
--
-- The client ships offline seed tables; a workspace may override an entry here.
-- The payload stays jsonb on purpose: these are indicative reference *tables*
-- with differing shapes, and an external provider (BORIS/Gutachterausschuss)
-- is a documented later stage, so a rigid column set would have to be migrated
-- again the moment it arrives.
-- -----------------------------------------------------------------------------

create table public.valuation_reference_data (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  key text not null,
  payload jsonb not null,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint valuation_reference_data_workspace_id_key unique (workspace_id, id),
  constraint valuation_reference_data_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint valuation_reference_data_key_unique unique (workspace_id, key),
  constraint valuation_reference_data_key_check check (
    key = lower(btrim(key))
    and key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(key) between 2 and 100
  ),
  constraint valuation_reference_data_payload_check check (
    jsonb_typeof(payload) = 'object'
  ),
  constraint valuation_reference_data_version_check check (version >= 1)
);

create trigger valuation_reference_data_protected_columns
before update on public.valuation_reference_data
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'key', 'created_at', 'created_by'
);

alter table public.valuation_reference_data enable row level security;
alter table public.valuation_reference_data force row level security;

create policy valuation_reference_data_select_valuation_read
on public.valuation_reference_data
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'valuation.read'));

revoke all on table public.valuation_reference_data from anon, authenticated;
grant select on table public.valuation_reference_data to authenticated;

-- -----------------------------------------------------------------------------
-- Command helpers: gate / claim / finish, identical in shape to P2-D03.
-- -----------------------------------------------------------------------------

create function private.valuation_command_gate(
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

alter function private.valuation_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.valuation_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function private.claim_valuation_mutation(
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

alter function private.claim_valuation_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_valuation_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_valuation_mutation(
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

alter function private.finish_valuation_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_valuation_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Snapshots
-- -----------------------------------------------------------------------------

create function private.valuation_case_snapshot(valuation_case public.valuation_cases)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', valuation_case.id,
    'workspace_id', valuation_case.workspace_id,
    'property_id', valuation_case.property_id,
    'scenario_id', valuation_case.scenario_id,
    'title', valuation_case.title,
    'kind', valuation_case.kind,
    'status', valuation_case.status,
    'dcf_terminal', valuation_case.dcf_terminal,
    'enabled_methods', to_jsonb(valuation_case.enabled_methods),
    'weight_overrides', valuation_case.weight_overrides,
    'minimum_comparables', valuation_case.minimum_comparables,
    'approved_at', valuation_case.approved_at,
    'approved_by', valuation_case.approved_by,
    'archived_at', valuation_case.archived_at,
    'created_at', valuation_case.created_at,
    'updated_at', valuation_case.updated_at,
    'created_by', valuation_case.created_by,
    'updated_by', valuation_case.updated_by,
    'version', valuation_case.version
  );
$$;

alter function private.valuation_case_snapshot(public.valuation_cases) owner to postgres;
revoke all on function private.valuation_case_snapshot(public.valuation_cases)
  from public, anon, authenticated;

create function private.valuation_factor_snapshot(factor public.valuation_factors)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'valuation_case_id', factor.valuation_case_id,
    'factor_id', factor.factor_id,
    'label', factor.label,
    'provenance', factor.provenance,
    'value', factor.value,
    'unit', factor.unit,
    'source', factor.source,
    'note', factor.note,
    'confidence', factor.confidence
  );
$$;

alter function private.valuation_factor_snapshot(public.valuation_factors) owner to postgres;
revoke all on function private.valuation_factor_snapshot(public.valuation_factors)
  from public, anon, authenticated;

-- All factors of a case, ordered by factor_id so the snapshot is deterministic.
create function private.valuation_factor_set(
  p_workspace_id uuid,
  p_valuation_case_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(private.valuation_factor_snapshot(factor) order by factor.factor_id),
    '[]'::jsonb
  )
  from public.valuation_factors as factor
  where factor.workspace_id = p_workspace_id
    and factor.valuation_case_id = p_valuation_case_id;
$$;

alter function private.valuation_factor_set(uuid, uuid) owner to postgres;
revoke all on function private.valuation_factor_set(uuid, uuid)
  from public, anon, authenticated;

-- The case plus its factors — the entity every case-level RPC returns.
create function private.valuation_case_detail(valuation_case public.valuation_cases)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select private.valuation_case_snapshot(valuation_case)
    || jsonb_build_object(
         'factors',
         private.valuation_factor_set(
           valuation_case.workspace_id, valuation_case.id
         )
       );
$$;

alter function private.valuation_case_detail(public.valuation_cases) owner to postgres;
revoke all on function private.valuation_case_detail(public.valuation_cases)
  from public, anon, authenticated;

-- Client-mirrored status machine, authoritative here.
create function private.valuation_status_can_transition(
  p_from public.valuation_case_status,
  p_to public.valuation_case_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_from
    when 'draft' then p_to in ('in_review', 'archived')
    when 'in_review' then p_to in ('draft', 'approved', 'archived')
    when 'approved' then p_to = 'archived'
    else false
  end;
$$;

alter function private.valuation_status_can_transition(
  public.valuation_case_status, public.valuation_case_status
) owner to postgres;
revoke all on function private.valuation_status_can_transition(
  public.valuation_case_status, public.valuation_case_status
) from public, anon, authenticated;
grant execute on function private.valuation_status_can_transition(
  public.valuation_case_status, public.valuation_case_status
) to authenticated;

-- Validates one element of the factor payload. Returns null when valid,
-- otherwise the error envelope.
create function private.validate_valuation_factor_payload(p_factor jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_provenance text := p_factor ->> 'provenance';
  v_factor_id text := p_factor ->> 'factor_id';
begin
  if jsonb_typeof(p_factor) <> 'object'
     or v_factor_id is null
     or char_length(btrim(v_factor_id)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Each factor requires a factor_id',
        'field', 'factors'
      )
    );
  end if;

  if v_provenance is null or not exists (
    select 1
    from unnest(enum_range(null::public.valuation_factor_provenance)) as allowed
    where allowed::text = v_provenance
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Factor provenance is invalid',
        'field', 'provenance'
      )
    );
  end if;

  -- Mirrors valuation_factors_value_provenance_check, but as a typed command
  -- error rather than a constraint violation.
  if (v_provenance = 'missing') <> (p_factor -> 'value' is null
        or jsonb_typeof(p_factor -> 'value') = 'null') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A missing factor carries no value, every other provenance requires one',
        'field', 'value'
      )
    );
  end if;

  if p_factor ->> 'label' is null
     or char_length(btrim(p_factor ->> 'label')) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Each factor requires a label',
        'field', 'label'
      )
    );
  end if;

  if p_factor ->> 'confidence' is not null and not exists (
    select 1
    from unnest(enum_range(null::public.valuation_confidence_band)) as allowed
    where allowed::text = p_factor ->> 'confidence'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Factor confidence is invalid',
        'field', 'confidence'
      )
    );
  end if;

  return null;
end;
$$;

alter function private.validate_valuation_factor_payload(jsonb) owner to postgres;
revoke all on function private.validate_valuation_factor_payload(jsonb)
  from public, anon, authenticated;

-- Writes the factor payload of a case (insert or update by factor_id).
create function private.apply_valuation_factors(
  p_workspace_id uuid,
  p_valuation_case_id uuid,
  p_factors jsonb,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_factor jsonb;
begin
  for v_factor in select * from jsonb_array_elements(coalesce(p_factors, '[]'::jsonb))
  loop
    insert into public.valuation_factors (
      workspace_id, valuation_case_id, factor_id, label, provenance, value,
      unit, source, note, confidence, created_by, updated_by
    ) values (
      p_workspace_id,
      p_valuation_case_id,
      btrim(v_factor ->> 'factor_id'),
      btrim(v_factor ->> 'label'),
      (v_factor ->> 'provenance')::public.valuation_factor_provenance,
      nullif(v_factor ->> 'value', '')::numeric,
      v_factor ->> 'unit',
      v_factor ->> 'source',
      v_factor ->> 'note',
      coalesce(
        (v_factor ->> 'confidence')::public.valuation_confidence_band,
        'unknown'::public.valuation_confidence_band
      ),
      p_actor_id,
      p_actor_id
    )
    on conflict (workspace_id, valuation_case_id, factor_id) do update
    set
      label = excluded.label,
      provenance = excluded.provenance,
      value = excluded.value,
      unit = excluded.unit,
      source = excluded.source,
      note = excluded.note,
      confidence = excluded.confidence,
      updated_at = now(),
      updated_by = p_actor_id,
      version = public.valuation_factors.version + 1;
  end loop;
end;
$$;

alter function private.apply_valuation_factors(uuid, uuid, jsonb, uuid) owner to postgres;
revoke all on function private.apply_valuation_factors(uuid, uuid, jsonb, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_valuation_case
-- -----------------------------------------------------------------------------

create function public.create_valuation_case(
  p_workspace_id uuid,
  p_property_id uuid,
  p_title text,
  p_kind text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_scenario_id uuid default null,
  p_dcf_terminal text default 'exit_cap',
  p_enabled_methods text[] default null,
  p_weight_overrides jsonb default '{}'::jsonb,
  p_minimum_comparables integer default 3,
  p_factors jsonb default '[]'::jsonb,
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
  v_factor jsonb;
  v_factor_error jsonb;
  v_methods public.valuation_method_kind[];
  v_case public.valuation_cases%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Property is required', 'field', 'property_id'
      )
    );
  end if;

  if p_title is null or char_length(btrim(p_title)) not between 1 and 300 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is required', 'field', 'title'
      )
    );
  end if;

  if p_kind is null or not exists (
    select 1 from unnest(enum_range(null::public.valuation_case_kind)) as allowed
    where allowed::text = p_kind
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Case kind is invalid', 'field', 'kind'
      )
    );
  end if;

  if p_dcf_terminal is null or not exists (
    select 1 from unnest(enum_range(null::public.valuation_dcf_terminal)) as allowed
    where allowed::text = p_dcf_terminal
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'DCF terminal method is invalid',
        'field', 'dcf_terminal'
      )
    );
  end if;

  if p_enabled_methods is not null and exists (
    select 1
    from unnest(p_enabled_methods) as requested
    where not exists (
      select 1 from unnest(enum_range(null::public.valuation_method_kind)) as allowed
      where allowed::text = requested
    )
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Enabled methods contain an unknown method',
        'field', 'enabled_methods'
      )
    );
  end if;

  if p_minimum_comparables is null or p_minimum_comparables not between 1 and 50 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Minimum comparables must be between 1 and 50',
        'field', 'minimum_comparables'
      )
    );
  end if;

  if jsonb_typeof(coalesce(p_weight_overrides, '{}'::jsonb)) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Weight overrides must be an object',
        'field', 'weight_overrides'
      )
    );
  end if;

  for v_factor in select * from jsonb_array_elements(coalesce(p_factors, '[]'::jsonb))
  loop
    v_factor_error := private.validate_valuation_factor_payload(v_factor);
    if v_factor_error is not null then
      return v_factor_error;
    end if;
  end loop;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  -- The property must live in the same workspace. A composite foreign key would
  -- state this structurally, but public.properties carries no (workspace_id, id)
  -- unique constraint to reference.
  if not exists (
    select 1
    from public.properties as property
    where property.id = p_property_id
      and property.workspace_id = p_workspace_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found in this workspace'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_valuation_case',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'scenario_id', p_scenario_id,
        'title', btrim(p_title),
        'kind', p_kind,
        'dcf_terminal', p_dcf_terminal,
        'enabled_methods', to_jsonb(p_enabled_methods),
        'weight_overrides', coalesce(p_weight_overrides, '{}'::jsonb),
        'minimum_comparables', p_minimum_comparables,
        'factors', coalesce(p_factors, '[]'::jsonb),
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if p_enabled_methods is null then
    v_methods := array[
      'income_approach_de',
      'cost_approach_de',
      'comparison_approach',
      'discounted_cash_flow',
      'direct_capitalization'
    ]::public.valuation_method_kind[];
  else
    select array_agg(method::public.valuation_method_kind order by method)
    into v_methods
    from unnest(p_enabled_methods) as method;
  end if;

  if v_methods is null or array_length(v_methods, 1) is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'At least one method must be enabled',
        'field', 'enabled_methods'
      )
    );
  end if;

  insert into public.valuation_cases (
    workspace_id, property_id, scenario_id, title, kind, dcf_terminal,
    enabled_methods, weight_overrides, minimum_comparables, created_by, updated_by
  ) values (
    p_workspace_id,
    p_property_id,
    p_scenario_id,
    btrim(p_title),
    p_kind::public.valuation_case_kind,
    p_dcf_terminal::public.valuation_dcf_terminal,
    v_methods,
    coalesce(p_weight_overrides, '{}'::jsonb),
    p_minimum_comparables,
    v_actor_id,
    v_actor_id
  )
  returning * into v_case;

  perform private.apply_valuation_factors(
    p_workspace_id, v_case.id, p_factors, v_actor_id
  );

  v_new_values := private.valuation_case_detail(v_case);
  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_case.create', 'valuation_case', v_case.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_valuation_case(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text[], jsonb, integer, jsonb, text
) owner to postgres;
revoke all on function public.create_valuation_case(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text[], jsonb, integer, jsonb, text
) from public, anon, authenticated;
grant execute on function public.create_valuation_case(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text[], jsonb, integer, jsonb, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_valuation_case: configuration only (title, methods, weighting).
-- Factors go through upsert_valuation_factors.
-- -----------------------------------------------------------------------------

create function public.update_valuation_case(
  p_workspace_id uuid,
  p_valuation_case_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_title text default null,
  p_kind text default null,
  p_scenario_id uuid default null,
  p_clear_scenario_id boolean default false,
  p_dcf_terminal text default null,
  p_enabled_methods text[] default null,
  p_weight_overrides jsonb default null,
  p_minimum_comparables integer default null,
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
  v_existing public.valuation_cases%rowtype;
  v_case public.valuation_cases%rowtype;
  v_methods public.valuation_method_kind[];
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_valuation_case_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id and expected version are required'
      )
    );
  end if;

  if p_title is not null
     and char_length(btrim(p_title)) not between 1 and 300 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is invalid', 'field', 'title'
      )
    );
  end if;

  if p_kind is not null and not exists (
    select 1 from unnest(enum_range(null::public.valuation_case_kind)) as allowed
    where allowed::text = p_kind
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Case kind is invalid', 'field', 'kind'
      )
    );
  end if;

  if p_dcf_terminal is not null and not exists (
    select 1 from unnest(enum_range(null::public.valuation_dcf_terminal)) as allowed
    where allowed::text = p_dcf_terminal
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'DCF terminal method is invalid',
        'field', 'dcf_terminal'
      )
    );
  end if;

  if p_minimum_comparables is not null
     and p_minimum_comparables not between 1 and 50 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Minimum comparables must be between 1 and 50',
        'field', 'minimum_comparables'
      )
    );
  end if;

  if p_weight_overrides is not null
     and jsonb_typeof(p_weight_overrides) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Weight overrides must be an object',
        'field', 'weight_overrides'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_valuation_case',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'valuation_case_id', p_valuation_case_id,
        'expected_version', p_expected_version,
        'title', p_title,
        'kind', p_kind,
        'scenario_id', p_scenario_id,
        'clear_scenario_id', p_clear_scenario_id,
        'dcf_terminal', p_dcf_terminal,
        'enabled_methods', to_jsonb(p_enabled_methods),
        'weight_overrides', p_weight_overrides,
        'minimum_comparables', p_minimum_comparables,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select valuation_case.*
  into v_existing
  from public.valuation_cases as valuation_case
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Valuation case not found')
    );
  end if;

  if v_existing.status in ('approved', 'archived') then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'approved_immutable',
        'message', 'An approved or archived valuation is a record and cannot be edited'
      )
    );
  end if;

  if v_existing.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Valuation case version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_existing.version,
        'current_entity', private.valuation_case_snapshot(v_existing)
      )
    );
  end if;

  if p_enabled_methods is null then
    v_methods := v_existing.enabled_methods;
  else
    if exists (
      select 1
      from unnest(p_enabled_methods) as requested
      where not exists (
        select 1 from unnest(enum_range(null::public.valuation_method_kind)) as allowed
        where allowed::text = requested
      )
    ) then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Enabled methods contain an unknown method',
          'field', 'enabled_methods'
        )
      );
    end if;

    select array_agg(method::public.valuation_method_kind order by method)
    into v_methods
    from unnest(p_enabled_methods) as method;

    if v_methods is null or array_length(v_methods, 1) is null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'At least one method must be enabled',
          'field', 'enabled_methods'
        )
      );
    end if;
  end if;

  update public.valuation_cases as valuation_case
  set
    title = coalesce(btrim(p_title), valuation_case.title),
    kind = coalesce(p_kind::public.valuation_case_kind, valuation_case.kind),
    scenario_id = case
      when p_clear_scenario_id then null
      else coalesce(p_scenario_id, valuation_case.scenario_id)
    end,
    dcf_terminal = coalesce(
      p_dcf_terminal::public.valuation_dcf_terminal, valuation_case.dcf_terminal
    ),
    enabled_methods = v_methods,
    weight_overrides = coalesce(p_weight_overrides, valuation_case.weight_overrides),
    minimum_comparables = coalesce(
      p_minimum_comparables, valuation_case.minimum_comparables
    ),
    updated_at = now(),
    updated_by = v_actor_id,
    version = valuation_case.version + 1
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  returning * into v_case;

  v_new_values := private.valuation_case_detail(v_case);
  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_case.update', 'valuation_case', v_case.id,
    private.valuation_case_snapshot(v_existing), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.update_valuation_case(
  uuid, uuid, bigint, uuid, uuid, text, text, uuid, boolean, text, text[], jsonb,
  integer, text
) owner to postgres;
revoke all on function public.update_valuation_case(
  uuid, uuid, bigint, uuid, uuid, text, text, uuid, boolean, text, text[], jsonb,
  integer, text
) from public, anon, authenticated;
grant execute on function public.update_valuation_case(
  uuid, uuid, bigint, uuid, uuid, text, text, uuid, boolean, text, text[], jsonb,
  integer, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- upsert_valuation_factors: the factor write path, including confirming a
-- system suggestion (provenance 'accepted'). Removing a factor is legitimate
-- and makes the dependent methods report "nicht ermittelbar" again.
-- -----------------------------------------------------------------------------

create function public.upsert_valuation_factors(
  p_workspace_id uuid,
  p_valuation_case_id uuid,
  p_expected_version bigint,
  p_factors jsonb,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_remove_factor_ids text[] default '{}'::text[],
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
  v_factor jsonb;
  v_factor_error jsonb;
  v_existing public.valuation_cases%rowtype;
  v_case public.valuation_cases%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_valuation_case_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id and expected version are required'
      )
    );
  end if;

  if jsonb_typeof(coalesce(p_factors, '[]'::jsonb)) <> 'array' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Factors must be an array',
        'field', 'factors'
      )
    );
  end if;

  for v_factor in select * from jsonb_array_elements(coalesce(p_factors, '[]'::jsonb))
  loop
    v_factor_error := private.validate_valuation_factor_payload(v_factor);
    if v_factor_error is not null then
      return v_factor_error;
    end if;
  end loop;

  if coalesce(jsonb_array_length(coalesce(p_factors, '[]'::jsonb)), 0) = 0
     and coalesce(array_length(p_remove_factor_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Nothing to write: neither factors nor removals were supplied'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_valuation_factors',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'valuation_case_id', p_valuation_case_id,
        'expected_version', p_expected_version,
        'factors', coalesce(p_factors, '[]'::jsonb),
        'remove_factor_ids', to_jsonb(p_remove_factor_ids),
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select valuation_case.*
  into v_existing
  from public.valuation_cases as valuation_case
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Valuation case not found')
    );
  end if;

  if v_existing.status in ('approved', 'archived') then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'approved_immutable',
        'message', 'An approved or archived valuation is a record and cannot be edited'
      )
    );
  end if;

  if v_existing.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Valuation case version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_existing.version,
        'current_entity', private.valuation_case_snapshot(v_existing)
      )
    );
  end if;

  if coalesce(array_length(p_remove_factor_ids, 1), 0) > 0 then
    delete from public.valuation_factors as factor
    where factor.workspace_id = p_workspace_id
      and factor.valuation_case_id = p_valuation_case_id
      and factor.factor_id = any (p_remove_factor_ids);
  end if;

  perform private.apply_valuation_factors(
    p_workspace_id, p_valuation_case_id, p_factors, v_actor_id
  );

  -- The factor set is part of the case's observable state, so the case version
  -- moves with it — that is what makes optimistic concurrency work across two
  -- clients editing the same inputs.
  update public.valuation_cases as valuation_case
  set
    updated_at = now(),
    updated_by = v_actor_id,
    version = valuation_case.version + 1
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  returning * into v_case;

  v_new_values := private.valuation_case_detail(v_case);
  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_case.factors_upsert', 'valuation_case', v_case.id,
    private.valuation_case_snapshot(v_existing), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.upsert_valuation_factors(
  uuid, uuid, bigint, jsonb, uuid, uuid, text[], text
) owner to postgres;
revoke all on function public.upsert_valuation_factors(
  uuid, uuid, bigint, jsonb, uuid, uuid, text[], text
) from public, anon, authenticated;
grant execute on function public.upsert_valuation_factors(
  uuid, uuid, bigint, jsonb, uuid, uuid, text[], text
) to authenticated;

-- -----------------------------------------------------------------------------
-- transition_valuation_case_status: STM for the case. Approving requires the
-- separate valuation.approve permission (guardrail: scenario.approve-class
-- capabilities are distinct from ordinary edit rights).
-- -----------------------------------------------------------------------------

create function public.transition_valuation_case_status(
  p_workspace_id uuid,
  p_valuation_case_id uuid,
  p_expected_version bigint,
  p_target_status text,
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
  v_existing public.valuation_cases%rowtype;
  v_case public.valuation_cases%rowtype;
  v_target public.valuation_case_status;
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_valuation_case_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id and expected version are required'
      )
    );
  end if;

  if p_target_status is null or not exists (
    select 1 from unnest(enum_range(null::public.valuation_case_status)) as allowed
    where allowed::text = p_target_status
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Target status is invalid',
        'field', 'target_status'
      )
    );
  end if;

  v_target := p_target_status::public.valuation_case_status;

  if v_target = 'approved' then
    if not private.has_workspace_permission(p_workspace_id, 'valuation.approve') then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'forbidden', 'message', 'Valuation approval is not permitted'
        )
      );
    end if;
  elsif not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_valuation_case_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'valuation_case_id', p_valuation_case_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select valuation_case.*
  into v_existing
  from public.valuation_cases as valuation_case
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Valuation case not found')
    );
  end if;

  if v_existing.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Valuation case version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_existing.version,
        'current_entity', private.valuation_case_snapshot(v_existing)
      )
    );
  end if;

  if not private.valuation_status_can_transition(v_existing.status, v_target) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'Transition %s -> %s is not allowed', v_existing.status, v_target
        ),
        'field', 'target_status'
      )
    );
  end if;

  update public.valuation_cases as valuation_case
  set
    status = v_target,
    approved_at = case when v_target = 'approved' then now() else null end,
    approved_by = case when v_target = 'approved' then v_actor_id else null end,
    archived_at = case when v_target = 'archived' then now() else null end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = valuation_case.version + 1
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  returning * into v_case;

  v_new_values := private.valuation_case_snapshot(v_case);
  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_case.' || v_target::text, 'valuation_case', v_case.id,
    private.valuation_case_snapshot(v_existing), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.transition_valuation_case_status(
  uuid, uuid, bigint, text, uuid, uuid, text
) owner to postgres;
revoke all on function public.transition_valuation_case_status(
  uuid, uuid, bigint, text, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.transition_valuation_case_status(
  uuid, uuid, bigint, text, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- publish_valuation_report: stores the computed method results plus the
-- reconciled Verkehrswert. Replaces the previous report of the case (the
-- report is derived state, so there is exactly one live projection), validates
-- the case version without bumping it, and refuses to touch an approved case.
-- -----------------------------------------------------------------------------

create function public.publish_valuation_report(
  p_workspace_id uuid,
  p_valuation_case_id uuid,
  p_expected_version bigint,
  p_method_results jsonb,
  p_opinion jsonb,
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
  v_result jsonb;
  v_existing public.valuation_cases%rowtype;
  v_opinion_available boolean;
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_valuation_case_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Case id and expected version are required'
      )
    );
  end if;

  if jsonb_typeof(coalesce(p_method_results, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_method_results, '[]'::jsonb)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A report needs at least one method result',
        'field', 'method_results'
      )
    );
  end if;

  for v_result in select * from jsonb_array_elements(p_method_results)
  loop
    if not exists (
      select 1 from unnest(enum_range(null::public.valuation_method_kind)) as allowed
      where allowed::text = v_result ->> 'method'
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Method result names an unknown method',
          'field', 'method'
        )
      );
    end if;

    -- The core rule of the rewrite, enforced before the constraint fires: an
    -- unavailable method may not carry a number.
    if coalesce((v_result ->> 'is_available')::boolean, false) then
      if v_result ->> 'amount' is null or v_result ->> 'confidence' is null then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'validation_failed',
            'message', 'An available method result needs an amount and a confidence band',
            'field', 'amount'
          )
        );
      end if;
    elsif v_result ->> 'amount' is not null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'An unavailable method result must not carry an amount',
          'field', 'amount'
        )
      );
    end if;
  end loop;

  if jsonb_typeof(coalesce(p_opinion, 'null'::jsonb)) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A market value opinion is required',
        'field', 'opinion'
      )
    );
  end if;

  v_opinion_available := coalesce((p_opinion ->> 'is_available')::boolean, false);
  if v_opinion_available
     and (p_opinion ->> 'amount' is null or p_opinion ->> 'confidence' is null) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An available market value needs an amount and a confidence band',
        'field', 'opinion'
      )
    );
  end if;

  if not v_opinion_available and p_opinion ->> 'amount' is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An unavailable market value must not carry an amount',
        'field', 'opinion'
      )
    );
  end if;

  if p_opinion ->> 'rationale' is null
     or char_length(btrim(p_opinion ->> 'rationale')) not between 1 and 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The opinion must carry a rationale',
        'field', 'rationale'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'publish_valuation_report',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'valuation_case_id', p_valuation_case_id,
        'expected_version', p_expected_version,
        'method_results', p_method_results,
        'opinion', p_opinion,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_report'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select valuation_case.*
  into v_existing
  from public.valuation_cases as valuation_case
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_valuation_case_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Valuation case not found')
    );
  end if;

  if v_existing.status in ('approved', 'archived') then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'approved_immutable',
        'message', 'An approved or archived valuation keeps the report it was approved with'
      )
    );
  end if;

  if v_existing.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'The report was computed from a stale factor set',
        'expected_version', p_expected_version,
        'actual_version', v_existing.version,
        'current_entity', private.valuation_case_snapshot(v_existing)
      )
    );
  end if;

  delete from public.valuation_method_results as result
  where result.workspace_id = p_workspace_id
    and result.valuation_case_id = p_valuation_case_id;

  insert into public.valuation_method_results (
    workspace_id, valuation_case_id, method, is_available, amount, confidence,
    breakdown, assumptions, missing_factors, reasons, computed_from_version,
    created_by
  )
  select
    p_workspace_id,
    p_valuation_case_id,
    (element ->> 'method')::public.valuation_method_kind,
    coalesce((element ->> 'is_available')::boolean, false),
    nullif(element ->> 'amount', '')::numeric,
    (element ->> 'confidence')::public.valuation_confidence_band,
    coalesce(element -> 'breakdown', '[]'::jsonb),
    coalesce(element -> 'assumptions', '[]'::jsonb),
    coalesce(element -> 'missing_factors', '[]'::jsonb),
    coalesce(element -> 'reasons', '[]'::jsonb),
    v_existing.version,
    v_actor_id
  from jsonb_array_elements(p_method_results) as element;

  delete from public.market_value_opinions as opinion
  where opinion.workspace_id = p_workspace_id
    and opinion.valuation_case_id = p_valuation_case_id;

  insert into public.market_value_opinions (
    workspace_id, valuation_case_id, is_available, amount, confidence, weights,
    rationale, unavailable_methods, computed_from_version, created_by
  ) values (
    p_workspace_id,
    p_valuation_case_id,
    v_opinion_available,
    nullif(p_opinion ->> 'amount', '')::numeric,
    (p_opinion ->> 'confidence')::public.valuation_confidence_band,
    coalesce(p_opinion -> 'weights', '{}'::jsonb),
    btrim(p_opinion ->> 'rationale'),
    coalesce(p_opinion -> 'unavailable_methods', '[]'::jsonb),
    v_existing.version,
    v_actor_id
  );

  v_new_values := jsonb_build_object(
    'valuation_case_id', p_valuation_case_id,
    'computed_from_version', v_existing.version,
    'method_results', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'method', result.method,
            'is_available', result.is_available,
            'amount', result.amount,
            'confidence', result.confidence,
            'breakdown', result.breakdown,
            'assumptions', result.assumptions,
            'missing_factors', result.missing_factors,
            'reasons', result.reasons
          )
          order by result.method
        ),
        '[]'::jsonb
      )
      from public.valuation_method_results as result
      where result.workspace_id = p_workspace_id
        and result.valuation_case_id = p_valuation_case_id
    ),
    'opinion', (
      select jsonb_build_object(
        'is_available', opinion.is_available,
        'amount', opinion.amount,
        'confidence', opinion.confidence,
        'weights', opinion.weights,
        'rationale', opinion.rationale,
        'unavailable_methods', opinion.unavailable_methods
      )
      from public.market_value_opinions as opinion
      where opinion.workspace_id = p_workspace_id
        and opinion.valuation_case_id = p_valuation_case_id
    )
  );

  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_report.publish', 'valuation_report', p_valuation_case_id,
    null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.publish_valuation_report(
  uuid, uuid, bigint, jsonb, jsonb, uuid, uuid, text
) owner to postgres;
revoke all on function public.publish_valuation_report(
  uuid, uuid, bigint, jsonb, jsonb, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.publish_valuation_report(
  uuid, uuid, bigint, jsonb, jsonb, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- upsert_valuation_reference_data: workspace override of a reference entry.
-- -----------------------------------------------------------------------------

create function public.upsert_valuation_reference_data(
  p_workspace_id uuid,
  p_key text,
  p_payload jsonb,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_source text default null,
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
  v_key text := lower(btrim(coalesce(p_key, '')));
  v_request_hash bytea;
  v_claim jsonb;
  v_existing public.valuation_reference_data%rowtype;
  v_entry public.valuation_reference_data%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if v_key !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
     or char_length(v_key) not between 2 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Reference key is invalid', 'field', 'key'
      )
    );
  end if;

  if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Reference payload must be an object',
        'field', 'payload'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_valuation_reference_data',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'key', v_key,
        'payload', p_payload,
        'source', p_source,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_reference_data'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select entry.*
  into v_existing
  from public.valuation_reference_data as entry
  where entry.workspace_id = p_workspace_id
    and entry.key = v_key
  for update;

  if found then
    update public.valuation_reference_data as entry
    set
      payload = p_payload,
      source = p_source,
      updated_at = now(),
      updated_by = v_actor_id,
      version = entry.version + 1
    where entry.id = v_existing.id
    returning * into v_entry;

    v_old_values := jsonb_build_object(
      'id', v_existing.id,
      'workspace_id', v_existing.workspace_id,
      'key', v_existing.key,
      'payload', v_existing.payload,
      'source', v_existing.source,
      'version', v_existing.version
    );
  else
    insert into public.valuation_reference_data (
      workspace_id, key, payload, source, created_by, updated_by
    ) values (
      p_workspace_id, v_key, p_payload, p_source, v_actor_id, v_actor_id
    )
    returning * into v_entry;

    v_old_values := null;
  end if;

  v_new_values := jsonb_build_object(
    'id', v_entry.id,
    'workspace_id', v_entry.workspace_id,
    'key', v_entry.key,
    'payload', v_entry.payload,
    'source', v_entry.source,
    'created_at', v_entry.created_at,
    'updated_at', v_entry.updated_at,
    'created_by', v_entry.created_by,
    'updated_by', v_entry.updated_by,
    'version', v_entry.version
  );

  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_old_values is null
      then 'valuation_reference_data.create'
      else 'valuation_reference_data.update'
    end,
    'valuation_reference_data', v_entry.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.upsert_valuation_reference_data(
  uuid, text, jsonb, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.upsert_valuation_reference_data(
  uuid, text, jsonb, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_valuation_reference_data(
  uuid, text, jsonb, uuid, uuid, text, text
) to authenticated;
