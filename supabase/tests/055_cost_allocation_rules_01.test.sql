begin;

create extension if not exists pgtap with schema extensions;

-- COST-ALLOCATION-RULES-01 (P-2a).
--
-- Whether a cost may be passed on to tenants, and on which principle it is
-- settled. Two assertions carry the package.
--
-- **The HeizkostenV constraint is declarative, not a validation.** `DEC-014`
-- model consequence 3 requires "hartem Zwang auf das Leistungsprinzip für die
-- HeizkostenV-Positionen (BGH VIII ZR 156/11)". The command refuses it with a
-- message naming the case, *and* the CHECK refuses a direct insert -- because a
-- rule that only lives in a command is a rule a later command can be written
-- without. Both are asserted, and the second is the one that matters.
--
-- **An unclassified account is listed, not filtered away.** The read returns
-- every account with its rule or null, and counts what is still unclassified.
-- A surface that showed only the classified accounts would make the work look
-- finished, and this is the work that decides which costs a tenant pays.
--
-- `betrkv_position` is deliberately free text. The BetrKV § 2 catalogue is one
-- of the seven points `DEC-014` records as source-contradictory, and a
-- seventeen-value enum in a migration would encode a legal list nobody has
-- signed off.

select plan(33);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'finance_account_allocation_rules',
  'the rule satellite exists');

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname = 'finance_account_allocation_rules'),
  'with row level security enabled and forced');

select is(
  (select count(*)::integer from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'finance_account_allocation_rules'),
  1,
  'exactly one policy, and a SELECT one');

select ok(
  (select count(*) = 0 from information_schema.columns
   where table_schema = 'public' and table_name = 'finance_accounts'
     and column_name in (
       'allocatable', 'betrkv_position', 'settlement_principle'
     )),
  'and finance_accounts was not altered. A satellite is the same attribute '
  'relationally and reverts cleanly, which a column added to a live table '
  'does not');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('71200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alloc-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('71200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alloc-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('71100000-0000-0000-0000-000000000001', 'alloc', 'Alloc');
select private.seed_workspace_role_catalog('71100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '71100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('71200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  -- analyst holds finance.read but not finance.manage: the actor who may see
  -- which costs are apportionable and may not decide it.
  ('71200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '71100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('71300000-0000-0000-0000-000000000001', '71100000-0000-0000-0000-000000000001',
   '4210', 'Heizkosten', 'expense',
   '71200000-0000-0000-0000-000000000001', '71200000-0000-0000-0000-000000000001'),
  ('71300000-0000-0000-0000-000000000002', '71100000-0000-0000-0000-000000000001',
   '4220', 'Hausreinigung', 'expense',
   '71200000-0000-0000-0000-000000000001', '71200000-0000-0000-0000-000000000001'),
  ('71300000-0000-0000-0000-000000000003', '71100000-0000-0000-0000-000000000001',
   '4900', 'Instandhaltung', 'expense',
   '71200000-0000-0000-0000-000000000001', '71200000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_user(p_user uuid, p_statement text)
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
                      'aal', 'aal2')::text,
    true
  );
  execute p_statement into v;
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

create or replace function pg_temp.set_rule(
  p_account uuid,
  p_allocatable boolean,
  p_principle text default null,
  p_heating boolean default false,
  p_version bigint default null,
  p_betrkv text default null,
  p_user uuid default '71200000-0000-0000-0000-000000000001',
  p_mutation uuid default gen_random_uuid(),
  p_correlation uuid default gen_random_uuid()
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.set_cost_allocation_rule(
        %L::uuid, %L::uuid, %L::boolean, %L::uuid, %L::uuid, %s, %s, %s,
        %L::boolean, null, 'Test')$q$,
      '71100000-0000-0000-0000-000000000001', p_account, p_allocatable,
      p_mutation, p_correlation,
      case when p_version is null then 'null'
           else p_version::text || '::bigint' end,
      case when p_principle is null then 'null'
           else quote_literal(p_principle) end,
      case when p_betrkv is null then 'null' else quote_literal(p_betrkv) end,
      p_heating
    )
  );
$$;

create or replace function pg_temp.rules(
  p_user uuid default '71200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.cost_allocation_rules(%L::uuid, false)$q$,
      '71100000-0000-0000-0000-000000000001'
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- The HeizkostenV constraint
-- ---------------------------------------------------------------------------

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000001', true, 'outflow', true
  ) #>> '{error,message}',
  'A HeizkostenV position is settled on the performance principle '
  '(BGH VIII ZR 156/11)',
  'the command refuses the outflow principle for a HeizkostenV position, and '
  'names the case rather than a constraint');

select throws_ok(
  $$insert into public.finance_account_allocation_rules (
      finance_account_id, workspace_id, allocatable,
      under_heating_cost_regulation, settlement_principle,
      created_by, updated_by
    ) values (
      '71300000-0000-0000-0000-000000000001',
      '71100000-0000-0000-0000-000000000001', true, true, 'outflow',
      '71200000-0000-0000-0000-000000000001',
      '71200000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'and a direct insert is refused too. This is the assertion that matters: a '
  'rule living only in a command is a rule the next command can be written '
  'without');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000001', false, null, true
  ) #>> '{error,field}',
  'allocatable',
  'a HeizkostenV position that is not apportionable is a contradiction -- the '
  'regulation is about apportioning heating costs');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000001', true, 'performance', true,
    null, '§ 2 Nr. 4 BetrKV'
  ) #>> '{entity,settlement_principle}',
  'performance',
  'with the performance principle it is accepted');

