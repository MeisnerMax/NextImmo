begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-ASOF-01b / DEC-027 follow-ups.
--
-- Both defects were uncovered: applying the migration broke nothing in the
-- 1864-assertion suite, in either direction. That is the third time in this
-- work that a green suite covered a wrong number, so both are pinned here from
-- both sides.
--
--   * `property_leasing_summary` counted the rent of a lease that had not
--     begun. Its `lease_roll` counters, which count contracts rather than
--     money, deliberately keep counting it.
--   * `operations_signals` dropped an expiring lease from the ladder on the
--     day it passed its end date -- the one state that always needs a human.

select plan(16);

-- ---------------------------------------------------------------------------
-- Fixture: three leases, one per case, on three units.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a2100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'asofb@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('a1100000-0000-0000-0000-000000000001', 'asofb', 'As Of B');
select private.seed_workspace_role_catalog('a1100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'a4100000-0000-0000-0000-000000000001',
  'a1100000-0000-0000-0000-000000000001',
  'a2100000-0000-0000-0000-000000000001',
  role.id,
  'active'
from public.roles as role
where role.workspace_id = 'a1100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'a5100000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
  'Folgehaus', 'Nachtragweg 2', '10115', 'Berlin', 'de', 'residential', 3,
  'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('a6100000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'B-01', 'occupied',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001'),
  ('a6100000-0000-0000-0000-000000000002', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'B-02', 'occupied',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001'),
  ('a6100000-0000-0000-0000-000000000003', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'B-03', 'occupied',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001');

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, base_rent_monthly, currency_code, created_by, updated_by
) values
  -- Running, and ending inside the 180-day window: the control that shows the
  -- expiry ladder still works.
  ('a7100000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'a6100000-0000-0000-0000-000000000001',
   'Laufend', 'active',
   current_date - 200, current_date + 60, 1000.00, 'EUR',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001'),
  -- Signed and activated, but its term starts next month.
  ('a7100000-0000-0000-0000-000000000002', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'a6100000-0000-0000-0000-000000000002',
   'Beginnt spaeter', 'active',
   current_date + 30, current_date + 395, 555.00, 'EUR',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001'),
  -- Term ran out 40 days ago and nobody acted.
  ('a7100000-0000-0000-0000-000000000003', 'a1100000-0000-0000-0000-000000000001',
   'a5100000-0000-0000-0000-000000000001', 'a6100000-0000-0000-0000-000000000003',
   'Abgelaufen, laeuft weiter', 'active',
   current_date - 800, current_date - 40, 800.00, 'EUR',
   'a2100000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001');

create or replace function pg_temp.as_admin(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', 'a2100000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text, true
  );
  execute p_sql into v;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

create or replace function pg_temp.summary() returns jsonb language sql as $$
  select pg_temp.as_admin(
    'select public.property_leasing_summary(
       ''a1100000-0000-0000-0000-000000000001'',
       ''a5100000-0000-0000-0000-000000000001'')'
  );
$$;

create or replace function pg_temp.signals() returns jsonb language sql as $$
  select pg_temp.as_admin(
    'select public.operations_signals(
       ''a1100000-0000-0000-0000-000000000001'',
       ''a5100000-0000-0000-0000-000000000001'')'
  );
$$;

-- ---------------------------------------------------------------------------
-- The leasing summary.
-- ---------------------------------------------------------------------------

select is(
  (select (row ->> 'monthly_base')::numeric
   from jsonb_array_elements(pg_temp.summary() #> '{summary,rent_roll}') as row
   where row ->> 'currency_code' = 'EUR'),
  1800.00::numeric,
  'the rent roll is the running lease plus the expired-but-active one -- and '
  'not the one whose term has not started'
);
select is(
  (select (row ->> 'leases')::integer
   from jsonb_array_elements(pg_temp.summary() #> '{summary,rent_roll}') as row
   where row ->> 'currency_code' = 'EUR'),
  2,
  'two leases carry rent today, not three'
);
select is(
  (pg_temp.summary() #>> '{summary,lease_roll,active}')::integer,
  3,
  'while the lease roll still counts all three: a signed lease starting next '
  'month is a real contract, it just is not income yet'
);
select is(
  (pg_temp.summary() #>> '{summary,lease_roll,expired_open}')::integer,
  1,
  'and the expired-but-active one is still reported separately'
);

-- ---------------------------------------------------------------------------
-- The signals.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open'),
  1,
  'the expired lease produces a signal at all -- it used to vanish from the '
  'ladder on exactly the day it became actionable'
);
select is(
  (select signal ->> 'severity'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open'),
  'critical',
  'and it is critical'
);
select is(
  (select signal ->> 'lease_id'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open'),
  'a7100000-0000-0000-0000-000000000003',
  'pointing at the lease that expired'
);
select ok(
  (select signal ->> 'message'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open')
    like '%passed its end date 40 days ago%',
  'the message counts days since, not a negative countdown'
);
select ok(
  (select signal ->> 'message'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open')
    not like '%-40%',
  'and never renders "expires in -40 days"'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expiry'
     and signal ->> 'lease_id' = 'a7100000-0000-0000-0000-000000000003'),
  0,
  'the expired lease is not also an upcoming expiry: the ladder keeps meaning '
  '"a decision is coming"'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expiry'
     and signal ->> 'lease_id' = 'a7100000-0000-0000-0000-000000000001'),
  1,
  'and a lease ending inside the window still climbs it'
);

-- ---------------------------------------------------------------------------
-- Acknowledgement: the new type is accepted, and it is its own decision.
-- ---------------------------------------------------------------------------

select is(
  pg_temp.as_admin(
    'select public.update_operations_signal_status(
       ''a1100000-0000-0000-0000-000000000001'',
       ''a5100000-0000-0000-0000-000000000001'',
       ''lease_expired_open'', ''dismissed'',
       gen_random_uuid(), gen_random_uuid(),
       ''a6100000-0000-0000-0000-000000000003'',
       ''a7100000-0000-0000-0000-000000000003'',
       null, null, ''geprueft'', null)'
  ) ->> 'ok',
  'true',
  'the new signal type can be acknowledged'
);
select is(
  (select signal ->> 'status'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expired_open'),
  'dismissed',
  'and the acknowledgement sticks'
);
select is(
  (select signal ->> 'status'
   from jsonb_array_elements(pg_temp.signals() #> '{entity,signals}') as signal
   where signal ->> 'type' = 'lease_expiry'
     and signal ->> 'lease_id' = 'a7100000-0000-0000-0000-000000000001'),
  'open',
  'dismissing "it expired" does not also dismiss "it is about to expire": the '
  'key carries the signal type, and they are different decisions'
);

select is(
  (select count(*)::integer
   from pg_constraint
   where conrelid = 'public.operations_signal_states'::regclass
     and conname = 'operations_signal_states_type_check'
     and pg_get_constraintdef(oid) like '%lease_expired_open%'),
  1,
  'the table constraint knows the type too, so a state row cannot be written '
  'for a type the read never produces -- nor the reverse'
);
select is(
  pg_temp.as_admin(
    'select public.update_operations_signal_status(
       ''a1100000-0000-0000-0000-000000000001'',
       ''a5100000-0000-0000-0000-000000000001'',
       ''lease_renegotiated'', ''dismissed'',
       gen_random_uuid(), gen_random_uuid(),
       null, null, null, null, ''probe'', null)'
  ) #>> '{error,code}',
  'validation_failed',
  'and an unknown type is still refused'
);

select * from finish();

rollback;
