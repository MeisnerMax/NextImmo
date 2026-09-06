\set ON_ERROR_STOP on
set role authenticated;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    'fc000000-0000-0000-0000-000000000001',
    false
  );
  -- DEC-025: every workspace business surface requires aal2, and
  -- private.finance_command_gate refuses without it. All three sessions
  -- present the identical shape so that only the race differs.
  perform set_config('request.jwt.claims', '{"aal":"aal2"}', false);
end;
$$;

-- The holder. It claims both business keys inside one explicit transaction and
-- then stays there, so the two challengers are guaranteed to arrive while its
-- rows are written but not yet visible to anybody else. That is the whole
-- point: the race this package fixes is not "two sessions overlap by
-- microseconds and we hope to catch it", it is "a second session reads a
-- snapshot that predates the first session's commit", and an open transaction
-- stages that condition deterministically instead of hoping for it.
--
-- The advisory locks are transaction-scoped, so they are held for exactly as
-- long as this transaction is open and released by the commit below.
begin;

do $$
declare
  v_account jsonb;
  v_period jsonb;
begin
  v_account := public.create_finance_account(
    'fc000000-0000-0000-0000-000000000010',
    '4000',
    'Mieteinnahmen',
    'income',
    'fc000000-0000-0000-0000-000000000020',
    'fc000000-0000-0000-0000-000000000030',
    null,
    'concurrency test holder, account'
  );
  if v_account ->> 'ok' <> 'true' then
    raise exception 'the holder could not create the account: %', v_account;
  end if;

  v_period := public.open_finance_period(
    'fc000000-0000-0000-0000-000000000010',
    2026,
    3,
    'fc000000-0000-0000-0000-000000000021',
    'fc000000-0000-0000-0000-000000000030',
    'concurrency test holder, period'
  );
  if v_period ->> 'ok' <> 'true' then
    raise exception 'the holder could not open the period: %', v_period;
  end if;

  -- Hold both keys long enough for both challengers to arrive and block. They
  -- start their own wait at one second, so three seconds is a wide margin on a
  -- loaded CI runner without making the gate slow.
  --
  -- No statement timeout applies here: psql logs in as `postgres`, and `set
  -- role` does not carry the `authenticated` role's login-time GUCs -- its 8 s
  -- `statement_timeout` is a property of a PostgREST connection, not of this
  -- session. Three seconds stays inside it regardless, so the fixture asks the
  -- database for nothing production would refuse.
  perform pg_sleep(3);
end;
$$;

commit;

select 'ok';
