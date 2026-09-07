-- SUPPLIER-CONTRACTS-01 (P-3, second half of Suppliers + Contracts).
--
-- A service or utility contract with a supplier: the lift maintenance, the
-- heating service, the waste collection, the insurance broker's mandate. The
-- programme's inventory records that this exists nowhere -- "Lieferant ist
-- heute ein Freitextfeld auf der Kostenzeile" -- and names what it should be.
-- This is that.
--
-- **A supplier is a party.** The FK points at `public.parties`, not at a new
-- supplier table. A company that is both a contractor on tickets and the
-- counterparty of a framework contract is one row with one name and one
-- address, which is the whole reason P2-D02 replaced the standalone legacy
-- contractor table.
--
-- **Deadlines are derived, never stored.** The target model says so in one
-- line -- "Fristen werden abgeleitet gelesen, nicht persistiert" -- and the
-- reason is the one finding B-4 already forced on the alert reader: there is
-- no scheduler. A stored notice deadline goes stale the moment somebody
-- corrects the end date, and nothing exists to recompute it. So the table
-- holds the *terms* (end date, notice period in days, renewal) and the read
-- computes the deadline against the date it was asked for.
--
-- **What it deliberately does not compute: a chain of future renewals.** An
-- auto-renewing contract has infinitely many renewal dates, and projecting
-- them is a calendar. A calendar wants a scheduler to fire from, and this
-- stack has none -- so the read answers about the *next* one and stops.
--
-- **Permission is `party.read`/`party.manage`, deliberately.** A supplier
-- contract is part of the supplier relationship, and the register it hangs off
-- is already gated that way. Inventing a `contract.manage` capability here
-- would put a new key in the permission catalogue without a decision behind
-- it, and a capability nobody has decided who holds is a capability that gets
-- granted to everyone. If the owner wants contracts separable from the party
-- directory, that is a catalogue change with its own review.
--
-- Four new public functions: SR-20 95 -> 99.
-- One new client-reachable policy: SR-22 51 -> 52.

-- ---------------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------------

