-- COST-POOLS-ALLOCATION-KEYS-01 (P-2b, second half of Cost Categories + Pools
-- + Allocation Keys).
--
-- **What the programme actually mandates is two sentences.** Verbatim:
--
--   "cost_pools — Kostenpool mit Scope (Portfolio/Property/Building/Entrance/
--    Unit/Meter-Gruppe)."
--   "allocation_keys — versioniert und zeitabhaengig, je Property/Kostenart/
--    Pool/Periode."
--
-- Everything below beyond a scope discriminator and that four-part grain is a
-- design decision taken here, not a requirement read out of a document. This
-- header says which is which, because the alternative is a later reader
-- treating an invention as a mandate.
--
-- **The legacy allocation feature is not a template; it is a warning.** It
-- stored German display strings in a free-text column and matched them by
-- case-insensitive substring, so `Umlageschluessel Heizung` routed into the
-- branch for `Individuelle Schluessel`. Two editors offered disjoint option
-- lists writing to the same column. `Verbrauch` and `Individuelle Schluessel`
-- fabricated their per-unit values from `String.hashCode`; `Personen` and
-- `Miteigentumsanteil` silently fell through to area. The programme already
-- lists that consumption apportionment among the four legacy finds that must
-- not migrate because they invent numbers. So: machine identity for the basis,
-- a workspace-owned label separately, and nothing carried over.
--
-- **"Kostenart" is `finance_accounts`, not a new tree.** The guardrail is
-- explicit and P-2a already hung apportionability and the settlement principle
-- off that tree as a satellite. Neither table here carries `allocatable`, a
-- BetrKV position or a settlement principle: they would be a second, silently
-- diverging copy of a decision `finance_account_allocation_rules` already owns
-- under three CHECK constraints.
--
-- **"Periode" is a validity range here, not a foreign key.** The programme
-- names `service_charge_periods` as the settlement period, per property, with
-- its own status model -- and groups it with the settlement engine, which is
-- P-5. A key bound to a period row would have to be re-entered for every
-- accounting year; a key with a validity range is asked "which key was in
-- force then", exactly as `lease_components_as_of` is. The period table, when
-- P-5 builds it, becomes a consumer of these keys rather than their parent.
--
-- **Three of the six scopes have no entity to point at.** Building, Entrance
-- and Meter group exist nowhere in this schema, and meters are P-4. They are
-- kept in the vocabulary because the programme enumerates them and dropping
-- them would narrow the model silently -- but a pool at one of those scopes
-- carries a workspace-written label as its only identity, and the read reports
-- it as unresolvable. It can hold costs a human assigns; it cannot be
-- distributed automatically, and it says so rather than distributing wrongly.
--
-- **Four of the seven bases cannot be resolved from anything stored today.**
-- `units.area_sqm` is the only distribution basis this schema actually holds,
-- and a unit count is `count(*)` over `public.units`. Persons, co-ownership
-- shares, fixed shares and consumption have no store at all -- the first three
-- get one in P-2c, consumption in P-4. They are named, reported as
-- unresolvable with the reason, and refuse to compute. The alternative, which
-- the legacy code took, is to fall through to area and produce a number.
--
-- **Area is ambiguous and the key must say which one it means.** This schema
-- holds `properties.sqft`, `properties.residential_area`, `commercial_area`,
-- `land_area` and the sum of `units.area_sqm`, and nothing reconciles them.
-- Only the last is reachable by a write path that exists. `area` here means
-- the sum of `units.area_sqm` over the units in scope, stated in the comment
-- on the enum value, and the read returns that sum together with how many
-- units have no area recorded -- because a missing area is a gap, and
-- redistributing that unit's share over its neighbours is the quiet error this
-- whole package is shaped to prevent.
--
-- **The explanation is mandatory, and that is `DEC-014`.** Model consequence 2
-- makes the "Verteilerschluessel mit Erlaeuterung" one of the four Mindest-
-- angaben whose absence renders an operating-cost statement formally void --
-- the most expensive failure mode in the module, because it costs the whole
-- claim rather than a correction. A key that cannot explain itself cannot
-- appear on a statement, so it cannot be stored without an explanation either.
--
-- **This migration also corrects P-2a.** `set_cost_allocation_rule` was
-- written against `private.party_command_gate` and released its receipt with a
-- DELETE. The finance-scoped set is the more mature one and the right one for
-- a finance table: its gate checks `is_aal2()` explicitly (DEC-025) instead of
-- relying on the permission helper to do it later, and `fail_finance_mutation`
-- marks a receipt failed rather than deleting it -- so a retry re-arms only
-- when the request hash matches, which a deleted receipt cannot check. Not a
-- security hole as it stood (SR-21 guarantees the permission helper asserts
-- AAL2), but an inconsistency that would have propagated.
--
-- Four new public functions: SR-20 101 -> 105.
-- Two new client-reachable policies: SR-22 53 -> 55.

