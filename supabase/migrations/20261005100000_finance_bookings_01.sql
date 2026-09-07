-- FINANCE-BOOKINGS-01 (the ledger becomes reachable, and a booking lands in
-- the period it says it does).
--
-- **Why this package exists, stated plainly.** Five packages have now shipped
-- that classify and configure costs — P-2a decided which are apportionable,
-- P-2b built the pools and the distribution keys, P-2c the per-unit basis
-- figures, F-1 made the cost types creatable. Not one of them produces a
-- number, because nothing can record what a property actually spent.
-- `record_finance_ledger_entry` has existed since `FINANCE-01a`, audited,
-- idempotent and granted to `authenticated`, and no client calls it. So
-- `finance_ledger_entries` is empty in every workspace, and
-- `Investment → Performance → Ergebnis` renders an empty statement for every
-- property and always will.
--
-- This is the same shape of gap `FINANCE-COST-TYPES-01` closed one layer up,
-- and it was found the same way: by asking which server commands nothing
-- calls, rather than by reading a plan.
--
-- **Two reads, because a booking form cannot work without them.**
--
--   * `workspace_finance_periods` — nothing lists periods. A client could
--     only learn a period existed by trying to open it and being told it
--     already exists, a refusal that deliberately carries no entity. So a
--     period picker was impossible and `open_finance_period` was, in
--     practice, write-only.
--   * `property_finance_ledger_entries` — nothing lists entries.
--     `property_finance_actuals` sums per account and currency and reports
--     `entries` as a *count*; there is no way to see what was booked, which
--     means no way to notice a mistake. That matters more here than usual,
--     because of the next paragraph.
--
-- **A booking cannot be corrected, and this package does not pretend
-- otherwise.** There is no update, no delete and no reversal command, no
-- write policy on the table, and no column linking a correction to what it
-- corrects. The only path is a compensating counter-booking with a negated
-- amount — the amount column is deliberately signed, so that works, and the
-- client says so rather than offering an edit that cannot exist. A real
-- reversal (with a link, and a refusal to reverse twice) is a package of its
-- own and is not smuggled in here.
--
-- **One correctness fix, and it is not cosmetic.**
-- `record_finance_ledger_entry` validated the account, the property, the
-- unit, the lease and the period's open status — and never that `booked_on`
-- falls inside the period it is being booked into. A cost dated 2024-03-15
-- was accepted into period 2026/01. Every figure this package exists to feed
-- is grouped by period, so a booking in the wrong period is a wrong number in
-- every read downstream of it, silently. The check is added here, before the
-- first client can produce such a row. Every booking in the existing test
-- suite already falls inside its period, so nothing that was correct becomes
-- refused.
--
-- Counters this migration moves, deliberately:
--   SR-20  107 -> 109  (two new public functions)
--   SR-22  unchanged   (no new table, no new policy)
--   private function inventory: unchanged (no new private function)

-- ---------------------------------------------------------------------------
-- The periods a workspace has
-- ---------------------------------------------------------------------------

create function public.workspace_finance_periods(
  p_workspace_id uuid,
  p_include_closed boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_periods jsonb;
  v_open integer;
  v_total integer;
begin
  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace is required',
        'field', 'workspaceId'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance periods are not permitted'
      )
    );
  end if;

  select
    coalesce(
      jsonb_agg(
        private.finance_period_snapshot(period)
        || jsonb_build_object(
             -- Counted here so a closing decision can be made from the list.
             -- Closing a period that still has nothing in it is usually a
             -- mistake, and closing one with entries is the normal act; the
             -- caller should be able to tell them apart without a second read.
             'entry_count', (
               select count(*)
               from public.finance_ledger_entries as entry
               where entry.workspace_id = period.workspace_id
                 and entry.period_id = period.id
             )
           )
        order by period.fiscal_year desc, period.period_month desc
      ),
      '[]'::jsonb
    ),
    count(*) filter (where period.status = 'open')::integer,
    count(*)::integer
  into v_periods, v_open, v_total
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id
    and (p_include_closed or period.status = 'open');

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'periods', v_periods,
      'open_count', v_open,
      'total_count', v_total
    )
  );
end;
$function$;

