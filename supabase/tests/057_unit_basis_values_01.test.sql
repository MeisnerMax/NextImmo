begin;

create extension if not exists pgtap with schema extensions;

-- UNIT-BASIS-VALUES-01 (P-2c).
--
-- Four assertions carry this package.
--
-- **Two conventions do not add up.** If one unit's person count is a Stichtag
-- figure and its neighbour's is a Personenmonate figure, their sum is not a
-- denominator -- it is two different measurements added together. `DEC-014`
-- decides no counting rule for any of these three bases and lists none as
-- contested, so the convention travels with the figure and the resolution
-- refuses a mixed set by name rather than summing anyway.
--
-- **A partial set is unresolvable, not approximate.** Values on three of four
-- units make the denominator wrong for the three that have one, because the
-- fourth's share is silently redistributed over them. Asserted positively and
-- negatively: a complete set resolves with the right total, removing one
-- value flips it.
--
-- **Nothing recorded still reads as `no_basis_store`.** An installation that
-- has entered no values must answer exactly as it did before this package
-- existed -- the basis has no data, rather than incomplete data -- or every
-- workspace would wake up to a new kind of failure it did not cause.
--
-- **The fitness test the programme states.** P-5 needs the three branches that
-- answered `no_basis_store` to stop answering it once values exist. That is
-- asserted through the allocation-key read, not only through the private
-- helper, because the read is what a settlement run will actually call.

select plan(49);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'unit_basis_values', 'the basis store exists');

select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname = 'unit_basis_values'),
  'with row level security enabled and forced');

select is(
  (select count(*)::integer from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'unit_basis_values'),
  1,
  'exactly one policy, and a SELECT one -- writes go through the command');

select ok(
  (select count(*) = 0 from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'unit_basis_values' and policy.polcmd <> 'r'),
  'and no DML policy');

