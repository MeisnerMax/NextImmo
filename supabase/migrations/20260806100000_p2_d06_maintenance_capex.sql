-- P2-D06 (Welle 4): maintenance_capex — MaintenanceTicket (AGG-008) and
-- CapExProject (AGG-009), the two aggregates DOM-005 covers.
--
-- The mutation surface mirrors P2-D02/P2-D03/P2-D04/P2-D05 exactly: enveloped
-- {ok,entity}/{ok:false,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events (no separate history table — audit_events alone
-- satisfies AGG-008's "jede Statusaenderung erzeugt Historie und Audit", the
-- same precedent P2-D05 set for lease status changes), default-deny RLS,
-- reject_protected_column_update, and one shared command gate / claim / finish
-- helper trio per domain instead of per-RPC boilerplate.
--
-- Design decisions:
--
-- * Contractor = existing Party role (P2-D02's party_contractor_details ships
--   trade/rate/ratings/insurance in full already). Both tables carry a
--   nullable contractor_party_id validated against an open contractor role,
--   replacing the legacy free-text vendor_name/owner columns. No new
--   contractor schema in this migration.
-- * Status transitions are STM-006 (MaintenanceTicket) and STM-007
--   (CapExProject) exactly, server-enforced via a *_status_transition_allowed
--   helper, same shape as private.lease_status_transition_allowed. Ticket
--   reopen (resolved -> in_progress) is the one back-edge STM-006 allows;
--   STM-007 has none ("Abschluss ersetzt keine Abrechnung" reads as
--   one-directional).
-- * AGG-008: entering a closed state (resolved/invoiced/archived) stamps
--   resolved_at; reopening clears it. cost_estimate/cost_actual are never
--   negative.
-- * AGG-009: "Freigabe ist akteurs- und zeitbezogen" -> entering 'approved'
--   stamps approved_by/approved_at and requires the separate capex.approve
--   permission, mirroring valuation.approve in P2-D07. Budget, forecast and
--   actual stay three distinct columns, never conflated.
-- * Money is numeric + currency_code (DEC-011), same ISO-3 check and
--   required-iff-amount-present pattern as units/leases.
-- * New permission keys (maintenance.read, maintenance.manage, capex.read,
--   capex.manage, capex.approve) are referenced only, not seeded here — this
--   repo's public.permissions is deliberately not seeded by migrations so
--   pgTAP fixtures can insert their own rows without colliding on
--   permissions_key_unique (see supabase/seed.sql). They are added to
--   seed.sql's local-dev catalogue in this change.
-- * document_link_entity_type already forward-declared 'maintenance_ticket'
--   and 'capex_project' in P2-D03, but private.document_entity_ref_state has
--   returned 'unmigrated' for them ever since. This migration adds the two
--   branches now that the tables exist. 'unit'/'lease' are left untouched —
--   they are in the identical situation since P2-D05 shipped and were never
--   unblocked; that is a pre-existing P2-D05 gap, out of scope here, and is
--   flagged in 00_phase_2_status.md rather than fixed silently.

-- -----------------------------------------------------------------------------
-- Status enums.
-- -----------------------------------------------------------------------------

-- STM-006: new -> triage -> quote_requested -> commissioned -> scheduled ->
-- in_progress -> waiting -> resolved -> invoiced -> archived, with the one
-- reopen edge resolved -> in_progress.
create type public.maintenance_ticket_status as enum (
  'new',
  'triage',
  'quote_requested',
  'commissioned',
  'scheduled',
  'in_progress',
  'waiting',
  'resolved',
  'invoiced',
  'archived'
);

-- STM-007: idea -> planned -> quote_requested -> approved -> in_progress ->
-- completed -> invoiced -> archived. No reopen.
create type public.capex_project_status as enum (
  'idea',
  'planned',
  'quote_requested',
  'approved',
  'in_progress',
  'completed',
  'invoiced',
  'archived'
);

-- -----------------------------------------------------------------------------
-- maintenance_tickets
-- -----------------------------------------------------------------------------

create table public.maintenance_tickets (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  unit_id uuid,
  title text not null,
  description text,
  category text not null default 'general',
  status public.maintenance_ticket_status not null default 'new',
  priority text not null default 'normal',
  reported_at timestamptz not null default now(),
  due_at timestamptz,
  resolved_at timestamptz,
  cost_estimate numeric,
  cost_actual numeric,
  currency_code text,
  contractor_party_id uuid,
  damage_location text,
  insurance_case boolean not null default false,
  insurance_status text,
  insurance_claim_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint maintenance_tickets_workspace_id_key unique (workspace_id, id),
  constraint maintenance_tickets_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  -- See P2-D05 header: composite FK is impossible against public.properties
  -- today; private.leasing_property_in_workspace stands in for it.
  constraint maintenance_tickets_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint maintenance_tickets_unit_fkey foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  constraint maintenance_tickets_contractor_fkey
    foreign key (workspace_id, contractor_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint maintenance_tickets_title_check check (
    char_length(btrim(title)) between 1 and 200
  ),
  constraint maintenance_tickets_description_check check (
    description is null or char_length(description) <= 10000
  ),
  constraint maintenance_tickets_category_check check (
    char_length(btrim(category)) between 1 and 100
  ),
  constraint maintenance_tickets_priority_check check (
    priority in ('low', 'normal', 'high', 'urgent')
  ),
  constraint maintenance_tickets_cost_estimate_check check (
    cost_estimate is null or (cost_estimate >= 0 and cost_estimate <> 'NaN'::numeric)
  ),
  constraint maintenance_tickets_cost_actual_check check (
    cost_actual is null or (cost_actual >= 0 and cost_actual <> 'NaN'::numeric)
  ),
  -- DEC-011: a money amount never exists without its currency.
  constraint maintenance_tickets_currency_code_check check (
    currency_code is null or currency_code ~ '^[A-Z]{3}$'
  ),
  constraint maintenance_tickets_currency_required_check check (
    currency_code is not null or (cost_estimate is null and cost_actual is null)
  ),
  constraint maintenance_tickets_damage_location_check check (
    damage_location is null or char_length(damage_location) <= 2000
  ),
  constraint maintenance_tickets_insurance_status_check check (
    insurance_status is null or char_length(btrim(insurance_status)) between 1 and 100
  ),
  constraint maintenance_tickets_insurance_claim_number_check check (
    insurance_claim_number is null or char_length(insurance_claim_number) <= 200
  ),
  -- AGG-008: closed states carry a resolution timestamp, open states don't.
  constraint maintenance_tickets_resolved_marker_check check (
    (status in ('resolved', 'invoiced', 'archived')) = (resolved_at is not null)
  ),
  constraint maintenance_tickets_version_check check (version >= 1)
);

create index maintenance_tickets_workspace_idx
  on public.maintenance_tickets (workspace_id);
-- property_id leads so this index also covers maintenance_tickets_property_fkey
-- (same reasoning as units_property_idx in P2-D05).
create index maintenance_tickets_property_idx
  on public.maintenance_tickets (property_id, workspace_id);
create index maintenance_tickets_unit_idx
  on public.maintenance_tickets (workspace_id, unit_id)
  where unit_id is not null;
create index maintenance_tickets_status_idx
  on public.maintenance_tickets (workspace_id, status);
-- Due/overdue dashboards read open tickets ordered by due date, matching the
-- legacy createDueNotifications sweep.
create index maintenance_tickets_due_idx
  on public.maintenance_tickets (workspace_id, due_at)
  where due_at is not null and status not in ('resolved', 'invoiced', 'archived');
create index maintenance_tickets_contractor_idx
  on public.maintenance_tickets (workspace_id, contractor_party_id)
  where contractor_party_id is not null;

create trigger maintenance_tickets_protected_columns
before update on public.maintenance_tickets
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'created_at', 'created_by'
);

alter table public.maintenance_tickets enable row level security;
alter table public.maintenance_tickets force row level security;

create policy maintenance_tickets_select_maintenance_read
on public.maintenance_tickets
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'maintenance.read'));