create table public.supplier_contracts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  party_id uuid not null,

  -- Null means the whole portfolio, which is what a framework contract
  -- usually is. Scoping every contract to one property would force a lift
  -- maintenance agreement covering nine buildings to be entered nine times,
  -- and then to be corrected nine times.
  property_id uuid,

  title text not null,

  -- Free text, for the same reason `maintenance_tickets.category` is: an enum
  -- would be the tidier schema and the worse product, because a workspace
  -- that already files its contracts its own way would have that vocabulary
  -- rejected by a migration.
  contract_type text not null,

  scope_note text,

  status text not null default 'draft',

  start_date date not null,
  -- Null is open-ended: a supply contract with no agreed end is normal, not
  -- missing data.
  end_date date,

  -- Null means no notice period was agreed, which is a different statement
  -- from "the notice period is zero days". The read reports the difference.
  notice_period_days integer,

  auto_renew boolean not null default false,
  renewal_term_months integer,

  annual_value numeric(14, 2),
  currency_code text,

  ended_at timestamptz,
  ended_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  constraint supplier_contracts_workspace_id_key unique (workspace_id, id),
  constraint supplier_contracts_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint supplier_contracts_party_fkey foreign key (workspace_id, party_id)
    references public.parties (workspace_id, id) on delete restrict,
  -- Single-column, like every other table that points at a property. A
  -- composite (workspace_id, id) key would be stronger, but `public.properties`
  -- carries no such unique constraint and adding one is a change to an existing
  -- table's structure. The same gap and the same resolution as P2-D05 and
  -- P2-D07: the commands verify the property's workspace explicitly before they
  -- write, which is why both of them do that check above.
  constraint supplier_contracts_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,

  constraint supplier_contracts_title_check check (
    char_length(btrim(title)) between 1 and 200
  ),
  constraint supplier_contracts_type_check check (
    char_length(btrim(contract_type)) between 1 and 100
    and contract_type = btrim(contract_type)
  ),
  constraint supplier_contracts_scope_note_check check (
    scope_note is null or char_length(btrim(scope_note)) between 1 and 2000
  ),
  constraint supplier_contracts_status_check check (
    status in ('draft', 'active', 'ended')
  ),
  constraint supplier_contracts_term_check check (
    end_date is null or end_date >= start_date
  ),
  -- Ten years. Not a business rule, a typo guard: a four-digit notice period
  -- is somebody who meant months.
  constraint supplier_contracts_notice_check check (
    notice_period_days is null
    or (notice_period_days >= 0 and notice_period_days <= 3650)
  ),
  -- A renewal needs something to renew *to*. Auto-renewal on an open-ended
  -- contract is a contradiction, and a term of zero months is a loop.
  constraint supplier_contracts_renewal_check check (
    (auto_renew
      and end_date is not null
      and renewal_term_months is not null
      and renewal_term_months > 0)
    or (not auto_renew and renewal_term_months is null)
  ),
  constraint supplier_contracts_value_check check (
    annual_value is null
    or (annual_value >= 0 and annual_value <> 'NaN'::numeric)
  ),
  -- An amount without a currency is not a figure. The same rule the rest of
  -- the money surface holds.
  --
  -- `currency_code is not null` is not redundant, and leaving it out was a
  -- real defect the test caught. With a null currency the comparison
  -- `currency_code = upper(btrim(currency_code))` evaluates to NULL, the whole
  -- branch to NULL, and `false or NULL` to NULL -- and a CHECK that evaluates
  -- to NULL is **satisfied**. The constraint would have accepted exactly the
  -- row it exists to reject.
  constraint supplier_contracts_currency_check check (
    (annual_value is null and currency_code is null)
    or (
      annual_value is not null
      and currency_code is not null
      and currency_code = upper(btrim(currency_code))
      and char_length(currency_code) = 3
    )
  ),
  -- The terminal state carries its stamp, like every other lifecycle in this
  -- schema. A contract that is `ended` with no `ended_at` cannot be ordered
  -- against anything.
  constraint supplier_contracts_ended_check check (
    (status = 'ended' and ended_at is not null)
    or (status <> 'ended' and ended_at is null and ended_reason is null)
  ),
  constraint supplier_contracts_ended_reason_check check (
    ended_reason is null or char_length(btrim(ended_reason)) between 1 and 2000
  ),
  constraint supplier_contracts_version_check check (version >= 1)
);

create index supplier_contracts_party_idx
  on public.supplier_contracts (workspace_id, party_id);
-- `property_id` leads, not `workspace_id`. The foreign key is single-column
-- (properties carries no composite unique key), and `004`'s invariant requires
-- an index whose leading columns match the key positionally -- a
-- `(workspace_id, property_id)` index does not support it, which is how this
-- was caught. The read filters on both columns either way, and property is the
-- selective one.
create index supplier_contracts_property_idx
  on public.supplier_contracts (property_id, workspace_id)
  where property_id is not null;
create index supplier_contracts_status_idx
  on public.supplier_contracts (workspace_id, status);
-- The deadline read filters and orders on this, and a contract running out is
-- the question the surface exists to answer.
create index supplier_contracts_end_date_idx
  on public.supplier_contracts (workspace_id, end_date)
  where end_date is not null;

create trigger supplier_contracts_protected_columns
before update on public.supplier_contracts
-- Named, not empty: the trigger reads its protected columns from `tg_argv`,
-- and calling it with none makes that array NULL rather than empty, which
-- fails on the first update with "FOREACH expression must not be null".
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.supplier_contracts enable row level security;
alter table public.supplier_contracts force row level security;

create policy supplier_contracts_select_party_read
on public.supplier_contracts
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'party.read'));

revoke all on table public.supplier_contracts from public, anon, authenticated;
grant select on table public.supplier_contracts to authenticated;

comment on table public.supplier_contracts is
  'Service and utility contracts with a supplier party. Holds the terms; the '
  'notice deadline is computed by supplier_contracts_as_of against the date '
  'it is asked for, never stored -- there is no scheduler to recompute a '
  'stored one when somebody corrects the end date.';

