-- NOTIFICATION-EMITTER-01 (B-2): server-side fan-out for the four V1 task
-- events (tasks_notifications_shared.md §6.3, E-T1/E-T2/E-T5/E-T6).
--
-- The B11 finding drives the design: `create_notification` requires
-- `notification.manage` FROM THE TRIGGERING USER, and neither handing every
-- task editor that permission nor routing through admins is acceptable. The
-- fan-out therefore happens server-side, inside the task mutation itself —
-- the recipient set is derivable from the row (`assigned_to`, `created_by`),
-- the actor needs no extra permission, AS-1 is structural, and the whole
-- thing shares the task command's transaction and correlation id.
--
-- Mechanically the emitter is an AFTER trigger on public.tasks rather than a
-- copy of the three RPC bodies: only the audited RPCs can write tasks (no
-- client DML grant exists), a mutation replay returns before touching the row
-- (so replays never re-emit), and a trigger cannot drift out of sync with a
-- future write path. The command's correlation id reaches the trigger through
-- a transaction-local GUC published by the shared platform command gate.
--
--   * E-T1 task.assigned    — assigned_to set to X            → X
--   * E-T2 task.unassigned  — assigned_to removed from X      → X
--   * E-T5 task.blocked     — transition to blocked           → creator
--   * E-T6 task.done        — transition to done              → creator
--
-- AS-1: the acting user is never notified (self-assign, own transitions).
-- AS-3: dedupe per (recipient, kind, entity) — while an UNREAD notification
--       of the same kind for the same task still waits in the recipient's
--       inbox, a repeat emits nothing. Reading it re-arms the triple, so a
--       later repetition is news again. (The window is possession-based, not
--       time-based: a time constant would be a second, invisible truth about
--       relevance — NOTIFICATION-RETENTION-01 owns time windows.)
--
-- Addressing: notifications must point AT the task (`/tasks/:id` deep link,
-- and the AS-3 triple needs the task as its entity), so the controlled
-- registry gains the `task` value. T-3 explicitly delegated this decision to
-- this package. Only the value itself ships here — `document`/`valuation_case`
-- and document→task linking remain TASK-ENTITY-REGISTRY-01. A task must not
-- LINK a task, so tasks gets a guard constraint (text comparison — the new
-- enum value cannot be referenced as a literal in the transaction that adds
-- it).
--
-- No new table, no new policy (SR-22 stays 41), no new public function
-- (SR-20 stays 66), no permission change.

-- -----------------------------------------------------------------------------
-- 0. Registry: the task value, and the no-self-linking guard
-- -----------------------------------------------------------------------------

alter type public.document_link_entity_type add value 'task';

alter table public.tasks
  add constraint tasks_entity_not_task_check
  check (entity_type is null or entity_type::text <> 'task');

-- -----------------------------------------------------------------------------
-- 1. The command gate publishes its context to same-transaction triggers
-- -----------------------------------------------------------------------------

-- Unchanged in every observable behaviour — including the DEC-025 AAL2 gate
-- SECURITY-AAL-ENFORCEMENT-01 put here; it additionally records the command's
-- correlation and mutation ids as transaction-local settings so the emitter
-- can audit with the command's own correlation id. Volatile now, because
-- set_config is a write.
create or replace function private.platform_command_gate(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform set_config(
    'neximmo.correlation_id', coalesce(p_correlation_id::text, ''), true
  );
  perform set_config(
    'neximmo.mutation_id', coalesce(p_mutation_id::text, ''), true
  );

  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for platform mutations'
      )
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

-- -----------------------------------------------------------------------------
-- 2. AS-3 lookup support
-- -----------------------------------------------------------------------------

-- The dedupe probe is an equality on the full triple against the recipient's
-- unread rows; partial on read_at so the index stays as small as the open
-- inbox.
create index notifications_unread_dedupe_idx
  on public.notifications (workspace_id, recipient_user_id, kind, entity_type, entity_id)
  where read_at is null;

-- -----------------------------------------------------------------------------
-- 3. The emitter
-- -----------------------------------------------------------------------------

