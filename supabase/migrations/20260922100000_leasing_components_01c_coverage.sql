-- LEASING-COMPONENTS-01c: a gap is reported, not merely invisible.
--
-- This is the second half of DEC-029, in the form the owner chose on
-- 2026-09-07. The decision demanded two things on the write side — no overlap
-- per type, and **no gap inside the term when a component is put into force**.
-- The first shipped as an EXCLUSION constraint in migration 54. The second did
-- not, and the mutation form that shipped alongside it is exactly what
-- produces gaps: someone records base rent for January to June on a lease that
-- runs to December, and July onwards is unrecorded.
--
-- **Why it is a report and not a refusal.** A strict write-side check makes the
-- natural entry order impossible: the first period of a type can never cover
-- the whole term, so the very first component of every type would be rejected.
-- The owner therefore decided the gap is a *reported incompleteness state*
-- rather than a write veto — which is also what DEC-029's read side already
-- asked for: "verweigern oder als unvollstaendig markieren, nie darum herum
-- summieren".
--
-- **Two different gaps, and only one of them was visible.**
--
--   * A type with no row covering the queried date already showed as nothing.
--     But "nothing" looked identical whether the type had never been recorded
--     or had been recorded for other periods and not this one — and in the
--     second case the total silently omits a component that ought to have a
--     value. That is summing around a gap, precisely what the decision forbids.
--   * A gap **elsewhere** in the term was invisible entirely. Base rent
--     covering January to June and August to December reads as complete on any
--     September date, and July is simply unknown to everyone.
--
-- The read now answers both. `coverage` is reported per lease, because the
-- property-scoped read spans several and a single flag would hide which one is
-- incomplete.
--
-- **The window ends at the queried date, never later.** A fixed-term lease
-- running to December, queried in September, is not incomplete for October:
-- nobody has agreed the future yet. Gaps are only claimed for days that have
-- happened.
--
-- Only the function body changes: no new object, no new policy, so SR-20 and
-- SR-22 stay where they are. The return type is unchanged, so this replaces
-- rather than drops.

create or replace function public.lease_components_as_of(
  p_workspace_id uuid,
  p_as_of date default null,
  p_lease_id uuid default null,
  p_property_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, current_date);
  v_components jsonb;
  v_coverage jsonb;
