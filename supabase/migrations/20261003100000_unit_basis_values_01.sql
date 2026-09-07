-- UNIT-BASIS-VALUES-01 (P-2c, the per-unit distribution basis store).
--
-- **This package was not asked for by the commission.** Its entire mandate is
-- one row of the implementation-order table:
--
--   "| P-2c | Basiswerte je Einheit (fester Anteil, Personen,
--    Miteigentumsanteil) | macht drei der vier heute nicht aufloesbaren
--    Massstaebe rechenbar | P-5 |"
--
-- and that row was written by P-2b's own pull request two days ago
-- (`git log -S "P-2c" -- docs/product/ENTERPRISE_OPERATIONS_PROGRAM.md`
-- returns exactly one commit, d2f4cd9 -- this repository squash-merges, so
-- there is no separate merge commit to find). `Software_Goal.txt`
-- contains the string "person" zero times. The underlying Auftrag is not in
-- this repository; the programme quotes its sections second-hand and gives
-- P-2c no section at all. So this is a follow-up the previous package wrote
-- for itself, justified by a real gap rather than by a requirement, and the
-- header says so because a reader six months from now cannot tell the
-- difference from the code.
--
-- What *is* binding comes from three other places:
--
--   * **P-5 needs it.** ":334 | P-5 | Settlement Engine (§8) | braucht V-1,
--     V-2, V-4, P-2a, P-2b, P-2c, P-4 |". The fitness test is exact: the three
--     branches of `private.allocation_basis_resolution` that answer
--     `no_basis_store` must stop answering it once values exist.
--   * **§4 requires the figure on the statement.** A settlement line must
--     carry "Basis der Einheit" beside a "Gesamtbasis" -- the only place the
--     programme names a per-unit basis figure as a required artefact.
--   * **OPN-DOM-001**: "Eine Einheit **darf** mehrere gleichzeitig wirksame
--     Vertraege haben (Teilflaechenvermietung); es gibt bewusst keinen
--     Unique-Index. Die Umlage je Einheit muss damit umgehen." This decides
--     the grain on its own: the basis belongs to the **unit**, never to a
--     lease. `lease_components` is keyed on `lease_id` and is therefore
--     ambiguous per unit, which is exactly why it cannot be reused here.
--
-- **Exactly three bases, and the CHECK says which.** `area_sqm` lives on
-- `units.area_sqm` and `unit_count` is `count(*)` over `public.units`; storing
-- either here would be a second copy of a fact the schema already owns, and
-- the two copies would disagree. `consumption` needs meters, which are P-4.
-- `direct` distributes nothing. That leaves `fixed_share`, `persons` and
-- `co_ownership_share` -- named in a CHECK rather than left to convention, so
-- a later attempt to park an area figure here fails loudly.
--
-- **Nothing is migrated, because there is nothing to migrate.** The legacy
-- schema holds two per-unit numbers, `sqft` (an area) and `beds` (a room
-- count). It has no persons, no co-ownership share and no fixed share
-- anywhere. What it does have is
-- `lib/data/repositories/asset_workbook_repo.dart:990` `_getUnitFactorValue`,
-- a `contains()` chain over German display strings that ends in an unguarded
-- `return unit.sqft ?? 0.0` -- every unrecognised key silently becomes area.
-- A second legacy surface, `budget_vs_actual_screen.dart`, computes a person
-- share as `unit.beds / sum(beds)`: the room count, at an unstated date, on a
-- field this schema does not have. Neither is a source; both are the failure
-- this table exists to make impossible.
--
-- **The convention is mandatory, because no rule exists to default to.**
-- `DEC-014`'s accepted set decides six model consequences and none of them
-- touches how a Personenzahl, a Miteigentumsanteil or a fester Anteil is
-- measured. They are not on the contested-seven list either -- they are simply
-- absent, so there is no owner decision to read and picking one here would
-- encode a legal position nobody signed off. A person count can be an agreed
-- Stichtag, Personenmonate, or a period average; an MEA is a fraction from the
-- Teilungserklaerung whose denominator this schema does not hold. So every
-- value states its own convention, in the workspace's words, and it cannot be
-- saved without one. This is the same calibration P-2a and P-2b used: what
-- `DEC-014` approved became a CHECK constraint, what it left open became text
-- with the reason named.
--
-- **And two conventions do not add up.** If one unit's person count is a
-- Stichtag figure and its neighbour's is a Personenmonate figure, their sum is
-- not a denominator -- it is two different measurements added together. The
-- resolution refuses that case by name (`mixed_conventions`) rather than
-- summing anyway, for the same reason a single missing area makes the area
-- basis unresolvable instead of approximate.
--
-- **Time is a range, and the aggregation over time is deliberately not
-- decided here.** A settlement for 2024 re-run in 2026 needs the 2024 figures,
-- so a value has a validity and the resolution is asked as of a date -- the
-- same shape `allocation_keys` and `lease_components` already use. What this
-- package does *not* decide is how a settlement combines a person count that
-- changed mid-period. That is P-5's question, it has no answer in `DEC-014`
-- either, and answering it here would hide the decision inside a helper.
--
-- **Four things an adversarial review found before this merged**, each of
-- them the package failing its own rule:
--
--   * `value >= 0` is satisfied by NaN, and a stored NaN made the resolution
--     answer `resolvable: true` with a total of `"NaN"` -- reachable over HTTP
--     with ordinary `finance.manage`.
--   * A property whose units are all recorded as zero resolved with a total of
--     zero. Every other branch guarantees a divisible total; this one handed
--     P-5 a denominator it cannot divide by.
--   * The `area_sqm` branch, in this very function, declared
--     `incomplete_basis` and then returned the sum of the units that happen to
--     have an area -- the number DEC-029 forbids, contradicting this header's
--     own sentence about area.
--   * A key on a `building`/`entrance`/`meter_group` pool inherited a
--     whole-property denominator and reported itself resolvable. P-2b calls
--     those scopes unresolvable; the key read never consulted the pool.
--
-- Counters this migration moves, deliberately:
--   SR-20  105 -> 107  (two new public functions)
--   SR-22   55 ->  56  (one new SELECT policy)
--   private function inventory in 002: + unit_basis_value_snapshot
--
-- `private.allocation_basis_resolution` is dropped and recreated rather than
-- replaced: it gains an as-of date, and a `create or replace` cannot change a
-- signature. Leaving the three-argument version beside it would leave a
-- resolver that ignores time, which is the one thing this package adds.

