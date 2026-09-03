-- TASK-QUERY-01 (B-1): server-side My-Work query semantics.
--
-- Three deliverables, all read-side:
--
--   1. tasks.property_id — a denormalised, server-maintained property roll-up.
--      A task linked to a unit, lease, maintenance ticket or capex project
--      belongs to that entity's property for filtering purposes; the client
--      cannot compute that without N+1 reads. The column is written by a
--      BEFORE INSERT trigger only (the entity link is immutable after create —
--      update_task carries no entity field) and is protected against updates
--      like the other server-owned columns. All four child tables declare
--      property_id immutable themselves, so the roll-up can never go stale.
--
--   2. public.count_tasks — the KPI count for the My-Work header. SECURITY
--      DEFINER number 66 (SR-20 in 026 is updated in the same change), gated
--      on task.read through private.has_workspace_permission exactly like the
--      task select policy, so it can never count rows the caller could not
--      list. It mirrors the PostgREST list filters one for one.
--
--   3. search_index projection for the task-linkable sources (properties,
--      units, leases, parties, maintenance tickets, capex projects), so the
--      task center and the notification inbox can resolve entity ids to
--      display names through the existing search.read surface. DOM-010 keeps
--      the index derived and non-authoritative: triggers project on write,
--      last writer wins, and a row without a usable display name projects
--      nothing. Tasks themselves are NOT indexed — the entity-type registry
--      carries no 'task' value (TASK-ENTITY-REGISTRY-01).
--
-- No new table, no new policy (SR-22 stays 41), no new extension. Every new
-- helper lives in private, is owned by postgres and holds no client grant.

-- -----------------------------------------------------------------------------
-- 1. The property roll-up
-- -----------------------------------------------------------------------------

-- Resolves the property a workflow entity belongs to. Workspace-guarded on
-- every branch: create_task does not verify the linked entity exists, so a
-- foreign or dangling entity id must roll up to null rather than leak a
-- property id from another workspace.
create function private.task_property_rollup(
  p_workspace_id uuid,
  p_entity_type public.document_link_entity_type,
  p_entity_id uuid
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select case p_entity_type
    when 'property' then (
      select property.id
      from public.properties as property
      where property.id = p_entity_id
        and property.workspace_id = p_workspace_id
    )
    when 'unit' then (
      select unit.property_id
      from public.units as unit
      where unit.id = p_entity_id
        and unit.workspace_id = p_workspace_id
    )
    when 'lease' then (
      select lease.property_id
      from public.leases as lease
      where lease.id = p_entity_id
        and lease.workspace_id = p_workspace_id
    )
    when 'maintenance_ticket' then (
      select ticket.property_id
      from public.maintenance_tickets as ticket
      where ticket.id = p_entity_id
        and ticket.workspace_id = p_workspace_id
    )
    when 'capex_project' then (
      select project.property_id
      from public.capex_projects as project
      where project.id = p_entity_id
        and project.workspace_id = p_workspace_id
    )
    else null
  end;
$$;

alter function private.task_property_rollup(uuid, public.document_link_entity_type, uuid)
  owner to postgres;
revoke all on function private.task_property_rollup(uuid, public.document_link_entity_type, uuid)
  from public, anon, authenticated;

create function private.tasks_apply_property_rollup()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.property_id := private.task_property_rollup(
    new.workspace_id, new.entity_type, new.entity_id
  );
  return new;
end;
$$;

alter function private.tasks_apply_property_rollup() owner to postgres;
revoke all on function private.tasks_apply_property_rollup()
  from public, anon, authenticated;

-- on delete restrict matches every other property_id in the schema (units,
-- leases, maintenance_tickets, capex_projects). set null is not an option
-- anyway: the column is protected below, so the FK's internal update would be
-- rejected — restrict fails the delete instead of corrupting the roll-up.
alter table public.tasks
  add column property_id uuid
    references public.properties (id) on delete restrict;

create trigger tasks_property_rollup
before insert on public.tasks
for each row execute function private.tasks_apply_property_rollup();

-- Backfill existing rows BEFORE the column becomes protected.
update public.tasks as task
set property_id = private.task_property_rollup(
  task.workspace_id, task.entity_type, task.entity_id
)
where task.entity_id is not null;

drop trigger tasks_protected_columns on public.tasks;
create trigger tasks_protected_columns
before update on public.tasks
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'generated_key', 'created_at', 'created_by', 'property_id'
);

