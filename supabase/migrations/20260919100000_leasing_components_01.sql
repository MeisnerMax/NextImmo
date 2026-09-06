-- LEASING-COMPONENTS-01 (V-2 of the enterprise operations programme).
--
-- Time-versioned rent components per lease. Everything rent-related downstream
-- hangs off this: warm rent (§4 of the brief), service-charge advances and the
-- settlement engine (§8), and the recommendation surface (§12). Until now the
-- three flat columns on `public.leases` — `base_rent_monthly`,
-- `ancillary_charges_monthly`, `parking_other_charges_monthly` — were the only
-- record of what a tenant pays, and they carry no validity period at all. A
-- rent increase overwrote history; there was no date at which the old amount
-- had been correct. That is B-1 of the gap analysis.
--
-- **DEC-029 governs the relationship to those columns and is followed exactly.**
-- They stay. They are not migrated, not shadowed and not deprecated here: they
-- remain the inception figures the lease was signed at. Components are
-- authoritative *per component type* from the moment one exists for that type,
-- and **a gap is a gap** — where no component covers a date, the read function
-- returns no row for that type rather than falling back to the flat column or
-- to zero. A silent fallback is how a missing figure becomes a wrong figure.
-- Callers must distinguish "nothing owed" from "not recorded"; §28 of the brief
-- puts that decision on the server, and this is the server saying it does not
-- know.
--
-- **Non-overlap is a constraint, not a convention.** Two components of the same
-- type covering the same day would make "the rent on 1 March" ambiguous, and
-- an ambiguity the database allows is one the application has to guess about
-- forever. `btree_gist` gives the exclusion constraint the equality operators
-- it needs beside the range overlap. The extension is installed into
-- `extensions`, following `20260907100000_property_lookup_01.sql`, and every
-- operator class is schema-qualified: an unqualified `gist_uuid_ops` resolves
-- through whatever `search_path` the migration happens to run under, which is
-- not something a migration should depend on.
--
-- **Currency is derived, never supplied.** The RPCs read it from the parent
-- lease, so a caller cannot introduce a mismatch, and a trigger holds the
-- invariant afterwards for anything that reaches the table another way. The
-- alternative — a composite foreign key — would have required a new unique
-- constraint on `public.leases`, and this package has no mandate to reshape an
-- existing table.
--
-- **Audit.** Writes go through the existing leasing mutation contract
-- (`private.leasing_command_gate` → `private.claim_leasing_mutation` →
-- `private.finish_leasing_mutation`), so idempotency, optimistic concurrency,
-- correlation and the append-only audit record are the same ones the rest of
-- leasing uses. `finish_leasing_mutation` writes no `parent_entity_*`, which
-- means the property chronicle resolves these rows through the lease, exactly
-- as PROPERTY-ACTIVITY-01 found it must for ten of the twelve audit-writing
-- migrations. The activity taxonomy therefore needs a `lease_component` entry;
-- without one these writes exist and are invisible.
--
-- Counters this migration moves, listed so the pull request has to acknowledge
-- them rather than discover them: SR-20 (public SECURITY DEFINER functions)
-- 82 → 86, SR-22 (client-reachable policies) 49 → 50.

create extension if not exists btree_gist with schema extensions;

-- -----------------------------------------------------------------------------
-- Types
--

-- The five types of the target data model (§4). `other` is deliberately last
-- and deliberately vague: it absorbs what a real contract contains and this
-- list does not, without inviting a schema change for every lease that has a
-- garden levy. It is not a dumping ground for the four named ones — the read
-- contract treats each type independently, so mislabelling one hides it.
create type public.lease_component_type as enum (
  'base_rent',
  'service_charge_advance',
  'heating_advance',
  'parking',
  'other'
);

-- VAT handling is per component and per period, because the rate is a legal
-- fact with a validity date and the component already carries one. A single
-- flag on the lease could not describe a lease that was exempt until an option
-- under §9 UStG was exercised.
create type public.lease_component_vat_mode as enum (
  'exempt',   -- no VAT (the residential default)
  'net',      -- `amount` is net; VAT is added at `vat_rate_percent`
  'gross'     -- `amount` already includes VAT at `vat_rate_percent`
);

-- -----------------------------------------------------------------------------
-- Table
--

