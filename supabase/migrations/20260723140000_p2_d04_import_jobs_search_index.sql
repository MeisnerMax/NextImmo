-- P2-D04 increment 3 — platform_audit_jobs: the ImportJob aggregate and the
-- derived SearchIndex.
--
-- import_jobs follows the P2-D04 increment-2 vertical exactly: enveloped RPCs,
-- optimistic concurrency via p_expected_version, mutation_receipts idempotency
-- with claim-before-state-validation and receipt cleanup, append-only audit,
-- default-deny RLS, the shared private platform_* helpers, and publication
-- through private.publish_domain_event. No AAL2 gate — an import job is
-- ordinary workspace business data (import.read / import.manage), like tasks.
--
-- search_index is the DOM-010 exception, deliberately relaxed and documented as
-- such: "Suchindex ist abgeleitet und keine Wahrheit" (the search index is
-- derived and not a source of truth). It carries NO version token, NO audit
-- record and NO mutation receipt, because a reindex is a content-addressed
-- upsert into a non-authoritative projection: it is idempotent by construction
-- (last writer wins is the correct semantics), and a receipt would wrongly
-- block a legitimate re-projection. It is the one table here that allows DELETE,
-- because stale index rows must be removable. Mutation is still RPC-only and
-- permission-gated, and reads are still default-deny RLS.

-- =============================================================================
-- import_jobs — STM-013, AGG-020.
-- =============================================================================

create type public.import_job_status as enum (
  'draft', 'validating', 'ready', 'running', 'completed', 'failed'
);

-- AGG-020 is modelled as explicit job state, not a side channel: the mapping is
-- declared up front, and the dry-run manifest, reconciliation and error report
-- are columns whose presence is tied to the status by check constraints. The
-- legacy per-target import_mappings rows collapse into `mapping` — a job targets
-- one scope, so a single mapping object is the whole mapping.
create table public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  source_kind text not null,
  target_scope text not null,
  status public.import_job_status not null default 'draft',
  mapping jsonb not null default '{}'::jsonb,
  -- Present before commit (STM-013 `ready`): the deterministic dry-run manifest
  -- and the row-count / checksum reconciliation the client computed while
  -- validating. Null until validation succeeds.
  dry_run jsonb,
  reconciliation jsonb,
  -- Set when a validation or run fails; carries the structured error report.
  error_report jsonb,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint import_jobs_workspace_id_key unique (workspace_id, id),
  constraint import_jobs_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint import_jobs_source_kind_check check (
    source_kind = lower(btrim(source_kind))
    and source_kind ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(source_kind) between 2 and 100
  ),
  constraint import_jobs_target_scope_check check (
    char_length(btrim(target_scope)) between 1 and 200
  ),
  constraint import_jobs_mapping_check check (
    jsonb_typeof(mapping) = 'object' and pg_column_size(mapping) <= 65536
  ),
  constraint import_jobs_dry_run_check check (
    dry_run is null or (jsonb_typeof(dry_run) = 'object' and pg_column_size(dry_run) <= 262144)
  ),
  constraint import_jobs_reconciliation_check check (
    reconciliation is null
    or (jsonb_typeof(reconciliation) = 'object' and pg_column_size(reconciliation) <= 65536)
  ),
  constraint import_jobs_error_report_check check (
    error_report is null
    or (jsonb_typeof(error_report) = 'object' and pg_column_size(error_report) <= 262144)
  ),
  -- AGG-020 as a schema invariant: nothing reaches `ready` (and therefore
  -- nothing commits) without a dry-run manifest AND a reconciliation.
  constraint import_jobs_commit_evidence_check check (
    (status in ('ready', 'running', 'completed'))
      <= (dry_run is not null and reconciliation is not null)
  ),
  -- A failure always carries its report.
  constraint import_jobs_failure_report_check check (
    (status = 'failed') <= (error_report is not null)
  ),
  -- A run that started (or completed) has a start stamp; a terminal job has a
  -- finish stamp exactly when it is terminal.
  constraint import_jobs_started_check check (
    (status in ('running', 'completed')) <= (started_at is not null)
  ),
  constraint import_jobs_finished_check check (
    (status in ('completed', 'failed')) = (finished_at is not null)
  ),
  constraint import_jobs_version_check check (version >= 1)
);

create index import_jobs_workspace_idx on public.import_jobs (workspace_id, status);
create index import_jobs_scope_idx
  on public.import_jobs (workspace_id, target_scope);

create trigger import_jobs_protected_columns
before update on public.import_jobs
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.import_jobs enable row level security;
alter table public.import_jobs force row level security;

