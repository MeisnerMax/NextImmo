-- P2-D03: documents_compliance — cloud document/version/requirement contract
-- backed by a private Supabase Storage bucket (DOM-006, DEBT-007, DUP-011,
-- MIG-BND-003).
--
-- The mutation surface mirrors the P2-D02 contacts_parties vertical (enveloped
-- {ok,entity}/{ok,error:{code}} RPCs, optimistic versioning via
-- p_expected_version, idempotency via mutation_receipts + request hash,
-- append-only audit_events, default-deny RLS, reject_protected_column_update,
-- one shared command gate / claim / finish helper trio instead of per-RPC
-- boilerplate) and keeps the P2-D01 claim-before-state-validation rule with
-- receipt cleanup for every mutation that changes the state its own validation
-- reads. Like P2-D02 and P1-004 there is NO AAL2 gate: documents are ordinary
-- workspace business data, so access is gated by the document.read /
-- document.manage / document.verify permissions.
--
-- What is genuinely new here versus P2-D02:
--   * a private Storage bucket plus RLS on storage.objects, so the file bytes
--     are workspace-isolated by the same permission helper as the metadata;
--   * deliberate absence of UPDATE/DELETE policies on storage.objects for this
--     bucket, which makes the DOM-006 invariant "Versionen werden nicht
--     ueberschrieben" structural rather than conventional;
--   * confirm_document_content, which verifies the uploaded object really
--     exists with the declared size before the document becomes available —
--     MIG-BND-003's "Upload verifizieren, erst dann Link umschalten".
--
-- DUP-011 consolidation: the legacy property_document_checklist (a write-only
-- per-property table with a hardcoded key list and the states vorhanden /
-- fehlt / angefordert / nicht_relevant) and the general documents /
-- required_documents model collapse into ONE requirement policy table plus a
-- derived projection (evaluate_document_requirements). The checklist's
-- workflow-only states survive as requirement columns — requested_at for
-- "angefordert", waived_at/waived_by/waiver_reason for "nicht_relevant" — so
-- the union is lossless; fulfilment itself is never stored, only derived.
--
-- Retention (OPN-DOM-005, still open in the decision register): this migration
-- ships the register's documented default and nothing more — retention_until is
-- informational, there is no automatic deletion, no delete RPC and no DELETE
-- policy on storage.objects. Blocking access is the 'archived' status, and the
-- decision is audited. OPN-DOM-005 stays open.
--
-- Named gap (not silently improvised): download access is not audited. A read
-- RPC writes no audit_events by convention in this codebase, and per-access
-- logging belongs to the P2-D04 platform_audit_jobs event envelope.

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

-- STM-008: uploaded -> processing -> available -> verified -> superseded ->
-- archived, error path processing -> rejected. 'processing' is reserved for an
-- asynchronous scan/extract pipeline that does not exist yet; no RPC in this
-- migration produces it, and that is documented rather than faked.
create type public.document_status as enum (
  'uploaded',
  'processing',
  'available',
  'verified',
  'superseded',
  'archived',
  'rejected'
);

create type public.document_verification_status as enum (
  'pending',
  'verified',
  'rejected'
);

-- DEBT-006: the legacy polymorphic entity_type/entity_id pair becomes a
-- controlled registry instead of free text. Values whose owning domain has not
-- migrated yet are accepted by the enum but rejected by link_document with
-- dependency_conflict until that domain ships.
create type public.document_link_entity_type as enum (
  'workspace',
  'property',
  'portfolio',
  'unit',
  'lease',
  'party',
  'maintenance_ticket',
  'capex_project',
  'scenario'
);

-- -----------------------------------------------------------------------------
-- document_types: workspace-scoped type registry. Mirrors the legacy
-- document_types table (a user-managed registry, NOT a fixed enum), so the
-- dry-run mapper can carry existing types over instead of forcing them into an
-- invented catalogue.
-- -----------------------------------------------------------------------------

create table public.document_types (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  key text not null,
  name text not null,
  entity_type public.document_link_entity_type not null,
  default_validity_months integer,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint document_types_workspace_id_key unique (workspace_id, id),
  constraint document_types_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint document_types_key_unique unique (workspace_id, key),
  constraint document_types_key_normalized_check check (
    key = lower(btrim(key))
    and key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(key) between 2 and 100
  ),
  constraint document_types_name_check check (
    char_length(btrim(name)) between 1 and 200
  ),
  constraint document_types_validity_check check (
    default_validity_months is null
    or default_validity_months between 1 and 1200
  ),
  constraint document_types_version_check check (version >= 1)
);

create index document_types_workspace_idx on public.document_types (workspace_id);
create index document_types_entity_type_idx
  on public.document_types (workspace_id, entity_type)
  where is_active;

create trigger document_types_protected_columns
before update on public.document_types
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'key', 'created_at', 'created_by'
);

alter table public.document_types enable row level security;
alter table public.document_types force row level security;

create policy document_types_select_document_read
on public.document_types
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'document.read'));

revoke all on table public.document_types from anon, authenticated;
grant select on table public.document_types to authenticated;

-- -----------------------------------------------------------------------------
-- documents: the logical document aggregate carrying STM-008 status and
-- validity. Deliberately no deleted_at column — 'archived' is the terminal
-- STM-008 state, and two competing truths for "gone" would be worse than one.
-- -----------------------------------------------------------------------------

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  document_type_id uuid,
  title text not null,
  status public.document_status not null default 'uploaded',
  current_version_no integer not null default 0,
  valid_from date,
  valid_until date,
  retention_until date,
  superseded_by_document_id uuid,
  archived_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint documents_workspace_id_key unique (workspace_id, id),
  constraint documents_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint documents_type_fkey foreign key (workspace_id, document_type_id)
    references public.document_types (workspace_id, id) on delete restrict,
  constraint documents_superseded_by_fkey
    foreign key (workspace_id, superseded_by_document_id)
    references public.documents (workspace_id, id) on delete restrict,
  constraint documents_title_check check (
    char_length(btrim(title)) between 1 and 300
  ),
  constraint documents_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  constraint documents_validity_range_check check (
    valid_from is null or valid_until is null or valid_until >= valid_from
  ),
  constraint documents_current_version_check check (current_version_no >= 0),
  constraint documents_not_self_supersede_check check (
    superseded_by_document_id is null or superseded_by_document_id <> id
  ),
  -- A successor may only be recorded once the document has actually left the
  -- active states.
  constraint documents_superseded_state_check check (
    superseded_by_document_id is null
    or status in ('superseded', 'archived')
  ),
  constraint documents_archived_marker_check check (
    (status = 'archived') = (archived_at is not null)
  ),
  constraint documents_version_check check (version >= 1)
);

create index documents_workspace_idx on public.documents (workspace_id);
create index documents_type_idx
  on public.documents (workspace_id, document_type_id)
  where document_type_id is not null;
create index documents_status_idx on public.documents (workspace_id, status);
-- Expiry sweeps read active documents with a validity end date.
create index documents_valid_until_idx
  on public.documents (workspace_id, valid_until)
  where valid_until is not null and status in ('available', 'verified');
create index documents_superseded_by_idx
  on public.documents (workspace_id, superseded_by_document_id)
  where superseded_by_document_id is not null;

create trigger documents_protected_columns
before update on public.documents
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.documents enable row level security;
alter table public.documents force row level security;

create policy documents_select_document_read
on public.documents
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'document.read'));