revoke all on table public.maintenance_tickets from anon, authenticated;
grant select on table public.maintenance_tickets to authenticated;

-- -----------------------------------------------------------------------------
-- capex_projects
-- -----------------------------------------------------------------------------

create table public.capex_projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  project_code text not null,
  category text,
  measure text,
  status public.capex_project_status not null default 'idea',
  start_date date,
  planned_end_date date,
  actual_end_date date,
  budget_amount numeric,
  forecast_amount numeric,
  actual_amount numeric,
  currency_code text,
  contractor_party_id uuid,
  owner text,
  next_step text,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint capex_projects_workspace_id_key unique (workspace_id, id),
  constraint capex_projects_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint capex_projects_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint capex_projects_contractor_fkey
    foreign key (workspace_id, contractor_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint capex_projects_project_code_check check (
    char_length(btrim(project_code)) between 1 and 100
  ),
  constraint capex_projects_category_check check (
    category is null or char_length(btrim(category)) between 1 and 100
  ),
  constraint capex_projects_measure_check check (
    measure is null or char_length(measure) <= 2000
  ),
  constraint capex_projects_budget_check check (
    budget_amount is null or (budget_amount >= 0 and budget_amount <> 'NaN'::numeric)
  ),
  constraint capex_projects_forecast_check check (
    forecast_amount is null or (forecast_amount >= 0 and forecast_amount <> 'NaN'::numeric)
  ),
  constraint capex_projects_actual_check check (
    actual_amount is null or (actual_amount >= 0 and actual_amount <> 'NaN'::numeric)
  ),
  -- DEC-011: a money amount never exists without its currency.
  constraint capex_projects_currency_code_check check (
    currency_code is null or currency_code ~ '^[A-Z]{3}$'
  ),
  constraint capex_projects_currency_required_check check (
    currency_code is not null
    or (budget_amount is null and forecast_amount is null and actual_amount is null)
  ),
  constraint capex_projects_owner_check check (
    owner is null or char_length(btrim(owner)) between 1 and 200
  ),
  constraint capex_projects_next_step_check check (
    next_step is null or char_length(next_step) <= 2000
  ),
  constraint capex_projects_planned_end_check check (
    planned_end_date is null or start_date is null or planned_end_date >= start_date
  ),
  constraint capex_projects_actual_end_check check (
    actual_end_date is null or start_date is null or actual_end_date >= start_date
  ),
  -- AGG-009: "Freigabe ist akteurs- und zeitbezogen" — approved-or-later
  -- states carry who/when approved it; earlier states don't.
  constraint capex_projects_approved_marker_check check (
    (status in ('approved', 'in_progress', 'completed', 'invoiced', 'archived'))
    = (approved_by is not null and approved_at is not null)
  ),
  constraint capex_projects_version_check check (version >= 1)
);

