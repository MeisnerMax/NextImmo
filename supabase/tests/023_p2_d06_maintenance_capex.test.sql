begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- === Schema surface ===================================================

select has_table('public', 'maintenance_tickets', 'the ticket table exists');
select has_table('public', 'capex_projects', 'the project table exists');

select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   where class.oid = 'public.maintenance_tickets'::regclass),
  'maintenance_tickets enables and forces RLS'
);
select ok(
  (select class.relrowsecurity and class.relforcerowsecurity
   from pg_class as class
   where class.oid = 'public.capex_projects'::regclass),
  'capex_projects enables and forces RLS'
);
select policies_are('public', 'maintenance_tickets',
  array['maintenance_tickets_select_maintenance_read']);
select policies_are('public', 'capex_projects',
  array['capex_projects_select_capex_read']);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('maintenance_tickets', 'capex_projects')
     and grantee in ('anon', 'authenticated')
     and privilege_type <> 'SELECT'),
  0,
  'client roles receive no DML grants on either table'
);

select has_function('public', 'maintenance_tickets', array['uuid', 'uuid', 'uuid', 'text', 'text']);
select has_function('public', 'capex_projects', array['uuid', 'uuid', 'text']);
select has_function('public', 'create_maintenance_ticket', array[
  'uuid', 'uuid', 'text', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'timestamptz',
  'numeric', 'text', 'uuid', 'text', 'boolean', 'text', 'text', 'text'
]);
select has_function('public', 'update_maintenance_ticket', array[
  'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'timestamptz',
  'numeric', 'numeric', 'text', 'uuid', 'text', 'boolean', 'text', 'text', 'text'
]);
select has_function('public', 'transition_maintenance_ticket_status', array[
  'uuid', 'uuid', 'bigint', 'maintenance_ticket_status', 'uuid', 'uuid', 'numeric', 'text'
]);
select has_function('public', 'create_capex_project', array[
  'uuid', 'uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'date', 'date', 'numeric', 'numeric',
  'text', 'uuid', 'text', 'text', 'text'
]);
select has_function('public', 'update_capex_project', array[
  'uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'text', 'text', 'text', 'date', 'date', 'date',
  'numeric', 'numeric', 'numeric', 'text', 'uuid', 'text', 'text', 'text'
]);
select has_function('public', 'transition_capex_project_status', array[
  'uuid', 'uuid', 'bigint', 'capex_project_status', 'uuid', 'uuid', 'numeric', 'text'
]);
select is(
  (select count(*)::integer
   from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in (
       'maintenance_tickets', 'capex_projects', 'create_maintenance_ticket',
       'update_maintenance_ticket', 'transition_maintenance_ticket_status',
       'create_capex_project', 'update_capex_project', 'transition_capex_project_status'
     )
     and grantee in ('PUBLIC', 'anon')),
  0,
  'PUBLIC and anon cannot execute any maintenance_capex RPC'
);

-- === Fixtures ==========================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('ea000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-manager-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-approver-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-reader-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ea000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-noperm-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('eb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2d06-manager-b@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'p2d06-workspace-a', 'P2D06 Workspace A'),
  ('e2000000-0000-0000-0000-000000000001', 'p2d06-workspace-b', 'P2D06 Workspace B');

