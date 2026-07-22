-- P2-D02: contacts_parties — canonical Party aggregate (DOM-003, AGG-005).
--
-- Resolves DUP-010 / OPEN-001 (decided 2026-07-22): the parallel legacy
-- contacts / tenants / contractors models collapse into one canonical identity
-- with a shared party id. Functional roles (tenant/contractor/buyer/bank/
-- company) are time-boundable party_roles rows, NOT separate tables; role-
-- specific attributes live in per-role satellite tables joined on parties, not
-- in generic party_roles columns.
--
-- The mutation surface mirrors the P1-004 property contract (enveloped
-- {ok,entity}/{ok,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events, default-deny RLS, reject_protected_column_update)
-- and reuses the P2-D01 shared-helper shape (one command gate / claim / finish
-- pair instead of copying the boilerplate per RPC). Unlike P2-D01 there is NO
-- AAL2 gate: parties are ordinary workspace business data like properties, so
-- access is gated by the party.read / party.manage permissions
-- ("zweckbezogene Berechtigung", DOM-003), matching P1-004's auth+permission
-- gate rather than the membership mutations' AAL2 gate.
--
-- Satellites: only the contractor role carries role-specific legacy attributes
-- (trade category, hourly rate, ratings, insurance expiry), so this migration
-- ships party_contractor_details. tenant/buyer/bank/company have no role-
-- specific attributes yet; their satellites are added when their owning
-- domains migrate (leasing_operations, maintenance_capex, finance_debt).

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

create type public.party_type as enum (
  'person',
  'organization'
);

create type public.party_role_type as enum (
  'tenant',
  'contractor',
  'buyer',
  'bank',
  'company'
);

-- -----------------------------------------------------------------------------
-- parties: canonical identity. PII is minimized to a single email/phone
-- channel (multi-channel is deferred). A merged party is tombstoned
-- (deleted_at set) and points at the survivor via merged_into_party_id.
-- -----------------------------------------------------------------------------

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  party_type public.party_type not null,
  display_name text not null,
  legal_name text,
  email text,
  phone text,
  notes text,
  merged_into_party_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  deleted_at timestamptz,
  constraint parties_workspace_id_key unique (workspace_id, id),
  constraint parties_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint parties_merged_into_fkey foreign key (workspace_id, merged_into_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint parties_display_name_check check (
    char_length(btrim(display_name)) between 1 and 200
  ),
  constraint parties_legal_name_check check (
    legal_name is null or char_length(btrim(legal_name)) between 1 and 200
  ),
  constraint parties_email_normalized_check check (
    email is null or (
      email = lower(btrim(email))
      and char_length(email) between 3 and 320
      and position('@' in email) > 1
    )
  ),
  constraint parties_phone_check check (
    phone is null or char_length(btrim(phone)) between 1 and 50
  ),
  constraint parties_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  constraint parties_version_check check (version >= 1),
  -- A merge always tombstones the source; a live party never carries a target.
  constraint parties_merged_tombstone_check check (
    merged_into_party_id is null or deleted_at is not null
  ),
  constraint parties_not_self_merge_check check (
    merged_into_party_id is null or merged_into_party_id <> id
  )
);

create index parties_workspace_idx on public.parties (workspace_id);
create index parties_merged_into_idx
  on public.parties (workspace_id, merged_into_party_id)
  where merged_into_party_id is not null;
-- Duplicate-detection lookups run on normalized identity within a workspace.
create index parties_email_idx
  on public.parties (workspace_id, email)
  where email is not null and deleted_at is null;
create index parties_display_name_idx
  on public.parties (workspace_id, lower(display_name))
  where deleted_at is null;

create trigger parties_protected_columns
before update on public.parties
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.parties enable row level security;
alter table public.parties force row level security;

create policy parties_select_party_read
on public.parties
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'party.read'));

revoke all on table public.parties from anon, authenticated;
grant select on table public.parties to authenticated;

-- -----------------------------------------------------------------------------
-- party_roles: time-boundable functional roles. At most one open (valid_until
-- null) role of each type per party. party_id is intentionally NOT protected —
-- merge re-points source roles onto the surviving party through the RPC only.
-- -----------------------------------------------------------------------------

