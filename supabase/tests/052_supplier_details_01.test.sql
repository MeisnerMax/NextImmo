begin;

create extension if not exists pgtap with schema extensions;

-- SUPPLIER-DETAILS-01 (P-3).
--
-- The register has held a trade, an hourly rate, five ratings and an insurance
-- expiry since P2-D02, and the only way to change any of them was to re-assign
-- the contractor role. Two things follow, and both are what this file pins.
--
-- **The audit trail told the wrong story.** A rate correction came out as
-- `party.role.assign` -- a statement about who this company *is* to the
-- workspace, not about a typo in a number. The action key is asserted
-- explicitly below, because an audit entry that is confidently wrong is worse
-- than none.
--
-- **Nothing checked the version.** The satellite has carried a `version`
-- column all along that the role upsert increments and nothing compares, so
-- two people editing one contractor silently overwrote each other. The
-- conflict case here is the first time that column does any work.
--
-- The partial-update assertions matter more than they look. Every field this
-- command does not name must keep its value, and the `case ... else` branch
-- that does it is ten lines of near-identical code -- exactly the shape where
-- one copy-pasted column name goes unnoticed. So the test changes one field
-- and checks the other nine.

select plan(32);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'update_contractor_details',
  'the dedicated update exists');

select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'update_contractor_details'),
  'v'::"char",
  'it is volatile: a mutation, not a read');

