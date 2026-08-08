\set ON_ERROR_STOP on
set role authenticated;
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'ec000000-0000-0000-0000-000000000001',
    false
  );
  -- Leasing has no AAL2 gate (units and leases are ordinary workspace business
  -- data, like properties and parties). The claim is set anyway so both workers
  -- present an identical session shape and only the race differs.
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
    'ec000000-0000-0000-0000-000000000050',
    'ec000000-0000-0000-0000-000000000060',
    null,
    'concurrency test worker a'
  ) as result
) as mutation;