-- The store holds exactly the three bases with no other home. Area lives on
-- the unit and a unit count is counted; a second copy here could only
-- disagree with them.
select throws_ok(
  $$insert into public.unit_basis_values (
      workspace_id, unit_id, basis, value, convention, valid_from,
      created_by, updated_by
    ) values (
      '73100000-0000-0000-0000-000000000001',
      '73600000-0000-0000-0000-000000000001', 'area_sqm', 10, 'x',
      date '2026-01-01',
      '73200000-0000-0000-0000-000000000001',
      '73200000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'an area figure cannot be parked here, and the CHECK is what stops it -- '
  'not only the command');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('73200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'basis-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('73200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'basis-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('73100000-0000-0000-0000-000000000001', 'basis', 'Basis');
select private.seed_workspace_role_catalog('73100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '73100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('73200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('73200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '73100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('73500000-0000-0000-0000-000000000001', '73100000-0000-0000-0000-000000000001',
   'Basishaus A', 'Basisweg 1', '10115', 'Berlin', 'de', 'residential', 2,
   '73200000-0000-0000-0000-000000000001', '73200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, area_sqm,
  created_by, updated_by
) values
  ('73600000-0000-0000-0000-000000000001', '73100000-0000-0000-0000-000000000001',
   '73500000-0000-0000-0000-000000000001', 'A-01', 'occupied', 50,
   '73200000-0000-0000-0000-000000000001', '73200000-0000-0000-0000-000000000001'),
  ('73600000-0000-0000-0000-000000000002', '73100000-0000-0000-0000-000000000001',
   '73500000-0000-0000-0000-000000000001', 'A-02', 'occupied', 30,
   '73200000-0000-0000-0000-000000000001', '73200000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('73300000-0000-0000-0000-000000000001', '73100000-0000-0000-0000-000000000001',
   '4300', 'Muellabfuhr', 'expense',
   '73200000-0000-0000-0000-000000000001', '73200000-0000-0000-0000-000000000001');

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

create or replace function pg_temp.put(
  p_unit uuid,
  p_value numeric,
  p_convention text default 'Stichtag 1. Januar, gemeldete Bewohner',
  p_basis text default 'persons',
  p_from date default '2026-01-01',
  p_to date default null,
  p_id uuid default null,
  p_version bigint default null,
  p_user uuid default '73200000-0000-0000-0000-000000000001',
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
      $q$select public.upsert_unit_basis_value(
        %L::uuid, %L::uuid, %L, %s, %s, %L::date, %L::uuid, %L::uuid, %s, %s,
        %s, null, 'Test')$q$,
      '73100000-0000-0000-0000-000000000001', p_unit, p_basis,
      case when p_value is null then 'null' else p_value::text end,
      case when p_convention is null then 'null'
           else quote_literal(p_convention) end,
      p_from, p_mutation, p_correlation,
      case when p_id is null then 'null' else quote_literal(p_id) || '::uuid' end,
      case when p_version is null then 'null'
           else p_version::text || '::bigint' end,
      case when p_to is null then 'null' else quote_literal(p_to) || '::date' end
    ),
    p_aal
  );
$$;

create or replace function pg_temp.resolve(
  p_basis text default 'persons',
  p_as_of date default '2026-06-01'
)
returns jsonb
language sql
as $$
  select private.allocation_basis_resolution(
    '73100000-0000-0000-0000-000000000001',
    '73500000-0000-0000-0000-000000000001',
    p_basis::public.allocation_basis,
    p_as_of
  );
$$;

-- ---------------------------------------------------------------------------
-- Nothing recorded reads exactly as it did before this package
-- ---------------------------------------------------------------------------

select is(
  pg_temp.resolve('persons') ->> 'reason',
  'no_basis_store',
  'with nothing recorded, persons still answers no_basis_store -- an '
  'installation that has entered nothing must not wake up to a new kind of '
  'failure it did not cause');

select is(
  pg_temp.resolve('co_ownership_share') ->> 'reason',
  'no_basis_store',
  'and so does a co-ownership share');

select is(
  pg_temp.resolve('fixed_share') ->> 'resolvable',
  'false',
  'and neither is resolvable');

select is(
  pg_temp.resolve('consumption') ->> 'reason',
  'no_meters',
  'consumption is untouched by this package and still names its own gap');

-- ---------------------------------------------------------------------------
-- What a value must state
-- ---------------------------------------------------------------------------

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 2, p_convention => null)
    -> 'error' ->> 'field',
  'convention',
  'a figure without its convention is refused: no counting rule is agreed for '
  'this basis, so the convention is part of the figure');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', -1)
    -> 'error' ->> 'field',
  'value',
  'a negative head count is refused');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 0) -> 'ok',
  'true'::jsonb,
  'zero is accepted: a unit with nobody in it is a real answer, and not the '
  'same as a unit nobody has recorded');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 3, p_basis => 'area_sqm')
    -> 'error' ->> 'field',
  'basis',
  'an area figure is refused by the command as well -- it lives on the unit '
  'and a second copy here could only disagree');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 3, p_basis => 'unit_count')
    -> 'error' ->> 'field',
  'basis',
  'and so is a unit count, which is counted rather than stored');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 3, p_version => 7)
    -> 'error' ->> 'field',
  'expectedVersion',
  'a version without a value id is refused rather than quietly creating a '
  'second row beside the one the caller meant to edit');

-- ---------------------------------------------------------------------------
-- One figure per unit, basis and day
-- ---------------------------------------------------------------------------

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 2,
              p_from => '2026-01-01', p_to => '2026-12-31')
    -> 'error' ->> 'code',
  'dependency_conflict',
  'a second open-ended value for the same unit and basis overlaps the first');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 2,
              p_basis => 'co_ownership_share') -> 'ok',
  'true'::jsonb,
  'a different basis for the same unit does not');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000002', 2) -> 'ok',
  'true'::jsonb,
  'nor the same basis for a different unit');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 5,
              p_from => '2026-06-01', p_to => '2026-01-01')
    -> 'error' ->> 'field',
  'validTo',
  'an end before the start is refused');

-- ---------------------------------------------------------------------------
-- A complete set, and what makes it incomplete
-- ---------------------------------------------------------------------------

select is(
  pg_temp.resolve('persons') ->> 'resolvable',
  'true',
  'with both units recorded under one convention, persons resolves');

select is(
  pg_temp.resolve('persons') ->> 'total',
  '2.000000',
  'and totals the recorded values -- 0 and 2');

select is(
  pg_temp.resolve('persons') ->> 'convention',
  'Stichtag 1. Januar, gemeldete Bewohner',
  'naming the one convention they were all measured under');

select is(
  pg_temp.resolve('persons') ->> 'units_without_value',
  '0',
  'with nothing missing');

