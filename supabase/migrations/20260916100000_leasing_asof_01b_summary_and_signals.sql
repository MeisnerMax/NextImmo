-- LEASING-ASOF-01b: the two defects DEC-027 named, each on its own surface.
--
-- LEASING-ASOF-01 corrected the rent-roll helpers. DEC-027 named two more
-- places that decide lease effectiveness and get it wrong, and they were left
-- out of that package deliberately: each changes a different surface's
-- published numbers, and folding them in would have made one migration answer
-- for three.
--
-- -----------------------------------------------------------------------------
-- 1. `property_leasing_summary` counted a lease that had not begun
-- -----------------------------------------------------------------------------
--
-- Its rent roll filtered on `status = 'active'` and nothing else -- no start
-- bound at all. A lease signed and activated today for a term starting next
-- month had its rent in this month's roll. That is not a decision anyone took;
-- the rent-roll helpers always had the bound, this copy simply never did, and
-- no assertion covered it.
--
-- It now asks `private.lease_is_effective_on(...)` for today, which adds the
-- start bound and keeps counting a lease past its `end_date` -- the part this
-- surface always had right, and the reason it disagreed with the helpers until
-- DEC-027 settled which of them was correct.
--
-- The `lease_roll` counters above it are deliberately NOT changed. They count
-- contracts, not money: a signed lease starting next month is a real active
-- contract, and `lease_roll.active` saying so is honest. `rent_roll` claiming
-- its rent as this month's income is not. The two may therefore differ by
-- design, and that is the difference between a portfolio count and a cash
-- figure.
--
-- -----------------------------------------------------------------------------
-- 2. `operations_signals` dropped a lease on the day it became actionable
-- -----------------------------------------------------------------------------
--
-- `lease_expiry` selects leases whose end date is within 180 days -- and, until
-- now, `end_date >= current_date`. So the signal climbed from info to warning
-- to critical as the date approached, and then vanished the moment it passed.
-- The one state that always needs a human disappeared from the ladder built to
-- surface it.
--
-- The fix is a second signal type rather than a negative first one. See the
-- comment at the branch itself for why, and for what the message deliberately
-- does not claim.
--
-- `signal_type` is constrained twice -- a CHECK on
-- `public.operations_signal_states` and a validation list in
-- `public.update_operations_signal_status` -- so both are widened here. The
-- acknowledgement key already carries the signal type, so dismissing "about to
-- expire" does not also dismiss "expired and nobody acted".
--
-- No table, column, index or policy. One CHECK constraint is replaced and three
-- functions are replaced in place with unchanged signatures, so the public
-- SECURITY DEFINER inventory and the private function inventory do not move.
--
-- `public.operations_signals` is reproduced from its CURRENT definition, which
-- is the one `20260812100000_security_aal_enforcement.sql` re-declared -- not
-- the P2-D05a original. Deriving from the original would silently revert the
-- AAL permission ordering that migration introduced.

-- -----------------------------------------------------------------------------
-- 1. The leasing summary gets the start bound it never had.
-- -----------------------------------------------------------------------------

