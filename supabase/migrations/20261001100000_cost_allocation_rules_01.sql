-- COST-ALLOCATION-RULES-01 (P-2a, first half of Cost Categories + Pools +
-- Allocation Keys).
--
-- Whether a cost may be passed on to tenants, and on which principle it is
-- settled. Both hang off `public.finance_accounts` -- the target model is
-- explicit that this is "Umlagefähigkeit und BetrKV-Zuordnung als Attribut an
-- `finance_accounts`, nicht als neuer Baum", because a second cost-category
-- tree beside the account tree is two places for the same category to exist
-- and one of them to be wrong.
--
-- **A satellite table, not new columns.** `finance_accounts` belongs to
-- P2-D08 and altering it is a change to an existing table's structure. A 1:1
-- satellite keyed on the account is the same "attribute of the account"
-- relationally, and it is the pattern the house already uses --
-- `party_contractor_details` is exactly this shape on `parties`. It also
-- reverts cleanly, which a column added to a live table does not.
--
-- **The settlement principle carries `DEC-014` model consequence 3.**
-- "Abrechnungsprinzip pro Kostenart konfigurierbar, mit hartem Zwang auf das
-- Leistungsprinzip für die HeizkostenV-Positionen (BGH VIII ZR 156/11)." The
-- CHECK below is that hard constraint: a position under the HeizkostenV cannot
-- be settled on the outflow principle. Not a validation the command could skip
-- -- a declarative constraint, because this one is not a matter of taste.
--
-- **`betrkv_position` is free text, and that is a `DEC-014` boundary.** The
-- BetrKV § 2 catalogue is one of the seven points the research lists as
-- source-contradictory and requiring expert confirmation. Shipping a
-- seventeen-value enum here would encode a legal list this project has
-- explicitly not signed off, in a migration, where correcting it costs another
-- migration. The workspace files its own position and the compliance rule
-- layer (V-4) is where a confirmed catalogue would live.
--
-- **`under_heating_cost_regulation` is a fact, not a legal reading.** Whether
-- the HeizkostenV applies to a cost is something the workspace knows about its
-- own accounts. The product does not infer it from the account name, because
-- inferring it wrong picks the settlement principle wrong, and that is the
-- error the constraint above exists to make impossible.
--
-- Two new public functions: SR-20 99 -> 101.
-- One new client-reachable policy: SR-22 52 -> 53.

create type public.cost_settlement_principle as enum (
  -- Leistungsprinzip: costs belong to the period in which the service was
  -- rendered. Mandatory under the HeizkostenV.
  'performance',
  -- Abflussprinzip: costs belong to the period in which they were paid.
  'outflow'
);

create table public.finance_account_allocation_rules (
  -- The account is the key. One rule per account, which is what "an attribute
  -- of the account" means.
  finance_account_id uuid primary key,
  workspace_id uuid not null,

  -- Whether this cost may be passed on to tenants at all. Default false: a
  -- cost nobody has classified is not apportionable, because the reverse
  -- default would silently make every new account billable.
  allocatable boolean not null default false,

  -- The BetrKV § 2 item as the workspace files it. Free text on purpose --
  -- see the header: the catalogue is a contested source under DEC-014.
  betrkv_position text,

  -- Set by the workspace, never inferred. Inferring it from an account name
  -- would pick the settlement principle wrong, which is the error the
  -- constraint below exists to prevent.
  under_heating_cost_regulation boolean not null default false,

  settlement_principle public.cost_settlement_principle,

  note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  constraint finance_account_allocation_rules_workspace_fkey
    foreign key (workspace_id) references public.workspaces (id)
    on delete restrict,
  constraint finance_account_allocation_rules_account_fkey
    foreign key (workspace_id, finance_account_id)
    references public.finance_accounts (workspace_id, id) on delete cascade,

  constraint finance_account_allocation_rules_betrkv_check check (
    betrkv_position is null
    or char_length(btrim(betrkv_position)) between 1 and 200
  ),
  constraint finance_account_allocation_rules_note_check check (
    note is null or char_length(btrim(note)) between 1 and 2000
  ),

  -- DEC-014 model consequence 3, as a declarative constraint rather than a
  -- check the command could be refactored past: a HeizkostenV position is
  -- settled on the performance principle (BGH VIII ZR 156/11). There is no
  -- workspace for which this is a preference.
  constraint finance_account_allocation_rules_heating_principle_check check (
    not under_heating_cost_regulation
    or settlement_principle = 'performance'
  ),

  -- A cost that may be passed on has to say on which principle. One that may
  -- not has no principle to state -- and storing one anyway would leave a
  -- setting that looks meaningful and decides nothing.
  constraint finance_account_allocation_rules_principle_check check (
    (allocatable and settlement_principle is not null)
    or (not allocatable and settlement_principle is null)
  ),

  -- Only an allocatable cost can be a HeizkostenV position: the regulation is
  -- about apportioning heating costs to tenants.
  constraint finance_account_allocation_rules_heating_allocatable_check check (
    not under_heating_cost_regulation or allocatable
  ),

  constraint finance_account_allocation_rules_version_check check (version >= 1)
);