create table public.party_roles (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  party_id uuid not null,
  role_type public.party_role_type not null,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint party_roles_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint party_roles_party_fkey foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete cascade,
  constraint party_roles_valid_range_check check (
    valid_until is null or valid_until >= valid_from
  ),
  constraint party_roles_version_check check (version >= 1)
);

create unique index party_roles_open_role_unique
  on public.party_roles (workspace_id, party_id, role_type)
  where valid_until is null;

create index party_roles_party_idx on public.party_roles (workspace_id, party_id);
create index party_roles_role_type_idx
  on public.party_roles (workspace_id, role_type);

create trigger party_roles_protected_columns
before update on public.party_roles
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'role_type', 'created_at', 'created_by'
);

alter table public.party_roles enable row level security;
alter table public.party_roles force row level security;

create policy party_roles_select_party_read
on public.party_roles
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'party.read'));

revoke all on table public.party_roles from anon, authenticated;
grant select on table public.party_roles to authenticated;

-- -----------------------------------------------------------------------------
-- party_contractor_details: per-role satellite for the contractor role, keyed
-- by party_id (joins on parties). Money as numeric.
-- -----------------------------------------------------------------------------

create table public.party_contractor_details (
  party_id uuid primary key,
  workspace_id uuid not null,
  trade_category text not null,
  hourly_rate numeric,
  service_area text,
  rating_price numeric,
  rating_quality numeric,
  rating_speed numeric,
  rating_communication numeric,
  rating_punctuality numeric,
  insurance_cert_expiry date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint party_contractor_details_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint party_contractor_details_party_fkey foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete cascade,
  constraint party_contractor_details_trade_category_check check (
    char_length(btrim(trade_category)) between 1 and 100
  ),
  constraint party_contractor_details_hourly_rate_check check (
    hourly_rate is null or (hourly_rate >= 0 and hourly_rate <> 'NaN'::numeric)
  ),
  constraint party_contractor_details_service_area_check check (
    service_area is null or char_length(service_area) <= 2000
  ),
  constraint party_contractor_details_rating_price_check check (
    rating_price is null or rating_price between 0 and 5
  ),
  constraint party_contractor_details_rating_quality_check check (
    rating_quality is null or rating_quality between 0 and 5
  ),
  constraint party_contractor_details_rating_speed_check check (
    rating_speed is null or rating_speed between 0 and 5
  ),
  constraint party_contractor_details_rating_communication_check check (
    rating_communication is null or rating_communication between 0 and 5
  ),
  constraint party_contractor_details_rating_punctuality_check check (
    rating_punctuality is null or rating_punctuality between 0 and 5
  ),
  constraint party_contractor_details_version_check check (version >= 1)
);

create index party_contractor_details_party_idx
  on public.party_contractor_details (workspace_id, party_id);

create trigger party_contractor_details_protected_columns
before update on public.party_contractor_details
for each row execute function private.reject_protected_column_update(
  'party_id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.party_contractor_details enable row level security;
alter table public.party_contractor_details force row level security;

create policy party_contractor_details_select_party_read
on public.party_contractor_details
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'party.read'));

revoke all on table public.party_contractor_details from anon, authenticated;
grant select on table public.party_contractor_details to authenticated;

-- -----------------------------------------------------------------------------
-- party_aliases: append-only merge history so a merge keeps the source's
-- former identity ("Merge behält Alias-/Audit-Historie"). Written by the merge
-- RPC only; no update path.
-- -----------------------------------------------------------------------------

create table public.party_aliases (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  target_party_id uuid not null,
  source_party_id uuid not null,
  alias_display_name text not null,
  alias_legal_name text,
  alias_email text,
  alias_phone text,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint party_aliases_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint party_aliases_target_fkey foreign key (workspace_id, target_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint party_aliases_source_fkey foreign key (workspace_id, source_party_id)
    references public.parties (workspace_id, id) on delete restrict,
  constraint party_aliases_display_name_check check (
    char_length(btrim(alias_display_name)) between 1 and 200
  ),
  constraint party_aliases_not_self_check check (target_party_id <> source_party_id)
);

create index party_aliases_target_idx
  on public.party_aliases (workspace_id, target_party_id);
create index party_aliases_source_idx
  on public.party_aliases (workspace_id, source_party_id);

alter table public.party_aliases enable row level security;
alter table public.party_aliases force row level security;

create policy party_aliases_select_party_read
on public.party_aliases
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'party.read'));

