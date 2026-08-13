begin;

create extension if not exists pgtap with schema extensions;

select plan(116);

-- === Schema surface ===================================================

select has_table('public', 'leasing_cases', 'leasing_cases table exists');
select has_table('public', 'rent_roll_snapshots', 'rent_roll_snapshots table exists');
select has_table('public', 'rent_roll_snapshot_lines', 'rent_roll_snapshot_lines table exists');
select has_type('public', 'leasing_case_status', 'leasing_case_status enum exists');

-- STM-004 vocabulary, in the documented order.
select is(
  (select array_agg(enum.enumlabel::text order by enum.enumsortorder)
   from pg_enum as enum where enum.enumtypid = 'public.leasing_case_status'::regtype),
  array['inquiry', 'contact', 'viewing', 'documents_pending', 'screening',
        'offer', 'contract_draft', 'signed', 'handover', 'completed',
        'cancelled'],
  'leasing_case_status carries the STM-004 labels'
);

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in (
     'public.leasing_cases'::regclass,
     'public.rent_roll_snapshots'::regclass,
     'public.rent_roll_snapshot_lines'::regclass
   )),
  'all increment 2 tables enable and force RLS'
);
select policies_are('public', 'leasing_cases', array['leasing_cases_select_lease_read']);
select policies_are('public', 'rent_roll_snapshots', array['rent_roll_snapshots_select_lease_read']);
select policies_are('public', 'rent_roll_snapshot_lines', array['rent_roll_snapshot_lines_select_lease_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in (
       'leasing_cases', 'rent_roll_snapshots', 'rent_roll_snapshot_lines'
     )
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no leasing-case or rent-roll DML grants'
);

select has_function('public', 'create_leasing_case', array['uuid', 'uuid', 'text', 'uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text']);
select has_function('public', 'update_leasing_case', array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'text']);
select has_function('public', 'transition_leasing_case_status', array['uuid', 'uuid', 'bigint', 'leasing_case_status', 'uuid', 'uuid', 'uuid', 'text']);
select has_function('public', 'create_rent_roll_snapshot', array['uuid', 'uuid', 'date', 'uuid', 'uuid', 'text', 'text']);

select ok(
  (select bool_and(
     function.prosecdef and owner.rolname = 'postgres'
     and function.proconfig @> array['search_path=""']::text[]
   )
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.proname in (
       'create_leasing_case', 'update_leasing_case',
       'transition_leasing_case_status', 'create_rent_roll_snapshot'
     )),
  'increment 2 RPCs are postgres security definers with a fixed search path'
);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'create_leasing_case', 'update_leasing_case',
       'transition_leasing_case_status', 'create_rent_roll_snapshot'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute increment 2 RPCs'
);