create policy import_jobs_select_import_read
on public.import_jobs
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'import.read'));

revoke all on table public.import_jobs from anon, authenticated;
grant select on table public.import_jobs to authenticated;

-- =============================================================================
-- search_index — DOM-010 derived, non-authoritative projection.
-- =============================================================================

create table public.search_index (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  -- Reuses the controlled document_link_entity_type registry: the search index
  -- points at the same workflow entities, and a parallel enum would be debt.
  entity_type public.document_link_entity_type not null,
  entity_id uuid not null,
  title text not null,
  subtitle text,
  body text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  constraint search_index_workspace_id_key unique (workspace_id, id),
  constraint search_index_entity_unique unique (workspace_id, entity_type, entity_id),
  constraint search_index_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint search_index_title_check check (
    char_length(btrim(title)) between 1 and 500
  ),
  constraint search_index_subtitle_check check (
    subtitle is null or char_length(subtitle) <= 2000
  ),
  constraint search_index_body_check check (
    body is null or char_length(body) <= 20000
  )
);

create index search_index_updated_idx
  on public.search_index (workspace_id, updated_at desc);

-- Only the derived content moves; the indexed entity's identity is immutable.
create trigger search_index_protected_columns
before update on public.search_index
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'entity_type', 'entity_id', 'created_at', 'created_by'
);

alter table public.search_index enable row level security;
alter table public.search_index force row level security;

create policy search_index_select_search_read
on public.search_index
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'search.read'));

revoke all on table public.search_index from anon, authenticated;
grant select on table public.search_index to authenticated;

-- =============================================================================
-- Private helpers. The command gate / claim / finish helpers are the shared
-- platform_* set from increment 2; only the aggregate-specific snapshots and
-- the STM-013 matrix are new here.
-- =============================================================================

create function private.import_job_snapshot(import_job public.import_jobs)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', import_job.id,
    'workspace_id', import_job.workspace_id,
    'source_kind', import_job.source_kind,
    'target_scope', import_job.target_scope,
    'status', import_job.status,
    'mapping', import_job.mapping,
    'dry_run', import_job.dry_run,
    'reconciliation', import_job.reconciliation,
    'error_report', import_job.error_report,
    'started_at', import_job.started_at,
    'finished_at', import_job.finished_at,
    'created_at', import_job.created_at,
    'updated_at', import_job.updated_at,
    'created_by', import_job.created_by,
    'updated_by', import_job.updated_by,
    'version', import_job.version
  );
$$;

alter function private.import_job_snapshot(public.import_jobs) owner to postgres;
revoke all on function private.import_job_snapshot(public.import_jobs)
  from public, anon, authenticated;

create function private.search_index_snapshot(entry public.search_index)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', entry.id,
    'workspace_id', entry.workspace_id,
    'entity_type', entry.entity_type,
    'entity_id', entry.entity_id,
    'title', entry.title,
    'subtitle', entry.subtitle,
    'body', entry.body,
    'updated_at', entry.updated_at,
    'created_at', entry.created_at,
    'created_by', entry.created_by,
    'updated_by', entry.updated_by
  );
$$;

alter function private.search_index_snapshot(public.search_index) owner to postgres;
revoke all on function private.search_index_snapshot(public.search_index)
  from public, anon, authenticated;

