-- FINANCE-01b: versioned KPI definitions, and the figures computed from them.
--
-- FINANCE-01a summed what was booked and refused to compute anything, because
-- `PROPERTY_PERFORMANCE_V2.md` §7 requires a definition *version* to travel
-- with any computed figure so a number can be reproduced and audited later.
-- This migration is that versioning, and the first figures that may therefore
-- exist.
--
-- **A definition is data, not code.**
--
-- NexImmo cannot know which accounts of *your* chart are operating expenses.
-- A hard-coded NOI would be a guess about someone else's bookkeeping dressed
-- as a product feature, and the first workspace whose chart differs would get
-- a confidently wrong number. So a definition is a workspace record: a key, a
-- name, and a set of lines that each name an account or a whole account class
-- and say what it does — add, subtract, or exclude. Nothing is seeded. A workspace with no definitions gets no KPIs,
-- which is the honest answer to "we have not told the system what NOI means
-- here yet".
--
-- **A definition is immutable; changing it means a new version.**
--
-- That is the whole point of the exercise. If a definition could be edited in
-- place, a figure computed last quarter could not be reproduced today, and the
-- audit trail would record a change to the meaning of a number without
-- recording the number. So `create_finance_kpi_definition` always writes a new
-- version, `activate_finance_kpi_definition` decides which version is the
-- current one, and no command updates a definition's lines. Retiring a version
-- leaves it readable, because a figure published under it must stay
-- explicable.
--
-- **What the computation is, and what it deliberately is not.**
--
-- A KPI value is the signed sum, over the booked entries of one property in
-- one currency over a period range, of the entries its lines govern. Addition and subtraction of
-- amounts that are already in the ledger — no rates, no allocations, no
-- accruals, no annualisation, no per-square-metre. Each of those needs its own
-- decision (a rate source with a rate date, an allocation basis, a convention
-- for partial periods), and inventing one inside a sum is how a plausible
-- number becomes an unaccountable one.
--
-- Consequently there is still **no cross-currency figure**: a KPI is computed
-- per currency, exactly like the actuals it draws on. A definition that mixes
-- accounts booked in EUR and CHF produces one row per currency, not a
-- conversion.
--
-- Provisionality travels as in FINANCE-01a: a value computed over any open
-- period is provisional, and says so.

-- =============================================================================
-- Definitions
-- =============================================================================

create type public.finance_kpi_status as enum ('draft', 'active', 'retired');

-- What a line does to the entries it matches.
--
-- `exclude` exists because the common real requirement is "everything in this
-- class, except that one account". Without it a definition could only ever add
-- classes together, and the exception would have to be expressed as a second
-- line with the opposite sign that happens to cancel the first — arithmetic
-- that works but that nobody can read back six months later.
create type public.finance_kpi_line_effect as enum (
  'add', 'subtract', 'exclude'
);

create table public.finance_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  -- Stable across versions: `noi` stays `noi` while its meaning is revised.
  kpi_key text not null,
  definition_version integer not null,
  name text not null,
  description text,
  status public.finance_kpi_status not null default 'draft',
  activated_at timestamptz,
  activated_by uuid,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  constraint finance_kpi_definitions_workspace_id_key unique (workspace_id, id),
  constraint finance_kpi_definitions_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint finance_kpi_definitions_version_unique
    unique (workspace_id, kpi_key, definition_version),
  constraint finance_kpi_definitions_key_check check (
    kpi_key = lower(btrim(kpi_key))
    and kpi_key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    and char_length(kpi_key) between 2 and 60
  ),
  constraint finance_kpi_definitions_definition_version_check check (
    definition_version >= 1
  ),
  constraint finance_kpi_definitions_name_check check (
    char_length(btrim(name)) between 1 and 200
  ),
  constraint finance_kpi_definitions_description_check check (
    description is null or char_length(description) <= 2000
  ),
  -- STM-005 terminal markers, one per state that carries a timestamp.
  constraint finance_kpi_definitions_active_marker_check check (
    (status = 'active') = (activated_at is not null)
    and (status = 'active') = (activated_by is not null)
  ),
  constraint finance_kpi_definitions_retired_marker_check check (
    (status = 'retired') = (retired_at is not null)
  ),
  constraint finance_kpi_definitions_row_version_check check (version >= 1)
);