create or replace function public.property_leasing_summary(
  p_workspace_id uuid,
  p_property_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_today date := (v_now at time zone 'utc')::date;
  v_units jsonb;
  v_vacancy jsonb;
  v_roll jsonb;
  v_decisions jsonb;
  v_rent jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for the leasing summary'
      )
    );
  end if;

  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Property access is not permitted'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Leasing access is not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  -- --------------------------------------------------------------------------
  -- Units and area. `units_without_area` is the coverage statement: without it
  -- a partial sum would read as a complete one.
  -- --------------------------------------------------------------------------
  select jsonb_build_object(
    'total', count(*),
    'occupied', count(*) filter (where unit.status = 'occupied'),
    'vacant', count(*) filter (where unit.status = 'vacant'),
    'offline', count(*) filter (where unit.status = 'offline'),
    'area_sqm_total', coalesce(sum(unit.area_sqm), 0),
    'area_sqm_occupied',
      coalesce(sum(unit.area_sqm) filter (where unit.status = 'occupied'), 0),
    'area_sqm_vacant',
      coalesce(sum(unit.area_sqm) filter (where unit.status = 'vacant'), 0),
    'units_without_area', count(*) filter (where unit.area_sqm is null)
  )
  into v_units
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;

  -- --------------------------------------------------------------------------
  -- Vacancy duration, from the stored `vacancy_since`. A unit that is vacant
  -- without a recorded date is counted separately rather than treated as
  -- vacant since today.
  -- --------------------------------------------------------------------------
  select jsonb_build_object(
    'longest_vacancy_days',
      max(v_today - unit.vacancy_since) filter (
        where unit.status = 'vacant' and unit.vacancy_since is not null
      ),
    'vacant_without_since', count(*) filter (
      where unit.status = 'vacant' and unit.vacancy_since is null
    )
  )
  into v_vacancy
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;

  -- --------------------------------------------------------------------------
  -- The lease roll. Windows are cumulative from today, labelled here so a
  -- client renders the server's definition rather than its own.
  -- --------------------------------------------------------------------------
  select jsonb_build_object(
    'active', count(*) filter (where lease.status = 'active'),
    'open_ended', count(*) filter (
      where lease.status = 'active' and lease.end_date is null
    ),
    'expired_open', count(*) filter (
      where lease.status = 'active'
        and lease.end_date is not null
        and lease.end_date < v_today
    ),
    'windows', jsonb_build_array(
      jsonb_build_object(
        'days', 30, 'label', '30 Tage',
        'expiring', count(*) filter (
          where lease.status = 'active'
            and lease.end_date between v_today and (v_today + 30)
        )
      ),
      jsonb_build_object(
        'days', 90, 'label', '90 Tage',
        'expiring', count(*) filter (
          where lease.status = 'active'
            and lease.end_date between v_today and (v_today + 90)
        )
      ),
      jsonb_build_object(
        'days', 180, 'label', '180 Tage',
        'expiring', count(*) filter (
          where lease.status = 'active'
            and lease.end_date between v_today and (v_today + 180)
        )
      ),
      jsonb_build_object(
        'days', 365, 'label', '365 Tage',
        'expiring', count(*) filter (
          where lease.status = 'active'
            and lease.end_date between v_today and (v_today + 365)
        )
      )
    )
  )
  into v_roll
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.property_id = p_property_id;

  -- --------------------------------------------------------------------------
  -- The decisions the lease itself carries. Dates, not scores: a renewal risk
  -- needs an explained signal contract, and deriving one from a date is the
  -- invention the overview spec rejects.
  -- --------------------------------------------------------------------------
  select jsonb_build_object(
    'window_days', 90,
    'notice_due', count(*) filter (
      where lease.status = 'active'
        and lease.notice_date between v_today and (v_today + 90)
    ),
    'renewal_option', count(*) filter (
      where lease.status = 'active'
        and lease.renewal_option_date between v_today and (v_today + 90)
    ),
    'break_option', count(*) filter (
      where lease.status = 'active'
        and lease.break_option_date between v_today and (v_today + 90)
    )
  )
  into v_decisions
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.property_id = p_property_id;

  -- --------------------------------------------------------------------------
  -- Rent roll, one row per currency.
  --
  -- No coverage counter here, unlike the areas above: `base_rent_monthly` and
  -- `currency_code` are NOT NULL on a lease, so every active lease carries
  -- both. A "leases without a rent" field would be permanently zero, and a
  -- number that can never be anything else is noise dressed as a caveat.
  -- --------------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'currency_code', row.currency_code,
        'monthly_base', row.monthly_base,
        'leases', row.leases
      )
      order by row.currency_code
    ),
    '[]'::jsonb
  )
  into v_rent
  from (
    select
      lease.currency_code as currency_code,
      sum(lease.base_rent_monthly) as monthly_base,
      count(*) as leases
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      -- Was `status = 'active'` alone, which counted a lease that has not
      -- begun: signed, active, starting next month, its rent already in this
      -- month's roll. The predicate adds the start bound this copy never had.
      -- It keeps counting a lease past its `end_date` -- that is DEC-027, and
      -- was always right here.
      and private.lease_is_effective_on(
        lease.status, lease.start_date, lease.end_date,
        lease.move_out_date, lease.ended_at, v_today
      )
    group by lease.currency_code
  ) as row;

  return jsonb_build_object(
    'ok', true,
    'summary', jsonb_build_object(
      'as_of', v_now,
      'units', v_units,
      'vacancy', v_vacancy,
      'lease_roll', v_roll,
      'decisions', v_decisions,
      'rent_roll', v_rent
    )
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. The expiry ladder keeps its meaning; the expired case gets its own type.
-- -----------------------------------------------------------------------------

alter table public.operations_signal_states
  drop constraint operations_signal_states_type_check;

alter table public.operations_signal_states
  add constraint operations_signal_states_type_check check (
    signal_type = any (array[
      'lease_expiry',
      'lease_expired_open',
      'vacancy_missing_since',
      'vacancy_aged',
      'offline_missing_reason',
      'missing_tenant_contact',
      'stale_rent_roll'
    ])
  );

CREATE OR REPLACE FUNCTION public.operations_signals(p_workspace_id uuid, p_property_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_signals jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id and property id are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Operations signals are not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  with raw_signals as (
    -- lease_expiry: active lease, effective end date within 180 days.
    select
      'lease_expiry'::text as signal_type,
      case
        when (lease.end_date - current_date) <= 30 then 'critical'
        when (lease.end_date - current_date) <= 90 then 'warning'
        else 'info'
      end as severity,
      format(
        'Lease %s expires in %s days.', lease.lease_name,
        (lease.end_date - current_date)
      ) as message,
      'Review renewal, notice and follow-up actions for this lease.'
        as recommended_action,
      lease.unit_id as unit_id,
      lease.id as lease_id,
      lease.tenant_party_id as tenant_party_id
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      and lease.status = 'active'::public.lease_status
      and lease.end_date is not null
      and lease.end_date >= current_date
      and (lease.end_date - current_date) <= 180

    union all

    -- lease_expired_open: the end date has passed and the lease is still
    -- active. Its own signal type rather than a negative `lease_expiry`: the
    -- ladder above means "a decision is coming", this one means "a decision
    -- was not taken", and folding both into one key would produce "expires in
    -- -400 days" and make the 30/90/180 severities meaningless.
    --
    -- Unbounded on purpose. Per DEC-027 this is where every fixed-term lease
    -- ends up -- nothing ends one on its own, and `update_lease` cannot even
    -- correct an `end_date` while the lease is active -- so it is not a
    -- transient state that ages out. It is an open decision, and the product
    -- already treats it as one: `property_overview` reports it as a
    -- `critical` attention with no time bound either. Noise is answered by the
    -- acknowledgement this package already has -- and keyed on this signal
    -- type rather than on the expiry one, because dismissing "it is about to
    -- expire" must not also dismiss "it expired and nobody acted".
    --
    -- What it deliberately does not say is what the law made of it. A tenancy
    -- may have continued by operation of law, in which case it is no longer
    -- expired but indefinite -- and whether the landlord objected in time is
    -- not in this database. The message states the fact and leaves the reading
    -- to a human.
    select
      'lease_expired_open'::text as signal_type,
      'critical'::text as severity,
      format(
        'Lease %s passed its end date %s days ago and is still active.',
        lease.lease_name, (current_date - lease.end_date)
      ) as message,
      'Record whether this tenancy ended, was renewed or continues open-ended, '
      'so the rent roll and the expiry ladder stay truthful.'
        as recommended_action,
      lease.unit_id as unit_id,
      lease.id as lease_id,
      lease.tenant_party_id as tenant_party_id
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      and lease.status = 'active'::public.lease_status
      and lease.end_date is not null
      and lease.end_date < current_date

    union all

    -- vacancy_missing_since: named gap in the P2-D05 header — vacant units are
    -- not constrained to carry a vacancy_since, imported data can lack one.
    select
      'vacancy_missing_since', 'warning',
      format('Unit %s is vacant without a vacancy date.', unit.unit_code),
      'Set the vacancy start date so vacancy aging can be tracked.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is null

    union all

    -- vacancy_aged: matches the legacy 45-day threshold.
    select
      'vacancy_aged', 'warning',
      format(
        'Unit %s has been vacant for %s days.', unit.unit_code,
        (current_date - unit.vacancy_since)
      ),
      'Review marketing status, target rent and next action for this vacancy.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is not null
      and (current_date - unit.vacancy_since) >= 45

    union all

    -- offline_missing_reason: units_offline_reason_state_check only forbids a
    -- reason on a non-offline unit, it does not require one when offline.
    select
      'offline_missing_reason', 'critical',
      format('Unit %s is offline without a reason.', unit.unit_code),
      'Add the offline reason before the unit disappears from normal operations.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id
      and unit.status = 'offline'::public.unit_status
      and (unit.offline_reason is null or char_length(btrim(unit.offline_reason)) = 0)

    union all

    -- missing_tenant_contact: active lease with no tenant party, or a tenant
    -- party missing email or phone.
    select
      'missing_tenant_contact', 'warning',
      format('Lease %s is missing tenant email or phone.', lease.lease_name),
      'Complete tenant contact details before the next operational handoff.',
      lease.unit_id, lease.id, lease.tenant_party_id
    from public.leases as lease
    left join public.parties as party
      on party.workspace_id = lease.workspace_id and party.id = lease.tenant_party_id
    where lease.workspace_id = p_workspace_id
      and lease.property_id = p_property_id
      and lease.status = 'active'::public.lease_status
      and (
        lease.tenant_party_id is null
        or coalesce(btrim(party.email), '') = ''
        or coalesce(btrim(party.phone), '') = ''
      )

    union all

    -- stale_rent_roll: property-level, no unit/lease/tenant reference.
    -- Matches the legacy ~92-day freshness window (RentRoll snapshots are
    -- roughly quarterly), now on the real as_of_date instead of a periodKey.
    select
      'stale_rent_roll', 'warning',
      'Rent roll is missing or older than the accepted freshness window.',
      'Generate a new rent roll snapshot for the current period.',
      null::uuid, null::uuid, null::uuid
    where not exists (
      select 1
      from public.rent_roll_snapshots as snapshot
      where snapshot.workspace_id = p_workspace_id
        and snapshot.property_id = p_property_id
        and snapshot.as_of_date >= current_date - 92
    )
  ),
  keyed as (
    select
      raw.*,
      raw.signal_type || ':' || coalesce(raw.unit_id::text, '-')
        || ':' || coalesce(raw.lease_id::text, '-')
        || ':' || coalesce(raw.tenant_party_id::text, '-') as signal_key
    from raw_signals as raw
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'signal_key', keyed.signal_key,
        'type', keyed.signal_type,
        'severity', keyed.severity,
        'message', keyed.message,
        'recommended_action', keyed.recommended_action,
        'property_id', p_property_id,
        'unit_id', keyed.unit_id,
        'lease_id', keyed.lease_id,
        'tenant_party_id', keyed.tenant_party_id,
        'status', coalesce(state.status, 'open'),
        'resolution_note', state.resolution_note,
        'status_version', state.version,
        'status_updated_at', state.updated_at
      )
      order by
        case keyed.severity when 'critical' then 0 when 'warning' then 1 else 2 end,
        keyed.message
    ),
    '[]'::jsonb
  )
  into v_signals
  from keyed
  left join public.operations_signal_states as state
    on state.workspace_id = p_workspace_id
    and state.property_id = p_property_id
    and state.signal_key = keyed.signal_key;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object('computed_at', now(), 'signals', v_signals)
  );