revoke all on table public.party_aliases from anon, authenticated;
grant select on table public.party_aliases to authenticated;

-- -----------------------------------------------------------------------------
-- Shared private helpers: command envelope validation, idempotency claim,
-- audit + receipt finish, and row snapshots — one implementation for all five
-- party mutation RPCs.
-- -----------------------------------------------------------------------------

create function private.party_command_gate(
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

alter function private.party_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.party_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- Claims the mutation id. Returns null when the caller owns a fresh receipt
-- (proceed), otherwise the deterministic replay result: the recorded success
-- payload, a mutation_conflict, or in_progress.
create function private.claim_party_mutation(
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

alter function private.claim_party_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_party_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_party_mutation(
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

alter function private.finish_party_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_party_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

create function private.party_snapshot(party public.parties)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', party.id,
    'workspace_id', party.workspace_id,
    'party_type', party.party_type,
    'display_name', party.display_name,
    'legal_name', party.legal_name,
    'email', party.email,
    'phone', party.phone,
    'notes', party.notes,
    'merged_into_party_id', party.merged_into_party_id,
    'created_at', party.created_at,
    'updated_at', party.updated_at,
    'created_by', party.created_by,
    'updated_by', party.updated_by,
    'version', party.version,
    'deleted_at', party.deleted_at
  );
$$;

alter function private.party_snapshot(public.parties) owner to postgres;
revoke all on function private.party_snapshot(public.parties)
  from public, anon, authenticated;

create function private.party_role_snapshot(role public.party_roles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', role.id,
    'workspace_id', role.workspace_id,
    'party_id', role.party_id,
    'role_type', role.role_type,
    'valid_from', role.valid_from,
    'valid_until', role.valid_until,
    'created_at', role.created_at,
    'updated_at', role.updated_at,
    'created_by', role.created_by,
    'updated_by', role.updated_by,
    'version', role.version
  );
$$;

alter function private.party_role_snapshot(public.party_roles) owner to postgres;
revoke all on function private.party_role_snapshot(public.party_roles)
  from public, anon, authenticated;

create function private.contractor_details_snapshot(
  details public.party_contractor_details
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'party_id', details.party_id,
    'workspace_id', details.workspace_id,
    'trade_category', details.trade_category,
    'hourly_rate', details.hourly_rate,
    'service_area', details.service_area,
    'rating_price', details.rating_price,
    'rating_quality', details.rating_quality,
    'rating_speed', details.rating_speed,
    'rating_communication', details.rating_communication,
    'rating_punctuality', details.rating_punctuality,
    'insurance_cert_expiry', details.insurance_cert_expiry,
    'is_active', details.is_active,
    'version', details.version
  );
$$;

alter function private.contractor_details_snapshot(public.party_contractor_details)
  owner to postgres;
revoke all on function private.contractor_details_snapshot(public.party_contractor_details)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_party: create a canonical party identity.
-- -----------------------------------------------------------------------------

create function public.create_party(
  p_workspace_id uuid,
  p_party_type text,
  p_display_name text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_legal_name text default null,
  p_email text default null,
  p_phone text default null,
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
  v_email text;
  v_request_hash bytea;
  v_claim jsonb;
  v_party public.parties%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_type is null or p_party_type not in ('person', 'organization') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Party type is invalid', 'field', 'party_type'
      )
    );
  end if;

  if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Display name is required', 'field', 'display_name'
      )
    );
  end if;

  if p_legal_name is not null and char_length(btrim(p_legal_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Legal name is invalid', 'field', 'legal_name'
      )
    );
  end if;

  v_email := lower(btrim(p_email));
  if p_email is not null and (
       char_length(v_email) not between 3 and 320 or position('@' in v_email) <= 1
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Email is invalid', 'field', 'email'
      )
    );
  end if;

  if p_phone is not null and char_length(btrim(p_phone)) not between 1 and 50 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Phone is invalid', 'field', 'phone'
      )
    );
  end if;

  if p_notes is not null and char_length(p_notes) > 10000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Notes are too long', 'field', 'notes'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_party',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'party_type', p_party_type,
        'display_name', btrim(p_display_name),
        'legal_name', p_legal_name,
        'email', p_email,
        'phone', p_phone,
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'party'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.parties (
    workspace_id, party_type, display_name, legal_name, email, phone, notes,
    created_by, updated_by
  ) values (
    p_workspace_id,
    p_party_type::public.party_type,
    btrim(p_display_name),
    nullif(btrim(coalesce(p_legal_name, '')), ''),
    nullif(v_email, ''),
    nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(p_notes, ''),
    v_actor_id, v_actor_id
  )
  returning * into v_party;

  v_new_values := private.party_snapshot(v_party);
  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'party.create', 'party', v_party.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_party(uuid, text, text, uuid, uuid, text, text, text, text, text)
  owner to postgres;
