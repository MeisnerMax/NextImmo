-- LEASING-SUMMARY-01: the server-side lease roll and vacancy exposure.
--
-- The overview has been able to say how many units are vacant since
-- PROPERTY-OVERVIEW-DATA-01, but not how much of the building that is, when
-- the contracts run out, or what has to be decided next. Those are the
-- questions an asset manager actually opens a property for, and every one of
-- them is a definition — which is why they belong here rather than in a client
-- that would have to invent them.
--
-- What this function will and will not answer:
--
--   * **It counts and it sums; it does not divide.** There is no occupancy
--     rate, because "occupied by unit" and "occupied by area" are different
--     numbers and choosing between them is a product decision this package
--     does not own. Both inputs are published, so the decision stays open.
--   * **It reports its own coverage.** Areas are summed only where they are
--     recorded, and the number of units *without* an area travels with the
--     total. A square-metre figure that silently omits half the building is
--     worse than no figure.
--   * **Currencies are never mixed.** The rent roll is one row per currency.
--     Adding EUR to CHF produces a number that is wrong in both.
--   * **No renewal risk.** A risk score needs a signal contract with reasons;
--     inventing one from an end date is exactly what the overview spec
--     rejects. What is published instead are the dates the lease itself
--     carries: notice, renewal option, break option.
--   * **Windows are the server's.** 30/90/180/365 days, labelled in the
--     payload, so a client cannot quietly re-cut them and report a different
--     exposure under the same name.
--
-- Open-ended leases are their own count. They are not "not expiring": they are
-- a different kind of obligation, and folding them into either bucket would
-- misstate the roll.

create function public.property_leasing_summary(
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
      and lease.status = 'active'
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

alter function public.property_leasing_summary(uuid, uuid) owner to postgres;

revoke all on function public.property_leasing_summary(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.property_leasing_summary(uuid, uuid)
  to authenticated;
