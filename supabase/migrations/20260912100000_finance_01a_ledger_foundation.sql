-- FINANCE-01a: the ledger foundation — chart of accounts, accounting periods
-- and property-scoped actuals.
--
-- `PROPERTY_PERFORMANCE_V2.md` has been blocked on `P2-D08`/`FINANCE-01` since
-- the readiness review, and `PROPERTY_OVERVIEW_V2.md` leaves its financial KPI
-- slots empty for the same reason. Nothing financial exists in this database
-- today: no account, no period, no booking. This migration is the first
-- increment, and it is deliberately the *boring* one — the three tables every
-- later figure has to be derived from.
--
-- **What this increment does not contain, and why.**
--
-- No NOI, no cashflow, no budget variance, no covenant headroom. Every one of
-- those is a formula, and the spec's data contract (§7) requires a *definition
-- version* to travel with any computed figure so a number can be reproduced
-- and audited later. That versioning is the next increment's contract. Adding
-- a "provisional NOI" here would mean publishing a figure nobody can reproduce
-- — the exact thing `PROPERTY_OVERVIEW_V2.md` rules out for financial KPIs.
-- So this increment sums what was booked, per account and per currency, and
-- stops there.
--
-- **Three rules the schema enforces rather than documents.**
--
--   1. **A closed period does not move.** `finance_periods` carries an open /
--      closed status, and no ledger entry may be written into, changed within
--      or moved out of a closed period. Closing is a separate, separately
--      permitted action (`finance.close`), because it is the moment a figure
--      stops being provisional.
--   2. **Provisional says so.** Every read reports which of the periods it
--      summed are still open. A total that mixes a closed quarter with a
--      half-booked current month is not wrong, but it is provisional, and a
--      reader who cannot see that will treat it as final.
--   3. **Currencies never merge.** A ledger entry carries its own currency and
--      the reads group by it. There is no reporting-currency conversion here:
--      that needs an approved rate source with a rate date, which is its own
--      decision and not one a sum should make silently.
--
-- **Signed amounts, one convention.** An entry's `amount` is signed in the
-- natural direction of its account type: income is positive when earned,
-- expense positive when incurred. The alternative — debit/credit columns —
-- models double-entry bookkeeping, which this product is not: NexImmo reports
-- on an owner's operating result, it does not keep their books. Encoding a
-- half-implemented double entry would invite a balance check that can never
-- pass.

-- =============================================================================
-- Permissions
-- =============================================================================
--
-- Three keys, because the three actions differ in consequence: reading a
-- figure, booking one, and declaring a period final.
--
-- Role bundles follow the existing least-privilege shape, with one deliberate
-- asymmetry: `operations` gets nothing here. It is the one role in the spec's
-- role table with no finance job — it runs maintenance and tasks — and giving
-- it a finance read "for symmetry" would widen the surface for nobody's
-- benefit. `analyst` reads but does not book: they build valuations from
-- financial truth, they do not produce it.

create or replace function private.ensure_permission_catalog()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.permissions (key, name)
  values
    ('workspace.read', 'Workspace Read'),
    ('security.manage', 'Security Manage'),
    ('audit.read', 'Audit Read'),
    ('property.read', 'Property Read'),
    ('property.create', 'Property Create'),
    ('property.update', 'Property Update'),
    ('party.read', 'Party Read'),
    ('party.manage', 'Party Manage'),
    ('document.read', 'Document Read'),
    ('document.manage', 'Document Manage'),
    ('document.verify', 'Document Verify'),
    ('task.read', 'Task Read'),
    ('task.manage', 'Task Manage'),
    ('notification.read', 'Notification Read'),
    ('notification.manage', 'Notification Manage'),
    ('import.read', 'Import Read'),
    ('import.manage', 'Import Manage'),
    ('search.read', 'Search Read'),
    ('search.reindex', 'Search Reindex'),
    ('lease.read', 'Lease Read'),
    ('lease.manage', 'Lease Manage'),
    ('valuation.read', 'Valuation Read'),
    ('valuation.manage', 'Valuation Manage'),
    ('valuation.approve', 'Valuation Approve'),
    ('maintenance.read', 'Maintenance Read'),
    ('maintenance.manage', 'Maintenance Manage'),
    ('capex.read', 'CapEx Read'),
    ('capex.manage', 'CapEx Manage'),
    ('capex.approve', 'CapEx Approve'),
    ('reporting.generate', 'Reporting Generate'),
    -- FINANCE-01a.
    ('finance.read', 'Finance Read'),
    ('finance.manage', 'Finance Manage'),
    ('finance.close', 'Finance Close')
  on conflict (key) do nothing;