create index capex_projects_workspace_idx on public.capex_projects (workspace_id);
create index capex_projects_property_idx
  on public.capex_projects (property_id, workspace_id);
create index capex_projects_status_idx on public.capex_projects (workspace_id, status);
-- CapEx pipeline dashboards read open projects ordered by planned end date.
create index capex_projects_planned_end_idx
  on public.capex_projects (workspace_id, planned_end_date)
  where planned_end_date is not null
    and status not in ('completed', 'invoiced', 'archived');
create index capex_projects_contractor_idx
  on public.capex_projects (workspace_id, contractor_party_id)
  where contractor_party_id is not null;

create trigger capex_projects_protected_columns
before update on public.capex_projects
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'created_at', 'created_by'
);

alter table public.capex_projects enable row level security;
alter table public.capex_projects force row level security;

create policy capex_projects_select_capex_read
on public.capex_projects
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'capex.read'));

revoke all on table public.capex_projects from anon, authenticated;
grant select on table public.capex_projects to authenticated;

-- -----------------------------------------------------------------------------
-- Shared command plumbing: gate, idempotency claim, audit + receipt finish —
-- one implementation for all maintenance_capex mutation RPCs (same shape as
-- private.leasing_command_gate / claim_leasing_mutation / finish_leasing_mutation).
-- -----------------------------------------------------------------------------

