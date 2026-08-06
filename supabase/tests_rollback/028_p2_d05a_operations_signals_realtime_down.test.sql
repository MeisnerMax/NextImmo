begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

-- Rolling back only the realtime step must leave the operations_signal_states
-- table itself intact — the publication membership is a separate migration
-- for exactly that reason (mirrors 020_p2_d05_realtime_down).
select is(
  (select count(*)::integer
   from pg_publication_tables as publication
   where publication.pubname = 'supabase_realtime'
     and publication.schemaname = 'public'
     and publication.tablename = 'operations_signal_states'),
  0,
  'operations_signal_states is no longer published for realtime'
);
select has_table('public', 'operations_signal_states',
  'the table survives the realtime rollback');
select has_function('public', 'operations_signals', array['uuid', 'uuid'],
  'the read function survives the realtime rollback');

select * from finish();

rollback;
