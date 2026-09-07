begin;

create extension if not exists pgtap with schema extensions;

-- COMPLIANCE-RULES-01 (V-4): the legal rule layer.
--
-- `DEC-014` sat open from Phase 0 until the owner granted it on 2026-09-07.
-- What that approval authorises is a *shape*, and this file is where the shape
-- is pinned, because the shape is the only thing standing between a researched
-- legal position and a number somebody remembered.
--
-- Three assertions carry the package:
--
--   * **A date gets the law of its own period.** An operating-cost statement
--     for 2024 runs under different rules than one for 2026, and a
--     retrospective correction must apply the law of *then*. The fixture holds
--     the real CO2 price ladder -- 45 for 2024, 55 for 2025, 60 for 2026 --
--     and the read is asked for each year.
--   * **Editing a rule un-verifies it.** Stating the law and vouching for the
--     statement are different acts. A rule that stays `verified` through an
--     edit carries somebody's name on a sentence they never read.
--   * **A `decision_support` rule cannot be verified into an automatic one.**
--     § 5d CO2KostAufG is a five-part cumulative test with open legal
--     concepts; the programme's instruction is "Assistenz mit Bestätigung,
--     nicht automatische Entscheidung". Verifying it once, for all cases, is
--     precisely the failure that instruction names.

select plan(39);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'compliance_rules', 'the rule table exists');

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public' and class.relname = 'compliance_rules'),
  'with row level security enabled and forced');

select is(
  (select count(*)::integer from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'compliance_rules'),
  1,
  'exactly one policy, and it is a SELECT: writes go through the audited '
  'commands, never through a DML policy');

select is(
  (select policy.polcmd from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'compliance_rules'),
  'r'::"char",
  'read only');

select ok(
  (select count(*) > 0 from pg_constraint
   where conname = 'compliance_rules_no_overlap' and contype = 'x'),
  'an EXCLUSION constraint forbids two rules of one key covering one day. '
  'Otherwise "the CO2 price on 3 March 2026" has two answers');

select ok(
  not has_table_privilege('anon', 'public.compliance_rules', 'SELECT'),
  'anon cannot read the table');

