-- SUPPLIER-DETAILS-01 (P-3, first half of Suppliers + Contracts).
--
-- Two gaps that `contractors_controller.dart` names in its own header, closed
-- here because both are server-side.
--
-- **1. Correcting a contractor's details is not assigning them a role.**
--
-- The satellite (`party_contractor_details`: trade, hourly rate, service area,
-- five ratings, insurance expiry) is written today only by
-- `assign_party_role`, which upserts it as a side effect of granting the
-- contractor role. So the only way to fix a wrong hourly rate is to re-assign
-- the role — and the audit trail then records `party.role.assign`, which is a
-- statement about who this company *is* to the workspace, not about a typo in
-- a number. An audit trail that describes a rate correction as a role grant is
-- worse than no audit trail, because it is confidently wrong.
--
-- It is also unversioned in practice: the satellite carries its own `version`
-- column that the upsert increments and nothing ever checks, so two people
-- editing the same contractor silently overwrite each other. `assign_party_role`
-- has no way to check it — the caller is assigning a role, and demanding the
-- satellite's version for that would be asking about the wrong thing.
--
-- `update_contractor_details` is the dedicated path: `party.manage`, optimistic
-- concurrency on the satellite's own version, idempotent by mutation id, and
-- audited as what it is.
--
-- **`assign_party_role` is deliberately left alone.** Its upsert is correct for
-- what it does — a role grant may legitimately carry the initial details — and
-- narrowing it now would break the one flow that works.
--
-- **2. "Which tickets does this contractor have" had no read.**
--
-- `maintenance_tickets.contractor_party_id` has existed since P2-D06 and is
-- indexed; nothing could filter on it. The contractor screen documents the
-- absence as a gap it declined to build around. One more parameter on
-- `workspace_maintenance_tickets` closes it — server-side, like the category
-- filter beside it, because a client-side filter over a page cannot see the
-- tickets that page does not hold.
--
-- The audit payload is `private.contractor_details_snapshot`, which P2-D02
-- already ships and `assign_party_role` already uses. Writing a second one
-- here was the first thing I tried and the wrong thing to do: two snapshot
-- functions for one table is two chances for an audit entry and a replayed
-- result to describe the same row differently.
--
-- One new public function, one recreated: SR-20 91 -> 92.

-- ---------------------------------------------------------------------------
-- The dedicated update
-- ---------------------------------------------------------------------------