end;
$function$;

create or replace function public.update_operations_signal_status(
  p_workspace_id uuid,
  p_property_id uuid,
  p_signal_type text,
  p_status text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_unit_id uuid default null,
  p_lease_id uuid default null,
  p_tenant_party_id uuid default null,
  p_expected_version bigint default null,
  p_reason text default null,
  p_resolution_note text default null
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
  v_signal_key text;
  v_old public.operations_signal_states%rowtype;
  v_new public.operations_signal_states%rowtype;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null or p_signal_type is null or p_status is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Property id, signal type and status are required'
      )
    );
  end if;

  if p_signal_type not in (
    'lease_expiry', 'lease_expired_open', 'vacancy_missing_since',
    'vacancy_aged', 'offline_missing_reason', 'missing_tenant_contact',
    'stale_rent_roll'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown signal type', 'field', 'signal_type'
      )
    );
  end if;

  if p_status not in ('open', 'dismissed', 'resolved') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown status', 'field', 'status'
      )
    );
  end if;

  if p_resolution_note is not null and char_length(p_resolution_note) > 4000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Resolution note must contain at most 4000 characters',
        'field', 'resolution_note'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Operations signal management is not permitted'
      )
    );
  end if;

  if p_unit_id is not null and not exists (
    select 1 from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_unit_id
      and unit.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Unit not found', 'field', 'unit_id')
    );
  end if;

  if p_lease_id is not null and not exists (
    select 1 from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.id = p_lease_id
      and lease.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Lease not found', 'field', 'lease_id')
    );
  end if;

  if p_tenant_party_id is not null and not exists (
    select 1 from public.parties as party
    where party.workspace_id = p_workspace_id and party.id = p_tenant_party_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Party not found', 'field', 'tenant_party_id'
      )
    );
  end if;

  v_signal_key := p_signal_type || ':' || coalesce(p_unit_id::text, '-')
    || ':' || coalesce(p_lease_id::text, '-')
    || ':' || coalesce(p_tenant_party_id::text, '-');

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_operations_signal_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'signal_key', v_signal_key,
        'expected_version', p_expected_version,
        'status', p_status,
        'resolution_note', p_resolution_note,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'operations_signal_state'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  select *
  into v_old
  from public.operations_signal_states as state
  where state.workspace_id = p_workspace_id
    and state.property_id = p_property_id
    and state.signal_key = v_signal_key
  for update;

  if v_old.id is null then
    if p_expected_version is not null then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'version_conflict',
          'message', 'Signal state does not exist yet',
          'expected_version', p_expected_version,
          'actual_version', null
        )
      );
    end if;

    insert into public.operations_signal_states (
      workspace_id, property_id, signal_type, unit_id, lease_id, tenant_party_id,
      status, resolution_note, created_by, updated_by
    ) values (
      p_workspace_id, p_property_id, p_signal_type, p_unit_id, p_lease_id, p_tenant_party_id,
      p_status, p_resolution_note, v_actor_id, v_actor_id
    )
    returning * into v_new;

    perform private.finish_leasing_mutation(
      p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
      'operations_signal.update_status', 'operations_signal_state', v_new.id,
      null, private.operations_signal_state_snapshot(v_new)
    );
    return jsonb_build_object('ok', true, 'entity', private.operations_signal_state_snapshot(v_new));
  end if;

  if p_expected_version is null or v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Signal state version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.operations_signal_state_snapshot(v_old)
      )
    );
  end if;

  update public.operations_signal_states as state
  set
    status = p_status,
    resolution_note = p_resolution_note,
    updated_at = now(),
    updated_by = v_actor_id,
    version = state.version + 1
  where state.workspace_id = p_workspace_id
    and state.id = v_old.id
  returning * into v_new;

  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'operations_signal.update_status', 'operations_signal_state', v_new.id,
    private.operations_signal_state_snapshot(v_old),
    private.operations_signal_state_snapshot(v_new)
  );
  return jsonb_build_object('ok', true, 'entity', private.operations_signal_state_snapshot(v_new));
end;
$$;