create function private.maintenance_command_gate(
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

alter function private.maintenance_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.maintenance_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function private.claim_maintenance_mutation(
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

alter function private.claim_maintenance_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_maintenance_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_maintenance_mutation(
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

alter function private.finish_maintenance_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_maintenance_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

create function private.maintenance_ticket_snapshot(ticket public.maintenance_tickets)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', ticket.id,
    'workspace_id', ticket.workspace_id,
    'property_id', ticket.property_id,
    'unit_id', ticket.unit_id,
    'title', ticket.title,
    'description', ticket.description,
    'category', ticket.category,
    'status', ticket.status,
    'priority', ticket.priority,
    'reported_at', ticket.reported_at,
    'due_at', ticket.due_at,
    'resolved_at', ticket.resolved_at,
    'cost_estimate', ticket.cost_estimate,
    'cost_actual', ticket.cost_actual,
    'currency_code', ticket.currency_code,
    'contractor_party_id', ticket.contractor_party_id,
    'damage_location', ticket.damage_location,
    'insurance_case', ticket.insurance_case,
    'insurance_status', ticket.insurance_status,
    'insurance_claim_number', ticket.insurance_claim_number,
    'created_at', ticket.created_at,
    'updated_at', ticket.updated_at,
    'created_by', ticket.created_by,
    'updated_by', ticket.updated_by,
    'version', ticket.version
  );
$$;

alter function private.maintenance_ticket_snapshot(public.maintenance_tickets)
  owner to postgres;

create function private.capex_project_snapshot(project public.capex_projects)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', project.id,
    'workspace_id', project.workspace_id,
    'property_id', project.property_id,
    'project_code', project.project_code,
    'category', project.category,
    'measure', project.measure,
    'status', project.status,
    'start_date', project.start_date,
    'planned_end_date', project.planned_end_date,
    'actual_end_date', project.actual_end_date,
    'budget_amount', project.budget_amount,
    'forecast_amount', project.forecast_amount,
    'actual_amount', project.actual_amount,
    'currency_code', project.currency_code,
    'contractor_party_id', project.contractor_party_id,
    'owner', project.owner,
    'next_step', project.next_step,
    'approved_by', project.approved_by,
    'approved_at', project.approved_at,
    'created_at', project.created_at,
    'updated_at', project.updated_at,
    'created_by', project.created_by,
    'updated_by', project.updated_by,
    'version', project.version
  );
$$;

alter function private.capex_project_snapshot(public.capex_projects) owner to postgres;

-- The contractor is a Party role (AGG-005 / P2-D02), so a ticket/project may
-- only name a party that actually carries an open contractor role.
create function private.maintenance_contractor_party_valid(
  p_workspace_id uuid,
  p_contractor_party_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.parties as party
    join public.party_roles as party_role
      on party_role.workspace_id = party.workspace_id
      and party_role.party_id = party.id
    where party.workspace_id = p_workspace_id
      and party.id = p_contractor_party_id
      and party.deleted_at is null
      and party_role.role_type = 'contractor'::public.party_role_type
      and party_role.valid_until is null
  );
$$;

alter function private.maintenance_contractor_party_valid(uuid, uuid) owner to postgres;
revoke all on function private.maintenance_contractor_party_valid(uuid, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- maintenance_tickets(): read RPC, maintenance.read-gated, filterable by
-- unit/status/priority.
-- -----------------------------------------------------------------------------

create function public.maintenance_tickets(
  p_workspace_id uuid,
  p_property_id uuid,
  p_unit_id uuid default null,
  p_status text default null,
  p_priority text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
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
$$;

alter function public.maintenance_tickets(uuid, uuid, uuid, text, text) owner to postgres;
revoke all on function public.maintenance_tickets(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.maintenance_tickets(uuid, uuid, uuid, text, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- create_maintenance_ticket
-- -----------------------------------------------------------------------------

create function public.create_maintenance_ticket(
  p_workspace_id uuid,
  p_property_id uuid,
  p_title text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_unit_id uuid default null,
  p_description text default null,
  p_category text default 'general',
  p_priority text default 'normal',
  p_due_at timestamptz default null,
  p_cost_estimate numeric default null,
  p_currency_code text default null,
  p_contractor_party_id uuid default null,
  p_damage_location text default null,
  p_insurance_case boolean default false,
  p_insurance_status text default null,
  p_insurance_claim_number text default null,
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
  v_ticket public.maintenance_tickets%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_title is null or char_length(btrim(p_title)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is required', 'field', 'title'
      )
    );
  end if;

  if coalesce(p_priority, 'normal') not in ('low', 'normal', 'high', 'urgent') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported priority', 'field', 'priority'
      )
    );
  end if;

  if p_cost_estimate is not null and p_cost_estimate < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Cost estimate must not be negative',
        'field', 'cost_estimate'
      )
    );
  end if;

  if p_cost_estimate is not null
     and (p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A cost estimate requires a three-letter ISO currency',
        'field', 'currency_code'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance management is not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if p_unit_id is not null and not exists (
    select 1 from public.units as unit
    where unit.workspace_id = p_workspace_id and unit.id = p_unit_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found')
    );
  end if;

  if p_contractor_party_id is not null
     and not private.maintenance_contractor_party_valid(p_workspace_id, p_contractor_party_id)
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The party does not hold an open contractor role',
        'field', 'contractor_party_id'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_maintenance_ticket',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'unit_id', p_unit_id,
        'title', btrim(p_title),
        'description', p_description,
        'category', coalesce(p_category, 'general'),
        'priority', coalesce(p_priority, 'normal'),
        'due_at', p_due_at,
        'cost_estimate', p_cost_estimate,
        'currency_code', p_currency_code,
        'contractor_party_id', p_contractor_party_id,
        'damage_location', p_damage_location,
        'insurance_case', coalesce(p_insurance_case, false),
        'insurance_status', p_insurance_status,
        'insurance_claim_number', p_insurance_claim_number,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'maintenance_ticket'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.maintenance_tickets (
    workspace_id, property_id, unit_id, title, description, category, status,
    priority, due_at, cost_estimate, currency_code, contractor_party_id,
    damage_location, insurance_case, insurance_status, insurance_claim_number,
    created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, p_unit_id, btrim(p_title),
    nullif(p_description, ''), coalesce(nullif(btrim(p_category), ''), 'general'),
    'new', coalesce(p_priority, 'normal'), p_due_at, p_cost_estimate, p_currency_code,
    p_contractor_party_id, nullif(p_damage_location, ''), coalesce(p_insurance_case, false),
    nullif(p_insurance_status, ''), nullif(p_insurance_claim_number, ''),
    v_actor_id, v_actor_id
  )
  returning * into v_ticket;

  v_new_values := private.maintenance_ticket_snapshot(v_ticket);

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'maintenance_ticket.create', 'maintenance_ticket', v_ticket.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_maintenance_ticket(
  uuid, uuid, text, uuid, uuid, uuid, text, text, text, timestamptz, numeric, text,
  uuid, text, boolean, text, text, text
) owner to postgres;
revoke all on function public.create_maintenance_ticket(
  uuid, uuid, text, uuid, uuid, uuid, text, text, text, timestamptz, numeric, text,
  uuid, text, boolean, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_maintenance_ticket(
  uuid, uuid, text, uuid, uuid, uuid, text, text, text, timestamptz, numeric, text,
  uuid, text, boolean, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_maintenance_ticket: attribute changes only. Status changes go
-- through transition_maintenance_ticket_status.
-- -----------------------------------------------------------------------------

create function public.update_maintenance_ticket(
  p_workspace_id uuid,
  p_maintenance_ticket_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_title text default null,
  p_description text default null,
  p_category text default null,
  p_priority text default null,
  p_due_at timestamptz default null,
  p_cost_estimate numeric default null,
  p_cost_actual numeric default null,
  p_currency_code text default null,
  p_contractor_party_id uuid default null,
  p_damage_location text default null,
  p_insurance_case boolean default null,
  p_insurance_status text default null,
  p_insurance_claim_number text default null,
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
  v_old public.maintenance_tickets%rowtype;
  v_new public.maintenance_tickets%rowtype;
  v_title text;
  v_category text;
  v_priority text;
  v_currency_code text;
  v_new_values jsonb;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_maintenance_ticket_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Ticket id and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance management is not permitted'
      )
    );
  end if;

  select *
  into v_old
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and ticket.id = p_maintenance_ticket_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Ticket not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Ticket version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.maintenance_ticket_snapshot(v_old)
      )
    );
  end if;

  v_title := coalesce(p_title, v_old.title);
  v_category := coalesce(p_category, v_old.category);
  v_priority := coalesce(p_priority, v_old.priority);
  v_currency_code := coalesce(p_currency_code, v_old.currency_code);

  if char_length(btrim(v_title)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is required', 'field', 'title'
      )
    );
  end if;

  if v_priority not in ('low', 'normal', 'high', 'urgent') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unsupported priority', 'field', 'priority'
      )
    );
  end if;

  if p_contractor_party_id is not null
     and not private.maintenance_contractor_party_valid(p_workspace_id, p_contractor_party_id)
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The party does not hold an open contractor role',
        'field', 'contractor_party_id'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_maintenance_ticket',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'maintenance_ticket_id', p_maintenance_ticket_id,
        'expected_version', p_expected_version,
        'title', v_title,
        'description', p_description,
        'category', v_category,
        'priority', v_priority,
        'due_at', p_due_at,
        'cost_estimate', p_cost_estimate,
        'cost_actual', p_cost_actual,
        'currency_code', v_currency_code,
        'contractor_party_id', p_contractor_party_id,
        'damage_location', p_damage_location,
        'insurance_case', p_insurance_case,
        'insurance_status', p_insurance_status,
        'insurance_claim_number', p_insurance_claim_number,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'maintenance_ticket'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  update public.maintenance_tickets
  set
    title = btrim(v_title),
    description = coalesce(nullif(p_description, ''), description),
    category = btrim(v_category),
    priority = v_priority,
    due_at = coalesce(p_due_at, due_at),
    cost_estimate = coalesce(p_cost_estimate, cost_estimate),
    cost_actual = coalesce(p_cost_actual, cost_actual),
    currency_code = v_currency_code,
    contractor_party_id = coalesce(p_contractor_party_id, contractor_party_id),
    damage_location = coalesce(nullif(p_damage_location, ''), damage_location),
    insurance_case = coalesce(p_insurance_case, insurance_case),
    insurance_status = coalesce(nullif(p_insurance_status, ''), insurance_status),
    insurance_claim_number =
      coalesce(nullif(p_insurance_claim_number, ''), insurance_claim_number),
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_maintenance_ticket_id
  returning * into v_new;

  v_new_values := private.maintenance_ticket_snapshot(v_new);

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'maintenance_ticket.update', 'maintenance_ticket', v_new.id,
    private.maintenance_ticket_snapshot(v_old), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.update_maintenance_ticket(
  uuid, uuid, bigint, uuid, uuid, text, text, text, text, timestamptz, numeric, numeric,
  text, uuid, text, boolean, text, text, text
) owner to postgres;
revoke all on function public.update_maintenance_ticket(
  uuid, uuid, bigint, uuid, uuid, text, text, text, text, timestamptz, numeric, numeric,
  text, uuid, text, boolean, text, text, text
) from public, anon, authenticated;
grant execute on function public.update_maintenance_ticket(
  uuid, uuid, bigint, uuid, uuid, text, text, text, text, timestamptz, numeric, numeric,
  text, uuid, text, boolean, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- transition_maintenance_ticket_status
-- -----------------------------------------------------------------------------

create function private.maintenance_ticket_status_transition_allowed(
  p_from public.maintenance_ticket_status,
  p_to public.maintenance_ticket_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    -- The one reopen edge STM-006 allows.
    when p_from = 'resolved'::public.maintenance_ticket_status
      then p_to in (
        'in_progress'::public.maintenance_ticket_status,
        'invoiced'::public.maintenance_ticket_status
      )
    when p_from = 'new'::public.maintenance_ticket_status
      then p_to = 'triage'::public.maintenance_ticket_status
    when p_from = 'triage'::public.maintenance_ticket_status
      then p_to = 'quote_requested'::public.maintenance_ticket_status
    when p_from = 'quote_requested'::public.maintenance_ticket_status
      then p_to = 'commissioned'::public.maintenance_ticket_status
    when p_from = 'commissioned'::public.maintenance_ticket_status
      then p_to = 'scheduled'::public.maintenance_ticket_status
    when p_from = 'scheduled'::public.maintenance_ticket_status
      then p_to = 'in_progress'::public.maintenance_ticket_status
    when p_from = 'in_progress'::public.maintenance_ticket_status
      then p_to in (
        'waiting'::public.maintenance_ticket_status,
        'resolved'::public.maintenance_ticket_status
      )
    when p_from = 'waiting'::public.maintenance_ticket_status
      then p_to = 'in_progress'::public.maintenance_ticket_status
    when p_from = 'invoiced'::public.maintenance_ticket_status
      then p_to = 'archived'::public.maintenance_ticket_status
    else false
  end;
$$;

alter function private.maintenance_ticket_status_transition_allowed(
  public.maintenance_ticket_status, public.maintenance_ticket_status
) owner to postgres;

create function public.transition_maintenance_ticket_status(
  p_workspace_id uuid,
  p_maintenance_ticket_id uuid,
  p_expected_version bigint,
  p_target_status public.maintenance_ticket_status,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_cost_actual numeric default null,
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
  v_old public.maintenance_tickets%rowtype;
  v_new public.maintenance_tickets%rowtype;
  v_resolved_at timestamptz;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_maintenance_ticket_id is null or p_expected_version is null
     or p_target_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Ticket id, expected version and target status are required'
      )
    );
  end if;

  if p_cost_actual is not null and p_cost_actual < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Actual cost must not be negative',
        'field', 'cost_actual'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_maintenance_ticket_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'maintenance_ticket_id', p_maintenance_ticket_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'cost_actual', p_cost_actual,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'maintenance_ticket'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and ticket.id = p_maintenance_ticket_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Ticket not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Ticket version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.maintenance_ticket_snapshot(v_old)
      )
    );
  end if;

  if not private.maintenance_ticket_status_transition_allowed(v_old.status, p_target_status) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'STM-006 does not allow %s -> %s', v_old.status, p_target_status
        ),
        'field', 'target_status',
        'current_status', v_old.status
      )
    );
  end if;

  -- AGG-008: resolved_at is stamped on entering a closed state and cleared on
  -- reopen; it stays put on the invoiced->archived forward move.
  v_resolved_at := case
    when p_target_status in (
      'resolved'::public.maintenance_ticket_status,
      'invoiced'::public.maintenance_ticket_status,
      'archived'::public.maintenance_ticket_status
    ) then coalesce(v_old.resolved_at, now())
    else null
  end;

  update public.maintenance_tickets
  set
    status = p_target_status,
    resolved_at = v_resolved_at,
    cost_actual = coalesce(p_cost_actual, cost_actual),
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_maintenance_ticket_id
  returning * into v_new;

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'maintenance_ticket.transition_status', 'maintenance_ticket', v_new.id,
    private.maintenance_ticket_snapshot(v_old), private.maintenance_ticket_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.maintenance_ticket_snapshot(v_new));