-- ---------------------------------------------------------------------------
-- The store
-- ---------------------------------------------------------------------------

create table public.unit_basis_values (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,

  -- The unit, never the lease. OPN-DOM-001 permits several concurrently
  -- effective leases per unit and deliberately has no unique index, so a
  -- lease-keyed basis would have no single answer for the unit it is meant to
  -- describe.
  unit_id uuid not null,

  basis public.allocation_basis not null,

  -- The measured quantity: a head count, a share, a weight. Deliberately not
  -- normalised to a percentage -- the resolution reports the total and the
  -- caller divides, so a workspace can enter 3 persons rather than 0.25 of a
  -- house.
  value numeric(18, 6) not null,

  -- How the number was arrived at, in the workspace's words. Mandatory: no
  -- accepted counting rule exists for any of these three bases (DEC-014
  -- decides none of them and lists none as contested), so a figure without its
  -- convention is a figure nobody can check.
  convention text not null,

  valid_from date not null,
  -- Inclusive. Null is open-ended, the normal state of a current figure.
  valid_to date,

  note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  -- Half-open internally so consecutive periods do not overlap, inclusive at
  -- the edges of the API so a date reads the way a lease does.
  validity daterange generated always as (
    daterange(
      valid_from,
      case when valid_to is null then null else valid_to + 1 end,
      '[)'
    )
  ) stored,

  constraint unit_basis_values_workspace_id_key unique (workspace_id, id),
  constraint unit_basis_values_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint unit_basis_values_unit_fkey foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,

  -- The three with no other home. `area_sqm` is `units.area_sqm`,
  -- `unit_count` is `count(*)`, `consumption` needs P-4's meters and `direct`
  -- distributes nothing -- each of those stored here would be a second copy of
  -- a fact that already has an owner.
  constraint unit_basis_values_basis_check check (
    basis in ('fixed_share', 'persons', 'co_ownership_share')
  ),

  -- A negative share or a negative head count is not a smaller number, it is a
  -- wrong one. Zero is allowed: a unit with nobody in it is a real answer and
  -- must not be confused with a unit nobody has recorded.
  --
  -- `value <> 'NaN'` is not defensive noise. In Postgres `'NaN'::numeric >= 0`
  -- is TRUE, so `value >= 0` alone is satisfied by exactly the value it exists
  -- to reject -- and numeric(18,6) accepts NaN (it refuses Infinity itself
  -- with 22003). A stored NaN then propagates through `sum()` while every
  -- resolvability term still holds, so this package's central promise, that an
  -- unusable basis refuses to compute, would be broken by the one value that
  -- poisons every share derived from it. The 28 other numeric CHECKs in this
  -- schema carry the same term.
  constraint unit_basis_values_value_check check (
    value >= 0 and value <> 'NaN'::numeric
  ),

  constraint unit_basis_values_convention_check check (
    char_length(btrim(convention)) between 1 and 2000
  ),
  constraint unit_basis_values_note_check check (
    note is null or char_length(btrim(note)) between 1 and 2000
  ),

  -- Load-bearing, not documentation. An earlier draft of this comment repeated
  -- P-2b's wording, that the generated range is evaluated first and this CHECK
  -- is therefore never reached. That is only true for a term inverted by more
  -- than one day: `valid_to = valid_from - 1` makes
  -- `daterange(d, d, '[)')`, which is a legal *empty* range rather than an
  -- error. Without this constraint that row would store an empty validity that
  -- `&&` never matches and `@>` never answers -- a figure that exists, blocks
  -- nothing, and is invisible to every read. The command still handles
  -- `data_exception` because the wider inversions do raise 22000.
  constraint unit_basis_values_term_check check (
    valid_to is null or valid_to >= valid_from
  ),

  constraint unit_basis_values_version_check check (version >= 1),

  -- One value per unit and basis on any given day. Two would mean "how many
  -- people live here on 3 March" has two answers, which is the same failure
  -- two rents for one day would be. All three key columns are NOT NULL, so
  -- unlike `allocation_keys` this constraint needs no coalesce -- there is no
  -- null for `null = null` to let through.
  constraint unit_basis_values_no_overlap exclude using gist (
    workspace_id extensions.gist_uuid_ops with =,
    unit_id extensions.gist_uuid_ops with =,
    basis extensions.gist_enum_ops with =,
    validity with &&
  )
);