select ok(
  not has_function_privilege(
    'anon',
    'public.update_contractor_details(uuid, uuid, bigint, uuid, uuid, jsonb, text)',
    'EXECUTE'
  ),
  'anon cannot call it');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'contractor_details_snapshot'),
  1,
  'and the audit payload comes from the one snapshot function P2-D02 already '
  'ships. A second one for the same table is two chances for an audit entry '
  'and a replayed result to describe the same row differently');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_maintenance_tickets'),
  1,
  'the ticket list exists exactly once -- the contractor filter was added by '
  'drop and recreate, not by an overload that would make the call ambiguous');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('41200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'supplier-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('41200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'supplier-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('41100000-0000-0000-0000-000000000001', 'supplier', 'Supplier');
select private.seed_workspace_role_catalog('41100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '41100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('41200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  -- viewer holds neither party.read nor party.manage.
  ('41200000-0000-0000-0000-000000000002'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '41100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values
  ('41900000-0000-0000-0000-000000000001', '41100000-0000-0000-0000-000000000001',
   'organization', 'Elektro Meyer GmbH',
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001'),
  -- A party with no contractor satellite: an update must not invent one.
  ('41900000-0000-0000-0000-000000000002', '41100000-0000-0000-0000-000000000001',
   'person', 'Frau Schmidt',
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001');

insert into public.party_contractor_details (
  party_id, workspace_id, trade_category, hourly_rate, service_area,
  rating_price, rating_quality, rating_speed, rating_communication,
  rating_punctuality, insurance_cert_expiry, is_active,
  created_by, updated_by
) values
  ('41900000-0000-0000-0000-000000000001', '41100000-0000-0000-0000-000000000001',
   'electrical', 85, 'Berlin Mitte', 4, 5, 3, 4, 5, date '2027-06-30', true,
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('41500000-0000-0000-0000-000000000001', '41100000-0000-0000-0000-000000000001',
   'Lieferantenhaus', 'Handwerkerweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001');

insert into public.maintenance_tickets (
  id, workspace_id, property_id, title, status, priority, contractor_party_id,
  reported_at, created_by, updated_by
) values
  ('41600000-0000-0000-0000-000000000001', '41100000-0000-0000-0000-000000000001',
   '41500000-0000-0000-0000-000000000001', 'Steckdose defekt', 'new', 'normal',
   '41900000-0000-0000-0000-000000000001', now(),
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001'),
  ('41600000-0000-0000-0000-000000000002', '41100000-0000-0000-0000-000000000001',
   '41500000-0000-0000-0000-000000000001', 'Zweiter Auftrag', 'new', 'normal',
   '41900000-0000-0000-0000-000000000001', now(),
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001'),
  -- Unassigned: it must disappear when the filter is applied, and it is the
  -- reason "the filter narrows" is a real assertion rather than a tautology.
  ('41600000-0000-0000-0000-000000000003', '41100000-0000-0000-0000-000000000001',
   '41500000-0000-0000-0000-000000000001', 'Ohne Handwerker', 'new', 'normal',
   null, now(),
   '41200000-0000-0000-0000-000000000001', '41200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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

-- The correlation id is a parameter with a fresh default, not a fresh value
-- per call. It is part of the request hash, so a "retry" that invented a new
-- one would be a different request and would conflict rather than replay --
-- which is correct server behaviour and would have made the replay assertion
-- below test the wrong thing.
create or replace function pg_temp.update_details(
  p_changes jsonb,
  p_version bigint default 1,
  p_mutation uuid default gen_random_uuid(),
  p_user uuid default '41200000-0000-0000-0000-000000000001',
  p_party uuid default '41900000-0000-0000-0000-000000000001',
  p_correlation uuid default gen_random_uuid()
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.update_contractor_details(
        %L::uuid, %L::uuid, %s::bigint, %L::uuid, %L::uuid, %L::jsonb, 'Test')$q$,
      '41100000-0000-0000-0000-000000000001', p_party, p_version,
      p_mutation, p_correlation, p_changes
    )
  );
$$;

create or replace function pg_temp.tickets(p_contractor uuid)
returns integer
language sql
as $$
  select jsonb_array_length(
    pg_temp.as_user(
      '41200000-0000-0000-0000-000000000001',
      format(
        $q$select public.workspace_maintenance_tickets(
          %L::uuid, null, null, null, %s)$q$,
        '41100000-0000-0000-0000-000000000001',
        case when p_contractor is null then 'null'
             else quote_literal(p_contractor::text) || '::uuid' end
      )
    ) -> 'entity'
  );
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  pg_temp.update_details(
    '{"hourly_rate": 90}'::jsonb,
    p_user => '41200000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'a member without party.manage is refused');

select is(
  pg_temp.update_details(
    '{"hourly_rate": 90}'::jsonb,
    p_party => '41900000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'not_found',
  'a party with no contractor satellite is not found. Creating one here would '
  'let an update invent a contractor, which is assign_party_role''s decision');

select is(
  pg_temp.update_details('{}'::jsonb) #>> '{error,field}',
  'changes',
  'an empty change set is refused rather than treated as a no-op write');

select is(
  pg_temp.update_details('{"favourite_colour": "blau"}'::jsonb)
    #> '{error,fields}',
  jsonb_build_array('favourite_colour'),
  'an unsupported field is named back, not silently dropped');

select is(
  pg_temp.update_details('{"hourly_rate": 90}'::jsonb, p_version => 99)
    #>> '{error,code}',
  'version_conflict',
  'a stale version conflicts. This column has existed since P2-D02 and until '
  'now nothing ever compared it, so two people editing one contractor '
  'overwrote each other in silence');

select is(
  pg_temp.update_details('{"hourly_rate": 90}'::jsonb, p_version => 99)
    #> '{error,current_entity,hourly_rate}',
  to_jsonb(85.0),
  'and the conflict carries the row as it actually stands, so the form can '
  'show what it would have overwritten');

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

select is(
  pg_temp.update_details('{"rating_quality": 7}'::jsonb) #>> '{error,field}',
  'rating_quality',
  'a rating above five is refused, naming the field that was wrong -- five '
  'ratings share one rule and the error still has to point at one of them');

select is(
  pg_temp.update_details('{"rating_speed": -1}'::jsonb) #>> '{error,field}',
  'rating_speed',
  'and so is one below zero, on a different field');

select is(
  pg_temp.update_details('{"hourly_rate": -5}'::jsonb) #>> '{error,field}',
  'hourly_rate',
  'a negative rate is refused');

select is(
  pg_temp.update_details('{"trade_category": null}'::jsonb) #>> '{error,field}',
  'trade_category',
  'the trade cannot be cleared: it is what makes the row a contractor record '
  'rather than an empty satellite, and the column says so with NOT NULL');

select is(
  pg_temp.update_details('{"insurance_cert_expiry": "gestern"}'::jsonb)
    #>> '{error,field}',
  'insurance_cert_expiry',
  'a date that is not a date is refused');

select is(
  pg_temp.update_details('{"is_active": "ja"}'::jsonb) #>> '{error,field}',
  'is_active',
  'and so is a string where a boolean belongs');

-- ---------------------------------------------------------------------------
-- The write
-- ---------------------------------------------------------------------------

select is(
  pg_temp.update_details('{"hourly_rate": 95}'::jsonb) #> '{entity,hourly_rate}',
  to_jsonb(95.0),
  'the named field changes');

select is(
  (select hourly_rate from public.party_contractor_details
   where party_id = '41900000-0000-0000-0000-000000000001'),
  95::numeric,
  'and it is what the table holds');

select is(
  (select version from public.party_contractor_details
   where party_id = '41900000-0000-0000-0000-000000000001'),
  2::bigint,
  'the version moves');

select is(
  (select
     trade_category || '|' || service_area || '|' ||
     rating_price || rating_quality || rating_speed ||
     rating_communication || rating_punctuality || '|' ||
     insurance_cert_expiry || '|' || is_active
   from public.party_contractor_details
   where party_id = '41900000-0000-0000-0000-000000000001'),
  'electrical|Berlin Mitte|45345|2027-06-30|true',
  'and every field the command did not name keeps its value. Ten near-'
  'identical `case ... else` branches is exactly where one copy-pasted column '
  'name goes unnoticed, so all nine are checked at once');

select is(
  (select action from public.audit_events
   where workspace_id = '41100000-0000-0000-0000-000000000001'
     and entity_type = 'party_contractor_details'
   order by created_at desc limit 1),
  'party.contractor_details.update',
  'the audit entry says what happened. Through assign_party_role a rate '
  'correction came out as `party.role.assign`, which is a statement about who '
  'this company is to the workspace rather than about a typo in a number');

select is(
  pg_temp.update_details(
    '{"rating_price": null, "hourly_rate": null}'::jsonb, p_version => 2
  ) #> '{entity,hourly_rate}',
  'null'::jsonb,
  'null clears a figure. "We no longer have an agreed rate" is a different '
  'statement from "the rate is zero"');

select is(
  (select rating_price from public.party_contractor_details
   where party_id = '41900000-0000-0000-0000-000000000001'),
  null::numeric,
  'and a rating clears the same way');

select is(
  pg_temp.update_details(
    '{"insurance_cert_expiry": "2020-01-01"}'::jsonb, p_version => 3
  ) #>> '{entity,insurance_cert_expiry}',
  '2020-01-01',
  'a past insurance date is accepted on purpose. An expired certificate is a '
  'fact worth recording, and refusing it would leave the register showing the '
  'old valid one -- which is the reading that gets somebody sent to a site '
  'uninsured');

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------

create or replace function pg_temp.replay() returns jsonb
language plpgsql
as $$
declare
  v_mutation uuid := gen_random_uuid();
  v_correlation uuid := gen_random_uuid();
  v_first jsonb;
  v_second jsonb;
  v_other jsonb;
begin
  v_first := pg_temp.update_details(
    '{"service_area": "Berlin gesamt"}'::jsonb, 4, v_mutation,
    p_correlation => v_correlation
  );
  -- The same command, sent twice. What a client retry after a lost response
  -- looks like.
  v_second := pg_temp.update_details(
    '{"service_area": "Berlin gesamt"}'::jsonb, 4, v_mutation,
    p_correlation => v_correlation
  );
  -- The same mutation id carrying a different command. Not a retry.
  v_other := pg_temp.update_details(
    '{"service_area": "etwas anderes"}'::jsonb, 4, v_mutation,
    p_correlation => v_correlation
  );
  return jsonb_build_object(
    'first', v_first, 'second', v_second, 'other', v_other
  );
end;
$$;

create or replace function pg_temp.replayed() returns jsonb
language sql
as $$
  select pg_temp.replay();
$$;

create temporary table _replay_result as select pg_temp.replay() as value;

select is(
  (select (value #>> '{second,entity,version}')::bigint from _replay_result),
  5::bigint,
  'a replayed mutation returns the entity the first call produced, with the '
  'version it produced -- not a second increment');

select is(
  (select value #> '{first,entity}' from _replay_result),
  (select value #> '{second,entity}' from _replay_result),
  'the two answers are the same object, field for field');

select is(
  (select version from public.party_contractor_details
   where party_id = '41900000-0000-0000-0000-000000000001'),
  5::bigint,
  'and the table moved once, not twice');

select is(
  (select value #>> '{other,error,code}' from _replay_result),
  'mutation_conflict',
  'the same mutation id carrying a different command is a conflict, not a '
  'replay -- otherwise a client that reused an id would be told its second, '
  'different intent had succeeded');

-- ---------------------------------------------------------------------------
-- "Which tickets does this contractor have"
-- ---------------------------------------------------------------------------

select is(pg_temp.tickets(null), 3,
  'without the filter every ticket comes back');

select is(
  pg_temp.tickets('41900000-0000-0000-0000-000000000001'),
  2,
  'the contractor filter narrows to the two assigned to them. The column has '
  'existed since P2-D06 and was indexed; nothing could filter on it');

select is(
  pg_temp.tickets('41900000-0000-0000-0000-000000000002'),
  0,
  'a party with no tickets matches none rather than falling back to all');

select * from finish();
rollback;