-- Idempotent, and repeated deliberately. It is installed exactly once today,
-- by LEASING-COMPONENTS-01, and every later EXCLUDE constraint has silently
-- depended on that migration having run first. Repeating it costs nothing and
-- makes this migration replayable on its own.
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------------
-- Vocabulary
-- ---------------------------------------------------------------------------

create type public.cost_pool_scope as enum (
  -- Every property in the workspace. `property_id` is null for exactly this.
  'portfolio',
  'property',
  'unit',
  -- The three the schema has no entity for. A pool at these scopes carries a
  -- workspace-written label and is reported as unresolvable.
  'building',
  'entrance',
  'meter_group'
);

create type public.allocation_basis as enum (
  -- The sum of `units.area_sqm` over the units in scope. Named precisely
  -- because this schema holds four other area figures and nothing reconciles
  -- them.
  'area_sqm',
  -- count(*) over public.units -- never `properties.units`, which is the
  -- figure typed on the property and can differ while a building is being
  -- entered.
  'unit_count',
  -- Assigned to one unit outright; nothing is distributed.
  'direct',
  -- The four with no store. P-2c gives the first three one; consumption is
  -- P-4. Until then they resolve to nothing and say why.
  'fixed_share',
  'persons',
  'co_ownership_share',
  'consumption'
);

-- ---------------------------------------------------------------------------
-- Cost pools
-- ---------------------------------------------------------------------------

create table public.cost_pools (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,

  -- Null exactly for the portfolio scope. Every other scope names a property,
  -- including the three that then narrow further by label.
  property_id uuid,

  -- Stable within its scope, chosen by the workspace. The name is what a human
  -- reads; this is what a later run line cites.
  pool_key text not null,
  name text not null,

  scope public.cost_pool_scope not null,

  -- The only identity a building, entrance or meter group has in this schema.
  -- Required for those three, forbidden for the others -- where it would be a
  -- second name competing with `name`.
  scope_label text,

  note text,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  constraint cost_pools_workspace_id_key unique (workspace_id, id),
  constraint cost_pools_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  -- Single-column, like every other table that points at a property:
  -- `properties` carries no composite unique key and adding one is a change to
  -- an existing table. The commands verify the workspace explicitly.
  constraint cost_pools_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,

  constraint cost_pools_key_check check (
    pool_key = btrim(pool_key)
    and pool_key ~ '^[a-z0-9][a-z0-9._-]{0,49}$'
  ),
  constraint cost_pools_name_check check (
    char_length(btrim(name)) between 1 and 200
  ),
  constraint cost_pools_note_check check (
    note is null or char_length(btrim(note)) between 1 and 2000
  ),

  -- The portfolio scope is the workspace, so it has no property; every other
  -- scope does. Stated as an equivalence rather than two one-way checks, so
  -- neither half can be satisfied alone.
  constraint cost_pools_portfolio_scope_check check (
    (scope = 'portfolio' and property_id is null)
    or (scope <> 'portfolio' and property_id is not null)
  ),

  -- A label is the entire identity of a building, entrance or meter group
  -- here, so it is required for those and refused for the rest. `is not null`
  -- is spelled out on both sides: a comparison against a null label evaluates
  -- to NULL, and a CHECK that evaluates to NULL is satisfied.
  constraint cost_pools_scope_label_check check (
    (scope in ('building', 'entrance', 'meter_group')
      and scope_label is not null
      and char_length(btrim(scope_label)) between 1 and 200)
    or (scope not in ('building', 'entrance', 'meter_group')
      and scope_label is null)
  ),

  constraint cost_pools_version_check check (version >= 1)
);

-- One pool key per property, and one per workspace for the portfolio scope.
-- Two partial indexes rather than one over a nullable column: `null = null` is
-- not true, so a single unique index would let two portfolio pools share a key.
create unique index cost_pools_property_key_idx
  on public.cost_pools (workspace_id, property_id, pool_key)
  where property_id is not null;