-- FK-covering (property_id leading) like units_property_idx/leases_property_idx,
-- and the roll-up filter (workspace_id = ? and property_id = ?) is an equality
-- on both columns, so one index serves both.
create index tasks_property_idx
  on public.tasks (property_id, workspace_id)
  where property_id is not null;

-- The due-sorted My-Work read: keyset over (due_at, id) ascending within one
-- workspace. Partial — tasks without a due date are a separate filter bucket,
-- never part of the due-ordered scan.
create index tasks_due_idx
  on public.tasks (workspace_id, due_at, id)
  where due_at is not null;

-- The RPC snapshot gains the new column. Additive: every existing consumer
-- parses unknown keys as absent-optional, and property_id is nullable.
create or replace function private.task_snapshot(task public.tasks)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', task.id,
    'workspace_id', task.workspace_id,
    'entity_type', task.entity_type,
    'entity_id', task.entity_id,
    'property_id', task.property_id,
    'title', task.title,
    'description', task.description,
    'category', task.category,
    'assigned_to', task.assigned_to,
    'priority', task.priority,
    'status', task.status,
    'due_at', task.due_at,
    'generated_key', task.generated_key,
    'archived_at', task.archived_at,
    'created_at', task.created_at,
    'updated_at', task.updated_at,
    'created_by', task.created_by,
    'updated_by', task.updated_by,
    'version', task.version
  );
$$;

-- -----------------------------------------------------------------------------
-- 2. count_tasks — the KPI count RPC
-- -----------------------------------------------------------------------------

