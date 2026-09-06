-- FINANCE-01c: the two finance business keys are claimed under a lock instead
-- of under a hope.
--
-- FINANCE-01a mints two rows whose uniqueness is a business rule, and in both
-- places it checks the key with `exists` and then inserts:
--
--     create_finance_account   unique (workspace_id, code)
--     open_finance_period      unique (workspace_id, fiscal_year, period_month)
--
-- Both checks sit *behind* the idempotency claim on purpose, and that part is
-- correct and stays: a retry of the same mutation id has to replay its receipt
-- rather than trip over the row it created itself. The header comments in
-- FINANCE-01a say so, and this migration keeps them word for word.
--
-- What the pattern does not survive is two *different* mutations racing on the
-- same key. Read Committed gives each session a snapshot taken before the
-- other inserted, so both `exists` queries come back empty, both proceed, and
-- the unique constraint refuses the loser. The loser does not get the refusal
-- the command is written to return:
--
--     intended   {"ok": false, "error": {"code": "dependency_conflict", ...}}
--     actual     ERROR 23505  finance_accounts_code_unique
--
-- The raw 23505 escapes the typed-failure contract the whole finance surface
-- is built on, and it does more damage than an ugly error string. The client
-- adapter is written against a JSON envelope and receives a Postgres
-- exception. And because the exception aborts the statement -- one RPC call is
-- one transaction -- the receipt the command had just claimed rolls back with
-- it. `private.fail_finance_mutation` never runs, so the refusal leaves no
-- trace at all, where every other refusal on this surface leaves a `failed`
-- receipt. A command that was attempted and refused looks exactly like a
-- command that was never sent.
--
-- The window is narrow; it is not zero, and an import that opens twelve
-- periods in a loop is exactly the shape that finds it.
--
-- The fix is the one this repository already uses twice: a transaction-scoped
-- advisory lock on the business key, taken before the state is read.
-- FINANCE-01b does it for `kpi_key` in `create_finance_kpi_definition` and
-- `activate_finance_kpi_definition`; PROPERTY-MEDIA-DATA-01 does it per
-- property for the cover claim. The second session blocks until the first
-- commits and then reads a snapshot that contains the committed row, so it
-- takes the `dependency_conflict` branch it was always meant to take.
--
-- That last step is the load-bearing detail and it is worth naming, because it
-- is the reason a lock is enough on its own. Both commands are VOLATILE
-- PL/pgSQL, so under Read Committed each statement inside the body takes a
-- fresh snapshot. The `exists` check therefore runs *after* the lock is
-- granted and sees what the winner committed. A STABLE function would keep the
-- caller's snapshot, the check would still come back empty, and the lock would
-- buy nothing but a delay.
--
-- Key namespaces, and why they cannot collide:
--
--     account   <workspace>:account:<code>
--     period    <workspace>:period:<year>-<month>
--     kpi       <workspace>:<kpi_key>            (FINANCE-01b, untouched)
--
-- An account code matches `^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$` and a kpi_key
-- matches `^[a-z0-9]+(?:[._-][a-z0-9]+)*$`. Neither admits a colon, so no
-- account code can spell `period:...` and no kpi_key can spell `account:...`:
-- the three namespaces are disjoint by construction rather than by luck. A
-- hash collision in `hashtextextended` would only serialize two unrelated
-- keys, never merge them -- the lock is a serialization device, and the unique
-- constraints stay the authority on what is actually unique.
--
-- Scope, stated plainly. This migration replaces two function bodies and
-- creates, drops, renames and re-grants nothing. Same signatures, same owner,
-- same grants, so the SECURITY DEFINER inventory SR-20 counts does not move.
-- It also does not touch the commands that guard on `expected_version`
-- (`update_finance_account`, `transition_finance_period_status`,
-- `record_finance_ledger_entry`): optimistic concurrency is a different
-- mechanism with a different, already-typed failure, and P1-004 covers it.
-- Only these two commands mint a row whose uniqueness nothing else defends.
--
-- Proving it. pgTAP runs inside one transaction and can no more stage this
-- race than it could stage P1-004's; a pgTAP test here would only assert that
-- the lock call is present in the body, which is not the same claim. The proof
-- is a real two-session test, `tool/verify_finance_01c_concurrency.ps1`, built
-- the way P1-004 and P2-D05 build theirs: a holder that keeps both keys inside
-- an open transaction, and two challengers that must come back with
-- `dependency_conflict` and a `failed` receipt rather than an exception.

