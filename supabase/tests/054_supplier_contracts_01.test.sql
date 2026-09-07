begin;

create extension if not exists pgtap with schema extensions;

-- SUPPLIER-CONTRACTS-01 (P-3).
--
-- The programme's inventory records that a supplier contract exists nowhere:
-- "Lieferant ist heute ein Freitextfeld auf der Kostenzeile". The target model
-- names what it should be in one line — `supplier_contracts` with `party_id`
-- on `parties`, and "Fristen werden abgeleitet gelesen, nicht persistiert".
--
-- **The derived deadline is what most of this file is about.** There is no
-- scheduler anywhere in this stack (finding B-4), so a stored notice deadline
-- would go stale the moment somebody corrected an end date and nothing would
-- recompute it. The table therefore holds the *terms* and the read computes
-- the deadline against the date it was asked for. The fixture is built so the
-- same contract answers differently on three different dates — before the
-- notice window, inside it, and after it — which a stored column could not do.
--
-- The other half is the lifecycle: `draft` -> `active` -> `ended`, with the
-- terminal state reachable only through its own command and only with a
-- reason.

select plan(42);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'supplier_contracts', 'the contract table exists');

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname = 'supplier_contracts'),
  'with row level security enabled and forced');

select is(
  (select count(*)::integer from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   where class.relname = 'supplier_contracts'),
  1,
  'exactly one policy, and a SELECT one: writes go through the audited '
  'commands');

select ok(
  not has_table_privilege('anon', 'public.supplier_contracts', 'SELECT'),
  'anon cannot read it');