end;
$$;

alter function public.transition_maintenance_ticket_status(
  uuid, uuid, bigint, public.maintenance_ticket_status, uuid, uuid, numeric, text
) owner to postgres;
revoke all on function public.transition_maintenance_ticket_status(
  uuid, uuid, bigint, public.maintenance_ticket_status, uuid, uuid, numeric, text
) from public, anon, authenticated;
grant execute on function public.transition_maintenance_ticket_status(
  uuid, uuid, bigint, public.maintenance_ticket_status, uuid, uuid, numeric, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- capex_projects(): read RPC, capex.read-gated.
-- -----------------------------------------------------------------------------

create function public.capex_projects(
  p_workspace_id uuid,
  p_property_id uuid,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
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

  select coalesce(jsonb_agg(private.capex_project_snapshot(project)
                            order by project.created_at desc), '[]'::jsonb)
  into v_projects
  from public.capex_projects as project
  where project.workspace_id = p_workspace_id
    and project.property_id = p_property_id
    and (p_status is null or project.status::text = p_status);

  return jsonb_build_object('ok', true, 'entity', v_projects);
end;
$$;

alter function public.capex_projects(uuid, uuid, text) owner to postgres;
revoke all on function public.capex_projects(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.capex_projects(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- create_capex_project
-- -----------------------------------------------------------------------------

create function public.create_capex_project(
  p_workspace_id uuid,
  p_property_id uuid,
  p_project_code text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_category text default null,
  p_measure text default null,
  p_start_date date default null,
  p_planned_end_date date default null,
  p_budget_amount numeric default null,
  p_forecast_amount numeric default null,
  p_currency_code text default null,
  p_contractor_party_id uuid default null,
  p_owner text default null,
  p_next_step text default null,
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
  v_project public.capex_projects%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_project_code is null or char_length(btrim(p_project_code)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Project code is required',
        'field', 'project_code'
      )
    );
  end if;

  if p_planned_end_date is not null and p_start_date is not null
     and p_planned_end_date < p_start_date then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Planned end date must not precede the start date',
        'field', 'planned_end_date'
      )
    );
  end if;

  if (p_budget_amount is not null and p_budget_amount < 0)
     or (p_forecast_amount is not null and p_forecast_amount < 0) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Budget and forecast must not be negative'
      )
    );
  end if;

  if (p_budget_amount is not null or p_forecast_amount is not null)
     and (p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A budget or forecast requires a three-letter ISO currency',
        'field', 'currency_code'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'capex.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'CapEx management is not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if p_contractor_party_id is not null
     and not private.maintenance_contractor_party_valid(p_workspace_id, p_contractor_party_id)
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The party does not hold an open contractor role',
        'field', 'contractor_party_id'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_capex_project',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'project_code', btrim(p_project_code),
        'category', p_category,
        'measure', p_measure,
        'start_date', p_start_date,
        'planned_end_date', p_planned_end_date,
        'budget_amount', p_budget_amount,
        'forecast_amount', p_forecast_amount,
        'currency_code', p_currency_code,
        'contractor_party_id', p_contractor_party_id,
        'owner', p_owner,
        'next_step', p_next_step,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'capex_project'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.capex_projects (
    workspace_id, property_id, project_code, category, measure, status,
    start_date, planned_end_date, budget_amount, forecast_amount, currency_code,
    contractor_party_id, owner, next_step, created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, btrim(p_project_code), nullif(p_category, ''),
    nullif(p_measure, ''), 'idea', p_start_date, p_planned_end_date, p_budget_amount,
    p_forecast_amount, p_currency_code, p_contractor_party_id, nullif(p_owner, ''),
    nullif(p_next_step, ''), v_actor_id, v_actor_id
  )
  returning * into v_project;

  v_new_values := private.capex_project_snapshot(v_project);

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'capex_project.create', 'capex_project', v_project.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_capex_project(
  uuid, uuid, text, uuid, uuid, text, text, date, date, numeric, numeric, text, uuid,
  text, text, text
) owner to postgres;
revoke all on function public.create_capex_project(
  uuid, uuid, text, uuid, uuid, text, text, date, date, numeric, numeric, text, uuid,
  text, text, text
) from public, anon, authenticated;
grant execute on function public.create_capex_project(
  uuid, uuid, text, uuid, uuid, text, text, date, date, numeric, numeric, text, uuid,
  text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_capex_project: attribute changes only. Status changes (including
-- approval) go through transition_capex_project_status.
-- -----------------------------------------------------------------------------

create function public.update_capex_project(
  p_workspace_id uuid,
  p_capex_project_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_project_code text default null,
  p_category text default null,
  p_measure text default null,
  p_start_date date default null,
  p_planned_end_date date default null,
  p_actual_end_date date default null,
  p_budget_amount numeric default null,
  p_forecast_amount numeric default null,
  p_actual_amount numeric default null,
  p_currency_code text default null,
  p_contractor_party_id uuid default null,
  p_owner text default null,
  p_next_step text default null,
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
  v_old public.capex_projects%rowtype;
  v_new public.capex_projects%rowtype;
  v_project_code text;
  v_currency_code text;
  v_new_values jsonb;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_capex_project_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Project id and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'capex.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'CapEx management is not permitted'
      )
    );
  end if;

  select *
  into v_old
  from public.capex_projects as project
  where project.workspace_id = p_workspace_id
    and project.id = p_capex_project_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Project not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Project version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.capex_project_snapshot(v_old)
      )
    );
  end if;

  v_project_code := coalesce(p_project_code, v_old.project_code);
  v_currency_code := coalesce(p_currency_code, v_old.currency_code);

  if char_length(btrim(v_project_code)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Project code is required',
        'field', 'project_code'
      )
    );
  end if;

  if p_contractor_party_id is not null
     and not private.maintenance_contractor_party_valid(p_workspace_id, p_contractor_party_id)
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The party does not hold an open contractor role',
        'field', 'contractor_party_id'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_capex_project',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'capex_project_id', p_capex_project_id,
        'expected_version', p_expected_version,
        'project_code', v_project_code,
        'category', p_category,
        'measure', p_measure,
        'start_date', p_start_date,
        'planned_end_date', p_planned_end_date,
        'actual_end_date', p_actual_end_date,
        'budget_amount', p_budget_amount,
        'forecast_amount', p_forecast_amount,
        'actual_amount', p_actual_amount,
        'currency_code', v_currency_code,
        'contractor_party_id', p_contractor_party_id,
        'owner', p_owner,
        'next_step', p_next_step,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'capex_project'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  update public.capex_projects
  set
    project_code = btrim(v_project_code),
    category = coalesce(nullif(p_category, ''), category),
    measure = coalesce(nullif(p_measure, ''), measure),
    start_date = coalesce(p_start_date, start_date),
    planned_end_date = coalesce(p_planned_end_date, planned_end_date),
    actual_end_date = coalesce(p_actual_end_date, actual_end_date),
    budget_amount = coalesce(p_budget_amount, budget_amount),
    forecast_amount = coalesce(p_forecast_amount, forecast_amount),
    actual_amount = coalesce(p_actual_amount, actual_amount),
    currency_code = v_currency_code,
    contractor_party_id = coalesce(p_contractor_party_id, contractor_party_id),
    owner = coalesce(nullif(p_owner, ''), owner),
    next_step = coalesce(nullif(p_next_step, ''), next_step),
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_capex_project_id
  returning * into v_new;

  v_new_values := private.capex_project_snapshot(v_new);

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'capex_project.update', 'capex_project', v_new.id,
    private.capex_project_snapshot(v_old), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.update_capex_project(
  uuid, uuid, bigint, uuid, uuid, text, text, text, date, date, date, numeric, numeric,
  numeric, text, uuid, text, text, text
) owner to postgres;
revoke all on function public.update_capex_project(
  uuid, uuid, bigint, uuid, uuid, text, text, text, date, date, date, numeric, numeric,
  numeric, text, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.update_capex_project(
  uuid, uuid, bigint, uuid, uuid, text, text, text, date, date, date, numeric, numeric,
  numeric, text, uuid, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- transition_capex_project_status: STM-007. Approving requires the separate
-- capex.approve permission (guardrail: valuation.approve-class capabilities
-- are distinct from ordinary edit rights).
-- -----------------------------------------------------------------------------

create function private.capex_project_status_transition_allowed(
  p_from public.capex_project_status,
  p_to public.capex_project_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_from = 'idea'::public.capex_project_status
      then p_to = 'planned'::public.capex_project_status
    when p_from = 'planned'::public.capex_project_status
      then p_to = 'quote_requested'::public.capex_project_status
    when p_from = 'quote_requested'::public.capex_project_status
      then p_to = 'approved'::public.capex_project_status
    when p_from = 'approved'::public.capex_project_status
      then p_to = 'in_progress'::public.capex_project_status
    when p_from = 'in_progress'::public.capex_project_status
      then p_to = 'completed'::public.capex_project_status
    when p_from = 'completed'::public.capex_project_status
      then p_to = 'invoiced'::public.capex_project_status
    when p_from = 'invoiced'::public.capex_project_status
      then p_to = 'archived'::public.capex_project_status
    else false
  end;
$$;

alter function private.capex_project_status_transition_allowed(
  public.capex_project_status, public.capex_project_status
) owner to postgres;

create function public.transition_capex_project_status(
  p_workspace_id uuid,
  p_capex_project_id uuid,
  p_expected_version bigint,
  p_target_status public.capex_project_status,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_actual_amount numeric default null,
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
  v_old public.capex_projects%rowtype;
  v_new public.capex_projects%rowtype;
  v_approved_by uuid;
  v_approved_at timestamptz;
begin
  v_gate := private.maintenance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_capex_project_id is null or p_expected_version is null
     or p_target_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Project id, expected version and target status are required'
      )
    );
  end if;

  if p_actual_amount is not null and p_actual_amount < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Actual amount must not be negative',
        'field', 'actual_amount'
      )
    );
  end if;

  if p_target_status = 'approved'::public.capex_project_status then
    if not private.has_workspace_permission(p_workspace_id, 'capex.approve') then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'forbidden', 'message', 'CapEx approval is not permitted'
        )
      );
    end if;
  elsif not private.has_workspace_permission(p_workspace_id, 'capex.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'CapEx management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_capex_project_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'capex_project_id', p_capex_project_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'actual_amount', p_actual_amount,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_maintenance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'capex_project'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.capex_projects as project
  where project.workspace_id = p_workspace_id
    and project.id = p_capex_project_id
  for update;

  if v_old.id is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Project not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Project version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.capex_project_snapshot(v_old)
      )
    );
  end if;

  if not private.capex_project_status_transition_allowed(v_old.status, p_target_status) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format(
          'STM-007 does not allow %s -> %s', v_old.status, p_target_status
        ),
        'field', 'target_status',
        'current_status', v_old.status
      )
    );
  end if;

  if p_actual_amount is not null and v_old.currency_code is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An actual amount requires the project to already carry a currency',
        'field', 'actual_amount'
      )
    );
  end if;

  -- AGG-009: approved-or-later states carry who/when approved it.
  v_approved_by := case when v_old.approved_by is not null then v_old.approved_by
    when p_target_status <> 'idea'::public.capex_project_status
      and p_target_status <> 'planned'::public.capex_project_status
      and p_target_status <> 'quote_requested'::public.capex_project_status
    then v_actor_id else null end;
  v_approved_at := case when v_old.approved_at is not null then v_old.approved_at
    when v_approved_by is not null then now() else null end;

  update public.capex_projects
  set
    status = p_target_status,
    approved_by = v_approved_by,
    approved_at = v_approved_at,
    actual_amount = coalesce(p_actual_amount, actual_amount),
    actual_end_date =
      case when p_target_status = 'completed'::public.capex_project_status
        then coalesce(actual_end_date, current_date)
        else actual_end_date
      end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_capex_project_id
  returning * into v_new;

  perform private.finish_maintenance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'capex_project.transition_status', 'capex_project', v_new.id,
    private.capex_project_snapshot(v_old), private.capex_project_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.capex_project_snapshot(v_new));
