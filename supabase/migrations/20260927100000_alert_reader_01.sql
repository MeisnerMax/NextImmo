-- ALERT-READER-01 (P-10 of the enterprise operations programme).
--
-- Two things, and they belong together.
--
-- **1. One time source.** There is no scheduler anywhere in this stack -- no
-- `pg_cron`, no `pg_net`, no edge function (finding B-4). Every deadline in
-- the product is therefore decided at *read* time, which makes the question
-- "when is now" a load-bearing one, and until this migration eight signal
-- sources answered it eight times with a bare `current_date`.
--
-- That is not merely untidy. `current_date` follows the session timezone while
-- `now()` is an absolute instant, so a signal computed from one and stamped
-- with the other can disagree by a day for anyone whose session is not UTC --
-- and the disagreement appears at midnight, which is exactly when a deadline
-- alarm is read. `private.operations_today()` is derived from
-- `private.operations_now()`, so the two cannot drift apart. It is the same
-- construction `property_overview` already uses inline; this makes it a thing
-- with a name that other packages can share.
--
-- **2. A workspace-wide reader.** `operations_signals` computes for one
-- property. A workspace worklist built by calling it once per property is the
-- N+1 the programme forbids, and with forty assets it is forty round trips to
-- answer "what needs attention today".
--
-- **The eight signal definitions are moved, not copied.**
-- `private.operations_signal_rows` now holds them once and takes an optional
-- property filter; `public.operations_signals` is recreated as a thin caller
-- with a byte-identical payload. Copying them would have meant maintaining two
-- sets of thresholds, two severity ladders and two sets of German-facing
-- messages -- and the first time somebody adjusted the 45-day vacancy window
-- in one of them, the property screen and the workspace list would have
-- started disagreeing about the same unit.
--
-- **What changes in behaviour, deliberately:**
--
--   * `stale_rent_roll` was a bare `NOT EXISTS` that could only ever emit one
--     row, because the caller had already named the property. It now walks the
--     properties in scope. For a single-property call that is the same answer;
--     for a workspace call it is the only useful one.
--   * The workspace reader skips soft-deleted properties, using the same
--     `deleted_at is null` predicate `private.leasing_property_in_workspace`
--     already applies. This is not a new policy: the property-scoped read
--     answers `not_found` for an archived asset today. Without the filter the
--     workspace list would surface signals for properties its own detail
--     screen refuses to open.
--
-- **No cursor, on purpose.** The signal set is computed at read time, not
-- stored, so a keyset cursor would page over a moving target: a lease renewed
-- between page one and page two silently shifts every later signal, and the
-- reader would skip or repeat entries without any way to tell. Instead the
-- read caps, reports the true `total` and says `truncated`. Fixing the
-- criticals is what shortens the list.
--
-- Two new public functions and three private ones: SR-20 90 -> 91.
-- (`workspace_operations_signals` is the only new *public* one; the recreate
-- of `operations_signals` keeps its place in the inventory.)

-- ---------------------------------------------------------------------------
-- The time source
-- ---------------------------------------------------------------------------

create function private.operations_now()
returns timestamptz
language sql
stable
set search_path = ''
as $function$
  select now();
$function$;

-- `grant usage on schema private to authenticated` (P1-003) means a private
-- function is reachable by name, and a function with no explicit grants keeps
-- PUBLIC's default EXECUTE. Revoked, like every other private function here.
revoke all on function private.operations_now()
  from public, anon, authenticated;

comment on function private.operations_now() is
  'The reference instant for every deadline the operations surface judges. '
  'One function because there is no scheduler: "now" is decided at read time, '
  'and it must be decided once per read rather than once per subquery.';

create function private.operations_today()
returns date
language sql
stable
set search_path = ''
as $function$
  -- Derived, never independently taken. `current_date` follows the session
  -- timezone and `now()` does not, so a source using one and a stamp using
  -- the other can differ by a day -- at midnight, which is when a deadline
  -- alarm is read.
  select (private.operations_now() at time zone 'utc')::date;
$function$;

revoke all on function private.operations_today()
  from public, anon, authenticated;

comment on function private.operations_today() is
  'The calendar day of private.operations_now(), in UTC. Derived from it so '
  'the two cannot drift apart across a midnight boundary.';

