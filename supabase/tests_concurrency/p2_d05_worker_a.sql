\set ON_ERROR_STOP on
set role authenticated;
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'ec000000-0000-0000-0000-000000000001',
    false
  );
  -- Since SECURITY-AAL-ENFORCEMENT-01 / DEC-025 every workspace business
  -- surface requires aal2, leasing included -- this file previously carried a
  -- comment claiming the opposite. Both workers present the identical session
  -- shape so that only the race differs; without the assurance claim both
  -- would simply be refused and the concurrency contract would go untested.
  perform set_config(
    'request.jwt.claims',
    '{"aal":"aal2"}',
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