-- ---------------------------------------------------------------------------
-- The audit payload
-- ---------------------------------------------------------------------------

create function private.supplier_contract_snapshot(
  contract public.supplier_contracts
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', contract.id,
    'workspace_id', contract.workspace_id,
    'party_id', contract.party_id,
    'property_id', contract.property_id,
    'title', contract.title,
    'contract_type', contract.contract_type,
    'scope_note', contract.scope_note,
    'status', contract.status,
    'start_date', contract.start_date,
    'end_date', contract.end_date,
    'notice_period_days', contract.notice_period_days,
    'auto_renew', contract.auto_renew,
    'renewal_term_months', contract.renewal_term_months,
    'annual_value', contract.annual_value,
    'currency_code', contract.currency_code,
    'ended_at', contract.ended_at,
    'ended_reason', contract.ended_reason,
    'created_at', contract.created_at,
    'updated_at', contract.updated_at,
    'created_by', contract.created_by,
    'updated_by', contract.updated_by,
    'version', contract.version
  );
$function$;

alter function private.supplier_contract_snapshot(public.supplier_contracts)
  owner to postgres;
revoke all on function private.supplier_contract_snapshot(public.supplier_contracts)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The derived deadline, in one place
-- ---------------------------------------------------------------------------

create function private.supplier_contract_deadlines(
  p_status text,
  p_start_date date,
  p_end_date date,
  p_notice_period_days integer,
  p_auto_renew boolean,
  p_as_of date
)
returns jsonb
language sql
immutable
set search_path = ''
as $function$
  select jsonb_build_object(
    -- Whether the contract is running on the date asked about. A draft is not,
    -- and neither is one that has ended -- status first, dates second.
    'is_effective',
      p_status = 'active'
      and p_start_date <= p_as_of
      and (p_end_date is null or p_end_date >= p_as_of),
    -- The last day notice can be given. Null when there is no end date or no
    -- agreed notice period -- and those are different absences, which the two
    -- source fields already report separately.
    'notice_deadline',
      case
        when p_end_date is null or p_notice_period_days is null then null
        else p_end_date - p_notice_period_days
      end,
    'days_to_notice',
      case
        when p_end_date is null or p_notice_period_days is null then null
        else (p_end_date - p_notice_period_days) - p_as_of
      end,
    -- The single most useful fact on this surface: it is too late to stop
    -- this contract running on. True only while the contract is still
    -- running, because a deadline behind an ended contract is history.
    'notice_deadline_passed',
      case
        when p_end_date is null or p_notice_period_days is null
             or p_status <> 'active' then false
        else (p_end_date - p_notice_period_days) < p_as_of
             and p_end_date >= p_as_of
      end,
    'notice_window_open',
      case
        when p_end_date is null or p_notice_period_days is null
             or p_status <> 'active' then false
        else p_as_of <= (p_end_date - p_notice_period_days)
             and p_end_date >= p_as_of
      end,
    -- What happens at the end date, stated once rather than left to the
    -- reader to infer from `auto_renew` and a date. Deliberately not a chain:
    -- an auto-renewing contract has infinitely many renewal dates, and
    -- projecting them is a calendar that wants a scheduler this stack has not
    -- got.
    'ends_on', case when p_status = 'ended' then null else p_end_date end,
    'renews_on',
      case
        when p_auto_renew and p_status = 'active' then p_end_date
        else null
      end
  );
$function$;

alter function private.supplier_contract_deadlines(
  text, date, date, integer, boolean, date
) owner to postgres;
revoke all on function private.supplier_contract_deadlines(
  text, date, date, integer, boolean, date
) from public, anon, authenticated;

comment on function private.supplier_contract_deadlines(
  text, date, date, integer, boolean, date
) is
  'The notice arithmetic, once. Immutable and parameterised rather than a '
  'query over the table, so the list read and any later single-contract read '
  'cannot disagree about whether a deadline has passed.';

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