end;
$function$;

alter function private.ensure_permission_catalog() owner to postgres;
revoke all on function private.ensure_permission_catalog()
  from public, anon, authenticated;

create or replace function private.seed_workspace_role_catalog(p_workspace_id uuid)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if p_workspace_id is null
     or not exists (select 1 from public.workspaces where id = p_workspace_id) then
    raise exception 'seed_workspace_role_catalog: unknown workspace %', p_workspace_id
      using errcode = '22023';
  end if;

  perform private.ensure_permission_catalog();

  insert into public.roles (workspace_id, key, name) values
    (p_workspace_id, 'admin', 'Admin'),
    (p_workspace_id, 'manager', 'Manager'),
    (p_workspace_id, 'analyst', 'Analyst'),
    (p_workspace_id, 'operations', 'Operations'),
    (p_workspace_id, 'viewer', 'Viewer')
  on conflict (workspace_id, key) do nothing;

  insert into public.role_permissions (workspace_id, role_id, permission_id)
  select p_workspace_id, role.id, permission.id
  from public.roles as role
  join public.permissions as permission
    on case role.key
      when 'admin' then true
      when 'manager' then permission.key in (
        'workspace.read', 'audit.read',
        'property.read', 'property.create', 'property.update',
        'party.read', 'party.manage',
        'document.read', 'document.manage', 'document.verify',
        'task.read', 'task.manage',
        'lease.read', 'lease.manage',
        'valuation.read', 'valuation.manage', 'valuation.approve',
        'maintenance.read', 'maintenance.manage',
        'capex.read', 'capex.manage', 'capex.approve',
        'import.read', 'import.manage',
        'finance.read', 'finance.manage', 'finance.close',
        'search.read', 'reporting.generate')
      when 'analyst' then permission.key in (
        'workspace.read', 'audit.read',
        'property.read', 'property.update',
        'party.read',
        'document.read', 'document.manage',
        'task.read', 'task.manage',
        'lease.read',
        'valuation.read', 'valuation.manage',
        'maintenance.read', 'capex.read',
        'import.read', 'import.manage',
        'finance.read',
        'search.read', 'reporting.generate')
      when 'operations' then permission.key in (
        'workspace.read', 'audit.read',
        'property.read', 'property.update',
        'party.read',
        'document.read', 'document.manage',
        'task.read', 'task.manage',
        'lease.read',
        'valuation.read',
        'maintenance.read', 'maintenance.manage',
        'capex.read',
        'search.read', 'reporting.generate')
      when 'viewer' then permission.key in (
        'workspace.read', 'audit.read',
        'property.read', 'document.read', 'task.read',
        'lease.read', 'valuation.read', 'finance.read', 'reporting.generate')
      else false
    end
  where role.workspace_id = p_workspace_id
    and role.key in ('admin', 'manager', 'analyst', 'operations', 'viewer')
  on conflict (workspace_id, role_id, permission_id) do nothing;

  -- Append-only trace: role_permissions is security-critical state, and this
  -- write can happen outside a user session (migration, operations), so the
  -- actor is the system.
  insert into public.audit_events (
    workspace_id, actor_type, actor_identifier, scope_snapshot,
    action, entity_type, entity_id, source, correlation_id,
    new_values
  ) values (
    p_workspace_id, 'system', 'permission-catalog-02',
    jsonb_build_object('workspace_id', p_workspace_id),
    'security.role_catalog_seeded', 'role_catalog', null, 'migration',
    gen_random_uuid(),
    jsonb_build_object(
      'roles', (select jsonb_agg(role.key order by role.key)
                from public.roles as role
                where role.workspace_id = p_workspace_id),
      'grant_count', (select count(*)
                      from public.role_permissions as role_permission
                      where role_permission.workspace_id = p_workspace_id)
    )
  );
end;
$function$;

alter function private.seed_workspace_role_catalog(uuid) owner to postgres;
revoke all on function private.seed_workspace_role_catalog(uuid)
  from public, anon, authenticated;

-- Workspaces that exist at migration time gain the three new keys and their
-- grants. Guarded on an existing workspace so an empty database (local CI
-- reset, every pgTAP file) stays untouched. Existing rows are never modified.
do $do$
begin
  if exists (select 1 from public.workspaces) then
    perform private.ensure_permission_catalog();

    insert into public.role_permissions (workspace_id, role_id, permission_id)
    select role.workspace_id, role.id, permission.id
    from public.roles as role
    cross join public.permissions as permission
    where (
        (permission.key = 'finance.read'
         and role.key in ('admin', 'manager', 'analyst', 'viewer'))
        or (permission.key in ('finance.manage', 'finance.close')
            and role.key in ('admin', 'manager'))
      )
    on conflict do nothing;
  end if;