-- ---------------------------------------------------------------------------
-- The eight signals, in one place
-- ---------------------------------------------------------------------------

create function private.operations_signal_rows(
  p_workspace_id uuid,
  p_property_id uuid default null
)
returns table (
  property_id uuid,
  signal_type text,
  severity text,
  message text,
  recommended_action text,
  unit_id uuid,
  lease_id uuid,
  tenant_party_id uuid,
  signal_key text
)
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_today date := private.operations_today();
begin
  -- No permission check here, and that is deliberate rather than an omission:
  -- this function is private, is granted to nobody, and both callers are
  -- SECURITY DEFINER functions that gate on `lease.read` before reaching it.
  -- Checking again here would put the rule in two places and invite the two
  -- copies to disagree.
  return query
  with raw_signals as (
    -- lease_expiry: active lease, effective end date within 180 days.
    select
      lease.property_id as property_id,
      'lease_expiry'::text as signal_type,
      case
        when (lease.end_date - v_today) <= 30 then 'critical'
        when (lease.end_date - v_today) <= 90 then 'warning'
        else 'info'
      end as severity,
      format(
        'Lease %s expires in %s days.', lease.lease_name,
        (lease.end_date - v_today)
      ) as message,
      'Review renewal, notice and follow-up actions for this lease.'
        as recommended_action,
      lease.unit_id as unit_id,
      lease.id as lease_id,
      lease.tenant_party_id as tenant_party_id
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and (p_property_id is null or lease.property_id = p_property_id)
      and lease.status = 'active'::public.lease_status
      and lease.end_date is not null
      and lease.end_date >= v_today
      and (lease.end_date - v_today) <= 180

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
      lease.property_id as property_id,
      'lease_expired_open'::text as signal_type,
      'critical'::text as severity,
      format(
        'Lease %s passed its end date %s days ago and is still active.',
        lease.lease_name, (v_today - lease.end_date)
      ) as message,
      'Record whether this tenancy ended, was renewed or continues open-ended, '
      'so the rent roll and the expiry ladder stay truthful.'
        as recommended_action,
      lease.unit_id as unit_id,
      lease.id as lease_id,
      lease.tenant_party_id as tenant_party_id
    from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and (p_property_id is null or lease.property_id = p_property_id)
      and lease.status = 'active'::public.lease_status
      and lease.end_date is not null
      and lease.end_date < v_today

    union all

    -- vacancy_missing_since: named gap in the P2-D05 header — vacant units are
    -- not constrained to carry a vacancy_since, imported data can lack one.
    select
      unit.property_id, 'vacancy_missing_since', 'warning',
      format('Unit %s is vacant without a vacancy date.', unit.unit_code),
      'Set the vacancy start date so vacancy aging can be tracked.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and (p_property_id is null or unit.property_id = p_property_id)
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is null

    union all

    -- vacancy_aged: matches the legacy 45-day threshold.
    select
      unit.property_id, 'vacancy_aged', 'warning',
      format(
        'Unit %s has been vacant for %s days.', unit.unit_code,
        (v_today - unit.vacancy_since)
      ),
      'Review marketing status, target rent and next action for this vacancy.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and (p_property_id is null or unit.property_id = p_property_id)
      and unit.status = 'vacant'::public.unit_status
      and unit.vacancy_since is not null
      and (v_today - unit.vacancy_since) >= 45

    union all

    -- offline_missing_reason: units_offline_reason_state_check only forbids a
    -- reason on a non-offline unit, it does not require one when offline.
    select
      unit.property_id, 'offline_missing_reason', 'critical',
      format('Unit %s is offline without a reason.', unit.unit_code),
      'Add the offline reason before the unit disappears from normal operations.',
      unit.id, null::uuid, null::uuid
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and (p_property_id is null or unit.property_id = p_property_id)
      and unit.status = 'offline'::public.unit_status
      and (unit.offline_reason is null or char_length(btrim(unit.offline_reason)) = 0)

    union all

    -- missing_tenant_contact: active lease with no tenant party, or a tenant
    -- party missing email or phone.
    select
      lease.property_id, 'missing_tenant_contact', 'warning',
      format('Lease %s is missing tenant email or phone.', lease.lease_name),
      'Complete tenant contact details before the next operational handoff.',
      lease.unit_id, lease.id, lease.tenant_party_id
    from public.leases as lease
    left join public.parties as party
      on party.workspace_id = lease.workspace_id and party.id = lease.tenant_party_id
    where lease.workspace_id = p_workspace_id
      and (p_property_id is null or lease.property_id = p_property_id)
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
    --
    -- Lifted from a bare NOT EXISTS to a walk over the properties in scope.
    -- The old form could only ever emit one row, because the caller had
    -- already named the property; a workspace read has to say *which*
    -- properties are stale, and there can be many.
    select
      property.id, 'stale_rent_roll', 'warning',
      'Rent roll is missing or older than the accepted freshness window.',
      'Generate a new rent roll snapshot for the current period.',
      null::uuid, null::uuid, null::uuid
    from public.properties as property
    where property.workspace_id = p_workspace_id
      and (p_property_id is null or property.id = p_property_id)
      and not exists (
        select 1
        from public.rent_roll_snapshots as snapshot
        where snapshot.workspace_id = p_workspace_id
          and snapshot.property_id = property.id
          and snapshot.as_of_date >= v_today - 92
      )
  )
  select
    raw.property_id,
    raw.signal_type,
    raw.severity,
    raw.message,
    raw.recommended_action,
    raw.unit_id,
    raw.lease_id,
    raw.tenant_party_id,
    -- The acknowledgement key. Unchanged from P2-D05a: it is stored in
    -- `operations_signal_states`, so altering its shape would orphan every
    -- acknowledgement anyone has ever made.
    raw.signal_type || ':' || coalesce(raw.unit_id::text, '-')
      || ':' || coalesce(raw.lease_id::text, '-')
      || ':' || coalesce(raw.tenant_party_id::text, '-') as signal_key
  from raw_signals as raw;
