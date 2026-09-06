-- LEASING-ASOF-01: one place decides whether a lease was in force on a date.
--
-- Implements DEC-027 ("`end_date` is a planned end, not a termination") and
-- closes the as-of gap named as B-2 in `ENTERPRISE_OPERATIONS_PROGRAM.md`.
--
-- -----------------------------------------------------------------------------
-- What was wrong
-- -----------------------------------------------------------------------------
--
-- Three helpers carried the same three-line filter, copied:
--
--     and lease.status = 'active'
--     and lease.start_date <= p_as_of_date
--     and (lease.end_date is null or lease.end_date >= p_as_of_date)
--
-- Two things are wrong with it, and they pull in opposite directions.
--
-- **It asks the wrong question about the past.** `status` is the lease's state
-- *now*, not on `p_as_of_date`. A lease that ran January to June and has since
-- been ended contributes nothing to a rent roll for March -- the date filters
-- match, and then the status filter removes the row. Nothing fails; the number
-- is simply too low. No live surface asks for a past date today (the only
-- caller sends today), which is exactly why this can be corrected now without
-- regression risk, and why it could not be later.
--
-- **It asks the wrong question about the present.** Excluding a lease because
-- `end_date` has passed treats a planned end as a termination. Per DEC-027 it
-- is not: there is no scheduler, no trigger and no constraint that ends a lease
-- when its term runs out, and `update_lease` refuses every change to an active
-- lease, so `end_date` cannot even be corrected. Running past `end_date` while
-- still `active` is therefore the unavoidable end state of every fixed-term
-- lease, and the only representable form of a tenancy continuing by operation
-- of law -- where the rent is genuinely owed. Excluding those leases understated
-- the actual rent, and it disagreed with `property_leasing_summary`, which
-- counts them and reports them separately as `expired_open`.
--
-- -----------------------------------------------------------------------------
-- The rule
-- -----------------------------------------------------------------------------
--
-- A lease was in force on a date when it had reached `active` and the date
-- falls within its effective span:
--
--   * `active` -- open at the top. `end_date` is a plan, not a boundary.
--   * `ended`  -- bounded by `coalesce(move_out_date, end_date, ended_at)`.
--     The transition to `ended` does not touch `end_date`; it records
--     `move_out_date` (the business fact, when known) and `ended_at` (the
--     instant somebody recorded it). They are tried in that order, most
--     meaningful first. `ended_at` is a last resort and a system timestamp, so
--     it is read at UTC to stay deterministic rather than session-dependent.
--   * every other status -- never in force. A lease still in the signing chain
--     was not let, and a `cancelled` one never was.
--
-- The predicate is `immutable` and touches no table, so it needs no
-- `security definer` and adds nothing to the public SECURITY DEFINER inventory.
--
-- -----------------------------------------------------------------------------
-- A consequence worth stating rather than discovering
-- -----------------------------------------------------------------------------
--
-- `rent_roll_snapshots` is an immutable document and carries no marker for the
-- rule its figures were computed under. Snapshots written before this migration
-- used the old filter; snapshots written after use this one. For a property
-- with a lease running past its `end_date`, the two differ -- and the jump is a
-- change of rule, not a change of rent.
--
-- Nothing on the row says so. That is the same shape as the finance lesson from
-- FINANCE-01b ("no computed figure without its definition version"), and it is
-- not fixed here: labelling the snapshots means a column, a decision about what
-- to write on the rows that already exist, and a way to show it -- a package of
-- its own, named in `ENTERPRISE_OPERATIONS_PROGRAM.md` rather than folded in.
--
-- What can be said today is said here: `generated_at` separates the two eras,
-- and this migration is the boundary.
--
-- Deliberately NOT changed here:
--
--   * `private.lease_status_is_effective` keeps its meaning. It answers a
--     question about *now* for AGG-004 occupancy, takes no date, and conflating
--     the two would make occupancy depend on a reference date it does not have.
--   * `property_leasing_summary` and `operations_signals` also decide lease
--     effectiveness, and both have their own defects (a missing `start_date`
--     filter; an expiry ladder that drops a lease on the day it becomes
--     actionable). They are named in DEC-027 and fixed in their own package
--     rather than folded in here, because each changes a different surface's
--     published numbers.

create function private.lease_is_effective_on(
  p_status public.lease_status,
  p_start_date date,
  p_end_date date,
  p_move_out_date date,
  p_ended_at timestamptz,
  p_as_of date
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select p_start_date <= p_as_of
    and case p_status
      when 'active'::public.lease_status then true
      when 'ended'::public.lease_status then
        p_as_of <= coalesce(
          p_move_out_date,
          p_end_date,
          (p_ended_at at time zone 'UTC')::date
        )
      else false
    end;
$function$;

alter function private.lease_is_effective_on(
  public.lease_status, date, date, date, timestamptz, date
) owner to postgres;
revoke all on function private.lease_is_effective_on(
  public.lease_status, date, date, date, timestamptz, date
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- The three helpers now ask that one question.
-- -----------------------------------------------------------------------------

create or replace function private.rent_roll_unit_rows(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns table (
  unit_id uuid,
  unit_code text,
  unit_status public.unit_status,
  area_sqm numeric,
  effective_lease_count integer,
  base_rent_monthly numeric,
  ancillary_charges_monthly numeric,
  parking_other_charges_monthly numeric,
  total_rent_monthly numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    unit.id,
    unit.unit_code,
    unit.status,
    unit.area_sqm,
    coalesce(effective.lease_count, 0)::integer,
    coalesce(effective.base_rent, 0)::numeric,
    coalesce(effective.ancillary, 0)::numeric,
    coalesce(effective.parking, 0)::numeric,
    (
      coalesce(effective.base_rent, 0)
      + coalesce(effective.ancillary, 0)
      + coalesce(effective.parking, 0)
    )::numeric
  from public.units as unit
  left join lateral (
    select
      count(*) as lease_count,
      sum(lease.base_rent_monthly) as base_rent,
      sum(coalesce(lease.ancillary_charges_monthly, 0)) as ancillary,
      sum(coalesce(lease.parking_other_charges_monthly, 0)) as parking
    from public.leases as lease
    where lease.workspace_id = unit.workspace_id
      and lease.unit_id = unit.id
      and private.lease_is_effective_on(
        lease.status, lease.start_date, lease.end_date,
        lease.move_out_date, lease.ended_at, p_as_of_date
      )
  ) as effective on true
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;
$$;

create or replace function private.rent_roll_currencies(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    array_agg(distinct lease.currency_code order by lease.currency_code),
    '{}'::text[]
  )
  from public.leases as lease
  join public.units as unit
    on unit.workspace_id = lease.workspace_id
    and unit.id = lease.unit_id
  where lease.workspace_id = p_workspace_id
    and unit.property_id = p_property_id
    and private.lease_is_effective_on(
      lease.status, lease.start_date, lease.end_date,
      lease.move_out_date, lease.ended_at, p_as_of_date
    );
$$;

create or replace function private.rent_roll_unit_currencies(
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
          and private.lease_is_effective_on(
            lease.status, lease.start_date, lease.end_date,
            lease.move_out_date, lease.ended_at, p_as_of_date
          )
      ),
      '{}'::text[]
    )
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;
$$;
