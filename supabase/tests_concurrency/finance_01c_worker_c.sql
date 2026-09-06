\set ON_ERROR_STOP on
set role authenticated;

-- Challenger on the fiscal month. Same shape as worker B, different command --
-- FINANCE-01c fixes two call sites and one challenger could only prove one.
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'fc000000-0000-0000-0000-000000000001',
    false
  );
  perform set_config('request.jwt.claims', '{"aal":"aal2"}', false);
  perform pg_sleep(1);
end;
$$;

select case
  when result ->> 'ok' = 'true' then 'ok'
  else result #>> '{error,code}'
end
from (
  select public.open_finance_period(
    'fc000000-0000-0000-0000-000000000010',
    2026,
    3,
    'fc000000-0000-0000-0000-000000000023',
    'fc000000-0000-0000-0000-000000000032',
    'concurrency test challenger, period'
  ) as result
) as mutation;