create table public.lease_components (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  lease_id uuid not null,
  component_type public.lease_component_type not null,
  valid_from date not null,
  -- Inclusive. Null means open-ended, which is the normal state of a current
  -- component: most rents have a start and no agreed end.
  valid_to date,
  amount numeric(14, 2) not null,
  currency_code text not null,
  vat_mode public.lease_component_vat_mode not null default 'exempt',
  vat_rate_percent numeric(5, 2),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  -- Half-open internally so adjacent periods do not overlap, inclusive at the
  -- edges of the API so `valid_to` reads the way a contract does.
  validity daterange generated always as (
    daterange(
      valid_from,
      case when valid_to is null then null else valid_to + 1 end,
      '[)'
    )
  ) stored,

  constraint lease_components_workspace_id_key unique (workspace_id, id),
  constraint lease_components_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint lease_components_lease_fkey foreign key (workspace_id, lease_id)
    references public.leases (workspace_id, id) on delete restrict,
  constraint lease_components_term_check check (
    valid_to is null or valid_to >= valid_from
  ),
  constraint lease_components_amount_check check (amount >= 0),
  -- A reduction is a lower amount for a period, not a negative line. Two rows
  -- that net out would leave "the rent" depending on which ones you summed.
  constraint lease_components_currency_check check (
    currency_code = upper(btrim(currency_code))
    and char_length(currency_code) = 3
  ),
  constraint lease_components_vat_check check (
    (vat_mode = 'exempt' and coalesce(vat_rate_percent, 0) = 0)
    or (vat_mode <> 'exempt' and vat_rate_percent is not null
        and vat_rate_percent >= 0 and vat_rate_percent <= 100)
  ),
  constraint lease_components_note_check check (
    note is null or char_length(btrim(note)) between 1 and 2000
  ),
  constraint lease_components_version_check check (version >= 1),

  -- The invariant this table exists to hold: for one lease and one component
  -- type, no two rows may cover the same day.
  constraint lease_components_no_overlap exclude using gist (
    workspace_id extensions.gist_uuid_ops with =,
    lease_id extensions.gist_uuid_ops with =,
    component_type extensions.gist_enum_ops with =,
    validity with &&
  )
);

create index lease_components_workspace_idx
  on public.lease_components (workspace_id);
create index lease_components_lease_idx
  on public.lease_components (workspace_id, lease_id, component_type, valid_from);
-- The as-of read filters on the range; gist is what answers that without a
-- sequential scan once a workspace has a few thousand components.
create index lease_components_validity_idx
  on public.lease_components using gist (workspace_id, validity);

comment on table public.lease_components is
  'Time-versioned rent components per lease (LEASING-COMPONENTS-01). '
  'Authoritative per component type from the first row for that type; '
  'a period no row covers is unknown, not zero (DEC-029).';

-- -----------------------------------------------------------------------------
-- Invariants held by trigger
--

-- Currency must equal the parent lease's. The RPCs never take it from the
-- caller, so this catches the paths that do not go through them.
create function private.enforce_lease_component_currency()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_lease_currency text;
begin
  select lease.currency_code into v_lease_currency
  from public.leases as lease
  where lease.workspace_id = new.workspace_id and lease.id = new.lease_id;

  if v_lease_currency is null then
    raise exception 'Lease % does not exist in workspace %',
      new.lease_id, new.workspace_id using errcode = '23503';
  end if;

  if new.currency_code is distinct from v_lease_currency then
    raise exception
      'Component currency % does not match the lease currency %',
      new.currency_code, v_lease_currency using errcode = '23514';
  end if;

  return new;
end;
$function$;

create trigger lease_components_currency_matches_lease
before insert or update on public.lease_components
for each row execute function private.enforce_lease_component_currency();

create trigger lease_components_protected_columns
before update on public.lease_components
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'lease_id', 'component_type', 'created_at', 'created_by'
);

-- -----------------------------------------------------------------------------
-- RLS: default deny, one SELECT policy, no DML policy
--

alter table public.lease_components enable row level security;
alter table public.lease_components force row level security;

create policy lease_components_select_lease_read
on public.lease_components
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'lease.read'));

revoke all on table public.lease_components from public, anon, authenticated;
grant select on table public.lease_components to authenticated;

-- -----------------------------------------------------------------------------
-- Read contract
--

-- Resolves the components in force on a date, for one lease or for every lease
-- of a property. Two filters, both necessary: the component's own validity,
-- and — through `private.lease_is_effective_on` (LEASING-ASOF-01) — whether the
-- lease itself was in force that day. Without the second, a component would
-- keep reporting rent for a lease that had already ended, which is the defect
-- LEASING-ASOF-01 was created to remove from the rent roll.
create function public.lease_components_as_of(
  p_workspace_id uuid,
  p_as_of date default null,
  p_lease_id uuid default null,
  p_property_id uuid default null
)
returns table (
  lease_id uuid,
  property_id uuid,
  component_id uuid,
  component_type public.lease_component_type,
  amount numeric,
  currency_code text,
  vat_mode public.lease_component_vat_mode,
  vat_rate_percent numeric,
  valid_from date,
  valid_to date,
  version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, current_date);