insert into public.roles (id, workspace_id, key, name) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('e3000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'approver', 'Approver A'),
  ('e3000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'reader', 'Reader A'),
  ('e3000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001', 'noperm', 'No Permission A'),
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('e5000000-0000-0000-0000-000000000001', 'maintenance.read', 'Maintenance Read'),
  ('e5000000-0000-0000-0000-000000000002', 'maintenance.manage', 'Maintenance Manage'),
  ('e5000000-0000-0000-0000-000000000003', 'capex.read', 'CapEx Read'),
  ('e5000000-0000-0000-0000-000000000004', 'capex.manage', 'CapEx Manage'),
  ('e5000000-0000-0000-0000-000000000005', 'capex.approve', 'CapEx Approve'),
  ('e5000000-0000-0000-0000-000000000006', 'workspace.read', 'Workspace Read'),
  ('e5000000-0000-0000-0000-000000000007', 'audit.read', 'Audit Read'),
  ('e5000000-0000-0000-0000-000000000008', 'party.read', 'Party Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- manager: full read/manage on both, no capex.approve
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000004'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000006'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000007'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000008'),
  -- approver: capex.approve + capex.read, deliberately no capex.manage
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000005'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000006'),
  -- reader: read-only on both
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000003'),
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000006'),
  -- noperm: workspace.read only
  ('e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000004', 'e5000000-0000-0000-0000-000000000006'),
  -- Workspace B manager: full permissions, own workspace only
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000002'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000003'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000004'),
  ('e2000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000006');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('e6000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'active'),
  ('e6000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'active'),
  ('e6000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000003', 'e3000000-0000-0000-0000-000000000003', 'active'),
  ('e6000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000004', 'e3000000-0000-0000-0000-000000000004', 'active'),
  ('e6000000-0000-0000-0000-000000000005', 'e2000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'active');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  created_by, updated_by
) values
  ('e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'Objekt A', 'Hauptstrasse 1', '10115', 'Berlin', 'de', 'residential',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  ('e7000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001',
   'Objekt B', 'Nebenstrasse 2', '20095', 'Hamburg', 'de', 'residential',
   'eb000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, currency_code, created_by, updated_by
) values
  ('e9000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001',
   'U-01', 'occupied', 'EUR', 'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');

insert into public.parties (
  id, workspace_id, party_type, display_name, email, phone, created_by, updated_by
) values
  ('e8000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'organization', 'Handwerker GmbH', 'kontakt@handwerker.test', '+49 2', 'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  -- has a tenant role, not a contractor role -> must be rejected
  ('e8000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'person', 'Nur Mieter', 'mieter@example.test', '+49 3', 'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');

insert into public.party_roles (workspace_id, party_id, role_type, created_by, updated_by) values
  ('e1000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'contractor',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001'),
  ('e1000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000002', 'tenant',
   'ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001');

create temporary table p2_d06_results (
  key text primary key,
  result jsonb not null
);
grant all on table p2_d06_results to authenticated;

-- === create_maintenance_ticket =========================================

set local role authenticated;
-- These fixtures authenticate through request.jwt.claim.sub, which auth.uid()
-- reads but auth.jwt() does not. State the assurance level once for the
-- transaction so the reads below exercise authorization rather than the
-- AAL2 boundary, which 027 covers on its own.
select set_config('request.jwt.claims', '{"aal":"aal2"}', true);
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000004', true);
insert into p2_d06_results (key, result)
select 'ticket_forbidden', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000002', 'ed000000-0000-0000-0000-000000000002'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_forbidden'), 'forbidden', 'a member without maintenance.manage cannot create a ticket');

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d06_results (key, result)
select 'ticket_bad_property', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000002', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000003', 'ed000000-0000-0000-0000-000000000003'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_bad_property'), 'not_found', 'a property outside the workspace is not_found');

insert into p2_d06_results (key, result)
select 'ticket_negative_cost', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000004', 'ed000000-0000-0000-0000-000000000004',
  null, null, 'general', 'normal', null, -50
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_negative_cost'), 'validation_failed', 'a negative cost estimate is rejected');

insert into p2_d06_results (key, result)
select 'ticket_cost_no_currency', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000005', 'ed000000-0000-0000-0000-000000000005',
  null, null, 'general', 'normal', null, 250
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_cost_no_currency'), 'validation_failed', 'a cost estimate without a currency is rejected');

insert into p2_d06_results (key, result)
select 'ticket_bad_contractor', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000006', 'ed000000-0000-0000-0000-000000000006',
  'e9000000-0000-0000-0000-000000000001', null, 'general', 'urgent', null, 250, 'EUR',
  'e8000000-0000-0000-0000-000000000002'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_bad_contractor'), 'dependency_conflict', 'a party without an open contractor role is rejected');

insert into p2_d06_results (key, result)
select 'ticket_create', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000007', 'ed000000-0000-0000-0000-000000000007',
  'e9000000-0000-0000-0000-000000000001', 'Kein Warmwasser', 'plumbing', 'urgent', null, 250, 'EUR',
  'e8000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d06_results where key = 'ticket_create'), 'true', 'creating a valid ticket succeeds');
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_create'), 'new', 'a new ticket starts in status new');
select is((select result #>> '{entity,version}' from p2_d06_results where key = 'ticket_create'), '1', 'a new ticket starts at version 1');
select is((select result #>> '{entity,contractor_party_id}' from p2_d06_results where key = 'ticket_create'), 'e8000000-0000-0000-0000-000000000001', 'the contractor party is stored');

-- Idempotent replay: same mutation id returns the same result.
insert into p2_d06_results (key, result)
select 'ticket_replay', public.create_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'Heizung defekt',
  'ec000000-0000-0000-0000-000000000007', 'ed000000-0000-0000-0000-000000000007',
  'e9000000-0000-0000-0000-000000000001', 'Kein Warmwasser', 'plumbing', 'urgent', null, 250, 'EUR',
  'e8000000-0000-0000-0000-000000000001'
);
select is(
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_replay'),
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create'),
  'replaying the same mutation id returns the original ticket, not a duplicate'
);

-- === update_maintenance_ticket =========================================

insert into p2_d06_results (key, result)
select 'ticket_update', public.update_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  1, 'ec000000-0000-0000-0000-000000000008', 'ed000000-0000-0000-0000-000000000008',
  null, 'Aktualisierte Beschreibung'
);
select is((select result #>> '{entity,version}' from p2_d06_results where key = 'ticket_update'), '2', 'a valid update increments the version');
select is((select result #>> '{entity,description}' from p2_d06_results where key = 'ticket_update'), 'Aktualisierte Beschreibung', 'the description is updated');

insert into p2_d06_results (key, result)
select 'ticket_stale', public.update_maintenance_ticket(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  1, 'ec000000-0000-0000-0000-000000000009', 'ed000000-0000-0000-0000-000000000009',
  null, 'Sollte fehlschlagen'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_stale'), 'version_conflict', 'a stale expected_version is rejected');

-- === transition_maintenance_ticket_status (STM-006) ====================

insert into p2_d06_results (key, result)
select 'ticket_illegal', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  2, 'resolved', 'ec000000-0000-0000-0000-00000000000a', 'ed000000-0000-0000-0000-00000000000a'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_illegal'), 'validation_failed', 'STM-006 rejects new -> resolved directly');

insert into p2_d06_results (key, result)
select 'ticket_triage', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  2, 'triage', 'ec000000-0000-0000-0000-00000000000b', 'ed000000-0000-0000-0000-00000000000b'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_triage'), 'triage', 'new -> triage succeeds');

insert into p2_d06_results (key, result)
select 'ticket_quote', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  3, 'quote_requested', 'ec000000-0000-0000-0000-00000000000c', 'ed000000-0000-0000-0000-00000000000c'
);
insert into p2_d06_results (key, result)
select 'ticket_commissioned', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  4, 'commissioned', 'ec000000-0000-0000-0000-00000000000d', 'ed000000-0000-0000-0000-00000000000d'
);
insert into p2_d06_results (key, result)
select 'ticket_scheduled', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  5, 'scheduled', 'ec000000-0000-0000-0000-00000000000e', 'ed000000-0000-0000-0000-00000000000e'
);
insert into p2_d06_results (key, result)
select 'ticket_in_progress', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  6, 'in_progress', 'ec000000-0000-0000-0000-00000000000f', 'ed000000-0000-0000-0000-00000000000f'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_in_progress'), 'in_progress', 'the chain reaches in_progress');

insert into p2_d06_results (key, result)
select 'ticket_resolved', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  7, 'resolved', 'ec000000-0000-0000-0000-000000000010', 'ed000000-0000-0000-0000-000000000010',
  230
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_resolved'), 'resolved', 'in_progress -> resolved succeeds');
select isnt((select result #>> '{entity,resolved_at}' from p2_d06_results where key = 'ticket_resolved'), null, 'resolved_at is stamped on entering resolved');
select is((select result #>> '{entity,cost_actual}' from p2_d06_results where key = 'ticket_resolved'), '230', 'the actual cost is recorded on resolution');

insert into p2_d06_results (key, result)
select 'ticket_reopen', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  8, 'in_progress', 'ec000000-0000-0000-0000-000000000011', 'ed000000-0000-0000-0000-000000000011'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_reopen'), 'in_progress', 'resolved -> in_progress (reopen) succeeds');
select is((select result #>> '{entity,resolved_at}' from p2_d06_results where key = 'ticket_reopen'), null, 'reopening clears resolved_at');

insert into p2_d06_results (key, result)
select 'ticket_resolved_2', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  9, 'resolved', 'ec000000-0000-0000-0000-000000000012', 'ed000000-0000-0000-0000-000000000012'
);
insert into p2_d06_results (key, result)
select 'ticket_invoiced', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  10, 'invoiced', 'ec000000-0000-0000-0000-000000000013', 'ed000000-0000-0000-0000-000000000013'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_invoiced'), 'invoiced', 'resolved -> invoiced succeeds');
select isnt((select result #>> '{entity,resolved_at}' from p2_d06_results where key = 'ticket_invoiced'), null, 'resolved_at survives the forward move to invoiced');

insert into p2_d06_results (key, result)
select 'ticket_archived', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  11, 'archived', 'ec000000-0000-0000-0000-000000000014', 'ed000000-0000-0000-0000-000000000014'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'ticket_archived'), 'archived', 'invoiced -> archived succeeds');

-- A reader cannot transition status.
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
insert into p2_d06_results (key, result)
select 'ticket_transition_forbidden', public.transition_maintenance_ticket_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid,
  12, 'archived', 'ec000000-0000-0000-0000-000000000015', 'ed000000-0000-0000-0000-000000000015'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'ticket_transition_forbidden'), 'forbidden', 'a reader without maintenance.manage cannot transition status');

-- === maintenance_tickets(): read RPC ===================================

insert into p2_d06_results (key, result)
select 'tickets_read', public.maintenance_tickets(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d06_results where key = 'tickets_read'), 'true', 'a reader with maintenance.read can list tickets');
select is(
  (select jsonb_array_length(result -> 'entity') from p2_d06_results where key = 'tickets_read'),
  1,
  'exactly the one fixture ticket is returned'
);

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000004', true);
insert into p2_d06_results (key, result)
select 'tickets_read_forbidden', public.maintenance_tickets(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'tickets_read_forbidden'), 'forbidden', 'a member without maintenance.read cannot list tickets');

-- Manager A also holds audit.read, so this reads through RLS rather than
-- around it (mirrors 022_p2_d05a_operations_signals).
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer
   from public.audit_events as audit
   where audit.workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and audit.entity_type = 'maintenance_ticket'),
  12,
  'every ticket create/update/transition is audited (1 create + 1 update + 10 transitions)'
);

-- === create_capex_project / STM-007 =====================================

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);

insert into p2_d06_results (key, result)
select 'capex_negative_budget', public.create_capex_project(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'CAPEX-001',
  'ec000000-0000-0000-0000-000000000020', 'ed000000-0000-0000-0000-000000000020',
  'roof', 'Dachsanierung', null, null, -1000
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'capex_negative_budget'), 'validation_failed', 'a negative budget is rejected');

insert into p2_d06_results (key, result)
select 'capex_create', public.create_capex_project(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'CAPEX-001',
  'ec000000-0000-0000-0000-000000000021', 'ed000000-0000-0000-0000-000000000021',
  'roof', 'Dachsanierung', current_date, current_date + 90, 50000, 55000, 'EUR',
  'e8000000-0000-0000-0000-000000000001', 'Facility Manager'
);
select is((select result ->> 'ok' from p2_d06_results where key = 'capex_create'), 'true', 'creating a valid capex project succeeds');
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'capex_create'), 'idea', 'a new project starts in status idea');

insert into p2_d06_results (key, result)
select 'capex_planned', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  1, 'planned', 'ec000000-0000-0000-0000-000000000022', 'ed000000-0000-0000-0000-000000000022'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'capex_planned'), 'planned', 'idea -> planned succeeds');
select is((select result #>> '{entity,approved_by}' from p2_d06_results where key = 'capex_planned'), null, 'approved_by is still null before approval');

-- Approving is target-gated on capex.approve before the transition table is
-- even consulted, so this illegal-edge check runs as the approver — otherwise
-- a capex.manage-only actor would get 'forbidden' before STM-007 is checked.
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000002', true);
insert into p2_d06_results (key, result)
select 'capex_illegal', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  2, 'approved', 'ec000000-0000-0000-0000-000000000023', 'ed000000-0000-0000-0000-000000000023'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'capex_illegal'), 'validation_failed', 'STM-007 rejects planned -> approved directly (quote_requested is required)');

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
insert into p2_d06_results (key, result)
select 'capex_quote', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  2, 'quote_requested', 'ec000000-0000-0000-0000-000000000024', 'ed000000-0000-0000-0000-000000000024'
);

