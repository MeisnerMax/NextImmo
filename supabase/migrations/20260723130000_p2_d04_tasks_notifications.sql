-- P2-D04 increment 2 — platform_audit_jobs: the Task and Notification
-- aggregates.
--
-- Follows the P2-D02/P2-D03 vertical exactly: enveloped RPCs, optimistic
-- concurrency via p_expected_version, mutation_receipts idempotency with
-- claim-before-state-validation and receipt cleanup, append-only audit,
-- default-deny RLS, shared private helpers. No AAL2 gate — tasks and
-- notifications are ordinary workspace business data (task.read/task.manage,
-- notification.read/notification.manage), like parties and documents.
--
-- New aggregates publish their envelopes through the increment-1 helper
-- private.publish_domain_event rather than any bespoke mechanism.

create type public.task_status as enum (
  'open', 'in_progress', 'blocked', 'done', 'archived'
);

create type public.task_priority as enum ('low', 'normal', 'high');

-- -----------------------------------------------------------------------------
-- tasks: STM-012. `archived` is terminal with no delete path, so a task row
-- with a generated_key is itself the durable AGG-019 idempotency ledger — a
-- separate task_generated_instances table would be a second truth for the same
-- fact.
-- -----------------------------------------------------------------------------

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  -- Optional link to a workflow entity. Deliberately reuses the controlled
  -- document_link_entity_type registry: its values already are the workflow
  -- entities a task attaches to, and a parallel enum would be pure debt. The
  -- name is document-flavoured; the reuse is intentional.
  entity_type public.document_link_entity_type,
  entity_id uuid,
  title text not null,
  description text,
  category text,
  assigned_to uuid,
  priority public.task_priority not null default 'normal',
  status public.task_status not null default 'open',
  due_at timestamptz,
  -- AGG-019: a stable, business-level dedup key for recurring generation,
  -- distinct from the per-call mutation_id. Immutable once set.
  generated_key text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint tasks_workspace_id_key unique (workspace_id, id),
  constraint tasks_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint tasks_entity_link_check check (
    (entity_type is null) = (entity_id is null)
  ),
  constraint tasks_title_check check (
    char_length(btrim(title)) between 1 and 300
  ),
  constraint tasks_description_check check (
    description is null or char_length(description) <= 10000
  ),
  constraint tasks_category_check check (
    category is null or char_length(btrim(category)) between 1 and 100
  ),
  constraint tasks_generated_key_check check (
    generated_key is null or char_length(btrim(generated_key)) between 1 and 200
  ),
  constraint tasks_archived_marker_check check (
    (status = 'archived') = (archived_at is not null)
  ),
  constraint tasks_version_check check (version >= 1)
);

create index tasks_workspace_idx on public.tasks (workspace_id, status);
create index tasks_entity_idx
  on public.tasks (workspace_id, entity_type, entity_id)
  where entity_id is not null;
create index tasks_assignee_idx
  on public.tasks (workspace_id, assigned_to)
  where assigned_to is not null;
-- The AGG-019 ledger: at most one live task per generated key per workspace.
create unique index tasks_generated_key_unique
  on public.tasks (workspace_id, generated_key)
  where generated_key is not null;

create trigger tasks_protected_columns
before update on public.tasks
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'generated_key', 'created_at', 'created_by'
);

alter table public.tasks enable row level security;
alter table public.tasks force row level security;

create policy tasks_select_task_read
on public.tasks
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'task.read'));

revoke all on table public.tasks from anon, authenticated;
grant select on table public.tasks to authenticated;

-- -----------------------------------------------------------------------------
-- notifications: recipient-addressed, so one platform event fans out to one row
-- per recipient. A member reads their own; a holder of notification.read sees
-- the whole workspace feed.
-- -----------------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  recipient_user_id uuid not null,
  kind text not null,
  title text not null,
  body text,
  entity_type public.document_link_entity_type,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint notifications_workspace_id_key unique (workspace_id, id),
  constraint notifications_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint notifications_entity_link_check check (
    (entity_type is null) = (entity_id is null)
  ),
  constraint notifications_kind_check check (
    kind = lower(btrim(kind))
    and kind ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(kind) between 2 and 100
  ),
  constraint notifications_title_check check (
    char_length(btrim(title)) between 1 and 300
  ),
  constraint notifications_body_check check (
    body is null or char_length(body) <= 4000
  ),
  constraint notifications_version_check check (version >= 1)
);