end;
$$;

alter function public.transition_capex_project_status(
  uuid, uuid, bigint, public.capex_project_status, uuid, uuid, numeric, text
) owner to postgres;
revoke all on function public.transition_capex_project_status(
  uuid, uuid, bigint, public.capex_project_status, uuid, uuid, numeric, text
) from public, anon, authenticated;
grant execute on function public.transition_capex_project_status(
  uuid, uuid, bigint, public.capex_project_status, uuid, uuid, numeric, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- DUP-013 unblock: document linking now recognises maintenance_ticket and
-- capex_project (the enum has carried them since P2-D03). unit/lease stay
-- 'unmigrated' here on purpose — see the header note.
-- -----------------------------------------------------------------------------

create or replace function private.document_entity_ref_state(
  p_workspace_id uuid,
  p_entity_type public.document_link_entity_type,
  p_entity_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_entity_type = 'workspace' then
    return case
      when exists (
        select 1 from public.workspaces as workspace
        where workspace.id = p_workspace_id and workspace.id = p_entity_id
      ) then 'ok'
      else 'missing'
    end;
  elsif p_entity_type = 'property' then
    return case
      when exists (
        select 1 from public.properties as property
        where property.workspace_id = p_workspace_id and property.id = p_entity_id
      ) then 'ok'
      else 'missing'
    end;
  elsif p_entity_type = 'party' then
    return case
      when exists (
        select 1 from public.parties as party
        where party.workspace_id = p_workspace_id and party.id = p_entity_id
      ) then 'ok'
      else 'missing'
    end;
  elsif p_entity_type = 'maintenance_ticket' then
    return case
      when exists (
        select 1 from public.maintenance_tickets as ticket
        where ticket.workspace_id = p_workspace_id and ticket.id = p_entity_id
      ) then 'ok'
      else 'missing'
    end;
  elsif p_entity_type = 'capex_project' then
    return case
      when exists (
        select 1 from public.capex_projects as project
        where project.workspace_id = p_workspace_id and project.id = p_entity_id
      ) then 'ok'
      else 'missing'
    end;
  end if;

  -- portfolio / unit / lease / scenario arrive with P2-D05 (still open, see
  -- 00_phase_2_status.md) and P2-D08.
  return 'unmigrated';
end;
$$;

alter function private.document_entity_ref_state(
  uuid, public.document_link_entity_type, uuid
) owner to postgres;
revoke all on function private.document_entity_ref_state(
  uuid, public.document_link_entity_type, uuid
) from public, anon, authenticated;