-- The increment reuses increment 1's command plumbing instead of adding a
-- second trio; if these disappear the reuse claim in the header is false.
select has_function('private', 'leasing_command_gate', array['uuid', 'uuid', 'uuid', 'text']);
select has_function('private', 'claim_leasing_mutation', array['uuid', 'uuid', 'bytea', 'text']);
select has_function('private', 'finish_leasing_mutation', array['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'uuid', 'jsonb', 'jsonb']);
select has_function('private', 'rent_roll_unit_rows', array['uuid', 'uuid', 'date']);
select has_function('private', 'leasing_case_transition_allowed', array['leasing_case_status', 'leasing_case_status']);

-- === AGG-007 immutability, asserted structurally ======================
--
-- A snapshot must be unwritable after creation, and that must be a property of
-- the schema rather than a convention the RPCs happen to follow.

select is(
  (select count(*)::integer
   from pg_trigger as trigger_row
   where trigger_row.tgrelid = 'public.rent_roll_snapshots'::regclass
     and not trigger_row.tgisinternal),
  2,
  'AGG-007: the snapshot header carries both reject triggers'
);
select is(
  (select count(*)::integer
   from pg_trigger as trigger_row
   where trigger_row.tgrelid = 'public.rent_roll_snapshot_lines'::regclass
     and not trigger_row.tgisinternal),
  2,
  'AGG-007: the snapshot lines carry both reject triggers'
);

-- An immutable row has no second writer, so it carries no optimistic
-- concurrency token and no "who touched it last" columns.
select hasnt_column('public', 'rent_roll_snapshots', 'version');
select hasnt_column('public', 'rent_roll_snapshots', 'updated_at');
select hasnt_column('public', 'rent_roll_snapshots', 'updated_by');

-- Immutable is NOT the same claim as unique-per-period. With no delete path
-- (OPN-DOM-005 open), uniqueness would make one bad run poison a period
-- forever, so its absence is a requirement and is asserted like OPN-DOM-001 is.
select is(
  (select count(*)::integer
   from pg_index as index
   where index.indrelid = 'public.rent_roll_snapshots'::regclass
     and index.indisunique
     and 'as_of_date' = any (
       select attribute.attname
       from pg_attribute as attribute
       where attribute.attrelid = 'public.rent_roll_snapshots'::regclass
         and attribute.attnum = any (index.indkey)
     )),
  0,
  'AGG-007: snapshots are deliberately not unique per property and period'
);

-- === Fixtures =========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ca000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05i2-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05i2-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('cb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d05i2-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('c1000000-0000-0000-0000-000000000001', 'p2d05i2-workspace-a', 'P2D05 I2 Workspace A'),
  ('c2000000-0000-0000-0000-000000000001', 'p2d05i2-workspace-b', 'P2D05 I2 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('c3000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('c5000000-0000-0000-0000-000000000001', 'lease.read', 'Lease Read'),
  ('c5000000-0000-0000-0000-000000000002', 'lease.manage', 'Lease Manage'),
  ('c5000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read'),
  ('c5000000-0000-0000-0000-000000000004', 'audit.read', 'Audit Read'),
  ('c5000000-0000-0000-0000-000000000005', 'party.read', 'Party Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000003'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000004'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000005'),
  -- Reader A: lease.read only — may see cases and rent rolls, may create neither.
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000003'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002'),
  ('c2000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000003');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('c6000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'active'),
  ('c6000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'active'),
  ('c6000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('c7000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001'),
  -- A second property in the same workspace, used for the all-vacant rent roll.
  ('c7000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001',
   'Objekt Leerstand', 'Hauptstrasse 3', '10115', 'Berlin', 'de', 'residential',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001'),
  ('c7000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001',
   'Objekt B', 'Nebenstrasse 2', '20095', 'Hamburg', 'de', 'residential',
   'cb000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001');

insert into public.parties (
  id, workspace_id, party_type, display_name, created_by, updated_by
) values
  ('c8000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'person', 'Mieter Meier',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001'),
  -- Deliberately holds NO tenant role: a prospect is not a tenant yet.
  ('c8000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'person', 'Interessent ohne Mieterrolle',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001');

insert into public.party_roles (
  id, workspace_id, party_id, role_type, created_by, updated_by
) values
  ('c9000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'c8000000-0000-0000-0000-000000000001', 'tenant',
   'ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001');

create temporary table p2_d05_i2_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d05_i2_results to authenticated;

-- Advances a leasing case by one STM-004 step, reading the current version
-- itself so the tests read as statements about the pipeline rather than as
-- version bookkeeping. Deliberately NOT security definer: it must run with the
-- caller's auth.uid().
create function pg_temp.advance_case(
  p_workspace_id uuid,
  p_case_id uuid,
  p_target public.leasing_case_status,
  p_seed text,
  p_lease_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_version bigint;
begin
  select leasing_case.version into v_version
  from public.leasing_cases as leasing_case
  where leasing_case.workspace_id = p_workspace_id
    and leasing_case.id = p_case_id;

  return public.transition_leasing_case_status(
    p_workspace_id,
    p_case_id,
    v_version,
    p_target,
    md5(p_seed || '-mutation')::uuid,
    md5(p_seed || '-correlation')::uuid,
    p_lease_id,
    p_reason
  );
end;
$$;

-- Walks a lease from draft to active through the whole STM-005 chain so the
-- rent-roll tests can talk about effective leases without restating increment
-- 1's state machine each time.
create function pg_temp.activate_lease(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_seed text
)
returns jsonb
language plpgsql
as $$
declare
  v_targets public.lease_status[] := array[
    'reviewed'::public.lease_status,
    'sent'::public.lease_status,
    'tenant_signed'::public.lease_status,
    'landlord_signed'::public.lease_status,
    'active'::public.lease_status
  ];
  v_target public.lease_status;
  v_version bigint;
  v_result jsonb;
  v_step integer := 0;
begin
  foreach v_target in array v_targets loop
    v_step := v_step + 1;

    select lease.version into v_version
    from public.leases as lease
    where lease.workspace_id = p_workspace_id and lease.id = p_lease_id;

    v_result := public.transition_lease_status(
      p_workspace_id, p_lease_id, v_version, v_target,
      md5(p_seed || '-mutation-' || v_step)::uuid,
      md5(p_seed || '-correlation-' || v_step)::uuid
    );

    if v_result ->> 'ok' <> 'true' then
      return v_result;
    end if;
  end loop;

  return v_result;
end;
$$;

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

-- Units and leases the pipeline and the rent roll operate on.
insert into p2_d05_i2_results (key, result)
select 'unit_1', public.create_unit(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'EG-links', 'ce000000-0000-0000-0000-000000000001',
  'cc000000-0000-0000-0000-000000000001',
  'apartment', '0', 68.5, 3, 1, 950, 1050, 'EUR'
);
insert into p2_d05_i2_results (key, result)
select 'unit_2', public.create_unit(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'EG-rechts', 'ce000000-0000-0000-0000-000000000002',
  'cc000000-0000-0000-0000-000000000002',
  'apartment', '0', 55, 2, 1, 800, 850, 'EUR'
);
insert into p2_d05_i2_results (key, result)
select 'unit_3', public.create_unit(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'OG-links', 'ce000000-0000-0000-0000-000000000003',
  'cc000000-0000-0000-0000-000000000003',
  'apartment', '1', 72, 3, 1, 1000, 1100, 'EUR'
);
-- The all-vacant property gets exactly one unit and no lease at all.
insert into p2_d05_i2_results (key, result)
select 'unit_empty', public.create_unit(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000003',
  'Leerstand-1', 'ce000000-0000-0000-0000-000000000004',
  'cc000000-0000-0000-0000-000000000004',
  'apartment', '0', 40, 1, 1, null, null, null
);

-- === create_leasing_case ==============================================

insert into p2_d05_i2_results (key, result)
select 'case_1', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  '  Anfrage Meier  ', 'ce000000-0000-0000-0000-000000000011',
  'cc000000-0000-0000-0000-000000000011'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'case_1'), 'true', 'create_leasing_case creates a case');
select is((select result #>> '{entity,case_name}' from p2_d05_i2_results where key = 'case_1'), 'Anfrage Meier', 'the case name is trimmed');
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1'), 'inquiry', 'STM-004: a new case starts at inquiry');
select is((select result #>> '{entity,version}' from p2_d05_i2_results where key = 'case_1'), '1', 'a new case starts at version 1');
select is((select result #>> '{entity,source}' from p2_d05_i2_results where key = 'case_1'), 'other', 'the lead source defaults to other');
select is((select result #>> '{entity,unit_id}' from p2_d05_i2_results where key = 'case_1'), null, 'an inquiry may predate the choice of unit');

-- A prospect is a Party WITHOUT the tenant role — the role attaches when a
-- lease names the party, not when someone enquires.
insert into p2_d05_i2_results (key, result)
select 'case_prospect_no_role', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'Anfrage ohne Mieterrolle', 'ce000000-0000-0000-0000-000000000012',
  'cc000000-0000-0000-0000-000000000012',
  null, 'c8000000-0000-0000-0000-000000000002', 'portal'
);
select is(
  (select result ->> 'ok' from p2_d05_i2_results where key = 'case_prospect_no_role'),
  'true',
  'a prospect party needs no tenant role (unlike a lease tenant)'
);

-- A unit from a different property is a wrong pointer, not a tolerable slip.
insert into p2_d05_i2_results (key, result)
select 'case_wrong_unit', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'Falsche Einheit', 'ce000000-0000-0000-0000-000000000013',
  'cc000000-0000-0000-0000-000000000013',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_empty')
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'case_wrong_unit'), 'not_found', 'a unit of another property is rejected');
select is((select result #>> '{error,field}' from p2_d05_i2_results where key = 'case_wrong_unit'), 'unit_id', 'and the refusal names the field');

insert into p2_d05_i2_results (key, result)
select 'case_bad_source', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'Unbekannte Quelle', 'ce000000-0000-0000-0000-000000000014',
  'cc000000-0000-0000-0000-000000000014', null, null, 'telepathy'
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'case_bad_source'), 'validation_failed', 'an unknown lead source is rejected');

-- === STM-004: the chain is strictly one step forward ==================

select is(
  (select pg_temp.advance_case(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
     'viewing'::public.leasing_case_status, 'skip-a-stage'
   ) #>> '{error,code}'),
  'validation_failed',
  'STM-004: skipping a stage is rejected'
);

insert into p2_d05_i2_results (key, result)
select 'case_1_contact', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'contact'::public.leasing_case_status, 'to-contact'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_contact'), 'contact', 'inquiry -> contact is allowed');
select is((select result #>> '{entity,version}' from p2_d05_i2_results where key = 'case_1_contact'), '2', 'a transition bumps the version');

select is(
  (select pg_temp.advance_case(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
     'inquiry'::public.leasing_case_status, 'go-back'
   ) #>> '{error,code}'),
  'validation_failed',
  'STM-004: there is no backward edge'
);

insert into p2_d05_i2_results (key, result)
select 'case_1_viewing', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'viewing'::public.leasing_case_status, 'to-viewing'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_viewing'), 'viewing', 'contact -> viewing is allowed');

insert into p2_d05_i2_results (key, result)
select 'case_1_documents', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'documents_pending'::public.leasing_case_status, 'to-documents'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_documents'), 'documents_pending', 'viewing -> documents_pending is allowed');

-- === Progression preconditions ========================================

insert into p2_d05_i2_results (key, result)
select 'case_1_screening_no_prospect', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'screening'::public.leasing_case_status, 'screening-no-prospect'
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'case_1_screening_no_prospect'), 'validation_failed', 'screening without a prospect is rejected');
select is((select result #>> '{error,field}' from p2_d05_i2_results where key = 'case_1_screening_no_prospect'), 'prospect_party_id', 'and the refusal names the missing prospect');

-- Naming the prospect is an ordinary attribute update, not a stage change.
insert into p2_d05_i2_results (key, result)
select 'case_1_set_prospect', public.update_leasing_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  (select (result #>> '{entity,version}')::bigint from p2_d05_i2_results where key = 'case_1_documents'),
  'ce000000-0000-0000-0000-000000000021', 'cc000000-0000-0000-0000-000000000021',
  null, null, 'c8000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'case_1_set_prospect'), 'true', 'the prospect can be named while the case is open');

insert into p2_d05_i2_results (key, result)
select 'case_1_screening', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'screening'::public.leasing_case_status, 'to-screening'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_screening'), 'screening', 'screening is allowed once a prospect is named');

insert into p2_d05_i2_results (key, result)
select 'case_1_offer_no_unit', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'offer'::public.leasing_case_status, 'offer-no-unit'
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'case_1_offer_no_unit'), 'validation_failed', 'an offer without a unit is rejected');
select is((select result #>> '{error,field}' from p2_d05_i2_results where key = 'case_1_offer_no_unit'), 'unit_id', 'and the refusal names the missing unit');

insert into p2_d05_i2_results (key, result)
select 'case_1_set_unit', public.update_leasing_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  (select (result #>> '{entity,version}')::bigint from p2_d05_i2_results where key = 'case_1_screening'),
  'ce000000-0000-0000-0000-000000000022', 'cc000000-0000-0000-0000-000000000022',
  null, (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1')
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'case_1_set_unit'), 'true', 'the unit can still be chosen at screening');

insert into p2_d05_i2_results (key, result)
select 'case_1_offer', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'offer'::public.leasing_case_status, 'to-offer'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_offer'), 'offer', 'the offer is allowed once a unit is chosen');

insert into p2_d05_i2_results (key, result)
select 'case_1_draft', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'contract_draft'::public.leasing_case_status, 'to-draft'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_draft'), 'contract_draft', 'offer -> contract_draft is allowed');

insert into p2_d05_i2_results (key, result)
select 'case_1_signed_no_lease', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'signed'::public.leasing_case_status, 'signed-no-lease'
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'case_1_signed_no_lease'), 'validation_failed', 'a signed case without a lease is rejected');
select is((select result #>> '{error,field}' from p2_d05_i2_results where key = 'case_1_signed_no_lease'), 'lease_id', 'and the refusal names the missing lease');

-- The lease the case produced.
insert into p2_d05_i2_results (key, result)
select 'lease_1', public.create_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1'),
  'Mietvertrag EG-links', date '2026-01-01', 950, 'EUR',
  'ce000000-0000-0000-0000-000000000031', 'cc000000-0000-0000-0000-000000000031',
  'c8000000-0000-0000-0000-000000000001', null, null, null, 150, 50
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'lease_1'), 'true', 'the lease behind the case is created');

insert into p2_d05_i2_results (key, result)
select 'case_1_signed', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'signed'::public.leasing_case_status, 'to-signed',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'lease_1')
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_signed'), 'signed', 'signed is allowed once the lease is named');
select is(
  (select result #>> '{entity,lease_id}' from p2_d05_i2_results where key = 'case_1_signed'),
  (select result #>> '{entity,id}' from p2_d05_i2_results where key = 'lease_1'),
  'the case points at the lease it produced'
);

insert into p2_d05_i2_results (key, result)
select 'case_1_handover', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'handover'::public.leasing_case_status, 'to-handover'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_handover'), 'handover', 'signed -> handover is allowed');

insert into p2_d05_i2_results (key, result)
select 'case_1_completed', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
  'completed'::public.leasing_case_status, 'to-completed'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_1_completed'), 'completed', 'handover -> completed closes the pipeline');
select isnt((select result #>> '{entity,completed_at}' from p2_d05_i2_results where key = 'case_1_completed'), null, 'a completed case records when it completed');
select is((select result #>> '{entity,cancelled_at}' from p2_d05_i2_results where key = 'case_1_completed'), null, 'a completed case is not also cancelled');

select is(
  (select pg_temp.advance_case(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
     'cancelled'::public.leasing_case_status, 'cancel-completed', null, 'zu spaet'
   ) #>> '{error,code}'),
  'validation_failed',
  'STM-004: nothing leaves a terminal state, not even a cancellation'
);

-- A completed case is history and is not edited in place either.
select is(
  (select public.update_leasing_case(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_1'),
     (select (result #>> '{entity,version}')::bigint from p2_d05_i2_results where key = 'case_1_completed'),
     'ce000000-0000-0000-0000-000000000041', 'cc000000-0000-0000-0000-000000000041',
     'Nachtraeglich umbenannt'
   ) #>> '{error,code}'),
  'validation_failed',
  'a completed case is not editable'
);

-- === Cancellation =====================================================

insert into p2_d05_i2_results (key, result)
select 'case_2', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  'Anfrage die scheitert', 'ce000000-0000-0000-0000-000000000051',
  'cc000000-0000-0000-0000-000000000051'
);

select is(
  (select pg_temp.advance_case(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_2'),
     'cancelled'::public.leasing_case_status, 'cancel-no-reason'
   ) #>> '{error,field}'),
  'reason',
  'cancelling without a reason is rejected'
);

-- Cancelling is exempt from the progression preconditions: it ends the case
-- where it stands, with no unit, prospect or lease named.
insert into p2_d05_i2_results (key, result)
select 'case_2_cancelled', pg_temp.advance_case(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_2'),
  'cancelled'::public.leasing_case_status, 'cancel-from-inquiry', null,
  'Interessent hat abgesagt'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'case_2_cancelled'), 'cancelled', 'a case can be cancelled straight from inquiry');
select isnt((select result #>> '{entity,cancelled_at}' from p2_d05_i2_results where key = 'case_2_cancelled'), null, 'a cancelled case records when it was cancelled');
select is((select result #>> '{entity,unit_id}' from p2_d05_i2_results where key = 'case_2_cancelled'), null, 'cancelling needs no unit, prospect or lease');

-- === Versioning, idempotency and audit ================================

select is(
  (select public.transition_leasing_case_status(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_prospect_no_role'),
     99, 'contact'::public.leasing_case_status,
     'ce000000-0000-0000-0000-000000000061', 'cc000000-0000-0000-0000-000000000061'
   ) #>> '{error,code}'),
  'version_conflict',
  'a stale expected version is refused'
);
select isnt(
  (select public.transition_leasing_case_status(
     'c1000000-0000-0000-0000-000000000001',
     (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'case_prospect_no_role'),
     99, 'contact'::public.leasing_case_status,
     'ce000000-0000-0000-0000-000000000062', 'cc000000-0000-0000-0000-000000000062'
   ) #>> '{error,current_entity,status}'),
  null,
  'the version conflict carries the current entity'
);

-- Replaying the identical command returns the original result rather than
-- creating a second case.
insert into p2_d05_i2_results (key, result)
select 'case_1_replay', public.create_leasing_case(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  '  Anfrage Meier  ', 'ce000000-0000-0000-0000-000000000011',
  'cc000000-0000-0000-0000-000000000011'
);
select is(
  (select result #>> '{entity,id}' from p2_d05_i2_results where key = 'case_1_replay'),
  (select result #>> '{entity,id}' from p2_d05_i2_results where key = 'case_1'),
  'replaying a mutation id returns the original case'
);

select is(
  (select public.create_leasing_case(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
     'Anderer Befehl, gleiche Mutation', 'ce000000-0000-0000-0000-000000000011',
     'cc000000-0000-0000-0000-000000000011'
   ) #>> '{error,code}'),
  'mutation_conflict',
  'reusing a mutation id for a different command is refused'
);

select is(
  (select count(*)::integer from public.audit_events as audit
   where audit.workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and audit.entity_type = 'leasing_case'
     and audit.action = 'leasing_case.transition'
     and audit.entity_id = (
       select (result #>> '{entity,id}')::uuid
       from p2_d05_i2_results where key = 'case_1'
     )),
  9,
  'every leasing-case transition wrote exactly one append-only audit row'
);

-- === Permissions and workspace isolation ==============================

select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000002', true);

select is(
  (select public.create_leasing_case(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
     'Leser darf nicht', 'ce000000-0000-0000-0000-000000000071',
     'cc000000-0000-0000-0000-000000000071'
   ) #>> '{error,code}'),
  'forbidden',
  'lease.read alone does not permit creating a leasing case'
);
select ok(
  (select count(*) from public.leasing_cases) > 0,
  'a lease.read holder may still read leasing cases'
);

select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.leasing_cases),
  0,
  'another workspace sees no leasing cases through RLS'
);
select is(
  (select public.create_leasing_case(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
     'Fremder Workspace', 'ce000000-0000-0000-0000-000000000072',
     'cc000000-0000-0000-0000-000000000072'
   ) #>> '{error,code}'),
  'forbidden',
  'a member of another workspace cannot create a case there'
);

select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

-- === Rent roll: OPN-DOM-001 aggregation ===============================
--
-- unit_1 gets a SECOND effective lease (Teilflaechen-Vermietung), which is the
-- decided behaviour. unit_2 stays vacant. unit_3 gets a lease whose term starts
-- after the reporting date.

insert into p2_d05_i2_results (key, result)
select 'lease_1_active', pg_temp.activate_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'lease_1'),
  'lease-1'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'lease_1_active'), 'active', 'the first lease is effective');

insert into p2_d05_i2_results (key, result)
select 'lease_2', public.create_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1'),
  'Teilflaeche Kellerraum', date '2026-02-01', 100, 'EUR',
  'ce000000-0000-0000-0000-000000000032', 'cc000000-0000-0000-0000-000000000032',
  'c8000000-0000-0000-0000-000000000001', null, null, null, 20, 10
);
insert into p2_d05_i2_results (key, result)
select 'lease_2_active', pg_temp.activate_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'lease_2'),
  'lease-2'
);
select is((select result #>> '{entity,status}' from p2_d05_i2_results where key = 'lease_2_active'), 'active', 'OPN-DOM-001: a second lease on the same unit is effective too');

-- A lease that only starts in July: effective by status, outside the March
-- reporting window by term.
insert into p2_d05_i2_results (key, result)
select 'lease_3', public.create_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_3'),
  'Mietvertrag ab Juli', date '2026-07-01', 1000, 'EUR',
  'ce000000-0000-0000-0000-000000000033', 'cc000000-0000-0000-0000-000000000033',
  'c8000000-0000-0000-0000-000000000001'
);
insert into p2_d05_i2_results (key, result)
select 'lease_3_active', pg_temp.activate_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'lease_3'),
  'lease-3'
);

insert into p2_d05_i2_results (key, result)
select 'snapshot_1', public.create_rent_roll_snapshot(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  date '2026-03-31', 'ce000000-0000-0000-0000-000000000081',
  'cc000000-0000-0000-0000-000000000081'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'snapshot_1'), 'true', 'create_rent_roll_snapshot freezes a rent roll');
select is((select result #>> '{entity,currency_code}' from p2_d05_i2_results where key = 'snapshot_1'), 'EUR', 'the currency is derived from the contributing leases');
select is((select result #>> '{entity,unit_count}' from p2_d05_i2_results where key = 'snapshot_1'), '3', 'every unit of the property gets a line');
select is((select jsonb_array_length(result #> '{entity,lines}') from p2_d05_i2_results where key = 'snapshot_1'), 3, 'the returned document carries its lines');

-- OPN-DOM-001: ONE line for unit_1, carrying the SUM of both leases.
select is(
  (select line ->> 'effective_lease_count'
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'EG-links'),
  '2',
  'OPN-DOM-001: the unit with two effective leases has one line counting both'
);
select is(
  (select (line ->> 'base_rent_monthly')::numeric
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'EG-links'),
  1050::numeric,
  'OPN-DOM-001: the per-unit base rent is the sum over both leases'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'EG-links'),
  1280::numeric,
  'the per-unit total sums base, ancillary and parking across both leases'
);

-- The vacant unit is present with zeros rather than missing: a rent roll that
-- silently omitted vacancy could not produce an occupancy rate.
select is(
  (select line ->> 'effective_lease_count'
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'EG-rechts'),
  '0',
  'a vacant unit still gets a line'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'EG-rechts'),
  0::numeric,
  'and it carries no rent'
);

-- The documented asymmetry: occupied by AGG-004, zero in a snapshot whose
-- as_of_date falls outside the lease term. The frozen status makes it legible.
select is(
  (select line ->> 'unit_status'
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'OG-links'),
  'occupied',
  'a unit let from July is occupied by AGG-004 already'
);
select is(
  (select (line ->> 'total_rent_monthly')::numeric
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1' and line ->> 'unit_code' = 'OG-links'),
  0::numeric,
  'but contributes nothing to a March rent roll (term outside the window)'
);
select is(
  (select result #>> '{entity,occupied_unit_count}' from p2_d05_i2_results where key = 'snapshot_1'),
  '2',
  'the occupancy counters follow AGG-004, not the date window'
);

-- === AGG-007 reproducibility ==========================================

select is(
  (select (result #>> '{entity,total_rent_monthly}')::numeric
   from p2_d05_i2_results where key = 'snapshot_1'),
  (select sum((line ->> 'total_rent_monthly')::numeric)
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1'),
  'AGG-007: the header total is exactly the sum of the frozen lines'
);
select is(
  (select (result #>> '{entity,effective_lease_count}')::integer
   from p2_d05_i2_results where key = 'snapshot_1'),
  (select sum((line ->> 'effective_lease_count')::integer)::integer
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1'),
  'AGG-007: the header lease count is exactly the sum of the frozen lines'
);
select is(
  (select
     (result #>> '{entity,occupied_unit_count}')::integer
     + (result #>> '{entity,vacant_unit_count}')::integer
     + (result #>> '{entity,offline_unit_count}')::integer
   from p2_d05_i2_results where key = 'snapshot_1'),
  (select (result #>> '{entity,unit_count}')::integer
   from p2_d05_i2_results where key = 'snapshot_1'),
  'AGG-007: the occupancy counters partition the units'
);

-- Renaming the unit afterwards must not rewrite what a past rent roll said.
insert into p2_d05_i2_results (key, result)
select 'unit_1_renamed', public.update_unit(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1'),
  (select unit.version from public.units as unit
   where unit.id = (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1')),
  jsonb_build_object('unit_code', 'EG-links-neu'),
  'ce000000-0000-0000-0000-000000000091', 'cc000000-0000-0000-0000-000000000091'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'unit_1_renamed'), 'true', 'the unit is renamed after the snapshot');
select is(
  (select line.unit_code from public.rent_roll_snapshot_lines as line
   where line.snapshot_id = (
     select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'snapshot_1'
   )
     and line.unit_id = (
       select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_1'
     )),
  'EG-links',
  'AGG-007: the frozen line keeps the unit code it was taken with'
);

-- === AGG-007 immutability, at runtime =================================

set local role postgres;

select throws_ok(
  format(
    'update public.rent_roll_snapshots set as_of_date = date ''2026-12-31'' where id = %L',
    (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'snapshot_1')
  ),
  'P0001',
  'rent roll snapshots are immutable (AGG-007)',
  'AGG-007: a snapshot header cannot be updated, even by the owner'
);
select throws_ok(
  format(
    'delete from public.rent_roll_snapshots where id = %L',
    (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'snapshot_1')
  ),
  'P0001',
  'rent roll snapshots are immutable (AGG-007)',
  'AGG-007: a snapshot header cannot be deleted'
);
select throws_ok(
  format(
    'update public.rent_roll_snapshot_lines set base_rent_monthly = 0 where snapshot_id = %L',
    (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'snapshot_1')
  ),
  'P0001',
  'rent roll snapshots are immutable (AGG-007)',
  'AGG-007: a snapshot line cannot be updated'
);
select throws_ok(
  format(
    'delete from public.rent_roll_snapshot_lines where snapshot_id = %L',
    (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'snapshot_1')
  ),
  'P0001',
  'rent roll snapshots are immutable (AGG-007)',
  'AGG-007: a snapshot line cannot be deleted'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);

-- === A second snapshot for the same period is lawful ==================

insert into p2_d05_i2_results (key, result)
select 'snapshot_1_again', public.create_rent_roll_snapshot(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  date '2026-03-31', 'ce000000-0000-0000-0000-000000000082',
  'cc000000-0000-0000-0000-000000000082'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'snapshot_1_again'), 'true', 'a second snapshot for the same property and period is allowed');
select isnt(
  (select result #>> '{entity,id}' from p2_d05_i2_results where key = 'snapshot_1_again'),
  (select result #>> '{entity,id}' from p2_d05_i2_results where key = 'snapshot_1'),
  'and it is a distinct, separately frozen document'
);
select is(
  (select line ->> 'unit_code'
   from p2_d05_i2_results,
        jsonb_array_elements(result #> '{entity,lines}') as line
   where key = 'snapshot_1_again' and line ->> 'unit_status' = 'vacant'),
  'EG-rechts',
  'the re-run reflects the data as it stands now, not as the first run froze it'
);

-- Replaying the snapshot command returns the identical frozen document,
-- lines included, rather than a header-only stub.
select is(
  (select public.create_rent_roll_snapshot(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
     date '2026-03-31', 'ce000000-0000-0000-0000-000000000081',
     'cc000000-0000-0000-0000-000000000081'
   ) #> '{entity}'),
  (select result #> '{entity}' from p2_d05_i2_results where key = 'snapshot_1'),
  'replaying a snapshot mutation id returns the identical document'
);

-- === Currency handling ================================================

insert into p2_d05_i2_results (key, result)
select 'lease_chf', public.create_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'unit_2'),
  'Vertrag in Franken', date '2026-01-01', 900, 'CHF',
  'ce000000-0000-0000-0000-000000000034', 'cc000000-0000-0000-0000-000000000034',
  'c8000000-0000-0000-0000-000000000001'
);
insert into p2_d05_i2_results (key, result)
select 'lease_chf_active', pg_temp.activate_lease(
  'c1000000-0000-0000-0000-000000000001',
  (select (result #>> '{entity,id}')::uuid from p2_d05_i2_results where key = 'lease_chf'),
  'lease-chf'
);

insert into p2_d05_i2_results (key, result)
select 'snapshot_mixed', public.create_rent_roll_snapshot(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001',
  date '2026-03-31', 'ce000000-0000-0000-0000-000000000083',
  'cc000000-0000-0000-0000-000000000083'
);
select is((select result #>> '{error,code}' from p2_d05_i2_results where key = 'snapshot_mixed'), 'currency_mismatch', 'DEC-011: mixed currencies are refused, not summed');
select is(
  (select result #>> '{error,currencies}' from p2_d05_i2_results where key = 'snapshot_mixed'),
  '["CHF", "EUR"]',
  'and the refusal names the currencies it found'
);

-- An all-vacant property implies no currency, so one must be passed.
insert into p2_d05_i2_results (key, result)
select 'snapshot_empty_no_currency', public.create_rent_roll_snapshot(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000003',
  date '2026-03-31', 'ce000000-0000-0000-0000-000000000084',
  'cc000000-0000-0000-0000-000000000084'
);
select is((select result #>> '{error,field}' from p2_d05_i2_results where key = 'snapshot_empty_no_currency'), 'currency_code', 'an implied currency is never guessed');

insert into p2_d05_i2_results (key, result)
select 'snapshot_empty', public.create_rent_roll_snapshot(
  'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000003',
  date '2026-03-31', 'ce000000-0000-0000-0000-000000000085',
  'cc000000-0000-0000-0000-000000000085', 'EUR'
);
select is((select result ->> 'ok' from p2_d05_i2_results where key = 'snapshot_empty'), 'true', 'an all-vacant property still gets a rent roll');
select is((select result #>> '{entity,total_rent_monthly}' from p2_d05_i2_results where key = 'snapshot_empty'), '0', 'and it is all zeros');
select is((select result #>> '{entity,vacant_unit_count}' from p2_d05_i2_results where key = 'snapshot_empty'), '1', 'with its vacancy counted');

-- === Rent roll permissions and isolation ==============================

select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000002', true);
select is(
  (select public.create_rent_roll_snapshot(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000003',
     date '2026-04-30', 'ce000000-0000-0000-0000-000000000086',
     'cc000000-0000-0000-0000-000000000086', 'EUR'
   ) #>> '{error,code}'),
  'forbidden',
  'lease.read alone does not permit freezing a rent roll'
);
select ok(
  (select count(*) from public.rent_roll_snapshot_lines) > 0,
  'a lease.read holder may read the frozen lines'
);

select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from public.rent_roll_snapshots),
  0,
  'another workspace sees no rent rolls through RLS'
);

select set_config('request.jwt.claim.sub', 'ca000000-0000-0000-0000-000000000001', true);
select is(
  (select public.create_rent_roll_snapshot(
     'c1000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000002',
     date '2026-03-31', 'ce000000-0000-0000-0000-000000000087',
     'cc000000-0000-0000-0000-000000000087', 'EUR'
   ) #>> '{error,code}'),
  'not_found',
  'a property of another workspace is not visible to snapshot creation'
);

select is(
  (select count(*)::integer from public.audit_events as audit
   where audit.workspace_id = 'c1000000-0000-0000-0000-000000000001'
     and audit.entity_type = 'rent_roll_snapshot'
     and audit.action = 'rent_roll_snapshot.create'),
  3,
  'every frozen rent roll wrote exactly one append-only audit row'
);

-- === Realtime publication =============================================

select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename in ('leasing_cases', 'rent_roll_snapshots')),
  2,
  'the leasing case and rent roll aggregates are published for realtime'
);
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename = 'rent_roll_snapshot_lines'),
  0,
  'snapshot lines are deliberately not published: the header event covers them'
);

select * from finish();

rollback;
