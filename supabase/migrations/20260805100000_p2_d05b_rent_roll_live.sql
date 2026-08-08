-- =============================================================================
-- P2-D05b — the live rent roll as a server-side read
-- =============================================================================
--
-- A rent roll answers two different questions, and P2-D05 only implemented one
-- of them:
--
--   * "What did this property look like on that date?" — a frozen snapshot
--     (AGG-007), immutable, citable, the record a report quotes.
--   * "What does it look like right now?" — the operational view, which nobody
--     wants to have to freeze first in order to see.
--
-- The second question was answered client-side for one release, which made the
-- rule that decides what counts exist twice: once in SQL, once in Dart. That is
-- the drift this repository already refused elsewhere (the operations-signal
-- derivation lives in Postgres for exactly this reason). This migration moves
-- it back next to the snapshot.
--
-- **No drift by construction, not by discipline.** `rent_roll_live` is built on
-- `private.rent_roll_unit_rows` and `private.rent_roll_currencies` — the same
-- two helpers `create_rent_roll_snapshot` uses. The live document and a
-- snapshot taken for the same date therefore cannot disagree unless the data
-- changed in between, and the pgTAP suite pins exactly that equality.
--
-- Two deliberate differences from a snapshot:
--
--   * **No identity.** A live read has no id, no `generated_at` and no
--     `created_by`, because nothing was written. It carries `computed_at` so a
--     screenshot of it can still be dated.
--   * **A mixed-currency property still gets an answer.** Creating a snapshot
--     is refused when the contributing leases disagree on currency (DEC-011:
--     summing them would be confidently wrong). A live read cannot refuse to
--     show the property at all, so it returns the per-unit lines, reports every
--     currency it found, and leaves the totals null. A null total says "not
--     summable"; a zero would say something false.
--
-- Read-only and permission-gated on `lease.read`. No table, no write, no audit
-- entry: reading a computation is not a mutation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Per-unit currencies
-- -----------------------------------------------------------------------------
--
-- The predicate below is the one in `private.rent_roll_unit_rows`' lateral
-- join. It is repeated rather than shared because that helper returns money,
-- not currency, and widening its signature would change a function three RPCs
-- already depend on. The duplication is pinned by a pgTAP test asserting the
-- two agree on every unit (a unit contributes iff it has currencies), so a
-- future change to one that forgets the other breaks the build instead of the
-- report.
create function private.rent_roll_unit_currencies(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns table (unit_id uuid, currencies text[])
language sql
stable
security definer
set search_path = ''
as $$
  select
    unit.id,
    coalesce(
      (
        select array_agg(distinct lease.currency_code order by lease.currency_code)
        from public.leases as lease
        where lease.workspace_id = unit.workspace_id
          and lease.unit_id = unit.id
          and lease.status = 'active'::public.lease_status
          and lease.start_date <= p_as_of_date
          and (lease.end_date is null or lease.end_date >= p_as_of_date)
      ),
      '{}'::text[]
    )
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;
$$;

alter function private.rent_roll_unit_currencies(uuid, uuid, date)
  owner to postgres;
revoke all on function private.rent_roll_unit_currencies(uuid, uuid, date)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- rent_roll_live: the current rent roll of one property
-- -----------------------------------------------------------------------------
create function public.rent_roll_live(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_currencies text[];
  v_single_currency text;
  v_lines jsonb;
  v_unit_count integer;
  v_occupied integer;
  v_vacant integer;
  v_offline integer;
  v_lease_count integer;
  v_base numeric;
  v_ancillary numeric;
  v_parking numeric;
  v_total numeric;
begin
  if p_workspace_id is null or p_property_id is null or p_as_of_date is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace, property and reporting date are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Reading the rent roll is not permitted'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  v_currencies := private.rent_roll_currencies(
    p_workspace_id, p_property_id, p_as_of_date
  );
  -- DEC-011. One currency means the sums mean something; more than one means
  -- they do not, and the totals stay null rather than becoming a wrong number.
  v_single_currency := case
    when array_length(v_currencies, 1) = 1 then v_currencies[1]
    else null
  end;

  select
    count(*)::integer,
    count(*) filter (
      where unit_row.unit_status = 'occupied'::public.unit_status
    )::integer,
    count(*) filter (
      where unit_row.unit_status = 'vacant'::public.unit_status
    )::integer,
    count(*) filter (
      where unit_row.unit_status = 'offline'::public.unit_status
    )::integer,
    coalesce(sum(unit_row.effective_lease_count), 0)::integer,
    coalesce(sum(unit_row.base_rent_monthly), 0)::numeric,
    coalesce(sum(unit_row.ancillary_charges_monthly), 0)::numeric,
    coalesce(sum(unit_row.parking_other_charges_monthly), 0)::numeric,
    coalesce(sum(unit_row.total_rent_monthly), 0)::numeric
  into
    v_unit_count, v_occupied, v_vacant, v_offline, v_lease_count,
    v_base, v_ancillary, v_parking, v_total
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row;

  -- unit_code-ordered, like the snapshot document, so two reads of unchanged
  -- data are byte-identical.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'unit_id', unit_row.unit_id,
        'unit_code', unit_row.unit_code,
        'unit_status', unit_row.unit_status,
        'area_sqm', unit_row.area_sqm,
        'effective_lease_count', unit_row.effective_lease_count,
        'base_rent_monthly', unit_row.base_rent_monthly,
        'ancillary_charges_monthly', unit_row.ancillary_charges_monthly,
        'parking_other_charges_monthly', unit_row.parking_other_charges_monthly,
        'total_rent_monthly', unit_row.total_rent_monthly,
        'currency_code', case
          when array_length(unit_currency.currencies, 1) = 1
            then unit_currency.currencies[1]
          else null
        end,
        'currencies', to_jsonb(unit_currency.currencies)
      )
      order by unit_row.unit_code
    ),
    '[]'::jsonb
  )
  into v_lines
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row
  join private.rent_roll_unit_currencies(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_currency on unit_currency.unit_id = unit_row.unit_id;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'workspace_id', p_workspace_id,
      'property_id', p_property_id,
      'as_of_date', p_as_of_date,
      'computed_at', now(),
      'currency_code', v_single_currency,
      'currencies', to_jsonb(v_currencies),
      'unit_count', v_unit_count,
      'occupied_unit_count', v_occupied,
      'vacant_unit_count', v_vacant,
      'offline_unit_count', v_offline,
      'effective_lease_count', v_lease_count,
      'total_base_rent_monthly',
        case when v_single_currency is null and v_lease_count > 0
          then null else v_base end,
      'total_ancillary_charges_monthly',
        case when v_single_currency is null and v_lease_count > 0
          then null else v_ancillary end,
      'total_parking_other_charges_monthly',
        case when v_single_currency is null and v_lease_count > 0
          then null else v_parking end,
      'total_rent_monthly',
        case when v_single_currency is null and v_lease_count > 0
          then null else v_total end,
      'lines', v_lines
    )
  );
end;
$$;

alter function public.rent_roll_live(uuid, uuid, date) owner to postgres;
revoke all on function public.rent_roll_live(uuid, uuid, date)
  from public, anon, authenticated;
grant execute on function public.rent_roll_live(uuid, uuid, date)
  to authenticated;

comment on function public.rent_roll_live(uuid, uuid, date) is
  'P2-D05b: the current rent roll of one property, computed from the same '
  'helpers create_rent_roll_snapshot uses. Read-only, lease.read-gated. Totals '
  'are null when the contributing leases do not share one currency (DEC-011).';