create function public.update_contractor_details(
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
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_claim jsonb;
  v_request_hash bytea;
  v_old public.party_contractor_details%rowtype;
  v_new public.party_contractor_details%rowtype;
  v_key text;
  v_rating numeric;
  v_allowed_keys constant text[] := array[
    'trade_category', 'hourly_rate', 'service_area',
    'rating_price', 'rating_quality', 'rating_speed',
    'rating_communication', 'rating_punctuality',
    'insurance_cert_expiry', 'is_active'
  ];
  -- The five that share one validation rule. Named once so a sixth cannot be
  -- added to the table without this list going stale visibly.
  v_rating_keys constant text[] := array[
    'rating_price', 'rating_quality', 'rating_speed',
    'rating_communication', 'rating_punctuality'
  ];
  v_unknown_keys text[];
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_id is null or p_expected_version is null
     or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Party id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object'
     or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Changes must be a non-empty object', 'field', 'changes'
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

  -- The trade is the one field that cannot be cleared: it is what makes the
  -- row a contractor record rather than an empty satellite, and the column
  -- says so with NOT NULL.
  if p_changes ? 'trade_category' and (
       jsonb_typeof(p_changes -> 'trade_category') <> 'string'
       or char_length(btrim(p_changes ->> 'trade_category')) not between 1 and 100
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Trade category is invalid',
        'field', 'trade_category'
      )
    );
  end if;

  -- Null clears the figure, which is a real intent: "we no longer have an
  -- agreed rate" is different from "the rate is zero".
  if p_changes ? 'hourly_rate' and not (
       jsonb_typeof(p_changes -> 'hourly_rate') = 'null'
       or (
         jsonb_typeof(p_changes -> 'hourly_rate') = 'number'
         and (p_changes ->> 'hourly_rate')::numeric >= 0
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Hourly rate is invalid',
        'field', 'hourly_rate'
      )
    );
  end if;

  if p_changes ? 'service_area' and not (
       jsonb_typeof(p_changes -> 'service_area') = 'null'
       or (
         jsonb_typeof(p_changes -> 'service_area') = 'string'
         and char_length(p_changes ->> 'service_area') <= 2000
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Service area is invalid',
        'field', 'service_area'
      )
    );
  end if;

  -- One loop rather than five copies of the same six lines. The field name in
  -- the error is the one that was actually wrong, so the form can point at it.
  foreach v_key in array v_rating_keys loop
    if p_changes ? v_key then
      if jsonb_typeof(p_changes -> v_key) = 'null' then
        continue;
      end if;
      if jsonb_typeof(p_changes -> v_key) <> 'number' then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'validation_failed', 'message', 'Rating is invalid',
            'field', v_key
          )
        );
      end if;
      v_rating := (p_changes ->> v_key)::numeric;
      if v_rating < 0 or v_rating > 5 then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'validation_failed',
            'message', 'Rating must be between 0 and 5', 'field', v_key
          )
        );
      end if;
    end if;
  end loop;

  if p_changes ? 'insurance_cert_expiry' and not (
       jsonb_typeof(p_changes -> 'insurance_cert_expiry') = 'null'
       or jsonb_typeof(p_changes -> 'insurance_cert_expiry') = 'string'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Insurance expiry is invalid',
        'field', 'insurance_cert_expiry'
      )
    );
  end if;

  -- A past date is accepted on purpose. An expired certificate is a fact
  -- worth recording, and refusing it would leave the register showing the old
  -- valid one -- which is the reading that gets somebody sent to a site
  -- uninsured.
  if p_changes ? 'insurance_cert_expiry'
     and jsonb_typeof(p_changes -> 'insurance_cert_expiry') = 'string' then
    begin
      perform (p_changes ->> 'insurance_cert_expiry')::date;
    exception when others then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'Insurance expiry is invalid',
          'field', 'insurance_cert_expiry'
        )
      );
    end;
  end if;

  if p_changes ? 'is_active'
     and jsonb_typeof(p_changes -> 'is_active') <> 'boolean' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Active flag is invalid',
        'field', 'is_active'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Contractor details update is not permitted'
      )
    );
  end if;

  select details.*
  into v_old
  from public.party_contractor_details as details
  where details.workspace_id = p_workspace_id
    and details.party_id = p_party_id
  for update;

  if not found then
    -- No row means this party never held a contractor role. Creating one here
    -- would let an update invent a contractor, which is `assign_party_role`'s
    -- decision to make and not this function's.
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Contractor details not found'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_contractor_details',
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

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'party_contractor_details'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Contractor details version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.contractor_details_snapshot(v_old)
      )
    );
  end if;

  update public.party_contractor_details as details
  set
    trade_category = case
      when p_changes ? 'trade_category'
        then btrim(p_changes ->> 'trade_category')
      else details.trade_category
    end,
    hourly_rate = case
      when p_changes ? 'hourly_rate'
        then (p_changes ->> 'hourly_rate')::numeric
      else details.hourly_rate
    end,
    service_area = case
      when p_changes ? 'service_area'
        then nullif(btrim(coalesce(p_changes ->> 'service_area', '')), '')
      else details.service_area
    end,
    rating_price = case
      when p_changes ? 'rating_price'
        then (p_changes ->> 'rating_price')::numeric
      else details.rating_price
    end,
    rating_quality = case
      when p_changes ? 'rating_quality'
        then (p_changes ->> 'rating_quality')::numeric
      else details.rating_quality
    end,
    rating_speed = case
      when p_changes ? 'rating_speed'
        then (p_changes ->> 'rating_speed')::numeric
      else details.rating_speed
    end,
    rating_communication = case
      when p_changes ? 'rating_communication'
        then (p_changes ->> 'rating_communication')::numeric
      else details.rating_communication
    end,
    rating_punctuality = case
      when p_changes ? 'rating_punctuality'
        then (p_changes ->> 'rating_punctuality')::numeric
      else details.rating_punctuality
    end,
    insurance_cert_expiry = case
      when p_changes ? 'insurance_cert_expiry'
        then (p_changes ->> 'insurance_cert_expiry')::date
      else details.insurance_cert_expiry
    end,
    is_active = case
      when p_changes ? 'is_active'
        then (p_changes ->> 'is_active')::boolean
      else details.is_active
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = details.version + 1
  where details.workspace_id = p_workspace_id
    and details.party_id = p_party_id
  returning * into v_new;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    -- Its own action key. Recording a rate correction as `party.role.assign`
    -- would be an audit entry that is confidently wrong about what happened.
    'party.contractor_details.update', 'party_contractor_details', p_party_id,
    private.contractor_details_snapshot(v_old),
    private.contractor_details_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.contractor_details_snapshot(v_new)
  );
end;
$function$;

alter function public.update_contractor_details(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) owner to postgres;
revoke all on function public.update_contractor_details(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) from public, anon, authenticated;
grant execute on function public.update_contractor_details(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) to authenticated;

comment on function public.update_contractor_details(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) is
  'Corrects a contractor''s trade, rate, service area, ratings, insurance '
  'expiry or active flag. Separate from assign_party_role because correcting '
  'a rate is not granting a role, and the audit trail must say which one '
  'happened. Optimistic concurrency on the satellite''s own version, which '
  'the role-assignment path cannot check.';

-- ---------------------------------------------------------------------------
-- "Which tickets does this contractor have"
-- ---------------------------------------------------------------------------

drop function if exists public.workspace_maintenance_tickets(uuid, text, text, text);

create function public.workspace_maintenance_tickets(
  p_workspace_id uuid,
  p_status text default null,
  p_priority text default null,
  p_category text default null,
  p_contractor_party_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tickets jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace id is required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  select coalesce(jsonb_agg(private.maintenance_ticket_snapshot(ticket)
                            order by ticket.reported_at desc), '[]'::jsonb)
  into v_tickets
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and (p_status is null or ticket.status::text = p_status)
    and (p_priority is null or ticket.priority = p_priority)
    and (p_category is null or ticket.category = btrim(p_category))
    -- The column has existed since P2-D06 and is indexed; nothing could
    -- filter on it until now. Server-side like the rest, because a
    -- client-side filter cannot see the tickets its page does not hold.
    and (
      p_contractor_party_id is null
      or ticket.contractor_party_id = p_contractor_party_id
    );

  return jsonb_build_object('ok', true, 'entity', v_tickets);
end;
$function$;

alter function public.workspace_maintenance_tickets(uuid, text, text, text, uuid)
  owner to postgres;
revoke all on function public.workspace_maintenance_tickets(uuid, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.workspace_maintenance_tickets(uuid, text, text, text, uuid)
  to authenticated;

comment on function public.workspace_maintenance_tickets(uuid, text, text, text, uuid) is
  'Workspace-wide maintenance tickets, filterable by status, priority, '
  'category and the contractor they are assigned to. Every filter is applied '
  'here rather than in the client, so none of them can be narrower than the '
  'page a client happens to hold.';