-- Leading-column support for the composite unit foreign key (004's positional
-- invariant), and the shape the resolution reads by.
create index unit_basis_values_unit_idx
  on public.unit_basis_values (workspace_id, unit_id, basis);
create index unit_basis_values_basis_idx
  on public.unit_basis_values (workspace_id, basis);

create trigger unit_basis_values_protected_columns
before update on public.unit_basis_values
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.unit_basis_values enable row level security;
alter table public.unit_basis_values force row level security;

create policy unit_basis_values_select_finance_read
on public.unit_basis_values
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.unit_basis_values from public, anon, authenticated;
grant select on table public.unit_basis_values to authenticated;

comment on table public.unit_basis_values is
  'The per-unit figure a distribution basis divides by, for the three bases '
  'this schema has no other home for. Every value states the convention it '
  'was measured under, because no accepted counting rule exists for any of '
  'them and a figure without its convention cannot be checked.';

create function private.unit_basis_value_snapshot(entry public.unit_basis_values)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', entry.id,
    'workspace_id', entry.workspace_id,
    'unit_id', entry.unit_id,
    'basis', entry.basis,
    'value', entry.value,
    'convention', entry.convention,
    'valid_from', entry.valid_from,
    'valid_to', entry.valid_to,
    'note', entry.note,
    'created_at', entry.created_at,
    'updated_at', entry.updated_at,
    'created_by', entry.created_by,
    'updated_by', entry.updated_by,
    'version', entry.version
  );
$function$;

alter function private.unit_basis_value_snapshot(public.unit_basis_values)
  owner to postgres;