create index notifications_recipient_idx
  on public.notifications (workspace_id, recipient_user_id, created_at desc);
create index notifications_unread_idx
  on public.notifications (workspace_id, recipient_user_id)
  where read_at is null;

create trigger notifications_protected_columns
before update on public.notifications
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'recipient_user_id', 'kind', 'created_at', 'created_by'
);

alter table public.notifications enable row level security;
alter table public.notifications force row level security;

-- The recipient always sees their own; notification.read is the admin feed.
create policy notifications_select_own_or_read
on public.notifications
for select
to authenticated
using (
  recipient_user_id = (select auth.uid())
  or private.has_workspace_permission(workspace_id, 'notification.read')
);

revoke all on table public.notifications from anon, authenticated;
grant select on table public.notifications to authenticated;

-- -----------------------------------------------------------------------------
-- Shared command helpers for the platform domain. Identical in shape to the
-- party/document helpers, one set per domain so the private inventory stays
-- explicit.
-- -----------------------------------------------------------------------------

create function private.platform_command_gate(
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
        'code', 'validation_failed', 'message', 'Command identifiers are required'
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

alter function private.platform_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.platform_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function private.claim_platform_mutation(
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
      'code', 'in_progress', 'message', 'Mutation is already in progress'
    )
  );
end;
$$;

alter function private.claim_platform_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_platform_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

create function private.finish_platform_mutation(
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

  -- The receipt's result pointer must stay a matched pair. A fan-out has a
  -- type but no single entity id, so both columns go null there; the audit row
  -- above still carries the entity_type, which is what replay looks up.
  update public.mutation_receipts
  set
    status = 'succeeded',
    result_entity_type = case when p_entity_id is null then null else p_entity_type end,
    result_entity_id = p_entity_id,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id
    and mutation_id = p_mutation_id;
end;
$$;

alter function private.finish_platform_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_platform_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

create function private.task_snapshot(task public.tasks)
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

alter function private.task_snapshot(public.tasks) owner to postgres;
revoke all on function private.task_snapshot(public.tasks)
  from public, anon, authenticated;

create function private.notification_snapshot(notification public.notifications)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', notification.id,
    'workspace_id', notification.workspace_id,
    'recipient_user_id', notification.recipient_user_id,
    'kind', notification.kind,
    'title', notification.title,
    'body', notification.body,
    'entity_type', notification.entity_type,
    'entity_id', notification.entity_id,
    'read_at', notification.read_at,
    'created_at', notification.created_at,
    'updated_at', notification.updated_at,
    'created_by', notification.created_by,
    'updated_by', notification.updated_by,
    'version', notification.version
  );
$$;

alter function private.notification_snapshot(public.notifications) owner to postgres;
revoke all on function private.notification_snapshot(public.notifications)
  from public, anon, authenticated;