create function public.supplier_contracts_as_of(
  p_workspace_id uuid,
  p_as_of date default null,
  p_party_id uuid default null,
  p_property_id uuid default null,
  p_include_ended boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, private.operations_today());
  v_contracts jsonb;
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

  if not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Supplier contracts are not permitted'
      )
    );
  end if;

  select coalesce(
    jsonb_agg(
      private.supplier_contract_snapshot(contract)
      || private.supplier_contract_deadlines(
           contract.status, contract.start_date, contract.end_date,
           contract.notice_period_days, contract.auto_renew, v_as_of
         )
      || jsonb_build_object('party_name', party.display_name)
      -- Soonest end first, so the thing about to run out is at the top.
      -- Nulls last: an open-ended contract has no deadline and is not urgent.
      order by contract.end_date asc nulls last, contract.title
    ),
    '[]'::jsonb
  )
  into v_contracts
  from public.supplier_contracts as contract
  join public.parties as party
    on party.workspace_id = contract.workspace_id
    and party.id = contract.party_id
  where contract.workspace_id = p_workspace_id
    and (p_party_id is null or contract.party_id = p_party_id)
    and (p_property_id is null or contract.property_id = p_property_id)
    -- Ended contracts are out by default and reachable on request. "What did
    -- we agree with them before" is a real question, and it is not the
    -- question a worklist asks.
    and (p_include_ended or contract.status <> 'ended');

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'contracts', v_contracts
    )
  );
end;
$function$;

alter function public.supplier_contracts_as_of(uuid, date, uuid, uuid, boolean)
  owner to postgres;
revoke all on function public.supplier_contracts_as_of(uuid, date, uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.supplier_contracts_as_of(uuid, date, uuid, uuid, boolean)
  to authenticated;

comment on function public.supplier_contracts_as_of(uuid, date, uuid, uuid, boolean) is
  'Supplier contracts with their notice deadlines computed against p_as_of. '
  'Ended ones are excluded unless asked for. The deadline is never read from '
  'a column, because a stored one goes stale the moment an end date is '
  'corrected and nothing exists to recompute it.';

-- ---------------------------------------------------------------------------
-- create
-- ---------------------------------------------------------------------------

create function public.create_supplier_contract(
  p_workspace_id uuid,
  p_party_id uuid,
  p_title text,
  p_contract_type text,
  p_start_date date,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_property_id uuid default null,
  p_scope_note text default null,
  p_end_date date default null,
  p_notice_period_days integer default null,
  p_auto_renew boolean default false,
  p_renewal_term_months integer default null,
  p_annual_value numeric default null,
  p_currency_code text default null,
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
  v_new public.supplier_contracts%rowtype;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_party_id is null or p_start_date is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Supplier and start date are required'
      )
    );
  end if;

  if p_title is null or char_length(btrim(p_title)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Title is invalid',
        'field', 'title'
      )
    );
  end if;

  if p_contract_type is null
     or char_length(btrim(p_contract_type)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Contract type is invalid',
        'field', 'contractType'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Supplier contract create is not permitted'
      )
    );
  end if;

  if not exists (
    select 1 from public.parties as party
    where party.workspace_id = p_workspace_id
      and party.id = p_party_id
      and party.deleted_at is null
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Supplier not found'
      )
    );
  end if;

  if p_property_id is not null and not exists (
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

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_supplier_contract',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'party_id', p_party_id,
        'property_id', p_property_id,
        'title', p_title,
        'contract_type', p_contract_type,
        'start_date', p_start_date,
        'end_date', p_end_date,
        'notice_period_days', p_notice_period_days,
        'auto_renew', p_auto_renew,
        'renewal_term_months', p_renewal_term_months,
        'annual_value', p_annual_value,
        'currency_code', p_currency_code,
        'scope_note', p_scope_note,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'supplier_contract'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  begin
    insert into public.supplier_contracts (
      workspace_id, party_id, property_id, title, contract_type, scope_note,
      status, start_date, end_date, notice_period_days, auto_renew,
      renewal_term_months, annual_value, currency_code, created_by, updated_by
    ) values (
      p_workspace_id, p_party_id, p_property_id, btrim(p_title),
      btrim(p_contract_type),
      nullif(btrim(coalesce(p_scope_note, '')), ''),
      -- Opens as a draft, like every other entity with a lifecycle here.
      -- Promoting it to active is an explicit, audited update.
      'draft', p_start_date, p_end_date, p_notice_period_days,
      coalesce(p_auto_renew, false), p_renewal_term_months, p_annual_value,
      nullif(upper(btrim(coalesce(p_currency_code, ''))), ''),
      v_actor_id, v_actor_id
    )
    returning * into v_new;
  exception when check_violation then
    -- The CHECKs are the contract's own rules -- a renewal without a term, an
    -- amount without a currency, an end before a start. Reported as a
    -- validation failure rather than escaping as a raw constraint name.
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The contract terms are inconsistent'
      )
    );
  end;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'supplier_contract.create', 'supplier_contract', v_new.id,
    null, private.supplier_contract_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.supplier_contract_snapshot(v_new)
  );
