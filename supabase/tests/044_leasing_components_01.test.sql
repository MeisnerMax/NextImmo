begin;

create extension if not exists pgtap with schema extensions;

-- LEASING-COMPONENTS-01 (V-2) / DEC-029.
--
-- Two things this file is really about, because the rest is shape.
--
-- **A gap must stay a gap.** Where no component covers a date, the read
-- returns no row — not zero, and not a fall back to the flat inception column
-- on `leases`. Every convenient alternative turns "not recorded" into "nothing
-- owed", and a settlement built on that is wrong in a direction nobody
-- notices. The assertion for it is deliberately a count of zero rows *while
-- a component for that lease exists on other dates*, because a read that
-- returned nothing for the wrong reason would pass a weaker test.
--
-- **An overlap must be impossible, not merely unusual.** Two components of the
-- same type covering one day make "the rent on 1 March" ambiguous, and an
-- ambiguity the database permits is one the application guesses about forever.
-- The boundary case is the one worth pinning: periods that *touch* (one ends
-- 30 June, the next starts 1 July) must be accepted, and one that overlaps by
-- a single day must not. A half-open range is what separates them, and an
-- inclusive one would have failed the first while passing the second.

select plan(42);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('public', 'lease_components', 'the component table exists');

select is(
  (select relrowsecurity from pg_class where oid = 'public.lease_components'::regclass),
  true, 'row level security is enabled'
);
select is(
  (select relforcerowsecurity from pg_class where oid = 'public.lease_components'::regclass),
  true, 'and forced, so the owner does not bypass it either'
);

select is(
  (select count(*)::integer from pg_policy
   where polrelid = 'public.lease_components'::regclass),
  1, 'exactly one policy: default deny with a single read exception'
);
select is(
  (select polcmd from pg_policy where polrelid = 'public.lease_components'::regclass),
  'r'::"char",
  'and it is a SELECT policy -- every write goes through an audited RPC'
);
select ok(
  (select pg_get_expr(polqual, polrelid) like '%has_workspace_permission%'
   from pg_policy where polrelid = 'public.lease_components'::regclass),
  'the policy binds the permission helper, which is where the AAL2 guard lives'
);

select ok(
  (select count(*) > 0 from pg_constraint
   where conrelid = 'public.lease_components'::regclass
     and contype = 'x' and conname = 'lease_components_no_overlap'),
  'the non-overlap invariant is a constraint, not a convention'
);
select ok(
  (select count(*) > 0 from pg_extension where extname = 'btree_gist'),
  'btree_gist is installed -- the exclusion constraint needs equality beside '
  'range overlap'
);

select ok(
  (select array_agg(enumlabel::text order by enumsortorder)
   from pg_enum where enumtypid = 'public.lease_component_type'::regtype)
  = array['base_rent', 'service_charge_advance', 'heating_advance',
          'parking', 'other'],
  'the five component types of the target data model, in order'
);
select ok(
  (select array_agg(enumlabel::text order by enumsortorder)
   from pg_enum where enumtypid = 'public.lease_component_vat_mode'::regtype)
  = array['exempt', 'net', 'gross'],
  'and the three VAT modes'
);

select ok(
  (select attgenerated = 's' from pg_attribute
   where attrelid = 'public.lease_components'::regclass and attname = 'validity'),
  'validity is generated, so it cannot disagree with valid_from/valid_to'
);

select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'lease_components'
     and grantee = 'authenticated'
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'authenticated holds no DML grant: the table is readable, never writable '
  'directly'
);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c1200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'components-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('c1200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'components-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('c1100000-0000-0000-0000-000000000001', 'components', 'Components');
select private.seed_workspace_role_catalog('c1100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'c1400000-0000-0000-0000-000000000001',
  'c1100000-0000-0000-0000-000000000001',
  'c1200000-0000-0000-0000-000000000001',
  role.id, 'active'
from public.roles as role
where role.workspace_id = 'c1100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'c1500000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
  'Komponentenhaus', 'Komponentenweg 1', '10115', 'Berlin', 'de',
  'residential', 2,
  'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('c1600000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
   'c1500000-0000-0000-0000-000000000001', 'A-01', 'occupied',
   'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'),
  ('c1600000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001',
   'c1500000-0000-0000-0000-000000000001', 'A-02', 'occupied',
   'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001');