-- STM-012 transition matrix. `archived` is terminal; `done -> open` is the
-- audited reopen. Kept explicit rather than "any active -> any active".
create function private.task_status_can_transition(
  p_from public.task_status,
  p_to public.task_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_from
    when 'open' then p_to in ('in_progress', 'blocked', 'archived')
    when 'in_progress' then p_to in ('blocked', 'done', 'open', 'archived')
    when 'blocked' then p_to in ('in_progress', 'done', 'open', 'archived')
    when 'done' then p_to in ('open', 'archived')
    when 'archived' then false
    else false
  end;
$$;

alter function private.task_status_can_transition(public.task_status, public.task_status)
  owner to postgres;
revoke all on function private.task_status_can_transition(public.task_status, public.task_status)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_task: register a task. Two idempotency layers — the per-call
-- mutation_id (replay) and, if provided, the business-level generated_key
-- (AGG-019: the same recurring instance returns the existing task, not a
-- duplicate and not a conflict).
-- -----------------------------------------------------------------------------

create function public.create_task(
  p_workspace_id uuid,
  p_title text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_description text default null,
  p_category text default null,
  p_assigned_to uuid default null,
  p_priority text default 'normal',
  p_due_at timestamptz default null,
  p_generated_key text default null,
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
  v_existing public.tasks%rowtype;
  v_task public.tasks%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.platform_command_gate(
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

  if (p_entity_type is null) <> (p_entity_id is null) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An entity link needs both a type and an id',
        'field', 'entity_type'
      )
    );
  end if;

  if p_priority is null or p_priority not in ('low', 'normal', 'high') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Priority is invalid', 'field', 'priority'
      )
    );
  end if;

  if p_description is not null and char_length(p_description) > 10000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Description is too long', 'field', 'description'
      )
    );
  end if;

  if p_category is not null and char_length(btrim(p_category)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Category is invalid', 'field', 'category'
      )
    );
  end if;

  if p_generated_key is not null
     and char_length(btrim(p_generated_key)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Generated key is invalid', 'field', 'generated_key'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'task.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Task management is not permitted')
    );
  end if;

  -- The assignee, if any, must be an active member of the workspace.
  if p_assigned_to is not null and not exists (
    select 1 from public.memberships as membership
    where membership.workspace_id = p_workspace_id
      and membership.user_id = p_assigned_to
      and membership.status = 'active'::public.membership_status
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Assignee must be an active workspace member',
        'field', 'assigned_to'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_task',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'title', btrim(p_title),
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'description', p_description,
        'category', p_category,
        'assigned_to', p_assigned_to,
        'priority', p_priority,
        'due_at', p_due_at,
        'generated_key', p_generated_key,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_platform_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'task'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- AGG-019: a prior generation with the same key wins. Return it as this
  -- mutation's result so a retry with a fresh mutation_id still converges.
  if p_generated_key is not null then
    select task.*
    into v_existing
    from public.tasks as task
    where task.workspace_id = p_workspace_id
      and task.generated_key = btrim(p_generated_key);

    if found then
      v_new_values := private.task_snapshot(v_existing);
      perform private.finish_platform_mutation(
        p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
        'task.generation_deduplicated', 'task', v_existing.id, null, v_new_values
      );
      return jsonb_build_object('ok', true, 'entity', v_new_values);
    end if;
  end if;

  insert into public.tasks (
    workspace_id, entity_type, entity_id, title, description, category,
    assigned_to, priority, status, due_at, generated_key, created_by, updated_by
  ) values (
    p_workspace_id,
    nullif(p_entity_type, '')::public.document_link_entity_type,
    p_entity_id,
    btrim(p_title),
    nullif(p_description, ''),
    nullif(btrim(coalesce(p_category, '')), ''),
    p_assigned_to,
    p_priority::public.task_priority,
    'open',
    p_due_at,
    nullif(btrim(coalesce(p_generated_key, '')), ''),
    v_actor_id, v_actor_id
  )
  returning * into v_task;

  v_new_values := private.task_snapshot(v_task);
  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'task.create', 'task', v_task.id, null, v_new_values
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'task.created',
    p_aggregate_type => 'task',
    p_required_permission => 'task.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_task.id,
    p_aggregate_version => v_task.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('status', v_task.status, 'assigned_to', v_task.assigned_to)
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_task(
  uuid, text, uuid, uuid, text, uuid, text, text, uuid, text, timestamptz, text, text
) owner to postgres;
revoke all on function public.create_task(
  uuid, text, uuid, uuid, text, uuid, text, text, uuid, text, timestamptz, text, text
) from public, anon, authenticated;
grant execute on function public.create_task(
  uuid, text, uuid, uuid, text, uuid, text, text, uuid, text, timestamptz, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_task: edit mutable fields with optimistic concurrency. Status is not
-- editable here — it moves only through transition_task_status.
-- -----------------------------------------------------------------------------

create function public.update_task(
  p_workspace_id uuid,
  p_task_id uuid,
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
    'title', 'description', 'category', 'assigned_to', 'priority', 'due_at'
  ];
  v_unknown_keys text[];
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.tasks%rowtype;
  v_new public.tasks%rowtype;
  v_assignee uuid;
  v_replayed jsonb;
  v_now timestamptz;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_task_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Task id and expected version are required'
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

  if p_changes ? 'title' and (
       jsonb_typeof(p_changes -> 'title') <> 'string'
       or char_length(btrim(p_changes ->> 'title')) not between 1 and 300
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is invalid', 'field', 'title'
      )
    );
  end if;

  if p_changes ? 'description' and not (
       jsonb_typeof(p_changes -> 'description') = 'null'
       or (jsonb_typeof(p_changes -> 'description') = 'string'
           and char_length(p_changes ->> 'description') <= 10000)
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Description is invalid', 'field', 'description'
      )
    );
  end if;

  if p_changes ? 'category' and not (
       jsonb_typeof(p_changes -> 'category') = 'null'
       or (jsonb_typeof(p_changes -> 'category') = 'string'
           and char_length(btrim(p_changes ->> 'category')) between 1 and 100)
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Category is invalid', 'field', 'category'
      )
    );
  end if;

  if p_changes ? 'priority' and (
       jsonb_typeof(p_changes -> 'priority') <> 'string'
       or p_changes ->> 'priority' not in ('low', 'normal', 'high')
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Priority is invalid', 'field', 'priority'
      )
    );
  end if;

  if p_changes ? 'assigned_to' and not (
       jsonb_typeof(p_changes -> 'assigned_to') = 'null'
       or jsonb_typeof(p_changes -> 'assigned_to') = 'string'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Assignee is invalid', 'field', 'assigned_to'
      )
    );
  end if;

  if p_changes ? 'due_at' and not (
       jsonb_typeof(p_changes -> 'due_at') = 'null'
       or jsonb_typeof(p_changes -> 'due_at') = 'string'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Due date is invalid', 'field', 'due_at'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'task.manage')
     or not private.has_workspace_permission(p_workspace_id, 'task.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Task update is not permitted')
    );
  end if;

  if p_changes ? 'assigned_to' and jsonb_typeof(p_changes -> 'assigned_to') = 'string' then
    v_assignee := (p_changes ->> 'assigned_to')::uuid;
    if not exists (
      select 1 from public.memberships as membership
      where membership.workspace_id = p_workspace_id
        and membership.user_id = v_assignee
        and membership.status = 'active'::public.membership_status
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Assignee must be an active workspace member',
          'field', 'assigned_to'
        )
      );
    end if;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_task',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'task_id', p_task_id,
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
        and audit.entity_type = 'task';

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

  select task.* into v_old
  from public.tasks as task
  where task.id = p_task_id and task.workspace_id = p_workspace_id
  for update;

  if not found then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Task not found')
    );
  end if;

  if v_old.status = 'archived'::public.task_status then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'An archived task cannot be edited'
      )
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Task version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.task_snapshot(v_old)
      )
    );
  end if;

  v_now := now();

  update public.tasks as task
  set
    title = case when p_changes ? 'title'
      then btrim(p_changes ->> 'title') else task.title end,
    description = case when p_changes ? 'description'
      then nullif(p_changes ->> 'description', '') else task.description end,
    category = case when p_changes ? 'category'
      then nullif(btrim(coalesce(p_changes ->> 'category', '')), '') else task.category end,
    assigned_to = case when p_changes ? 'assigned_to'
      then nullif(p_changes ->> 'assigned_to', '')::uuid else task.assigned_to end,
    priority = case when p_changes ? 'priority'
      then (p_changes ->> 'priority')::public.task_priority else task.priority end,
    due_at = case when p_changes ? 'due_at'
      then nullif(p_changes ->> 'due_at', '')::timestamptz else task.due_at end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = task.version + 1
  where task.id = p_task_id and task.workspace_id = p_workspace_id
  returning * into v_new;

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'task.update', 'task', v_new.id,
    private.task_snapshot(v_old), private.task_snapshot(v_new)
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'task.updated',
    p_aggregate_type => 'task',
    p_required_permission => 'task.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_new.id,
    p_aggregate_version => v_new.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('status', v_new.status, 'assigned_to', v_new.assigned_to)
  );
  return jsonb_build_object('ok', true, 'entity', private.task_snapshot(v_new));