-- STM-013 transition matrix. draft -> validating -> ready -> running ->
-- completed; failure only from validating or running; completed and failed are
-- terminal — a retry is a brand-new job, never a transition out of a terminal
-- state.
create function private.import_job_status_can_transition(
  p_from public.import_job_status,
  p_to public.import_job_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_from
    when 'draft' then p_to = 'validating'
    when 'validating' then p_to in ('ready', 'failed')
    when 'ready' then p_to = 'running'
    when 'running' then p_to in ('completed', 'failed')
    when 'completed' then false
    when 'failed' then false
    else false
  end;
$$;

alter function private.import_job_status_can_transition(
  public.import_job_status, public.import_job_status
) owner to postgres;
revoke all on function private.import_job_status_can_transition(
  public.import_job_status, public.import_job_status
) from public, anon, authenticated;

-- =============================================================================
-- create_import_job: register an import job in `draft` with its declared
-- mapping. Idempotent on mutation_id.
-- =============================================================================

create function public.create_import_job(
  p_workspace_id uuid,
  p_source_kind text,
  p_target_scope text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_mapping jsonb default '{}'::jsonb,
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
  v_job public.import_jobs%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_source_kind is null
     or p_source_kind <> lower(btrim(p_source_kind))
     or p_source_kind !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
     or char_length(p_source_kind) not between 2 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Source kind must be a normalised key', 'field', 'source_kind'
      )
    );
  end if;

  if p_target_scope is null or char_length(btrim(p_target_scope)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Target scope is required', 'field', 'target_scope'
      )
    );
  end if;

  if p_mapping is null
     or jsonb_typeof(p_mapping) <> 'object'
     or pg_column_size(p_mapping) > 65536 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Mapping must be a JSON object within the size limit', 'field', 'mapping'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'import.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Import management is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_import_job',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'source_kind', lower(btrim(p_source_kind)),
        'target_scope', btrim(p_target_scope),
        'mapping', p_mapping,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_platform_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'import_job'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  insert into public.import_jobs (
    workspace_id, source_kind, target_scope, status, mapping, created_by, updated_by
  ) values (
    p_workspace_id, lower(btrim(p_source_kind)), btrim(p_target_scope), 'draft', p_mapping,
    v_actor_id, v_actor_id
  )
  returning * into v_job;

  v_new_values := private.import_job_snapshot(v_job);
  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'import_job.create', 'import_job', v_job.id, null, v_new_values
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'import_job.created',
    p_aggregate_type => 'import_job',
    p_required_permission => 'import.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_job.id,
    p_aggregate_version => v_job.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object(
      'status', v_job.status, 'source_kind', v_job.source_kind, 'target_scope', v_job.target_scope
    )
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_import_job(uuid, text, text, uuid, uuid, jsonb, text)
  owner to postgres;
revoke all on function public.create_import_job(uuid, text, text, uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.create_import_job(uuid, text, text, uuid, uuid, jsonb, text)
  to authenticated;

-- =============================================================================
-- update_import_job: edit the mapping / source / scope of a `draft` job with
-- optimistic concurrency. Once a job leaves draft its mapping is frozen — a
-- changed mapping means a new job, so validation always reflects what will
-- commit. Status moves only through transition_import_job_status.
-- =============================================================================

create function public.update_import_job(
  p_workspace_id uuid,
  p_import_job_id uuid,
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
  v_allowed_keys constant text[] := array['source_kind', 'target_scope', 'mapping'];
  v_unknown_keys text[];
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.import_jobs%rowtype;
  v_new public.import_jobs%rowtype;
  v_replayed jsonb;
  v_now timestamptz;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_import_job_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Import job id and expected version are required'
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

  if p_changes ? 'source_kind' and (
       jsonb_typeof(p_changes -> 'source_kind') <> 'string'
       or p_changes ->> 'source_kind' <> lower(btrim(p_changes ->> 'source_kind'))
       or p_changes ->> 'source_kind' !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
       or char_length(p_changes ->> 'source_kind') not between 2 and 100
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Source kind is invalid', 'field', 'source_kind'
      )
    );
  end if;

  if p_changes ? 'target_scope' and (
       jsonb_typeof(p_changes -> 'target_scope') <> 'string'
       or char_length(btrim(p_changes ->> 'target_scope')) not between 1 and 200
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Target scope is invalid', 'field', 'target_scope'
      )
    );
  end if;

  if p_changes ? 'mapping' and not (
       jsonb_typeof(p_changes -> 'mapping') = 'object'
       and pg_column_size(p_changes -> 'mapping') <= 65536
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Mapping is invalid', 'field', 'mapping'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'import.manage')
     or not private.has_workspace_permission(p_workspace_id, 'import.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Import update is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_import_job',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'import_job_id', p_import_job_id,
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
    select receipt.* into v_receipt
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
      select audit.new_values into v_replayed
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'import_job';

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
      'error', jsonb_build_object('code', 'in_progress', 'message', 'Mutation is already in progress')
    );
  end if;

  select import_job.* into v_old
  from public.import_jobs as import_job
  where import_job.id = p_import_job_id and import_job.workspace_id = p_workspace_id
  for update;

  if not found then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Import job not found')
    );
  end if;

  if v_old.status <> 'draft'::public.import_job_status then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Only a draft import job can be edited'
      )
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Import job version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.import_job_snapshot(v_old)
      )
    );
  end if;

  v_now := now();

  update public.import_jobs as import_job
  set
    source_kind = case when p_changes ? 'source_kind'
      then lower(btrim(p_changes ->> 'source_kind')) else import_job.source_kind end,
    target_scope = case when p_changes ? 'target_scope'
      then btrim(p_changes ->> 'target_scope') else import_job.target_scope end,
    mapping = case when p_changes ? 'mapping'
      then p_changes -> 'mapping' else import_job.mapping end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = import_job.version + 1
  where import_job.id = p_import_job_id and import_job.workspace_id = p_workspace_id
  returning * into v_new;

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'import_job.update', 'import_job', v_new.id,
    private.import_job_snapshot(v_old), private.import_job_snapshot(v_new)
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'import_job.updated',
    p_aggregate_type => 'import_job',
    p_required_permission => 'import.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_new.id,
    p_aggregate_version => v_new.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('status', v_new.status)
  );
  return jsonb_build_object('ok', true, 'entity', private.import_job_snapshot(v_new));
