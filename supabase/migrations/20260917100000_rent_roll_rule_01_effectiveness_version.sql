-- RENT-ROLL-RULE-01: a frozen rent roll says which rule produced it.
--
-- Follow-up 4 from DEC-027, recorded in `ENTERPRISE_OPERATIONS_PROGRAM.md` §6
-- and named in the header of `20260915100000_leasing_asof_01_effective_on.sql`
-- as the one thing that migration could see but deliberately did not fix.
--
-- -----------------------------------------------------------------------------
-- What is wrong
-- -----------------------------------------------------------------------------
--
-- `rent_roll_snapshots` freezes eleven figures and says nothing about how they
-- were computed. LEASING-ASOF-01 changed which leases count: an `active` lease
-- past its `end_date` is now included, and a since-`ended` lease is included for
-- a date it covered. Two snapshots of the same property for the same
-- `as_of_date`, one taken before that migration and one after, therefore differ
-- -- and the difference reads as a rent change when it is a rule change.
--
-- Only `generated_at` separates the two eras, and only by inference: a reader
-- has to know when a migration was applied to the database they are looking at,
-- which is not a fact the row carries and not a fact the product tells them.
--
-- This is the FINANCE-01b lesson, in leasing: no computed figure without its
-- definition version. `property_finance_kpis` publishes `definition_version`
-- with every value and `FinanceKpiValue.definitionVersion` is non-optional, so
-- a surface that renders a figure without its version is a choice somebody made
-- rather than an accident the type allowed. A rent roll should be no different.
--
-- -----------------------------------------------------------------------------
-- The shape: an integer, not a definition entity
-- -----------------------------------------------------------------------------
--
-- FINANCE-01b is the house precedent, and it is deliberately NOT copied here.
-- A KPI definition is a table because it is *the workspace's* data: NexImmo
-- cannot know which accounts of somebody else's chart are operating expenses,
-- so a definition is a record a workspace writes, versioned by its own edits,
-- and nothing is seeded.
--
-- Lease effectiveness is the opposite kind of thing. It is NexImmo's rule, the
-- same in every workspace, expressed in `private.lease_is_effective_on` and
-- changed only by a migration. Modelling it as a definition entity would
-- produce a table nobody may write, holding one row per migration whose content
-- restates the migration header -- and it would advertise an affordance that
-- does not exist, inviting the reasonable belief that a workspace can configure
-- when a lease counts. It cannot, and it should not: a rent roll that meant
-- something different per workspace would not be comparable across a portfolio.
--
-- So: an integer, monotonically numbered, whose meaning lives in exactly one
-- place. That place is `private.rent_roll_effectiveness_rule_version()`,
-- declared below next to the versions it names, so a future migration that
-- edits the predicate has the number it must bump in the same file it is
-- already editing.
--
--   * **1** -- P2-D05 through migration 49. A lease counted when
--     `status = 'active' and start_date <= as_of and (end_date is null or
--     end_date >= as_of)`. A planned end was treated as a termination, and a
--     lease that had since ended contributed nothing to a date it covered.
--   * **2** -- LEASING-ASOF-01 (migration 50) onward.
--     `private.lease_is_effective_on`: `active` is open at the top, `ended` is
--     bounded by `coalesce(move_out_date, end_date, ended_at)`, everything else
--     never counted. This is DEC-027.
--
-- The version sits on the header and not on `rent_roll_snapshot_lines`. A line
-- belongs to exactly one header and was produced by the same evaluation, so a
-- second copy per line could only ever agree or be wrong.
--
-- -----------------------------------------------------------------------------
-- The rows that already exist are NOT labelled, and that is the finding
-- -----------------------------------------------------------------------------
--
-- Back-labelling every existing row as 1 was the obvious move, and it is a claim
-- this migration cannot make truthfully. The evidence, checked rather than
-- assumed:
--
--   * `rent_roll_snapshots`, `private.rent_roll_unit_rows`,
--     `private.rent_roll_currencies` and `public.create_rent_roll_snapshot` were
--     all created by `20260730120000_p2_d05_leasing_cases_rent_roll.sql` and
--     none of them was replaced by any migration up to 49 -- not by P2-D05b
--     (which added `rent_roll_unit_currencies` for the *live* read only), not by
--     P2-X01, not by the AAL enforcement migration. `public.lease_status` has
--     never gained or lost a value. So up to migration 49 there was exactly one
--     rule, and every snapshot written in that window is rule 1.
--
--   * Migration 50 opened rule 2. Any snapshot written after 50 was applied to a
--     database and before this migration reaches it is rule 2 -- and carries
--     nothing that distinguishes it from a rule 1 row. Postgres does not record
--     when a function was created, and `supabase_migrations.schema_migrations`
--     does not record when a version was applied, so this migration cannot
--     derive the boundary from the database it is running in.
--
-- That window is empty wherever all migrations are applied in one replay (CI,
-- `db reset`, a fresh environment). It is not empty in general, because the web
-- build and the database reach staging through different workflows and the
-- database one is dispatched by hand.
--
-- Stamping 1 on every existing row would therefore write a definite claim over
-- an indefinite fact, in the exact column whose reason for existing is that a
-- figure must not assert more than it can support. So the column is nullable and
-- this migration writes nothing: **null means the rule was not recorded**, which
-- is true of every row that predates this migration and is the honest reading of
-- a snapshot taken while nothing was labelling them.
--
-- This is the same move `rent_roll_live` already makes with its totals -- null
-- because the figures are not summable across currencies, rather than a zero
-- that would say something false. A reader who wants a labelled figure for an
-- unlabelled date takes a new snapshot, which is the only lawful operation on a
-- frozen document anyway (AGG-007).
--
-- -----------------------------------------------------------------------------
-- Why the column carries a default AND the writer names it
-- -----------------------------------------------------------------------------
--
-- The two are not redundant; they fail differently.
--
-- `create_rent_roll_snapshot` names the version explicitly because that is where
-- the rule is actually applied: the figures and the label are written by the
-- same statement, so they cannot drift. A future writer that computes under a
-- different rule -- a backfill recomputing history, say -- must say so there,
-- and the explicit column makes that a visible decision instead of an omission.
--
-- The default exists for the writer that forgets. Without it, an omission
-- produces null, which this migration has just defined to mean "written before
-- the marker existed" -- a false statement about a row written today. With it,
-- an omission produces the current version, which for new code computing under
-- the current rule is right. Wrong-in-the-narrow-case beats false-by-default.
--
-- The default is set AFTER the column is added, on purpose. `add column ...
-- default ...` fills every existing row in one step, which is precisely the
-- silent stamping the section above rules out.
--
-- -----------------------------------------------------------------------------
-- What moves and what does not
-- -----------------------------------------------------------------------------
--
-- One private function is added (the version constant) -- the private inventory
-- in `002_p1_003_rls.test.sql` moves by one and is updated there. Three
-- functions are replaced in place with unchanged signatures, so the public
-- SECURITY DEFINER inventory (SR-20) does not move. No table, no index, no
-- policy: the new column inherits the row-scoped select policy and the
-- table-wide grant `rent_roll_snapshots` already has, so the default-deny
-- posture and the SR-22 policy inventory do not move either.
--
-- `public.create_rent_roll_snapshot`, `private.rent_roll_snapshot_header` and
-- `public.rent_roll_live` are reproduced from their CURRENT definitions, which
-- for all three is still the P2-D05 / P2-D05b original: none of them was
-- re-declared by the AAL enforcement migration, unlike `operations_signals`,
-- where deriving from the original would have reverted a permission ordering.
-- That was checked, not assumed.

