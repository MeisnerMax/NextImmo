\set ON_ERROR_STOP on
set role authenticated;
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'ec000000-0000-0000-0000-000000000001',
    false
  );
  perform set_config(
    'request.jwt.claims',
    '{"aal":"aal1"}',
    false
  );
  perform pg_sleep(1);
end;
$$;
select case
  when result ->> 'ok' = 'true' then 'ok'
  else result #>> '{error,code}'
end
from (
  select public.transition_lease_status(
    'ec000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000040',
    1,
    'active'::public.lease_status,
    'ec000000-0000-0000-0000-000000000051',
    'ec000000-0000-0000-0000-000000000061',
    null,
    'concurrency test worker b'
  ) as result
) as mutation;
