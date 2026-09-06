\set ON_ERROR_STOP on
set role authenticated;

-- Challenger on the account code. A different mutation id, so this is a
-- genuinely different command and not an idempotent retry -- the receipt
-- replay path is pgTAP's to cover and is not what this file is about.
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'fc000000-0000-0000-0000-000000000001',
    false
  );
  perform set_config('request.jwt.claims', '{"aal":"aal2"}', false);
  -- Arrive one second into the holder's open transaction.
  perform pg_sleep(1);
end;
$$;

-- With the lock: this blocks on the holder's advisory lock, then reads a
-- snapshot containing the committed account and returns dependency_conflict.
-- Without it: the exists check comes back empty, the insert blocks on
-- finance_accounts_code_unique instead, and the statement dies with a raw
-- 23505 -- which ON_ERROR_STOP turns into a non-zero exit and the harness
-- reports as a failure. That is the difference this file exists to show.
select case
  when result ->> 'ok' = 'true' then 'ok'
  else result #>> '{error,code}'
end
from (
  select public.create_finance_account(
    'fc000000-0000-0000-0000-000000000010',
    '4000',
    'Mieteinnahmen (Duplikat)',
    'income',
    'fc000000-0000-0000-0000-000000000022',
    'fc000000-0000-0000-0000-000000000031',
    null,
    'concurrency test challenger, account'
  ) as result
) as mutation;