-- -----------------------------------------------------------------------------
-- The version, declared once.
-- -----------------------------------------------------------------------------

create function private.rent_roll_effectiveness_rule_version()
returns integer
language sql
immutable
set search_path = ''
as $function$
  select 2;
$function$;

alter function private.rent_roll_effectiveness_rule_version() owner to postgres;
revoke all on function private.rent_roll_effectiveness_rule_version()
  from public, anon, authenticated;

comment on function private.rent_roll_effectiveness_rule_version() is
  'The effectiveness rule a rent roll computed now runs under. 1 = the P2-D05 '
  'filter, which treated a planned end as a termination; 2 = LEASING-ASOF-01 / '
  'DEC-027 via private.lease_is_effective_on. Bump this in the same migration '
  'that changes the predicate.';

-- -----------------------------------------------------------------------------
-- The marker on the frozen header.
-- -----------------------------------------------------------------------------

alter table public.rent_roll_snapshots
  add column effectiveness_rule_version integer;

alter table public.rent_roll_snapshots
  add constraint rent_roll_snapshots_effectiveness_rule_version_check check (
    effectiveness_rule_version is null or effectiveness_rule_version >= 1
  );

-- Only now, so the rows that already exist keep their null.
alter table public.rent_roll_snapshots
  alter column effectiveness_rule_version
  set default private.rent_roll_effectiveness_rule_version();

