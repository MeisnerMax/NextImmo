begin;

create extension if not exists pgtap with schema extensions;

-- ALERT-READER-01 (P-10): one time source, and the signals of a whole
-- workspace in one read.
--
-- The riskiest part of this package is not the new function, it is the **move**
-- underneath it. Eight signal definitions -- thresholds, severity ladders and
-- the German-facing messages -- came out of `public.operations_signals` and
-- into `private.operations_signal_rows`, so the property screen and the
-- workspace list compute from one definition instead of two.
--
-- A move like that is exactly the kind that passes a green suite while
-- silently changing a number. Two things guard it here:
--
--   * the whole existing `operations_signals` test file, which was written
--     against the old body and still passes untouched;
--   * the equality assertion below, which requires the workspace read and the
--     property read to name the *same signals* for the same property. If a
--     future author edits one path, that is what fails.
--
-- The rest pins what a workspace read does that a property read never had to:
-- exclude archived assets, cap honestly, and refuse a filter it does not
-- understand instead of answering it with an empty list.

select plan(40);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'workspace_operations_signals',
  'the workspace-wide reader exists');

select has_function('private', 'operations_signal_rows',
  'and the signal definitions live in one private place');

select has_function('private', 'operations_now', 'the time source exists');
select has_function('private', 'operations_today', 'and its calendar day');

select is(
  private.operations_today(),
  (private.operations_now() at time zone 'utc')::date,
  'today is derived from now, never taken independently. `current_date` '
  'follows the session timezone and `now()` does not, so two sources taking '
  'them separately can disagree by a day -- at midnight, which is when a '
  'deadline alarm is read');

select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_operations_signals'),
  true,
  'the reader is security definer');

select ok(
  not has_function_privilege(
    'anon',
    'public.workspace_operations_signals(uuid, text, text, integer)',
    'EXECUTE'
  ),
  'anon cannot call the reader');

select ok(
  not has_function_privilege(
    'authenticated',
    'private.operations_signal_rows(uuid, uuid)',
    'EXECUTE'
  ),
  'and no session role can call the private one at all. It does no permission '
  'check of its own -- and `grant usage on schema private to authenticated` '
  'means it would be reachable by name, with PUBLIC keeping its default '
  'EXECUTE, if nothing revoked it');

select ok(
  not has_function_privilege(
    'authenticated', 'private.operations_now()', 'EXECUTE'
  ),
  'the time source is private too');

select ok(
  has_function_privilege(
    'authenticated',
    'public.workspace_operations_signals(uuid, text, text, integer)',
    'EXECUTE'
  ),
  'while a signed-in member can call the reader -- otherwise the three '
  'assertions above would pass on a surface nobody can reach');