revoke all on function public.create_party(uuid, text, text, uuid, uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_party(uuid, text, text, uuid, uuid, text, text, text, text, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- update_party: edit identity fields with optimistic concurrency. Mirrors
-- update_property.
-- -----------------------------------------------------------------------------

create function public.update_party(
  p_workspace_id uuid,
  p_party_id uuid,
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
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_allowed_keys constant text[] := array[
    'party_type', 'display_name', 'legal_name', 'email', 'phone', 'notes'
  ];
  v_unknown_keys text[];
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.parties%rowtype;
  v_new public.parties%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_replayed jsonb;
  v_email text;
  v_now timestamptz;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Party id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object' or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Changes must be a non-empty object', 'field', 'changes'
      )
    );
  end if;

  select array_agg(change_key order by change_key)
  into v_unknown_keys
  from jsonb_object_keys(p_changes) as change(change_key)
  where not (change_key = any (v_allowed_keys));

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Changes contain unsupported fields',
        'fields', to_jsonb(v_unknown_keys)
      )
    );
  end if;

  if p_changes ? 'party_type' and (
       jsonb_typeof(p_changes -> 'party_type') <> 'string'
       or p_changes ->> 'party_type' not in ('person', 'organization')
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Party type is invalid', 'field', 'party_type'
      )
    );
  end if;

  if p_changes ? 'display_name' and (
       jsonb_typeof(p_changes -> 'display_name') <> 'string'
       or char_length(btrim(p_changes ->> 'display_name')) not between 1 and 200
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Display name is invalid', 'field', 'display_name'
      )
    );
  end if;

  if p_changes ? 'legal_name' and not (
       jsonb_typeof(p_changes -> 'legal_name') = 'null'
       or (
         jsonb_typeof(p_changes -> 'legal_name') = 'string'
         and char_length(btrim(p_changes ->> 'legal_name')) between 1 and 200
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Legal name is invalid', 'field', 'legal_name'
      )
    );
  end if;

  if p_changes ? 'email' and not (
       jsonb_typeof(p_changes -> 'email') = 'null'
       or (
         jsonb_typeof(p_changes -> 'email') = 'string'
         and char_length(lower(btrim(p_changes ->> 'email'))) between 3 and 320
         and position('@' in lower(btrim(p_changes ->> 'email'))) > 1
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Email is invalid', 'field', 'email'
      )
    );
  end if;

  if p_changes ? 'phone' and not (
       jsonb_typeof(p_changes -> 'phone') = 'null'
       or (
         jsonb_typeof(p_changes -> 'phone') = 'string'
         and char_length(btrim(p_changes ->> 'phone')) between 1 and 50
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Phone is invalid', 'field', 'phone'
      )
    );
  end if;

  if p_changes ? 'notes' and not (
       jsonb_typeof(p_changes -> 'notes') = 'null'
       or (
         jsonb_typeof(p_changes -> 'notes') = 'string'
         and char_length(p_changes ->> 'notes') <= 10000
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Notes are too long', 'field', 'notes'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party update is not permitted')
    );
  end if;

  select party.*
  into v_old
  from public.parties as party
  where party.id = p_party_id
    and party.workspace_id = p_workspace_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Party not found')
    );
  end if;

  if v_old.deleted_at is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A merged or deleted party cannot be edited'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_party',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'party_id', p_party_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason,
        'changes', p_changes
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  insert into public.mutation_receipts (
    workspace_id, mutation_id, request_hash, status, created_by, updated_by
  ) values (
    p_workspace_id, p_mutation_id, v_request_hash, 'pending', v_actor_id, v_actor_id
  )
  on conflict (workspace_id, mutation_id) do nothing
  returning id into v_inserted_receipt_id;

  if v_inserted_receipt_id is null then
    select receipt.*
    into v_receipt
    from public.mutation_receipts as receipt
    where receipt.workspace_id = p_workspace_id
      and receipt.mutation_id = p_mutation_id
    for update;

    if v_receipt.request_hash is distinct from v_request_hash then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'mutation_conflict', 'message', 'Mutation id was used with a different command'
        )
      );
    end if;

    if v_receipt.status = 'succeeded' then
      select audit.new_values
      into v_replayed
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'party';

      if v_replayed is null then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'infrastructure_failure', 'message', 'Successful mutation result is unavailable'
          )
        );
      end if;

      return jsonb_build_object('ok', true, 'entity', v_replayed);
    end if;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'in_progress', 'message', 'Mutation is already in progress'
      )
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Party version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.party_snapshot(v_old)
      )
    );
  end if;

  v_now := now();
  v_email := lower(btrim(p_changes ->> 'email'));

  update public.parties as party
  set
    party_type = case
      when p_changes ? 'party_type' then (p_changes ->> 'party_type')::public.party_type
      else party.party_type
    end,
    display_name = case
      when p_changes ? 'display_name' then btrim(p_changes ->> 'display_name')
      else party.display_name
    end,
    legal_name = case
      when p_changes ? 'legal_name' then nullif(btrim(coalesce(p_changes ->> 'legal_name', '')), '')
      else party.legal_name
    end,
    email = case
      when p_changes ? 'email' then nullif(v_email, '')
      else party.email
    end,
    phone = case
      when p_changes ? 'phone' then nullif(btrim(coalesce(p_changes ->> 'phone', '')), '')
      else party.phone
    end,
    notes = case
      when p_changes ? 'notes' then nullif(p_changes ->> 'notes', '')
      else party.notes
    end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = party.version + 1
  where party.id = p_party_id
    and party.workspace_id = p_workspace_id
  returning * into v_new;

  v_old_values := private.party_snapshot(v_old);
  v_new_values := private.party_snapshot(v_new);

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'party.update', 'party', p_party_id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.update_party(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  owner to postgres;
revoke all on function public.update_party(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.update_party(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- assign_party_role: attach a time-boundable role, optionally writing the
-- contractor satellite. At most one open role of each type per party.
-- -----------------------------------------------------------------------------

create function public.assign_party_role(
  p_workspace_id uuid,
  p_party_id uuid,
  p_role_type text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null,
  p_details jsonb default null,
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
  v_party public.parties%rowtype;
  v_role public.party_roles%rowtype;
  v_valid_from timestamptz;
  v_trade_category text;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_id is null or p_role_type is null
     or p_role_type not in ('tenant', 'contractor', 'buyer', 'bank', 'company') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Party and role type are required', 'field', 'role_type'
      )
    );
  end if;

  v_valid_from := coalesce(p_valid_from, v_now);
  if p_valid_until is not null and p_valid_until < v_valid_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'valid_until must not precede valid_from', 'field', 'valid_until'
      )
    );
  end if;

  if p_details is not null then
    if p_role_type <> 'contractor' then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Role details apply to the contractor role only', 'field', 'details'
        )
      );
    end if;
    if jsonb_typeof(p_details) <> 'object' then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Role details must be an object', 'field', 'details'
        )
      );
    end if;
    v_trade_category := btrim(p_details ->> 'trade_category');
    if v_trade_category is null or char_length(v_trade_category) not between 1 and 100 then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Trade category is required for contractor details', 'field', 'trade_category'
        )
      );
    end if;
    if p_details ? 'hourly_rate' and (
         jsonb_typeof(p_details -> 'hourly_rate') not in ('null', 'number')
         or (jsonb_typeof(p_details -> 'hourly_rate') = 'number'
             and (p_details ->> 'hourly_rate')::numeric < 0)
       ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Hourly rate must be a non-negative number', 'field', 'hourly_rate'
        )
      );
    end if;
    if exists (
      select 1
      from unnest(array[
        'rating_price', 'rating_quality', 'rating_speed',
        'rating_communication', 'rating_punctuality'
      ]) as rating_key
      where p_details ? rating_key
        and (
          jsonb_typeof(p_details -> rating_key) not in ('null', 'number')
          or (jsonb_typeof(p_details -> rating_key) = 'number'
              and (p_details ->> rating_key)::numeric not between 0 and 5)
        )
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Ratings must be numbers between 0 and 5', 'field', 'ratings'
        )
      );
    end if;
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'assign_party_role',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'party_id', p_party_id,
        'role_type', p_role_type,
        'valid_from', p_valid_from,
        'valid_until', p_valid_until,
        'details', p_details,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: a successful assign creates the
  -- open role the checks below reject, so replays resolve from the receipt.
  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'party_role'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select party.*
  into v_party
  from public.parties as party
  where party.workspace_id = p_workspace_id
    and party.id = p_party_id
    and party.deleted_at is null
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Party not found')
    );
  end if;

  if p_valid_until is null and exists (
    select 1 from public.party_roles as role
    where role.workspace_id = p_workspace_id
      and role.party_id = p_party_id
      and role.role_type = p_role_type::public.party_role_type
      and role.valid_until is null
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The party already holds an open role of this type'
      )
    );
  end if;

  insert into public.party_roles (
    workspace_id, party_id, role_type, valid_from, valid_until, created_by, updated_by
  ) values (
    p_workspace_id, p_party_id, p_role_type::public.party_role_type,
    v_valid_from, p_valid_until, v_actor_id, v_actor_id
  )
  returning * into v_role;

  if p_details is not null then
    insert into public.party_contractor_details (
      party_id, workspace_id, trade_category, hourly_rate, service_area,
      rating_price, rating_quality, rating_speed, rating_communication,
      rating_punctuality, insurance_cert_expiry, is_active, created_by, updated_by
    ) values (
      p_party_id, p_workspace_id, v_trade_category,
      (p_details ->> 'hourly_rate')::numeric,
      nullif(btrim(coalesce(p_details ->> 'service_area', '')), ''),
      (p_details ->> 'rating_price')::numeric,
      (p_details ->> 'rating_quality')::numeric,
      (p_details ->> 'rating_speed')::numeric,
      (p_details ->> 'rating_communication')::numeric,
      (p_details ->> 'rating_punctuality')::numeric,
      (p_details ->> 'insurance_cert_expiry')::date,
      coalesce((p_details ->> 'is_active')::boolean, true),
      v_actor_id, v_actor_id
    )
    on conflict (party_id) do update
    set
      trade_category = excluded.trade_category,
      hourly_rate = excluded.hourly_rate,
      service_area = excluded.service_area,
      rating_price = excluded.rating_price,
      rating_quality = excluded.rating_quality,
      rating_speed = excluded.rating_speed,
      rating_communication = excluded.rating_communication,
      rating_punctuality = excluded.rating_punctuality,
      insurance_cert_expiry = excluded.insurance_cert_expiry,
      is_active = excluded.is_active,
      updated_at = v_now,
      updated_by = v_actor_id,
      version = public.party_contractor_details.version + 1;
  end if;

  v_new_values := private.party_role_snapshot(v_role);
  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'party_role.assign', 'party_role', v_role.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.assign_party_role(
  uuid, uuid, text, uuid, uuid, timestamptz, timestamptz, jsonb, text
) owner to postgres;
revoke all on function public.assign_party_role(
  uuid, uuid, text, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from public, anon, authenticated;
grant execute on function public.assign_party_role(
  uuid, uuid, text, uuid, uuid, timestamptz, timestamptz, jsonb, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- end_party_role: time-bound an open role (sets valid_until).
-- -----------------------------------------------------------------------------

create function public.end_party_role(
  p_workspace_id uuid,
  p_party_role_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_valid_until timestamptz default null,
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
  v_role public.party_roles%rowtype;
  v_valid_until timestamptz;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_role_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Role and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party management is not permitted')
    );
  end if;

  v_valid_until := coalesce(p_valid_until, v_now);

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'end_party_role',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'party_role_id', p_party_role_id,
        'expected_version', p_expected_version,
        'valid_until', p_valid_until,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: ending changes valid_until, so
  -- replays resolve from the receipt rather than re-validating a changed state.
  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'party_role'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select role.*
  into v_role
  from public.party_roles as role
  where role.workspace_id = p_workspace_id
    and role.id = p_party_role_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Party role not found')
    );
  end if;

  if v_role.valid_until is not null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'The role is already time-bound'
      )
    );
  end if;

  if v_valid_until < v_role.valid_from then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'valid_until must not precede valid_from', 'field', 'valid_until'
      )
    );
  end if;

  if v_role.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Party role version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_role.version,
        'current_entity', private.party_role_snapshot(v_role)
      )
    );
  end if;

  v_old_values := private.party_role_snapshot(v_role);

  update public.party_roles as role
  set
    valid_until = v_valid_until,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = role.version + 1
  where role.id = p_party_role_id
  returning * into v_role;

  v_new_values := private.party_role_snapshot(v_role);
  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'party_role.end', 'party_role', v_role.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.end_party_role(uuid, uuid, bigint, uuid, uuid, timestamptz, text)
  owner to postgres;