comment on column public.rent_roll_snapshots.effectiveness_rule_version is
  'Which revision of the lease-effectiveness rule produced these figures. Null '
  'means the snapshot predates RENT-ROLL-RULE-01 and its rule was never '
  'recorded -- not that it used rule 1. A writer computing under a rule other '
  'than the current one must set this explicitly.';

-- -----------------------------------------------------------------------------
-- The frozen document carries the marker.
--
-- `rent_roll_snapshot_header` is what the RPC returns AND what the audit row
-- stores, so adding the key here puts the version into the reply, the replay of
-- an idempotent call and the audit trail in one edit. It is the last key rather
-- than an insertion in the middle, so a stored document from before this
-- migration and one from after differ by an addition and nothing else.
-- -----------------------------------------------------------------------------

create or replace function private.rent_roll_snapshot_header(
  snapshot public.rent_roll_snapshots
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', snapshot.id,
    'workspace_id', snapshot.workspace_id,
    'property_id', snapshot.property_id,
    'as_of_date', snapshot.as_of_date,
    'currency_code', snapshot.currency_code,
    'generated_at', snapshot.generated_at,
    'unit_count', snapshot.unit_count,
    'occupied_unit_count', snapshot.occupied_unit_count,
    'vacant_unit_count', snapshot.vacant_unit_count,
    'offline_unit_count', snapshot.offline_unit_count,
    'effective_lease_count', snapshot.effective_lease_count,
    'total_base_rent_monthly', snapshot.total_base_rent_monthly,
    'total_ancillary_charges_monthly', snapshot.total_ancillary_charges_monthly,
    'total_parking_other_charges_monthly',
      snapshot.total_parking_other_charges_monthly,
    'total_rent_monthly', snapshot.total_rent_monthly,
    'created_at', snapshot.created_at,
    'created_by', snapshot.created_by,
    'effectiveness_rule_version', snapshot.effectiveness_rule_version
  );
$$;

-- -----------------------------------------------------------------------------
-- The writer names the rule it applied.
--
-- Reproduced verbatim from P2-D05 apart from two lines in the header INSERT.
-- The lines INSERT below it is untouched: the version governs the document, and
-- a per-line copy could only agree with it or be wrong.
-- -----------------------------------------------------------------------------