-- Two leases: one live, and one that ended in June. The second exists so the
-- as-of read has something to *exclude* -- a component whose lease was over is
-- the LEASING-ASOF-01 defect in its second form.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  ('c1700000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
   'c1500000-0000-0000-0000-000000000001', 'c1600000-0000-0000-0000-000000000001',
   'Laufend', 'active', date '2026-01-01', date '2026-12-31', null, null,
   1000, 'EUR',
   'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'),
  ('c1700000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001',
   'c1500000-0000-0000-0000-000000000001', 'c1600000-0000-0000-0000-000000000002',
   'Beendet', 'ended', date '2026-01-01', date '2026-06-30', date '2026-06-30',
   timestamptz '2026-07-01 09:00+00', 900, 'EUR',
   'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Invariants, exercised directly. These are the rules the RPCs rely on; if a
-- row can reach the table another way, they still hold.
-- ---------------------------------------------------------------------------

select lives_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from, valid_to,
    amount, currency_code, created_by, updated_by
  ) values
    ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
     'base_rent', date '2026-01-01', date '2026-06-30', 1000, 'EUR',
     'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'),
    ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
     'base_rent', date '2026-07-01', date '2026-08-31', 1080, 'EUR',
     'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001')
$$, 'periods that touch are accepted -- the range is half-open, so 30 June and '
    '1 July do not collide');

select lives_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from,
    amount, currency_code, created_by, updated_by
  ) values (
    'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
    'heating_advance', date '2026-01-01', 90, 'EUR',
    'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
  )
$$, 'a different component type may cover the same days');

select throws_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from, valid_to,
    amount, currency_code, created_by, updated_by
  ) values (
    'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
    'base_rent', date '2026-06-30', date '2026-07-31', 1, 'EUR',
    'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
  )
$$, '23P01',
  null,
  'a single overlapping day is refused -- this is the boundary an inclusive '
  'range would have got wrong');

select throws_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from,
    amount, currency_code, created_by, updated_by
  ) values (
    'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
    'parking', date '2026-01-01', 50, 'CHF',
    'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
  )
$$, '23514', null,
  'a component may not carry a currency the lease does not');

select throws_ok($$
  insert into public.lease_components (
    workspace_id, lease_id, component_type, valid_from,
    amount, currency_code, vat_mode, created_by, updated_by
  ) values (
    'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001',
    'parking', date '2026-01-01', 50, 'EUR', 'net',
    'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
  )
$$, '23514', null,
  'a net amount without a rate is refused: it cannot be turned into a gross '
  'figure, so storing it would only look like information');

select throws_ok($$
  update public.lease_components set component_type = 'parking'
  where component_type = 'heating_advance'
$$, '23000', null,
  'the component type is immutable -- relabelling a row would silently move '
  'money between categories in every past reading');

-- ---------------------------------------------------------------------------
-- Read contract
-- ---------------------------------------------------------------------------

select has_function('public', 'lease_components_as_of',
  'the as-of read exists');