end;
$do$;

-- =============================================================================
-- Chart of accounts
-- =============================================================================

create type public.finance_account_type as enum (
  'income', 'expense', 'asset', 'liability', 'equity'
);

create table public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  code text not null,
  name text not null,
  account_type public.finance_account_type not null,
  -- Hierarchy for reporting rollups. Depth is not constrained here; the read
  -- surface renders accounts flat until a rollup contract exists, so a deep
  -- tree cannot produce a wrong subtotal by accident.
  parent_account_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint finance_accounts_workspace_id_key unique (workspace_id, id),
  constraint finance_accounts_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint finance_accounts_parent_fkey
    foreign key (workspace_id, parent_account_id)
    references public.finance_accounts (workspace_id, id) on delete restrict,
  constraint finance_accounts_code_unique unique (workspace_id, code),
  constraint finance_accounts_code_check check (
    code = btrim(code)
    and code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'
  ),
  constraint finance_accounts_name_check check (
    char_length(btrim(name)) between 1 and 200
  ),
  -- An account cannot be its own parent. Deeper cycles are rejected by the
  -- command, which can walk the chain; a check constraint cannot.
  constraint finance_accounts_parent_self_check check (
    parent_account_id is null or parent_account_id <> id
  ),
  constraint finance_accounts_version_check check (version >= 1)
);

create index finance_accounts_workspace_idx on public.finance_accounts (workspace_id);
create index finance_accounts_type_idx
  on public.finance_accounts (workspace_id, account_type, code);
create index finance_accounts_parent_idx
  on public.finance_accounts (workspace_id, parent_account_id)
  where parent_account_id is not null;

create trigger finance_accounts_protected_columns
before update on public.finance_accounts
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.finance_accounts enable row level security;
alter table public.finance_accounts force row level security;

create policy finance_accounts_select_finance_read
on public.finance_accounts
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_accounts from anon, authenticated;
grant select on table public.finance_accounts to authenticated;

-- =============================================================================
-- Accounting periods
-- =============================================================================

create type public.finance_period_status as enum ('open', 'closed');

create table public.finance_periods (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  fiscal_year integer not null,
  period_month integer not null,
  status public.finance_period_status not null default 'open',
  closed_at timestamptz,
  closed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint finance_periods_workspace_id_key unique (workspace_id, id),
  constraint finance_periods_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint finance_periods_unique unique (workspace_id, fiscal_year, period_month),
  constraint finance_periods_year_check check (fiscal_year between 1900 and 2999),
  constraint finance_periods_month_check check (period_month between 1 and 12),
  -- STM-005 terminal marker: exactly the closed status carries its timestamp
  -- and its closer, so "is this period final" has one answer, not three.
  constraint finance_periods_closed_marker_check check (
    (status = 'closed') = (closed_at is not null)
    and (status = 'closed') = (closed_by is not null)
  ),
  constraint finance_periods_version_check check (version >= 1)
);

create index finance_periods_workspace_idx on public.finance_periods (workspace_id);
create index finance_periods_order_idx
  on public.finance_periods (workspace_id, fiscal_year, period_month);

create trigger finance_periods_protected_columns
before update on public.finance_periods
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'fiscal_year', 'period_month', 'created_at', 'created_by'
);

alter table public.finance_periods enable row level security;
alter table public.finance_periods force row level security;

create policy finance_periods_select_finance_read
on public.finance_periods
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_periods from anon, authenticated;
grant select on table public.finance_periods to authenticated;

-- =============================================================================
-- Ledger entries: the property-scoped actuals
-- =============================================================================

create type public.finance_entry_source as enum ('manual', 'import');