revoke all on function private.unit_basis_value_snapshot(
  public.unit_basis_values
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The resolver, now with a date and three fewer holes
-- ---------------------------------------------------------------------------
--
-- Dropped and recreated because it gains an as-of parameter, and a
-- `create or replace` cannot change a signature. Keeping the three-argument
-- version beside it would leave a resolver that ignores time -- which is the
-- one thing this package adds.

drop function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis
);

create function private.allocation_basis_resolution(
  p_workspace_id uuid,
  p_property_id uuid,
  p_basis public.allocation_basis,
  p_as_of date
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_total numeric;
  v_units integer;
  v_missing integer;
  v_valued integer;
  v_conventions integer;
  v_convention text;
  v_recorded_ever boolean;
begin
  -- Meters and readings arrive with P-4. Unchanged by this package, and named
  -- separately from the three below so the two gaps do not blur into one.
  if p_basis = 'consumption' then
    return jsonb_build_object(
      'resolvable', false, 'reason', 'no_meters',
      'detail', 'Meters and readings arrive with P-4.'
    );
  end if;

  if p_basis = 'direct' then
    -- Nothing is distributed, so there is nothing to total. Resolvable, and
    -- deliberately without a total: a direct assignment that reported one
    -- would invite dividing by it.
    return jsonb_build_object(
      'resolvable', true, 'reason', null,
      'detail', 'Assigned to one unit outright; nothing is distributed.'
    );
  end if;

  -- The three this package gives a store. Read as of a date, because a
  -- settlement for a past year needs that year's figures.
  if p_basis in ('fixed_share', 'persons', 'co_ownership_share') then
    select
      count(*)::integer,
      count(entry.value)::integer,
      sum(entry.value),
      count(distinct btrim(entry.convention))::integer,
      min(btrim(entry.convention))
    into v_units, v_valued, v_total, v_conventions, v_convention
    from public.units as unit
    left join public.unit_basis_values as entry
      on entry.workspace_id = unit.workspace_id
      and entry.unit_id = unit.id
      and entry.basis = p_basis
      and entry.validity @> p_as_of
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id;

    -- Asked separately, and only to tell two silences apart: a workspace that
    -- has recorded nothing for this basis, and one whose figures simply do not
    -- cover the day being asked about. Both leave `v_valued` at zero and used
    -- to answer `no_basis_store` alike, which told a reader of a 2024
    -- settlement that they had never entered anything -- the distinction
    -- LEASING-COMPONENTS-01c exists to make.
    select exists (
      select 1
      from public.units as unit
      join public.unit_basis_values as entry
        on entry.workspace_id = unit.workspace_id
        and entry.unit_id = unit.id
        and entry.basis = p_basis
      where unit.workspace_id = p_workspace_id
        and unit.property_id = p_property_id
    )
    into v_recorded_ever;

    return jsonb_build_object(
      -- Every unit must carry a value, every value must have been measured the
      -- same way, and the sum must be something a share can be taken of. A
      -- partial set makes the denominator wrong for the units that do have
      -- one; two conventions make the sum an addition of two different
      -- measurements; and a total of zero is not a denominator at all.
      --
      -- The zero clause restores an invariant the other branches already hold
      -- and this one broke: `unit_count` reports a total it has just required
      -- to be positive, and `area_sqm` sums a column whose own CHECK is
      -- `> 0`. Before this package every `resolvable: true` carried a
      -- divisible total, and the migration's own contract is "the resolution
      -- reports the total and the caller divides". A property whose units are
      -- all recorded as nobody-lives-here is a real state, and the honest
      -- answer is that persons cannot distribute anything there.
      'resolvable',
        v_units > 0 and v_valued = v_units and v_conventions = 1
        and coalesce(v_total, 0) > 0,
      'reason', case
        when v_units = 0 then 'no_units'
        -- Kept as the answer for a workspace that has recorded nothing, so an
        -- untouched installation reads exactly as it did before this package:
        -- the basis has no data, rather than incomplete data.
        when v_valued = 0 and not v_recorded_ever then 'no_basis_store'
        when v_valued = 0 then 'no_value_on_date'
        when v_valued < v_units then 'incomplete_basis'
        when v_conventions > 1 then 'mixed_conventions'
        when coalesce(v_total, 0) <= 0 then 'zero_total'
        else null
      end,
      'unit_count', v_units,
      'units_without_value', v_units - v_valued,
      'total', case
        when v_valued = v_units and v_conventions = 1 and coalesce(v_total, 0) > 0
          then v_total
        -- Withheld in every other case, including the zero one: a number that
        -- cannot be divided by is not a smaller denominator, and DEC-029's
        -- rule is never to sum around a gap.
        else null
      end,
      'convention', case when v_conventions = 1 then v_convention else null end,
      'convention_count', v_conventions,
      'detail', case
        when v_units = 0 then
          'This property has no units to divide over.'
        when v_valued = 0 and not v_recorded_ever then
          'No value has ever been recorded for this basis. There is no agreed '
          'rule to fall back on, so nothing is computed.'
        when v_valued = 0 then
          'Values exist for this basis, but none of them covers that date. '
          'This is not the same as never having recorded any, and a '
          'settlement for that period needs figures that cover it.'
        when v_valued < v_units then
          'Recorded for ' || v_valued || ' of ' || v_units || ' units. The '
          'missing units'' share would otherwise be redistributed over the '
          'rest without saying so.'
        when v_conventions > 1 then
          'The units state ' || v_conventions || ' different conventions for '
          'this basis. Adding figures measured different ways does not '
          'produce a denominator.'
        when coalesce(v_total, 0) <= 0 then
          'Every unit is recorded and they sum to zero. That is a real state, '
          'and it means this basis has nothing to divide by -- not that the '
          'share of each unit is zero.'
        else
          'Sum of the recorded values, all measured as: ' || v_convention
      end
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (where unit.area_sqm is null)::integer,
    sum(unit.area_sqm)
  into v_units, v_missing, v_total
  from public.units as unit
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;

  if p_basis = 'unit_count' then
    return jsonb_build_object(
      'resolvable', v_units > 0,
      'reason', case when v_units = 0 then 'no_units' else null end,
      'unit_count', v_units,
      'total', v_units,
      -- count(*) over the unit records, never `properties.units`, which is the
      -- figure typed on the property and can differ while a building is still
      -- being entered.
      'detail', 'Counted over the unit records.'
    );
  end if;

  if p_basis = 'area_sqm' then
  return jsonb_build_object(
    -- A single unit without an area makes the denominator wrong for every
    -- other unit, because its share is silently redistributed over them. So
    -- the basis is unresolvable until the gap is closed, rather than
    -- resolvable-but-approximate.
    'resolvable', v_units > 0 and v_missing = 0,
    'reason', case
      when v_units = 0 then 'no_units'
      when v_missing > 0 then 'incomplete_basis'
      else null
    end,
    'unit_count', v_units,
    'units_without_value', v_missing,
    -- Withheld when the set is incomplete, which it was not before this
    -- package. The branch declared `incomplete_basis` and then handed out the
    -- sum of the units that happen to have an area -- precisely the figure
    -- DEC-029 forbids ("nie darum herum summieren") and precisely what this
    -- migration's own header says the area basis must not do. Nothing read it
    -- while the verdict said unresolvable; `allocation_keys_as_of` carried it
    -- verbatim into every consumer, and a settlement engine that trusted a
    -- present total over an absent verdict would have divided by it.
    'total', case
      when v_units > 0 and v_missing = 0 then v_total else null
    end,
    'detail',
      'The sum of units.area_sqm. This schema holds four other area figures '
      'and reconciles none of them; this key means this one.'
  );
  end if;

  -- Every enum value above is handled by name, and this is what is left. It
  -- exists because the first version of this function let `area_sqm` be the
  -- unguarded fall-through: plpgsql has no exhaustiveness check, so a value
  -- added to the enum by a later migration would have been answered with the
  -- area sum and an area `detail` -- the legacy "Personen wird zu Flaeche"
  -- failure, rebuilt by the code written to prevent it. An unrecognised basis
  -- now refuses, and the refusal names itself.
  return jsonb_build_object(
    'resolvable', false,
    'reason', 'unknown_basis',
    'detail',
      'This basis was added to the vocabulary without deciding what it '
      'resolves to. It distributes nothing until that decision is made.'
  );
end;
$function$;

alter function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis, date
) owner to postgres;
revoke all on function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis, date
) from public, anon, authenticated;