end;
$$;

alter function public.update_import_job(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  owner to postgres;
revoke all on function public.update_import_job(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.update_import_job(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  to authenticated;

-- =============================================================================
-- transition_import_job_status: the STM-013 state machine, server-enforced.
-- The pre-commit artifacts are attached at the transition that produces them —
-- dry_run + reconciliation on `-> ready` (AGG-020), error_report on `-> failed`
-- — and no other transition may carry them.
-- =============================================================================

create function public.transition_import_job_status(
  p_workspace_id uuid,
  p_import_job_id uuid,
  p_expected_version bigint,
  p_to_status text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_dry_run jsonb default null,
  p_reconciliation jsonb default null,
  p_error_report jsonb default null,
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
  v_to public.import_job_status;
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.import_jobs%rowtype;
  v_new public.import_jobs%rowtype;
  v_replayed jsonb;
  v_now timestamptz;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_import_job_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Import job id and expected version are required'
      )
    );
  end if;

  if p_to_status is null
     or p_to_status not in ('draft', 'validating', 'ready', 'running', 'completed', 'failed') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Target status is invalid', 'field', 'to_status'
      )
    );
  end if;
  v_to := p_to_status::public.import_job_status;

  -- Artifact/target coherence: the pre-commit evidence may only ride the
  -- transition that produces it.
  if v_to = 'ready' then
    if p_dry_run is null or jsonb_typeof(p_dry_run) <> 'object'
       or p_reconciliation is null or jsonb_typeof(p_reconciliation) <> 'object' then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A dry-run manifest and a reconciliation are required before a job is ready',
          'field', 'reconciliation'
        )
      );
    end if;
    if p_error_report is not null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'An error report does not belong on a ready transition', 'field', 'error_report'
        )
      );
    end if;
  elsif v_to = 'failed' then
    if p_error_report is null or jsonb_typeof(p_error_report) <> 'object' then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'A failure requires an error report', 'field', 'error_report'
        )
      );
    end if;
    if p_dry_run is not null or p_reconciliation is not null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'A dry-run or reconciliation does not belong on a failure', 'field', 'dry_run'
        )
      );
    end if;
  else
    if p_dry_run is not null or p_reconciliation is not null or p_error_report is not null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', format('No pre-commit artifact belongs on a %s transition', p_to_status),
          'field', 'to_status'
        )
      );
    end if;
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'import.manage')
     or not private.has_workspace_permission(p_workspace_id, 'import.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Import transition is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_import_job_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'import_job_id', p_import_job_id,
        'expected_version', p_expected_version,
        'to_status', p_to_status,
        'dry_run', p_dry_run,
        'reconciliation', p_reconciliation,
        'error_report', p_error_report,
        'correlation_id', p_correlation_id,
        'reason', p_reason
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
    select receipt.* into v_receipt
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
      select audit.new_values into v_replayed
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'import_job';

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
      'error', jsonb_build_object('code', 'in_progress', 'message', 'Mutation is already in progress')
    );
  end if;

  select import_job.* into v_old
  from public.import_jobs as import_job
  where import_job.id = p_import_job_id and import_job.workspace_id = p_workspace_id
  for update;

  if not found then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Import job not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Import job version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.import_job_snapshot(v_old)
      )
    );
  end if;

  if v_old.status = v_to then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Import job is already in that status', 'field', 'to_status'
      )
    );
  end if;

  if not private.import_job_status_can_transition(v_old.status, v_to) then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format('Transition from %s to %s is not allowed', v_old.status, v_to),
        'field', 'to_status'
      )
    );
  end if;

  v_now := now();

  update public.import_jobs as import_job
  set
    status = v_to,
    dry_run = case when v_to = 'ready'::public.import_job_status then p_dry_run else import_job.dry_run end,
    reconciliation = case when v_to = 'ready'::public.import_job_status then p_reconciliation else import_job.reconciliation end,
    error_report = case when v_to = 'failed'::public.import_job_status then p_error_report else import_job.error_report end,
    started_at = case when v_to = 'running'::public.import_job_status
      then coalesce(import_job.started_at, v_now) else import_job.started_at end,
    finished_at = case when v_to in ('completed'::public.import_job_status, 'failed'::public.import_job_status)
      then v_now else import_job.finished_at end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = import_job.version + 1
  where import_job.id = p_import_job_id and import_job.workspace_id = p_workspace_id
  returning * into v_new;

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'import_job.status_changed', 'import_job', v_new.id,
    private.import_job_snapshot(v_old), private.import_job_snapshot(v_new)
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'import_job.status_changed',
    p_aggregate_type => 'import_job',
    p_required_permission => 'import.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_new.id,
    p_aggregate_version => v_new.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('from', v_old.status, 'to', v_new.status)
  );
  return jsonb_build_object('ok', true, 'entity', private.import_job_snapshot(v_new));