select ok(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'lease_components_as_of'),
  'it is security definer, so the permission check inside it is the boundary'
);
select is(
  (select pg_get_function_result(function.oid) from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public' and function.proname = 'lease_components_as_of'),
  'jsonb',
  'and it answers in the same envelope as every other public read, so a '
  'refusal arrives as a typed code rather than as a SQLSTATE the adapter has '
  'to special-case'
);

create or replace function pg_temp.as_user(p_user uuid, p_statement text)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  execute p_statement into v_result;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

create or replace function pg_temp.components_of(
  p_user uuid, p_as_of text, p_lease uuid
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(p_user, format(
    $q$select public.lease_components_as_of(
      %L::uuid, %L::date, %L::uuid)$q$,
    'c1100000-0000-0000-0000-000000000001', p_as_of, p_lease));
$$;

select is(
  pg_temp.as_user(
    'c1200000-0000-0000-0000-000000000001',
    $inner$select public.lease_components_as_of(
      'c1100000-0000-0000-0000-000000000001'::uuid, date '2026-03-15')
      #> '{error,code}'$inner$),
  to_jsonb('validation_failed'::text),
  'an unscoped read is refused: returning every component in the workspace is '
  'the client-side-full-dataset shape the brief forbids');

select is(
  pg_temp.components_of(
    'c1200000-0000-0000-0000-000000000002', '2026-03-15',
    'c1700000-0000-0000-0000-000000000001') #> '{error,code}',
  to_jsonb('forbidden'::text),
  'and so is a read by someone with no membership in the workspace');

select is(
  (select to_jsonb(sum((component ->> 'amount')::numeric))
   from jsonb_array_elements(
     pg_temp.components_of(
       'c1200000-0000-0000-0000-000000000001', '2026-03-15',
       'c1700000-0000-0000-0000-000000000001') #> '{entity,components}'
   ) as component),
  to_jsonb(1090::numeric),
  'on a date inside both periods the read returns base rent and heating '
  'advance, and nothing else'
);

select is(
  pg_temp.components_of(
    'c1200000-0000-0000-0000-000000000001', '2026-03-15',
    'c1700000-0000-0000-0000-000000000001') #> '{entity,as_of_date}',
  to_jsonb('2026-03-15'::text),
  'the answer names the date it is true on -- a set of amounts without it is '
  'the misreading LEASING-ASOF-01 exists to prevent'
);

select is(
  (select to_jsonb(count(*))
   from jsonb_array_elements(
     pg_temp.components_of(
       'c1200000-0000-0000-0000-000000000001', '2026-11-15',
       'c1700000-0000-0000-0000-000000000001') #> '{entity,components}'
   ) as component
   where component ->> 'component_type' = 'base_rent'),
  to_jsonb(0),
  'after the last base-rent period ends the read returns no base rent -- a '
  'gap is a gap (DEC-029), not a zero and not the flat column'
);

-- The assertion above would also pass if the read returned nothing at all, for
-- any reason. This is the one that makes it mean what it claims: on the same
-- date the open-ended heating advance is still there, so the read works and
-- base rent alone is missing.
select is(
  (select to_jsonb(count(*))
   from jsonb_array_elements(
     pg_temp.components_of(
       'c1200000-0000-0000-0000-000000000001', '2026-11-15',
       'c1700000-0000-0000-0000-000000000001') #> '{entity,components}'
   ) as component),
  to_jsonb(1),
  'and the read is not simply empty on that date: the open-ended heating '
  'advance still reports, so the missing base rent is a gap and not a failure'
);

-- The ended lease gets its own component, so the exclusion below is about the
-- lease being over rather than about there being nothing to find.
insert into public.lease_components (
  workspace_id, lease_id, component_type, valid_from,
  amount, currency_code, created_by, updated_by
) values (
  'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000002',
  'base_rent', date '2026-01-01', 900, 'EUR',
  'c1200000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001'
);

select is(
  (select to_jsonb(count(*))
   from jsonb_array_elements(
     pg_temp.components_of(
       'c1200000-0000-0000-0000-000000000001', '2026-03-15',
       'c1700000-0000-0000-0000-000000000002') #> '{entity,components}'
   ) as component),
  to_jsonb(1),
  'a lease that has since ended still reports for a date it covered');

select is(
  (select to_jsonb(count(*))
   from jsonb_array_elements(
     pg_temp.components_of(
       'c1200000-0000-0000-0000-000000000001', '2026-09-15',
       'c1700000-0000-0000-0000-000000000002') #> '{entity,components}'
   ) as component),
  to_jsonb(0),
  'but not for a date after it ended, even though its component is open-ended '
  '-- the component outliving the lease is the second form of the as-of defect'
);

-- ---------------------------------------------------------------------------
-- Write contract
-- ---------------------------------------------------------------------------

create temporary table component_results (key text primary key, result jsonb);

insert into component_results (key, result)
select 'create', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.create_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    'c1700000-0000-0000-0000-000000000001'::uuid,
    'parking'::public.lease_component_type, date '2026-01-01', 45,
    'c1800000-0000-0000-0000-000000000001'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result -> 'ok' from component_results where key = 'create'),
  to_jsonb(true), 'a component can be created through the command');

select is(
  (select count(*)::integer from public.audit_events
   where entity_type = 'lease_component' and action = 'lease_component.create'),
  1, 'and it writes one audit event under its own action');

select isnt(
  (select result #>> '{entity,id}' from component_results where key = 'create'),
  null,
  'the created row travels under `entity`, the key every other leasing command '
  'uses and the one `claim_leasing_mutation` replays under');

insert into component_results (key, result)
select 'overlap', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.create_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    'c1700000-0000-0000-0000-000000000001'::uuid,
    'parking'::public.lease_component_type, date '2026-05-01', 60,
    'c1800000-0000-0000-0000-000000000002'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result #>> '{error,code}' from component_results where key = 'overlap'),
  'dependency_conflict',
  'an overlapping period comes back as a typed refusal, not a raw constraint '
  'error');

select is(
  (select count(*)::integer from public.mutation_receipts
   where mutation_id = 'c1800000-0000-0000-0000-000000000002'),
  0,
  'and the rejected command leaves no receipt behind -- otherwise a retry '
  'would be answered with a success it never got');

insert into component_results (key, result)
select 'update', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.update_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    (select id from public.lease_components
     where component_type = 'parking'
       and lease_id = 'c1700000-0000-0000-0000-000000000001'),
    1::bigint, jsonb_build_object('amount', '55'),
    'c1800000-0000-0000-0000-000000000003'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result #>> '{entity,version}' from component_results where key = 'update'),
  '2', 'an update bumps the version');

