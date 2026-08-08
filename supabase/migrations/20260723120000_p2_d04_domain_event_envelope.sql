-- P2-D04 increment 1 — platform_audit_jobs: the CTR-005 domain event envelope.
--
-- Generalises the two invalidation mechanisms proven in Phase 1 into one:
--   * P1-011 publishes whole tables to `supabase_realtime`. That works for a
--     parent row, but not for child tables: a DELETE payload carries only the
--     replica identity columns, so a workspace_id filter is impossible without
--     REPLICA IDENTITY FULL, and bumping the parent row to signal a child
--     change would move the optimistic-concurrency token under live clients.
--     P2-D03 hit exactly this and deferred cross-table invalidation to here.
--   * P1-017 broadcasts through `realtime.send()` on a per-user topic, with an
--     RLS policy on realtime.messages and graceful degradation when the
--     broadcast is unavailable.
--
-- This migration takes P1-017's shape and generalises it: a durable append-only
-- outbox (`domain_events`) is the truth, the broadcast is only transport. A
-- failed broadcast must never fail the mutation that produced it.
--
-- Permission scoping: an envelope is readable only by callers holding the
-- permission the *source* aggregate requires, carried on the row itself as
-- `required_permission`. A workspace-wide stream would otherwise leak the
-- existence and ids of rows the reader may not see — a document link event
-- reaching someone without `document.read`, for instance.
--
-- Retention follows the OPN-DOM-005 default already applied in P2-D03: no
-- automatic deletion, and no DELETE policy at all.

-- -----------------------------------------------------------------------------
-- domain_events: the CTR-005 envelope, append-only.
-- -----------------------------------------------------------------------------

create table public.domain_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  event_type text not null,
  schema_version integer not null default 1,
  -- CTR-005 names aggregateId; the type is carried alongside it because an id
  -- alone does not identify an aggregate across domains.
  aggregate_type text not null,
  aggregate_id uuid,
  aggregate_version bigint,
  -- The permission a reader must hold for this envelope, mirroring the source
  -- aggregate's own read gate.
  required_permission text not null,
  occurred_at timestamptz not null default now(),
  actor_id uuid,
  correlation_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint domain_events_workspace_id_key unique (workspace_id, id),
  constraint domain_events_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint domain_events_event_type_check check (
    event_type = lower(btrim(event_type))
    and event_type ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)+$'
    and char_length(event_type) between 3 and 100
  ),
  constraint domain_events_aggregate_type_check check (
    aggregate_type = lower(btrim(aggregate_type))
    and aggregate_type ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(aggregate_type) between 2 and 100
  ),
  constraint domain_events_required_permission_check check (
    required_permission = lower(btrim(required_permission))
    and required_permission ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(required_permission) between 2 and 100
  ),
  constraint domain_events_schema_version_check check (schema_version >= 1),
  constraint domain_events_aggregate_version_check check (
    aggregate_version is null or aggregate_version >= 1
  ),
  -- The envelope is a pointer, not a copy: it carries identifiers and state
  -- keys so a client knows what to refetch, never business field values. The
  -- size ceiling keeps that honest.
  constraint domain_events_payload_check check (
    jsonb_typeof(payload) = 'object'
    and pg_column_size(payload) <= 4096
  ),
  constraint domain_events_version_check check (version >= 1)
);

create index domain_events_workspace_idx
  on public.domain_events (workspace_id, occurred_at desc);
create index domain_events_aggregate_idx
  on public.domain_events (workspace_id, aggregate_type, aggregate_id)
  where aggregate_id is not null;
create index domain_events_correlation_idx
  on public.domain_events (workspace_id, correlation_id);

create function private.reject_domain_event_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'domain_events is append-only' using errcode = 'P0001';
end;
$$;

alter function private.reject_domain_event_change() owner to postgres;
revoke all on function private.reject_domain_event_change()
from public, anon, authenticated;

-- Append-only is structural, not conventional: there is no update or delete
-- path, and no DELETE policy either.
create trigger domain_events_reject_update
before update on public.domain_events
for each row execute function private.reject_domain_event_change();

create trigger domain_events_reject_delete
before delete on public.domain_events
for each row execute function private.reject_domain_event_change();