create unique index cost_pools_portfolio_key_idx
  on public.cost_pools (workspace_id, pool_key)
  where property_id is null;

-- The foreign key is on `property_id` alone, so the supporting index has to
-- lead with it (004's leading-column invariant).
create index cost_pools_property_fk_idx
  on public.cost_pools (property_id)
  where property_id is not null;
create index cost_pools_workspace_idx
  on public.cost_pools (workspace_id, is_active);

create trigger cost_pools_protected_columns
before update on public.cost_pools
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.cost_pools enable row level security;
alter table public.cost_pools force row level security;

create policy cost_pools_select_finance_read
on public.cost_pools
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.cost_pools from public, anon, authenticated;
grant select on table public.cost_pools to authenticated;

comment on table public.cost_pools is
  'A pool of costs at one of six scopes. Building, entrance and meter group '
  'have no entity in this schema, so a pool at those scopes carries a '
  'workspace-written label and is reported as not automatically resolvable.';

-- ---------------------------------------------------------------------------
-- Allocation keys
-- ---------------------------------------------------------------------------

create table public.allocation_keys (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,

  -- Required: the programme's grain is "je Property".
  property_id uuid not null,

  -- Null means the key applies to any cost type not otherwise keyed. The
  -- exclusion constraint below coalesces it, so two such keys still cannot
  -- overlap.
  finance_account_id uuid,
  cost_pool_id uuid,

  basis public.allocation_basis not null,

  -- Mandatory, and DEC-014 model consequence 2 is why: the "Verteiler-
  -- schluessel mit Erlaeuterung" is one of the four Mindestangaben whose
  -- absence makes an operating-cost statement formally void. A key that
  -- cannot explain itself cannot appear on a statement.
  explanation text not null,

  valid_from date not null,
  -- Inclusive. Null is open-ended, which is the normal state of a current key.
  valid_to date,

  note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  -- Half-open internally so adjacent periods do not overlap, inclusive at the
  -- edges of the API so a date reads the way a contract does.
  validity daterange generated always as (
    daterange(
      valid_from,
      case when valid_to is null then null else valid_to + 1 end,
      '[)'
    )
  ) stored,

  constraint allocation_keys_workspace_id_key unique (workspace_id, id),
  constraint allocation_keys_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint allocation_keys_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint allocation_keys_account_fkey
    foreign key (workspace_id, finance_account_id)
    references public.finance_accounts (workspace_id, id) on delete restrict,
  constraint allocation_keys_pool_fkey
    foreign key (workspace_id, cost_pool_id)
    references public.cost_pools (workspace_id, id) on delete restrict,

  constraint allocation_keys_explanation_check check (
    char_length(btrim(explanation)) between 1 and 2000
  ),
  constraint allocation_keys_note_check check (
    note is null or char_length(btrim(note)) between 1 and 2000
  ),
  constraint allocation_keys_term_check check (
    valid_to is null or valid_to >= valid_from
  ),
  constraint allocation_keys_version_check check (version >= 1),

  -- The invariant this table exists to hold: for one property, one cost type
  -- and one pool, no two keys may cover the same day. Otherwise "how is this
  -- cost distributed on 3 March" has two answers, which is the same failure
  -- two rents for one day would be.
  --
  -- The two nullable columns are coalesced to the nil UUID. Without that,
  -- `null = null` is not true and the constraint would happily accept two
  -- overlapping keys that both leave the cost type open -- exactly the rows it
  -- exists to reject.
  constraint allocation_keys_no_overlap exclude using gist (
    workspace_id extensions.gist_uuid_ops with =,
    property_id extensions.gist_uuid_ops with =,
    (coalesce(finance_account_id, '00000000-0000-0000-0000-000000000000'::uuid))
      extensions.gist_uuid_ops with =,
    (coalesce(cost_pool_id, '00000000-0000-0000-0000-000000000000'::uuid))
      extensions.gist_uuid_ops with =,
    validity with &&
  )
);

create index allocation_keys_property_idx
  on public.allocation_keys (workspace_id, property_id);
-- Leading-column support for the single-column property foreign key.
create index allocation_keys_property_fk_idx
  on public.allocation_keys (property_id);
create index allocation_keys_account_idx
  on public.allocation_keys (workspace_id, finance_account_id)
  where finance_account_id is not null;
create index allocation_keys_pool_idx
  on public.allocation_keys (workspace_id, cost_pool_id)
  where cost_pool_id is not null;

create trigger allocation_keys_protected_columns
before update on public.allocation_keys
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.allocation_keys enable row level security;
alter table public.allocation_keys force row level security;

create policy allocation_keys_select_finance_read
on public.allocation_keys
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.allocation_keys from public, anon, authenticated;
grant select on table public.allocation_keys to authenticated;

comment on table public.allocation_keys is
  'How a cost is distributed, per property, cost type and pool, with a '
  'validity range. The explanation is mandatory because it is one of the four '
  'Mindestangaben (DEC-014). Four of the seven bases have no store yet and '
  'resolve to nothing rather than falling back to area.';

-- ---------------------------------------------------------------------------
-- Audit payloads
-- ---------------------------------------------------------------------------

create function private.cost_pool_snapshot(pool public.cost_pools)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', pool.id,
    'workspace_id', pool.workspace_id,
    'property_id', pool.property_id,
    'pool_key', pool.pool_key,
    'name', pool.name,
    'scope', pool.scope,
    'scope_label', pool.scope_label,
    'note', pool.note,
    'is_active', pool.is_active,
    'created_at', pool.created_at,
    'updated_at', pool.updated_at,
    'created_by', pool.created_by,
    'updated_by', pool.updated_by,
    'version', pool.version
  );