select is(
  (select betrkv_position from public.finance_account_allocation_rules
   where finance_account_id = '71300000-0000-0000-0000-000000000001'),
  '§ 2 Nr. 4 BetrKV',
  'and the BetrKV position is stored as the workspace filed it. Free text '
  'because the catalogue is one of the seven contested sources DEC-014 names, '
  'and a seventeen-value enum in a migration would encode a list nobody '
  'signed off');

-- ---------------------------------------------------------------------------
-- Apportionable and the principle travel together
-- ---------------------------------------------------------------------------

select is(
  pg_temp.set_rule('71300000-0000-0000-0000-000000000002', true, null)
    #>> '{error,field}',
  'settlementPrinciple',
  'an apportionable cost needs a principle');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000003', false, 'outflow'
  ) #>> '{error,field}',
  'settlementPrinciple',
  'and one that is not apportionable has none. Storing a principle anyway '
  'would leave a setting that looks meaningful and decides nothing');

select is(
  pg_temp.set_rule('71300000-0000-0000-0000-000000000003', false)
    #>> '{entity,allocatable}',
  'false',
  'a non-apportionable cost is recorded as such');

select is(
  pg_temp.set_rule('71300000-0000-0000-0000-000000000002', true, 'outflow')
    #>> '{entity,settlement_principle}',
  'outflow',
  'and a cleaning cost may settle on the outflow principle -- the constraint '
  'is about the HeizkostenV, not about every cost');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000002', true, 'nach Gefuehl', false, 2
  ) #>> '{error,field}',
  'settlementPrinciple',
  'an unknown principle is refused rather than cast');

-- ---------------------------------------------------------------------------
-- First write vs change
-- ---------------------------------------------------------------------------

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000003', true, 'outflow', false, 99
  ) #>> '{error,code}',
  'version_conflict',
  'changing an existing rule with a stale version conflicts');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000003', true, 'outflow'
  ) #>> '{error,field}',
  'expectedVersion',
  'and changing one without a version is refused rather than taking the last '
  'write');

select is(
  (select count(*)::integer from public.finance_account_allocation_rules
   where finance_account_id = '71300000-0000-0000-0000-000000000003'
     and allocatable),
  0,
  'and nothing was written by either refusal');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000003', true, 'outflow', false, 1
  ) #>> '{entity,version}',
  '2',
  'with the right version it lands and the version moves');

-- A fourth account, so a first write can be tested against a version.
insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('71300000-0000-0000-0000-000000000004', '71100000-0000-0000-0000-000000000001',
   '4230', 'Gartenpflege', 'expense',
   '71200000-0000-0000-0000-000000000001', '71200000-0000-0000-0000-000000000001');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000004', true, 'outflow', false, 1
  ) #>> '{error,field}',
  'expectedVersion',
  'a first write with a version is refused: there is nothing yet to expect a '
  'version of, and accepting one would let a caller guess');