select ok(
  (select count(*) = 0 from information_schema.columns
   where table_schema = 'public' and table_name = 'supplier_contracts'
     and column_name in ('notice_deadline', 'next_notice_date', 'renews_on')),
  'there is no stored deadline column. That is the design: with no scheduler '
  'anywhere in this stack, a stored deadline goes stale the moment an end date '
  'is corrected and nothing recomputes it');

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('61200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'contracts-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('61200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'contracts-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('61100000-0000-0000-0000-000000000001', 'contracts', 'Contracts');
select private.seed_workspace_role_catalog('61100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '61100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('61200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('61200000-0000-0000-0000-000000000002'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '61100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values
  ('61900000-0000-0000-0000-000000000001', '61100000-0000-0000-0000-000000000001',
   'organization', 'Aufzug Service GmbH',
   '61200000-0000-0000-0000-000000000001', '61200000-0000-0000-0000-000000000001');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('61500000-0000-0000-0000-000000000001', '61100000-0000-0000-0000-000000000001',
   'Vertragshaus', 'Vertragsweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   '61200000-0000-0000-0000-000000000001', '61200000-0000-0000-0000-000000000001');

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

-- A lift maintenance contract ending 2026-12-31 with three months' notice.
-- The deadline is therefore 2026-10-02, and the fixture asks about it from
-- three sides.
create or replace function pg_temp.create_contract(
  p_title text default 'Aufzugswartung',
  p_end date default date '2026-12-31',
  p_notice integer default 90,
  p_auto_renew boolean default false,
  p_renewal_months integer default null,
  p_property uuid default null,
  p_value numeric default null,
  p_currency text default null,
  p_user uuid default '61200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.create_supplier_contract(
        %L::uuid, %L::uuid, %L, 'maintenance', date '2024-01-01',
        %L::uuid, %L::uuid, %s, null, %s, %s, %L::boolean, %s, %s, %s, 'Test')$q$,
      '61100000-0000-0000-0000-000000000001',
      '61900000-0000-0000-0000-000000000001', p_title,
      gen_random_uuid(), gen_random_uuid(),
      case when p_property is null then 'null'
           else quote_literal(p_property::text) || '::uuid' end,
      case when p_end is null then 'null'
           else quote_literal(p_end::text) || '::date' end,
      case when p_notice is null then 'null' else p_notice::text end,
      p_auto_renew,
      case when p_renewal_months is null then 'null'
           else p_renewal_months::text end,
      case when p_value is null then 'null' else p_value::text end,
      case when p_currency is null then 'null'
           else quote_literal(p_currency) end
    )
  );
$$;

create or replace function pg_temp.contracts_on(
  p_as_of date,
  p_include_ended boolean default false,
  p_user uuid default '61200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.supplier_contracts_as_of(
        %L::uuid, %L::date, null, null, %L::boolean)$q$,
      '61100000-0000-0000-0000-000000000001', p_as_of, p_include_ended
    )
  );
$$;

create or replace function pg_temp.first_contract(p_as_of date)
returns jsonb
language sql
as $$
  select pg_temp.contracts_on(p_as_of) #> '{entity,contracts,0}';
$$;

create or replace function pg_temp.contract_id()
returns uuid
language sql
as $$
  select id from public.supplier_contracts
  where workspace_id = '61100000-0000-0000-0000-000000000001'
    and title = 'Aufzugswartung';
$$;

-- ---------------------------------------------------------------------------
-- create
-- ---------------------------------------------------------------------------

select is(
  pg_temp.create_contract() #>> '{entity,status}',
  'draft',
  'a new contract opens as a draft, like every other entity with a lifecycle '
  'here. Promoting it is an explicit, audited update');

select is(
  pg_temp.create_contract(p_title => 'Ohne Berechtigung',
                          p_user => '61200000-0000-0000-0000-000000000002')
    #>> '{error,code}',
  'forbidden',
  'a viewer cannot create one');

select is(
  pg_temp.create_contract(p_title => 'Falsches Objekt',
                          p_property => '61500000-0000-0000-0000-000000000009')
    #>> '{error,code}',
  'not_found',
  'a property from outside the workspace is not found. The foreign key is '
  'single-column because `properties` carries no composite unique key, so this '
  'check is what actually holds the workspace boundary');

select is(
  pg_temp.create_contract(p_title => 'Verlängerung ohne Laufzeit',
                          p_auto_renew => true, p_renewal_months => null)
    #>> '{error,code}',
  'validation_failed',
  'auto-renewal without a renewal term is refused: a renewal needs something '
  'to renew to');

select is(
  pg_temp.create_contract(p_title => 'Verlängerung ohne Ende',
                          p_end => null, p_auto_renew => true,
                          p_renewal_months => 12)
    #>> '{error,code}',
  'validation_failed',
  'and auto-renewal on an open-ended contract is a contradiction');

select is(
  pg_temp.create_contract(p_title => 'Betrag ohne Währung', p_value => 1200)
    #>> '{error,code}',
  'validation_failed',
  'an amount without a currency is not a figure -- the same rule the rest of '
  'the money surface holds');

-- ---------------------------------------------------------------------------
-- The derived deadline: the same contract, three dates
-- ---------------------------------------------------------------------------

update public.supplier_contracts set status = 'active'
where title = 'Aufzugswartung';

select is(
  pg_temp.first_contract(date '2026-06-01') #>> '{notice_deadline}',
  '2026-10-02',
  'the notice deadline is end date minus notice period, computed at read time');

select is(
  (pg_temp.first_contract(date '2026-06-01') #>> '{days_to_notice}')::integer,
  123,
  'and the days remaining are counted against the date asked about');

select is(
  (pg_temp.first_contract(date '2026-06-01') #>> '{notice_window_open}')::boolean,
  true,
  'before the deadline the window is open');

select is(
  (pg_temp.first_contract(date '2026-06-01') #>> '{notice_deadline_passed}')::boolean,
  false,
  'and nothing has been missed');

select is(
  (pg_temp.first_contract(date '2026-11-15') #>> '{notice_deadline_passed}')::boolean,
  true,
  'after the deadline and before the end date, the contract will run on and '
  'it is too late to stop it. The single most useful fact on this surface -- '
  'and one a stored column would have got wrong the moment the end date was '
  'corrected');

select is(
  (pg_temp.first_contract(date '2026-11-15') #>> '{notice_window_open}')::boolean,
  false,
  'and the window is shut');

select is(
  (pg_temp.first_contract(date '2027-03-01') #>> '{notice_deadline_passed}')::boolean,
  false,
  'past the end date nothing is "missed" any more: a deadline behind an '
  'expired contract is history, not an alarm');

select is(
  (pg_temp.first_contract(date '2026-06-01') #>> '{is_effective}')::boolean,
  true,
  'the contract is in force on that date');

select is(
  (pg_temp.first_contract(date '2027-03-01') #>> '{is_effective}')::boolean,
  false,
  'and not after its end date');

select is(
  pg_temp.first_contract(date '2026-06-01') #>> '{renews_on}',
  null,
  'a contract that does not auto-renew renews on no date');

select is(
  pg_temp.first_contract(date '2026-06-01') #>> '{ends_on}',
  '2026-12-31',
  'while its end date is stated plainly');

select is(
  pg_temp.first_contract(date '2026-06-01') #>> '{party_name}',
  'Aufzug Service GmbH',
  'the supplier''s name travels with the contract -- a party id alone is not '
  'a counterparty anybody can recognise');

-- A second contract with no agreed notice period: the two absences are
-- different and the read has to report them differently.
select ok(
  (pg_temp.create_contract(p_title => 'Ohne Frist', p_notice => null)
   -> 'ok')::boolean,
  'a contract without an agreed notice period is allowed');

update public.supplier_contracts set status = 'active' where title = 'Ohne Frist';

select is(
  (select entry #>> '{notice_deadline}'
   from jsonb_array_elements(
     pg_temp.contracts_on(date '2026-06-01') #> '{entity,contracts}') as entry
   where entry ->> 'title' = 'Ohne Frist'),
  null,
  'no agreed notice period means no deadline -- not a deadline of zero days. '
  '"None was agreed" and "it is due today" are different statements');

-- ---------------------------------------------------------------------------
-- Auto-renewal
-- ---------------------------------------------------------------------------

select ok(
  (pg_temp.create_contract(p_title => 'Verlängert sich',
                           p_auto_renew => true, p_renewal_months => 12)
   -> 'ok')::boolean,
  'an auto-renewing contract with a term is allowed');

update public.supplier_contracts set status = 'active'
where title = 'Verlängert sich';

select is(
  (select entry #>> '{renews_on}'
   from jsonb_array_elements(
     pg_temp.contracts_on(date '2026-06-01') #> '{entity,contracts}') as entry
   where entry ->> 'title' = 'Verlängert sich'),
  '2026-12-31',
  'it renews on its end date -- and only the next one. An auto-renewing '
  'contract has infinitely many renewal dates, and projecting them is a '
  'calendar that wants a scheduler this stack has not got');

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------

create or replace function pg_temp.update_contract(
  p_changes jsonb,
  p_version bigint default 1,
  p_user uuid default '61200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.update_supplier_contract(
        %L::uuid, %L::uuid, %s::bigint, %L::uuid, %L::uuid, %L::jsonb, 'Test')$q$,
      '61100000-0000-0000-0000-000000000001', pg_temp.contract_id(), p_version,
      gen_random_uuid(), gen_random_uuid(), p_changes
    )
  );
$$;

select is(
  pg_temp.update_contract('{"status": "ended"}'::jsonb) #>> '{error,field}',
  'status',
  'a field edit cannot end a contract. Ending has its own command, which '
  'demands a reason and stamps the date -- and letting the terminal state be '
  'reached without either is how "why did we drop them" becomes unanswerable');

select is(
  pg_temp.update_contract('{"notice_period_days": 5000}'::jsonb)
    #>> '{error,code}',
  'validation_failed',
  'a four-digit notice period is refused: somebody meant months');

select is(
  pg_temp.update_contract('{"notice_period_days": 30}'::jsonb)
    #>> '{entity,notice_period_days}',
  '30',
  'a real change lands');

select is(
  pg_temp.first_contract(date '2026-06-01') #>> '{notice_deadline}',
  '2026-12-01',
  'and the deadline moves with it, because it was never stored');

-- ---------------------------------------------------------------------------
-- end
-- ---------------------------------------------------------------------------

create or replace function pg_temp.end_contract(
  p_version bigint,
  p_ended_reason text default 'Anbieter gewechselt'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    '61200000-0000-0000-0000-000000000001',
    format(
      $q$select public.end_supplier_contract(
        %L::uuid, %L::uuid, %s::bigint, %L::uuid, %L::uuid, %s, 'Test')$q$,
      '61100000-0000-0000-0000-000000000001', pg_temp.contract_id(), p_version,
      gen_random_uuid(), gen_random_uuid(),
      case when p_ended_reason is null then 'null'
           else quote_literal(p_ended_reason) end
    )
  );
$$;

select is(
  pg_temp.end_contract(2, null) #>> '{error,field}',
  'endedReason',
  'ending without a reason is refused. Why a supplier relationship ended is '
  'what somebody wants to know in two years, and a terminal state reachable '
  'without an explanation is how that gets lost');

select is(
  pg_temp.end_contract(2) #>> '{entity,status}',
  'ended',
  'with a reason it ends');

select ok(
  (select ended_at is not null from public.supplier_contracts
   where id = pg_temp.contract_id()),
  'and carries its stamp');

select is(
  pg_temp.end_contract(3) #>> '{error,code}',
  'validation_failed',
  'ending an ended contract is refused rather than silently repeated');

select is(
  pg_temp.update_contract('{"title": "Neuer Titel"}'::jsonb, 3)
    #>> '{error,code}',
  'validation_failed',
  'and an ended contract cannot be edited');

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.contracts_on(date '2026-06-01') #> '{entity,contracts}') as entry
   where entry ->> 'title' = 'Aufzugswartung'),
  0,
  'an ended contract is out of the default list -- a worklist is what is '
  'still running');

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.contracts_on(date '2026-06-01', true) #> '{entity,contracts}') as entry
   where entry ->> 'title' = 'Aufzugswartung'),
  1,
  'and reachable on request. "What did we agree with them before" is a real '
  'question, just not the one a worklist asks');

select is(
  (select entry #>> '{is_effective}'
   from jsonb_array_elements(
     pg_temp.contracts_on(date '2026-06-01', true) #> '{entity,contracts}') as entry
   where entry ->> 'title' = 'Aufzugswartung')::boolean,
  false,
  'and it is not effective on a date it was ended before -- status decides '
  'first, dates second');

-- Existence, not "the most recent". Every event in this file is written in one
-- transaction, so `now()` is identical for all of them and `order by
-- created_at desc limit 1` picks an arbitrary one -- an ordering assertion here
-- would pass or fail by luck.
select ok(
  exists (
    select 1 from public.audit_events
    where workspace_id = '61100000-0000-0000-0000-000000000001'
      and entity_type = 'supplier_contract'
      and action = 'supplier_contract.end'
  ),
  'the end is in the audit trail under its own action');

select ok(
  exists (
    select 1 from public.audit_events
    where workspace_id = '61100000-0000-0000-0000-000000000001'
      and entity_type = 'supplier_contract'
      and action = 'supplier_contract.create'
  ),
  'and so is the create, under a different one -- which is the whole reason '
  'ending has its own command');

select is(
  pg_temp.contracts_on(date '2026-06-01',
                       p_user => '61200000-0000-0000-0000-000000000002')
    #>> '{error,code}',
  'forbidden',
  'a viewer holds no party.read and cannot list them');

select * from finish();
rollback;