revoke all on table public.documents from anon, authenticated;
grant select on table public.documents to authenticated;

-- -----------------------------------------------------------------------------
-- document_versions: immutable content versions. Everything describing the
-- bytes (path, hash, size, mime type, filename) is locked by the protected
-- column trigger; only the verification and supersede columns may ever change,
-- and only through the RPCs below. "Hash/Version unveraenderlich".
-- -----------------------------------------------------------------------------

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  document_id uuid not null,
  version_no integer not null,
  storage_bucket text not null,
  storage_object_path text not null,
  content_hash bytea not null,
  byte_size bigint not null,
  mime_type text not null,
  original_filename text,
  content_confirmed_at timestamptz,
  verification_status public.document_verification_status not null default 'pending',
  verified_at timestamptz,
  verified_by uuid,
  verification_note text,
  superseded_at timestamptz,
  superseded_by_version_no integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint document_versions_workspace_id_key unique (workspace_id, id),
  constraint document_versions_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint document_versions_document_fkey foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete cascade,
  constraint document_versions_no_unique unique (workspace_id, document_id, version_no),
  -- One storage object backs exactly one version, globally.
  constraint document_versions_object_unique unique (storage_bucket, storage_object_path),
  constraint document_versions_no_check check (version_no >= 1),
  constraint document_versions_bucket_check check (storage_bucket = 'documents'),
  -- The object path must live under the owning workspace's prefix; this is the
  -- database-side half of the storage.objects RLS isolation.
  constraint document_versions_path_scope_check check (
    storage_object_path like (workspace_id::text || '/%')
    and char_length(storage_object_path) between 38 and 1024
    and storage_object_path not like '%..%'
  ),
  constraint document_versions_hash_check check (octet_length(content_hash) = 32),
  constraint document_versions_byte_size_check check (byte_size >= 0),
  constraint document_versions_mime_check check (
    char_length(btrim(mime_type)) between 3 and 255
  ),
  constraint document_versions_filename_check check (
    original_filename is null or char_length(btrim(original_filename)) between 1 and 255
  ),
  constraint document_versions_note_check check (
    verification_note is null or char_length(verification_note) <= 4000
  ),
  -- Verification and expiry are separate concerns; a pending version carries no
  -- verification outcome.
  constraint document_versions_verification_marker_check check (
    (verification_status = 'pending') = (verified_at is null)
    and (verified_at is null) = (verified_by is null)
  ),
  constraint document_versions_supersede_marker_check check (
    (superseded_at is null) = (superseded_by_version_no is null)
  ),
  constraint document_versions_supersede_order_check check (
    superseded_by_version_no is null or superseded_by_version_no > version_no
  ),
  constraint document_versions_version_check check (version >= 1)
);

create index document_versions_document_idx
  on public.document_versions (workspace_id, document_id, version_no desc);
create index document_versions_open_idx
  on public.document_versions (workspace_id, document_id)
  where superseded_at is null;

create trigger document_versions_protected_columns
before update on public.document_versions
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'document_id', 'version_no', 'storage_bucket',
  'storage_object_path', 'content_hash', 'byte_size', 'mime_type',
  'original_filename', 'created_at', 'created_by'
);

alter table public.document_versions enable row level security;
alter table public.document_versions force row level security;

create policy document_versions_select_document_read
on public.document_versions
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'document.read'));

revoke all on table public.document_versions from anon, authenticated;
grant select on table public.document_versions to authenticated;

-- -----------------------------------------------------------------------------
-- document_links: the DocumentLinkPort EntityRef table. The composite foreign
-- key to (workspace_id, id) is what makes "Links workspacegleich" a schema
-- invariant rather than an application rule.
-- -----------------------------------------------------------------------------

create table public.document_links (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  document_id uuid not null,
  entity_type public.document_link_entity_type not null,
  entity_id uuid not null,
  link_role text,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint document_links_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint document_links_document_fkey foreign key (workspace_id, document_id)
    references public.documents (workspace_id, id) on delete cascade,
  constraint document_links_unique
    unique (workspace_id, document_id, entity_type, entity_id),
  constraint document_links_role_check check (
    link_role is null or char_length(btrim(link_role)) between 1 and 100
  )
);

create index document_links_entity_idx
  on public.document_links (workspace_id, entity_type, entity_id);
create index document_links_document_idx
  on public.document_links (workspace_id, document_id);

alter table public.document_links enable row level security;
alter table public.document_links force row level security;

create policy document_links_select_document_read
on public.document_links
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'document.read'));

revoke all on table public.document_links from anon, authenticated;
grant select on table public.document_links to authenticated;

-- -----------------------------------------------------------------------------
-- required_documents: the RequirementPolicyRepository table and the single
-- home of the consolidated DUP-011 model. entity_id null means a workspace-wide
-- rule for that entity type (the legacy required_documents semantics);
-- entity_id set means an instance-level requirement (the legacy checklist row).
-- scope_key generalises the legacy property_type column without dragging
-- portfolio vocabulary into DOM-006; null means "applies to every scope".
-- -----------------------------------------------------------------------------

create table public.required_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  entity_type public.document_link_entity_type not null,
  entity_id uuid,
  scope_key text,
  document_type_id uuid not null,
  is_mandatory boolean not null default true,
  due_at date,
  validity_months integer,
  owner_user_id uuid,
  note text,
  -- Checklist state "angefordert": the document has been requested but not
  -- delivered. Fulfilment itself is never stored, only derived.
  requested_at timestamptz,
  -- Checklist state "nicht_relevant": an explicit, audited waiver.
  waived_at timestamptz,
  waived_by uuid,
  waiver_reason text,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint required_documents_workspace_id_key unique (workspace_id, id),
  constraint required_documents_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint required_documents_type_fkey foreign key (workspace_id, document_type_id)
    references public.document_types (workspace_id, id) on delete restrict,
  constraint required_documents_scope_key_check check (
    scope_key is null or char_length(btrim(scope_key)) between 1 and 100
  ),
  constraint required_documents_validity_check check (
    validity_months is null or validity_months between 1 and 1200
  ),
  constraint required_documents_note_check check (
    note is null or char_length(note) <= 4000
  ),
  constraint required_documents_waiver_marker_check check (
    (waived_at is null) = (waived_by is null)
    and (waiver_reason is null or waived_at is not null)
  ),
  constraint required_documents_waiver_reason_check check (
    waiver_reason is null or char_length(btrim(waiver_reason)) between 1 and 2000
  ),
  constraint required_documents_version_check check (version >= 1)
);

-- One live rule per (entity type, entity, scope, document type). Mirrors the
-- legacy unique index on (entity_type, property_type, type_id) and the
-- checklist's unique (property_id, document_key).
create unique index required_documents_live_unique
  on public.required_documents (
    workspace_id,
    entity_type,
    coalesce(entity_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(scope_key, ''),
    document_type_id
  )
  where retired_at is null;

create index required_documents_entity_idx
  on public.required_documents (workspace_id, entity_type, entity_id)
  where retired_at is null;
create index required_documents_type_idx
  on public.required_documents (workspace_id, document_type_id);

create trigger required_documents_protected_columns
before update on public.required_documents
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'entity_type', 'entity_id', 'document_type_id',
  'created_at', 'created_by'
);

alter table public.required_documents enable row level security;
alter table public.required_documents force row level security;

create policy required_documents_select_document_read
on public.required_documents
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'document.read'));

