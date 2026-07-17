begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select hasnt_table('public', 'workspaces');
select hasnt_table('public', 'user_profiles');
select hasnt_table('public', 'roles');
select hasnt_table('public', 'permissions');
select hasnt_table('public', 'memberships');
select hasnt_table('public', 'role_permissions');
select hasnt_table('public', 'entity_scopes');
select hasnt_table('public', 'audit_events');
select hasnt_table('public', 'mutation_receipts');
select hasnt_type('public', 'membership_status');
select hasnt_type('public', 'audit_actor_type');
select hasnt_schema('private');

select * from finish();

rollback;