$function$;

alter function private.cost_pool_snapshot(public.cost_pools) owner to postgres;
revoke all on function private.cost_pool_snapshot(public.cost_pools)
  from public, anon, authenticated;

create function private.allocation_key_snapshot(key public.allocation_keys)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', key.id,
    'workspace_id', key.workspace_id,
    'property_id', key.property_id,
    'finance_account_id', key.finance_account_id,
    'cost_pool_id', key.cost_pool_id,
    'basis', key.basis,
    'explanation', key.explanation,
    'valid_from', key.valid_from,
    'valid_to', key.valid_to,
    'note', key.note,
    'created_at', key.created_at,
    'updated_at', key.updated_at,
    'created_by', key.created_by,
    'updated_by', key.updated_by,
    'version', key.version
  );
$function$;

alter function private.allocation_key_snapshot(public.allocation_keys)
  owner to postgres;
revoke all on function private.allocation_key_snapshot(public.allocation_keys)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- What a basis actually resolves to, in one place
-- ---------------------------------------------------------------------------

create function private.allocation_basis_resolution(
  p_workspace_id uuid,
  p_property_id uuid,
  p_basis public.allocation_basis
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
begin
  -- The four with no store. Named individually rather than as an else-branch,
  -- so adding a basis to the enum without deciding this is a compile-time
  -- omission a reader can see rather than a silent fall-through -- which is
  -- precisely how the legacy implementation turned "Personen" into area.
  if p_basis = 'fixed_share' then
    return jsonb_build_object(
      'resolvable', false, 'reason', 'no_basis_store',
      'detail', 'Fixed shares have no store yet; P-2c adds one.'
    );
  end if;
  if p_basis = 'persons' then
    return jsonb_build_object(
      'resolvable', false, 'reason', 'no_basis_store',
      'detail', 'No occupancy figures are recorded anywhere in this schema.'
    );
  end if;
  if p_basis = 'co_ownership_share' then
    return jsonb_build_object(
      'resolvable', false, 'reason', 'no_basis_store',
      'detail', 'Co-ownership shares have no store yet; P-2c adds one.'
    );
  end if;
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

  -- area_sqm.
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
    'total', v_total,
    'detail',
      'The sum of units.area_sqm. This schema holds four other area figures '
      'and reconciles none of them; this key means this one.'
  );
end;
$function$;

alter function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis
) owner to postgres;
revoke all on function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis
) from public, anon, authenticated;

comment on function private.allocation_basis_resolution(
  uuid, uuid, public.allocation_basis
) is
  'What a basis resolves to for one property, or why it does not. The four '
  'bases with no store are named individually so adding an enum value without '
  'deciding this is visible rather than a silent fall-through.';

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