create table public.finance_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  account_id uuid not null,
  period_id uuid not null,
  -- The booking date inside the period. Kept alongside the period because a
  -- period is a reporting bucket, not a date: two entries in the same month
  -- can still need ordering by when they happened.
  booked_on date not null,
  amount numeric(18, 2) not null,
  currency_code text not null,
  description text,
  source public.finance_entry_source not null default 'manual',
  -- Optional finer scope. A cost can belong to one unit or one contract; both
  -- stay optional because most do not.
  unit_id uuid,
  lease_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint finance_ledger_entries_workspace_id_key unique (workspace_id, id),
  constraint finance_ledger_entries_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint finance_ledger_entries_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint finance_ledger_entries_account_fkey
    foreign key (workspace_id, account_id)
    references public.finance_accounts (workspace_id, id) on delete restrict,
  constraint finance_ledger_entries_period_fkey
    foreign key (workspace_id, period_id)
    references public.finance_periods (workspace_id, id) on delete restrict,
  constraint finance_ledger_entries_unit_fkey
    foreign key (workspace_id, unit_id)
    references public.units (workspace_id, id) on delete restrict,
  constraint finance_ledger_entries_lease_fkey
    foreign key (workspace_id, lease_id)
    references public.leases (workspace_id, id) on delete restrict,
  constraint finance_ledger_entries_amount_check check (
    amount <> 'NaN'::numeric
  ),
  constraint finance_ledger_entries_currency_check check (
    currency_code ~ '^[A-Z]{3}$'
  ),
  constraint finance_ledger_entries_description_check check (
    description is null or char_length(description) <= 2000
  ),
  constraint finance_ledger_entries_version_check check (version >= 1)
);

create index finance_ledger_entries_workspace_idx
  on public.finance_ledger_entries (workspace_id);
-- The hot path: one property's entries for a range of periods.
create index finance_ledger_entries_property_period_idx
  on public.finance_ledger_entries (workspace_id, property_id, period_id);
create index finance_ledger_entries_account_idx
  on public.finance_ledger_entries (workspace_id, account_id);
create index finance_ledger_entries_period_idx
  on public.finance_ledger_entries (workspace_id, period_id);
-- Leading-column indexes for the two optional references, so their referential
-- checks are lookups rather than scans.
create index finance_ledger_entries_unit_idx
  on public.finance_ledger_entries (workspace_id, unit_id)
  where unit_id is not null;
create index finance_ledger_entries_lease_idx
  on public.finance_ledger_entries (workspace_id, lease_id)
  where lease_id is not null;
create index finance_ledger_entries_property_fk_idx
  on public.finance_ledger_entries (property_id);

create trigger finance_ledger_entries_protected_columns
before update on public.finance_ledger_entries
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'property_id', 'created_at', 'created_by'
);

alter table public.finance_ledger_entries enable row level security;
alter table public.finance_ledger_entries force row level security;

create policy finance_ledger_entries_select_finance_read
on public.finance_ledger_entries
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_ledger_entries from anon, authenticated;
grant select on table public.finance_ledger_entries to authenticated;

-- -----------------------------------------------------------------------------
-- The closed-period invariant, enforced by trigger rather than by the commands.
--
-- The commands check it too, so a caller gets a typed refusal instead of an
-- exception. This trigger is the backstop: a future import path, a repair
-- script or a new RPC cannot book into a closed month by forgetting the check.
-- It fires on the *old* period as well, so an entry cannot be moved out of a
-- closed period either.
-- -----------------------------------------------------------------------------

create function private.finance_reject_closed_period()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status public.finance_period_status;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select period.status into v_status
    from public.finance_periods as period
    where period.workspace_id = new.workspace_id and period.id = new.period_id;
    if v_status = 'closed'::public.finance_period_status then
      raise exception 'FIN-001: period is closed and cannot receive entries'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.period_id is distinct from new.period_id then
    select period.status into v_status
    from public.finance_periods as period
    where period.workspace_id = old.workspace_id and period.id = old.period_id;
    if v_status = 'closed'::public.finance_period_status then
      raise exception 'FIN-001: entries cannot be moved out of a closed period'
        using errcode = '23514';
    end if;
  end if;

  return null;
end;
$function$;

alter function private.finance_reject_closed_period() owner to postgres;

create constraint trigger finance_ledger_entries_closed_period
after insert or update on public.finance_ledger_entries
deferrable initially immediate
for each row execute function private.finance_reject_closed_period();

-- =============================================================================
-- Command plumbing
-- =============================================================================

create function private.finance_command_gate(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  -- DEC-025.
  if not private.is_aal2() then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for finance mutations'
      )
    );
  end if;

  if p_workspace_id is null or p_mutation_id is null or p_correlation_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Command identifiers are required'
      )
    );
  end if;

  if p_reason is not null
     and char_length(btrim(p_reason)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Reason must contain at most 2000 characters',
        'field', 'reason'
      )
    );
  end if;

  return null;
end;
$function$;