-- The negative counterpart. Without it the four assertions above would also
-- pass if the resolution simply never looked at the second unit.
select is(
  pg_temp.resolve('co_ownership_share') ->> 'reason',
  'incomplete_basis',
  'one unit of two recorded makes the basis unresolvable, not approximate: '
  'the missing unit''s share would be redistributed over the rest');

select is(
  pg_temp.resolve('co_ownership_share') ->> 'units_without_value',
  '1',
  'and the resolution says how many are missing');

select is(
  pg_temp.resolve('co_ownership_share') ->> 'total',
  null,
  'and reports no total at all, so nothing downstream can divide by a '
  'partial denominator');

-- ---------------------------------------------------------------------------
-- Two conventions do not add up
-- ---------------------------------------------------------------------------

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000002', 3,
              p_convention => 'Personenmonate ueber den Abrechnungszeitraum',
              p_id => (select id from public.unit_basis_values
                       where unit_id = '73600000-0000-0000-0000-000000000002'
                         and basis = 'persons'),
              p_version => 1) -> 'ok',
  'true'::jsonb,
  'a unit may state a different convention -- the store records what the '
  'workspace says, it does not police the wording');

select is(
  pg_temp.resolve('persons') ->> 'reason',
  'mixed_conventions',
  'but the two cannot be summed: adding a Stichtag figure to a '
  'Personenmonate figure does not produce a denominator');

select is(
  pg_temp.resolve('persons') ->> 'total',
  null,
  'so no total is offered');

select is(
  pg_temp.resolve('persons') ->> 'convention_count',
  '2',
  'and the count of conventions is reported, so the fix is obvious');

-- Back to one convention, to prove the refusal above was the conventions and
-- not something else that happened to break at the same time.
select is(
  (select pg_temp.put('73600000-0000-0000-0000-000000000002', 3,
              p_id => (select id from public.unit_basis_values
                       where unit_id = '73600000-0000-0000-0000-000000000002'
                         and basis = 'persons'),
              p_version => 2) -> 'ok'),
  'true'::jsonb,
  'restoring the shared convention succeeds');

select is(
  pg_temp.resolve('persons') ->> 'resolvable',
  'true',
  'and the basis resolves again');

select is(
  pg_temp.resolve('persons') ->> 'total',
  '3.000000',
  'with the corrected total');

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------

select is(
  pg_temp.resolve('persons', date '2025-06-01') ->> 'reason',
  'no_basis_store',
  'a value that starts in 2026 does not answer for 2025: a settlement for a '
  'past year needs that year''s figures, not today''s');

-- ---------------------------------------------------------------------------
-- The fitness test the programme states
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user('73200000-0000-0000-0000-000000000001',
    format(
      $q$select public.upsert_allocation_key(
        %L::uuid, %L::uuid, 'persons', 'Nach Personenzahl', %L::date,
        %L::uuid, %L::uuid, null, null, %L::uuid, null, null, null, 'Test')$q$,
      '73100000-0000-0000-0000-000000000001',
      '73500000-0000-0000-0000-000000000001', '2026-01-01',
      gen_random_uuid(), gen_random_uuid(),
      '73300000-0000-0000-0000-000000000001'))
    -> 'ok',
  'true'::jsonb,
  'a key on the persons basis can be recorded');

select is(
  (select entry -> 'basis_resolution' ->> 'resolvable'
   from jsonb_array_elements(
     pg_temp.as_user('73200000-0000-0000-0000-000000000001',
       $q$select public.allocation_keys_as_of(
         '73100000-0000-0000-0000-000000000001'::uuid, '2026-06-01'::date,
         '73500000-0000-0000-0000-000000000001'::uuid, null)$q$)
     -> 'entity' -> 'keys') as entry
   where entry ->> 'basis' = 'persons'),
  'true',
  'and the allocation-key read now resolves it -- the branch that answered '
  'no_basis_store has stopped answering it, which is P-5''s stated '
  'precondition');

