begin;

create extension if not exists pgtap with schema extensions;

-- COST-POOLS-ALLOCATION-KEYS-01 (P-2b).
--
-- Four assertions carry this package, and each one exists because the legacy
-- implementation got exactly that thing wrong.
--
-- **A basis with no store refuses to compute.** `persons`,
-- `co_ownership_share` and `fixed_share` have no data anywhere in this schema
-- and `consumption` has no meters until P-4. The legacy code fell through to
-- area and produced a number. Here the read says `resolvable: false` with a
-- reason, and the count of unresolvable keys is reported alongside the keys --
-- so a settlement run cannot mistake "no basis" for "basis of zero".
--
-- **An incomplete basis is unresolvable, not approximate.** One unit without
-- `area_sqm` makes the denominator wrong for every *other* unit, because the
-- missing unit's share is silently redistributed over them. That is asserted
-- positively and negatively: complete units resolve with the right total,
-- one missing value flips it.
--
-- **Two keys may not cover the same day.** Including when both leave the cost
-- type open: `null = null` is not true, so the exclusion constraint coalesces
-- the nullable columns, and the test drives exactly that pair. Adjacency is
-- asserted too -- a key ending on the 31st and one starting on the 1st must be
-- accepted, which is what the half-open generated range buys.
--
-- **An explanation is mandatory.** DEC-014 model consequence 2: the
-- "Verteilerschluessel mit Erlaeuterung" is one of the four Mindestangaben
-- whose absence makes an operating-cost statement formally void. It is
-- refused, not defaulted.
--
-- The P-2a correction is asserted here rather than in 055, because it is this
-- migration that makes it. Only half of it was a defect: the DELETE on the
-- receipt was, because a deleted receipt cannot compare request hashes and a
-- different command reusing the id would have been accepted as a fresh
-- attempt. The gate was not -- `private.party_command_gate` checks AAL2 itself
-- and says so -- and the assertion below pins wording rather than claiming a
-- hole was closed.

select plan(74);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'cost_pools', 'the cost pool table exists');
select has_table('public', 'allocation_keys', 'the allocation key table exists');

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname in ('cost_pools', 'allocation_keys')),
  'both with row level security enabled and forced');

select is(
  (select count(*)::integer from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname in ('cost_pools', 'allocation_keys')),
  2,
  'exactly two policies across both tables, and both SELECT ones -- writes go '
  'through the commands');

