begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

-- After reverting the P2-D04 envelope migration, the whole mechanism is gone…
select hasnt_table(
  'public', 'domain_events',
  'domain_events is removed by the down path'
);

select is(
  (select count(*)::integer from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'publish_domain_event', 'domain_event_topic_workspace',
       'domain_event_topic_permission', 'reject_domain_event_change',
       'publish_document_link_event', 'publish_required_document_event'
     )),
  0,
  'every P2-D04 helper is removed'
);

select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'realtime' and tablename = 'messages'
     and policyname = 'domain_event_broadcast_receive_scoped'),
  0,
  'the broadcast policy is removed'
);

-- …while the P2-D03 surface it attached to is untouched.
select has_table(
  'public', 'document_links',
  'P2-D03 document_links survives the P2-D04 rollback'
);

select is(
  (select count(*)::integer from pg_trigger
   where tgrelid = 'public.document_links'::regclass and not tgisinternal),
  0,
  'the publishing trigger is gone from document_links'
);

select has_function(
  'public', 'resolve_document_content_ref', array['uuid', 'uuid', 'integer'],
  'resolve_document_content_ref still exists'
);

-- The decisive one: the down path must restore the P2-D03 body, which is
-- stable and records nothing. A volatile function here would mean the rollback
-- left the access-recording behaviour behind with no table to write to.
select ok(
  (select provolatile = 's' from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolve_document_content_ref'),
  'resolve_document_content_ref is stable again after rollback'
);

select * from finish();

rollback;