create index finance_kpi_definitions_workspace_idx
  on public.finance_kpi_definitions (workspace_id);
create index finance_kpi_definitions_key_idx
  on public.finance_kpi_definitions (workspace_id, kpi_key, definition_version desc);

-- At most one active version per key. The whole contract rests on this: if two
-- versions could be active, "the current definition of NOI" would have no
-- answer and a published figure could not name its own meaning.
create unique index finance_kpi_definitions_single_active_idx
  on public.finance_kpi_definitions (workspace_id, kpi_key)
  where status = 'active';

create trigger finance_kpi_definitions_protected_columns
before update on public.finance_kpi_definitions
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'kpi_key', 'definition_version', 'created_at',
  'created_by'
);

alter table public.finance_kpi_definitions enable row level security;
alter table public.finance_kpi_definitions force row level security;

create policy finance_kpi_definitions_select_finance_read
on public.finance_kpi_definitions
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_kpi_definitions from anon, authenticated;
grant select on table public.finance_kpi_definitions to authenticated;

-- =============================================================================
-- Definition lines
-- =============================================================================
--
-- Each line names either one account or one whole account class, and what that
-- match does. Both forms exist because both are how people actually describe a
-- figure: "all income minus all operating expense" is a class rule that keeps
-- working when a new account is opened, while "except account 5900" is the
-- exception somebody insists on. A line names exactly one target, never both.
--
-- Where an account line and a class line both match an entry, the account line
-- wins. The specific rule is the one somebody wrote deliberately, and an entry
-- is counted once — never once per matching line.

create table public.finance_kpi_definition_lines (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  definition_id uuid not null,
  account_id uuid,
  account_type public.finance_account_type,
  effect public.finance_kpi_line_effect not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  constraint finance_kpi_definition_lines_workspace_id_key
    unique (workspace_id, id),
  constraint finance_kpi_definition_lines_workspace_fkey
    foreign key (workspace_id) references public.workspaces (id) on delete restrict,
  constraint finance_kpi_definition_lines_definition_fkey
    foreign key (workspace_id, definition_id)
    references public.finance_kpi_definitions (workspace_id, id)
    on delete restrict,
  constraint finance_kpi_definition_lines_account_fkey
    foreign key (workspace_id, account_id)
    references public.finance_accounts (workspace_id, id) on delete restrict,
  constraint finance_kpi_definition_lines_target_check check (
    (account_id is not null) <> (account_type is not null)
  )
);

create index finance_kpi_definition_lines_definition_idx
  on public.finance_kpi_definition_lines (workspace_id, definition_id);
create index finance_kpi_definition_lines_account_idx
  on public.finance_kpi_definition_lines (workspace_id, account_id)
  where account_id is not null;

alter table public.finance_kpi_definition_lines enable row level security;
alter table public.finance_kpi_definition_lines force row level security;

create policy finance_kpi_definition_lines_select_finance_read
on public.finance_kpi_definition_lines
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'finance.read'));

revoke all on table public.finance_kpi_definition_lines
  from anon, authenticated;
grant select on table public.finance_kpi_definition_lines to authenticated;

-- A definition's lines are written once, with the definition, and never
-- afterwards. The trigger is the backstop: a future repair script that edited
-- a line in place would silently change the meaning of every figure ever
-- published under that version.
create function private.finance_kpi_lines_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception
    'FIN-002: a KPI definition line is immutable; create a new definition version'
    using errcode = '23514';
end;
$function$;

alter function private.finance_kpi_lines_immutable() owner to postgres;

create trigger finance_kpi_definition_lines_immutable
before update or delete on public.finance_kpi_definition_lines
for each row execute function private.finance_kpi_lines_immutable();

-- =============================================================================
-- Snapshots
-- =============================================================================