alter function private.finance_command_gate(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.finance_command_gate(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create function private.claim_finance_mutation(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_request_hash bytea,
  p_entity_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_replayed jsonb;
begin
  insert into public.mutation_receipts (
    workspace_id, mutation_id, request_hash, status, created_by, updated_by
  ) values (
    p_workspace_id, p_mutation_id, p_request_hash, 'pending', v_actor_id, v_actor_id
  )
  on conflict (workspace_id, mutation_id) do nothing
  returning id into v_inserted_receipt_id;

  if v_inserted_receipt_id is not null then
    return null;
  end if;

  select receipt.*
  into v_receipt
  from public.mutation_receipts as receipt
  where receipt.workspace_id = p_workspace_id
    and receipt.mutation_id = p_mutation_id
  for update;

  if v_receipt.request_hash is distinct from p_request_hash then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'mutation_conflict',
        'message', 'Mutation id was used with a different command'
      )
    );
  end if;

  -- A command that failed a *state* check (a code already taken, a period
  -- since closed) may legitimately be retried once the state changes, so a
  -- failed receipt with the same request hash re-arms rather than reporting
  -- "already in progress" forever. The hash equality above is what makes this
  -- safe: only the identical command can re-arm its own receipt.
  if v_receipt.status = 'failed' then
    update public.mutation_receipts
    set status = 'pending', updated_at = now(), updated_by = v_actor_id,
        version = version + 1
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;
    return null;
  end if;

  if v_receipt.status = 'succeeded' then
    select audit.new_values
    into v_replayed
    from public.audit_events as audit
    where audit.workspace_id = p_workspace_id
      and audit.mutation_id = p_mutation_id
      and audit.entity_type = p_entity_type;

    if v_replayed is null then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'infrastructure_failure',
          'message', 'Successful mutation result is unavailable'
        )
      );
    end if;

    return jsonb_build_object('ok', true, 'entity', v_replayed);
  end if;

  return jsonb_build_object(
    'ok', false,
    'error', jsonb_build_object(
      'code', 'in_progress',
      'message', 'Mutation is already in progress'
    )
  );
end;
$function$;

alter function private.claim_finance_mutation(uuid, uuid, bytea, text) owner to postgres;
revoke all on function private.claim_finance_mutation(uuid, uuid, bytea, text)
  from public, anon, authenticated;

-- Releases a claim whose command then failed a state check. Without this a
-- refused command would leave its receipt pending, and the caller's corrected
-- retry with the same id would be told the mutation is still running.
create function private.fail_finance_mutation(
  p_workspace_id uuid,
  p_mutation_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.mutation_receipts
  set status = 'failed', updated_at = now(), updated_by = auth.uid(),
      version = version + 1
  where workspace_id = p_workspace_id
    and mutation_id = p_mutation_id
    and status = 'pending';
$function$;

alter function private.fail_finance_mutation(uuid, uuid) owner to postgres;
revoke all on function private.fail_finance_mutation(uuid, uuid)
  from public, anon, authenticated;

create function private.finish_finance_mutation(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_role_key text;
begin
  select role.key
  into v_role_key
  from public.memberships as membership
  join public.roles as role
    on role.workspace_id = membership.workspace_id
    and role.id = membership.role_id
  where membership.workspace_id = p_workspace_id
    and membership.user_id = v_actor_id
    and membership.status = 'active'::public.membership_status;

  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, role_key, scope_snapshot,
    action, entity_type, entity_id, source, correlation_id, mutation_id,
    reason, old_values, new_values, created_by, updated_by
  ) values (
    p_workspace_id, 'user', v_actor_id, v_role_key,
    jsonb_build_object('workspace_id', p_workspace_id),
    p_action, p_entity_type, p_entity_id, 'rpc', p_correlation_id,
    p_mutation_id, p_reason, p_old_values, p_new_values,
    v_actor_id, v_actor_id
  );

  update public.mutation_receipts
  set
    status = 'succeeded',
    result_entity_type = p_entity_type,
    result_entity_id = p_entity_id,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id
    and mutation_id = p_mutation_id;
end;
$function$;

alter function private.finish_finance_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) owner to postgres;
revoke all on function private.finish_finance_mutation(
  uuid, uuid, uuid, text, text, text, uuid, jsonb, jsonb
) from public, anon, authenticated;

-- Snapshots: the published shape of each aggregate, used for both the RPC
-- result and the audit payload, so the two can never disagree.

create function private.finance_account_snapshot(p_row public.finance_accounts)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', p_row.id,
    'workspace_id', p_row.workspace_id,
    'code', p_row.code,
    'name', p_row.name,
    'account_type', p_row.account_type,
    'parent_account_id', p_row.parent_account_id,
    'is_active', p_row.is_active,
    'created_at', p_row.created_at,
    'updated_at', p_row.updated_at,
    'version', p_row.version
  );