begin
  if p_workspace_id is null then
    raise exception 'Workspace is required' using errcode = '22023';
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  -- One of the two scopes, never neither: an unscoped read would return every
  -- component in the workspace, which is the client-side-full-dataset shape
  -- §27 of the brief forbids.
  if p_lease_id is null and p_property_id is null then
    raise exception 'Either a lease or a property must be given'
      using errcode = '22023';
  end if;

  return query
  select
    lease.id,
    lease.property_id,
    component.id,
    component.component_type,
    component.amount,
    component.currency_code,
    component.vat_mode,
    component.vat_rate_percent,
    component.valid_from,
    component.valid_to,
    component.version
  from public.lease_components as component
  join public.leases as lease
    on lease.workspace_id = component.workspace_id
   and lease.id = component.lease_id
  where component.workspace_id = p_workspace_id
    and (p_lease_id is null or component.lease_id = p_lease_id)
    and (p_property_id is null or lease.property_id = p_property_id)
    and component.validity @> v_as_of
    and private.lease_is_effective_on(
      lease.status, lease.start_date, lease.end_date,
      lease.move_out_date, lease.ended_at, v_as_of
    )
  order by lease.id, component.component_type, component.valid_from;
end;
$function$;

revoke all on function public.lease_components_as_of(uuid, date, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.lease_components_as_of(uuid, date, uuid, uuid)
  to authenticated;

-- -----------------------------------------------------------------------------
-- Write contract
--

create function public.create_lease_component(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_component_type public.lease_component_type,
  p_valid_from date,
  p_amount numeric,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_valid_to date default null,
  p_vat_mode public.lease_component_vat_mode default 'exempt',
  p_vat_rate_percent numeric default null,
  p_note text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_currency text;
  v_property uuid;
  v_new public.lease_components%rowtype;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Not permitted to manage leases'
      )
    );
  end if;

  if p_lease_id is null or p_component_type is null
     or p_valid_from is null or p_amount is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Lease, component type, start date and amount are required'
      )
    );
  end if;

  -- Currency is read here, not accepted: see the header.
  select lease.currency_code, lease.property_id
  into v_currency, v_property
  from public.leases as lease
  where lease.workspace_id = p_workspace_id and lease.id = p_lease_id;

  if v_currency is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Lease not found', 'field', 'leaseId'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    coalesce(p_lease_id::text, '') || '|' ||
    coalesce(p_component_type::text, '') || '|' ||
    coalesce(p_valid_from::text, '') || '|' ||
    coalesce(p_valid_to::text, '') || '|' ||
    coalesce(p_amount::text, '') || '|' ||
    coalesce(p_vat_mode::text, '') || '|' ||
    coalesce(p_vat_rate_percent::text, '') || '|' ||
    coalesce(p_note, ''),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'lease_component'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  begin
    insert into public.lease_components (
      workspace_id, lease_id, component_type, valid_from, valid_to,
      amount, currency_code, vat_mode, vat_rate_percent, note,
      created_by, updated_by
    )
    values (
      p_workspace_id, p_lease_id, p_component_type, p_valid_from, p_valid_to,
      p_amount, v_currency, p_vat_mode, p_vat_rate_percent,
      nullif(btrim(coalesce(p_note, '')), ''),
      v_actor_id, v_actor_id
    )
    returning * into v_new;
  exception
    when exclusion_violation then
      -- The receipt must not survive a rejected command, or the caller's retry
      -- would be answered with a success it never got.
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', 'Another component of this type already covers part of that period',
          'field', 'validFrom'
        )
      );
    when check_violation or foreign_key_violation then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', sqlerrm
        )
      );
  end;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'lease_component.create', 'lease_component', v_new.id,
    null, to_jsonb(v_new)
  );

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_new));
end;
$function$;