revoke all on table public.required_documents from anon, authenticated;
grant select on table public.required_documents to authenticated;

-- -----------------------------------------------------------------------------
-- Private Storage bucket + RLS on storage.objects (MIG-BND-003).
--
-- One private bucket with a {workspace_id}/{document_id}/{version_no}/{file}
-- path convention. Isolation is enforced on the first path segment by the same
-- private.has_workspace_permission helper that guards the metadata tables, so
-- bytes and rows can never diverge in who may see them.
--
-- There is deliberately NO update and NO delete policy: an authenticated client
-- can read (document.read) and add (document.manage) objects in this bucket and
-- can never overwrite or remove one. That is the storage-level enforcement of
-- "Versionen werden nicht ueberschrieben" and of the OPN-DOM-005 default of no
-- automatic deletion.
-- -----------------------------------------------------------------------------

-- Idempotent on purpose. `supabase migration down` recreates schema from the
-- migrations but restores table *data* from a dump, so this bucket row outlives
-- a rollback while every schema artifact above and below it does not. Without
-- the conflict clause the replay-up leg of the CI rollback test would fail on a
-- duplicate key; with it, a replay also re-asserts that the bucket is private.
insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 52428800)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit;

-- Safe parse of the leading workspace segment. Returns null for any object name
-- that is not workspace-prefixed, which makes every policy below fail closed
-- (has_workspace_permission(null, ...) is false).
create function private.document_storage_workspace(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when object_name is null then null
    when split_part(object_name, '/', 1)
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then split_part(object_name, '/', 1)::uuid
    else null
  end;
$$;

alter function private.document_storage_workspace(text) owner to postgres;
revoke all on function private.document_storage_workspace(text)
  from public, anon, authenticated;
grant execute on function private.document_storage_workspace(text) to authenticated;

create policy documents_bucket_select_document_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'documents'
  and private.has_workspace_permission(
    private.document_storage_workspace(name), 'document.read'
  )
);

create policy documents_bucket_insert_document_manage
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'documents'
  and private.has_workspace_permission(
    private.document_storage_workspace(name), 'document.manage'
  )
  -- {workspace}/{document}/{version}/{filename}: at least four segments.
  and array_length(storage.foldername(name), 1) >= 3
);

-- -----------------------------------------------------------------------------
-- Shared private helpers: command envelope validation, idempotency claim,
-- audit + receipt finish, and row snapshots — one implementation for all
-- document mutation RPCs (P2-D01/P2-D02 shape).
-- -----------------------------------------------------------------------------

create function private.document_command_gate(
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

alter function private.document_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.document_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- Claims the mutation id. Returns null when the caller owns a fresh receipt
-- (proceed), otherwise the deterministic replay result.
create function private.claim_document_mutation(
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

alter function private.claim_document_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_document_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_document_mutation(
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

alter function private.finish_document_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_document_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

create function private.document_snapshot(document public.documents)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', document.id,
    'workspace_id', document.workspace_id,
    'document_type_id', document.document_type_id,
    'title', document.title,
    'status', document.status,
    'current_version_no', document.current_version_no,
    'valid_from', document.valid_from,
    'valid_until', document.valid_until,
    'retention_until', document.retention_until,
    'superseded_by_document_id', document.superseded_by_document_id,
    'archived_at', document.archived_at,
    'notes', document.notes,
    'created_at', document.created_at,
    'updated_at', document.updated_at,
    'created_by', document.created_by,
    'updated_by', document.updated_by,
    'version', document.version
  );
$$;

alter function private.document_snapshot(public.documents) owner to postgres;
revoke all on function private.document_snapshot(public.documents)
  from public, anon, authenticated;

create function private.document_version_snapshot(document_version public.document_versions)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', document_version.id,
    'workspace_id', document_version.workspace_id,
    'document_id', document_version.document_id,
    'version_no', document_version.version_no,
    'storage_bucket', document_version.storage_bucket,
    'storage_object_path', document_version.storage_object_path,
    'content_hash', encode(document_version.content_hash, 'hex'),
    'byte_size', document_version.byte_size,
    'mime_type', document_version.mime_type,
    'original_filename', document_version.original_filename,
    'content_confirmed_at', document_version.content_confirmed_at,
    'verification_status', document_version.verification_status,
    'verified_at', document_version.verified_at,
    'verified_by', document_version.verified_by,
    'verification_note', document_version.verification_note,
    'superseded_at', document_version.superseded_at,
    'superseded_by_version_no', document_version.superseded_by_version_no,
    'created_at', document_version.created_at,
    'updated_at', document_version.updated_at,
    'created_by', document_version.created_by,
    'updated_by', document_version.updated_by,
    'version', document_version.version
  );
$$;

alter function private.document_version_snapshot(public.document_versions) owner to postgres;
revoke all on function private.document_version_snapshot(public.document_versions)
  from public, anon, authenticated;

create function private.document_link_snapshot(link public.document_links)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', link.id,
    'workspace_id', link.workspace_id,
    'document_id', link.document_id,
    'entity_type', link.entity_type,
    'entity_id', link.entity_id,
    'link_role', link.link_role,
    'created_at', link.created_at,
    'created_by', link.created_by
  );
$$;

alter function private.document_link_snapshot(public.document_links) owner to postgres;
revoke all on function private.document_link_snapshot(public.document_links)
  from public, anon, authenticated;

create function private.document_type_snapshot(document_type public.document_types)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', document_type.id,
    'workspace_id', document_type.workspace_id,
    'key', document_type.key,
    'name', document_type.name,
    'entity_type', document_type.entity_type,
    'default_validity_months', document_type.default_validity_months,
    'is_active', document_type.is_active,
    'created_at', document_type.created_at,
    'updated_at', document_type.updated_at,
    'created_by', document_type.created_by,
    'updated_by', document_type.updated_by,
    'version', document_type.version
  );
$$;

alter function private.document_type_snapshot(public.document_types) owner to postgres;
revoke all on function private.document_type_snapshot(public.document_types)
  from public, anon, authenticated;

create function private.required_document_snapshot(requirement public.required_documents)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', requirement.id,
    'workspace_id', requirement.workspace_id,
    'entity_type', requirement.entity_type,
    'entity_id', requirement.entity_id,
    'scope_key', requirement.scope_key,
    'document_type_id', requirement.document_type_id,
    'is_mandatory', requirement.is_mandatory,
    'due_at', requirement.due_at,
    'validity_months', requirement.validity_months,
    'owner_user_id', requirement.owner_user_id,
    'note', requirement.note,
    'requested_at', requirement.requested_at,
    'waived_at', requirement.waived_at,
    'waived_by', requirement.waived_by,
    'waiver_reason', requirement.waiver_reason,
    'retired_at', requirement.retired_at,
    'created_at', requirement.created_at,
    'updated_at', requirement.updated_at,
    'created_by', requirement.created_by,
    'updated_by', requirement.updated_by,
    'version', requirement.version
  );
$$;

alter function private.required_document_snapshot(public.required_documents) owner to postgres;
revoke all on function private.required_document_snapshot(public.required_documents)
  from public, anon, authenticated;