-- Two indexes, and the first is not redundant with the primary key. The
-- account foreign key is composite `(workspace_id, finance_account_id)`, and
-- `004`'s invariant wants an index whose leading columns match it
-- positionally -- the primary key on `finance_account_id` alone does not, and
-- neither does the filter index below.
create index finance_account_allocation_rules_account_idx
  on public.finance_account_allocation_rules (workspace_id, finance_account_id);

-- "Which costs are apportionable" is the question the read answers.
create index finance_account_allocation_rules_workspace_idx
  on public.finance_account_allocation_rules (workspace_id, allocatable);

create trigger finance_account_allocation_rules_protected_columns
before update on public.finance_account_allocation_rules
for each row execute function private.reject_protected_column_update(
  'finance_account_id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.finance_account_allocation_rules
  enable row level security;
alter table public.finance_account_allocation_rules
  force row level security;

create policy finance_account_allocation_rules_select_finance_read
on public.finance_account_allocation_rules
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_account_allocation_rules
  from public, anon, authenticated;
grant select on table public.finance_account_allocation_rules
  to authenticated;

comment on table public.finance_account_allocation_rules is
  'Whether a cost account is apportionable to tenants and on which principle '
  'it settles. A satellite of finance_accounts rather than a second cost '
  'category tree. A HeizkostenV position is settled on the performance '
  'principle by constraint, not by convention.';

-- ---------------------------------------------------------------------------
-- The audit payload
-- ---------------------------------------------------------------------------

create function private.allocation_rule_snapshot(
  rule public.finance_account_allocation_rules
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'finance_account_id', rule.finance_account_id,
    'workspace_id', rule.workspace_id,
    'allocatable', rule.allocatable,
    'betrkv_position', rule.betrkv_position,
    'under_heating_cost_regulation', rule.under_heating_cost_regulation,
    'settlement_principle', rule.settlement_principle,
    'note', rule.note,
    'created_at', rule.created_at,
    'updated_at', rule.updated_at,
    'created_by', rule.created_by,
    'updated_by', rule.updated_by,
    'version', rule.version
  );
$function$;

alter function private.allocation_rule_snapshot(
  public.finance_account_allocation_rules
) owner to postgres;
revoke all on function private.allocation_rule_snapshot(
  public.finance_account_allocation_rules
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

create function public.cost_allocation_rules(
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

  -- Every account, whether or not it has a rule. An account with no rule is
  -- the interesting case: it is unclassified, and a list that showed only the
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
      -- Counted here rather than left to the caller. "How much of this is
      -- still unclassified" is the question the surface exists to answer, and
      -- a client counting its own page would answer it about the page.
      'unclassified_count', v_total - v_classified,
      'total_count', v_total
    )
  );
end;
$function$;

alter function public.cost_allocation_rules(uuid, boolean) owner to postgres;
revoke all on function public.cost_allocation_rules(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.cost_allocation_rules(uuid, boolean)
  to authenticated;

comment on function public.cost_allocation_rules(uuid, boolean) is
  'Every cost account with its allocation rule, or null where none has been '
  'set. Unclassified accounts are listed rather than filtered out, because a '
  'list of only the classified ones makes the work look finished.';

-- ---------------------------------------------------------------------------
-- The write
-- ---------------------------------------------------------------------------

create function public.set_cost_allocation_rule(
  p_workspace_id uuid,
  p_finance_account_id uuid,
  p_allocatable boolean,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_expected_version bigint default null,
  p_settlement_principle text default null,
  p_betrkv_position text default null,
  p_under_heating_cost_regulation boolean default false,
  p_note text default null,
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
  v_claim jsonb;
  v_request_hash bytea;
  v_old public.finance_account_allocation_rules%rowtype;
  v_new public.finance_account_allocation_rules%rowtype;
  v_principle public.cost_settlement_principle;
  v_exists boolean;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_finance_account_id is null or p_allocatable is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Account and allocatable flag are required'
      )
    );
  end if;

  if p_settlement_principle is not null
     and p_settlement_principle not in ('performance', 'outflow') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unknown settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  v_principle := case
    when p_settlement_principle is null then null
    else p_settlement_principle::public.cost_settlement_principle
  end;

  if p_allocatable and v_principle is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An apportionable cost needs a settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  if not p_allocatable and v_principle is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A cost that is not apportionable has no settlement principle',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  -- Order matters. A HeizkostenV position that is not apportionable is wrong
  -- about what kind of cost it is; which principle it settles on is downstream
  -- of that, and reporting the principle first would send the reader to fix
  -- the wrong field.
  if coalesce(p_under_heating_cost_regulation, false) and not p_allocatable then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'The HeizkostenV is about apportioning heating costs, so a position '
          'under it is apportionable',
        'field', 'allocatable'
      )
    );
  end if;

  -- Reported here rather than left to the CHECK, so the message names the law
  -- instead of a constraint. The constraint stays as the thing that actually
  -- cannot be circumvented.
  if coalesce(p_under_heating_cost_regulation, false)
     and v_principle is distinct from 'performance' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A HeizkostenV position is settled on the performance principle '
          '(BGH VIII ZR 156/11)',
        'field', 'settlementPrinciple'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.manage')
     or not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Cost allocation rule write is not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.finance_accounts as account
    where account.workspace_id = p_workspace_id
      and account.id = p_finance_account_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Finance account not found'
      )
    );
  end if;

  select rule.* into v_old
  from public.finance_account_allocation_rules as rule
  where rule.workspace_id = p_workspace_id
    and rule.finance_account_id = p_finance_account_id
  for update;
  v_exists := found;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'set_cost_allocation_rule',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'finance_account_id', p_finance_account_id,
        'allocatable', p_allocatable,
        'settlement_principle', p_settlement_principle,
        'betrkv_position', p_betrkv_position,
        'under_heating_cost_regulation', p_under_heating_cost_regulation,
        'note', p_note,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'cost_allocation_rule'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- After the claim, deliberately. Setting a rule for the first time is a
  -- create and takes no version; changing one takes the version it expects.
  -- But a *retried* create finds the rule its own first call made, and
  -- checking this before the claim would answer that retry with "a version is
  -- required" instead of replaying the original result. Both branches release
  -- the receipt, exactly as the version conflict below does.
  if v_exists and (p_expected_version is null or p_expected_version < 1) then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An expected version is required to change an existing rule',
        'field', 'expectedVersion'
      )
    );
  end if;

  if not v_exists and p_expected_version is not null then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'This account has no rule yet, so there is no version to expect',
        'field', 'expectedVersion'
      )
    );
  end if;

  if v_exists and v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Cost allocation rule version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.allocation_rule_snapshot(v_old)
      )
    );
  end if;

  if v_exists then
    update public.finance_account_allocation_rules as rule
    set
      allocatable = p_allocatable,
      betrkv_position = nullif(btrim(coalesce(p_betrkv_position, '')), ''),
      under_heating_cost_regulation =
        coalesce(p_under_heating_cost_regulation, false),
      settlement_principle = v_principle,
      note = nullif(btrim(coalesce(p_note, '')), ''),
      updated_at = now(),
      updated_by = v_actor_id,
      version = rule.version + 1
    where rule.workspace_id = p_workspace_id
      and rule.finance_account_id = p_finance_account_id
    returning * into v_new;
  else
    insert into public.finance_account_allocation_rules (
      finance_account_id, workspace_id, allocatable, betrkv_position,
      under_heating_cost_regulation, settlement_principle, note,
      created_by, updated_by
    ) values (
      p_finance_account_id, p_workspace_id, p_allocatable,
      nullif(btrim(coalesce(p_betrkv_position, '')), ''),
      coalesce(p_under_heating_cost_regulation, false), v_principle,
      nullif(btrim(coalesce(p_note, '')), ''),
      v_actor_id, v_actor_id
    )
    returning * into v_new;
  end if;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when v_exists
      then 'cost_allocation_rule.update' else 'cost_allocation_rule.create' end,
    'cost_allocation_rule', p_finance_account_id,
    case when v_exists then private.allocation_rule_snapshot(v_old) else null end,
    private.allocation_rule_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.allocation_rule_snapshot(v_new)
  );
end;
$function$;

alter function public.set_cost_allocation_rule(
  uuid, uuid, boolean, uuid, uuid, bigint, text, text, boolean, text, text
) owner to postgres;
revoke all on function public.set_cost_allocation_rule(
  uuid, uuid, boolean, uuid, uuid, bigint, text, text, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.set_cost_allocation_rule(
  uuid, uuid, boolean, uuid, uuid, bigint, text, text, boolean, text, text
) to authenticated;

comment on function public.set_cost_allocation_rule(
  uuid, uuid, boolean, uuid, uuid, bigint, text, text, boolean, text, text
) is
  'Sets whether a cost account is apportionable and on which principle it '
  'settles. Refuses the outflow principle for a HeizkostenV position with a '
  'message naming BGH VIII ZR 156/11; the CHECK constraint behind it is what '
  'makes that impossible rather than merely refused.';