-- ---------------------------------------------------------------------------
-- Fixture: three properties, one of them archived
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('31200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alert-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('31200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alert-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('31100000-0000-0000-0000-000000000001', 'alerts', 'Alerts');
select private.seed_workspace_role_catalog('31100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '31100000-0000-0000-0000-000000000001',
       '31200000-0000-0000-0000-000000000001', role.id, 'active'
from public.roles as role
where role.workspace_id = '31100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, deleted_at, created_by, updated_by
) values
  -- Named so the alphabetical tiebreak is checkable: Alpha before Beta.
  ('31500000-0000-0000-0000-000000000001', '31100000-0000-0000-0000-000000000001',
   'Alpha-Haus', 'Alarmweg 1', '10115', 'Berlin', 'de', 'residential', 2,
   'active', null,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001'),
  ('31500000-0000-0000-0000-000000000002', '31100000-0000-0000-0000-000000000001',
   'Beta-Haus', 'Alarmweg 2', '10115', 'Berlin', 'de', 'residential', 1,
   'active', null,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001'),
  -- Archived. It has a signal-producing unit, and must still not appear in a
  -- worklist.
  ('31500000-0000-0000-0000-000000000003', '31100000-0000-0000-0000-000000000001',
   'Gamma-Haus', 'Alarmweg 3', '10115', 'Berlin', 'de', 'residential', 1,
   -- The schema ties `archived` to a deletion stamp; the two travel together.
   'archived', now(),
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, vacancy_since,
  created_by, updated_by
) values
  -- Alpha: a vacancy with no start date (warning).
  ('31600000-0000-0000-0000-000000000001', '31100000-0000-0000-0000-000000000001',
   '31500000-0000-0000-0000-000000000001', 'A-01', 'vacant', null,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001'),
  ('31600000-0000-0000-0000-000000000002', '31100000-0000-0000-0000-000000000001',
   '31500000-0000-0000-0000-000000000001', 'A-02', 'occupied', null,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001'),
  -- Beta: a vacancy older than the 45-day window (warning).
  ('31600000-0000-0000-0000-000000000003', '31100000-0000-0000-0000-000000000001',
   '31500000-0000-0000-0000-000000000002', 'B-01', 'vacant', current_date - 60,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001'),
  -- Gamma, archived: would produce the same warning as Alpha's A-01.
  ('31600000-0000-0000-0000-000000000004', '31100000-0000-0000-0000-000000000001',
   '31500000-0000-0000-0000-000000000003', 'G-01', 'vacant', null,
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001');

insert into public.parties (
  id, workspace_id, party_type, display_name, email, phone,
  created_by, updated_by
) values
  ('31900000-0000-0000-0000-000000000001', '31100000-0000-0000-0000-000000000001',
   'person', 'Mieterin A', 'mieterin@example.test', '+49 30 000000',
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001');

-- Alpha: an active lease ending inside 30 days -> a `critical` lease_expiry.
insert into public.leases (
  id, workspace_id, property_id, unit_id, tenant_party_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  ('31700000-0000-0000-0000-000000000001', '31100000-0000-0000-0000-000000000001',
   '31500000-0000-0000-0000-000000000001', '31600000-0000-0000-0000-000000000002',
   '31900000-0000-0000-0000-000000000001',
   'Alpha-Vertrag', 'active', current_date - 400, current_date + 20, null, null,
   1000, 'EUR',
   '31200000-0000-0000-0000-000000000001', '31200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function pg_temp.alerts(
  p_user uuid default '31200000-0000-0000-0000-000000000001',
  p_severity text default null,
  p_status text default null,
  p_limit integer default 200,
  p_aal text default 'aal2',
  p_workspace uuid default '31100000-0000-0000-0000-000000000001'
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
  v := public.workspace_operations_signals(
    p_workspace, p_severity, p_status, p_limit
  );
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

-- The signal keys the workspace read reports for one property.
create or replace function pg_temp.workspace_keys(p_property uuid)
returns text[]
language sql
as $$
  select coalesce(array_agg(entry ->> 'signal_key' order by entry ->> 'signal_key'), '{}')
  from jsonb_array_elements(pg_temp.alerts() #> '{entity,signals}') as entry
  where entry ->> 'property_id' = p_property::text;
$$;

-- The property-scoped read's whole envelope, so a refusal is readable.
create or replace function pg_temp.property_signals(p_property uuid)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', '31200000-0000-0000-0000-000000000001',
                      'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v := public.operations_signals('31100000-0000-0000-0000-000000000001', p_property);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

-- The signal keys the property-scoped read reports for the same property.
create or replace function pg_temp.property_keys(p_property uuid)
returns text[]
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', '31200000-0000-0000-0000-000000000001',
                      'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v := public.operations_signals('31100000-0000-0000-0000-000000000001', p_property);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return (
    select coalesce(array_agg(entry ->> 'signal_key' order by entry ->> 'signal_key'), '{}')
    from jsonb_array_elements(v #> '{entity,signals}') as entry
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  public.workspace_operations_signals(
    '31100000-0000-0000-0000-000000000001', null, null, 200
  ) #>> '{error,code}',
  'forbidden',
  'an unauthenticated caller is refused');

select is(
  pg_temp.alerts(p_aal => 'aal1') #>> '{error,code}',
  'forbidden',
  'an aal1 session is refused (DEC-025)');

select is(
  pg_temp.alerts(p_user => '31200000-0000-0000-0000-000000000002')
    #>> '{error,code}',
  'forbidden',
  'and so is a caller without lease.read');

select is(
  pg_temp.alerts(p_workspace => null) #>> '{error,field}',
  'workspaceId',
  'a missing workspace is a validation failure');

select is(
  pg_temp.alerts(p_severity => 'katastrophal') #>> '{error,field}',
  'severity',
  'an unknown severity is refused, not answered with an empty list. Silence '
  'would read as "nothing critical"');

select is(
  pg_temp.alerts(p_status => 'erledigt') #>> '{error,field}',
  'status',
  'and so is an unknown status, which would read as "everything is handled"');

-- ---------------------------------------------------------------------------
-- One read, many properties
-- ---------------------------------------------------------------------------

select ok(
  (select count(distinct entry ->> 'property_id') from jsonb_array_elements(
     pg_temp.alerts() #> '{entity,signals}') as entry) >= 2,
  'signals from more than one property come back in one call -- the N+1 this '
  'package exists to remove');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      pg_temp.alerts() #> '{entity,signals}') as entry
    where entry ->> 'property_name' = 'Alpha-Haus'
  ),
  'each signal names the property it belongs to. "Lease 4B expires in 12 days" '
  'says nothing when forty buildings are in scope');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      pg_temp.alerts() #> '{entity,signals}') as entry
    where entry ->> 'type' = 'lease_expiry'
      and entry ->> 'severity' = 'critical'
  ),
  'a lease ending inside 30 days is critical -- the severity ladder survived '
  'the move');

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.alerts() #> '{entity,signals}') as entry
   where entry ->> 'type' = 'stale_rent_roll'),
  2,
  'stale_rent_roll reports once per property, not once for the workspace. It '
  'was a bare NOT EXISTS that could only ever emit one row, because the caller '
  'had already named the property');

select is(
  pg_temp.alerts() #>> '{entity,signals,0,severity}',
  'critical',
  'criticals come first');

-- ---------------------------------------------------------------------------
-- Archived properties
-- ---------------------------------------------------------------------------

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      pg_temp.alerts() #> '{entity,signals}') as entry
    where entry ->> 'property_name' = 'Gamma-Haus'
  ),
  'the archived property is absent from the worklist');

select ok(
  exists (
    select 1 from private.operations_signal_rows(
      '31100000-0000-0000-0000-000000000001',
      '31500000-0000-0000-0000-000000000003'
    )
  ),
  'and it is absent because it was filtered, not because it has no signals: '
  'the definitions do produce rows for it');

select is(
  pg_temp.property_signals('31500000-0000-0000-0000-000000000003')
    #>> '{error,code}',
  'not_found',
  'the property-scoped read refuses it too. The exclusion is not a new policy '
  'invented by the workspace list -- it is the same `deleted_at is null` '
  'predicate the rest of the leasing surface already applies, and without it '
  'the worklist would offer signals whose detail screen will not open');

-- ---------------------------------------------------------------------------
-- Agreement with the property-scoped read: the guard on the move
-- ---------------------------------------------------------------------------

select is(
  pg_temp.workspace_keys('31500000-0000-0000-0000-000000000001'),
  pg_temp.property_keys('31500000-0000-0000-0000-000000000001'),
  'the workspace read names exactly the signals the property read does. The '
  'eight definitions were moved into one private function, and this is what '
  'fails if a future author edits one path and not the other');

select is(
  pg_temp.workspace_keys('31500000-0000-0000-0000-000000000002'),
  pg_temp.property_keys('31500000-0000-0000-0000-000000000002'),
  'for the second property too -- one match could be a coincidence of an '
  'empty set on both sides, two with different signals could not');

select ok(
  array_length(pg_temp.workspace_keys('31500000-0000-0000-0000-000000000001'), 1) >= 3,
  'and the compared sets are not empty: Alpha has an expiring lease, a '
  'vacancy without a date and a stale rent roll');

-- ---------------------------------------------------------------------------
-- Filters
-- ---------------------------------------------------------------------------

select ok(
  (select bool_and(entry ->> 'severity' = 'warning')
   from jsonb_array_elements(
     pg_temp.alerts(p_severity => 'warning') #> '{entity,signals}') as entry),
  'a severity filter returns only that severity');

select ok(
  (select count(*) from jsonb_array_elements(
     pg_temp.alerts(p_severity => 'warning') #> '{entity,signals}') as entry) > 0,
  'and it returns something -- an empty list would satisfy the assertion above '
  'without proving anything');

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.alerts(p_severity => 'critical') #> '{entity,signals}') as entry
   where entry ->> 'severity' <> 'critical'),
  0,
  'and the other severities are gone, not merely outranked');

-- Dismiss one signal so the status filter has something to bite on.
-- `signal_key` is a generated column: the parts go in and the key comes out,
-- by the same expression the read computes. Supplying the key directly is
-- refused, which is how the two sides are kept from drifting.
insert into public.operations_signal_states (
  id, workspace_id, property_id, signal_type, unit_id, lease_id,
  tenant_party_id, status, created_by, updated_by
)
select
  gen_random_uuid(),
  '31100000-0000-0000-0000-000000000001',
  '31500000-0000-0000-0000-000000000001',
  entry ->> 'type',
  (entry ->> 'unit_id')::uuid,
  (entry ->> 'lease_id')::uuid,
  (entry ->> 'tenant_party_id')::uuid,
  'dismissed',
  '31200000-0000-0000-0000-000000000001',
  '31200000-0000-0000-0000-000000000001'
from jsonb_array_elements(
  pg_temp.alerts() #> '{entity,signals}') as entry
where entry ->> 'property_id' = '31500000-0000-0000-0000-000000000001'
  and entry ->> 'type' = 'lease_expiry';

select is(
  (select count(*)::integer from jsonb_array_elements(
     pg_temp.alerts(p_status => 'dismissed') #> '{entity,signals}') as entry),
  1,
  'a status filter finds the dismissed signal');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      pg_temp.alerts(p_status => 'open') #> '{entity,signals}') as entry
    where entry ->> 'type' = 'lease_expiry'
  ),
  'and the open list no longer carries it. The acknowledgement is stored '
  'against the same signal_key the property screen writes, so dismissing on '
  'one surface holds on the other');

select ok(
  (select count(*) from jsonb_array_elements(
     pg_temp.alerts(p_status => 'open') #> '{entity,signals}') as entry) > 0,
  'while the rest of the open list is untouched');

-- ---------------------------------------------------------------------------
-- The cap
-- ---------------------------------------------------------------------------

select is(
  (pg_temp.alerts() #>> '{entity,truncated}')::boolean,
  false,
  'a list that fits is not truncated');

select is(
  jsonb_array_length(pg_temp.alerts(p_limit => 1) #> '{entity,signals}'),
  1,
  'the cap caps');

select is(
  (pg_temp.alerts(p_limit => 1) #>> '{entity,truncated}')::boolean,
  true,
  'and says so. A silently capped list is the failure mode this surface '
  'exists to avoid');

select is(
  (pg_temp.alerts(p_limit => 1) #>> '{entity,total}')::integer,
  (pg_temp.alerts() #>> '{entity,total}')::integer,
  'the total still reports what exists, not what fitted');

select is(
  pg_temp.alerts(p_limit => 1) #> '{entity,total_by_severity}',
  pg_temp.alerts() #> '{entity,total_by_severity}',
  'and so does the severity summary -- it is counted over the filtered set '
  'before the cap, because a summary of the visible page is a summary of '
  'nothing');

select is(
  (pg_temp.alerts(p_limit => 99999) #>> '{entity,limit}')::integer,
  500,
  'an unreasonable limit is clamped rather than honoured. Reading the whole '
  'tenant in one statement is not what an alert list is for');

select ok(
  (pg_temp.alerts() #>> '{entity,computed_at}')::timestamptz
  between now() - interval '1 minute' and now() + interval '1 minute',
  'the answer carries the instant it was computed at. There is no scheduler, '
  'so this is the only thing that says how fresh a deadline judgement is');

select * from finish();
rollback;