create function public.workspace_cost_pools(
  p_workspace_id uuid,
  p_property_id uuid default null,
  p_include_inactive boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_pools jsonb;
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
        'code', 'forbidden', 'message', 'Cost pools are not permitted'
      )
    );
  end if;

  select coalesce(
    jsonb_agg(
      private.cost_pool_snapshot(pool)
      || jsonb_build_object(
           'property_name', property.name,
           -- Said on every pool rather than left for the caller to infer from
           -- the scope. A pool at a scope this schema has no entity for can
           -- hold costs a human assigns; it cannot be distributed
           -- automatically, and the difference has to be visible where the
           -- pool is read.
           'scope_resolvable',
             pool.scope not in ('building', 'entrance', 'meter_group'),
           'scope_unresolvable_reason', case
             when pool.scope in ('building', 'entrance', 'meter_group')
               then 'no_entity'
             else null
           end
         )
      order by property.name nulls first, pool.pool_key
    ),
    '[]'::jsonb
  )
  into v_pools
  from public.cost_pools as pool
  left join public.properties as property
    on property.workspace_id = pool.workspace_id
    and property.id = pool.property_id
  where pool.workspace_id = p_workspace_id
    and (p_property_id is null or pool.property_id = p_property_id)
    and (p_include_inactive or pool.is_active);

  return jsonb_build_object(
    'ok', true, 'entity', jsonb_build_object('pools', v_pools)
  );
end;
$function$;

alter function public.workspace_cost_pools(uuid, uuid, boolean)
  owner to postgres;
revoke all on function public.workspace_cost_pools(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.workspace_cost_pools(uuid, uuid, boolean)
  to authenticated;

comment on function public.workspace_cost_pools(uuid, uuid, boolean) is
  'Cost pools, with whether each one''s scope can be resolved to units at all. '
  'Building, entrance and meter group cannot: this schema has no entity for '
  'them, so they carry a label and are reported as such.';

create function public.allocation_keys_as_of(
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
             -- distribute over today, or why it would not.
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
    cross join lateral private.allocation_basis_resolution(
      key.workspace_id, key.property_id, key.basis
    ) as resolution(payload)
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

alter function public.allocation_keys_as_of(uuid, date, uuid, uuid)
  owner to postgres;
revoke all on function public.allocation_keys_as_of(uuid, date, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.allocation_keys_as_of(uuid, date, uuid, uuid)
  to authenticated;

comment on function public.allocation_keys_as_of(uuid, date, uuid, uuid) is
  'The allocation keys in force on a date, each with what its basis actually '
  'resolves to today or why it does not, and how many of them are '
  'unresolvable. Four of the seven bases have no store yet and say so rather '
  'than falling back to area.';

-- ---------------------------------------------------------------------------
-- upsert_cost_pool
-- ---------------------------------------------------------------------------

create function public.upsert_cost_pool(
  p_workspace_id uuid,
  p_pool_key text,
  p_name text,
  p_scope text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_pool_id uuid default null,
  p_expected_version bigint default null,
  p_property_id uuid default null,
  p_scope_label text default null,
  p_note text default null,
  p_is_active boolean default true,
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
  v_old public.cost_pools%rowtype;
  v_new public.cost_pools%rowtype;
  v_scope public.cost_pool_scope;
  v_exists boolean;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_scope is null or p_scope not in (
       'portfolio', 'property', 'unit', 'building', 'entrance', 'meter_group'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown cost pool scope',
        'field', 'scope'
      )
    );
  end if;
  v_scope := p_scope::public.cost_pool_scope;

  if p_pool_key is null or btrim(p_pool_key) !~ '^[a-z0-9][a-z0-9._-]{0,49}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A pool key is lower-case letters, digits, dot, dash or underscore',
        'field', 'poolKey'
      )
    );
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A name is required',
        'field', 'name'
      )
    );
  end if;

  -- A version without an id is a caller who thinks they are changing
  -- something. Refused before the claim rather than silently creating a second
  -- row beside the one they meant to edit -- which is the failure that is
  -- invisible until somebody wonders why there are two.
  if p_pool_id is null and p_expected_version is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A version was given but no pool to apply it to',
        'field', 'expectedVersion'
      )
    );
  end if;

  -- Reported before the CHECK so the message says what is wrong rather than
  -- naming a constraint. The constraint stays as the thing that cannot be
  -- circumvented.
  if v_scope = 'portfolio' and p_property_id is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A portfolio pool spans the workspace and names no property',
        'field', 'propertyId'
      )
    );
  end if;
  if v_scope <> 'portfolio' and p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'This scope needs a property',
        'field', 'propertyId'
      )
    );
  end if;

  if v_scope in ('building', 'entrance', 'meter_group')
     and (p_scope_label is null
          or char_length(btrim(p_scope_label)) not between 1 and 200) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'This schema has no entity for a building, entrance or meter group, '
          'so the label is the pool''s only identity and is required',
        'field', 'scopeLabel'
      )
    );
  end if;
  if v_scope not in ('building', 'entrance', 'meter_group')
     and p_scope_label is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'This scope names a real entity, so it takes no label',
        'field', 'scopeLabel'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage')
     or not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Cost pool write is not permitted'
      )
    );
  end if;

  -- The foreign key is single-column, so this is what actually holds the
  -- workspace boundary.
  if p_property_id is not null and not exists (
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

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_cost_pool',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'pool_id', p_pool_id,
        'pool_key', p_pool_key,
        'name', p_name,
        'scope', p_scope,
        'property_id', p_property_id,
        'scope_label', p_scope_label,
        'note', p_note,
        'is_active', p_is_active,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  if p_pool_id is not null then
    select pool.* into v_old
    from public.cost_pools as pool
    where pool.workspace_id = p_workspace_id and pool.id = p_pool_id
    for update;
    v_exists := found;

    if not v_exists then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Cost pool not found'
        )
      );
    end if;
  else
    v_exists := false;
  end if;

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'cost_pool'
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
        'message', 'An expected version is required to change an existing pool',
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
        'message', 'Cost pool version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.cost_pool_snapshot(v_old)
      )
    );
  end if;

  begin
    if v_exists then
      update public.cost_pools as pool
      set
        pool_key = btrim(p_pool_key),
        name = btrim(p_name),
        scope = v_scope,
        property_id = p_property_id,
        scope_label = nullif(btrim(coalesce(p_scope_label, '')), ''),
        note = nullif(btrim(coalesce(p_note, '')), ''),
        is_active = coalesce(p_is_active, true),
        updated_at = now(),
        updated_by = v_actor_id,
        version = pool.version + 1
      where pool.workspace_id = p_workspace_id and pool.id = p_pool_id
      returning * into v_new;
    else
      insert into public.cost_pools (
        workspace_id, property_id, pool_key, name, scope, scope_label, note,
        is_active, created_by, updated_by
      ) values (
        p_workspace_id, p_property_id, btrim(p_pool_key), btrim(p_name),
        v_scope, nullif(btrim(coalesce(p_scope_label, '')), ''),
        nullif(btrim(coalesce(p_note, '')), ''), coalesce(p_is_active, true),
        v_actor_id, v_actor_id
      )
      returning * into v_new;
    end if;
  exception
    when unique_violation then
      perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message', 'A pool with this key already exists in that scope',
          'field', 'poolKey'
        )
      );
    when check_violation then
      perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'The pool is inconsistent'
        )
      );
  end;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_exists then 'cost_pool.update' else 'cost_pool.create' end,
    'cost_pool', v_new.id,
    case when v_exists then private.cost_pool_snapshot(v_old) else null end,
    private.cost_pool_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.cost_pool_snapshot(v_new)
  );