-- ---------------------------------------------------------------------------
-- Fixture: the real CO2 price ladder, and one rule the law leaves to judgement
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('51200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'rules-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('51200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'rules-manager@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('51100000-0000-0000-0000-000000000001', 'rules', 'Rules');
select private.seed_workspace_role_catalog('51100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '51100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('51200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  -- manager holds workspace.read but not security.manage: the actor who may
  -- read the workspace's legal position and may not change it.
  ('51200000-0000-0000-0000-000000000002'::uuid, 'manager')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '51100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

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

create or replace function pg_temp.upsert(
  p_key text,
  p_from date,
  p_value jsonb,
  p_to date default null,
  p_source text default 'BEHG Anlage 1',
  p_rule_id uuid default null,
  p_version bigint default null,
  p_decision_support boolean default false,
  p_user uuid default '51200000-0000-0000-0000-000000000001',
  p_mutation uuid default gen_random_uuid(),
  p_correlation uuid default gen_random_uuid()
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.upsert_compliance_rule(
        %L::uuid, %L, %L::date, %L::jsonb, %L, %L::uuid, %L::uuid,
        %s, %s, %s, null, null, 'DE', %L::boolean, 'Test')$q$,
      '51100000-0000-0000-0000-000000000001', p_key, p_from, p_value, p_source,
      p_mutation, p_correlation,
      case when p_rule_id is null then 'null'
           else quote_literal(p_rule_id::text) || '::uuid' end,
      case when p_version is null then 'null'
           else p_version::text || '::bigint' end,
      case when p_to is null then 'null'
           else quote_literal(p_to::text) || '::date' end,
      p_decision_support
    )
  );
$$;

create or replace function pg_temp.rules_on(
  p_as_of date,
  p_key text default null,
  p_user uuid default '51200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.compliance_rules_as_of(%L::uuid, %L::date, %s, 'DE')$q$,
      '51100000-0000-0000-0000-000000000001', p_as_of,
      case when p_key is null then 'null' else quote_literal(p_key) end
    )
  );
$$;

-- The CO2 price ladder as the research records it. Three adjacent periods,
-- which the EXCLUSION constraint must accept -- adjacency is not overlap.
select is(
  (pg_temp.upsert('co2_price_eur_per_tonne', date '2024-01-01',
                  '45'::jsonb, date '2024-12-31') -> 'ok')::boolean,
  true,
  'the 2024 price is recorded');

select is(
  (pg_temp.upsert('co2_price_eur_per_tonne', date '2025-01-01',
                  '55'::jsonb, date '2025-12-31') -> 'ok')::boolean,
  true,
  'and the 2025 one directly after it -- adjacent periods are not an overlap, '
  'which is the whole reason the range is half-open internally');

select is(
  (pg_temp.upsert('co2_price_eur_per_tonne', date '2026-01-01',
                  '60'::jsonb, null) -> 'ok')::boolean,
  true,
  'and the current one, open-ended');

-- ---------------------------------------------------------------------------
-- A date gets the law of its own period
-- ---------------------------------------------------------------------------

select is(
  pg_temp.rules_on(date '2024-06-30', 'co2_price_eur_per_tonne')
    #> '{entity,rules,0,value}',
  '45'::jsonb,
  'a statement for 2024 gets the 2024 price');

select is(
  pg_temp.rules_on(date '2025-06-30', 'co2_price_eur_per_tonne')
    #> '{entity,rules,0,value}',
  '55'::jsonb,
  'a statement for 2025 gets the 2025 price. This is the entire reason the '
  'rules are data: a retrospective correction must apply the law of then, and '
  'a constant in code cannot');

select is(
  pg_temp.rules_on(date '2026-09-07', 'co2_price_eur_per_tonne')
    #> '{entity,rules,0,value}',
  '60'::jsonb,
  'and today gets today''s');

select is(
  jsonb_array_length(
    pg_temp.rules_on(date '2023-01-01', 'co2_price_eur_per_tonne')
      #> '{entity,rules}'
  ),
  0,
  'a date before any recorded rule gets nothing -- not the earliest rule. '
  'Reaching backwards would apply a price to a year it was not law in');

-- ---------------------------------------------------------------------------
-- No two answers for one day
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert('co2_price_eur_per_tonne', date '2025-06-01',
                 '99'::jsonb, date '2025-08-31') #>> '{error,code}',
  'dependency_conflict',
  'an overlapping period is refused. Two rules covering 1 June 2025 would '
  'make the price of that day depend on which row was read first');

select is(
  (select count(*)::integer from public.compliance_rules
   where workspace_id = '51100000-0000-0000-0000-000000000001'
     and rule_key = 'co2_price_eur_per_tonne'),
  3,
  'and nothing was written -- the refusal is not a partial write');

-- ---------------------------------------------------------------------------
-- A legal figure must say where it comes from
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert('umlageausfallwagnis_percent', date '2026-01-01',
                 '2'::jsonb, null, '') #>> '{error,field}',
  'sourceReference',
  'a rule without a source is refused. A legal figure with no source is a '
  'number somebody remembered, and this package exists because the programme '
  'insisted the research be "recherchiert, nicht aus dem Gedächtnis"');

-- ---------------------------------------------------------------------------
-- Permission
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert('test_key', date '2026-01-01', '1'::jsonb, null,
                 'Quelle', null, null, false,
                 '51200000-0000-0000-0000-000000000002')
    #>> '{error,code}',
  'forbidden',
  'a manager cannot change the workspace''s legal position. Editing a lease '
  'and deciding what the law says about it are different authorities');

select is(
  (pg_temp.rules_on(date '2026-09-07', null,
                    '51200000-0000-0000-0000-000000000002')
   -> 'ok')::boolean,
  true,
  'while they can read it. A rule nobody can see is a rule nobody can '
  'challenge');

-- ---------------------------------------------------------------------------
-- Verification is its own event
-- ---------------------------------------------------------------------------