end;
$function$;

revoke all on function private.operations_signal_rows(uuid, uuid)
  from public, anon, authenticated;

comment on function private.operations_signal_rows(uuid, uuid) is
  'The operations signal definitions, once. Property filter optional: null '
  'means the whole workspace. Private and granted to nobody -- both callers '
  'are SECURITY DEFINER and gate on lease.read before reaching it.';

-- ---------------------------------------------------------------------------
-- The property-scoped read, now a thin caller
-- ---------------------------------------------------------------------------

create or replace function public.operations_signals(
  p_workspace_id uuid,
  p_property_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_signals jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
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

  -- The payload below is byte-identical to the one this function produced
  -- before ALERT-READER-01. Only the source of the rows moved.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'signal_key', signal.signal_key,
        'type', signal.signal_type,
        'severity', signal.severity,
        'message', signal.message,
        'recommended_action', signal.recommended_action,
        'property_id', p_property_id,
        'unit_id', signal.unit_id,
        'lease_id', signal.lease_id,
        'tenant_party_id', signal.tenant_party_id,
        'status', coalesce(state.status, 'open'),
        'resolution_note', state.resolution_note,
        'status_version', state.version,
        'status_updated_at', state.updated_at
      )
      order by
        case signal.severity
          when 'critical' then 0 when 'warning' then 1 else 2
        end,
        signal.message
    ),
    '[]'::jsonb
  )
  into v_signals
  from private.operations_signal_rows(p_workspace_id, p_property_id) as signal
  left join public.operations_signal_states as state
    on state.workspace_id = p_workspace_id
    and state.property_id = p_property_id
    and state.signal_key = signal.signal_key;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'computed_at', private.operations_now(), 'signals', v_signals
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- The workspace-wide reader
-- ---------------------------------------------------------------------------