end;
$function$;

alter function public.upsert_cost_pool(
  uuid, text, text, text, uuid, uuid, uuid, bigint, uuid, text, text, boolean, text
) owner to postgres;
revoke all on function public.upsert_cost_pool(
  uuid, text, text, text, uuid, uuid, uuid, bigint, uuid, text, text, boolean, text
) from public, anon, authenticated;
grant execute on function public.upsert_cost_pool(
  uuid, text, text, text, uuid, uuid, uuid, bigint, uuid, text, text, boolean, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- upsert_allocation_key
-- ---------------------------------------------------------------------------

create function public.upsert_allocation_key(
  p_workspace_id uuid,
  p_property_id uuid,
  p_basis text,
  p_explanation text,
  p_valid_from date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_key_id uuid default null,
  p_expected_version bigint default null,
  p_finance_account_id uuid default null,
  p_cost_pool_id uuid default null,
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
  v_old public.allocation_keys%rowtype;
  v_new public.allocation_keys%rowtype;
  v_basis public.allocation_basis;
  v_exists boolean;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_property_id is null or p_valid_from is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A property and a start date are required'
      )
    );
  end if;

  if p_basis is null or p_basis not in (
       'area_sqm', 'unit_count', 'direct', 'fixed_share', 'persons',
       'co_ownership_share', 'consumption'
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Unknown allocation basis',
        'field', 'basis'
      )
    );
  end if;
  v_basis := p_basis::public.allocation_basis;

  -- Refused, not defaulted. DEC-014 model consequence 2 makes the
  -- "Verteilerschluessel mit Erlaeuterung" one of the four Mindestangaben, and
  -- their absence makes a statement formally void -- which costs the whole
  -- claim rather than a correction.
  if p_explanation is null
     or char_length(btrim(p_explanation)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'An explanation is required: it is one of the four Mindestangaben a '
          'statement is formally void without',
        'field', 'explanation'
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
  -- something. Refused before the claim rather than silently creating a second
  -- row beside the one they meant to edit -- which is the failure that is
  -- invisible until somebody wonders why there are two.
  if p_key_id is null and p_expected_version is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A version was given but no key to apply it to',
        'field', 'expectedVersion'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage')
     or not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Allocation key write is not permitted'
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

  if p_finance_account_id is not null and not exists (
    select 1 from public.finance_accounts as account
    where account.workspace_id = p_workspace_id
      and account.id = p_finance_account_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Finance account not found'
      )
    );
  end if;

  if p_cost_pool_id is not null and not exists (
    select 1 from public.cost_pools as pool
    where pool.workspace_id = p_workspace_id and pool.id = p_cost_pool_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Cost pool not found'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_allocation_key',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'key_id', p_key_id,
        'property_id', p_property_id,
        'finance_account_id', p_finance_account_id,
        'cost_pool_id', p_cost_pool_id,
        'basis', p_basis,
        'explanation', p_explanation,
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

  if p_key_id is not null then
    select key.* into v_old
    from public.allocation_keys as key
    where key.workspace_id = p_workspace_id and key.id = p_key_id
    for update;
    v_exists := found;

    if not v_exists then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Allocation key not found'
        )
      );
    end if;
  else
    v_exists := false;
  end if;

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'allocation_key'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_exists and (p_expected_version is null or p_expected_version < 1) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An expected version is required to change an existing key',
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
        'message', 'Allocation key version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.allocation_key_snapshot(v_old)
      )
    );
  end if;

  begin
    if v_exists then
      update public.allocation_keys as key
      set
        property_id = p_property_id,
        finance_account_id = p_finance_account_id,
        cost_pool_id = p_cost_pool_id,
        basis = v_basis,
        explanation = btrim(p_explanation),
        valid_from = p_valid_from,
        valid_to = p_valid_to,
        note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now(),
        updated_by = v_actor_id,
        version = key.version + 1
      where key.workspace_id = p_workspace_id and key.id = p_key_id
      returning * into v_new;
    else
      insert into public.allocation_keys (
        workspace_id, property_id, finance_account_id, cost_pool_id, basis,
        explanation, valid_from, valid_to, note, created_by, updated_by
      ) values (
        p_workspace_id, p_property_id, p_finance_account_id, p_cost_pool_id,
        v_basis, btrim(p_explanation), p_valid_from, p_valid_to,
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
            'Another key for this property, cost type and pool already covers '
            'part of that period'
        )
      );
    when check_violation then
      perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'The key is inconsistent'
        )
      );
  end;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_exists
      then 'allocation_key.update' else 'allocation_key.create' end,
    'allocation_key', v_new.id,
    case when v_exists then private.allocation_key_snapshot(v_old) else null end,
    private.allocation_key_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.allocation_key_snapshot(v_new)
  );