$function$;

alter function private.finance_account_snapshot(public.finance_accounts)
  owner to postgres;
revoke all on function private.finance_account_snapshot(public.finance_accounts)
  from public, anon, authenticated;

create function private.finance_period_snapshot(p_row public.finance_periods)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', p_row.id,
    'workspace_id', p_row.workspace_id,
    'fiscal_year', p_row.fiscal_year,
    'period_month', p_row.period_month,
    'status', p_row.status,
    'closed_at', p_row.closed_at,
    'closed_by', p_row.closed_by,
    'created_at', p_row.created_at,
    'updated_at', p_row.updated_at,
    'version', p_row.version
  );
$function$;

alter function private.finance_period_snapshot(public.finance_periods)
  owner to postgres;
revoke all on function private.finance_period_snapshot(public.finance_periods)
  from public, anon, authenticated;

create function private.finance_entry_snapshot(
  p_row public.finance_ledger_entries
)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', p_row.id,
    'workspace_id', p_row.workspace_id,
    'property_id', p_row.property_id,
    'account_id', p_row.account_id,
    'period_id', p_row.period_id,
    'booked_on', p_row.booked_on,
    'amount', p_row.amount,
    'currency_code', p_row.currency_code,
    'description', p_row.description,
    'source', p_row.source,
    'unit_id', p_row.unit_id,
    'lease_id', p_row.lease_id,
    'created_at', p_row.created_at,
    'updated_at', p_row.updated_at,
    'version', p_row.version
  );
$function$;

alter function private.finance_entry_snapshot(public.finance_ledger_entries)
  owner to postgres;
revoke all on function private.finance_entry_snapshot(public.finance_ledger_entries)
  from public, anon, authenticated;

-- =============================================================================
-- Commands: chart of accounts
-- =============================================================================

create function public.create_finance_account(
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

alter function public.create_finance_account(
  uuid, text, text, text, uuid, uuid, uuid, text
) owner to postgres;
revoke all on function public.create_finance_account(
  uuid, text, text, text, uuid, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_finance_account(
  uuid, text, text, text, uuid, uuid, uuid, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- update_finance_account: name, parent and active flag. The code and the type
-- are deliberately immutable — both are referenced by every booking made
-- against the account, and changing either would silently reinterpret history.
-- Retiring an account and creating a replacement is the honest path, which is
-- what `is_active` is for.
-- -----------------------------------------------------------------------------

create function public.update_finance_account(
  p_workspace_id uuid,
  p_account_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_name text default null,
  p_parent_account_id uuid default null,
  p_clear_parent boolean default false,
  p_is_active boolean default null,
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
  v_old public.finance_accounts%rowtype;
  v_row public.finance_accounts%rowtype;
  v_parent uuid;
  v_walk uuid;
  v_depth integer := 0;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_name is not null
     and char_length(btrim(p_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An account name is required',
        'field', 'name'
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

  select * into v_old
  from public.finance_accounts as account
  where account.workspace_id = p_workspace_id and account.id = p_account_id;

  if v_old.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Account not found')
    );
  end if;

  if p_expected_version is null or p_expected_version <> v_old.version then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'The account was changed by someone else'
      ),
      'entity', private.finance_account_snapshot(v_old)
    );
  end if;

  v_parent := case
    when coalesce(p_clear_parent, false) then null
    when p_parent_account_id is not null then p_parent_account_id
    else v_old.parent_account_id
  end;

  if v_parent is not null then
    if v_parent = p_account_id then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'An account cannot be its own parent',
          'field', 'parent_account_id'
        )
      );
    end if;

    if not exists (
      select 1 from public.finance_accounts as parent
      where parent.workspace_id = p_workspace_id and parent.id = v_parent
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Parent account not found',
          'field', 'parent_account_id'
        )
      );
    end if;

    -- Walk up from the proposed parent. A cycle here would make any future
    -- rollup non-terminating, and a check constraint cannot see past one row.
    v_walk := v_parent;
    while v_walk is not null and v_depth < 64 loop
      if v_walk = p_account_id then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'dependency_conflict',
            'message', 'That parent would create a cycle in the chart of accounts',
            'field', 'parent_account_id'
          )
        );
      end if;
      select parent.parent_account_id into v_walk
      from public.finance_accounts as parent
      where parent.workspace_id = p_workspace_id and parent.id = v_walk;
      v_depth := v_depth + 1;
    end loop;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_finance_account',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'account_id', p_account_id,
        'expected_version', p_expected_version,
        'name', p_name,
        'parent_account_id', p_parent_account_id,
        'clear_parent', coalesce(p_clear_parent, false),
        'is_active', p_is_active,
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

  update public.finance_accounts
  set
    name = coalesce(nullif(btrim(p_name), ''), name),
    parent_account_id = v_parent,
    is_active = coalesce(p_is_active, is_active),
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_account_id
  returning * into v_row;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'update', 'finance_account', v_row.id,
    private.finance_account_snapshot(v_old),
    private.finance_account_snapshot(v_row)
  );
  return jsonb_build_object(
    'ok', true, 'entity', private.finance_account_snapshot(v_row)
  );