comment on function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis, date
) is
  'What a basis resolves to for one property on one day, or why it does not. '
  'Every enum value is handled by name and the remaining branch refuses, so a '
  'value added later distributes nothing until somebody decides what it '
  'means. The three stored bases additionally refuse when the units state '
  'more than one convention: adding figures measured different ways does not '
  'produce a denominator.';

-- The as-of read already knows the date; it simply had nowhere to pass it.
create or replace function public.allocation_keys_as_of(
  p_workspace_id uuid,
  p_as_of date default null,
  p_property_id uuid default null,
  p_finance_account_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, private.operations_today());
  v_keys jsonb;
  v_resolvable integer;
  v_total integer;
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

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Allocation keys are not permitted'
      )
    );
  end if;

  select
    coalesce(
      jsonb_agg(
        entry.payload
        order by entry.property_name, entry.account_code nulls first,
                 entry.pool_key nulls first
      ),
      '[]'::jsonb
    ),
    count(*) filter (where entry.resolvable)::integer,
    count(*)::integer
  into v_keys, v_resolvable, v_total
  from (
    select
      property.name as property_name,
      account.code as account_code,
      pool.pool_key as pool_key,
      (resolution.payload ->> 'resolvable')::boolean as resolvable,
      private.allocation_key_snapshot(key)
        || jsonb_build_object(
             'property_name', property.name,
             -- Joined in so a list is readable without a second round trip.
             -- A key that names an account id and nothing else is not a key
             -- anybody can check.
             'finance_account_code', account.code,
             'finance_account_name', account.name,
             'cost_pool_key', pool.pool_key,
             'cost_pool_name', pool.name,
             -- The whole point of the read: what this key would actually
             -- distribute over on the day being asked about.
             'basis_resolution', resolution.payload
           ) as payload
    from public.allocation_keys as key
    join public.properties as property
      on property.workspace_id = key.workspace_id
      and property.id = key.property_id
    left join public.finance_accounts as account
      on account.workspace_id = key.workspace_id
      and account.id = key.finance_account_id
    left join public.cost_pools as pool
      on pool.workspace_id = key.workspace_id
      and pool.id = key.cost_pool_id
    cross join lateral (
      select case
        -- P-2b reports `building`, `entrance` and `meter_group` pools as
        -- `scope_resolvable: false, no_entity`: this schema has no entity for
        -- them, so nothing can say which units they cover. The basis
        -- resolution is computed over the *property's* units and knows nothing
        -- about the pool, so a key on such a pool would inherit a
        -- whole-property denominator and report itself fully resolvable. That
        -- was harmless only while these three bases always answered
        -- `no_basis_store`; the moment P-2c gave them values it became a
        -- number for a scope nobody can delimit.
        when pool.scope in ('building', 'entrance', 'meter_group') then
          jsonb_build_object(
            'resolvable', false,
            'reason', 'pool_scope_unresolvable',
            'detail',
              'This key distributes a pool at a scope this schema has no '
              'entity for, so which units it covers cannot be determined. The '
              'basis itself may be complete; the pool is what cannot be '
              'resolved.'
          )
        else private.allocation_basis_resolution(
          key.workspace_id, key.property_id, key.basis, v_as_of
        )
      end as payload
    ) as resolution
    where key.workspace_id = p_workspace_id
      and (p_property_id is null or key.property_id = p_property_id)
      and (
        p_finance_account_id is null
        or key.finance_account_id = p_finance_account_id
      )
      and key.validity @> v_as_of
  ) as entry;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'keys', v_keys,
      -- Counted by the server over everything that matched. A settlement run
      -- built on these has to be able to say how many of its keys could not
      -- be resolved, and it can only do that if the read tells it.
      'resolvable_count', v_resolvable,
      'unresolvable_count', v_total - v_resolvable,
      'total_count', v_total
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Read
-- ---------------------------------------------------------------------------