end;
$$;

alter function public.update_task(uuid, uuid, bigint, uuid, uuid, jsonb, text) owner to postgres;
revoke all on function public.update_task(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.update_task(uuid, uuid, bigint, uuid, uuid, jsonb, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- transition_task_status: the STM-012 state machine, server-enforced.
-- -----------------------------------------------------------------------------

create function public.transition_task_status(
  p_workspace_id uuid,
  p_task_id uuid,
  p_expected_version bigint,
  p_to_status text,
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
  v_to public.task_status;
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.tasks%rowtype;
  v_new public.tasks%rowtype;
  v_replayed jsonb;
  v_now timestamptz;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_task_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Task id and expected version are required'
      )
    );
  end if;

  if p_to_status is null
     or p_to_status not in ('open', 'in_progress', 'blocked', 'done', 'archived') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Target status is invalid', 'field', 'to_status'
      )
    );
  end if;
  v_to := p_to_status::public.task_status;

  if not private.has_workspace_permission(p_workspace_id, 'task.manage')
     or not private.has_workspace_permission(p_workspace_id, 'task.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Task transition is not permitted')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_task_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'task_id', p_task_id,
        'expected_version', p_expected_version,
        'to_status', p_to_status,
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
        and audit.entity_type = 'task';

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

  select task.* into v_old
  from public.tasks as task
  where task.id = p_task_id and task.workspace_id = p_workspace_id
  for update;

  if not found then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Task not found')
    );
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Task version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.task_snapshot(v_old)
      )
    );
  end if;

  if v_old.status = v_to then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Task is already in that status', 'field', 'to_status'
      )
    );
  end if;

  if not private.task_status_can_transition(v_old.status, v_to) then
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

  update public.tasks as task
  set
    status = v_to,
    archived_at = case when v_to = 'archived'::public.task_status then v_now else null end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = task.version + 1
  where task.id = p_task_id and task.workspace_id = p_workspace_id
  returning * into v_new;

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'task.status_changed', 'task', v_new.id,
    private.task_snapshot(v_old), private.task_snapshot(v_new)
  );
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'task.status_changed',
    p_aggregate_type => 'task',
    p_required_permission => 'task.read',
    p_correlation_id => p_correlation_id,
    p_aggregate_id => v_new.id,
    p_aggregate_version => v_new.version,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('from', v_old.status, 'to', v_new.status)
  );
  return jsonb_build_object('ok', true, 'entity', private.task_snapshot(v_new));