alter function public.workspace_finance_periods(uuid, boolean) owner to postgres;
revoke all on function public.workspace_finance_periods(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.workspace_finance_periods(uuid, boolean)
  to authenticated;

comment on function public.workspace_finance_periods(uuid, boolean) is
  'The accounting periods of a workspace, newest first, each with how many '
  'ledger entries it holds. Without this a period could only be discovered by '
  'trying to open it and being told it already exists -- a refusal that '
  'carries no entity, so `open_finance_period` was write-only in practice.';

-- ---------------------------------------------------------------------------
-- What was actually booked
-- ---------------------------------------------------------------------------

create function public.property_finance_ledger_entries(
  p_workspace_id uuid,
  p_property_id uuid,
  p_period_id uuid default null,
  p_account_id uuid default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_entries jsonb;
  v_total integer;
begin
  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace and property are required'
      )
    );
  end if;

  -- The same two gates in the same order as `property_finance_actuals`: the
  -- entity scope first, then the workspace permission. This read returns one
  -- property's spending line by line, which is more than the aggregate does.
  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'This property is not permitted'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance entries are not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
      and property.deleted_at is null
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found'
      )
    );
  end if;

  select
    coalesce(
      jsonb_agg(row.payload order by row.booked_on desc, row.created_at desc),
      '[]'::jsonb
    ),
    max(row.total)::integer
  into v_entries, v_total
  from (
    select
      entry.booked_on,
      entry.created_at,
      count(*) over ()::integer as total,
      private.finance_entry_snapshot(entry)
        || jsonb_build_object(
             -- Joined in so a list reads without a second round trip. An
             -- entry that names an account id and nothing else is not a line
             -- anybody can check.
             'account_code', account.code,
             'account_name', account.name,
             'account_type', account.account_type,
             'period_fiscal_year', period.fiscal_year,
             'period_month', period.period_month,
             'period_status', period.status,
             'unit_code', unit.unit_code,
             -- Said per line, because it decides whether this cost can appear
             -- on a service-charge statement at all. Null means nobody has
             -- classified the cost type yet -- which is not the same as "not
             -- apportionable", and the two must not render alike.
             'allocatable', rule.allocatable,
             'settlement_principle', rule.settlement_principle
           ) as payload
    from public.finance_ledger_entries as entry
    join public.finance_accounts as account
      on account.workspace_id = entry.workspace_id
      and account.id = entry.account_id
    join public.finance_periods as period
      on period.workspace_id = entry.workspace_id
      and period.id = entry.period_id
    left join public.units as unit
      on unit.workspace_id = entry.workspace_id
      and unit.id = entry.unit_id
    left join public.finance_account_allocation_rules as rule
      on rule.workspace_id = entry.workspace_id
      and rule.finance_account_id = entry.account_id
    where entry.workspace_id = p_workspace_id
      and entry.property_id = p_property_id
      and (p_period_id is null or entry.period_id = p_period_id)
      and (p_account_id is null or entry.account_id = p_account_id)
    order by entry.booked_on desc, entry.created_at desc
    limit v_limit
  ) as row;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'entries', v_entries,
      -- How many the filter matched, which is what the caller needs to know
      -- whether the page in hand is the whole answer. `count(*) over ()` is
      -- computed inside the limited subquery, so it counts the returned rows;
      -- the separate count below is the honest total.
      'returned_count', coalesce(jsonb_array_length(v_entries), 0),
      'total_count', (
        select count(*)::integer
        from public.finance_ledger_entries as entry
        where entry.workspace_id = p_workspace_id
          and entry.property_id = p_property_id
          and (p_period_id is null or entry.period_id = p_period_id)
          and (p_account_id is null or entry.account_id = p_account_id)
      ),
      'limit', v_limit
    )
  );
end;
$function$;

alter function public.property_finance_ledger_entries(
  uuid, uuid, uuid, uuid, integer
) owner to postgres;
revoke all on function public.property_finance_ledger_entries(
  uuid, uuid, uuid, uuid, integer
) from public, anon, authenticated;
grant execute on function public.property_finance_ledger_entries(
  uuid, uuid, uuid, uuid, integer
) to authenticated;

comment on function public.property_finance_ledger_entries(
  uuid, uuid, uuid, uuid, integer
) is
  'What a property actually spent, line by line, with the cost type and '
  'whether it is apportionable. `property_finance_actuals` sums; this one '
  'shows the rows, which is what makes a mis-booking noticeable at all -- and '
  'a booking cannot be edited or deleted, so noticing is the only remedy.';