select is(
  pg_temp.as_user('73200000-0000-0000-0000-000000000001',
    $q$select public.allocation_keys_as_of(
      '73100000-0000-0000-0000-000000000001'::uuid, '2025-06-01'::date,
      '73500000-0000-0000-0000-000000000001'::uuid, null)$q$)
    -> 'entity' ->> 'total_count',
  '0',
  'while the same read for 2025 finds no key in force, so the resolution '
  'above is about the date and not about the key existing at all');

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.as_user('73200000-0000-0000-0000-000000000001',
       $q$select public.unit_basis_values_as_of(
         '73100000-0000-0000-0000-000000000001'::uuid,
         '73500000-0000-0000-0000-000000000001'::uuid,
         'co_ownership_share', '2026-06-01'::date)$q$)
     -> 'entity' -> 'units') as entry),
  2,
  'the read lists every unit of the property, including the one with no '
  'value -- a list of only the finished work makes the work look finished');

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.as_user('73200000-0000-0000-0000-000000000001',
       $q$select public.unit_basis_values_as_of(
         '73100000-0000-0000-0000-000000000001'::uuid,
         '73500000-0000-0000-0000-000000000001'::uuid,
         'co_ownership_share', '2026-06-01'::date)$q$)
     -> 'entity' -> 'units') as entry
   where entry -> 'value' = 'null'::jsonb),
  1,
  'and says which one is missing');

select is(
  pg_temp.as_user('73200000-0000-0000-0000-000000000001',
    $q$select public.unit_basis_values_as_of(
      '73100000-0000-0000-0000-000000000001'::uuid,
      '73500000-0000-0000-0000-000000000001'::uuid,
      'co_ownership_share', '2026-06-01'::date)$q$)
    -> 'entity' -> 'resolution' ->> 'reason',
  'incomplete_basis',
  'carrying the same verdict the allocation keys get, so the two surfaces '
  'cannot disagree about whether the basis is usable');

select is(
  pg_temp.as_user('73200000-0000-0000-0000-000000000001',
    $q$select public.unit_basis_values_as_of(
      '73100000-0000-0000-0000-000000000001'::uuid,
      '73500000-0000-0000-0000-000000000001'::uuid,
      'area_sqm', '2026-06-01'::date)$q$)
    -> 'error' ->> 'field',
  'basis',
  'and the read refuses a basis this store does not hold');

-- ---------------------------------------------------------------------------
-- Permission and assurance level
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_user('73200000-0000-0000-0000-000000000002',
    $q$select public.unit_basis_values_as_of(
      '73100000-0000-0000-0000-000000000001'::uuid,
      '73500000-0000-0000-0000-000000000001'::uuid,
      'persons', '2026-06-01'::date)$q$)
    -> 'ok',
  'true'::jsonb,
  'the analyst holds finance.read and may see the figures');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 4,
              p_basis => 'fixed_share',
              p_user => '73200000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'forbidden',
  'and may not enter them: that is finance.manage');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 4,
              p_basis => 'fixed_share', p_aal => 'aal1')
    -> 'error' ->> 'message',
  'AAL2 is required for finance mutations',
  'an aal1 caller is told the assurance level is the problem, not the '
  'permission (DEC-025)');

-- ---------------------------------------------------------------------------
-- Concurrency and idempotency
-- ---------------------------------------------------------------------------

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 9,
              p_id => (select id from public.unit_basis_values
                       where unit_id = '73600000-0000-0000-0000-000000000001'
                         and basis = 'persons'),
              p_version => 99,
              p_mutation => '73700000-0000-0000-0000-000000000002',
              p_correlation => '73800000-0000-0000-0000-000000000002')
    -> 'error' ->> 'code',
  'version_conflict',
  'a stale version is refused');

select is(
  (select receipt.status::text from public.mutation_receipts as receipt
   where receipt.mutation_id = '73700000-0000-0000-0000-000000000002'),
  'failed',
  'and the refused command leaves its receipt failed, not deleted -- a '
  'deleted receipt cannot compare request hashes on the retry');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 4,
              p_basis => 'fixed_share',
              p_mutation => '73700000-0000-0000-0000-000000000001',
              p_correlation => '73800000-0000-0000-0000-000000000001')
    -> 'entity' ->> 'value',
  '4.000000',
  'a create runs');

select is(
  pg_temp.put('73600000-0000-0000-0000-000000000001', 4,
              p_basis => 'fixed_share',
              p_mutation => '73700000-0000-0000-0000-000000000001',
              p_correlation => '73800000-0000-0000-0000-000000000001')
    -> 'entity' ->> 'value',
  '4.000000',
  'and replaying it with the same mutation id answers with the same entity '
  'rather than colliding with the row its own first call created');

select is(
  (select count(*)::integer from public.unit_basis_values
   where unit_id = '73600000-0000-0000-0000-000000000001'
     and basis = 'fixed_share'),
  1,
  'leaving exactly one value');

select * from finish();
rollback;