create function private.finance_kpi_definition_snapshot(
  p_row public.finance_kpi_definitions
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', p_row.id,
    'workspace_id', p_row.workspace_id,
    'kpi_key', p_row.kpi_key,
    'definition_version', p_row.definition_version,
    'name', p_row.name,
    'description', p_row.description,
    'status', p_row.status,
    'activated_at', p_row.activated_at,
    'retired_at', p_row.retired_at,
    'created_at', p_row.created_at,
    'updated_at', p_row.updated_at,
    'version', p_row.version,
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'account_id', line.account_id,
            'account_type', line.account_type,
            'effect', line.effect
          )
          order by line.account_type, line.account_id, line.effect
        )
        from public.finance_kpi_definition_lines as line
        where line.workspace_id = p_row.workspace_id
          and line.definition_id = p_row.id
      ),
      '[]'::jsonb
    )
  );
$function$;

alter function private.finance_kpi_definition_snapshot(
  public.finance_kpi_definitions
) owner to postgres;
revoke all on function private.finance_kpi_definition_snapshot(
  public.finance_kpi_definitions
) from public, anon, authenticated;

-- =============================================================================
-- Commands
-- =============================================================================
--
-- Managing a definition is `finance.close`, not `finance.manage`.
--
-- That looks surprising until you consider what each does. `finance.manage`
-- books a figure; changing a definition changes what every published figure
-- *means*, retroactively for every future read. It belongs with the other act
-- of declaring what is true — closing a period — rather than with day-to-day
-- booking.

create function public.create_finance_kpi_definition(
  p_workspace_id uuid,
  p_kpi_key text,
  p_name text,
  p_lines jsonb,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_description text default null,
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
  v_next integer;
  v_row public.finance_kpi_definitions%rowtype;
  v_line jsonb;
  v_account_id uuid;
  v_account_type text;
  v_effect text;
  v_count integer := 0;
  v_new_values jsonb;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_kpi_key is null
     or btrim(p_kpi_key) !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
     or char_length(btrim(p_kpi_key)) not between 2 and 60 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A lowercase KPI key is required',
        'field', 'kpi_key'
      )
    );
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A name is required',
        'field', 'name'
      )
    );
  end if;

  if p_lines is null
     or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A definition needs at least one line',
        'field', 'lines'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.close') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Managing KPI definitions is not permitted'
      )
    );
  end if;

  -- Validate every line before writing anything, so a bad line cannot leave a
  -- half-built definition behind.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_account_id := case
      when v_line ->> 'account_id' is null then null
      else (v_line ->> 'account_id')::uuid
    end;
    v_account_type := v_line ->> 'account_type';
    v_effect := v_line ->> 'effect';

    if (v_account_id is null) = (v_account_type is null) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A line names either one account or one account class',
          'field', 'lines'
        )
      );
    end if;

    if v_effect is null or v_effect not in ('add', 'subtract', 'exclude') then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A line adds, subtracts or excludes',
          'field', 'lines'
        )
      );
    end if;

    if v_account_type is not null
       and v_account_type not in (
         'income', 'expense', 'asset', 'liability', 'equity'
       ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Unsupported account class in a line',
          'field', 'lines'
        )
      );
    end if;

    if v_account_id is not null and not exists (
      select 1 from public.finance_accounts as account
      where account.workspace_id = p_workspace_id and account.id = v_account_id
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found',
          'message', 'A line names an account that does not exist',
          'field', 'lines'
        )
      );
    end if;

    v_count := v_count + 1;
  end loop;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_finance_kpi_definition',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'kpi_key', btrim(p_kpi_key),
        'name', btrim(p_name),
        'description', p_description,
        'lines', p_lines,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'finance_kpi_definition'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- The next version for this key. Behind the claim, so a retry replays its
  -- receipt instead of minting a second version of the same definition.
  select coalesce(max(existing.definition_version), 0) + 1
  into v_next
  from public.finance_kpi_definitions as existing
  where existing.workspace_id = p_workspace_id
    and existing.kpi_key = btrim(p_kpi_key);

  insert into public.finance_kpi_definitions (
    workspace_id, kpi_key, definition_version, name, description,
    created_by, updated_by
  ) values (
    p_workspace_id, btrim(p_kpi_key), v_next, btrim(p_name),
    nullif(btrim(p_description), ''), v_actor_id, v_actor_id
  )
  returning * into v_row;

  insert into public.finance_kpi_definition_lines (
    workspace_id, definition_id, account_id, account_type, effect, created_by
  )
  select
    p_workspace_id,
    v_row.id,
    case
      when line ->> 'account_id' is null then null
      else (line ->> 'account_id')::uuid
    end,
    case
      when line ->> 'account_type' is null then null
      else (line ->> 'account_type')::public.finance_account_type
    end,
    (line ->> 'effect')::public.finance_kpi_line_effect,
    v_actor_id
  from jsonb_array_elements(p_lines) as line;

  v_new_values := private.finance_kpi_definition_snapshot(v_row);

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'create', 'finance_kpi_definition', v_row.id, null, v_new_values
  );
  return jsonb_build_object('ok', true, 'entity', v_new_values);
