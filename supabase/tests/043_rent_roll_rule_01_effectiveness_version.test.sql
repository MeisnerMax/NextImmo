begin;

create extension if not exists pgtap with schema extensions;

-- RENT-ROLL-RULE-01 / follow-up 4 from DEC-027.
--
-- A frozen rent roll must say which effectiveness rule produced its figures,
-- because LEASING-ASOF-01 changed that rule and two snapshots taken either side
-- of it differ for the same property and the same `as_of_date`. What is pinned
-- here, in the order it matters:
--
--   * the version is one constant, not a literal repeated at two call sites;
--   * a snapshot written now carries it, and the number matches the behaviour
--     the figures actually show -- asserted together, so bumping the constant
--     without changing the predicate, or the reverse, fails here;
--   * "unlabelled" stays representable and is NOT what a new row gets. That
--     distinction is the whole package: null means the rule was never recorded,
--     and a row written today must never read that way.

select plan(24);

-- ---------------------------------------------------------------------------
-- The constant.
-- ---------------------------------------------------------------------------

select has_function('private', 'rent_roll_effectiveness_rule_version',
  'the rule version is declared as a function, so it has exactly one home');
select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'rent_roll_effectiveness_rule_version'),
  'i'::"char",
  'it is immutable: a constant about the code, not a lookup'
);
select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'rent_roll_effectiveness_rule_version'
     and function.prosecdef),
  0,
  'and needs no security definer, so it adds nothing to the privileged surface'
);
select is(
  private.rent_roll_effectiveness_rule_version(),
  2,
  'the current rule is 2 -- LEASING-ASOF-01 / DEC-027'
);

-- ---------------------------------------------------------------------------
-- The column, and what null is allowed to mean.
-- ---------------------------------------------------------------------------

select has_column('public', 'rent_roll_snapshots', 'effectiveness_rule_version',
  'the frozen header carries the marker');
select col_type_is('public', 'rent_roll_snapshots', 'effectiveness_rule_version',
  'integer',
  'a monotonic integer, not a reference to a definition entity: this rule is '
  'NexImmo''s and identical in every workspace');
select col_is_null('public', 'rent_roll_snapshots', 'effectiveness_rule_version',
  'nullable, because the rows written before this migration cannot be labelled '
  'truthfully -- migration 50 opened rule 2 and nothing on a row separates the '
  'two eras');
select ok(
  (select pg_get_expr(default_expression.adbin, default_expression.adrelid)
     like '%rent_roll_effectiveness_rule_version%'
   from pg_attrdef as default_expression
   join pg_attribute as column_definition
     on column_definition.attrelid = default_expression.adrelid
     and column_definition.attnum = default_expression.adnum
   where default_expression.adrelid = 'public.rent_roll_snapshots'::regclass
     and column_definition.attname = 'effectiveness_rule_version'),
  'the default is the constant itself, so an omission cannot produce the null '
  'that means "written before the marker existed"'
);
select hasnt_column('public', 'rent_roll_snapshot_lines',
  'effectiveness_rule_version',
  'the lines do not repeat it: they belong to one header and came from the '
  'same evaluation, so a second copy could only agree or be wrong');

