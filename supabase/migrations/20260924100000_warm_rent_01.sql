-- WARM-RENT-01 (P-7 of the enterprise operations programme).
--
-- What a tenant pays per month, warm, computed on the server from the
-- time-versioned components — the first thing V-2 was built for.
--
-- **Three conflicting totals already exist, and this package agrees with none
-- of them by accident.**
--
--   * `LeasePaymentItem.warmRentMonthly` (legacy, `lib/core/models/`) is
--     base + ancillary + *other*. It is named warm rent and contains no
--     heating — wrong in both directions at once.
--   * `rent_roll_snapshots.total_rent_monthly` is base + ancillary + parking.
--     It never claimed to be warm rent, and the programme flags the name as a
--     collision waiting to be misread.
--   * This one is base rent + service-charge advance + heating advance, which
--     is what the word means: Kaltmiete plus Nebenkosten plus Heizkosten.
--     Parking is a separate service a tenant may or may not buy, and putting
--     it inside warm rent would make two flats with identical contracts differ
--     by whether one of them rents a garage.
--
-- **`other` is excluded, and that is a decision rather than an oversight.**
-- It absorbs whatever a contract contains that the four named types do not —
-- a garden levy, a cable fee, an antenna share. Some of those belong in warm
-- rent and some do not, and the type does not say which. Summing it would
-- make the figure depend on how somebody chose to file an oddity.
--
-- **The honest part is what happens when a component is missing.**
--
--   * A type with history but no row covering the date is a **gap**. The
--     figure is withheld entirely (DEC-029: never sum around a gap).
--   * A type that was never recorded at all is not a gap — nothing was ever
--     claimed about it — but the sum is then narrower than the word. So the
--     result says which types it contains, and `is_warm` is true only when
--     heating is one of them. A total without heating is a cold rent plus
--     service charges, and calling it warm rent would be the lie this whole
--     package exists to avoid.
--
-- **VAT.** Net and gross are reported separately and either may be null. A
-- component whose mode is `net` with no rate cannot be grossed up, and mixing
-- net with non-net amounts produces a figure that is neither — exactly as the
-- component total already refuses to.
--
-- One new public function: SR-20 87 → 88.

create function public.warm_rent_as_of(
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
  v_leases jsonb;
  -- The composition, named once. A reader looking for "what counts as warm
  -- rent" finds it here and nowhere else.
  c_warm constant public.lease_component_type[] := array[
    'base_rent'::public.lease_component_type,
    'service_charge_advance'::public.lease_component_type,
    'heating_advance'::public.lease_component_type
  ];
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

  select coalesce(jsonb_agg(row order by row ->> 'lease_id'), '[]'::jsonb)
  into v_leases
  from (
    select jsonb_build_object(
      'lease_id', lease.id,
      'property_id', lease.property_id,
      'currency_code', lease.currency_code,
      'included_types', coalesce(parts.included, '[]'::jsonb),
      -- Recorded for other periods, absent on this date. A gap, and the
      -- reason the figures below are null.
      'gap_types', coalesce(gaps.missing, '[]'::jsonb),
      -- Never recorded at all. Not a gap: nothing was claimed. But the sum is
      -- narrower than the word, which `is_warm` reports.
      'absent_types', coalesce(absent.never_recorded, '[]'::jsonb),
      'is_warm', coalesce(parts.has_heating, false),
      'net_monthly', case
        when coalesce(jsonb_array_length(gaps.missing), 0) > 0 then null
        else parts.net_total
      end,
      'gross_monthly', case
        when coalesce(jsonb_array_length(gaps.missing), 0) > 0 then null
        else parts.gross_total
      end
    ) as row
    from public.leases as lease
    -- What is in force on the date, of the three that make up warm rent.
    left join lateral (
      select
        jsonb_agg(component.component_type order by component.component_type)
          as included,
        bool_or(component.component_type
                = 'heating_advance'::public.lease_component_type)
          as has_heating,
        -- Null the moment the parts cannot be added into one honest figure,
        -- rather than quietly dropping one from the sum. The server enum has
        -- exactly three values; `unknown` is a client concept for a newer
        -- server and has no place in this predicate.
        case
          when bool_and(component.currency_code = lease.currency_code)
           and (bool_and(component.vat_mode = 'net'::public.lease_component_vat_mode)
                or bool_and(component.vat_mode <> 'net'::public.lease_component_vat_mode))
          then sum(component.amount)
          else null
        end as net_total,
        case
          when bool_and(component.currency_code = lease.currency_code)
           and bool_and(
                 component.vat_mode <> 'net'::public.lease_component_vat_mode
                 or component.vat_rate_percent is not null
               )
          -- Rounded to the currency's scale. Grossing up a net amount
          -- produces a repeating fraction, and a money figure carried to
          -- twenty-two decimal places is not more precise, only less readable.
          then round(sum(
            case component.vat_mode
              when 'net'::public.lease_component_vat_mode
                then component.amount * (1 + component.vat_rate_percent / 100)
              else component.amount
            end
          ), 2)
          else null
        end as gross_total
      from public.lease_components as component
      where component.workspace_id = lease.workspace_id
        and component.lease_id = lease.id
        and component.component_type = any (c_warm)
        and component.validity @> v_as_of
    ) as parts on true
    -- Types with history that do not cover the date.
    left join lateral (
      select jsonb_agg(distinct component.component_type) as missing
      from public.lease_components as component
      where component.workspace_id = lease.workspace_id
        and component.lease_id = lease.id
        and component.component_type = any (c_warm)
        and not exists (
          select 1 from public.lease_components as covering
          where covering.workspace_id = lease.workspace_id
            and covering.lease_id = lease.id
            and covering.component_type = component.component_type
            and covering.validity @> v_as_of
        )
    ) as gaps on true
    -- Types with no row for this lease at all.
    left join lateral (
      select jsonb_agg(candidate.component_type order by candidate.component_type)
        as never_recorded
      from unnest(c_warm) as candidate(component_type)
      where not exists (
        select 1 from public.lease_components as component
        where component.workspace_id = lease.workspace_id
          and component.lease_id = lease.id
          and component.component_type = candidate.component_type
      )
    ) as absent on true
    where lease.workspace_id = p_workspace_id
      and (p_lease_id is null or lease.id = p_lease_id)
      and (p_property_id is null or lease.property_id = p_property_id)
      and private.lease_is_effective_on(
        lease.status, lease.start_date, lease.end_date,
        lease.move_out_date, lease.ended_at, v_as_of
      )
  ) as per_lease;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'leases', v_leases
    )
  );
end;
$function$;

alter function public.warm_rent_as_of(uuid, date, uuid, uuid) owner to postgres;
revoke all on function public.warm_rent_as_of(uuid, date, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.warm_rent_as_of(uuid, date, uuid, uuid)
  to authenticated;

comment on function public.warm_rent_as_of(uuid, date, uuid, uuid) is
  'Warm rent per lease on a date: base rent + service-charge advance + heating '
  'advance, from lease_components. Parking and other are excluded on purpose. '
  'Withheld entirely when a constituent type has a gap at the date (DEC-029); '
  'is_warm is false when heating was never recorded, because a total without '
  'it is a cold rent plus service charges.';