end;
$function$;

alter function public.create_finance_kpi_definition(
  uuid, text, text, jsonb, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.create_finance_kpi_definition(
  uuid, text, text, jsonb, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.create_finance_kpi_definition(
  uuid, text, text, jsonb, uuid, uuid, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- activate_finance_kpi_definition: which version is the current one.
--
-- Activating a version retires whichever version of the same key was active,
-- in one statement, so there is never a moment with two active versions or
-- none. The retired version stays readable: a figure published under it must
-- remain explicable.
-- -----------------------------------------------------------------------------

create function public.activate_finance_kpi_definition(
  p_workspace_id uuid,
  p_definition_id uuid,
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
  v_old public.finance_kpi_definitions%rowtype;
  v_row public.finance_kpi_definitions%rowtype;
begin
  v_gate := private.finance_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.close') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Managing KPI definitions is not permitted'
      )
    );
  end if;

  select * into v_old
  from public.finance_kpi_definitions as definition
  where definition.workspace_id = p_workspace_id
    and definition.id = p_definition_id;

  if v_old.id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'KPI definition not found'
      )
    );
  end if;

  if p_expected_version is null or p_expected_version <> v_old.version then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'The definition was changed by someone else'
      ),
      'entity', private.finance_kpi_definition_snapshot(v_old)
    );
  end if;

  if v_old.status = 'active'::public.finance_kpi_status then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'That version is already the active one'
      )
    );
  end if;

  if v_old.status = 'retired'::public.finance_kpi_status then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'dependency_conflict',
        'message',
          'A retired version cannot be reactivated; create a new version'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'activate_finance_kpi_definition',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'definition_id', p_definition_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_finance_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'finance_kpi_definition'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  -- Retire the incumbent first. Same statement order every time, so the
  -- partial unique index can never see two active rows.
  update public.finance_kpi_definitions
  set
    status = 'retired'::public.finance_kpi_status,
    activated_at = null,
    activated_by = null,
    retired_at = now(),
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id
    and kpi_key = v_old.kpi_key
    and status = 'active'::public.finance_kpi_status;

  update public.finance_kpi_definitions
  set
    status = 'active'::public.finance_kpi_status,
    activated_at = now(),
    activated_by = v_actor_id,
    retired_at = null,
    updated_at = now(),
    updated_by = v_actor_id,
    version = version + 1
  where workspace_id = p_workspace_id and id = p_definition_id
  returning * into v_row;

  perform private.finish_finance_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    'transition', 'finance_kpi_definition', v_row.id,
    private.finance_kpi_definition_snapshot(v_old),
    private.finance_kpi_definition_snapshot(v_row)
  );
  return jsonb_build_object(
    'ok', true, 'entity', private.finance_kpi_definition_snapshot(v_row)
  );
end;
$function$;