end;
$function$;

alter function public.upsert_allocation_key(
  uuid, uuid, text, text, date, uuid, uuid, uuid, bigint, uuid, uuid, date, text, text
) owner to postgres;
revoke all on function public.upsert_allocation_key(
  uuid, uuid, text, text, date, uuid, uuid, uuid, bigint, uuid, uuid, date, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_allocation_key(
  uuid, uuid, text, text, date, uuid, uuid, uuid, bigint, uuid, uuid, date, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- P-2a correction: the finance command surface, consistently
-- ---------------------------------------------------------------------------
--
-- `set_cost_allocation_rule` shipped against `private.party_command_gate` and
-- released its receipt with a DELETE. Both are corrected here, and neither is
-- cosmetic:
--
--   * the finance gate asserts `private.is_aal2()` itself (DEC-025) rather
--     than relying on the permission helper to assert it a few lines later.
--     The outcome was the same -- SR-21 guarantees the helper checks it -- but
--     an aal1 caller was told "the write is not permitted" instead of "AAL2 is
--     required", and the check sat in a different place than in every other
--     finance command.
--   * `fail_finance_mutation` marks a receipt failed; the DELETE removed it.
--     A deleted receipt cannot compare request hashes on the retry, so a
--     different command reusing that mutation id would have been accepted as a
--     fresh attempt instead of refused as a conflict.

create or replace function public.set_cost_allocation_rule(
  p_workspace_id uuid,
  p_finance_account_id uuid,
  p_allocatable boolean,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_expected_version bigint default null,
  p_settlement_principle text default null,
  p_betrkv_position text default null,
  p_under_heating_cost_regulation boolean default false,
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
  v_old public.finance_account_allocation_rules%rowtype;
  v_new public.finance_account_allocation_rules%rowtype;
  v_principle public.cost_settlement_principle;
  v_exists boolean;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_finance_account_id is null or p_allocatable is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Account and allocatable flag are required'
      )
    );
  end if;

  if p_settlement_principle is not null
     and p_settlement_principle not in ('performance', 'outflow') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unknown settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  v_principle := case
    when p_settlement_principle is null then null
    else p_settlement_principle::public.cost_settlement_principle
  end;

  if p_allocatable and v_principle is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An apportionable cost needs a settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  if not p_allocatable and v_principle is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A cost that is not apportionable has no settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  -- Order matters. A HeizkostenV position that is not apportionable is wrong
  -- about what kind of cost it is; which principle it settles on is downstream
  -- of that.
  if coalesce(p_under_heating_cost_regulation, false) and not p_allocatable then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'The HeizkostenV is about apportioning heating costs, so a position '
          'under it is apportionable',
        'field', 'allocatable'
      )
    );
  end if;

  if coalesce(p_under_heating_cost_regulation, false)
     and v_principle is distinct from 'performance' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A HeizkostenV position is settled on the performance principle '
          '(BGH VIII ZR 156/11)',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage')
     or not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Cost allocation rule write is not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.finance_accounts as account
    where account.workspace_id = p_workspace_id
      and account.id = p_finance_account_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Finance account not found'
      )
    );
  end if;

  select rule.* into v_old
  from public.finance_account_allocation_rules as rule
  where rule.workspace_id = p_workspace_id
    and rule.finance_account_id = p_finance_account_id
  for update;
  v_exists := found;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'set_cost_allocation_rule',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'finance_account_id', p_finance_account_id,
        'allocatable', p_allocatable,
        'settlement_principle', p_settlement_principle,
        'betrkv_position', p_betrkv_position,
        'under_heating_cost_regulation', p_under_heating_cost_regulation,
        'note', p_note,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'cost_allocation_rule'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_exists and (p_expected_version is null or p_expected_version < 1) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An expected version is required to change an existing rule',
        'field', 'expectedVersion'
      )
    );
  end if;

  if not v_exists and p_expected_version is not null then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'This account has no rule yet, so there is no version to expect',
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
        'message', 'Cost allocation rule version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.allocation_rule_snapshot(v_old)
      )
    );
  end if;

  if v_exists then
    update public.finance_account_allocation_rules as rule
    set
      allocatable = p_allocatable,
      betrkv_position = nullif(btrim(coalesce(p_betrkv_position, '')), ''),
      under_heating_cost_regulation =
        coalesce(p_under_heating_cost_regulation, false),
      settlement_principle = v_principle,
      note = nullif(btrim(coalesce(p_note, '')), ''),
      updated_at = now(),
      updated_by = v_actor_id,
      version = rule.version + 1
    where rule.workspace_id = p_workspace_id
      and rule.finance_account_id = p_finance_account_id
    returning * into v_new;
  else
    insert into public.finance_account_allocation_rules (
      finance_account_id, workspace_id, allocatable, betrkv_position,
      under_heating_cost_regulation, settlement_principle, note,
      created_by, updated_by
    ) values (
      p_finance_account_id, p_workspace_id, p_allocatable,
      nullif(btrim(coalesce(p_betrkv_position, '')), ''),
      coalesce(p_under_heating_cost_regulation, false), v_principle,
      nullif(btrim(coalesce(p_note, '')), ''),
      v_actor_id, v_actor_id
    )
    returning * into v_new;
  end if;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_exists
      then 'cost_allocation_rule.update' else 'cost_allocation_rule.create' end,
    'cost_allocation_rule', p_finance_account_id,
    case when v_exists then private.allocation_rule_snapshot(v_old) else null end,
    private.allocation_rule_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.allocation_rule_snapshot(v_new)
  );
end;
$function$;