revoke all on function public.end_party_role(uuid, uuid, bigint, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.end_party_role(uuid, uuid, bigint, uuid, uuid, timestamptz, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- merge_parties: fold the source party into the target, keeping alias/audit
-- history. Source roles are re-pointed and closed onto the target, its
-- contractor satellite moves only if the target lacks one, its former identity
-- becomes an alias, and the source is tombstoned pointing at the target.
-- -----------------------------------------------------------------------------

create function public.merge_parties(
  p_workspace_id uuid,
  p_target_party_id uuid,
  p_source_party_id uuid,
  p_expected_target_version bigint,
  p_expected_source_version bigint,
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
  v_target public.parties%rowtype;
  v_source public.parties%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_target_party_id is null or p_source_party_id is null
     or p_expected_target_version is null or p_expected_target_version < 1
     or p_expected_source_version is null or p_expected_source_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Target, source and both expected versions are required'
      )
    );
  end if;

  if p_target_party_id = p_source_party_id then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A party cannot be merged into itself'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'merge_parties',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'target_party_id', p_target_party_id,
        'source_party_id', p_source_party_id,
        'expected_target_version', p_expected_target_version,
        'expected_source_version', p_expected_source_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the merge tombstones the source,
  -- so a replayed mutation id must resolve from the receipt.
  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'party'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- Lock in a stable order (target then source) to avoid deadlocks.
  select party.* into v_target
  from public.parties as party
  where party.workspace_id = p_workspace_id and party.id = p_target_party_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Target party not found')
    );
  end if;

  select party.* into v_source
  from public.parties as party
  where party.workspace_id = p_workspace_id and party.id = p_source_party_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Source party not found')
    );
  end if;

  if v_target.deleted_at is not null or v_source.deleted_at is not null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A merged or deleted party cannot take part in a merge'
      )
    );
  end if;

  if v_target.version <> p_expected_target_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Target party version is stale',
        'expected_version', p_expected_target_version,
        'actual_version', v_target.version,
        'current_entity', private.party_snapshot(v_target)
      )
    );
  end if;

  if v_source.version <> p_expected_source_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Source party version is stale',
        'expected_version', p_expected_source_version,
        'actual_version', v_source.version,
        'current_entity', private.party_snapshot(v_source)
      )
    );
  end if;

  -- Re-point the source's roles onto the target and close any that are still
  -- open, so they never collide with the target's open roles.
  update public.party_roles as role
  set
    party_id = p_target_party_id,
    valid_until = coalesce(role.valid_until, v_now),
    updated_at = v_now,
    updated_by = v_actor_id,
    version = role.version + 1
  where role.workspace_id = p_workspace_id
    and role.party_id = p_source_party_id;

  -- Move the contractor satellite only if the target has none; otherwise the
  -- source's is dropped (its values are preserved in the merge audit event).
  if exists (
    select 1 from public.party_contractor_details as details
    where details.workspace_id = p_workspace_id and details.party_id = p_source_party_id
  ) then
    if exists (
      select 1 from public.party_contractor_details as details
      where details.workspace_id = p_workspace_id and details.party_id = p_target_party_id
    ) then
      delete from public.party_contractor_details
      where workspace_id = p_workspace_id and party_id = p_source_party_id;
    else
      insert into public.party_contractor_details (
        party_id, workspace_id, trade_category, hourly_rate, service_area,
        rating_price, rating_quality, rating_speed, rating_communication,
        rating_punctuality, insurance_cert_expiry, is_active, created_by, updated_by
      )
      select
        p_target_party_id, workspace_id, trade_category, hourly_rate, service_area,
        rating_price, rating_quality, rating_speed, rating_communication,
        rating_punctuality, insurance_cert_expiry, is_active, v_actor_id, v_actor_id
      from public.party_contractor_details
      where workspace_id = p_workspace_id and party_id = p_source_party_id;

      delete from public.party_contractor_details
      where workspace_id = p_workspace_id and party_id = p_source_party_id;
    end if;
  end if;

  insert into public.party_aliases (
    workspace_id, target_party_id, source_party_id,
    alias_display_name, alias_legal_name, alias_email, alias_phone, created_by
  ) values (
    p_workspace_id, p_target_party_id, p_source_party_id,
    v_source.display_name, v_source.legal_name, v_source.email, v_source.phone, v_actor_id
  );

  update public.parties as party
  set
    deleted_at = v_now,
    merged_into_party_id = p_target_party_id,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = party.version + 1
  where party.id = p_source_party_id;

  update public.parties as party
  set
    updated_at = v_now,
    updated_by = v_actor_id,
    version = party.version + 1
  where party.id = p_target_party_id
  returning * into v_target;

  v_old_values := private.party_snapshot(v_source);
  v_new_values := private.party_snapshot(v_target);

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'party.merge', 'party', p_target_party_id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.merge_parties(uuid, uuid, uuid, bigint, bigint, uuid, uuid, text)
  owner to postgres;
