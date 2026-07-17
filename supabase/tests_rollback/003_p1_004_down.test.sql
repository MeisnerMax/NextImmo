begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select hasnt_table('public', 'properties', 'P1-004 properties is removed');
select hasnt_type('public', 'property_status', 'P1-004 property status is removed');
select hasnt_function(
  'public',
  'update_property',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb', 'text'],
  'P1-004 update RPC is removed'
);

select has_table('public', 'workspaces', 'P1-003 workspaces remains');
select has_table('public', 'audit_events', 'P1-003 audit events remains');
select has_table('public', 'mutation_receipts', 'P1-003 mutation receipts remains');
select has_function('private', 'is_active_workspace_member', array['uuid']);
select has_function('private', 'has_workspace_permission', array['uuid', 'text']);
select policies_are('public', 'audit_events', array['audit_events_select_audit_read']);

select * from finish();

rollback;