-- The one write path for an existing component. Private, and carrying the
-- audit action as a parameter, so that "update" and "close" can be different
-- events in the trail without being different code. A public function with a
-- caller-supplied action would let a client label its own audit record, which
-- is worse than having no label at all.
create function private.apply_lease_component_update(
  p_workspace_id uuid,
  p_component_id uuid,
  p_expected_version bigint,
  p_changes jsonb,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_old public.lease_components%rowtype;
  v_new public.lease_components%rowtype;
  v_unknown_keys text[];
  c_editable constant text[] := array[
    'validFrom', 'validTo', 'amount', 'vatMode', 'vatRatePercent', 'note'
  ];
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Not permitted to manage leases'
      )
    );
  end if;

  if p_component_id is null or p_expected_version is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Component id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object'
     or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'No changes supplied',
        'field', 'changes'
      )
    );
  end if;

  -- An unknown key is refused rather than ignored: a caller that misspells a
  -- field would otherwise be told its change succeeded.
  select array_agg(key) into v_unknown_keys
  from jsonb_object_keys(p_changes) as key
  where key <> all (c_editable);

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unknown fields: ' || array_to_string(v_unknown_keys, ', '),
        'field', 'changes'
      )
    );
  end if;

  select * into v_old
  from public.lease_components
  where workspace_id = p_workspace_id and id = p_component_id;

  if v_old.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Component not found'
      )
    );
  end if;

  if v_old.version <> p_expected_version then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Component was changed by someone else',
        'currentVersion', v_old.version
      )
    );
  end if;

  v_request_hash := extensions.digest(
    p_component_id::text || '|' || p_expected_version::text || '|' ||
    p_changes::text,
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'lease_component'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  begin
    update public.lease_components as component
    set
      valid_from = case when p_changes ? 'validFrom'
        then (p_changes ->> 'validFrom')::date else component.valid_from end,
      valid_to = case when p_changes ? 'validTo'
        then nullif(p_changes ->> 'validTo', '')::date else component.valid_to end,
      amount = case when p_changes ? 'amount'
        then (p_changes ->> 'amount')::numeric else component.amount end,
      vat_mode = case when p_changes ? 'vatMode'
        then (p_changes ->> 'vatMode')::public.lease_component_vat_mode
        else component.vat_mode end,
      vat_rate_percent = case when p_changes ? 'vatRatePercent'
        then nullif(p_changes ->> 'vatRatePercent', '')::numeric
        else component.vat_rate_percent end,
      note = case when p_changes ? 'note'
        then nullif(btrim(coalesce(p_changes ->> 'note', '')), '')
        else component.note end,
      updated_at = now(),
      updated_by = v_actor_id,
      version = component.version + 1
    where component.workspace_id = p_workspace_id and component.id = p_component_id
    returning * into v_new;
  exception
    when exclusion_violation then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', 'The new period would overlap another component of this type',
          'field', 'validFrom'
        )
      );
    when check_violation or invalid_text_representation or datetime_field_overflow then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', sqlerrm
        )
      );
  end;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    p_action, 'lease_component', v_new.id,
    to_jsonb(v_old), to_jsonb(v_new)
  );

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_new));
end;
$function$;

-- SECURITY DEFINER and directly invocable, so PUBLIC's default EXECUTE has to
-- go: SR-09 exists because a privileged helper left open is a way around the
-- command that wraps it.
alter function private.apply_lease_component_update(
  uuid, uuid, bigint, jsonb, uuid, uuid, text, text
) owner to postgres;
revoke all on function private.apply_lease_component_update(
  uuid, uuid, bigint, jsonb, uuid, uuid, text, text
) from public, anon, authenticated;

create function public.update_lease_component(
  p_workspace_id uuid,
  p_component_id uuid,
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
as $function$
declare
  v_gate jsonb;
begin
  -- Gated here as well as inside the shared path. Not defensive duplication:
  -- an entry point whose guard is only visible one call away is one a reader
  -- has to take on trust, and SR-21 declines to.
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  return private.apply_lease_component_update(
    p_workspace_id, p_component_id, p_expected_version, p_changes,
    p_mutation_id, p_correlation_id, p_reason, 'lease_component.update'
  );
end;
$function$;

-- Ends a component on a date rather than deleting it. A rent that was paid
-- until March is a fact about March; removing the row would erase it, and the
-- settlement engine reads history, not just the present.
create function public.close_lease_component(
  p_workspace_id uuid,
  p_component_id uuid,
  p_expected_version bigint,
  p_valid_to date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate jsonb;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_valid_to is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An end date is required to close a component',
        'field', 'validTo'
      )
    );
  end if;

  -- Same write path as an update — one set of conflict rules, one concurrency
  -- check — but its own audit action, because "closed on 31 March" and
  -- "changed the end date" are different things to read in a trail a year
  -- later.
  return private.apply_lease_component_update(
    p_workspace_id, p_component_id, p_expected_version,
    jsonb_build_object('validTo', p_valid_to::text),
    p_mutation_id, p_correlation_id, p_reason, 'lease_component.close'
  );
end;
$function$;

revoke all on function public.create_lease_component(
  uuid, uuid, public.lease_component_type, date, numeric, uuid, uuid, date,
  public.lease_component_vat_mode, numeric, text, text
) from public, anon, authenticated;
grant execute on function public.create_lease_component(
  uuid, uuid, public.lease_component_type, date, numeric, uuid, uuid, date,
  public.lease_component_vat_mode, numeric, text, text
) to authenticated;

revoke all on function public.update_lease_component(
  uuid, uuid, bigint, jsonb, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.update_lease_component(
  uuid, uuid, bigint, jsonb, uuid, uuid, text
) to authenticated;

revoke all on function public.close_lease_component(
  uuid, uuid, bigint, date, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.close_lease_component(
  uuid, uuid, bigint, date, uuid, uuid, text
) to authenticated;