revoke all on function public.merge_parties(uuid, uuid, uuid, bigint, bigint, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.merge_parties(uuid, uuid, uuid, bigint, bigint, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- detect_party_duplicates: read-only duplicate candidates for a prospective
-- party, matched on normalized email / phone / display name within the
-- workspace, excluding tombstoned/merged parties. Permission-gated on
-- party.read; no receipt, audit or AAL — mirrors list_workspace_members.
-- -----------------------------------------------------------------------------

create function public.detect_party_duplicates(
  p_workspace_id uuid,
  p_display_name text default null,
  p_email text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text := nullif(lower(btrim(p_email)), '');
  v_name text := nullif(lower(btrim(p_display_name)), '');
  v_phone_digits text := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
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

  if not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Party access is not permitted')
    );
  end if;

  if v_email is null and v_name is null and v_phone_digits is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'At least one of display name, email or phone is required'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'entity', coalesce(
      (
        select jsonb_agg(candidate order by sort_name, sort_id)
        from (
          select
            jsonb_build_object(
              'id', party.id,
              'workspace_id', party.workspace_id,
              'party_type', party.party_type,
              'display_name', party.display_name,
              'legal_name', party.legal_name,
              'email', party.email,
              'phone', party.phone,
              'version', party.version,
              'match_email', (v_email is not null and lower(party.email) = v_email),
              'match_phone', (
                v_phone_digits is not null
                and nullif(regexp_replace(coalesce(party.phone, ''), '\D', '', 'g'), '') = v_phone_digits
              ),
              'match_name', (v_name is not null and lower(party.display_name) = v_name)
            ) as candidate,
            lower(party.display_name) as sort_name,
            party.id as sort_id
          from public.parties as party
          where party.workspace_id = p_workspace_id
            and party.deleted_at is null
            and (
              (v_email is not null and lower(party.email) = v_email)
              or (v_name is not null and lower(party.display_name) = v_name)
              or (
                v_phone_digits is not null
                and nullif(regexp_replace(coalesce(party.phone, ''), '\D', '', 'g'), '') = v_phone_digits
              )
            )
        ) as duplicate_rows
      ),
      '[]'::jsonb
    )
  );
end;
$$;

alter function public.detect_party_duplicates(uuid, text, text, text) owner to postgres;
revoke all on function public.detect_party_duplicates(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.detect_party_duplicates(uuid, text, text, text)
  to authenticated;
