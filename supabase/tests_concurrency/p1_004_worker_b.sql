\set ON_ERROR_STOP on
set role authenticated;
do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'ac000000-0000-0000-0000-000000000001',
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
  select public.update_property(
    '1c000000-0000-0000-0000-000000000001',
    '1c000000-0000-0000-0000-000000000005',
    1,
    '1c000000-0000-0000-0000-000000000007',
    '1c000000-0000-0000-0000-000000000009',
    '{"name":"Worker B"}'::jsonb,
    'concurrency test'
  ) as result
) as mutation;