end;
$function$;

alter function public.update_finance_account(
  uuid, uuid, bigint, uuid, uuid, text, uuid, boolean, boolean, text
) owner to postgres;
revoke all on function public.update_finance_account(
  uuid, uuid, bigint, uuid, uuid, text, uuid, boolean, boolean, text
) from public, anon, authenticated;
grant execute on function public.update_finance_account(
  uuid, uuid, bigint, uuid, uuid, text, uuid, boolean, boolean, text
) to authenticated;

-- =============================================================================
-- Commands: periods
-- =============================================================================

create function public.open_finance_period(
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

alter function public.open_finance_period(uuid, integer, integer, uuid, uuid, text)
  owner to postgres;
revoke all on function public.open_finance_period(uuid, integer, integer, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.open_finance_period(uuid, integer, integer, uuid, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- transition_finance_period_status: close and reopen.
--
-- One command for both directions, because they are the same state machine and
-- splitting them would let the two drift. Both require `finance.close`:
-- reopening a closed month is exactly as consequential as closing it, and a
-- role that may not declare a period final must not be able to un-declare one
-- either. Reopening always requires a reason — it changes numbers somebody has
-- already reported on.
-- -----------------------------------------------------------------------------

create function public.transition_finance_period_status(
  p_workspace_id uuid,
  p_period_id uuid,
  p_target_status text,
  p_expected_version bigint,
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
  v_old public.finance_periods%rowtype;
  v_row public.finance_periods%rowtype;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_target_status is null or p_target_status not in ('open', 'closed') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unsupported period status',
        'field', 'target_status'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.close') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Closing and reopening periods is not permitted'
      )
    );
  end if;

  select * into v_old
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id and period.id = p_period_id;

  if v_old.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Period not found')
    );
  end if;

  if p_expected_version is null or p_expected_version <> v_old.version then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'The period was changed by someone else'
      ),
      'entity', private.finance_period_snapshot(v_old)
    );
  end if;

  if v_old.status::text = p_target_status then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The period already has that status',
        'field', 'target_status'
      )
    );
  end if;

  if p_target_status = 'open'
     and (p_reason is null or char_length(btrim(p_reason)) = 0) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Reopening a closed period requires a reason',
        'field', 'reason'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'transition_finance_period_status',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'period_id', p_period_id,
        'target_status', p_target_status,
        'expected_version', p_expected_version,
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

  update public.finance_periods
  set
    status = p_target_status::public.finance_period_status,
    closed_at = case when p_target_status = 'closed' then now() else null end,
    closed_by = case when p_target_status = 'closed' then v_actor_id else null end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_period_id
  returning * into v_row;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'transition', 'finance_period', v_row.id,
    private.finance_period_snapshot(v_old),
    private.finance_period_snapshot(v_row)
  );
  return jsonb_build_object(
    'ok', true, 'entity', private.finance_period_snapshot(v_row)
  );
end;
$function$;