create or replace function public.create_rent_roll_snapshot(
  p_workspace_id uuid,
  p_property_id uuid,
  p_as_of_date date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_currency_code text default null,
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
  v_currencies text[];
  v_currency text;
  v_snapshot public.rent_roll_snapshots%rowtype;
  v_document jsonb;
  v_unit_count integer;
  v_occupied integer;
  v_vacant integer;
  v_offline integer;
  v_lease_count integer;
  v_base numeric;
  v_ancillary numeric;
  v_parking numeric;
begin
  v_gate := private.leasing_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null or p_as_of_date is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Property and as-of date are required'
      )
    );
  end if;

  if p_currency_code is not null and p_currency_code !~ '^[A-Z]{3}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Currency must be a three-letter ISO code',
        'field', 'currency_code'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Lease management is not permitted'
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

  -- No silent cross-currency sum (DEC-011). This is checked before the claim so a
  -- mismatch does not burn the mutation id: it is a property of the data, not of
  -- this command, and retrying the same id after fixing the leases is legitimate.
  if array_length(v_currencies, 1) > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'currency_mismatch',
        'message', 'The contributing leases do not share one currency',
        'field', 'currency_code',
        'currencies', to_jsonb(v_currencies)
      )
    );
  end if;

  if array_length(v_currencies, 1) = 1 then
    v_currency := v_currencies[1];

    if p_currency_code is not null and p_currency_code <> v_currency then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'currency_mismatch',
          'message', 'The requested currency is not the currency of the leases',
          'field', 'currency_code',
          'currencies', to_jsonb(v_currencies)
        )
      );
    end if;
  else
    -- Nothing contributes, so nothing implies a currency. Guessing here would
    -- invent data on an otherwise all-zero report.
    if p_currency_code is null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'No effective lease implies a currency; pass one explicitly',
          'field', 'currency_code'
        )
      );
    end if;

    v_currency := p_currency_code;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_rent_roll_snapshot',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'as_of_date', p_as_of_date,
        'currency_code', v_currency,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_leasing_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'rent_roll_snapshot'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- The header totals and the lines come from one definition of the aggregation
  -- (private.rent_roll_unit_rows), evaluated twice in the same transaction and
  -- therefore against the same snapshot of the data.
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
    coalesce(sum(unit_row.parking_other_charges_monthly), 0)::numeric
  into
    v_unit_count, v_occupied, v_vacant, v_offline, v_lease_count,
    v_base, v_ancillary, v_parking
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row;

  -- RENT-ROLL-RULE-01. The rule version is written by the same statement that
  -- writes the figures, because this is where the rule was applied: the two
  -- cannot drift apart if they are one INSERT. The column also carries this
  -- function as its default, so a writer that forgets gets the current version
  -- rather than the null that means "written before the marker existed"; naming
  -- it here is what makes a writer computing under a DIFFERENT rule say so.
  insert into public.rent_roll_snapshots (
    workspace_id, property_id, as_of_date, currency_code, unit_count,
    occupied_unit_count, vacant_unit_count, offline_unit_count,
    effective_lease_count, total_base_rent_monthly,
    total_ancillary_charges_monthly, total_parking_other_charges_monthly,
    total_rent_monthly, created_by, effectiveness_rule_version
  ) values (
    p_workspace_id, p_property_id, p_as_of_date, v_currency, v_unit_count,
    v_occupied, v_vacant, v_offline, v_lease_count, v_base, v_ancillary,
    v_parking, v_base + v_ancillary + v_parking, v_actor_id,
    private.rent_roll_effectiveness_rule_version()
  )
  returning * into v_snapshot;

  insert into public.rent_roll_snapshot_lines (
    workspace_id, snapshot_id, unit_id, unit_code, unit_status, area_sqm,
    effective_lease_count, base_rent_monthly, ancillary_charges_monthly,
    parking_other_charges_monthly, total_rent_monthly, created_by
  )
  select
    p_workspace_id, v_snapshot.id, unit_row.unit_id, unit_row.unit_code,
    unit_row.unit_status, unit_row.area_sqm, unit_row.effective_lease_count,
    unit_row.base_rent_monthly, unit_row.ancillary_charges_monthly,
    unit_row.parking_other_charges_monthly, unit_row.total_rent_monthly,
    v_actor_id
  from private.rent_roll_unit_rows(
    p_workspace_id, p_property_id, p_as_of_date
  ) as unit_row;

  v_document := private.rent_roll_snapshot_document(p_workspace_id, v_snapshot.id);

  -- The audited new_values is the whole frozen document, lines included, so an
  -- idempotent replay returns exactly what the first call returned. That makes
  -- the audit row large for a big property; that is the intended trade, because
  -- the snapshot IS the audited artefact and a header-only audit would not let
  -- anyone reconstruct what was reported.
  perform private.finish_leasing_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'rent_roll_snapshot.create', 'rent_roll_snapshot', v_snapshot.id,
    null, v_document
  );
  return jsonb_build_object('ok', true, 'entity', v_document);
end;
$$;

-- -----------------------------------------------------------------------------
-- The live read states its rule too.
--
-- Not strictly a snapshot concern, and included for the reason the whole package
-- exists: the comparison a reader actually makes is a snapshot against the
-- current stand. Without a version on the live side, a client can only guess
-- which rule the number in front of it came from, or -- worse -- hard-code its
-- own belief about what the server is doing. FINANCE-01b publishes the version
-- with every computed value for the same reason; a live rent roll is a computed
-- value.
--
-- Reproduced verbatim from P2-D05b apart from the one added key.
-- -----------------------------------------------------------------------------

create or replace function public.rent_roll_live(
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
      'lines', v_lines,
      -- RENT-ROLL-RULE-01: what a snapshot records, a live read states.
      'effectiveness_rule_version',
        private.rent_roll_effectiveness_rule_version()
    )
  );
end;
$$;
