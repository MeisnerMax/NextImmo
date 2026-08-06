begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- Rolling back P2-D05a must remove everything it added and leave the P2-D05
-- leasing contract (units/leases) exactly as it was.

select hasnt_table('public', 'operations_signal_states',
  'the acknowledgement table is removed');
select hasnt_function('public', 'operations_signals', array['uuid', 'uuid'],
  'the read function is removed');
select hasnt_function(
  'public', 'update_operations_signal_status',
  array['uuid', 'uuid', 'text', 'text', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'bigint', 'text', 'text'],
  'the write function is removed'
);
select hasnt_function(
  'private', 'operations_signal_state_snapshot', array['operations_signal_states'],
  'the snapshot helper is removed'
);

-- P2-D05's own private helpers are reused, not owned, by P2-D05a and must
-- survive its rollback.
select has_function('private', 'leasing_command_gate',
  array['uuid', 'uuid', 'uuid', 'text'], 'the shared command gate remains');
select has_function('private', 'claim_leasing_mutation',
  array['uuid', 'uuid', 'bytea', 'text'], 'the shared claim helper remains');
select has_function('private', 'finish_leasing_mutation',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'uuid', 'jsonb', 'jsonb'],
  'the shared finish helper remains');

select has_table('public', 'units', 'the units table survives the rollback');
select has_table('public', 'leases', 'the leases table survives the rollback');

select * from finish();

rollback;