end;
$$;

alter function public.transition_task_status(uuid, uuid, bigint, text, uuid, uuid, text)
  owner to postgres;
revoke all on function public.transition_task_status(uuid, uuid, bigint, text, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.transition_task_status(uuid, uuid, bigint, text, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- create_notification: fan out one platform event to one row per recipient.
-- The whole fan-out is one mutation; a replay returns the recorded batch.
-- -----------------------------------------------------------------------------

create function public.create_notification(
  p_workspace_id uuid,
  p_recipient_user_ids uuid[],
  p_kind text,
  p_title text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_body text default null,
  p_entity_type text default null,
  p_entity_id uuid default null,
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
  v_recipients uuid[];
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_replayed jsonb;
  v_ids uuid[];
  v_result jsonb;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_kind is null
     or p_kind <> lower(btrim(p_kind))
     or p_kind !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
     or char_length(p_kind) not between 2 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Kind must be a normalised key', 'field', 'kind'
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

  if p_body is not null and char_length(p_body) > 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Body is too long', 'field', 'body'
      )
    );
  end if;

  if (p_entity_type is null) <> (p_entity_id is null) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An entity link needs both a type and an id', 'field', 'entity_type'
      )
    );
  end if;

  -- Deduplicate and drop nulls; an empty recipient set is a no-op error rather
  -- than a silent success.
  select array_agg(distinct recipient)
  into v_recipients
  from unnest(coalesce(p_recipient_user_ids, array[]::uuid[])) as recipient
  where recipient is not null;

  if v_recipients is null or cardinality(v_recipients) = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'At least one recipient is required', 'field', 'recipient_user_ids'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'notification.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Notification management is not permitted')
    );
  end if;

  -- Every recipient must be an active member of the workspace: a notification
  -- to a non-member would be unreadable and would leak intent.
  if exists (
    select 1
    from unnest(v_recipients) as recipient
    where not exists (
      select 1 from public.memberships as membership
      where membership.workspace_id = p_workspace_id
        and membership.user_id = recipient
        and membership.status = 'active'::public.membership_status
    )
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Every recipient must be an active workspace member',
        'field', 'recipient_user_ids'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_notification',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'recipients', (select jsonb_agg(recipient order by recipient) from unnest(v_recipients) as recipient),
        'kind', p_kind,
        'title', btrim(p_title),
        'body', p_body,
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_replayed := private.claim_platform_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'notification_batch'
  );
  if v_replayed is not null then
    return v_replayed;
  end if;

  with inserted as (
    insert into public.notifications (
      workspace_id, recipient_user_id, kind, title, body, entity_type, entity_id,
      created_by, updated_by
    )
    select
      p_workspace_id, recipient, p_kind, btrim(p_title), nullif(p_body, ''),
      nullif(p_entity_type, '')::public.document_link_entity_type, p_entity_id,
      v_actor_id, v_actor_id
    from unnest(v_recipients) as recipient
    returning id
  )
  select array_agg(id order by id) into v_ids from inserted;

  v_result := jsonb_build_object(
    'kind', p_kind,
    'recipient_count', cardinality(v_recipients),
    'notification_ids', to_jsonb(v_ids)
  );

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'notification.fan_out', 'notification_batch', null, null, v_result
  );
  -- One coarse invalidation for the admin feed; a per-recipient wake belongs to
  -- the increment-4 consumer, not to a permission-scoped broadcast.
  perform private.publish_domain_event(
    p_workspace_id => p_workspace_id,
    p_event_type => 'notification.fanned_out',
    p_aggregate_type => 'notification_batch',
    p_required_permission => 'notification.read',
    p_correlation_id => p_correlation_id,
    p_actor_id => v_actor_id,
    p_payload => jsonb_build_object('kind', p_kind, 'recipient_count', cardinality(v_recipients))
  );
  return jsonb_build_object('ok', true, 'entity', v_result);