begin
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
        'code', 'forbidden', 'message', 'Not permitted to read leases'
      )
    );
  end if;

  -- One of the two scopes, never neither: an unscoped read would return every
  -- component in the workspace, which is the client-side-full-dataset shape
  -- the programme forbids.
  if p_lease_id is null and p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Either a lease or a property must be given',
        'field', 'scope'
      )
    );
  end if;

  select coalesce(
    jsonb_agg(component_row order by component_row ->> 'valid_from'),
    '[]'::jsonb
  )
  into v_components
  from (
    select jsonb_build_object(
      'id', component.id,
      'lease_id', lease.id,
      'property_id', lease.property_id,
      'component_type', component.component_type,
      'amount', component.amount,
      'currency_code', component.currency_code,
      'vat_mode', component.vat_mode,
      'vat_rate_percent', component.vat_rate_percent,
      'valid_from', component.valid_from,
      'valid_to', component.valid_to,
      'version', component.version
    ) as component_row
    from public.lease_components as component
    join public.leases as lease
      on lease.workspace_id = component.workspace_id
     and lease.id = component.lease_id
    where component.workspace_id = p_workspace_id
      and (p_lease_id is null or component.lease_id = p_lease_id)
      and (p_property_id is null or lease.property_id = p_property_id)
      and component.validity @> v_as_of
      and private.lease_is_effective_on(
        lease.status, lease.start_date, lease.end_date,
        lease.move_out_date, lease.ended_at, v_as_of
      )
  ) as rows;

  -- Coverage, per lease and per component type that has any history at all.
  --
  -- A type with no row for this lease is not reported: nothing was ever
  -- claimed about it, so there is nothing to be incomplete about. That is the
  -- DEC-029 boundary — components are authoritative *per type*, from the first
  -- row for that type onwards.
  select coalesce(jsonb_agg(lease_coverage order by lease_coverage ->> 'lease_id'), '[]'::jsonb)
  into v_coverage
  from (
    select jsonb_build_object(
      'lease_id', scope.lease_id,
      'window_from', lower(scope.window),
      -- Inclusive again at the edge, the way the rest of this contract reads.
      'window_to', upper(scope.window) - 1,
      'complete', bool_and(per_type.in_force and per_type.gap_count = 0),
      'types', jsonb_agg(
        jsonb_build_object(
          'component_type', per_type.component_type,
          'in_force', per_type.in_force,
          'has_gap', per_type.gap_count > 0,
          'gap_count', per_type.gap_count,
          'first_gap_from', per_type.first_gap_from,
          'first_gap_to', per_type.first_gap_to,
          'open_gap_from', per_type.open_gap_from
        ) order by per_type.component_type
      )
    ) as lease_coverage
    from (
      select
        lease.id as lease_id,
        daterange(
          lease.start_date,
          least(
            coalesce(lease.move_out_date, lease.end_date, 'infinity'::date),
            v_as_of
          ) + 1,
          '[)'
        ) as window
      from public.leases as lease
      where lease.workspace_id = p_workspace_id
        and (p_lease_id is null or lease.id = p_lease_id)
        and (p_property_id is null or lease.property_id = p_property_id)
        and private.lease_is_effective_on(
          lease.status, lease.start_date, lease.end_date,
          lease.move_out_date, lease.ended_at, v_as_of
        )
        and exists (
          select 1 from public.lease_components as any_component
          where any_component.workspace_id = p_workspace_id
            and any_component.lease_id = lease.id
        )
    ) as scope
    cross join lateral (
      -- The gap set is computed once and then read three ways. Written out
      -- three times it was the same expression each time, which is the shape
      -- that eventually stops being the same expression.
      select
        raw.component_type,
        raw.in_force,
        (select count(*)::integer from unnest(raw.gaps)) as gap_count,
        (select lower(gap) from unnest(raw.gaps) as gap order by gap limit 1)
          as first_gap_from,
        (select upper(gap) - 1 from unnest(raw.gaps) as gap order by gap limit 1)
          as first_gap_to,
        -- The gap that reaches the queried date, when there is one. It is the
        -- actionable half: "this type has been unrecorded since X and still
        -- is", as opposed to a closed hole earlier in the term.
        (select lower(gap) from unnest(raw.gaps) as gap
         where upper(gap) - 1 >= upper(scope.window) - 1
         order by gap desc limit 1) as open_gap_from
      from (
        select
          component.component_type,
          bool_or(component.validity @> v_as_of) as in_force,
          datemultirange(scope.window)
            - coalesce(
                range_agg(component.validity * scope.window)
                  filter (where not isempty(component.validity * scope.window)),
                datemultirange()
              ) as gaps
        from public.lease_components as component
        where component.workspace_id = p_workspace_id
          and component.lease_id = scope.lease_id
        group by component.component_type
      ) as raw
    ) as per_type
    group by scope.lease_id, scope.window
  ) as per_lease;

  -- An empty list is a real answer, not an error: where no component covers
  -- the date there is nothing recorded, and DEC-029 forbids turning that into
  -- a zero here or anywhere above.
  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'components', v_components,
      'coverage', v_coverage
    )
  );
end;
$function$;

comment on function public.lease_components_as_of(uuid, date, uuid, uuid) is
  'Rent components in force on a date, plus per-lease coverage. A component '
  'type with history but no row covering the date, or with a gap earlier in '
  'the term, is reported as incomplete rather than silently omitted '
  '(DEC-029, owner decision of 2026-09-07: report, do not refuse the write).';