-- ---------------------------------------------------------------------------
-- Fixture: one property, two units, two leases -- one running past its planned
-- end, one that has since ended. Both are the DEC-027 cases, so the figures
-- below are only correct under rule 2.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b9200000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ruleversion-admin@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('b9100000-0000-0000-0000-000000000001', 'ruleversion', 'Rule Version');
select private.seed_workspace_role_catalog('b9100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  'b9400000-0000-0000-0000-000000000001',
  'b9100000-0000-0000-0000-000000000001',
  'b9200000-0000-0000-0000-000000000001',
  role.id,
  'active'
from public.roles as role
where role.workspace_id = 'b9100000-0000-0000-0000-000000000001'
  and role.key = 'admin';

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values (
  'b9500000-0000-0000-0000-000000000001', 'b9100000-0000-0000-0000-000000000001',
  'Regelhaus', 'Regelweg 1', '10115', 'Berlin', 'de', 'residential', 2,
  'b9200000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001'
);

insert into public.units (
  id, workspace_id, property_id, unit_code, status, created_by, updated_by
) values
  ('b9600000-0000-0000-0000-000000000001', 'b9100000-0000-0000-0000-000000000001',
   'b9500000-0000-0000-0000-000000000001', 'A-01', 'occupied',
   'b9200000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001'),
  ('b9600000-0000-0000-0000-000000000002', 'b9100000-0000-0000-0000-000000000001',
   'b9500000-0000-0000-0000-000000000001', 'A-02', 'occupied',
   'b9200000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001');

insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  -- Active, past its planned end. Rule 1 dropped it; rule 2 counts it.
  ('b9700000-0000-0000-0000-000000000001', 'b9100000-0000-0000-0000-000000000001',
   'b9500000-0000-0000-0000-000000000001', 'b9600000-0000-0000-0000-000000000001',
   'Abgelaufen, laeuft weiter', 'active',
   date '2025-01-01', date '2025-12-31', null, null,
   1000.00, 'EUR',
   'b9200000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001'),
  -- Ended since, but in force on the reporting date. Rule 1 dropped it too.
  ('b9700000-0000-0000-0000-000000000002', 'b9100000-0000-0000-0000-000000000001',
   'b9500000-0000-0000-0000-000000000001', 'b9600000-0000-0000-0000-000000000002',
   'Beendet', 'ended',
   date '2026-01-01', date '2026-06-30', null, timestamptz '2026-07-02 09:00+00',
   700.00, 'EUR',
   'b9200000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- A raw header row, to establish what the column permits. `authenticated` holds
-- no insert grant on this table, so this runs as the migration role -- which is
-- the point: even the privileged path cannot produce an unlabelled row by
-- accident, only by saying so.
-- ---------------------------------------------------------------------------

insert into public.rent_roll_snapshots (
  workspace_id, property_id, as_of_date, currency_code, unit_count,
  occupied_unit_count, vacant_unit_count, offline_unit_count,
  effective_lease_count, total_base_rent_monthly,
  total_ancillary_charges_monthly, total_parking_other_charges_monthly,
  total_rent_monthly, created_by
) values (
  'b9100000-0000-0000-0000-000000000001', 'b9500000-0000-0000-0000-000000000001',
  date '2026-03-31', 'EUR', 2, 2, 0, 0, 2, 1700.00, 0, 0, 1700.00,
  'b9200000-0000-0000-0000-000000000001'
);

select is(
  (select effectiveness_rule_version from public.rent_roll_snapshots
   where property_id = 'b9500000-0000-0000-0000-000000000001'
     and as_of_date = date '2026-03-31'),
  2,
  'a writer that omits the column gets the current version, not the null that '
  'would claim the row predates the marker'
);

insert into public.rent_roll_snapshots (
  workspace_id, property_id, as_of_date, currency_code, unit_count,
  occupied_unit_count, vacant_unit_count, offline_unit_count,
  effective_lease_count, total_base_rent_monthly,
  total_ancillary_charges_monthly, total_parking_other_charges_monthly,
  total_rent_monthly, created_by, effectiveness_rule_version
) values (
  'b9100000-0000-0000-0000-000000000001', 'b9500000-0000-0000-0000-000000000001',
  date '2026-01-31', 'EUR', 2, 2, 0, 0, 0, 0, 0, 0, 0,
  'b9200000-0000-0000-0000-000000000001', null
);

select ok(
  (select effectiveness_rule_version is null from public.rent_roll_snapshots
   where property_id = 'b9500000-0000-0000-0000-000000000001'
     and as_of_date = date '2026-01-31'),
  'and "unlabelled" stays representable, which is what every row written '
  'before this migration is'
);

select throws_ok(
  $$insert into public.rent_roll_snapshots (
      workspace_id, property_id, as_of_date, currency_code, unit_count,
      occupied_unit_count, vacant_unit_count, offline_unit_count,
      effective_lease_count, total_base_rent_monthly,
      total_ancillary_charges_monthly, total_parking_other_charges_monthly,
      total_rent_monthly, created_by, effectiveness_rule_version
    ) values (
      'b9100000-0000-0000-0000-000000000001',
      'b9500000-0000-0000-0000-000000000001',
      date '2026-02-28', 'EUR', 2, 2, 0, 0, 0, 0, 0, 0, 0,
      'b9200000-0000-0000-0000-000000000001', 0
    )$$,
  '23514',
  null,
  'versions are counted from one: a zero is not an era, it is a mistake'
);

-- ---------------------------------------------------------------------------
-- Through the command and the read port.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.as_admin(p_statement text)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', 'b9200000-0000-0000-0000-000000000001',
      'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  execute p_statement into v_result;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

create temporary table rule_version_results (key text primary key, result jsonb);

insert into rule_version_results (key, result)
select 'snapshot', pg_temp.as_admin(
  $$select public.create_rent_roll_snapshot(
      'b9100000-0000-0000-0000-000000000001',
      'b9500000-0000-0000-0000-000000000001',
      date '2026-03-15',
      'b9e00000-0000-0000-0000-000000000001',
      'b9c00000-0000-0000-0000-000000000001'
    )$$
);

select is(
  (select result ->> 'ok' from rule_version_results where key = 'snapshot'),
  'true',
  'the snapshot command still freezes a rent roll'
);
select is(
  (select result #>> '{entity,effectiveness_rule_version}'
   from rule_version_results where key = 'snapshot'),
  '2',
  'and the returned document names the rule that produced it'
);

-- The label and the behaviour, asserted together. If somebody changes the
-- predicate without bumping the constant, or bumps the constant without
-- changing the predicate, exactly one of these two moves.
select is(
  (select (result #>> '{entity,total_rent_monthly}')::numeric
   from rule_version_results where key = 'snapshot'),
  1700.00::numeric,
  'the figures are the rule-2 figures: a lease past its end_date and a since-'
  'ended lease in force on the date both count'
);

select is(
  (select snapshot.effectiveness_rule_version
   from public.rent_roll_snapshots as snapshot
   where snapshot.id = (
     select (result #>> '{entity,id}')::uuid
     from rule_version_results where key = 'snapshot'
   )),
  2,
  'the stored row carries it too, not just the reply'
);

select is(
  (select audit.new_values #>> '{effectiveness_rule_version}'
   from public.audit_events as audit
   where audit.workspace_id = 'b9100000-0000-0000-0000-000000000001'
     and audit.entity_type = 'rent_roll_snapshot'
     and audit.entity_id = (
       select (result #>> '{entity,id}')::uuid
       from rule_version_results where key = 'snapshot'
     )),
  '2',
  'and so does the audited document, so a figure stays explicable from the '
  'trail alone'
);

-- Idempotent replay hands back the same document, version included. A replay
-- that dropped the marker would make the first and second answers differ.
insert into rule_version_results (key, result)
select 'snapshot_replay', pg_temp.as_admin(
  $$select public.create_rent_roll_snapshot(
      'b9100000-0000-0000-0000-000000000001',
      'b9500000-0000-0000-0000-000000000001',
      date '2026-03-15',
      'b9e00000-0000-0000-0000-000000000001',
      'b9c00000-0000-0000-0000-000000000001'
    )$$
);

select is(
  (select result #>> '{entity,effectiveness_rule_version}'
   from rule_version_results where key = 'snapshot_replay'),
  '2',
  'an idempotent replay returns the marker as well: the same document, not a '
  'stub'
);

insert into rule_version_results (key, result)
select 'live', pg_temp.as_admin(
  $$select public.rent_roll_live(
      'b9100000-0000-0000-0000-000000000001',
      'b9500000-0000-0000-0000-000000000001',
      date '2026-03-15'
    )$$
);

select is(
  (select result ->> 'ok' from rule_version_results where key = 'live'),
  'true',
  'the live read still answers'
);
select is(
  (select result #>> '{entity,effectiveness_rule_version}'
   from rule_version_results where key = 'live'),
  '2',
  'and states its rule too -- otherwise a client comparing a snapshot with the '
  'current stand can only guess which rule the live figure came from'
);
select is(
  (select result #>> '{entity,effectiveness_rule_version}'
   from rule_version_results where key = 'live'),
  (select result #>> '{entity,effectiveness_rule_version}'
   from rule_version_results where key = 'snapshot'),
  'a snapshot taken now and the live read agree, which is what makes a '
  'difference between them a difference in rent'
);

-- ---------------------------------------------------------------------------
-- Nothing else moved.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relname = 'rent_roll_snapshots'),
  1,
  'the column added no policy: it inherits the row-scoped lease.read select '
  'policy the table already had'
);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'rent_roll_snapshots'
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'and no write grant: a snapshot is still only ever created through the RPC'
);
select has_function('private', 'lease_is_effective_on',
  'the predicate the version names is still the one place the rule lives');

select * from finish();

rollback;