create or replace function pg_temp.verify(
  p_rule uuid,
  p_version bigint,
  p_verified boolean,
  p_user uuid default '51200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.verify_compliance_rule(
        %L::uuid, %L::uuid, %s::bigint, %L::boolean, %L::uuid, %L::uuid,
        'Gegen BGBl. geprüft', 'Test')$q$,
      '51100000-0000-0000-0000-000000000001', p_rule, p_version, p_verified,
      gen_random_uuid(), gen_random_uuid()
    )
  );
$$;

create or replace function pg_temp.rule_id(p_key text, p_from date)
returns uuid
language sql
as $$
  select id from public.compliance_rules
  where workspace_id = '51100000-0000-0000-0000-000000000001'
    and rule_key = p_key and valid_from = p_from;
$$;

select is(
  (select confidence::text from public.compliance_rules
   where id = pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01')),
  'unverified',
  'a new rule starts unverified. Not a defect state -- the normal state of a '
  'rule nobody has checked yet');

select is(
  pg_temp.verify(
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01'), 1, true
  ) #>> '{entity,confidence}',
  'verified',
  'a named person can confirm it');

select is(
  (select verified_by from public.compliance_rules
   where id = pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01')),
  '51200000-0000-0000-0000-000000000001'::uuid,
  'and the confirmation carries who they were');

select ok(
  (select verified_at is not null from public.compliance_rules
   where id = pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01')),
  'and when. A verification without an author or a date is not a verification, '
  'and the CHECK constraint refuses one');

select throws_ok(
  $$insert into public.compliance_rules (
      workspace_id, rule_key, valid_from, value, source_reference,
      confidence, created_by, updated_by
    ) values (
      '51100000-0000-0000-0000-000000000001', 'bogus', date '2026-01-01',
      '1'::jsonb, 'Quelle', 'verified',
      '51200000-0000-0000-0000-000000000001',
      '51200000-0000-0000-0000-000000000001'
    )$$,
  '23514',
  null,
  'a rule cannot be verified with nobody standing behind it, even by direct '
  'insert. That state is worse than unverified, because it stops the question '
  'being asked');

-- ---------------------------------------------------------------------------
-- Editing un-verifies. The assertion this package is really about.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert(
    'co2_price_eur_per_tonne', date '2026-01-01', '65'::jsonb, null,
    'BEHG Anlage 1, korrigiert',
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01'), 2
  ) #>> '{entity,confidence}',
  'unverified',
  'editing a verified rule drops it back to unverified. Stating the law and '
  'vouching for the statement are different acts, and a rule that stayed '
  'verified through an edit would carry somebody''s name on a sentence they '
  'never read');

select is(
  (select verified_by from public.compliance_rules
   where id = pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01')),
  null::uuid,
  'and the author is cleared with it');

select is(
  (select value from public.compliance_rules
   where id = pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01')),
  '65'::jsonb,
  'while the edit itself landed -- the un-verification is a consequence, not a '
  'refusal');

-- ---------------------------------------------------------------------------
-- Withdrawing a verification
-- ---------------------------------------------------------------------------

select is(
  pg_temp.verify(
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2025-01-01'), 1, true
  ) #>> '{entity,confidence}',
  'verified',
  'the 2025 rule is confirmed');

select is(
  pg_temp.verify(
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2025-01-01'), 2, false
  ) #>> '{entity,verified_by}',
  null,
  'and withdrawing the confirmation clears the author. A rule reading '
  '"unverified" while still naming who checked it invites trusting the name '
  'over the state');

-- ---------------------------------------------------------------------------
-- Decision support: the rule the law will not let a machine settle
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert(
    'co2kostaufg_5d_haertefall', date '2026-01-01',
    '{"test": "fünfgliedrig kumulativ", "automatable": false}'::jsonb,
    null, 'CO2KostAufG § 5d', null, null, true
  ) #>> '{entity,confidence}',
  'decision_support',
  '§ 5d is recorded as decision support');

select is(
  pg_temp.verify(
    pg_temp.rule_id('co2kostaufg_5d_haertefall', date '2026-01-01'), 1, true
  ) #>> '{error,field}',
  'verified',
  'and it cannot be verified into an automatic one. Confirming it once would '
  'turn "a human must decide each case" into "this was decided, for all '
  'cases" -- exactly the failure the programme names § 5d to prevent');

select is(
  (select confidence::text from public.compliance_rules
   where id = pg_temp.rule_id('co2kostaufg_5d_haertefall', date '2026-01-01')),
  'decision_support',
  'and the refusal left it as it was');

-- ---------------------------------------------------------------------------
-- The read reports what it is standing on
-- ---------------------------------------------------------------------------

select is(
  (pg_temp.rules_on(date '2026-09-07') #>> '{entity,decision_support_count}')::integer,
  1,
  'the read counts the rules that need a human. A calculation built on them '
  'has to be able to say so, and it can only do that if the read tells it');

select ok(
  (pg_temp.rules_on(date '2026-09-07') #>> '{entity,unverified_count}')::integer > 0,
  'and the ones nobody has checked');

select is(
  pg_temp.rules_on(date '2026-09-07') #>> '{entity,jurisdiction}',
  'DE',
  'the jurisdiction travels with the answer. A workspace holding Austrian '
  'assets would otherwise silently get German operating-cost law applied to '
  'them');

-- ---------------------------------------------------------------------------
-- Concurrency and idempotency
-- ---------------------------------------------------------------------------

select is(
  pg_temp.upsert(
    'co2_price_eur_per_tonne', date '2026-01-01', '70'::jsonb, null, 'Quelle',
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01'), 99
  ) #>> '{error,code}',
  'version_conflict',
  'a stale version conflicts');

select is(
  pg_temp.upsert(
    'co2_price_eur_per_tonne', date '2026-01-01', '70'::jsonb, null, 'Quelle',
    pg_temp.rule_id('co2_price_eur_per_tonne', date '2026-01-01'), 99
  ) #> '{error,current_entity,value}',
  '65'::jsonb,
  'and carries the rule as it stands, so a stale form can show what it would '
  'have overwritten');

create or replace function pg_temp.replay() returns jsonb
language plpgsql
as $$
declare
  v_mutation uuid := gen_random_uuid();
  v_correlation uuid := gen_random_uuid();
  v_first jsonb;
  v_second jsonb;
begin
  v_first := pg_temp.upsert(
    'heizkostenv_70_percent_rule', date '2026-01-01',
    '{"no_wschv_1994": true, "oil_or_gas": true, "insulated_pipes": true}'::jsonb,
    null, 'HeizkostenV § 7 Abs. 1 S. 2', null, null, false,
    '51200000-0000-0000-0000-000000000001', v_mutation, v_correlation
  );
  v_second := pg_temp.upsert(
    'heizkostenv_70_percent_rule', date '2026-01-01',
    '{"no_wschv_1994": true, "oil_or_gas": true, "insulated_pipes": true}'::jsonb,
    null, 'HeizkostenV § 7 Abs. 1 S. 2', null, null, false,
    '51200000-0000-0000-0000-000000000001', v_mutation, v_correlation
  );
  return jsonb_build_object('first', v_first, 'second', v_second);
end;
$$;

create temporary table _replay as select pg_temp.replay() as value;

select is(
  (select value #> '{first,entity,id}' from _replay),
  (select value #> '{second,entity,id}' from _replay),
  'a replayed create returns the rule the first call made, not a second one');

select is(
  (select count(*)::integer from public.compliance_rules
   where rule_key = 'heizkostenv_70_percent_rule'),
  1,
  'and exactly one row exists. The 70%% rule is three building attributes in '
  'one value, not three rules -- and certainly not six');

select is(
  pg_temp.verify(
    '51900000-0000-0000-0000-000000000009', 1, true
  ) #>> '{error,code}',
  'not_found',
  'verifying a rule that does not exist is not found');

select * from finish();
rollback;
