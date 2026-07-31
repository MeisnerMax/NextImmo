-- P2-D07 (Welle 5, AP6): Bewertungsvarianten.
--
-- A variant is a full valuation case — own factors, own version, own status,
-- own report — that belongs to a named group with its siblings. That is the
-- decision recorded as DEC-023: grouping lives in two columns of its own rather
-- than in `scenario_id` (which would re-couple the legacy scenario semantics
-- this wave just decoupled) or in title conventions (implicit semantics with no
-- constraint behind them).
--
-- The two columns move together: a case is either standalone (both null) or a
-- named member of a group (both set). The check constraint is what makes that
-- structural instead of conventional, and the unique index keeps two variants
-- of one group from carrying the same name.
--
-- Only one new command is added. `create_valuation_variant` copies an existing
-- case — configuration and factors — into a new case in the same group. It
-- deliberately does *not* copy the report: a variant that arrived with somebody
-- else's published result would be the exact kind of borrowed number this
-- rewrite removes. The copy starts as a draft and has to be computed and
-- published on its own.
--
-- Existing RPC signatures are untouched. Adding optional parameters to
-- `create_valuation_case`/`update_valuation_case` would have meant dropping and
-- recreating two large functions for a field neither of them needs.

alter table public.valuation_cases
  add column variant_group_id uuid,
  add column variant_label text;

alter table public.valuation_cases
  add constraint valuation_cases_variant_pair_check check (
    (variant_group_id is null) = (variant_label is null)
  ),
  add constraint valuation_cases_variant_label_check check (
    variant_label is null
    or char_length(btrim(variant_label)) between 1 and 120
  );

create index valuation_cases_variant_group_idx
  on public.valuation_cases (workspace_id, variant_group_id)
  where variant_group_id is not null;

create unique index valuation_cases_variant_label_unique
  on public.valuation_cases (workspace_id, variant_group_id, variant_label)
  where variant_group_id is not null;

-- -----------------------------------------------------------------------------
-- Snapshot carries the grouping, so every RPC result and every audit row shows
-- which variant it was.
-- -----------------------------------------------------------------------------

create or replace function private.valuation_case_snapshot(
  valuation_case public.valuation_cases
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', valuation_case.id,
    'workspace_id', valuation_case.workspace_id,
    'property_id', valuation_case.property_id,
    'scenario_id', valuation_case.scenario_id,
    'title', valuation_case.title,
    'kind', valuation_case.kind,
    'status', valuation_case.status,
    'dcf_terminal', valuation_case.dcf_terminal,
    'enabled_methods', to_jsonb(valuation_case.enabled_methods),
    'weight_overrides', valuation_case.weight_overrides,
    'minimum_comparables', valuation_case.minimum_comparables,
    'variant_group_id', valuation_case.variant_group_id,
    'variant_label', valuation_case.variant_label,
    'approved_at', valuation_case.approved_at,
    'approved_by', valuation_case.approved_by,
    'archived_at', valuation_case.archived_at,
    'created_at', valuation_case.created_at,
    'updated_at', valuation_case.updated_at,
    'created_by', valuation_case.created_by,
    'updated_by', valuation_case.updated_by,
    'version', valuation_case.version
  );
$$;

-- -----------------------------------------------------------------------------
-- create_valuation_variant: copy a case into a sibling variant.
-- -----------------------------------------------------------------------------

