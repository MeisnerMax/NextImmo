\set ON_ERROR_STOP on

do $$
declare
  v_count integer;
begin
  -- Exactly one of each key landed. The unique constraints would have enforced
  -- that much on their own; what the exit codes of the three sessions already
  -- proved is that the losers were *refused* rather than crashed.
  select count(*) into v_count
  from public.finance_accounts
  where workspace_id = 'fc000000-0000-0000-0000-000000000010' and code = '4000';
  if v_count <> 1 then
    raise exception 'expected exactly one account with code 4000, found %', v_count;
  end if;

  select count(*) into v_count
  from public.finance_periods
  where workspace_id = 'fc000000-0000-0000-0000-000000000010'
    and fiscal_year = 2026 and period_month = 3;
  if v_count <> 1 then
    raise exception 'expected exactly one period 2026-03, found %', v_count;
  end if;

  -- The holder's two mutations succeeded.
  select count(*) into v_count
  from public.mutation_receipts
  where mutation_id in (
    'fc000000-0000-0000-0000-000000000020',
    'fc000000-0000-0000-0000-000000000021'
  ) and status = 'succeeded';
  if v_count <> 2 then
    raise exception 'the holder did not leave two succeeded receipts, found %', v_count;
  end if;

  -- And this is the assertion the whole package is for. A losing challenger
  -- must reach private.fail_finance_mutation and leave a `failed` receipt. A
  -- raw 23505 aborts the statement, which rolls the receipt insert back with
  -- it -- so before FINANCE-01c the losers left no receipt at all, and the
  -- audit trail simply had no record that the command was ever attempted.
  select count(*) into v_count
  from public.mutation_receipts
  where mutation_id in (
    'fc000000-0000-0000-0000-000000000022',
    'fc000000-0000-0000-0000-000000000023'
  ) and status = 'failed';
  if v_count <> 2 then
    raise exception
      'the two challengers did not leave two failed receipts, found % -- a '
      'refused command must record that it was refused', v_count;
  end if;

  -- No challenger got halfway. Both keys carry exactly one audit event, the
  -- holder's.
  select count(*) into v_count
  from public.audit_events
  where workspace_id = 'fc000000-0000-0000-0000-000000000010'
    and entity_type in ('finance_account', 'finance_period');
  if v_count <> 2 then
    raise exception
      'expected exactly two finance audit events, found %', v_count;
  end if;
end;
$$;