select ok(
  (select count(*) = 0 from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname in ('cost_pools', 'allocation_keys')
     and policy.polcmd <> 'r'),
  'and no DML policy on either table');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('72200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'pool-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('72200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'pool-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('72100000-0000-0000-0000-000000000001', 'pools', 'Pools');
select private.seed_workspace_role_catalog('72100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '72100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('72200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  -- analyst holds finance.read and not finance.manage: the actor who may see
  -- how costs are distributed and may not decide it.
  ('72200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '72100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('72500000-0000-0000-0000-000000000001', '72100000-0000-0000-0000-000000000001',
   'Poolhaus A', 'Poolweg 1', '10115', 'Berlin', 'de', 'residential', 2,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001'),
  ('72500000-0000-0000-0000-000000000002', '72100000-0000-0000-0000-000000000001',
   'Poolhaus B', 'Poolweg 2', '10115', 'Berlin', 'de', 'residential', 2,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001');

-- A is complete; B has one unit whose area was never entered. That single null
-- is the whole point of the incompleteness assertion.
insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm,
  created_by, updated_by
) values
  ('72600000-0000-0000-0000-000000000001', '72100000-0000-0000-0000-000000000001',
   '72500000-0000-0000-0000-000000000001', 'A-01', 'occupied', 50,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001'),
  ('72600000-0000-0000-0000-000000000002', '72100000-0000-0000-0000-000000000001',
   '72500000-0000-0000-0000-000000000001', 'A-02', 'occupied', 30,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001'),
  ('72600000-0000-0000-0000-000000000003', '72100000-0000-0000-0000-000000000001',
   '72500000-0000-0000-0000-000000000002', 'B-01', 'occupied', 40,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001'),
  ('72600000-0000-0000-0000-000000000004', '72100000-0000-0000-0000-000000000001',
   '72500000-0000-0000-0000-000000000002', 'B-02', 'occupied', null,
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('72300000-0000-0000-0000-000000000001', '72100000-0000-0000-0000-000000000001',
   '4210', 'Heizkosten', 'expense',
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001'),
  ('72300000-0000-0000-0000-000000000002', '72100000-0000-0000-0000-000000000001',
   '4220', 'Hausreinigung', 'expense',
   '72200000-0000-0000-0000-000000000001', '72200000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_user(
  p_user uuid,
  p_statement text,
  p_aal text default 'aal2'
)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated',
                      'aal', p_aal)::text,
    true
  );
  execute p_statement into v;
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

create or replace function pg_temp.pool(
  p_key text,
  p_name text,
  p_scope text,
  p_property uuid default null,
  p_label text default null,
  p_id uuid default null,
  p_version bigint default null,
  p_active boolean default true,
  p_unit uuid default null,
  p_user uuid default '72200000-0000-0000-0000-000000000001',
  p_mutation uuid default gen_random_uuid(),
  p_correlation uuid default gen_random_uuid(),
  p_aal text default 'aal2'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.upsert_cost_pool(
        %L::uuid, %L, %L, %L, %L::uuid, %L::uuid, %s, %s, %s, %s, %s, null,
        %L::boolean, 'Test')$q$,
      '72100000-0000-0000-0000-000000000001', p_key, p_name, p_scope,
      p_mutation, p_correlation,
      case when p_id is null then 'null' else quote_literal(p_id) || '::uuid' end,
      case when p_version is null then 'null'
           else p_version::text || '::bigint' end,
      case when p_property is null then 'null'
           else quote_literal(p_property) || '::uuid' end,
      case when p_unit is null then 'null'
           else quote_literal(p_unit) || '::uuid' end,
      case when p_label is null then 'null' else quote_literal(p_label) end,
      p_active
    ),
    p_aal
  );
$$;

create or replace function pg_temp.key(
  p_basis text,
  p_from date,
  p_to date default null,
  p_property uuid default '72500000-0000-0000-0000-000000000001',
  p_account uuid default null,
  p_pool uuid default null,
  p_explanation text default 'Nach Wohnflaeche, § 556a Abs. 1 BGB',
  p_id uuid default null,
  p_version bigint default null,
  p_user uuid default '72200000-0000-0000-0000-000000000001',
  p_mutation uuid default gen_random_uuid(),
  p_correlation uuid default gen_random_uuid()
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.upsert_allocation_key(
        %L::uuid, %L::uuid, %L, %s, %L::date, %L::uuid, %L::uuid, %s, %s, %s,
        %s, %s, null, 'Test')$q$,
      '72100000-0000-0000-0000-000000000001', p_property, p_basis,
      case when p_explanation is null then 'null'
           else quote_literal(p_explanation) end,
      p_from, p_mutation, p_correlation,
      case when p_id is null then 'null' else quote_literal(p_id) || '::uuid' end,
      case when p_version is null then 'null'
           else p_version::text || '::bigint' end,
      case when p_account is null then 'null'
           else quote_literal(p_account) || '::uuid' end,
      case when p_pool is null then 'null'
           else quote_literal(p_pool) || '::uuid' end,
      case when p_to is null then 'null' else quote_literal(p_to) || '::date' end
    )
  );
$$;

create or replace function pg_temp.keys_as_of(
  p_as_of date default null,
  p_property uuid default null,
  p_user uuid default '72200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.allocation_keys_as_of(%L::uuid, %s, %s, null)$q$,
      '72100000-0000-0000-0000-000000000001',
      case when p_as_of is null then 'null'
           else quote_literal(p_as_of) || '::date' end,
      case when p_property is null then 'null'
           else quote_literal(p_property) || '::uuid' end
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Scope: what a pool is allowed to point at
-- ---------------------------------------------------------------------------

select is(
  pg_temp.pool('betrieb', 'Betriebskosten', 'portfolio') -> 'ok',
  'true'::jsonb,
  'a portfolio pool names no property and is accepted');

select is(
  pg_temp.pool('betrieb2', 'Betriebskosten', 'portfolio',
               '72500000-0000-0000-0000-000000000001')
    -> 'error' ->> 'field',
  'propertyId',
  'a portfolio pool that names a property is refused: the scope is the '
  'workspace');

select is(
  pg_temp.pool('heizung', 'Heizung', 'property') -> 'error' ->> 'field',
  'propertyId',
  'and every other scope needs one');

select is(
  pg_temp.pool('heizung', 'Heizung', 'property',
               '72500000-0000-0000-0000-000000000001') -> 'ok',
  'true'::jsonb,
  'a property pool with its property is accepted');

-- The three scopes with no entity. Kept in the vocabulary because the
-- programme enumerates them; the label is their only identity, so it is
-- required -- and refused where a real entity already supplies one.
select is(
  pg_temp.pool('aufgang', 'Aufgang', 'entrance',
               '72500000-0000-0000-0000-000000000001')
    -> 'error' ->> 'field',
  'scopeLabel',
  'an entrance pool without a label is refused: nothing else identifies it');

select is(
  pg_temp.pool('aufgang', 'Aufgang', 'entrance',
               '72500000-0000-0000-0000-000000000001', 'Aufgang West') -> 'ok',
  'true'::jsonb,
  'with a label it is accepted');

select is(
  pg_temp.pool('heizung2', 'Heizung', 'property',
               '72500000-0000-0000-0000-000000000001', 'Haus A')
    -> 'error' ->> 'field',
  'scopeLabel',
  'and a property pool takes no label: the property already names it');

select is(
  pg_temp.pool('betrieb', 'Zweiter', 'property',
               '72500000-0000-0000-0000-000000000001') -> 'ok',
  'true'::jsonb,
  'the portfolio key may be reused under a property -- different scopes, '
  'different uniqueness');

select is(
  pg_temp.pool('heizung', 'Nochmal', 'property',
               '72500000-0000-0000-0000-000000000001')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'but not twice under the same property');

-- The partial-index assertion. A single unique index over the nullable
-- property_id would accept this, because `null = null` is not true.
select is(
  pg_temp.pool('betrieb', 'Portfolio nochmal', 'portfolio')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'and not twice at portfolio scope, where the property is null');

-- A unit pool with no unit had no identity at all: this table has no other
-- column naming one, and a label is refused for that scope -- so two such
-- pools under one property were indistinguishable, while the read still
-- called them automatically distributable.
select is(
  pg_temp.pool('whg', 'Wohnung', 'unit',
               '72500000-0000-0000-0000-000000000001')
    -> 'error' ->> 'field',
  'unitId',
  'a unit pool without a unit is refused');

select is(
  pg_temp.pool('whg', 'Wohnung', 'unit',
               '72500000-0000-0000-0000-000000000001',
               p_unit => '72600000-0000-0000-0000-000000000001') -> 'ok',
  'true'::jsonb,
  'and is accepted once it names one');

select is(
  pg_temp.pool('whg-fremd', 'Fremde Wohnung', 'unit',
               '72500000-0000-0000-0000-000000000001',
               p_unit => '72600000-0000-0000-0000-000000000003')
    -> 'error' ->> 'code',
  'not_found',
  'a unit from another property is refused: the pool would carry this '
  'property''s name and point at that one''s unit');

select is(
  pg_temp.pool('betrieb-unit', 'Portfolio mit Einheit', 'portfolio',
               p_unit => '72600000-0000-0000-0000-000000000001')
    -> 'error' ->> 'field',
  'unitId',
  'and only a unit pool names a unit');

-- The label is called the only identity these three scopes have. Two pools
-- sharing one under the same property are two pools claiming one physical
-- entrance, and the costs assigned to it would split across both.
select is(
  pg_temp.pool('aufgang-b', 'Aufgang', 'entrance',
               '72500000-0000-0000-0000-000000000001', 'Aufgang West')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'a second entrance pool with the same label is refused');

select is(
  pg_temp.pool('aufgang-b', 'Aufgang', 'entrance',
               '72500000-0000-0000-0000-000000000001', 'Aufgang Ost') -> 'ok',
  'true'::jsonb,
  'a different label is accepted');

select is(
  pg_temp.pool('unfug', 'Unfug', 'district',
               '72500000-0000-0000-0000-000000000001')
    -> 'error' ->> 'field',
  'scope',
  'an unknown scope is named as such rather than raising');

-- ---------------------------------------------------------------------------
-- The read reports what it cannot resolve
-- ---------------------------------------------------------------------------

select is(
  (select entry ->> 'scope_resolvable'
   from jsonb_array_elements(
     pg_temp.as_user('72200000-0000-0000-0000-000000000001',
       $q$select public.workspace_cost_pools(
         '72100000-0000-0000-0000-000000000001'::uuid, null, false)$q$)
     -> 'entity' -> 'pools') as entry
   where entry ->> 'pool_key' = 'aufgang'),
  'false',
  'the entrance pool is reported as not automatically resolvable');

select is(
  (select entry ->> 'scope_unresolvable_reason'
   from jsonb_array_elements(
     pg_temp.as_user('72200000-0000-0000-0000-000000000001',
       $q$select public.workspace_cost_pools(
         '72100000-0000-0000-0000-000000000001'::uuid, null, false)$q$)
     -> 'entity' -> 'pools') as entry
   where entry ->> 'pool_key' = 'aufgang'),
  'no_entity',
  'with the reason named');

-- The positive counterpart: without it the two assertions above would also
-- pass if the read returned nothing at all.
select is(
  (select entry ->> 'scope_resolvable'
   from jsonb_array_elements(
     pg_temp.as_user('72200000-0000-0000-0000-000000000001',
       $q$select public.workspace_cost_pools(
         '72100000-0000-0000-0000-000000000001'::uuid, null, false)$q$)
     -> 'entity' -> 'pools') as entry
   where entry ->> 'pool_key' = 'heizung'
     and entry ->> 'scope' = 'property'),
  'true',
  'and the property pool is resolvable');

-- A portfolio pool covers every property by its own definition, and its
-- `property_id` is null -- so a plain `property_id = p` predicate dropped it
-- from exactly the read it applies to, because `null = p` is not true.
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.as_user('72200000-0000-0000-0000-000000000001',
       $q$select public.workspace_cost_pools(
         '72100000-0000-0000-0000-000000000001'::uuid,
         '72500000-0000-0000-0000-000000000001'::uuid, false)$q$)
     -> 'entity' -> 'pools') as entry
   where entry ->> 'pool_key' = 'betrieb'
     and entry ->> 'scope' = 'portfolio'),
  1,
  'the per-property read includes the portfolio pool that covers it');

select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.as_user('72200000-0000-0000-0000-000000000001',
       $q$select public.workspace_cost_pools(
         '72100000-0000-0000-0000-000000000001'::uuid,
         '72500000-0000-0000-0000-000000000002'::uuid, false)$q$)
     -> 'entity' -> 'pools') as entry
   where entry ->> 'property_id' = '72500000-0000-0000-0000-000000000001'),
  0,
  'and no pool belonging to the other property -- paired with the case above '
  'so neither passes by the filter being absent');

-- The command's own answer carries it too, not only the list read.
select is(
  pg_temp.pool('snapshot', 'Snapshot', 'entrance',
               '72500000-0000-0000-0000-000000000001', 'Aufgang Sued')
    -> 'entity' ->> 'scope_resolvable',
  'false',
  'the write result states resolvability as well, so a caller that only sees '
  'write results need not infer it from the scope');

-- ---------------------------------------------------------------------------
-- Allocation keys: the mandatory explanation
-- ---------------------------------------------------------------------------

select is(
  pg_temp.key('area_sqm', date '2026-01-01', p_explanation => null)
    -> 'error' ->> 'field',
  'explanation',
  'a key without an explanation is refused: it is one of the four '
  'Mindestangaben a statement is formally void without (DEC-014)');

select is(
  pg_temp.key('area_sqm', date '2026-01-01',
              p_account => '72300000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'with one it is accepted');

select is(
  pg_temp.key('nach_gefuehl', date '2026-01-01') -> 'error' ->> 'field',
  'basis',
  'an unknown basis is named rather than raising');

-- ---------------------------------------------------------------------------
-- No two keys may cover the same day
-- ---------------------------------------------------------------------------

select is(
  pg_temp.key('unit_count', date '2026-06-01',
              p_account => '72300000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'a second open-ended key for the same property and cost type overlaps the '
  'first');

select is(
  pg_temp.key('unit_count', date '2026-06-01', date '2027-12-31',
              p_account => '72300000-0000-0000-0000-000000000001') -> 'ok',
  'true'::jsonb,
  'the same period under a different cost type does not');

-- Both leave the cost type open. The exclusion constraint coalesces the null
-- to the nil UUID; without that these two would both be accepted, which is
-- precisely the pair the constraint exists to reject.
select is(
  pg_temp.key('area_sqm', date '2026-01-01', date '2026-12-31',
              p_property => '72500000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'a key that leaves the cost type open is accepted');

select is(
  pg_temp.key('unit_count', date '2026-06-01',
              p_property => '72500000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'and a second one overlapping it is refused, though both cost types are '
  'null and null = null is not true');

-- Adjacency. Generated half-open internally, inclusive at the edge: a key
-- ending on the 31st and one starting on the 1st are adjacent, not
-- overlapping.
select is(
  pg_temp.key('unit_count', date '2027-01-01',
              p_property => '72500000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'a key starting the day after another ends is accepted: the range is '
  'half-open internally and inclusive at the API edge');

select is(
  pg_temp.key('area_sqm', date '2026-12-31',
              p_property => '72500000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'and one starting on the last covered day is not');

select is(
  pg_temp.key('area_sqm', date '2026-06-01', date '2026-01-01')
    -> 'error' ->> 'field',
  'validTo',
  'an end before the start is refused');

-- ---------------------------------------------------------------------------
-- The pool a key may name
-- ---------------------------------------------------------------------------
--
-- The composite foreign key holds the workspace boundary and nothing else, and
-- the exclusion constraint keys on the pool rather than checking it. Without
-- these two rules a key for property A could name property B's pool, and the
-- read would render B's pool under A's name over A's units.

select is(
  pg_temp.key('unit_count', date '2030-01-01',
              p_pool => (select id from public.cost_pools
                         where pool_key = 'heizung' and scope = 'property'),
              p_account => '72300000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'a key may name a pool of its own property');

select is(
  pg_temp.key('unit_count', date '2030-01-01',
              p_property => '72500000-0000-0000-0000-000000000002',
              p_pool => (select id from public.cost_pools
                         where pool_key = 'heizung' and scope = 'property'),
              p_account => '72300000-0000-0000-0000-000000000002')
    -> 'error' ->> 'field',
  'costPoolId',
  'and not one belonging to a different property');

select is(
  pg_temp.key('unit_count', date '2031-01-01',
              p_pool => (select id from public.cost_pools
                         where pool_key = 'betrieb' and scope = 'portfolio'),
              p_account => '72300000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'a portfolio pool belongs to no single property and is accepted for any');

-- `is_active` is enforced here or nowhere: a flag that is written and filtered
-- in one read but checked in no command is a status without a lifecycle.
select is(
  pg_temp.pool('stillgelegt', 'Stillgelegt', 'property',
               '72500000-0000-0000-0000-000000000001',
               p_active => false) -> 'entity' ->> 'is_active',
  'false',
  'a pool can be deactivated');

select is(
  pg_temp.key('unit_count', date '2032-01-01',
              p_pool => (select id from public.cost_pools
                         where pool_key = 'stillgelegt'),
              p_account => '72300000-0000-0000-0000-000000000002')
    -> 'error' ->> 'field',
  'costPoolId',
  'and no new key may name it afterwards');

-- ---------------------------------------------------------------------------
-- What the basis actually resolves to
-- ---------------------------------------------------------------------------

select is(
  (select entry -> 'basis_resolution' ->> 'total'
   from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-03-01',
       '72500000-0000-0000-0000-000000000001') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'area_sqm'),
  '80',
  'area resolves to the sum of units.area_sqm -- 50 + 30 -- for the property '
  'whose units are all recorded');

select is(
  (select entry -> 'basis_resolution' ->> 'resolvable'
   from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-03-01',
       '72500000-0000-0000-0000-000000000001') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'area_sqm'),
  'true',
  'and is resolvable');

select is(
  (select entry -> 'basis_resolution' ->> 'reason'
   from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-03-01',
       '72500000-0000-0000-0000-000000000002') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'area_sqm'),
  'incomplete_basis',
  'one unit without an area makes the basis unresolvable, not approximate: '
  'that unit''s share would be silently redistributed over the others');

select is(
  (select entry -> 'basis_resolution' ->> 'units_without_value'
   from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-03-01',
       '72500000-0000-0000-0000-000000000002') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'area_sqm'),
  '1',
  'and the read says how many units are missing it');

select is(
  (select entry -> 'basis_resolution' ->> 'total'
   from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-06-15',
       '72500000-0000-0000-0000-000000000001') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'unit_count'),
  '2',
  'a unit count is count(*) over the unit records');

-- The four with no store. Named individually in the function so a new enum
-- value is a visible omission rather than a fall-through to area -- which is
-- exactly how the legacy code turned "Personen" into square metres.
select is(
  (private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', 'persons') ->> 'reason'),
  'no_basis_store',
  'persons resolves to nothing: no occupancy figure is recorded anywhere');

select is(
  (private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', 'co_ownership_share')
     ->> 'reason'),
  'no_basis_store',
  'nor does a co-ownership share');

select is(
  (private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', 'fixed_share') ->> 'reason'),
  'no_basis_store',
  'nor a fixed share');

select is(
  (private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', 'consumption') ->> 'reason'),
  'no_meters',
  'and consumption says meters, because P-4 is where they arrive');

select is(
  (private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', 'direct') ->> 'resolvable'),
  'true',
  'a direct assignment is resolvable and reports no total: there is nothing '
  'to divide by');

-- The first version of this function let `area_sqm` be the unguarded
-- fall-through, so a value added to the enum later would have been answered
-- with the area sum -- the legacy "Personen wird zu Flaeche" failure, rebuilt
-- by the code written to prevent it. A synthetic eighth value cannot be tested
-- here (`alter type ... add value` may not be used in the transaction that
-- adds it), so the guard is asserted the other way round: exactly one of the
-- seven reports the area figure, and every other one names itself.
select is(
  (select count(*)::integer
   from unnest(enum_range(null::public.allocation_basis)) as basis
   where private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', basis
   ) ->> 'detail' like 'The sum of units.area_sqm%'),
  1,
  'exactly one basis answers with the area figure -- area is a named branch '
  'now, not whatever is left at the end of the function');

select is(
  (select count(*)::integer
   from unnest(enum_range(null::public.allocation_basis)) as basis
   where private.allocation_basis_resolution(
     '72100000-0000-0000-0000-000000000001',
     '72500000-0000-0000-0000-000000000001', basis
   ) ->> 'detail' is null),
  0,
  'and every value in the vocabulary says something about itself');

-- ---------------------------------------------------------------------------
-- The read counts what a settlement run could not use
-- ---------------------------------------------------------------------------

select is(
  pg_temp.key('persons', date '2028-01-01',
              p_account => '72300000-0000-0000-0000-000000000001') -> 'ok',
  'true'::jsonb,
  'a key on a basis with no store may still be recorded -- the intent is real '
  'even where the data is not');

select is(
  pg_temp.keys_as_of(date '2028-06-01') -> 'entity' ->> 'unresolvable_count',
  '1',
  'and the read counts it as unresolvable');

select is(
  pg_temp.keys_as_of(date '2028-06-01') -> 'entity' ->> 'resolvable_count',
  '2',
  'while the two keys in force alongside it, on bases this schema does store, '
  'stay resolvable -- the count separates them rather than condemning the '
  'whole date');

-- One property has every area recorded and the other does not, so the same
-- basis resolves for one and not the other. The count is per key, not per
-- basis: a settlement run needs to know which key it cannot use.
select is(
  pg_temp.keys_as_of(date '2026-03-01') -> 'entity' ->> 'resolvable_count',
  '1',
  'and in March, where two area keys are in force, only the property whose '
  'units all carry an area resolves');

-- Time. The key starting in 2028 is not in force in 2026.
select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.keys_as_of(date '2026-03-01') -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'persons'),
  0,
  'a key that starts in 2028 is absent from a 2026 read');

-- ---------------------------------------------------------------------------
-- Permission and assurance level
-- ---------------------------------------------------------------------------

select is(
  pg_temp.keys_as_of(date '2026-03-01',
    p_user => '72200000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'the analyst holds finance.read and may see how costs are distributed');

select is(
  pg_temp.pool('analyst', 'Analyst', 'portfolio',
               p_user => '72200000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'forbidden',
  'and may not decide it: that is finance.manage');

select is(
  pg_temp.pool('aal1', 'AAL1', 'portfolio', p_aal => 'aal1')
    -> 'error' ->> 'message',
  'AAL2 is required for finance mutations',
  'an aal1 caller is told the assurance level is the problem, not the '
  'permission (DEC-025)');

-- ---------------------------------------------------------------------------
-- Concurrency and idempotency
-- ---------------------------------------------------------------------------

-- A version with no id is a caller who thinks they are editing. Refused
-- rather than quietly creating a second pool beside the one they meant to
-- change, which stays invisible until somebody wonders why there are two.
select is(
  pg_temp.pool('versionlos', 'Ohne Id', 'portfolio', p_version => 3)
    -> 'error' ->> 'field',
  'expectedVersion',
  'a version without a pool id is refused');

select is(
  pg_temp.key('area_sqm', date '2029-01-01', p_version => 3)
    -> 'error' ->> 'field',
  'expectedVersion',
  'and a version without a key id');

select is(
  pg_temp.pool('heizung', 'Heizung neu', 'property',
               '72500000-0000-0000-0000-000000000001',
               p_id => (select id from public.cost_pools
                        where pool_key = 'heizung' and scope = 'property'),
               p_version => 99,
               p_mutation => '72700000-0000-0000-0000-000000000002',
               p_correlation => '72800000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'version_conflict',
  'a stale version is refused');

select is(
  pg_temp.pool('heizung', 'Heizung neu', 'property',
               '72500000-0000-0000-0000-000000000001',
               p_id => (select id from public.cost_pools
                        where pool_key = 'heizung' and scope = 'property'),
               p_version => 1) -> 'entity' ->> 'name',
  'Heizung neu',
  'and the current one is accepted');

-- Idempotency: same id, same arguments, replayed. The receipt is what makes
-- this an answer rather than a second row.
select is(
  pg_temp.pool('replay', 'Replay', 'portfolio',
               p_mutation => '72700000-0000-0000-0000-000000000001',
               p_correlation => '72800000-0000-0000-0000-000000000001')
    -> 'entity' ->> 'pool_key',
  'replay',
  'a create runs');

select is(
  pg_temp.pool('replay', 'Replay', 'portfolio',
               p_mutation => '72700000-0000-0000-0000-000000000001',
               p_correlation => '72800000-0000-0000-0000-000000000001')
    -> 'entity' ->> 'pool_key',
  'replay',
  'and replaying it with the same mutation id answers with the same entity, '
  'rather than refusing the duplicate key it would otherwise create');

select is(
  (select count(*)::integer from public.cost_pools
   where pool_key = 'replay'),
  1,
  'leaving exactly one pool');

-- The receipt is marked failed, not deleted. A deleted receipt cannot compare
-- request hashes, so a different command reusing the id would be accepted as a
-- fresh attempt instead of refused.
select is(
  (select receipt.status::text from public.mutation_receipts as receipt
   where receipt.mutation_id = '72700000-0000-0000-0000-000000000002'),
  'failed',
  'a command refused after its claim leaves the receipt failed, not deleted');

-- ---------------------------------------------------------------------------
-- The P-2a correction
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user('72200000-0000-0000-0000-000000000001',
    format(
      $q$select public.set_cost_allocation_rule(
        %L::uuid, %L::uuid, true, %L::uuid, %L::uuid, null, 'performance',
        null, false, null, 'Test')$q$,
      '72100000-0000-0000-0000-000000000001',
      '72300000-0000-0000-0000-000000000001',
      gen_random_uuid(), gen_random_uuid()),
    'aal1')
    -> 'error' ->> 'message',
  'AAL2 is required for finance mutations',
  'set_cost_allocation_rule now runs on the finance command plumbing, and an '
  'aal1 caller is refused at the gate. The party gate it shipped on refused '
  'aal1 too -- it says "AAL2 is required for party mutations" -- so this '
  'assertion pins the wording, not a hole. The defect that was real is the '
  'receipt handling, asserted above');

select is(
  pg_temp.as_user('72200000-0000-0000-0000-000000000001',
    format(
      $q$select public.set_cost_allocation_rule(
        %L::uuid, %L::uuid, true, %L::uuid, %L::uuid, null, 'performance',
        null, false, null, 'Test')$q$,
      '72100000-0000-0000-0000-000000000001',
      '72300000-0000-0000-0000-000000000001',
      '72700000-0000-0000-0000-000000000003',
      '72800000-0000-0000-0000-000000000003'))
    -> 'ok',
  'true'::jsonb,
  'and an aal2 caller still writes the rule');

select is(
  (select receipt.status::text from public.mutation_receipts as receipt
   where receipt.mutation_id = '72700000-0000-0000-0000-000000000003'),
  'succeeded',
  'with a receipt recording it');

select * from finish();
rollback;