end;
$$;

alter function public.create_notification(
  uuid, uuid[], text, text, uuid, uuid, text, text, uuid, text
) owner to postgres;
revoke all on function public.create_notification(
  uuid, uuid[], text, text, uuid, uuid, text, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_notification(
  uuid, uuid[], text, text, uuid, uuid, text, text, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- mark_notification_read: the recipient marks their own notification read.
-- Idempotent: a second call returns the already-read row.
-- -----------------------------------------------------------------------------

create function public.mark_notification_read(
  p_workspace_id uuid,
  p_notification_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid
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
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.notifications%rowtype;
  v_new public.notifications%rowtype;
  v_replayed jsonb;
begin
  v_gate := private.platform_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, null
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_notification_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Notification id is required'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'mark_notification_read',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'notification_id', p_notification_id,
        'correlation_id', p_correlation_id
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
        and audit.entity_type = 'notification';

      if v_replayed is not null then
        return jsonb_build_object('ok', true, 'entity', v_replayed);
      end if;
    end if;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'in_progress', 'message', 'Mutation is already in progress')
    );
  end if;

  -- Only the recipient may mark their own notification read. The row is found
  -- through the recipient predicate, so a foreign notification reads as
  -- not_found rather than forbidden — it must not even confirm the row exists.
  select notification.* into v_old
  from public.notifications as notification
  where notification.id = p_notification_id
    and notification.workspace_id = p_workspace_id
    and notification.recipient_user_id = v_actor_id
  for update;

  if not found then
    delete from public.mutation_receipts where id = v_inserted_receipt_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Notification not found')
    );
  end if;

  if v_old.read_at is not null then
    -- Already read: idempotent success, no second audit row.
    perform private.finish_platform_mutation(
      p_workspace_id, p_mutation_id, p_correlation_id, null,
      'notification.read', 'notification', v_old.id, null, private.notification_snapshot(v_old)
    );
    return jsonb_build_object('ok', true, 'entity', private.notification_snapshot(v_old));
  end if;

  update public.notifications as notification
  set read_at = now(), updated_at = now(), updated_by = v_actor_id, version = notification.version + 1
  where notification.id = p_notification_id
    and notification.workspace_id = p_workspace_id
    and notification.recipient_user_id = v_actor_id
  returning * into v_new;

  perform private.finish_platform_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, null,
    'notification.read', 'notification', v_new.id,
    private.notification_snapshot(v_old), private.notification_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.notification_snapshot(v_new));
end;
$$;

alter function public.mark_notification_read(uuid, uuid, uuid, uuid) owner to postgres;
revoke all on function public.mark_notification_read(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.mark_notification_read(uuid, uuid, uuid, uuid)
  to authenticated;
