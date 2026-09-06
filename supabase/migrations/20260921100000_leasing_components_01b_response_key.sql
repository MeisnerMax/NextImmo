-- LEASING-COMPONENTS-01b: one response shape, whether or not it is a retry.
--
-- Migration 54 answers a successful component command with
-- `{"ok": true, "data": ...}`. Every other leasing command answers with
-- `"entity"`, and — this is the part that makes it a defect rather than a
-- naming preference — so does the *replay* of a component command, because the
-- replay is produced by `private.claim_leasing_mutation`, which was written
-- long before this package and returns `"entity"`.
--
-- So the same command answered in two shapes depending on whether it was a
-- first call or a retry. A client reading `data` gets null on every retry; a
-- client reading `entity` gets null on every first call. Idempotency is only
-- worth having if the retry is indistinguishable from the original, and this
-- made it distinguishable in the worst way: not by an error, but by a
-- successful response with the payload missing.
--
-- Caught while writing the adapter, not by the test that was supposed to catch
-- it. `044` asserted the replay "answers rather than erroring" with a null
-- check, and said in its own comment that the shape did not matter. It does.
-- The assertion is tightened in the same pull request to compare the replayed
-- entity's id with the original's, which is the check that would have failed.
--
-- Two bodies replaced, nothing created or dropped: SR-20 and SR-22 unchanged.
-- The two thin wrappers (`update_lease_component`, `close_lease_component`)
-- need no change — they return whatever the shared path returns.
--
-- Migration 54 is on main but has not reached staging, so no deployed client
-- has seen the old shape.

create or replace function private.apply_lease_component_update(
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

  return jsonb_build_object('ok', true, 'entity', to_jsonb(v_new));
end;
$function$;

create or replace function public.create_lease_component(
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

  return jsonb_build_object('ok', true, 'entity', to_jsonb(v_new));
end;
$function$;
