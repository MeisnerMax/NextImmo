-- FINANCE-COST-TYPES-01 (the cost type tree gets a reachable write path).
--
-- **Two keys, and the first of them is what a list-driven editor was
-- missing.** `public.update_finance_account` takes `p_expected_version bigint`
-- as a required argument — no default — and `public.cost_allocation_rules`,
-- the only read that lists a workspace's accounts, returned
-- `finance_account_id`, `code`, `name`, `account_type`, `is_active` and the
-- allocation rule. It did not return the account's version, so an account a
-- client had not itself just created could not be edited from that list.
--
-- **An earlier draft of this header put that far too strongly**, and the
-- correction belongs here rather than in a commit message. It said no client
-- could call the update at all, because there was no way to learn the version.
-- That is false, and an adversarial review demonstrated it live:
-- `private.finance_account_snapshot` carries `version`, so
-- `create_finance_account` returns it in its success payload, and
-- `update_finance_account` returns it inside its own `version_conflict` error.
-- A client could always learn the number — by having created the account, or
-- by calling the update with any value and reading the current version out of
-- the refusal (the version check sits ahead of the mutation claim, so that
-- probe consumes no mutation id and writes no audit row). The real gap was
-- narrower and is the one this migration closes: the *list* could show
-- accounts it could not edit.
--
-- `FINANCE-01a` shipped `create_finance_account`, `update_finance_account`,
-- `record_finance_ledger_entry`, `open_finance_period` and
-- `transition_finance_period_status` — all audited, all idempotent, all
-- granted to `authenticated`. (An earlier draft also claimed its header said
-- no screen drove them yet; it says no such thing, and the sentence is
-- withdrawn.) Two packages later the reads exist: `cost_allocation_rules`
-- (P-2a) lists the accounts, and the pools and keys (P-2b, P-2c) hang off
-- them. What nobody noticed is that a workspace with no accounts had no way
-- to make the first from inside the application — so the cost-allocation
-- surface opened on an empty list whose own empty state says "Ohne Konten
-- gibt es nichts einzuordnen", and stayed there.
--
-- **Nothing else changes.** No new table, no new function, no new policy, no
-- new permission. The counters SR-20, SR-22 and SR-23 do not move, and the
-- private function inventory is untouched: this is a `create or replace` that
-- adds two keys to a payload — `version` and `parent_account_id`. The package
-- that goes with it is otherwise entirely client-side, which is why it
-- carries a migration this small.
--
-- **The code stays absent from the update on purpose.** `update_finance_account`
-- accepts a name, a parent and an active flag, and not a code. A code is what
-- a booking, a report and an export cite; renaming one silently re-points
-- every line that quoted it. The client says so in the form rather than
-- offering a field the server would ignore.

create or replace function public.cost_allocation_rules(
  p_workspace_id uuid,
  p_allocatable_only boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_accounts jsonb;
  v_classified integer;
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
        'code', 'forbidden', 'message', 'Cost allocation rules are not permitted'
      )
    );
  end if;

  -- Every account, classified or not. An unclassified account is the
  -- interesting case: it is unclassified, and a list that showed only the
  -- classified ones would make the work look finished.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'finance_account_id', account.id,
          'code', account.code,
          'name', account.name,
          'account_type', account.account_type,
          'is_active', account.is_active,
          -- The account's own version, not the rule's -- `rule` below nests a
          -- snapshot with a `version` of its own, and sending that one would
          -- be refused by a command that never mentions it. Without this key
          -- an account could not be edited from the list that shows it.
          'version', account.version,
          'parent_account_id', account.parent_account_id,
          'rule', case
            when rule.finance_account_id is null then null
            else private.allocation_rule_snapshot(rule)
          end
        )
        order by account.code
      ),
      '[]'::jsonb
    ),
    count(*) filter (where rule.finance_account_id is not null)::integer,
    count(*)::integer
  into v_accounts, v_classified, v_total
  from public.finance_accounts as account
  left join public.finance_account_allocation_rules as rule
    on rule.workspace_id = account.workspace_id
    and rule.finance_account_id = account.id
  where account.workspace_id = p_workspace_id
    and (not p_allocatable_only or rule.allocatable);

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'accounts', v_accounts,
      'classified_count', v_classified,
      -- Counted by the server over the accounts this call selected, not by the
      -- caller over the rows it happens to hold. With the default
      -- `p_allocatable_only = false` that is every account in the workspace,
      -- which is the reading the surface uses; with the flag on, the WHERE
      -- clause has already excluded everything unclassified, so
      -- `unclassified_count` is necessarily 0 and says nothing. An earlier
      -- draft of this comment claimed the counts always span the workspace,
      -- which is only true of the default.
      'unclassified_count', v_total - v_classified,
      'total_count', v_total
    )
  );
end;
$function$;

comment on function public.cost_allocation_rules(uuid, boolean) is
  'Every cost account of a workspace with its allocation rule or null, plus '
  'the account version that update_finance_account requires. Unclassified '
  'accounts are listed rather than filtered away: they are the work.';