insert into component_results (key, result)
select 'stale', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.update_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    (select id from public.lease_components
     where component_type = 'parking'
       and lease_id = 'c1700000-0000-0000-0000-000000000001'),
    1::bigint, jsonb_build_object('amount', '99'),
    'c1800000-0000-0000-0000-000000000004'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result #>> '{error,code}' from component_results where key = 'stale'),
  'version_conflict', 'a stale expected version is refused');

insert into component_results (key, result)
select 'unknown', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.update_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    (select id from public.lease_components
     where component_type = 'parking'
       and lease_id = 'c1700000-0000-0000-0000-000000000001'),
    2::bigint, jsonb_build_object('amountt', '55'),
    'c1800000-0000-0000-0000-000000000005'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result #>> '{error,code}' from component_results where key = 'unknown'),
  'validation_failed',
  'a misspelled field is refused rather than ignored -- silently dropping it '
  'would report a change that never happened');

insert into component_results (key, result)
select 'close', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.close_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    (select id from public.lease_components
     where component_type = 'parking'
       and lease_id = 'c1700000-0000-0000-0000-000000000001'),
    2::bigint, date '2026-04-30',
    'c1800000-0000-0000-0000-000000000006'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

select is(
  (select result #>> '{entity,valid_to}' from component_results where key = 'close'),
  '2026-04-30', 'closing sets the end date instead of deleting the row');

select is(
  (select count(*)::integer from public.audit_events
   where entity_type = 'lease_component' and action = 'lease_component.close'),
  1,
  'and it is its own audit action: "closed on 30 April" and "changed the end '
  'date" read differently a year later');

insert into component_results (key, result)
select 'replay', pg_temp.as_user(
  'c1200000-0000-0000-0000-000000000001',
  $inner$select public.create_lease_component(
    'c1100000-0000-0000-0000-000000000001'::uuid,
    'c1700000-0000-0000-0000-000000000001'::uuid,
    'parking'::public.lease_component_type, date '2026-01-01', 45,
    'c1800000-0000-0000-0000-000000000001'::uuid,
    'c1900000-0000-0000-0000-000000000001'::uuid)$inner$);

-- Not a null check. An earlier version of this assertion only required the
-- replay to "answer rather than error", and said in its own comment that the
-- shape did not matter -- which is exactly how migration 54 shipped answering
-- `data` on a first call and `entity` on a retry, because the replay is
-- produced by `claim_leasing_mutation` and always used `entity`. A retry has
-- to be indistinguishable from the original, so the check is that it returns
-- the same row.
select is(
  (select result #>> '{entity,id}' from component_results where key = 'replay'),
  (select result #>> '{entity,id}' from component_results where key = 'create'),
  'a replayed mutation returns the same entity, in the same shape as the '
  'original -- an idempotent command that answers differently on the retry is '
  'not idempotent in any way a caller can use');

select is(
  (select count(*)::integer from public.lease_components
   where component_type = 'parking'
     and lease_id = 'c1700000-0000-0000-0000-000000000001'),
  1,
  'and it creates no second row: the replay is answered from the receipt');

select is(
  (select count(*)::integer
   from information_schema.role_routine_grants
   where routine_schema = 'public'
     and routine_name in ('create_lease_component', 'update_lease_component',
                          'close_lease_component', 'lease_components_as_of')
     and grantee = 'anon'),
  0, 'anon reaches none of the four functions');

select * from finish();
rollback;