-- SECURITY DEFINER because SR-20 pins "no public function is SECURITY INVOKER"
-- to zero; the permission gate below is therefore mandatory, not defensive —
-- it is the exact predicate of the tasks select policy, so the count can never
-- disagree with what a list read would return.
--
-- Filter semantics mirror the PostgREST list read one for one:
--   * archived tasks are excluded unless p_include_archived,
--   * p_due_from is inclusive, p_due_until exclusive (half-open day buckets),
--   * p_without_due counts only tasks without a due date and excludes a range,
--   * p_title_query is a substring match with ilike wildcards escaped.
create function public.count_tasks(
  p_workspace_id uuid,
  p_statuses text[] default null,
  p_assigned_to uuid default null,
  p_unassigned_only boolean default false,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_property_id uuid default null,
  p_due_from timestamptz default null,
  p_due_until timestamptz default null,
  p_without_due boolean default false,
  p_include_archived boolean default false,
  p_title_query text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_count bigint;
  v_pattern text;
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
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace is required'
      )
    );
  end if;

  if p_statuses is not null and exists (
    select 1 from unnest(p_statuses) as candidate(status)
    where candidate.status is null
       or candidate.status not in ('open', 'in_progress', 'blocked', 'done', 'archived')
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Status filter is invalid', 'field', 'status'
      )
    );
  end if;

  if (p_entity_type is null) <> (p_entity_id is null) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An entity filter needs both a type and an id',
        'field', 'entity_type'
      )
    );
  end if;

  if p_entity_type is not null and not exists (
    select 1
    from unnest(enum_range(null::public.document_link_entity_type)) as registered(value)
    where registered.value::text = p_entity_type
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Entity type is invalid', 'field', 'entity_type'
      )
    );
  end if;

  if coalesce(p_without_due, false)
     and (p_due_from is not null or p_due_until is not null) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A without-due filter excludes a due range',
        'field', 'due_at'
      )
    );
  end if;

  if p_assigned_to is not null and coalesce(p_unassigned_only, false) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An assignee filter excludes unassigned-only',
        'field', 'assigned_to'
      )
    );
  end if;

  if p_title_query is not null
     and char_length(btrim(p_title_query)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title query is invalid', 'field', 'title'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'task.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Task read is not permitted')
    );
  end if;

  if p_title_query is not null then
    v_pattern := '%' || replace(replace(replace(
      btrim(p_title_query), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  select count(*)
  into v_count
  from public.tasks as task
  where task.workspace_id = p_workspace_id
    and (p_statuses is null or task.status = any (p_statuses::public.task_status[]))
    and (coalesce(p_include_archived, false) or task.status <> 'archived')
    and (p_assigned_to is null or task.assigned_to = p_assigned_to)
    and (not coalesce(p_unassigned_only, false) or task.assigned_to is null)
    and (p_entity_type is null
         or (task.entity_type = p_entity_type::public.document_link_entity_type
             and task.entity_id = p_entity_id))
    and (p_property_id is null or task.property_id = p_property_id)
    and (p_due_from is null or task.due_at >= p_due_from)
    and (p_due_until is null or task.due_at < p_due_until)
    and (not coalesce(p_without_due, false) or task.due_at is null)
    and (v_pattern is null or task.title ilike v_pattern);

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object('count', v_count)
  );
end;
$$;

alter function public.count_tasks(
  uuid, text[], uuid, boolean, text, uuid, uuid, timestamptz, timestamptz,
  boolean, boolean, text
) owner to postgres;
revoke all on function public.count_tasks(
  uuid, text[], uuid, boolean, text, uuid, uuid, timestamptz, timestamptz,
  boolean, boolean, text
) from public, anon;
grant execute on function public.count_tasks(
  uuid, text[], uuid, boolean, text, uuid, uuid, timestamptz, timestamptz,
  boolean, boolean, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. search_index projection for the task-linkable sources
-- -----------------------------------------------------------------------------

-- The derived upsert. Converges on the (workspace, entity) unique key with the
-- same last-writer-wins semantics as the reindex_search_entry RPC, and only
-- ever moves the derived content columns — the protected identity columns are
-- never touched on conflict.
create function private.search_index_project(
  p_workspace_id uuid,
  p_entity_type public.document_link_entity_type,
  p_entity_id uuid,
  p_title text,
  p_actor uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_title text := left(nullif(btrim(coalesce(p_title, '')), ''), 500);
begin
  -- A source row without a usable display name projects nothing rather than
  -- violating the index's title constraint.
  if v_title is null or p_actor is null then
    return;
  end if;
  insert into public.search_index (
    workspace_id, entity_type, entity_id, title, created_by, updated_by
  ) values (
    p_workspace_id, p_entity_type, p_entity_id, v_title, p_actor, p_actor
  )
  on conflict (workspace_id, entity_type, entity_id) do update
    set title = excluded.title,
        updated_at = now(),
        updated_by = excluded.updated_by;
end;
$$;

alter function private.search_index_project(uuid, public.document_link_entity_type, uuid, text, uuid)
  owner to postgres;
revoke all on function private.search_index_project(uuid, public.document_link_entity_type, uuid, text, uuid)
  from public, anon, authenticated;

create function private.search_index_discard(
  p_workspace_id uuid,
  p_entity_type public.document_link_entity_type,
  p_entity_id uuid
)
returns void
language sql
set search_path = ''
as $$
  delete from public.search_index as entry
  where entry.workspace_id = p_workspace_id
    and entry.entity_type = p_entity_type
    and entry.entity_id = p_entity_id;
$$;

alter function private.search_index_discard(uuid, public.document_link_entity_type, uuid)
  owner to postgres;
revoke all on function private.search_index_discard(uuid, public.document_link_entity_type, uuid)
  from public, anon, authenticated;

-- One generic sync trigger for the five hard-named sources. tg_argv[0] is the
-- registry entity type, tg_argv[1] the title column, read through to_jsonb so
-- one function serves differently-shaped tables without dynamic SQL.
create function private.search_index_sync_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  if tg_op = 'DELETE' then
    perform private.search_index_discard(
      old.workspace_id, tg_argv[0]::public.document_link_entity_type, old.id
    );
    return old;
  end if;
  v_row := to_jsonb(new);
  perform private.search_index_project(
    new.workspace_id,
    tg_argv[0]::public.document_link_entity_type,
    new.id,
    v_row ->> tg_argv[1],
    coalesce((v_row ->> 'updated_by')::uuid, (v_row ->> 'created_by')::uuid)
  );
  return new;
end;
$$;

alter function private.search_index_sync_source() owner to postgres;
revoke all on function private.search_index_sync_source()
  from public, anon, authenticated;

-- Properties soft-delete (DEBT-012 delete marker): a deleted property must
-- leave the index, not linger as a resolvable name.
create function private.search_index_sync_property()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform private.search_index_discard(
      old.workspace_id, 'property'::public.document_link_entity_type, old.id
    );
    return old;
  end if;
  if new.deleted_at is not null then
    perform private.search_index_discard(
      new.workspace_id, 'property'::public.document_link_entity_type, new.id
    );
    return new;
  end if;
  perform private.search_index_project(
    new.workspace_id,
    'property'::public.document_link_entity_type,
    new.id,
    new.name,
    coalesce(new.updated_by, new.created_by)
  );
  return new;
end;
$$;

alter function private.search_index_sync_property() owner to postgres;
revoke all on function private.search_index_sync_property()
  from public, anon, authenticated;

-- Parties: soft delete and AGG merge both retire the row from resolution.
create function private.search_index_sync_party()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform private.search_index_discard(
      old.workspace_id, 'party'::public.document_link_entity_type, old.id
    );
    return old;
  end if;
  if new.deleted_at is not null or new.merged_into_party_id is not null then
    perform private.search_index_discard(
      new.workspace_id, 'party'::public.document_link_entity_type, new.id
    );
    return new;
  end if;
  perform private.search_index_project(
    new.workspace_id,
    'party'::public.document_link_entity_type,
    new.id,
    new.display_name,
    coalesce(new.updated_by, new.created_by)
  );
  return new;
end;
$$;

alter function private.search_index_sync_party() owner to postgres;
revoke all on function private.search_index_sync_party()
  from public, anon, authenticated;

-- Column-scoped UPDATE triggers: only a change to the projected content (or,
-- for the soft-deletable sources, the retirement marker) re-projects.
create trigger properties_search_index_sync
after insert or update of name, deleted_at or delete on public.properties
for each row execute function private.search_index_sync_property();

create trigger units_search_index_sync
after insert or update of unit_code or delete on public.units
for each row execute function private.search_index_sync_source('unit', 'unit_code');

create trigger leases_search_index_sync
after insert or update of lease_name or delete on public.leases
for each row execute function private.search_index_sync_source('lease', 'lease_name');

create trigger parties_search_index_sync
after insert or update of display_name, deleted_at, merged_into_party_id or delete
on public.parties
for each row execute function private.search_index_sync_party();

create trigger maintenance_tickets_search_index_sync
after insert or update of title or delete on public.maintenance_tickets
for each row execute function private.search_index_sync_source('maintenance_ticket', 'title');

create trigger capex_projects_search_index_sync
after insert or update of project_code or delete on public.capex_projects
for each row execute function private.search_index_sync_source('capex_project', 'project_code');

-- Backfill the projection for rows that predate the triggers. Same shape as
-- the trigger path: trimmed, capped at the index's title limit, skipping rows
-- without a usable name, attributed to the source row's last actor.
insert into public.search_index (
  workspace_id, entity_type, entity_id, title, created_by, updated_by
)
select source.workspace_id, source.entity_type, source.entity_id,
       left(btrim(source.title), 500), source.actor, source.actor
from (
  select property.workspace_id,
         'property'::public.document_link_entity_type as entity_type,
         property.id as entity_id, property.name as title,
         coalesce(property.updated_by, property.created_by) as actor
  from public.properties as property
  where property.deleted_at is null
  union all
  select unit.workspace_id, 'unit', unit.id, unit.unit_code,
         coalesce(unit.updated_by, unit.created_by)
  from public.units as unit
  union all
  select lease.workspace_id, 'lease', lease.id, lease.lease_name,
         coalesce(lease.updated_by, lease.created_by)
  from public.leases as lease
  union all
  select party.workspace_id, 'party', party.id, party.display_name,
         coalesce(party.updated_by, party.created_by)
  from public.parties as party
  where party.deleted_at is null and party.merged_into_party_id is null
  union all
  select ticket.workspace_id, 'maintenance_ticket', ticket.id, ticket.title,
         coalesce(ticket.updated_by, ticket.created_by)
  from public.maintenance_tickets as ticket
  union all
  select project.workspace_id, 'capex_project', project.id, project.project_code,
         coalesce(project.updated_by, project.created_by)
  from public.capex_projects as project
) as source
where nullif(btrim(coalesce(source.title, '')), '') is not null
  and source.actor is not null
on conflict (workspace_id, entity_type, entity_id) do update
  set title = excluded.title,
      updated_at = now(),
      updated_by = excluded.updated_by;