create function public.create_valuation_variant(
  p_workspace_id uuid,
  p_source_valuation_case_id uuid,
  p_variant_label text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_source_variant_label text default 'Basis',
  p_title text default null,
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
  v_source public.valuation_cases%rowtype;
  v_variant public.valuation_cases%rowtype;
  v_group_id uuid;
  v_label text := btrim(coalesce(p_variant_label, ''));
  v_source_label text := btrim(coalesce(p_source_variant_label, 'Basis'));
  v_new_values jsonb;
begin
  v_gate := private.valuation_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_source_valuation_case_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Source valuation case is required'
      )
    );
  end if;

  if char_length(v_label) not between 1 and 120
     or char_length(v_source_label) not between 1 and 120 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Variant labels must contain between 1 and 120 characters',
        'field', 'variant_label'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'valuation.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Valuation management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_valuation_variant',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'source_valuation_case_id', p_source_valuation_case_id,
        'variant_label', v_label,
        'source_variant_label', v_source_label,
        'title', p_title,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  -- Claim before reading state: the command may write the source row's group,
  -- so a replay has to resolve from the receipt rather than re-deriving it.
  v_claim := private.claim_valuation_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'valuation_case'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select valuation_case.*
  into v_source
  from public.valuation_cases as valuation_case
  where valuation_case.workspace_id = p_workspace_id
    and valuation_case.id = p_source_valuation_case_id
  for update;

  if not found then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Valuation case not found')
    );
  end if;

  -- A group is formed on first use: the source keeps its own name inside it.
  if v_source.variant_group_id is null then
    v_group_id := gen_random_uuid();
    update public.valuation_cases as valuation_case
    set
      variant_group_id = v_group_id,
      variant_label = v_source_label,
      updated_at = now(),
      updated_by = v_actor_id,
      version = valuation_case.version + 1
    where valuation_case.workspace_id = p_workspace_id
      and valuation_case.id = p_source_valuation_case_id;
  else
    v_group_id := v_source.variant_group_id;
    if v_source.variant_label = v_label then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A variant with this name already exists in the group',
          'field', 'variant_label'
        )
      );
    end if;
  end if;

  if exists (
    select 1
    from public.valuation_cases as sibling
    where sibling.workspace_id = p_workspace_id
      and sibling.variant_group_id = v_group_id
      and sibling.variant_label = v_label
  ) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A variant with this name already exists in the group',
        'field', 'variant_label'
      )
    );
  end if;

  insert into public.valuation_cases (
    workspace_id, property_id, scenario_id, title, kind, dcf_terminal,
    enabled_methods, weight_overrides, minimum_comparables,
    variant_group_id, variant_label, created_by, updated_by
  ) values (
    p_workspace_id,
    v_source.property_id,
    v_source.scenario_id,
    coalesce(nullif(btrim(coalesce(p_title, '')), ''), v_source.title),
    v_source.kind,
    v_source.dcf_terminal,
    v_source.enabled_methods,
    v_source.weight_overrides,
    v_source.minimum_comparables,
    v_group_id,
    v_label,
    v_actor_id,
    v_actor_id
  )
  returning * into v_variant;

  -- Factors are copied with their provenance intact: a suggestion stays an
  -- unconfirmed suggestion in the variant, because confirming it for one
  -- variant says nothing about the other.
  insert into public.valuation_factors (
    workspace_id, valuation_case_id, factor_id, label, provenance, value,
    unit, source, note, confidence, created_by, updated_by
  )
  select
    p_workspace_id,
    v_variant.id,
    factor.factor_id,
    factor.label,
    factor.provenance,
    factor.value,
    factor.unit,
    factor.source,
    factor.note,
    factor.confidence,
    v_actor_id,
    v_actor_id
  from public.valuation_factors as factor
  where factor.workspace_id = p_workspace_id
    and factor.valuation_case_id = p_source_valuation_case_id;

  v_new_values := private.valuation_case_detail(v_variant);
  perform private.finish_valuation_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'valuation_case.variant_create', 'valuation_case', v_variant.id,
    private.valuation_case_snapshot(v_source), v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$$;

alter function public.create_valuation_variant(
  uuid, uuid, text, uuid, uuid, text, text, text
) owner to postgres;
revoke all on function public.create_valuation_variant(
  uuid, uuid, text, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_valuation_variant(
  uuid, uuid, text, uuid, uuid, text, text, text
) to authenticated;