alter function public.transition_finance_period_status(
  uuid, uuid, text, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.transition_finance_period_status(
  uuid, uuid, text, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.transition_finance_period_status(
  uuid, uuid, text, bigint, uuid, uuid, text
) to authenticated;

-- =============================================================================
-- Commands: ledger entries
-- =============================================================================

create function public.record_finance_ledger_entry(
  p_workspace_id uuid,
  p_property_id uuid,
  p_account_id uuid,
  p_period_id uuid,
  p_booked_on date,
  p_amount numeric,
  p_currency_code text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_description text default null,
  p_unit_id uuid default null,
  p_lease_id uuid default null,
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
$function$;

alter function public.record_finance_ledger_entry(
  uuid, uuid, uuid, uuid, date, numeric, text, uuid, uuid, text, uuid, uuid, text
) owner to postgres;
revoke all on function public.record_finance_ledger_entry(
  uuid, uuid, uuid, uuid, date, numeric, text, uuid, uuid, text, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.record_finance_ledger_entry(
  uuid, uuid, uuid, uuid, date, numeric, text, uuid, uuid, text, uuid, uuid, text
) to authenticated;

-- =============================================================================
-- Read: a property's actuals
-- =============================================================================
--
-- Sums per account and per currency across a period range, and states its own
-- provisionality. Notably absent: a net result, a margin, or any figure that
-- combines income and expense. Those are the definitions the next increment
-- has to version; adding an unversioned one here would publish a number nobody
-- can reproduce.

create function public.property_finance_actuals(
  p_workspace_id uuid,
  p_property_id uuid,
  p_from_year integer default null,
  p_from_month integer default null,
  p_to_year integer default null,
  p_to_month integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_from integer;
  v_to integer;
  v_accounts jsonb;
  v_periods jsonb;
  v_open integer;
  v_total integer;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for finance reads'
      )
    );
  end if;

  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Property access is not permitted'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance access is not permitted'
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

  -- A period range is compared as year*12+month, so December to January needs
  -- no special case.
  v_from := case
    when p_from_year is null then null
    else p_from_year * 12 + coalesce(p_from_month, 1)
  end;
  v_to := case
    when p_to_year is null then null
    else p_to_year * 12 + coalesce(p_to_month, 12)
  end;

  if v_from is not null and v_to is not null and v_to < v_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The period range ends before it starts',
        'field', 'to_year'
      )
    );
  end if;

  -- Per account and currency. Two currencies on one account are two rows: a
  -- combined figure would be wrong in both.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'account_id', row.account_id,
        'account_code', row.code,
        'account_name', row.name,
        'account_type', row.account_type,
        'currency_code', row.currency_code,
        'amount', row.amount,
        'entries', row.entries
      )
      order by row.account_type, row.code, row.currency_code
    ),
    '[]'::jsonb
  )
  into v_accounts
  from (
    select
      account.id as account_id,
      account.code,
      account.name,
      account.account_type,
      entry.currency_code,
      sum(entry.amount) as amount,
      count(*) as entries
    from public.finance_ledger_entries as entry
    join public.finance_accounts as account
      on account.workspace_id = entry.workspace_id
      and account.id = entry.account_id
    join public.finance_periods as period
      on period.workspace_id = entry.workspace_id
      and period.id = entry.period_id
    where entry.workspace_id = p_workspace_id
      and entry.property_id = p_property_id
      and (
        v_from is null
        or (period.fiscal_year * 12 + period.period_month) >= v_from
      )
      and (
        v_to is null
        or (period.fiscal_year * 12 + period.period_month) <= v_to
      )
    group by
      account.id, account.code, account.name, account.account_type,
      entry.currency_code
  ) as row;

  -- The periods actually covered, with their status. This is the
  -- provisionality statement: a reader can see which months are still open.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'period_id', row.id,
          'fiscal_year', row.fiscal_year,
          'period_month', row.period_month,
          'status', row.status,
          'entries', row.entries
        )
        order by row.fiscal_year, row.period_month
      ),
      '[]'::jsonb
    ),
    count(*) filter (where row.status = 'open'::public.finance_period_status),
    count(*)
  into v_periods, v_open, v_total
  from (
    select
      period.id,
      period.fiscal_year,
      period.period_month,
      period.status,
      count(entry.id) as entries
    from public.finance_periods as period
    join public.finance_ledger_entries as entry
      on entry.workspace_id = period.workspace_id
      and entry.period_id = period.id
      and entry.property_id = p_property_id
    where period.workspace_id = p_workspace_id
      and (
        v_from is null
        or (period.fiscal_year * 12 + period.period_month) >= v_from
      )
      and (
        v_to is null
        or (period.fiscal_year * 12 + period.period_month) <= v_to
      )
    group by period.id, period.fiscal_year, period.period_month, period.status
  ) as row;

  return jsonb_build_object(
    'ok', true,
    'as_of', now(),
    'accounts', v_accounts,
    'periods', v_periods,
    -- The one-line honesty flag a surface can render without walking the
    -- period list: any open period makes every figure above provisional.
    'is_provisional', coalesce(v_open, 0) > 0,
    'open_periods', coalesce(v_open, 0),
    'covered_periods', coalesce(v_total, 0)
  );
end;
$function$;

alter function public.property_finance_actuals(
  uuid, uuid, integer, integer, integer, integer
) owner to postgres;
revoke all on function public.property_finance_actuals(
  uuid, uuid, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.property_finance_actuals(
  uuid, uuid, integer, integer, integer, integer
) to authenticated;