-- Validates an entity reference against the domains that already exist. Types
-- whose owning domain has not migrated yet are rejected with a distinct signal
-- instead of being silently accepted as dangling references (DEBT-006).
create function private.document_entity_ref_state(
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
  end if;

  -- portfolio / unit / lease / maintenance_ticket / capex_project / scenario
  -- arrive with P2-D05..P2-D08.
  return 'unmigrated';
end;
$$;

alter function private.document_entity_ref_state(
  uuid, public.document_link_entity_type, uuid
) owner to postgres;
revoke all on function private.document_entity_ref_state(
  uuid, public.document_link_entity_type, uuid
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- upsert_document_type: maintain the workspace type registry. Retiring a type
-- flips is_active; types are never deleted because documents reference them.
-- -----------------------------------------------------------------------------

create function public.upsert_document_type(
  p_workspace_id uuid,
  p_key text,
  p_name text,
  p_entity_type text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_default_validity_months integer default null,
  p_is_active boolean default true,
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
  v_key text;
  v_request_hash bytea;
  v_claim jsonb;
  v_existing public.document_types%rowtype;
  v_type public.document_types%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_action text;
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  v_key := lower(btrim(coalesce(p_key, '')));
  if v_key !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$' or char_length(v_key) not between 2 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Document type key is invalid', 'field', 'key'
      )
    );
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Document type name is required', 'field', 'name'
      )
    );
  end if;

  if p_entity_type is null or not exists (
    select 1 from unnest(enum_range(null::public.document_link_entity_type)) as allowed
    where allowed::text = p_entity_type
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Entity type is invalid', 'field', 'entity_type'
      )
    );
  end if;

  if p_default_validity_months is not null
     and p_default_validity_months not between 1 and 1200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Default validity must be between 1 and 1200 months',
        'field', 'default_validity_months'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_document_type',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'key', v_key,
        'name', btrim(p_name),
        'entity_type', p_entity_type,
        'default_validity_months', p_default_validity_months,
        'is_active', p_is_active,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before reading state: the upsert changes the row its own branch
  -- selection depends on, so replays must resolve from the receipt.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document_type'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select document_type.*
  into v_existing
  from public.document_types as document_type
  where document_type.workspace_id = p_workspace_id
    and document_type.key = v_key
  for update;

  if found then
    update public.document_types as document_type
    set
      name = btrim(p_name),
      entity_type = p_entity_type::public.document_link_entity_type,
      default_validity_months = p_default_validity_months,
      is_active = coalesce(p_is_active, true),
      updated_at = now(),
      updated_by = v_actor_id,
      version = document_type.version + 1
    where document_type.id = v_existing.id
    returning * into v_type;

    v_old_values := private.document_type_snapshot(v_existing);
    v_action := case
      when v_existing.is_active and not v_type.is_active then 'document_type.retire'
      else 'document_type.update'
    end;
  else
    insert into public.document_types (
      workspace_id, key, name, entity_type, default_validity_months, is_active,
      created_by, updated_by
    ) values (
      p_workspace_id, v_key, btrim(p_name),
      p_entity_type::public.document_link_entity_type,
      p_default_validity_months, coalesce(p_is_active, true),
      v_actor_id, v_actor_id
    )
    returning * into v_type;

    v_old_values := null;
    v_action := 'document_type.create';
  end if;

  v_new_values := private.document_type_snapshot(v_type);
  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    v_action, 'document_type', v_type.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.upsert_document_type(
  uuid, text, text, text, uuid, uuid, integer, boolean, text
) owner to postgres;
revoke all on function public.upsert_document_type(
  uuid, text, text, text, uuid, uuid, integer, boolean, text
) from public, anon, authenticated;
grant execute on function public.upsert_document_type(
  uuid, text, text, text, uuid, uuid, integer, boolean, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- create_document: register a document and its first content version. The
-- client uploads the object to the private bucket first and passes the
-- resulting path, hash and size here; the document stays in 'uploaded' until
-- confirm_document_content has verified the object really exists.
-- -----------------------------------------------------------------------------

create function public.create_document(
  p_workspace_id uuid,
  p_title text,
  p_storage_object_path text,
  p_content_hash text,
  p_byte_size bigint,
  p_mime_type text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_document_type_id uuid default null,
  p_original_filename text default null,
  p_valid_from date default null,
  p_valid_until date default null,
  p_retention_until date default null,
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
  v_hash bytea;
  v_request_hash bytea;
  v_claim jsonb;
  v_document public.documents%rowtype;
  v_version public.document_versions%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_title is null or char_length(btrim(p_title)) not between 1 and 300 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is required', 'field', 'title'
      )
    );
  end if;

  if p_storage_object_path is null
     or p_storage_object_path not like (p_workspace_id::text || '/%')
     or p_storage_object_path like '%..%'
     or char_length(p_storage_object_path) not between 38 and 1024 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Storage object path must live under the workspace prefix',
        'field', 'storage_object_path'
      )
    );
  end if;

  if p_content_hash is null or p_content_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Content hash must be a lowercase hex sha256 digest',
        'field', 'content_hash'
      )
    );
  end if;
  v_hash := decode(p_content_hash, 'hex');

  if p_byte_size is null or p_byte_size < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Byte size is invalid', 'field', 'byte_size'
      )
    );
  end if;

  if p_mime_type is null or char_length(btrim(p_mime_type)) not between 3 and 255 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Mime type is required', 'field', 'mime_type'
      )
    );
  end if;

  if p_valid_from is not null and p_valid_until is not null and p_valid_until < p_valid_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'valid_until must not precede valid_from', 'field', 'valid_until'
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

  if not private.has_workspace_permission(p_workspace_id, 'document.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  if p_document_type_id is not null and not exists (
    select 1 from public.document_types as document_type
    where document_type.workspace_id = p_workspace_id
      and document_type.id = p_document_type_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document type not found')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_document',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'title', btrim(p_title),
        'storage_object_path', p_storage_object_path,
        'content_hash', p_content_hash,
        'byte_size', p_byte_size,
        'mime_type', p_mime_type,
        'document_type_id', p_document_type_id,
        'original_filename', p_original_filename,
        'valid_from', p_valid_from,
        'valid_until', p_valid_until,
        'retention_until', p_retention_until,
        'notes', p_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if exists (
    select 1 from public.document_versions as existing
    where existing.storage_bucket = 'documents'
      and existing.storage_object_path = p_storage_object_path
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The storage object is already bound to a document version',
        'field', 'storage_object_path'
      )
    );
  end if;

  insert into public.documents (
    workspace_id, document_type_id, title, status, current_version_no,
    valid_from, valid_until, retention_until, notes, created_by, updated_by
  ) values (
    p_workspace_id, p_document_type_id, btrim(p_title), 'uploaded', 1,
    p_valid_from, p_valid_until, p_retention_until, nullif(p_notes, ''),
    v_actor_id, v_actor_id
  )
  returning * into v_document;

  insert into public.document_versions (
    workspace_id, document_id, version_no, storage_bucket, storage_object_path,
    content_hash, byte_size, mime_type, original_filename, created_by, updated_by
  ) values (
    p_workspace_id, v_document.id, 1, 'documents', p_storage_object_path,
    v_hash, p_byte_size, btrim(p_mime_type),
    nullif(btrim(coalesce(p_original_filename, '')), ''),
    v_actor_id, v_actor_id
  )
  returning * into v_version;

  v_new_values := private.document_snapshot(v_document)
    || jsonb_build_object('current_version', private.document_version_snapshot(v_version));

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'document.create', 'document', v_document.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_document(
  uuid, text, text, text, bigint, text, uuid, uuid, uuid, text, date, date, date, text, text
) owner to postgres;
revoke all on function public.create_document(
  uuid, text, text, text, bigint, text, uuid, uuid, uuid, text, date, date, date, text, text
) from public, anon, authenticated;
grant execute on function public.create_document(
  uuid, text, text, text, bigint, text, uuid, uuid, uuid, text, date, date, date, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- add_document_version: append a new immutable content version. The previous
-- version is superseded in place (never overwritten) and the document returns
-- to 'uploaded' until the new content is confirmed.
-- -----------------------------------------------------------------------------

create function public.add_document_version(
  p_workspace_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_storage_object_path text,
  p_content_hash text,
  p_byte_size bigint,
  p_mime_type text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_original_filename text default null,
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
  v_hash bytea;
  v_request_hash bytea;
  v_claim jsonb;
  v_document public.documents%rowtype;
  v_version public.document_versions%rowtype;
  v_next_no integer;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Document id and expected version are required'
      )
    );
  end if;

  if p_storage_object_path is null
     or p_storage_object_path not like (p_workspace_id::text || '/%')
     or p_storage_object_path like '%..%'
     or char_length(p_storage_object_path) not between 38 and 1024 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Storage object path must live under the workspace prefix',
        'field', 'storage_object_path'
      )
    );
  end if;

  if p_content_hash is null or p_content_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Content hash must be a lowercase hex sha256 digest',
        'field', 'content_hash'
      )
    );
  end if;
  v_hash := decode(p_content_hash, 'hex');

  if p_byte_size is null or p_byte_size < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Byte size is invalid', 'field', 'byte_size'
      )
    );
  end if;

  if p_mime_type is null or char_length(btrim(p_mime_type)) not between 3 and 255 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Mime type is required', 'field', 'mime_type'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'add_document_version',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'document_id', p_document_id,
        'expected_version', p_expected_version,
        'storage_object_path', p_storage_object_path,
        'content_hash', p_content_hash,
        'byte_size', p_byte_size,
        'mime_type', p_mime_type,
        'original_filename', p_original_filename,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: adding a version bumps the
  -- document version and supersedes the previous one, so a replay must resolve
  -- from the receipt rather than re-validate a state this command changed.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document_version'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select document.*
  into v_document
  from public.documents as document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  if v_document.status in ('superseded', 'archived') then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A superseded or archived document accepts no new versions'
      )
    );
  end if;

  if v_document.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Document version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_document.version,
        'current_entity', private.document_snapshot(v_document)
      )
    );
  end if;

  if exists (
    select 1 from public.document_versions as existing
    where existing.storage_bucket = 'documents'
      and existing.storage_object_path = p_storage_object_path
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The storage object is already bound to a document version',
        'field', 'storage_object_path'
      )
    );
  end if;

  -- Snapshot the document before it is bumped, so the audit trail records the
  -- real transition rather than the post-update row twice.
  v_old_values := private.document_snapshot(v_document);
  v_next_no := v_document.current_version_no + 1;

  insert into public.document_versions (
    workspace_id, document_id, version_no, storage_bucket, storage_object_path,
    content_hash, byte_size, mime_type, original_filename, created_by, updated_by
  ) values (
    p_workspace_id, p_document_id, v_next_no, 'documents', p_storage_object_path,
    v_hash, p_byte_size, btrim(p_mime_type),
    nullif(btrim(coalesce(p_original_filename, '')), ''),
    v_actor_id, v_actor_id
  )
  returning * into v_version;

  -- The previous version is marked superseded, never rewritten: its path, hash
  -- and size stay exactly as they were.
  update public.document_versions as previous
  set
    superseded_at = v_now,
    superseded_by_version_no = v_next_no,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = previous.version + 1
  where previous.workspace_id = p_workspace_id
    and previous.document_id = p_document_id
    and previous.version_no < v_next_no
    and previous.superseded_at is null;

  update public.documents as document
  set
    current_version_no = v_next_no,
    status = 'uploaded',
    updated_at = v_now,
    updated_by = v_actor_id,
    version = document.version + 1
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  returning * into v_document;

  v_new_values := private.document_version_snapshot(v_version)
    || jsonb_build_object('document', private.document_snapshot(v_document));

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'document_version.add', 'document_version', v_version.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.add_document_version(
  uuid, uuid, bigint, text, text, bigint, text, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.add_document_version(
  uuid, uuid, bigint, text, text, bigint, text, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.add_document_version(
  uuid, uuid, bigint, text, text, bigint, text, uuid, uuid, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- confirm_document_content (MIG-BND-003): verify that the declared object
-- really exists in the private bucket with the declared size BEFORE the
-- document becomes available. A mismatch drives the STM-008 error path to
-- 'rejected' instead of publishing an unverified link.
-- -----------------------------------------------------------------------------

create function public.confirm_document_content(
  p_workspace_id uuid,
  p_document_id uuid,
  p_version_no integer,
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
  v_request_hash bytea;
  v_claim jsonb;
  v_document public.documents%rowtype;
  v_version public.document_versions%rowtype;
  v_object_size bigint;
  v_object_found boolean;
  v_target_status public.document_status;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_id is null or p_version_no is null or p_version_no < 1
     or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Document id, version number and expected version are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'confirm_document_content',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'document_id', p_document_id,
        'version_no', p_version_no,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: confirming moves the document out
  -- of 'uploaded', which the checks below read.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select document.*
  into v_document
  from public.documents as document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  if v_document.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Document version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_document.version,
        'current_entity', private.document_snapshot(v_document)
      )
    );
  end if;

  if v_document.status <> 'uploaded' then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only an uploaded document awaits content confirmation'
      )
    );
  end if;

  select document_version.*
  into v_version
  from public.document_versions as document_version
  where document_version.workspace_id = p_workspace_id
    and document_version.document_id = p_document_id
    and document_version.version_no = p_version_no
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document version not found')
    );
  end if;

  if v_version.version_no <> v_document.current_version_no then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only the current version can be confirmed'
      )
    );
  end if;

  -- The real upload check: does the object exist in the private bucket, and
  -- does its recorded size match what the client declared?
  select true, (object.metadata ->> 'size')::bigint
  into v_object_found, v_object_size
  from storage.objects as object
  where object.bucket_id = v_version.storage_bucket
    and object.name = v_version.storage_object_path;

  if coalesce(v_object_found, false) and v_object_size is not distinct from v_version.byte_size then
    v_target_status := 'available';
  else
    v_target_status := 'rejected';
  end if;

  v_old_values := private.document_snapshot(v_document);

  if v_target_status = 'available' then
    update public.document_versions as document_version
    set
      content_confirmed_at = v_now,
      updated_at = v_now,
      updated_by = v_actor_id,
      version = document_version.version + 1
    where document_version.id = v_version.id
    returning * into v_version;
  end if;

  update public.documents as document
  set
    status = v_target_status,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = document.version + 1
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  returning * into v_document;

  v_new_values := private.document_snapshot(v_document)
    || jsonb_build_object(
      'current_version', private.document_version_snapshot(v_version),
      'content_verified', (v_target_status = 'available')
    );

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_target_status = 'available'
      then 'document.content_confirmed'
      else 'document.content_rejected'
    end,
    'document', v_document.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.confirm_document_content(
  uuid, uuid, integer, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.confirm_document_content(
  uuid, uuid, integer, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.confirm_document_content(
  uuid, uuid, integer, bigint, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- verify_document_version (DocumentVerificationPort): an explicit verification
-- decision on one immutable version, gated by the separate document.verify
-- permission. Verification and expiry stay separate concerns: verifying does
-- not touch valid_until, and an expired document can still be verified.
-- -----------------------------------------------------------------------------

create function public.verify_document_version(
  p_workspace_id uuid,
  p_document_id uuid,
  p_version_no integer,
  p_expected_version bigint,
  p_outcome text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_note text default null,
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
  v_document public.documents%rowtype;
  v_version public.document_versions%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_id is null or p_version_no is null or p_version_no < 1
     or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Document id, version number and expected version are required'
      )
    );
  end if;

  if p_outcome is null or p_outcome not in ('verified', 'rejected') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Outcome must be verified or rejected', 'field', 'outcome'
      )
    );
  end if;

  if p_note is not null and char_length(p_note) > 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Verification note is too long', 'field', 'note'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.verify')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document verification is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'verify_document_version',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'document_id', p_document_id,
        'version_no', p_version_no,
        'expected_version', p_expected_version,
        'outcome', p_outcome,
        'note', p_note,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: verification changes the very
  -- status the checks below read.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document_version'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select document.*
  into v_document
  from public.documents as document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  if v_document.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Document version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_document.version,
        'current_entity', private.document_snapshot(v_document)
      )
    );
  end if;

  -- STM-008: only an available document can be verified.
  if v_document.status <> 'available' then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only an available document can be verified'
      )
    );
  end if;

  select document_version.*
  into v_version
  from public.document_versions as document_version
  where document_version.workspace_id = p_workspace_id
    and document_version.document_id = p_document_id
    and document_version.version_no = p_version_no
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document version not found')
    );
  end if;

  if v_version.version_no <> v_document.current_version_no then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only the current version can be verified'
      )
    );
  end if;

  if v_version.content_confirmed_at is null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unconfirmed content cannot be verified'
      )
    );
  end if;

  v_old_values := private.document_version_snapshot(v_version);

  update public.document_versions as document_version
  set
    verification_status = p_outcome::public.document_verification_status,
    verified_at = v_now,
    verified_by = v_actor_id,
    verification_note = nullif(btrim(coalesce(p_note, '')), ''),
    updated_at = v_now,
    updated_by = v_actor_id,
    version = document_version.version + 1
  where document_version.id = v_version.id
  returning * into v_version;

  update public.documents as document
  set
    status = (
      case when p_outcome = 'verified' then 'verified' else 'rejected' end
    )::public.document_status,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = document.version + 1
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  returning * into v_document;

  v_new_values := private.document_version_snapshot(v_version)
    || jsonb_build_object('document', private.document_snapshot(v_document));

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when p_outcome = 'verified'
      then 'document_version.verify'
      else 'document_version.reject'
    end,
    'document_version', v_version.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.verify_document_version(
  uuid, uuid, integer, bigint, text, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.verify_document_version(
  uuid, uuid, integer, bigint, text, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.verify_document_version(
  uuid, uuid, integer, bigint, text, uuid, uuid, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- transition_document_status: the STM-008 transition matrix, evaluated server
-- side (mirrors P2-D01's update_membership_status). Covers supersede and
-- archive; 'available'/'verified'/'rejected' are produced by the content and
-- verification commands above, and 'processing' by no command yet.
-- -----------------------------------------------------------------------------

create function public.transition_document_status(
  p_workspace_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_target_status text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_superseded_by_document_id uuid default null,
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
  v_document public.documents%rowtype;
  v_successor public.documents%rowtype;
  v_allowed boolean;
  v_old_values jsonb;
  v_new_values jsonb;
  v_now timestamptz := now();
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Document id and expected version are required'
      )
    );
  end if;

  if p_target_status is null or p_target_status not in ('superseded', 'archived') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Only supersede and archive transitions are commandable',
        'field', 'target_status'
      )
    );
  end if;

  if p_target_status = 'superseded' and p_superseded_by_document_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A superseding document is required',
        'field', 'superseded_by_document_id'
      )
    );
  end if;

  if p_target_status = 'archived' and p_superseded_by_document_id is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Archiving does not take a superseding document',
        'field', 'superseded_by_document_id'
      )
    );
  end if;

  if p_superseded_by_document_id = p_document_id then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A document cannot supersede itself',
        'field', 'superseded_by_document_id'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_document_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'document_id', p_document_id,
        'expected_version', p_expected_version,
        'target_status', p_target_status,
        'superseded_by_document_id', p_superseded_by_document_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the transition is exactly what the
  -- matrix below reads.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select document.*
  into v_document
  from public.documents as document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  if v_document.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Document version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_document.version,
        'current_entity', private.document_snapshot(v_document)
      )
    );
  end if;

  -- STM-008 matrix: available|verified -> superseded; any non-archived state
  -- may be archived; archived is terminal.
  v_allowed := case
    when p_target_status = 'superseded'
      then v_document.status in ('available', 'verified')
    when p_target_status = 'archived'
      then v_document.status <> 'archived'
    else false
  end;

  if not v_allowed then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format('Transition %s -> %s is not permitted', v_document.status, p_target_status),
        'current_status', v_document.status,
        'target_status', p_target_status
      )
    );
  end if;

  if p_superseded_by_document_id is not null then
    select document.*
    into v_successor
    from public.documents as document
    where document.workspace_id = p_workspace_id
      and document.id = p_superseded_by_document_id;

    if not found then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object('code', 'not_found', 'message', 'Superseding document not found')
      );
    end if;

    if v_successor.status in ('superseded', 'archived', 'rejected') then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'The superseding document is not itself active'
        )
      );
    end if;
  end if;

  v_old_values := private.document_snapshot(v_document);

  update public.documents as document
  set
    status = p_target_status::public.document_status,
    superseded_by_document_id = coalesce(
      p_superseded_by_document_id, document.superseded_by_document_id
    ),
    archived_at = case when p_target_status = 'archived' then v_now else document.archived_at end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = document.version + 1
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id
  returning * into v_document;

  v_new_values := private.document_snapshot(v_document);

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when p_target_status = 'superseded'
      then 'document.supersede'
      else 'document.archive'
    end,
    'document', v_document.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.transition_document_status(
  uuid, uuid, bigint, text, uuid, uuid, uuid, text
) owner to postgres;
revoke all on function public.transition_document_status(
  uuid, uuid, bigint, text, uuid, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.transition_document_status(
  uuid, uuid, bigint, text, uuid, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- link_document / unlink_document (DocumentLinkPort).
-- -----------------------------------------------------------------------------

create function public.link_document(
  p_workspace_id uuid,
  p_document_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_link_role text default null,
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
  v_entity_type public.document_link_entity_type;
  v_ref_state text;
  v_request_hash bytea;
  v_claim jsonb;
  v_link public.document_links%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_id is null or p_entity_id is null or p_entity_type is null
     or not exists (
       select 1 from unnest(enum_range(null::public.document_link_entity_type)) as allowed
       where allowed::text = p_entity_type
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Document, entity type and entity id are required',
        'field', 'entity_type'
      )
    );
  end if;
  v_entity_type := p_entity_type::public.document_link_entity_type;

  if p_link_role is not null and char_length(btrim(p_link_role)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Link role is invalid', 'field', 'link_role'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'link_document',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'document_id', p_document_id,
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'link_role', p_link_role,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the link this command creates is
  -- what the duplicate check below rejects.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document_link'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if not exists (
    select 1 from public.documents as document
    where document.workspace_id = p_workspace_id and document.id = p_document_id
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  v_ref_state := private.document_entity_ref_state(p_workspace_id, v_entity_type, p_entity_id);

  if v_ref_state = 'unmigrated' then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', format('The %s domain has not been migrated yet', p_entity_type),
        'field', 'entity_type'
      )
    );
  end if;

  if v_ref_state <> 'ok' then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Linked entity not found')
    );
  end if;

  if exists (
    select 1 from public.document_links as link
    where link.workspace_id = p_workspace_id
      and link.document_id = p_document_id
      and link.entity_type = v_entity_type
      and link.entity_id = p_entity_id
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'The document is already linked to this entity'
      )
    );
  end if;

  insert into public.document_links (
    workspace_id, document_id, entity_type, entity_id, link_role, created_by
  ) values (
    p_workspace_id, p_document_id, v_entity_type, p_entity_id,
    nullif(btrim(coalesce(p_link_role, '')), ''), v_actor_id
  )
  returning * into v_link;

  v_new_values := private.document_link_snapshot(v_link);
  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'document_link.create', 'document_link', v_link.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.link_document(uuid, uuid, text, uuid, uuid, uuid, text, text)
  owner to postgres;