create function public.workspace_operations_signals(
  p_workspace_id uuid,
  p_severity text default null,
  p_status text default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := private.operations_now();
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_severity text := nullif(btrim(coalesce(p_severity, '')), '');
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_total integer;
  v_by_severity jsonb;
  v_signals jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025: the whole workspace business surface sits behind aal2.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'AAL2 is required for the alert list'
      )
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace is required',
        'field', 'workspaceId'
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

  -- Validated against the ladder rather than matched loosely: a caller that
  -- filters on a severity this build does not know is asking a question with
  -- no answer, and an empty list would read as "nothing critical".
  if v_severity is not null
     and v_severity not in ('critical', 'warning', 'info') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown severity',
        'field', 'severity'
      )
    );
  end if;

  -- The same three the acknowledgement command accepts. An unknown status
  -- would silently return nothing, which reads as "everything is handled".
  if v_status is not null
     and v_status not in ('open', 'dismissed', 'resolved') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown status',
        'field', 'status'
      )
    );
  end if;

  with scope as (
    select
      signal.property_id,
      property.name as property_name,
      signal.signal_key,
      signal.signal_type,
      signal.severity,
      signal.message,
      signal.recommended_action,
      signal.unit_id,
      signal.lease_id,
      signal.tenant_party_id,
      coalesce(state.status, 'open') as status,
      state.resolution_note,
      state.version as status_version,
      state.updated_at as status_updated_at
    from private.operations_signal_rows(p_workspace_id, null) as signal
    join public.properties as property
      on property.workspace_id = p_workspace_id
      and property.id = signal.property_id
      -- The same predicate `private.leasing_property_in_workspace` applies,
      -- so this list cannot offer a signal whose property the detail screen
      -- would refuse to open. `status = 'archived'` and a deletion stamp
      -- travel together by CHECK; the stamp is the predicate the rest of the
      -- leasing surface reads.
      and property.deleted_at is null
    left join public.operations_signal_states as state
      on state.workspace_id = p_workspace_id
      and state.property_id = signal.property_id
      and state.signal_key = signal.signal_key
    where (v_severity is null or signal.severity = v_severity)
      and (v_status is null or coalesce(state.status, 'open') = v_status)
  ),
  ranked as (
    select
      scope.*,
      -- Severity first, then the property so one building's signals read
      -- together, then the key so the order is total and a second call with
      -- the same data returns the same page.
      row_number() over (
        order by
          case scope.severity
            when 'critical' then 0 when 'warning' then 1 else 2
          end,
          scope.property_name,
          scope.signal_key
      ) as position
    from scope
  ),
  counted as (
    select
      (select count(*)::integer from scope) as total,
      -- Counted over the filtered set before the cap, so the summary
      -- describes what exists rather than what fitted.
      coalesce(
        (select jsonb_object_agg(bucket.severity, bucket.count)
         from (
           select severity, count(*)::integer as count
           from scope group by severity
         ) as bucket),
        '{}'::jsonb
      ) as by_severity
  )
  select
    counted.total,
    counted.by_severity,
    coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'signal_key', ranked.signal_key,
           'type', ranked.signal_type,
           'severity', ranked.severity,
           'message', ranked.message,
           'recommended_action', ranked.recommended_action,
           'property_id', ranked.property_id,
           -- The workspace list is unusable without it: "Lease 4B expires in
           -- 12 days" says nothing when forty buildings are in scope.
           'property_name', ranked.property_name,
           'unit_id', ranked.unit_id,
           'lease_id', ranked.lease_id,
           'tenant_party_id', ranked.tenant_party_id,
           'status', ranked.status,
           'resolution_note', ranked.resolution_note,
           'status_version', ranked.status_version,
           'status_updated_at', ranked.status_updated_at
         )
         order by ranked.position
       )
       from ranked
       where ranked.position <= v_limit),
      '[]'::jsonb
    )
  into v_total, v_by_severity, v_signals
  from counted;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'computed_at', v_now,
      'signals', v_signals,
      'total', v_total,
      'returned', jsonb_array_length(v_signals),
      -- Said out loud rather than left for the caller to infer from a length.
      -- A silently capped list is the failure mode this surface exists to
      -- avoid.
      'truncated', v_total > jsonb_array_length(v_signals),
      'limit', v_limit,
      'total_by_severity', v_by_severity
    )
  );
end;
$function$;

alter function public.workspace_operations_signals(uuid, text, text, integer)
  owner to postgres;
revoke all on function public.workspace_operations_signals(uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.workspace_operations_signals(uuid, text, text, integer)
  to authenticated;

comment on function public.workspace_operations_signals(uuid, text, text, integer) is
  'The operations signals of a whole workspace in one read, severity first, '
  'each carrying the property it belongs to. Archived properties are '
  'excluded. Capped rather than paged: the set is computed at read time, so a '
  'cursor would page over a moving target -- the answer reports the true '
  'total and says whether it was truncated.';