create function public.unit_basis_values_as_of(
  p_workspace_id uuid,
  p_property_id uuid,
  p_basis text,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, private.operations_today());
  v_basis public.allocation_basis;
  v_units jsonb;
begin
  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace and property are required'
      )
    );
  end if;

  if p_basis is null or p_basis not in (
       'fixed_share', 'persons', 'co_ownership_share'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'Only fixed share, persons and co-ownership share are stored per '
          'unit. Area is on the unit itself and a unit count is counted.',
        'field', 'basis'
      )
    );
  end if;
  v_basis := p_basis::public.allocation_basis;

  -- Two gates, in the order every other property-scoped finance read uses:
  -- the entity scope first, then the workspace permission. This read returns a
  -- property's entire unit inventory -- codes and areas, one row per unit --
  -- and the function is SECURITY DEFINER, so the workspace permission alone
  -- would hand that inventory to a member scoped to other properties.
  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'This property is not permitted'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Basis values are not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
      and property.deleted_at is null
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found'
      )
    );
  end if;

  -- Every unit of the property, with its value or without one. A read that
  -- listed only the units that have a figure would make the work look
  -- finished, and the missing ones are precisely what makes the basis
  -- unresolvable.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'unit_id', unit.id,
        'unit_code', unit.unit_code,
        'area_sqm', unit.area_sqm,
        'value', case when entry.id is null
                   then null else private.unit_basis_value_snapshot(entry) end
      )
      order by unit.unit_code
    ),
    '[]'::jsonb
  )
  into v_units
  from public.units as unit
  left join public.unit_basis_values as entry
    on entry.workspace_id = unit.workspace_id
    and entry.unit_id = unit.id
    and entry.basis = v_basis
    and entry.validity @> v_as_of
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'basis', p_basis,
      'units', v_units,
      -- The same verdict the allocation keys get, so the two surfaces cannot
      -- disagree about whether this basis is usable.
      'resolution', private.allocation_basis_resolution(
        p_workspace_id, p_property_id, v_basis, v_as_of
      )
    )
  );