revoke all on function public.link_document(uuid, uuid, text, uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.link_document(uuid, uuid, text, uuid, uuid, uuid, text, text)
  to authenticated;

create function public.unlink_document(
  p_workspace_id uuid,
  p_document_link_id uuid,
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
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_link public.document_links%rowtype;
  v_old_values jsonb;
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_document_link_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Document link id is required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'unlink_document',
        'actor_id', auth.uid(),
        'workspace_id', p_workspace_id,
        'document_link_id', p_document_link_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the row this command deletes is
  -- what the lookup below requires.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'document_link'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select link.*
  into v_link
  from public.document_links as link
  where link.workspace_id = p_workspace_id
    and link.id = p_document_link_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document link not found')
    );
  end if;

  v_old_values := private.document_link_snapshot(v_link);

  delete from public.document_links
  where id = v_link.id;

  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'document_link.delete', 'document_link', v_link.id, v_old_values, v_old_values
  );
  return jsonb_build_object('ok', true, 'entity', v_old_values);
end;
$$;

alter function public.unlink_document(uuid, uuid, uuid, uuid, text) owner to postgres;
revoke all on function public.unlink_document(uuid, uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.unlink_document(uuid, uuid, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- upsert_required_document (RequirementPolicyRepository): the single write path
-- for the consolidated DUP-011 model. entity_id null writes a workspace-wide
-- rule; entity_id set writes the instance-level requirement that replaces the
-- legacy per-property checklist row.
-- -----------------------------------------------------------------------------

create function public.upsert_required_document(
  p_workspace_id uuid,
  p_entity_type text,
  p_document_type_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_entity_id uuid default null,
  p_scope_key text default null,
  p_is_mandatory boolean default true,
  p_due_at date default null,
  p_validity_months integer default null,
  p_owner_user_id uuid default null,
  p_note text default null,
  p_requested boolean default false,
  p_waived boolean default false,
  p_waiver_reason text default null,
  p_retired boolean default false,
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
  v_entity_type public.document_link_entity_type;
  v_scope_key text;
  v_ref_state text;
  v_request_hash bytea;
  v_claim jsonb;
  v_existing public.required_documents%rowtype;
  v_requirement public.required_documents%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_action text;
  v_now timestamptz := now();
begin
  v_gate := private.document_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_entity_type is null or not exists (
    select 1 from unnest(enum_range(null::public.document_link_entity_type)) as allowed
    where allowed::text = p_entity_type
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Entity type is invalid', 'field', 'entity_type'
      )
    );
  end if;
  v_entity_type := p_entity_type::public.document_link_entity_type;

  if p_document_type_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Document type is required', 'field', 'document_type_id'
      )
    );
  end if;

  v_scope_key := nullif(btrim(coalesce(p_scope_key, '')), '');
  if v_scope_key is not null and char_length(v_scope_key) > 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Scope key is too long', 'field', 'scope_key'
      )
    );
  end if;

  if p_validity_months is not null and p_validity_months not between 1 and 1200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Validity must be between 1 and 1200 months', 'field', 'validity_months'
      )
    );
  end if;

  if p_note is not null and char_length(p_note) > 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Note is too long', 'field', 'note'
      )
    );
  end if;

  if coalesce(p_waived, false)
     and (p_waiver_reason is null or char_length(btrim(p_waiver_reason)) not between 1 and 2000) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A waiver requires a reason', 'field', 'waiver_reason'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.manage')
     or not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_required_document',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'scope_key', v_scope_key,
        'document_type_id', p_document_type_id,
        'is_mandatory', p_is_mandatory,
        'due_at', p_due_at,
        'validity_months', p_validity_months,
        'owner_user_id', p_owner_user_id,
        'note', p_note,
        'requested', p_requested,
        'waived', p_waived,
        'waiver_reason', p_waiver_reason,
        'retired', p_retired,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before state-dependent validation: the upsert changes the live row
  -- its own branch selection reads.
  v_claim := private.claim_document_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'required_document'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if not exists (
    select 1 from public.document_types as document_type
    where document_type.workspace_id = p_workspace_id
      and document_type.id = p_document_type_id
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document type not found')
    );
  end if;

  if p_entity_id is not null then
    v_ref_state := private.document_entity_ref_state(p_workspace_id, v_entity_type, p_entity_id);

    if v_ref_state = 'unmigrated' then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', format('The %s domain has not been migrated yet', p_entity_type),
          'field', 'entity_type'
        )
      );
    end if;

    if v_ref_state <> 'ok' then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object('code', 'not_found', 'message', 'Requirement entity not found')
      );
    end if;
  end if;

  select requirement.*
  into v_existing
  from public.required_documents as requirement
  where requirement.workspace_id = p_workspace_id
    and requirement.entity_type = v_entity_type
    and requirement.entity_id is not distinct from p_entity_id
    and requirement.scope_key is not distinct from v_scope_key
    and requirement.document_type_id = p_document_type_id
    and requirement.retired_at is null
  for update;

  if found then
    update public.required_documents as requirement
    set
      scope_key = v_scope_key,
      is_mandatory = coalesce(p_is_mandatory, true),
      due_at = p_due_at,
      validity_months = p_validity_months,
      owner_user_id = p_owner_user_id,
      note = nullif(btrim(coalesce(p_note, '')), ''),
      requested_at = case
        when coalesce(p_requested, false) then coalesce(requirement.requested_at, v_now)
        else null
      end,
      waived_at = case when coalesce(p_waived, false) then coalesce(requirement.waived_at, v_now) else null end,
      waived_by = case when coalesce(p_waived, false) then coalesce(requirement.waived_by, v_actor_id) else null end,
      waiver_reason = case when coalesce(p_waived, false) then btrim(p_waiver_reason) else null end,
      retired_at = case when coalesce(p_retired, false) then v_now else null end,
      updated_at = v_now,
      updated_by = v_actor_id,
      version = requirement.version + 1
    where requirement.id = v_existing.id
    returning * into v_requirement;

    v_old_values := private.required_document_snapshot(v_existing);
    v_action := case
      when coalesce(p_retired, false) then 'required_document.retire'
      when coalesce(p_waived, false) and v_existing.waived_at is null then 'required_document.waive'
      else 'required_document.update'
    end;
  else
    insert into public.required_documents (
      workspace_id, entity_type, entity_id, scope_key, document_type_id,
      is_mandatory, due_at, validity_months, owner_user_id, note,
      requested_at, waived_at, waived_by, waiver_reason, retired_at,
      created_by, updated_by
    ) values (
      p_workspace_id, v_entity_type, p_entity_id, v_scope_key, p_document_type_id,
      coalesce(p_is_mandatory, true), p_due_at, p_validity_months, p_owner_user_id,
      nullif(btrim(coalesce(p_note, '')), ''),
      case when coalesce(p_requested, false) then v_now else null end,
      case when coalesce(p_waived, false) then v_now else null end,
      case when coalesce(p_waived, false) then v_actor_id else null end,
      case when coalesce(p_waived, false) then btrim(p_waiver_reason) else null end,
      case when coalesce(p_retired, false) then v_now else null end,
      v_actor_id, v_actor_id
    )
    returning * into v_requirement;

    v_old_values := null;
    v_action := 'required_document.create';
  end if;

  v_new_values := private.required_document_snapshot(v_requirement);
  perform private.finish_document_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    v_action, 'required_document', v_requirement.id, v_old_values, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.upsert_required_document(
  uuid, text, uuid, uuid, uuid, uuid, text, boolean, date, integer, uuid, text,
  boolean, boolean, text, boolean, text
) owner to postgres;
revoke all on function public.upsert_required_document(
  uuid, text, uuid, uuid, uuid, uuid, text, boolean, date, integer, uuid, text,
  boolean, boolean, text, boolean, text
) from public, anon, authenticated;
grant execute on function public.upsert_required_document(
  uuid, text, uuid, uuid, uuid, uuid, text, boolean, date, integer, uuid, text,
  boolean, boolean, text, boolean, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- evaluate_document_requirements: the DUP-011 projection. Read-only, derived,
-- never stored. Requirement rows scoped to the entity type (entity_id null) and
-- to the entity itself are evaluated together, exactly like the legacy
-- "(property_type = ? or property_type is null)" rule lookup.
--
-- The 45-day "expiring" window is carried over verbatim from the legacy
-- DocumentsRepo._resolveDocumentStatus rather than invented here.
-- -----------------------------------------------------------------------------

create function public.evaluate_document_requirements(
  p_workspace_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_scope_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entity_type public.document_link_entity_type;
  v_scope_key text := nullif(btrim(coalesce(p_scope_key, '')), '');
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_entity_id is null or p_entity_type is null
     or not exists (
       select 1 from unnest(enum_range(null::public.document_link_entity_type)) as allowed
       where allowed::text = p_entity_type
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace, entity type and entity id are required'
      )
    );
  end if;
  v_entity_type := p_entity_type::public.document_link_entity_type;

  if not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document access is not permitted')
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'entity', coalesce(
      (
        select jsonb_agg(projection order by sort_key, sort_id)
        from (
          select
            jsonb_build_object(
              'requirement_id', requirement.id,
              'document_type_id', requirement.document_type_id,
              'document_type_key', document_type.key,
              'document_type_name', document_type.name,
              'entity_type', requirement.entity_type,
              'entity_id', p_entity_id,
              'scope_key', requirement.scope_key,
              'is_mandatory', requirement.is_mandatory,
              'is_instance_rule', (requirement.entity_id is not null),
              'due_at', requirement.due_at,
              'owner_user_id', requirement.owner_user_id,
              'note', requirement.note,
              'document_id', satisfying.id,
              'document_status', satisfying.status,
              'document_valid_until', satisfying.valid_until,
              'state', case
                when requirement.waived_at is not null then 'waived'
                when satisfying.id is null and requirement.requested_at is not null then 'requested'
                when satisfying.id is null then 'missing'
                when satisfying.valid_until is not null
                  and satisfying.valid_until < current_date then 'expired'
                when satisfying.valid_until is not null
                  and satisfying.valid_until <= (current_date + 45) then 'expiring'
                when satisfying.status = 'verified' then 'satisfied'
                when satisfying.status in ('uploaded', 'processing') then 'pending_content'
                when satisfying.status = 'rejected' then 'rejected'
                else 'pending_verification'
              end
            ) as projection,
            document_type.key as sort_key,
            requirement.id as sort_id
          from public.required_documents as requirement
          join public.document_types as document_type
            on document_type.workspace_id = requirement.workspace_id
            and document_type.id = requirement.document_type_id
          left join lateral (
            select document.id, document.status, document.valid_until
            from public.documents as document
            join public.document_links as link
              on link.workspace_id = document.workspace_id
              and link.document_id = document.id
            where document.workspace_id = requirement.workspace_id
              and document.document_type_id = requirement.document_type_id
              and document.status not in ('superseded', 'archived')
              and link.entity_type = v_entity_type
              and link.entity_id = p_entity_id
            order by
              case document.status
                when 'verified' then 0
                when 'available' then 1
                when 'uploaded' then 2
                when 'processing' then 3
                else 4
              end,
              document.created_at desc,
              document.id
            limit 1
          ) as satisfying on true
          where requirement.workspace_id = p_workspace_id
            and requirement.entity_type = v_entity_type
            and requirement.retired_at is null
            and (requirement.entity_id is null or requirement.entity_id = p_entity_id)
            and (requirement.scope_key is null or requirement.scope_key = v_scope_key)
        ) as requirement_rows
      ),
      '[]'::jsonb
    )
  );