alter function public.activate_finance_kpi_definition(
  uuid, uuid, bigint, uuid, uuid, text
) owner to postgres;
revoke all on function public.activate_finance_kpi_definition(
  uuid, uuid, bigint, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.activate_finance_kpi_definition(
  uuid, uuid, bigint, uuid, uuid, text
) to authenticated;

-- =============================================================================
-- Read: the computed figures
-- =============================================================================

create function public.property_finance_kpis(
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
  v_values jsonb;
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

  -- One row per active definition and currency. A definition whose accounts
  -- were booked in two currencies yields two rows; there is no conversion.
  --
  -- An entry contributes at most once, under exactly one line: the account
  -- line if there is one, otherwise the class line. Summing every matching
  -- line instead would double-count the entry an exception was written about,
  -- and the exception is the reason account lines exist.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'kpi_key', row.kpi_key,
        'definition_id', row.definition_id,
        'definition_version', row.definition_version,
        'name', row.name,
        'currency_code', row.currency_code,
        'value', row.value,
        'entries', row.entries
      )
      order by row.kpi_key, row.currency_code
    ),
    '[]'::jsonb
  )
  into v_values
  from (
    select
      definition.kpi_key,
      definition.id as definition_id,
      definition.definition_version,
      definition.name,
      contribution.currency_code,
      sum(contribution.signed_amount) as value,
      count(*) as entries
    from public.finance_kpi_definitions as definition
    join lateral (
      select
        entry.id,
        entry.currency_code,
        entry.amount * case matched.effect
          when 'add'::public.finance_kpi_line_effect then 1
          when 'subtract'::public.finance_kpi_line_effect then -1
        end as signed_amount
      from public.finance_ledger_entries as entry
      join public.finance_accounts as account
        on account.workspace_id = entry.workspace_id
        and account.id = entry.account_id
      join public.finance_periods as period
        on period.workspace_id = entry.workspace_id
        and period.id = entry.period_id
      -- The one line that governs this entry: the account line if there is
      -- one, otherwise the class line. An entry no line matches is simply not
      -- part of this figure.
      join lateral (
        select line.effect
        from public.finance_kpi_definition_lines as line
        where line.workspace_id = definition.workspace_id
          and line.definition_id = definition.id
          and (
            line.account_id = entry.account_id
            or line.account_type = account.account_type
          )
        order by (line.account_id is not null) desc
        limit 1
      ) as matched on true
      where entry.workspace_id = p_workspace_id
        and entry.property_id = p_property_id
        -- An excluded entry contributes nothing *and* is not counted: it is
        -- not part of the figure, so reporting it among the entries behind
        -- the figure would overstate what the number rests on.
        and matched.effect <> 'exclude'::public.finance_kpi_line_effect
        and (
          v_from is null
          or (period.fiscal_year * 12 + period.period_month) >= v_from
        )
        and (
          v_to is null
          or (period.fiscal_year * 12 + period.period_month) <= v_to
        )
    ) as contribution on true
    where definition.workspace_id = p_workspace_id
      and definition.status = 'active'::public.finance_kpi_status
    group by
      definition.kpi_key, definition.id, definition.definition_version,
      definition.name, contribution.currency_code
  ) as row;

  -- Provisionality, on the same basis as the actuals read: any open period in
  -- range makes every figure above provisional.
  select
    count(*) filter (
      where period.status = 'open'::public.finance_period_status
    ),
    count(*)
  into v_open, v_total
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id
    and exists (
      select 1 from public.finance_ledger_entries as entry
      where entry.workspace_id = period.workspace_id
        and entry.period_id = period.id
        and entry.property_id = p_property_id
    )
    and (
      v_from is null
      or (period.fiscal_year * 12 + period.period_month) >= v_from
    )
    and (
      v_to is null
      or (period.fiscal_year * 12 + period.period_month) <= v_to
    );

  return jsonb_build_object(
    'ok', true,
    'as_of', now(),
    'values', v_values,
    'is_provisional', coalesce(v_open, 0) > 0,
    'open_periods', coalesce(v_open, 0),
    'covered_periods', coalesce(v_total, 0),
    -- How many definitions are active at all. An empty `values` with a zero
    -- here means "nobody has told this workspace what to compute"; an empty
    -- `values` with a positive count means "the definitions matched nothing
    -- booked". Those are different answers and a surface must be able to give
    -- the right one.
    'active_definitions', (
      select count(*)
      from public.finance_kpi_definitions as definition
      where definition.workspace_id = p_workspace_id
        and definition.status = 'active'::public.finance_kpi_status
    )
  );
end;
$function$;

alter function public.property_finance_kpis(
  uuid, uuid, integer, integer, integer, integer
) owner to postgres;
revoke all on function public.property_finance_kpis(
  uuid, uuid, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.property_finance_kpis(
  uuid, uuid, integer, integer, integer, integer
) to authenticated;