alter table public.domain_events enable row level security;
alter table public.domain_events force row level security;

create policy domain_events_select_scoped
on public.domain_events
for select
to authenticated
using (private.has_workspace_permission(workspace_id, required_permission));

revoke all on table public.domain_events from anon, authenticated;
grant select on table public.domain_events to authenticated;

-- -----------------------------------------------------------------------------
-- Broadcast transport. Topic shape: `workspace:<workspace_id>:<permission>`.
-- -----------------------------------------------------------------------------

-- Safe parse of the topic's workspace segment; anything malformed yields null
-- so the policy below fails closed instead of raising.
create function private.domain_event_topic_workspace(topic text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_segment text;
begin
  if topic is null or split_part(topic, ':', 1) <> 'workspace' then
    return null;
  end if;
  v_segment := split_part(topic, ':', 2);
  if v_segment !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return null;
  end if;
  return v_segment::uuid;
exception
  when others then
    return null;
end;
$$;

alter function private.domain_event_topic_workspace(text) owner to postgres;
revoke all on function private.domain_event_topic_workspace(text) from public, anon;
-- Executable by `authenticated` because the realtime.messages policy below is
-- evaluated as that role: a policy calling a function the role cannot execute
-- raises, and a raising policy breaks realtime authorization for every
-- subscription, not just this one. Both topic helpers are pure string parsers
-- that read no data, so the grant exposes nothing. The writing helpers stay
-- ungranted.
grant execute on function private.domain_event_topic_workspace(text) to authenticated;

create function private.domain_event_topic_permission(topic text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_segment text;
begin
  if topic is null then
    return null;
  end if;
  v_segment := split_part(topic, ':', 3);
  if v_segment !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    or char_length(v_segment) not between 2 and 100 then
    return null;
  end if;
  return v_segment;
end;
$$;

alter function private.domain_event_topic_permission(text) owner to postgres;
revoke all on function private.domain_event_topic_permission(text) from public, anon;
grant execute on function private.domain_event_topic_permission(text) to authenticated;

create policy domain_event_broadcast_receive_scoped
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and private.domain_event_topic_workspace((select realtime.topic())) is not null
  and private.domain_event_topic_permission((select realtime.topic())) is not null
  and private.has_workspace_permission(
    private.domain_event_topic_workspace((select realtime.topic())),
    private.domain_event_topic_permission((select realtime.topic()))
  )
);

-- -----------------------------------------------------------------------------
-- publish_domain_event: append the outbox row, then attempt the broadcast.
-- -----------------------------------------------------------------------------

create function private.publish_domain_event(
  p_workspace_id uuid,
  p_event_type text,
  p_aggregate_type text,
  p_required_permission text,
  p_correlation_id uuid,
  p_aggregate_id uuid default null,
  p_aggregate_version bigint default null,
  p_actor_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_schema_version integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.domain_events%rowtype;
begin
  insert into public.domain_events (
    workspace_id, event_type, schema_version, aggregate_type, aggregate_id,
    aggregate_version, required_permission, actor_id, correlation_id, payload,
    created_by, updated_by
  ) values (
    p_workspace_id, p_event_type, coalesce(p_schema_version, 1), p_aggregate_type,
    p_aggregate_id, p_aggregate_version, p_required_permission, p_actor_id,
    coalesce(p_correlation_id, extensions.gen_random_uuid()), coalesce(p_payload, '{}'::jsonb),
    p_actor_id, p_actor_id
  )
  returning * into v_event;

  begin
    perform realtime.send(
      jsonb_build_object(
        'event_id', v_event.id,
        'event_type', v_event.event_type,
        'schema_version', v_event.schema_version,
        'workspace_id', v_event.workspace_id,
        'aggregate_type', v_event.aggregate_type,
        'aggregate_id', v_event.aggregate_id,
        'aggregate_version', v_event.aggregate_version,
        'occurred_at', v_event.occurred_at,
        'actor_id', v_event.actor_id,
        'correlation_id', v_event.correlation_id,
        'payload', v_event.payload
      ),
      'domain_event',
      'workspace:' || v_event.workspace_id::text || ':' || v_event.required_permission,
      true
    );
  exception
    when others then
      -- The outbox row is already durable; transport is best effort, exactly as
      -- P1-017 treats entitlement revalidation.
      raise warning 'Domain event broadcast unavailable; outbox row % remains.', v_event.id;
  end;

  return v_event.id;
end;
$$;

alter function private.publish_domain_event(
  uuid, text, text, text, uuid, uuid, bigint, uuid, jsonb, integer
) owner to postgres;
revoke all on function private.publish_domain_event(
  uuid, text, text, text, uuid, uuid, bigint, uuid, jsonb, integer
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Closes the two gaps P2-D03 deliberately left open.
--
-- (1) Cross-table invalidation for document_links / required_documents. These
--     never touch the documents row, so nothing invalidated a client's view.
--     An AFTER trigger sees the full OLD/NEW row, so DELETE is covered too.
-- -----------------------------------------------------------------------------

create function private.publish_document_link_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.document_links%rowtype := coalesce(new, old);
begin
  perform private.publish_domain_event(
    p_workspace_id => v_row.workspace_id,
    p_event_type => case when tg_op = 'DELETE'
      then 'document.unlinked' else 'document.linked' end,
    p_aggregate_type => 'document',
    p_required_permission => 'document.read',
    p_correlation_id => extensions.gen_random_uuid(),
    p_aggregate_id => v_row.document_id,
    p_actor_id => auth.uid(),
    p_payload => jsonb_build_object(
      'document_link_id', v_row.id,
      'entity_type', v_row.entity_type,
      'entity_id', v_row.entity_id
    )
  );
  return null;
end;
$$;

alter function private.publish_document_link_event() owner to postgres;
revoke all on function private.publish_document_link_event()
from public, anon, authenticated;

create trigger document_links_publish_event
after insert or delete on public.document_links
for each row execute function private.publish_document_link_event();

create function private.publish_required_document_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.publish_domain_event(
    p_workspace_id => new.workspace_id,
    p_event_type => 'document.requirement_changed',
    p_aggregate_type => 'required_document',
    p_required_permission => 'document.read',
    p_correlation_id => extensions.gen_random_uuid(),
    p_aggregate_id => new.id,
    p_aggregate_version => new.version,
    p_actor_id => auth.uid(),
    p_payload => jsonb_build_object(
      'entity_type', new.entity_type,
      'entity_id', new.entity_id,
      'document_type_id', new.document_type_id,
      'retired', new.retired_at is not null
    )
  );
  return null;
end;
$$;

alter function private.publish_required_document_event() owner to postgres;
revoke all on function private.publish_required_document_event()
from public, anon, authenticated;

create trigger required_documents_publish_event
after insert or update on public.required_documents
for each row execute function private.publish_required_document_event();

-- -----------------------------------------------------------------------------
-- (2) Per-access recording of document downloads. P2-D03 named this gap: a read
--     RPC writes no audit_events by convention, so downloads went unrecorded.
--     The access lands in the event envelope rather than in audit_events, which
--     keeps "audit_events records mutations" intact while still recording who
--     resolved which content. Only the successful branch is instrumented; a
--     refused resolve reveals nothing to record.
-- -----------------------------------------------------------------------------

-- Body is the P2-D03 original verbatim, with exactly two changes: the
-- `stable` marker is dropped (a stable function may not write) and the
-- successful branch publishes an access envelope. Every error code, message
-- and returned field is unchanged, so the P2-D03 pgTAP contract still holds.
create or replace function public.resolve_document_content_ref(
  p_workspace_id uuid,
  p_document_id uuid,
  p_version_no integer default null
)
returns jsonb
language plpgsql
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

  -- Only the successful branch is recorded: a refused resolve has nothing to
  -- report beyond what the caller already failed to reach.
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'document.content_accessed',
    p_aggregate_type => 'document',
    p_required_permission => 'document.read',
    p_correlation_id => extensions.gen_random_uuid(),
    p_aggregate_id => p_document_id,
    p_aggregate_version => v_document.version,
    p_actor_id => auth.uid(),
    p_payload => jsonb_build_object(
      'version_no', v_version.version_no,
      'storage_bucket', v_version.storage_bucket,
      'verification_status', v_version.verification_status
    )
  );

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
