-- =============================================================================
-- P2-D03 follow-up increment: workspace-wide requirement projection
-- (Wave 2, Arbeitspaket 2 — prerequisite of the ComplianceDashboard SCR-052).
--
-- Why this exists
-- ---------------
-- `evaluate_document_requirements(workspace, entity_type, entity_id, scope_key)`
-- is strictly per entity: it rejects a null entity id with `validation_failed`.
-- A compliance view over the whole workspace therefore had only two options,
-- both rejected:
--
--   (a) fan out one call per object — exactly the client-side N+1 loop this
--       wave removes from the dashboard;
--   (b) rebuild the derivation client-side from `listRequirements` + `search` —
--       a second truth, which `DUP-011` exists to forbid.
--
-- So the derivation stays server-side and gains a workspace-wide entry point.
--
-- How the entity set is determined (and why not by joining properties)
-- --------------------------------------------------------------------
-- Module contract rule 3 (`05_target_module_contracts.md`) forbids reading a
-- foreign module's persistence model, and DOM-006 declares no dependency on
-- DOM-002 — so this function must not join `public.properties` to discover
-- which objects exist. Instead the evaluated set is the union of:
--
--   1. instance rules, which carry their own `entity_id`;
--   2. entities that already have a `document_links` row;
--   3. entity ids the caller passes in `p_entity_ids`.
--
-- (3) is how the dashboard contributes objects that have neither a rule nor a
-- document yet: it reads the ids from the DOM-002 port — ids and DTOs across
-- module boundaries are explicitly allowed — and sends them in *one* call. The
-- derivation itself never leaves the server.
--
-- Scope keys
-- ----------
-- Per-entity evaluation narrows rules by `scope_key` (the generalised
-- `property_type`). Workspace-wide there is no per-entity scope key to match
-- against without importing portfolio vocabulary into DOM-006, so this function
-- evaluates scope-agnostic rules (`scope_key is null`) and *reports* how many
-- scoped rules it therefore skipped, rather than dropping them silently. Scoped
-- rules stay the per-entity RPC's job.
--
-- The state derivation itself is lifted into `private.document_requirement_state`
-- and the existing per-entity RPC is re-pointed at it, so the two projections
-- cannot drift — one truth, two entry points.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.document_requirement_state: the single DUP-011 state derivation.
-- Extracted verbatim from evaluate_document_requirements, including the 45-day
-- "expiring" window carried over from the legacy
-- DocumentsRepo._resolveDocumentStatus.
-- -----------------------------------------------------------------------------