end;
$$;

alter function public.transition_import_job_status(
  uuid, uuid, bigint, text, uuid, uuid, jsonb, jsonb, jsonb, text
) owner to postgres;
revoke all on function public.transition_import_job_status(
  uuid, uuid, bigint, text, uuid, uuid, jsonb, jsonb, jsonb, text
) from public, anon, authenticated;
grant execute on function public.transition_import_job_status(
  uuid, uuid, bigint, text, uuid, uuid, jsonb, jsonb, jsonb, text
) to authenticated;

-- =============================================================================
-- reindex_search_entry / remove_search_entry: the derived-index write path.
-- Deliberately un-enveloped — no mutation_id, no version, no receipt, no audit,
-- no domain event — because the index is not truth (DOM-010). A reindex is a
-- content-addressed upsert keyed by (workspace, entity_type, entity_id): the
-- last writer wins, retries are idempotent by construction, and stale rows are
-- removable. The RPCs stay domain-agnostic (generic title/subtitle/body), so
-- DOM-010 carries no business models: each owning domain projects its own
-- entities into this shape.
-- =============================================================================

create function public.reindex_search_entry(
  p_workspace_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_title text,
  p_subtitle text default null,
  p_body text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_entry public.search_index%rowtype;
begin
  if v_actor_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_entity_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace and entity id are required'
      )
    );
  end if;

  if p_entity_type is null
     or not exists (
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

  if p_title is null or char_length(btrim(p_title)) not between 1 and 500 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is required', 'field', 'title'
      )
    );
  end if;

  if p_subtitle is not null and char_length(p_subtitle) > 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Subtitle is too long', 'field', 'subtitle'
      )
    );
  end if;

  if p_body is not null and char_length(p_body) > 20000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Body is too long', 'field', 'body'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'search.reindex') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Search reindex is not permitted')
    );
  end if;

  insert into public.search_index (
    workspace_id, entity_type, entity_id, title, subtitle, body, created_by, updated_by
  ) values (
    p_workspace_id, p_entity_type::public.document_link_entity_type, p_entity_id,
    btrim(p_title), nullif(p_subtitle, ''), nullif(p_body, ''), v_actor_id, v_actor_id
  )
  on conflict (workspace_id, entity_type, entity_id) do update
  set
    title = btrim(p_title),
    subtitle = nullif(p_subtitle, ''),
    body = nullif(p_body, ''),
    updated_at = now(),
    updated_by = v_actor_id
  returning * into v_entry;

  return jsonb_build_object('ok', true, 'entity', private.search_index_snapshot(v_entry));
end;
$$;

alter function public.reindex_search_entry(uuid, text, uuid, text, text, text)
  owner to postgres;
revoke all on function public.reindex_search_entry(uuid, text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.reindex_search_entry(uuid, text, uuid, text, text, text)
  to authenticated;

create function public.remove_search_entry(
  p_workspace_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_removed integer;
begin
  if v_actor_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_entity_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace and entity id are required'
      )
    );
  end if;

  if p_entity_type is null
     or not exists (
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

  if not private.has_workspace_permission(p_workspace_id, 'search.reindex') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Search reindex is not permitted')
    );
  end if;

  with deleted as (
    delete from public.search_index
    where workspace_id = p_workspace_id
      and entity_type = p_entity_type::public.document_link_entity_type
      and entity_id = p_entity_id
    returning 1
  )
  select count(*)::integer into v_removed from deleted;

  -- Idempotent: removing an absent entry is a success, not an error.
  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'workspace_id', p_workspace_id,
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'removed', v_removed > 0
    )
  );
end;
$$;

alter function public.remove_search_entry(uuid, text, uuid) owner to postgres;
revoke all on function public.remove_search_entry(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.remove_search_entry(uuid, text, uuid)
  to authenticated;
