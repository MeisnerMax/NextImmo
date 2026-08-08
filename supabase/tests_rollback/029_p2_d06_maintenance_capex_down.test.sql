begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- Rolling back P2-D06 must remove everything it added and leave the P2-D02
-- party contract and P2-D03 document contract exactly as they were.

select hasnt_table('public', 'maintenance_tickets', 'the ticket table is removed');
select hasnt_table('public', 'capex_projects', 'the project table is removed');

select hasnt_function('public', 'maintenance_tickets', array['uuid', 'uuid', 'uuid', 'text', 'text'],
  'the ticket read function is removed');
select hasnt_function('public', 'capex_projects', array['uuid', 'uuid', 'text'],
  'the project read function is removed');
select hasnt_function('public', 'create_maintenance_ticket', array[
  'uuid', 'uuid', 'text', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'timestamptz',
  'numeric', 'text', 'uuid', 'text', 'boolean', 'text', 'text', 'text'
], 'create_maintenance_ticket is removed');
select hasnt_function('public', 'transition_maintenance_ticket_status', array[
  'uuid', 'uuid', 'bigint', 'maintenance_ticket_status', 'uuid', 'uuid', 'numeric', 'text'
], 'transition_maintenance_ticket_status is removed');
select hasnt_function('public', 'create_capex_project', array[
  'uuid', 'uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'date', 'date', 'numeric', 'numeric',
  'text', 'uuid', 'text', 'text', 'text'
], 'create_capex_project is removed');
select hasnt_function('public', 'transition_capex_project_status', array[
  'uuid', 'uuid', 'bigint', 'capex_project_status', 'uuid', 'uuid', 'numeric', 'text'
], 'transition_capex_project_status is removed');

select hasnt_function('private', 'maintenance_command_gate', array['uuid', 'uuid', 'uuid', 'text'],
  'the command gate is removed');
select hasnt_function('private', 'maintenance_contractor_party_valid', array['uuid', 'uuid'],
  'the contractor validity helper is removed');

-- The document-link unblock reverts with the migration: unmigrated again.
select is(
  private.document_entity_ref_state(gen_random_uuid(), 'maintenance_ticket', gen_random_uuid()),
  'unmigrated',
  'document linking reports maintenance_ticket as unmigrated again after rollback'
);
select is(
  private.document_entity_ref_state(gen_random_uuid(), 'capex_project', gen_random_uuid()),
  'unmigrated',
  'document linking reports capex_project as unmigrated again after rollback'
);

-- Neighbouring contracts this migration only read from must survive intact.
select has_table('public', 'parties', 'the parties table survives the rollback');
select has_table('public', 'party_contractor_details',
  'the contractor role satellite survives the rollback');
select has_function('private', 'leasing_property_in_workspace', array['uuid', 'uuid'],
  'the reused property-in-workspace helper survives the rollback');
select has_type('public', 'document_link_entity_type',
  'the document link entity type enum survives the rollback');

select * from finish();

rollback;