create function private.document_requirement_state(
  p_waived_at timestamptz,
  p_requested_at timestamptz,
  p_document_id uuid,
  p_document_status public.document_status,
  p_document_valid_until date
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_waived_at is not null then 'waived'
    when p_document_id is null and p_requested_at is not null then 'requested'
    when p_document_id is null then 'missing'
    when p_document_valid_until is not null
      and p_document_valid_until < current_date then 'expired'
    when p_document_valid_until is not null
      and p_document_valid_until <= (current_date + 45) then 'expiring'
    when p_document_status = 'verified' then 'satisfied'
    when p_document_status in ('uploaded', 'processing') then 'pending_content'
    when p_document_status = 'rejected' then 'rejected'
    else 'pending_verification'
  end;
$$;

alter function private.document_requirement_state(
  timestamptz, timestamptz, uuid, public.document_status, date
) owner to postgres;
revoke all on function private.document_requirement_state(
  timestamptz, timestamptz, uuid, public.document_status, date
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- evaluate_document_requirements, re-pointed at the shared derivation. Signature
-- and behaviour are unchanged; only the inlined `case` is replaced.
-- -----------------------------------------------------------------------------

create or replace function public.evaluate_document_requirements(
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
              'state', private.document_requirement_state(
                requirement.waived_at,
                requirement.requested_at,
                satisfying.id,
                satisfying.status,
                satisfying.valid_until
              )
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

-- -----------------------------------------------------------------------------
-- evaluate_workspace_document_requirements: the workspace-wide projection.
-- One call, one derivation, no client aggregation.
-- -----------------------------------------------------------------------------

create function public.evaluate_workspace_document_requirements(
  p_workspace_id uuid,
  p_entity_type text default null,
  p_entity_ids uuid[] default null,
  p_only_unmet boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entity_type public.document_link_entity_type;
  v_only_unmet boolean := coalesce(p_only_unmet, false);
  v_scoped_rule_count integer;
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
        'code', 'validation_failed',
        'message', 'Workspace is required'
      )
    );
  end if;

  if p_entity_type is not null and not exists (
       select 1 from unnest(enum_range(null::public.document_link_entity_type)) as allowed
       where allowed::text = p_entity_type
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unknown entity type'
      )
    );
  end if;

  -- Caller-supplied ids only mean something together with the type they belong
  -- to; accepting them without one would silently evaluate nothing.
  if p_entity_ids is not null
     and array_length(p_entity_ids, 1) is not null
     and p_entity_type is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Entity ids require an entity type'
      )
    );
  end if;

  v_entity_type := case
    when p_entity_type is null then null
    else p_entity_type::public.document_link_entity_type
  end;

  if not private.has_workspace_permission(p_workspace_id, 'document.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Document access is not permitted')
    );
  end if;

  select count(*)::integer
  into v_scoped_rule_count
  from public.required_documents as requirement
  where requirement.workspace_id = p_workspace_id
    and requirement.retired_at is null
    and requirement.scope_key is not null
    and (v_entity_type is null or requirement.entity_type = v_entity_type);

  return jsonb_build_object(
    'ok', true,
    -- Scoped rules are not silently dropped: the caller is told how many this
    -- pass could not evaluate without importing foreign scope vocabulary.
    'scoped_rule_count', v_scoped_rule_count,
    'requirements', coalesce(
      (
        select jsonb_agg(
          projection
          order by sort_entity_type, sort_entity_id, sort_key, sort_id
        )
        from (
          select
            jsonb_build_object(
              'requirement_id', requirement.id,
              'document_type_id', requirement.document_type_id,
              'document_type_key', document_type.key,
              'document_type_name', document_type.name,
              'entity_type', requirement.entity_type,
              'entity_id', target.entity_id,
              'scope_key', requirement.scope_key,
              'is_mandatory', requirement.is_mandatory,
              'is_instance_rule', (requirement.entity_id is not null),
              'due_at', requirement.due_at,
              'owner_user_id', requirement.owner_user_id,
              'note', requirement.note,
              'document_id', satisfying.id,
              'document_status', satisfying.status,
              'document_valid_until', satisfying.valid_until,
              'state', private.document_requirement_state(
                requirement.waived_at,
                requirement.requested_at,
                satisfying.id,
                satisfying.status,
                satisfying.valid_until
              )
            ) as projection,
            requirement.entity_type as sort_entity_type,
            target.entity_id as sort_entity_id,
            document_type.key as sort_key,
            requirement.id as sort_id
          from (
            -- 1. Instance rules carry their own entity.
            select requirement.entity_type, requirement.entity_id
            from public.required_documents as requirement
            where requirement.workspace_id = p_workspace_id
              and requirement.retired_at is null
              and requirement.entity_id is not null
              and (v_entity_type is null or requirement.entity_type = v_entity_type)
            union
            -- 2. Entities that already carry a document link.
            select link.entity_type, link.entity_id
            from public.document_links as link
            where link.workspace_id = p_workspace_id
              and (v_entity_type is null or link.entity_type = v_entity_type)
            union
            -- 3. Entities the caller named — how an object with neither a rule
            --    nor a document yet still gets evaluated, without this function
            --    reading a foreign module's tables.
            select v_entity_type, supplied.entity_id
            from unnest(coalesce(p_entity_ids, array[]::uuid[])) as supplied(entity_id)
            where v_entity_type is not null
          ) as target
          join public.required_documents as requirement
            on requirement.workspace_id = p_workspace_id
            and requirement.entity_type = target.entity_type
            and requirement.retired_at is null
            and requirement.scope_key is null
            and (
              requirement.entity_id is null
              or requirement.entity_id = target.entity_id
            )
          join public.document_types as document_type
            on document_type.workspace_id = requirement.workspace_id
            and document_type.id = requirement.document_type_id
          left join lateral (
            select document.id, document.status, document.valid_until
            from public.documents as document
            join public.document_links as link
              on link.workspace_id = document.workspace_id
              and link.document_id = document.id
            where document.workspace_id = p_workspace_id
              and document.document_type_id = requirement.document_type_id
              and document.status not in ('superseded', 'archived')
              and link.entity_type = target.entity_type
              and link.entity_id = target.entity_id
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
          where not v_only_unmet
             or private.document_requirement_state(
                  requirement.waived_at,
                  requirement.requested_at,
                  satisfying.id,
                  satisfying.status,
                  satisfying.valid_until
                ) not in ('satisfied', 'waived')
        ) as requirement_rows
      ),
      '[]'::jsonb
    )
  );
end;
$$;

alter function public.evaluate_workspace_document_requirements(uuid, text, uuid[], boolean)
  owner to postgres;
revoke all on function public.evaluate_workspace_document_requirements(uuid, text, uuid[], boolean)
  from public, anon, authenticated;
grant execute on function public.evaluate_workspace_document_requirements(uuid, text, uuid[], boolean)
  to authenticated;