create function private.emit_task_notification(
  p_task public.tasks,
  p_kind text,
  p_recipient uuid,
  p_actor uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_correlation uuid := coalesce(
    nullif(current_setting('neximmo.correlation_id', true), '')::uuid,
    gen_random_uuid()
  );
  v_notification_id uuid;
  v_role_key text;
begin
  -- AS-1: nobody to notify, or the actor themselves.
  if p_recipient is null or p_recipient = p_actor then
    return;
  end if;

  -- A recipient who is no longer an active member gets nothing: the row would
  -- be unreadable to them and would leak workspace activity.
  if not exists (
    select 1 from public.memberships as membership
    where membership.workspace_id = p_task.workspace_id
      and membership.user_id = p_recipient
      and membership.status = 'active'::public.membership_status
  ) then
    return;
  end if;

  -- AS-3: an unread notification of this kind for this task already waits in
  -- this recipient's inbox — a copy would be noise, not news.
  if exists (
    select 1 from public.notifications as notification
    where notification.workspace_id = p_task.workspace_id
      and notification.recipient_user_id = p_recipient
      and notification.kind = p_kind
      and notification.entity_type = 'task'
      and notification.entity_id = p_task.id
      and notification.read_at is null
  ) then
    return;
  end if;

  insert into public.notifications (
    workspace_id, recipient_user_id, kind, title, entity_type, entity_id,
    created_by, updated_by
  ) values (
    p_task.workspace_id, p_recipient, p_kind, p_task.title,
    'task', p_task.id, p_actor, p_actor
  )
  returning id into v_notification_id;

  select role.key
  into v_role_key
  from public.memberships as membership
  join public.roles as role
    on role.workspace_id = membership.workspace_id
    and role.id = membership.role_id
  where membership.workspace_id = p_task.workspace_id
    and membership.user_id = p_actor
    and membership.status = 'active'::public.membership_status;

  -- Audited append-only, in the same Vorgang: the command's correlation id
  -- ties the delivery to the task mutation that caused it. mutation_id stays
  -- null deliberately — audit_events is unique per (workspace, mutation_id)
  -- and that slot belongs to the task command's own audit row.
  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, role_key, scope_snapshot,
    action, entity_type, entity_id, parent_entity_type, parent_entity_id,
    source, correlation_id, mutation_id, reason, old_values, new_values,
    created_by, updated_by
  ) values (
    p_task.workspace_id, 'user', p_actor, v_role_key,
    jsonb_build_object('workspace_id', p_task.workspace_id),
    'notification.emitted', 'notification', v_notification_id, 'task', p_task.id,
    'rpc', v_correlation, null, null, null,
    jsonb_build_object(
      'kind', p_kind,
      'recipient_user_id', p_recipient,
      'task_id', p_task.id
    ),
    p_actor, p_actor
  );

  -- The same coarse notification.read invalidation create_notification
  -- publishes; a per-recipient wake stays NOTIFICATION-REALTIME-01 (B16).
  perform private.publish_domain_event(
    p_workspace_id => p_task.workspace_id,
    p_event_type => 'notification.fanned_out',
    p_aggregate_type => 'notification_batch',
    p_required_permission => 'notification.read',
    p_correlation_id => v_correlation,
    p_actor_id => p_actor,
    p_payload => jsonb_build_object('kind', p_kind, 'recipient_count', 1)
  );
end;
$$;

alter function private.emit_task_notification(public.tasks, text, uuid, uuid)
  owner to postgres;
revoke all on function private.emit_task_notification(public.tasks, text, uuid, uuid)
  from public, anon, authenticated;

create function private.tasks_emit_notifications()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actor uuid := coalesce(new.updated_by, new.created_by);
begin
  if tg_op = 'INSERT' then
    -- E-T1 at creation. AS-1 inside the helper filters the self-assign.
    perform private.emit_task_notification(
      new, 'task.assigned', new.assigned_to, v_actor
    );
    return null;
  end if;

  -- E-T2 then E-T1 on a reassignment: the previous assignee stops, the new
  -- one starts.
  if old.assigned_to is distinct from new.assigned_to then
    perform private.emit_task_notification(
      new, 'task.unassigned', old.assigned_to, v_actor
    );
    perform private.emit_task_notification(
      new, 'task.assigned', new.assigned_to, v_actor
    );
  end if;

  -- E-T5/E-T6: only these two transitions notify, and only the creator
  -- (AS-5: never a distribution list). archived and reopen stay silent per
  -- the closed §6.3 catalogue.
  if old.status is distinct from new.status
     and new.status in ('blocked'::public.task_status, 'done'::public.task_status) then
    perform private.emit_task_notification(
      new, 'task.' || new.status::text, new.created_by, v_actor
    );
  end if;

  return null;
end;
$$;

alter function private.tasks_emit_notifications() owner to postgres;
revoke all on function private.tasks_emit_notifications()
  from public, anon, authenticated;

create trigger tasks_emit_notifications
after insert or update of assigned_to, status on public.tasks
for each row execute function private.tasks_emit_notifications();