-- ---------------------------------------------------------------------------
-- A booking lands in the period it says it does
-- ---------------------------------------------------------------------------
--
-- Replaced in place: the body below is FINANCE-01a's, unchanged, plus one
-- validation. It is reproduced in full rather than patched because a
-- `create or replace` replaces the whole body, and a reader comparing this
-- against the original should be able to see exactly one addition.

CREATE OR REPLACE FUNCTION public.record_finance_ledger_entry(p_workspace_id uuid, p_property_id uuid, p_account_id uuid, p_period_id uuid, p_booked_on date, p_amount numeric, p_currency_code text, p_mutation_id uuid, p_correlation_id uuid, p_description text DEFAULT NULL::text, p_unit_id uuid DEFAULT NULL::uuid, p_lease_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_claim jsonb;
  v_period public.finance_periods%rowtype;
  v_row public.finance_ledger_entries%rowtype;
  v_new_values jsonb;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_amount is null or p_amount = 'NaN'::numeric then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'An amount is required',
        'field', 'amount'
      )
    );
  end if;

  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A three-letter ISO currency is required',
        'field', 'currency_code'
      )
    );
  end if;

  if p_booked_on is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A booking date is required',
        'field', 'booked_on'
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

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id and property.id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if not exists (
    select 1 from public.finance_accounts as account
    where account.workspace_id = p_workspace_id
      and account.id = p_account_id
      and account.is_active
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found',
        'message', 'Account not found or retired',
        'field', 'account_id'
      )
    );
  end if;

  select * into v_period
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id and period.id = p_period_id;

  if v_period.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Period not found', 'field', 'period_id'
      )
    );
  end if;

  -- Added by FINANCE-BOOKINGS-01. Until now this command validated the
  -- account, the property, the unit, the lease and whether the period was
  -- open -- and never that the booking date fell inside the period it was
  -- being booked into. A cost dated 2024-03-15 was accepted into 2026/01.
  --
  -- Every figure built on this table is grouped by period, so a booking in
  -- the wrong period is a wrong number in every read downstream of it, and
  -- silently: nothing anywhere compares the two. The check sits before the
  -- claim because it is a property of the request rather than of stored
  -- state -- a corrected retry with the same mutation id must be able to
  -- proceed.
  if extract(year from p_booked_on)::integer <> v_period.fiscal_year
     or extract(month from p_booked_on)::integer <> v_period.period_month then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'The booking date is not inside that period: ' ||
          to_char(p_booked_on, 'YYYY-MM-DD') || ' against ' ||
          v_period.fiscal_year || '-' ||
          lpad(v_period.period_month::text, 2, '0'),
        'field', 'booked_on'
      )
    );
  end if;

  if p_unit_id is not null and not exists (
    select 1 from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.id = p_unit_id
      and unit.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The unit does not belong to this property',
        'field', 'unit_id'
      )
    );
  end if;

  if p_lease_id is not null and not exists (
    select 1 from public.leases as lease
    where lease.workspace_id = p_workspace_id
      and lease.id = p_lease_id
      and lease.property_id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The lease does not belong to this property',
        'field', 'lease_id'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'record_finance_ledger_entry',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'account_id', p_account_id,
        'period_id', p_period_id,
        'booked_on', p_booked_on,
        'amount', p_amount,
        'currency_code', p_currency_code,
        'description', p_description,
        'unit_id', p_unit_id,
        'lease_id', p_lease_id,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'finance_ledger_entry'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- Behind the claim: an entry booked into an open period and retried after
  -- the period closed must replay its receipt, not be refused for a state
  -- that did not hold when the command was accepted.
  if v_period.status = 'closed'::public.finance_period_status then
    perform private.fail_finance_mutation(p_workspace_id, p_mutation_id);
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message', 'The period is closed and cannot receive entries',
        'field', 'period_id'
      )
    );
  end if;

  insert into public.finance_ledger_entries (
    workspace_id, property_id, account_id, period_id, booked_on, amount,
    currency_code, description, source, unit_id, lease_id,
    created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, p_account_id, p_period_id, p_booked_on,
    p_amount, p_currency_code, nullif(btrim(p_description), ''), 'manual',
    p_unit_id, p_lease_id, v_actor_id, v_actor_id
  )
  returning * into v_row;

  v_new_values := private.finance_entry_snapshot(v_row);

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'create', 'finance_ledger_entry', v_row.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$function$
;