-- =============================================================================
-- create_finance_account: unchanged except for the lock on the code.
-- =============================================================================

create or replace function public.create_finance_account(
  p_workspace_id uuid,
  p_code text,
  p_name text,
  p_account_type text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_parent_account_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_row public.finance_accounts%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_code is null or btrim(p_code) !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An account code is required',
        'field', 'code'
      )
    );
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An account name is required',
        'field', 'name'
      )
    );
  end if;

  if p_account_type is null
     or p_account_type not in ('income', 'expense', 'asset', 'liability', 'equity')
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unsupported account type',
        'field', 'account_type'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_finance_account',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'code', btrim(p_code),
        'name', btrim(p_name),
        'account_type', p_account_type,
        'parent_account_id', p_parent_account_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'finance_account'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- State checks live *behind* the claim on purpose. A retry of a command
  -- that already succeeded must replay its receipt; if the duplicate-code
  -- check ran first, the account this very command created would be the
  -- duplicate that refuses it.
  if p_parent_account_id is not null and not exists (
    select 1 from public.finance_accounts as parent
    where parent.workspace_id = p_workspace_id
      and parent.id = p_parent_account_id
  ) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Parent account not found',
        'field', 'parent_account_id'
      )
    );
  end if;

  -- Serialize the claim on this code. Without the lock two concurrent creates
  -- of the same code both read a snapshot in which the other has not committed,
  -- both find nothing, and the unique constraint refuses the loser with a raw
  -- 23505 instead of the typed refusal below. The lock is transaction-scoped
  -- and per code, so it costs nothing between different codes.
  perform pg_advisory_xact_lock(
    hashtextextended(p_workspace_id::text || ':account:' || btrim(p_code), 0)
  );

  if exists (
    select 1 from public.finance_accounts as existing
    where existing.workspace_id = p_workspace_id
      and existing.code = btrim(p_code)
  ) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'An account with this code already exists',
        'field', 'code'
      )
    );
  end if;

  insert into public.finance_accounts (
    workspace_id, code, name, account_type, parent_account_id,
    created_by, updated_by
  ) values (
    p_workspace_id, btrim(p_code), btrim(p_name),
    p_account_type::public.finance_account_type, p_parent_account_id,
    v_actor_id, v_actor_id
  )
  returning * into v_row;

  v_new_values := private.finance_account_snapshot(v_row);

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'create', 'finance_account', v_row.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$function$;

-- =============================================================================
-- open_finance_period: unchanged except for the lock on the month.
-- =============================================================================

create or replace function public.open_finance_period(
  p_workspace_id uuid,
  p_fiscal_year integer,
  p_period_month integer,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_row public.finance_periods%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_fiscal_year is null or p_fiscal_year not between 1900 and 2999
     or p_period_month is null or p_period_month not between 1 and 12 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A fiscal year and a month between 1 and 12 are required',
        'field', 'period_month'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance management is not permitted'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'open_finance_period',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'fiscal_year', p_fiscal_year,
        'period_month', p_period_month,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'finance_period'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- Serialize the claim on this month, for the same reason and with the same
  -- shape as the account code above: two concurrent opens of the same period
  -- would otherwise both pass the check below and one would die on
  -- finance_periods_unique rather than return dependency_conflict.
  perform pg_advisory_xact_lock(
    hashtextextended(
      p_workspace_id::text || ':period:' || p_fiscal_year::text || '-'
        || p_period_month::text,
      0
    )
  );

  -- Behind the claim, for the same reason as the account code: the period
  -- this command already opened must not be the one that refuses its retry.
  if exists (
    select 1 from public.finance_periods as period
    where period.workspace_id = p_workspace_id
      and period.fiscal_year = p_fiscal_year
      and period.period_month = p_period_month
  ) then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'That period already exists'
      )
    );
  end if;

  insert into public.finance_periods (
    workspace_id, fiscal_year, period_month, created_by, updated_by
  ) values (
    p_workspace_id, p_fiscal_year, p_period_month, v_actor_id, v_actor_id
  )
  returning * into v_row;

  v_new_values := private.finance_period_snapshot(v_row);

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'create', 'finance_period', v_row.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$function$;

-- The ownership and the grants are FINANCE-01a's and survive `create or
-- replace` untouched; restating them here would only invite them to drift
-- away from the package that owns them.