end;
$function$;

alter function public.unit_basis_values_as_of(uuid, uuid, text, date)
  owner to postgres;
revoke all on function public.unit_basis_values_as_of(uuid, uuid, text, date)
  from public, anon, authenticated;
grant execute on function public.unit_basis_values_as_of(uuid, uuid, text, date)
  to authenticated;

comment on function public.unit_basis_values_as_of(uuid, uuid, text, date) is
  'Every unit of a property with its basis value on a date, or without one, '
  'plus the same resolution verdict the allocation keys get. Units without a '
  'value are listed rather than filtered away: they are what makes the basis '
  'unresolvable.';

-- ---------------------------------------------------------------------------
-- Write
-- ---------------------------------------------------------------------------

create function public.upsert_unit_basis_value(
  p_workspace_id uuid,
  p_unit_id uuid,
  p_basis text,
  p_value numeric,
  p_convention text,
  p_valid_from date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_value_id uuid default null,
  p_expected_version bigint default null,
  p_valid_to date default null,
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
  v_claim jsonb;
  v_request_hash bytea;
  v_old public.unit_basis_values%rowtype;
  v_new public.unit_basis_values%rowtype;
  v_basis public.allocation_basis;
  v_exists boolean;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_unit_id is null or p_valid_from is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A unit and a start date are required'
      )
    );
  end if;

  if p_basis is null or p_basis not in (
       'fixed_share', 'persons', 'co_ownership_share'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'Only fixed share, persons and co-ownership share are stored per '
          'unit. Area lives on the unit and a unit count is counted, so a '
          'second copy here could only disagree with them.',
        'field', 'basis'
      )
    );
  end if;
  v_basis := p_basis::public.allocation_basis;

  -- `= 'NaN'` explicitly: `'NaN' < 0` is FALSE, so a negative-only guard lets
  -- through the one value that makes every downstream share meaningless while
  -- the resolution still calls the basis usable.
  if p_value is null or p_value < 0 or p_value = 'NaN'::numeric then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A value is required, must be a real number, and cannot be '
          'negative. Zero is allowed and means the figure is nil, which is '
          'not the same as unrecorded.',
        'field', 'value'
      )
    );
  end if;

  -- Refused, not defaulted. There is no accepted rule for counting any of
  -- these three -- DEC-014 decides none of them and lists none as contested --
  -- so a figure that does not say how it was measured is a figure nobody can
  -- check, and two such figures cannot be added together.
  if p_convention is null
     or char_length(btrim(p_convention)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'State how this figure was measured. No counting rule is agreed for '
          'this basis, so the convention is part of the figure.',
        'field', 'convention'
      )
    );
  end if;

  if p_valid_to is not null and p_valid_to < p_valid_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'The end is before the start',
        'field', 'validTo'
      )
    );
  end if;

  -- A version without an id is a caller who thinks they are changing
  -- something. Refused before the claim rather than silently creating a
  -- second row beside the one they meant to edit.
  if p_value_id is null and p_expected_version is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A version was given but no value to apply it to',
        'field', 'expectedVersion'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage')
     or not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Basis value write is not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.units as unit
    where unit.workspace_id = p_workspace_id and unit.id = p_unit_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Unit not found'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_unit_basis_value',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'value_id', p_value_id,
        'unit_id', p_unit_id,
        'basis', p_basis,
        'value', p_value,
        'convention', p_convention,
        'valid_from', p_valid_from,
        'valid_to', p_valid_to,
        'note', p_note,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  if p_value_id is not null then
    select entry.* into v_old
    from public.unit_basis_values as entry
    where entry.workspace_id = p_workspace_id and entry.id = p_value_id
    for update;
    v_exists := found;

    if not v_exists then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Basis value not found'
        )
      );
    end if;
  else
    v_exists := false;
  end if;

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'unit_basis_value'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- After the claim, so a retried create is replayed rather than answered
  -- with "a version is required" once its own first call has made the row.
  if v_exists and (p_expected_version is null or p_expected_version < 1) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An expected version is required to change an existing value',
        'field', 'expectedVersion'
      )
    );
  end if;

  if v_exists and v_old.version <> p_expected_version then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Basis value version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.unit_basis_value_snapshot(v_old)
      )
    );
  end if;

  begin
    if v_exists then
      update public.unit_basis_values as entry
      set
        unit_id = p_unit_id,
        basis = v_basis,
        value = p_value,
        convention = btrim(p_convention),
        valid_from = p_valid_from,
        valid_to = p_valid_to,
        note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now(),
        updated_by = v_actor_id,
        version = entry.version + 1
      where entry.workspace_id = p_workspace_id and entry.id = p_value_id
      returning * into v_new;
    else
      insert into public.unit_basis_values (
        workspace_id, unit_id, basis, value, convention, valid_from, valid_to,
        note, created_by, updated_by
      ) values (
        p_workspace_id, p_unit_id, v_basis, p_value, btrim(p_convention),
        p_valid_from, p_valid_to,
        nullif(btrim(coalesce(p_note, '')), ''), v_actor_id, v_actor_id
      )
      returning * into v_new;
    end if;
  exception
    when exclusion_violation then
      perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message',
            'This unit already has a value for that basis covering part of '
            'that period'
        )
      );
    -- `data_exception` alongside `check_violation`: an inverted term is
    -- rejected by the generated range expression, not by the CHECK, and it
    -- raises 22000 rather than 23514.
    when check_violation or data_exception then
      perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'The value is inconsistent'
        )
      );
  end;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_exists
      then 'unit_basis_value.update' else 'unit_basis_value.create' end,
    'unit_basis_value', v_new.id,
    case when v_exists
      then private.unit_basis_value_snapshot(v_old) else null end,
    private.unit_basis_value_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.unit_basis_value_snapshot(v_new)
  );
end;
$function$;

alter function public.upsert_unit_basis_value(
  uuid, uuid, text, numeric, text, date, uuid, uuid, uuid, bigint, date, text,
  text
) owner to postgres;
revoke all on function public.upsert_unit_basis_value(
  uuid, uuid, text, numeric, text, date, uuid, uuid, uuid, bigint, date, text,
  text
) from public, anon, authenticated;
grant execute on function public.upsert_unit_basis_value(
  uuid, uuid, text, numeric, text, date, uuid, uuid, uuid, bigint, date, text,
  text
) to authenticated;