-- A capex.manage-only actor cannot approve.
insert into p2_d06_results (key, result)
select 'capex_approve_forbidden', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  3, 'approved', 'ec000000-0000-0000-0000-000000000025', 'ed000000-0000-0000-0000-000000000025'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'capex_approve_forbidden'), 'forbidden', 'capex.manage alone does not permit approval');

-- The approver (capex.approve, no capex.manage) can approve, but not manage.
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000002', true);
insert into p2_d06_results (key, result)
select 'capex_manage_forbidden_for_approver', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  3, 'quote_requested', 'ec000000-0000-0000-0000-000000000026', 'ed000000-0000-0000-0000-000000000026'
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'capex_manage_forbidden_for_approver'), 'forbidden', 'capex.approve alone does not permit ordinary status management');

insert into p2_d06_results (key, result)
select 'capex_approved', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  3, 'approved', 'ec000000-0000-0000-0000-000000000027', 'ed000000-0000-0000-0000-000000000027'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'capex_approved'), 'approved', 'the approver can approve');
select is((select result #>> '{entity,approved_by}' from p2_d06_results where key = 'capex_approved'), 'ea000000-0000-0000-0000-000000000002', 'approved_by records the approving actor');
select isnt((select result #>> '{entity,approved_at}' from p2_d06_results where key = 'capex_approved'), null, 'approved_at is stamped');

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
insert into p2_d06_results (key, result)
select 'capex_in_progress', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  4, 'in_progress', 'ec000000-0000-0000-0000-000000000028', 'ed000000-0000-0000-0000-000000000028'
);
insert into p2_d06_results (key, result)
select 'capex_completed', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  5, 'completed', 'ec000000-0000-0000-0000-000000000029', 'ed000000-0000-0000-0000-000000000029',
  54200
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'capex_completed'), 'completed', 'in_progress -> completed succeeds');
select is((select result #>> '{entity,actual_amount}' from p2_d06_results where key = 'capex_completed'), '54200', 'the actual amount is recorded on completion');
select isnt((select result #>> '{entity,actual_end_date}' from p2_d06_results where key = 'capex_completed'), null, 'actual_end_date is stamped on completion');

insert into p2_d06_results (key, result)
select 'capex_negative_actual', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  6, 'invoiced', 'ec000000-0000-0000-0000-00000000002a', 'ed000000-0000-0000-0000-00000000002a',
  -100
);
select is((select result #>> '{error,code}' from p2_d06_results where key = 'capex_negative_actual'), 'validation_failed', 'a negative actual amount is rejected');

insert into p2_d06_results (key, result)
select 'capex_invoiced', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  6, 'invoiced', 'ec000000-0000-0000-0000-00000000002b', 'ed000000-0000-0000-0000-00000000002b'
);
insert into p2_d06_results (key, result)
select 'capex_archived', public.transition_capex_project_status(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  7, 'archived', 'ec000000-0000-0000-0000-00000000002c', 'ed000000-0000-0000-0000-00000000002c'
);
select is((select result #>> '{entity,status}' from p2_d06_results where key = 'capex_archived'), 'archived', 'invoiced -> archived succeeds');

-- === update_capex_project ===============================================

insert into p2_d06_results (key, result)
select 'capex_update', public.update_capex_project(
  'e1000000-0000-0000-0000-000000000001',
  (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid,
  8, 'ec000000-0000-0000-0000-00000000002d', 'ed000000-0000-0000-0000-00000000002d',
  null, null, null, null, null, null, null, null, null, null, null, null, 'Rechnung geprueft'
);
select is((select result #>> '{entity,version}' from p2_d06_results where key = 'capex_update'), '9', 'a valid attribute update increments the version');
select is((select result #>> '{entity,next_step}' from p2_d06_results where key = 'capex_update'), 'Rechnung geprueft', 'next_step is updated');

-- === capex_projects(): read RPC =========================================

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
insert into p2_d06_results (key, result)
select 'capex_read', public.capex_projects(
  'e1000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001'
);
select is((select result ->> 'ok' from p2_d06_results where key = 'capex_read'), 'true', 'a reader with capex.read can list projects');
select is(
  (select jsonb_array_length(result -> 'entity') from p2_d06_results where key = 'capex_read'),
  1,
  'exactly the one fixture project is returned'
);

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer
   from public.audit_events as audit
   where audit.workspace_id = 'e1000000-0000-0000-0000-000000000001'
     and audit.entity_type = 'capex_project'),
  9,
  'every project create/update/transition is audited (1 create + 1 update + 7 transitions)'
);

-- === DUP-013 unblock: document_entity_ref_state ==========================

reset role;
select is(
  private.document_entity_ref_state(
    'e1000000-0000-0000-0000-000000000001', 'maintenance_ticket',
    (select result #>> '{entity,id}' from p2_d06_results where key = 'ticket_create')::uuid
  ),
  'ok',
  'document linking now resolves an existing maintenance ticket'
);
select is(
  private.document_entity_ref_state(
    'e1000000-0000-0000-0000-000000000001', 'maintenance_ticket', gen_random_uuid()
  ),
  'missing',
  'document linking reports a nonexistent maintenance ticket as missing, not unmigrated'
);
select is(
  private.document_entity_ref_state(
    'e1000000-0000-0000-0000-000000000001', 'capex_project',
    (select result #>> '{entity,id}' from p2_d06_results where key = 'capex_create')::uuid
  ),
  'ok',
  'document linking now resolves an existing capex project'
);
select is(
  private.document_entity_ref_state('e1000000-0000-0000-0000-000000000001', 'unit', gen_random_uuid()),
  'unmigrated',
  'unit stays unmigrated (P2-D05 gap, out of scope here)'
);

select * from finish();

rollback;
