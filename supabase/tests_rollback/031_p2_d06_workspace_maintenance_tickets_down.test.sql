begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

-- Rolling back the workspace-wide read must remove it and leave the
-- per-property P2-D06 RPC (and everything else) exactly as it was.

select hasnt_function('public', 'workspace_maintenance_tickets', array['uuid', 'text', 'text'],
  'the workspace-wide read function is removed');

select has_function('public', 'maintenance_tickets', array['uuid', 'uuid', 'uuid', 'text', 'text'],
  'the per-property P2-D06 read RPC survives the rollback');

select * from finish();

rollback;