end;
$$;

alter function public.evaluate_document_requirements(uuid, text, uuid, text)
  owner to postgres;
revoke all on function public.evaluate_document_requirements(uuid, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.evaluate_document_requirements(uuid, text, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- resolve_document_content_ref (SignedUrlPort input): permission-gated
-- resolution of the storage coordinates for one version. The signed URL itself
-- is minted by the Storage API from the adapter, with the TTL clamped there
-- (300 s default, 3600 s maximum).
--
-- Named gap: this read RPC writes no audit event, so downloads are not audited.
-- Per-access logging belongs to the P2-D04 platform_audit_jobs envelope.
-- -----------------------------------------------------------------------------

create function public.resolve_document_content_ref(
  p_workspace_id uuid,
  p_document_id uuid,
  p_version_no integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_document public.documents%rowtype;
  v_version public.document_versions%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_document_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace and document are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document access is not permitted')
    );
  end if;

  select document.*
  into v_document
  from public.documents as document
  where document.workspace_id = p_workspace_id
    and document.id = p_document_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document not found')
    );
  end if;

  select document_version.*
  into v_version
  from public.document_versions as document_version
  where document_version.workspace_id = p_workspace_id
    and document_version.document_id = p_document_id
    and document_version.version_no = coalesce(p_version_no, v_document.current_version_no);

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Document version not found')
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'document_id', v_document.id,
      'workspace_id', v_document.workspace_id,
      'version_no', v_version.version_no,
      'storage_bucket', v_version.storage_bucket,
      'storage_object_path', v_version.storage_object_path,
      'content_hash', encode(v_version.content_hash, 'hex'),
      'byte_size', v_version.byte_size,
      'mime_type', v_version.mime_type,
      'original_filename', v_version.original_filename,
      'content_confirmed_at', v_version.content_confirmed_at,
      'verification_status', v_version.verification_status
    )
  );
end;
$$;

alter function public.resolve_document_content_ref(uuid, uuid, integer) owner to postgres;
revoke all on function public.resolve_document_content_ref(uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.resolve_document_content_ref(uuid, uuid, integer)
  to authenticated;