end;
$function$;

alter function public.create_supplier_contract(
  uuid, uuid, text, text, date, uuid, uuid, uuid, text, date, integer,
  boolean, integer, numeric, text, text
) owner to postgres;
revoke all on function public.create_supplier_contract(
  uuid, uuid, text, text, date, uuid, uuid, uuid, text, date, integer,
  boolean, integer, numeric, text, text
) from public, anon, authenticated;
grant execute on function public.create_supplier_contract(
  uuid, uuid, text, text, date, uuid, uuid, uuid, text, date, integer,
  boolean, integer, numeric, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------

create function public.update_supplier_contract(
  p_workspace_id uuid,
  p_contract_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_changes jsonb,
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
  v_old public.supplier_contracts%rowtype;
  v_new public.supplier_contracts%rowtype;
  v_allowed_keys constant text[] := array[
    'title', 'contract_type', 'scope_note', 'status', 'property_id',
    'start_date', 'end_date', 'notice_period_days', 'auto_renew',
    'renewal_term_months', 'annual_value', 'currency_code'
  ];
  v_unknown_keys text[];
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_contract_id is null or p_expected_version is null
     or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Contract id and expected version are required'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object'
     or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Changes must be a non-empty object', 'field', 'changes'
      )
    );
  end if;

  select array_agg(change_key order by change_key)
  into v_unknown_keys
  from jsonb_object_keys(p_changes) as change(change_key)
  where not (change_key = any (v_allowed_keys));

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Changes contain unsupported fields',
        'fields', to_jsonb(v_unknown_keys)
      )
    );
  end if;

  -- Ending a contract is `end_supplier_contract`, which demands a reason and
  -- stamps the date. Allowing it through a field edit would let the terminal
  -- state be reached without either.
  if p_changes ? 'status' and (
       jsonb_typeof(p_changes -> 'status') <> 'string'
       or p_changes ->> 'status' not in ('draft', 'active')
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Status must be draft or active; ending has its own command',
        'field', 'status'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Supplier contract update is not permitted'
      )
    );
  end if;

  select contract.*
  into v_old
  from public.supplier_contracts as contract
  where contract.workspace_id = p_workspace_id
    and contract.id = p_contract_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Supplier contract not found'
      )
    );
  end if;

  if v_old.status = 'ended' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An ended contract cannot be edited'
      )
    );
  end if;

  if p_changes ? 'property_id'
     and jsonb_typeof(p_changes -> 'property_id') = 'string'
     and not exists (
       select 1 from public.properties as property
       where property.workspace_id = p_workspace_id
         and property.id = (p_changes ->> 'property_id')::uuid
         and property.deleted_at is null
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_supplier_contract',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'contract_id', p_contract_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason,
        'changes', p_changes
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'supplier_contract'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Supplier contract version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.supplier_contract_snapshot(v_old)
      )
    );
  end if;

  begin
    update public.supplier_contracts as contract
    set
      title = case
        when p_changes ? 'title' then btrim(p_changes ->> 'title')
        else contract.title end,
      contract_type = case
        when p_changes ? 'contract_type'
          then btrim(p_changes ->> 'contract_type')
        else contract.contract_type end,
      scope_note = case
        when p_changes ? 'scope_note'
          then nullif(btrim(coalesce(p_changes ->> 'scope_note', '')), '')
        else contract.scope_note end,
      status = case
        when p_changes ? 'status' then p_changes ->> 'status'
        else contract.status end,
      property_id = case
        when p_changes ? 'property_id'
          then (p_changes ->> 'property_id')::uuid
        else contract.property_id end,
      start_date = case
        when p_changes ? 'start_date' then (p_changes ->> 'start_date')::date
        else contract.start_date end,
      end_date = case
        when p_changes ? 'end_date' then (p_changes ->> 'end_date')::date
        else contract.end_date end,
      notice_period_days = case
        when p_changes ? 'notice_period_days'
          then (p_changes ->> 'notice_period_days')::integer
        else contract.notice_period_days end,
      auto_renew = case
        when p_changes ? 'auto_renew' then (p_changes ->> 'auto_renew')::boolean
        else contract.auto_renew end,
      renewal_term_months = case
        when p_changes ? 'renewal_term_months'
          then (p_changes ->> 'renewal_term_months')::integer
        else contract.renewal_term_months end,
      annual_value = case
        when p_changes ? 'annual_value'
          then (p_changes ->> 'annual_value')::numeric
        else contract.annual_value end,
      currency_code = case
        when p_changes ? 'currency_code'
          then nullif(upper(btrim(coalesce(p_changes ->> 'currency_code', ''))), '')
        else contract.currency_code end,
      updated_at = now(),
      updated_by = v_actor_id,
      version = contract.version + 1
    where contract.workspace_id = p_workspace_id
      and contract.id = p_contract_id
    returning * into v_new;
  exception when check_violation or invalid_text_representation then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The contract terms are inconsistent'
      )
    );
  end;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'supplier_contract.update', 'supplier_contract', p_contract_id,
    private.supplier_contract_snapshot(v_old),
    private.supplier_contract_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.supplier_contract_snapshot(v_new)
  );