select is(
  pg_temp.set_rule('71300000-0000-0000-0000-000000000004', true, 'outflow')
    #>> '{entity,version}',
  '1',
  'a first write without one creates the rule at version 1');

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(pg_temp.rules() #> '{entity,accounts}'),
  4,
  'every account is listed');

select is(
  (pg_temp.rules() #>> '{entity,unclassified_count}')::integer,
  0,
  'and once all four are classified, none is unclassified');

-- A fifth account nobody has classified.
insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values
  ('71300000-0000-0000-0000-000000000005', '71100000-0000-0000-0000-000000000001',
   '4240', 'Ungeklaert', 'expense',
   '71200000-0000-0000-0000-000000000001', '71200000-0000-0000-0000-000000000001');

select is(
  (pg_temp.rules() #>> '{entity,unclassified_count}')::integer,
  1,
  'a new account counts as unclassified. This is the number the surface '
  'exists to drive to zero');

select is(
  (select entry #> '{rule}'
   from jsonb_array_elements(pg_temp.rules() #> '{entity,accounts}') as entry
   where entry ->> 'code' = '4240'),
  'null'::jsonb,
  'and it is listed with a null rule rather than filtered out -- a list of '
  'only the classified accounts would make the work look finished');

select is(
  (select entry #>> '{rule,settlement_principle}'
   from jsonb_array_elements(pg_temp.rules() #> '{entity,accounts}') as entry
   where entry ->> 'code' = '4210'),
  'performance',
  'while a classified one carries its rule');

select is(
  (pg_temp.rules() #>> '{entity,classified_count}')::integer,
  4,
  'and the counts add up');

-- ---------------------------------------------------------------------------
-- Permission
-- ---------------------------------------------------------------------------

select is(
  (pg_temp.rules('71200000-0000-0000-0000-000000000002') -> 'ok')::boolean,
  true,
  'an analyst holds finance.read and may see which costs are apportionable');

select is(
  pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000005', true, 'outflow', false, null, null,
    '71200000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'and does not hold finance.manage, so may not decide it');

select is(
  pg_temp.set_rule('71300000-0000-0000-0000-000000000009', true, 'outflow')
    #>> '{error,code}',
  'not_found',
  'an account that does not exist is not found');

-- ---------------------------------------------------------------------------
-- Idempotency and audit
-- ---------------------------------------------------------------------------

create or replace function pg_temp.replay() returns jsonb
language plpgsql
as $$
declare
  v_mutation uuid := gen_random_uuid();
  v_correlation uuid := gen_random_uuid();
  v_first jsonb;
  v_second jsonb;
begin
  v_first := pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000005', true, 'outflow', false, null, null,
    '71200000-0000-0000-0000-000000000001', v_mutation, v_correlation
  );
  v_second := pg_temp.set_rule(
    '71300000-0000-0000-0000-000000000005', true, 'outflow', false, null, null,
    '71200000-0000-0000-0000-000000000001', v_mutation, v_correlation
  );
  return jsonb_build_object('first', v_first, 'second', v_second);
end;
$$;

create temporary table _alloc_replay as select pg_temp.replay() as value;

select is(
  (select value #> '{first,entity}' from _alloc_replay),
  (select value #> '{second,entity}' from _alloc_replay),
  'a replayed write returns the rule the first call produced');

select is(
  (select version from public.finance_account_allocation_rules
   where finance_account_id = '71300000-0000-0000-0000-000000000005'),
  1::bigint,
  'and the rule was written once, not twice');

select ok(
  exists (
    select 1 from public.audit_events
    where workspace_id = '71100000-0000-0000-0000-000000000001'
      and entity_type = 'cost_allocation_rule'
      and action = 'cost_allocation_rule.create'
  ),
  'the first write is audited as a create');

select ok(
  exists (
    select 1 from public.audit_events
    where workspace_id = '71100000-0000-0000-0000-000000000001'
      and entity_type = 'cost_allocation_rule'
      and action = 'cost_allocation_rule.update'
  ),
  'and a later change as an update -- which cost a tenant pays is not a '
  'setting whose history may be blurred');

select * from finish();
rollback;