end;
$function$;

alter function public.update_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) owner to postgres;
revoke all on function public.update_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) from public, anon, authenticated;
grant execute on function public.update_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- end
-- ---------------------------------------------------------------------------

create function public.end_supplier_contract(
  p_workspace_id uuid,
  p_contract_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_ended_reason text,
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
  v_old public.supplier_contracts%rowtype;
  v_new public.supplier_contracts%rowtype;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_contract_id is null or p_expected_version is null
     or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Contract id and expected version are required'
      )
    );
  end if;

  -- Required, unlike the optional command `reason`. Why a contract with a
  -- supplier was ended is the thing somebody will want to know in two years,
  -- and a terminal state reachable without an explanation is how that gets
  -- lost.
  if p_ended_reason is null
     or char_length(btrim(p_ended_reason)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An end reason is required', 'field', 'endedReason'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'party.manage')
     or not private.has_workspace_permission(p_workspace_id, 'party.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Supplier contract end is not permitted'
      )
    );
  end if;

  select contract.*
  into v_old
  from public.supplier_contracts as contract
  where contract.workspace_id = p_workspace_id
    and contract.id = p_contract_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Supplier contract not found'
      )
    );
  end if;

  if v_old.status = 'ended' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The contract has already ended'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'end_supplier_contract',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'contract_id', p_contract_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'ended_reason', p_ended_reason,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'supplier_contract'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Supplier contract version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.supplier_contract_snapshot(v_old)
      )
    );
  end if;

  update public.supplier_contracts as contract
  set
    status = 'ended',
    ended_at = now(),
    ended_reason = btrim(p_ended_reason),
    updated_at = now(),
    updated_by = v_actor_id,
    version = contract.version + 1
  where contract.workspace_id = p_workspace_id
    and contract.id = p_contract_id
  returning * into v_new;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'supplier_contract.end', 'supplier_contract', p_contract_id,
    private.supplier_contract_snapshot(v_old),
    private.supplier_contract_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.supplier_contract_snapshot(v_new)
  );
end;
$function$;

alter function public.end_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.end_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.end_supplier_contract(
  uuid, uuid, bigint, uuid, uuid, text, text
) to authenticated;
