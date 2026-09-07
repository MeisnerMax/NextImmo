-- COMPLIANCE-RULES-01 (V-4): the legal rule layer, with a validity period and
-- a named confirmation on every rule.
--
-- `DEC-014` was open since Phase 0 -- "Legal/tax/accounting rules require
-- external domain validation" -- and the owner granted it on 2026-09-07. This
-- is what that approval can and cannot buy, made structural.
--
-- **Why this is data and not constants.** An operating-cost statement for 2024
-- runs under different law than one for 2026: the TV Nebenkostenprivileg
-- expired on 30.06.2024, § 556 BGB changed on 01.01.2025, the CO2 price moves
-- every year, and the GEG became the GModG in July 2026. A retrospective
-- correction must apply the law *of that period*, not today's. A constant in
-- code cannot do that, and a constant that is silently updated makes every
-- past statement irreproducible. So a rule is a row with a validity period,
-- and asking for a figure means asking as of a date.
--
-- **Why every rule carries who confirmed it.** The research behind these rules
-- lists seven points where the source position is contradictory -- GModG and
-- energy certificates, § 7 CO2KostAufG, the cumulability of the § 12
-- HeizkostenV reductions, BGH VIII ZR 6/24 in full, §§ 5a-5d CO2KostAufG, VAT
-- on opted commercial letting, BetrKV § 2. An owner's approval does not make a
-- contradictory source unambiguous. What it can do is authorise the shape:
-- the product proposes, a named person confirms, and the confirmation is
-- stored as an event with a date and an actor. `verified = false` is therefore
-- not a defect state; it is the normal state of a rule nobody has yet checked,
-- and the read reports it so no calculation can quietly rest on one.
--
-- **`decision_support` is the third state, and it is the important one.**
-- § 5d CO2KostAufG is a five-part cumulative test with open legal concepts.
-- The programme's own instruction is "als Assistenz mit Bestätigung bauen,
-- nicht als automatische Entscheidung". A rule marked `decision_support` may
-- be shown, may be proposed, and may **never** be applied without a human
-- decision recorded against the case it was applied to. The column exists so
-- that instruction survives contact with a later author who only reads the
-- schema.
--
-- **No overlap per rule key.** Two rules of the same key covering one day
-- would make "the CO2 price on 3 March 2026" have two answers. An EXCLUSION
-- constraint over `btree_gist` forbids it declaratively, the same way
-- `lease_components` forbids two rents for one day.
--
-- **This package computes nothing.** It stores the rules and answers "what was
-- in force on this date". The settlement engine (P-5) is what applies them,
-- and the four `Mindestangaben` validator belongs there too -- it validates a
-- statement before dispatch, which is a different thing from knowing the law.
--
-- **The mutation plumbing is reused, not re-poured.** The gate, the
-- idempotency claim and the audit finish are `private.party_command_gate`,
-- `private.claim_party_mutation` and `private.finish_party_mutation`. Their
-- names date from P2-D02 and their bodies do not mention parties at all: the
-- gate checks the caller and the identifiers, the claim takes the entity type
-- as a parameter, the finish takes the action and the entity type. A third
-- copy of that seventy-line receipt dance under a compliance-flavoured name
-- would be three places for the same idempotency rule to drift. The name is a
-- historical accident; the behaviour is the house contract.
--
-- **Writes need `security.manage`, reads need `workspace.read`.** There is no
-- `workspace.manage` key in the catalogue -- the first draft of this migration
-- gated on one, which would have made the write path dead for everyone
-- including the admin, silently. `security.manage` is the existing
-- workspace-administration capability and only `admin` holds it, which is the
-- right shape anyway: the workspace's legal position is policy, not day-to-day
-- data, and a manager who may edit a lease should not be able to change what
-- the law says about it. Reading is open to anyone who may read the workspace,
-- because a rule nobody can see is a rule nobody can challenge. Inventing a
-- `compliance.manage` key was the alternative, and it would have put a new
-- capability in the catalogue without a decision about who holds it.
--
-- Three new public functions and one private one: SR-20 92 -> 95.
-- One new client-reachable policy: SR-22 50 -> 51.

-- ---------------------------------------------------------------------------
-- How much a rule may be trusted
-- ---------------------------------------------------------------------------

create type public.compliance_rule_confidence as enum (
  -- Nobody has checked it. The default, and never a reason to hide the rule --
  -- an unchecked figure that is visible gets challenged; one that is hidden
  -- gets used by whatever code reached for it.
  'unverified',
  -- A named person confirmed it against a source. The confirmation is stored
  -- with them and the date.
  'verified',
  -- The law requires a judgement here. May be proposed to a human, may never
  -- be applied on its own. §§ 5a-5d CO2KostAufG is why this value exists.
  'decision_support'
);

-- ---------------------------------------------------------------------------
-- The rules
-- ---------------------------------------------------------------------------

create table public.compliance_rules (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,

  -- Free text rather than an enum, deliberately. The rule vocabulary grows
  -- with the law -- §§ 5a-5d did not exist when this schema was designed --
  -- and a migration is the wrong place to be the gatekeeper of what a
  -- workspace is allowed to record about its own legal position.
  rule_key text not null,

  -- 'DE' today. Named rather than assumed, because a workspace holding
  -- Austrian assets would otherwise silently apply German operating-cost law
  -- to them.
  jurisdiction text not null default 'DE',

  -- Inclusive at both ends, as a statute reads. Null `valid_to` is open-ended,
  -- which is the normal state of current law.
  valid_from date not null,
  valid_to date,

  -- The value, shaped by the rule. A CO2 price is a number with a unit; the
  -- 70% rule is three booleans; the Umlageausfallwagnis is a capped percent
  -- with a precondition. One jsonb column rather than a column per shape,
  -- because the alternative is a migration every time the legislature invents
  -- a new kind of threshold.
  value jsonb not null,
  unit text,

  -- Where it comes from. Not optional: a legal figure without a source is a
  -- number somebody remembered, and this whole package exists because the
  -- programme insisted the research be "recherchiert, nicht aus dem
  -- Gedächtnis".
  source_reference text not null,
  note text,

  confidence public.compliance_rule_confidence not null default 'unverified',
  -- Both set together with the confirmation, both cleared when it is
  -- withdrawn. A verification without an author is not a verification.
  verified_by uuid,
  verified_at timestamptz,
  verification_note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,

  -- Half-open internally so adjacent periods do not overlap, inclusive at the
  -- edges of the API so `valid_to` reads the way a transitional provision
  -- does. The same construction `lease_components` uses.
  validity daterange generated always as (
    daterange(
      valid_from,
      case when valid_to is null then null else valid_to + 1 end,
      '[)'
    )
  ) stored,

  constraint compliance_rules_workspace_id_key unique (workspace_id, id),
  constraint compliance_rules_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint compliance_rules_key_check check (
    char_length(btrim(rule_key)) between 1 and 100
    and rule_key = btrim(rule_key)
  ),
  constraint compliance_rules_jurisdiction_check check (
    jurisdiction = upper(btrim(jurisdiction))
    and char_length(jurisdiction) between 2 and 8
  ),
  constraint compliance_rules_term_check check (
    valid_to is null or valid_to >= valid_from
  ),
  constraint compliance_rules_source_check check (
    char_length(btrim(source_reference)) between 1 and 500
  ),
  constraint compliance_rules_note_check check (
    note is null or char_length(btrim(note)) between 1 and 4000
  ),
  constraint compliance_rules_unit_check check (
    unit is null or char_length(btrim(unit)) between 1 and 40
  ),
  -- A verification is a person and a moment, together or not at all. Without
  -- this a rule could read `verified` with nobody standing behind it, which is
  -- worse than `unverified` because it stops the question being asked.
  constraint compliance_rules_verification_check check (
    (confidence = 'verified'
      and verified_by is not null and verified_at is not null)
    or (confidence <> 'verified'
      and verified_by is null and verified_at is null
      and verification_note is null)
  ),
  constraint compliance_rules_verification_note_check check (
    verification_note is null
    or char_length(btrim(verification_note)) between 1 and 2000
  ),
  constraint compliance_rules_version_check check (version >= 1),

  -- The invariant this table exists to hold: for one workspace, one
  -- jurisdiction and one rule key, no two rows may cover the same day.
  -- Otherwise "the CO2 price on 3 March 2026" has two answers.
  constraint compliance_rules_no_overlap exclude using gist (
    workspace_id extensions.gist_uuid_ops with =,
    jurisdiction extensions.gist_text_ops with =,
    rule_key extensions.gist_text_ops with =,
    validity with &&
  )
);

create index compliance_rules_key_idx
  on public.compliance_rules (workspace_id, rule_key);
create index compliance_rules_confidence_idx
  on public.compliance_rules (workspace_id, confidence);

create trigger compliance_rules_protected_columns
before update on public.compliance_rules
-- Named, not empty: the trigger reads its protected columns from `tg_argv`,
-- and calling it with none makes that array NULL rather than empty, which
-- fails on the first update with "FOREACH expression must not be null".
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.compliance_rules enable row level security;
alter table public.compliance_rules force row level security;

-- Read by anyone who may read the workspace. A legal rule is not confidential
-- within the workspace that adopted it, and hiding it from the people who have
-- to work under it is how an unverified figure gets applied unchallenged.
create policy compliance_rules_select_workspace_read
on public.compliance_rules
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'workspace.read'));

revoke all on table public.compliance_rules from public, anon, authenticated;
grant select on table public.compliance_rules to authenticated;

comment on table public.compliance_rules is
  'Legal, tax and accounting rules as versioned data (DEC-014). A statement '
  'for 2024 runs under different law than one for 2026, and a retrospective '
  'correction must apply the law of its own period -- which a constant in '
  'code cannot do. Every rule carries its source and, when somebody has '
  'checked it, who and when.';

-- ---------------------------------------------------------------------------
-- The audit payload
-- ---------------------------------------------------------------------------

create function private.compliance_rule_snapshot(rule public.compliance_rules)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', rule.id,
    'workspace_id', rule.workspace_id,
    'rule_key', rule.rule_key,
    'jurisdiction', rule.jurisdiction,
    'valid_from', rule.valid_from,
    'valid_to', rule.valid_to,
    'value', rule.value,
    'unit', rule.unit,
    'source_reference', rule.source_reference,
    'note', rule.note,
    'confidence', rule.confidence,
    'verified_by', rule.verified_by,
    'verified_at', rule.verified_at,
    'verification_note', rule.verification_note,
    'created_at', rule.created_at,
    'updated_at', rule.updated_at,
    'created_by', rule.created_by,
    'updated_by', rule.updated_by,
    'version', rule.version
  );
$function$;

alter function private.compliance_rule_snapshot(public.compliance_rules)
  owner to postgres;
revoke all on function private.compliance_rule_snapshot(public.compliance_rules)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------

create function public.compliance_rules_as_of(
  p_workspace_id uuid,
  p_as_of date default null,
  p_rule_key text default null,
  p_jurisdiction text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_as_of date := coalesce(p_as_of, private.operations_today());
  v_jurisdiction text := upper(btrim(coalesce(p_jurisdiction, 'DE')));
  v_rules jsonb;
  v_unverified integer;
  v_decision_support integer;
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

  if not private.has_workspace_permission(p_workspace_id, 'workspace.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Compliance rules are not permitted'
      )
    );
  end if;

  select
    coalesce(
      jsonb_agg(
        private.compliance_rule_snapshot(rule) order by rule.rule_key
      ),
      '[]'::jsonb
    ),
    count(*) filter (where rule.confidence = 'unverified')::integer,
    count(*) filter (where rule.confidence = 'decision_support')::integer
  into v_rules, v_unverified, v_decision_support
  from public.compliance_rules as rule
  where rule.workspace_id = p_workspace_id
    and rule.jurisdiction = v_jurisdiction
    and (p_rule_key is null or rule.rule_key = btrim(p_rule_key))
    -- The whole point of the table: what was in force on that day, not what
    -- is in force now.
    and rule.validity @> v_as_of;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'as_of_date', v_as_of,
      'jurisdiction', v_jurisdiction,
      'rules', v_rules,
      -- Counted and reported rather than left for the caller to tally. A
      -- calculation resting on rules nobody has checked has to be able to say
      -- so on its own face, and it can only do that if the read tells it.
      'unverified_count', v_unverified,
      'decision_support_count', v_decision_support
    )
  );
end;
$function$;

alter function public.compliance_rules_as_of(uuid, date, text, text)
  owner to postgres;
revoke all on function public.compliance_rules_as_of(uuid, date, text, text)
  from public, anon, authenticated;
grant execute on function public.compliance_rules_as_of(uuid, date, text, text)
  to authenticated;

comment on function public.compliance_rules_as_of(uuid, date, text, text) is
  'The rules in force on a date. Reports how many of them are unverified and '
  'how many require a human decision, so a calculation built on them can say '
  'so rather than presenting an unchecked figure as settled law.';

-- ---------------------------------------------------------------------------
-- upsert_compliance_rule
-- ---------------------------------------------------------------------------

create function public.upsert_compliance_rule(
  p_workspace_id uuid,
  p_rule_key text,
  p_valid_from date,
  p_value jsonb,
  p_source_reference text,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_rule_id uuid default null,
  p_expected_version bigint default null,
  p_valid_to date default null,
  p_unit text default null,
  p_note text default null,
  p_jurisdiction text default 'DE',
  p_decision_support boolean default false,
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
  v_old public.compliance_rules%rowtype;
  v_new public.compliance_rules%rowtype;
  v_jurisdiction text := upper(btrim(coalesce(p_jurisdiction, 'DE')));
  v_confidence public.compliance_rule_confidence;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_rule_key is null
     or char_length(btrim(p_rule_key)) not between 1 and 100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Rule key is invalid',
        'field', 'ruleKey'
      )
    );
  end if;

  if p_valid_from is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A start date is required',
        'field', 'validFrom'
      )
    );
  end if;

  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A value is required',
        'field', 'value'
      )
    );
  end if;

  -- Not optional, and this is the one validation worth arguing about. A legal
  -- figure without a source is a number somebody remembered, and the research
  -- this table encodes was commissioned precisely because remembering was not
  -- good enough.
  if p_source_reference is null
     or char_length(btrim(p_source_reference)) not between 1 and 500 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A source reference is required',
        'field', 'sourceReference'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage')
     or not private.has_workspace_permission(p_workspace_id, 'workspace.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Compliance rule write is not permitted'
      )
    );
  end if;

  -- A write never verifies. Editing a rule is stating the law; confirming it
  -- is a domain expert vouching for that statement, and one action cannot be
  -- both. An edit to a verified rule therefore drops it back to unverified,
  -- because what was confirmed is no longer what is stored.
  v_confidence := case
    when coalesce(p_decision_support, false)
      then 'decision_support'::public.compliance_rule_confidence
    else 'unverified'::public.compliance_rule_confidence
  end;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'upsert_compliance_rule',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'rule_id', p_rule_id,
        'rule_key', p_rule_key,
        'jurisdiction', v_jurisdiction,
        'valid_from', p_valid_from,
        'valid_to', p_valid_to,
        'value', p_value,
        'unit', p_unit,
        'source_reference', p_source_reference,
        'note', p_note,
        'decision_support', p_decision_support,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  if p_rule_id is not null then
    if p_expected_version is null or p_expected_version < 1 then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'An expected version is required when editing a rule',
          'field', 'expectedVersion'
        )
      );
    end if;

    select rule.* into v_old
    from public.compliance_rules as rule
    where rule.workspace_id = p_workspace_id and rule.id = p_rule_id
    for update;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'not_found', 'message', 'Compliance rule not found'
        )
      );
    end if;
  end if;

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'compliance_rule'
  );
  if v_claim is not null then
    return v_claim;
  end if;

  if p_rule_id is not null and v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Compliance rule version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.compliance_rule_snapshot(v_old)
      )
    );
  end if;

  begin
    if p_rule_id is null then
      insert into public.compliance_rules (
        workspace_id, rule_key, jurisdiction, valid_from, valid_to, value,
        unit, source_reference, note, confidence, created_by, updated_by
      ) values (
        p_workspace_id, btrim(p_rule_key), v_jurisdiction, p_valid_from,
        p_valid_to, p_value,
        nullif(btrim(coalesce(p_unit, '')), ''),
        btrim(p_source_reference),
        nullif(btrim(coalesce(p_note, '')), ''),
        v_confidence, v_actor_id, v_actor_id
      )
      returning * into v_new;
    else
      update public.compliance_rules as rule
      set
        rule_key = btrim(p_rule_key),
        jurisdiction = v_jurisdiction,
        valid_from = p_valid_from,
        valid_to = p_valid_to,
        value = p_value,
        unit = nullif(btrim(coalesce(p_unit, '')), ''),
        source_reference = btrim(p_source_reference),
        note = nullif(btrim(coalesce(p_note, '')), ''),
        confidence = v_confidence,
        verified_by = null,
        verified_at = null,
        verification_note = null,
        updated_at = now(),
        updated_by = v_actor_id,
        version = rule.version + 1
      where rule.workspace_id = p_workspace_id and rule.id = p_rule_id
      returning * into v_new;
    end if;
  exception
    when exclusion_violation then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'dependency_conflict',
          'message',
            'Another rule with this key already covers part of that period'
        )
      );
    when check_violation then
      delete from public.mutation_receipts
      where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed', 'message', 'The rule is inconsistent'
        )
      );
  end;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when p_rule_id is null
      then 'compliance_rule.create' else 'compliance_rule.update' end,
    'compliance_rule', v_new.id,
    case when p_rule_id is null
      then null else private.compliance_rule_snapshot(v_old) end,
    private.compliance_rule_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.compliance_rule_snapshot(v_new)
  );
end;
$function$;

alter function public.upsert_compliance_rule(
  uuid, text, date, jsonb, text, uuid, uuid, uuid, bigint, date, text, text,
  text, boolean, text
) owner to postgres;
revoke all on function public.upsert_compliance_rule(
  uuid, text, date, jsonb, text, uuid, uuid, uuid, bigint, date, text, text,
  text, boolean, text
) from public, anon, authenticated;
grant execute on function public.upsert_compliance_rule(
  uuid, text, date, jsonb, text, uuid, uuid, uuid, bigint, date, text, text,
  text, boolean, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- verify_compliance_rule: the confirmation, as its own event
-- ---------------------------------------------------------------------------

create function public.verify_compliance_rule(
  p_workspace_id uuid,
  p_rule_id uuid,
  p_expected_version bigint,
  p_verified boolean,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_verification_note text default null,
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
  v_old public.compliance_rules%rowtype;
  v_new public.compliance_rules%rowtype;
begin
  v_gate := private.party_command_gate(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if p_rule_id is null or p_expected_version is null
     or p_expected_version < 1 or p_verified is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Rule id, expected version and the verdict are required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'security.manage')
     or not private.has_workspace_permission(p_workspace_id, 'workspace.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'Compliance rule verification is not permitted'
      )
    );
  end if;

  select rule.* into v_old
  from public.compliance_rules as rule
  where rule.workspace_id = p_workspace_id and rule.id = p_rule_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Compliance rule not found'
      )
    );
  end if;

  -- A rule the law leaves to judgement cannot be signed off into an automatic
  -- one. Confirming it would turn "a human must decide each case" into "this
  -- was decided once, for all cases" -- which is the failure the
  -- `decision_support` state exists to prevent, and the reason § 5d
  -- CO2KostAufG is named in the programme by number.
  if p_verified and v_old.confidence = 'decision_support' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A decision-support rule cannot be verified into an automatic one. '
          'It is confirmed per case, not once for all of them.',
        'field', 'verified'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'verify_compliance_rule',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'rule_id', p_rule_id,
        'expected_version', p_expected_version,
        'verified', p_verified,
        'verification_note', p_verification_note,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  v_claim := private.claim_party_mutation(
    p_workspace_id, p_mutation_id, v_request_hash, 'compliance_rule'
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
        'message', 'Compliance rule version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_entity', private.compliance_rule_snapshot(v_old)
      )
    );
  end if;

  update public.compliance_rules as rule
  set
    confidence = case
      when p_verified then 'verified'::public.compliance_rule_confidence
      else 'unverified'::public.compliance_rule_confidence
    end,
    -- Withdrawing a verification clears the author with it. A rule that says
    -- "unverified" while still naming who checked it invites the reader to
    -- trust the name over the state.
    verified_by = case when p_verified then v_actor_id else null end,
    verified_at = case when p_verified then now() else null end,
    verification_note = case
      when p_verified
        then nullif(btrim(coalesce(p_verification_note, '')), '')
      else null
    end,
    updated_at = now(),
    updated_by = v_actor_id,
    version = rule.version + 1
  where rule.workspace_id = p_workspace_id and rule.id = p_rule_id
  returning * into v_new;

  perform private.finish_party_mutation(
    p_workspace_id, p_mutation_id, p_correlation_id, p_reason,
    case when p_verified
      then 'compliance_rule.verify' else 'compliance_rule.unverify' end,
    'compliance_rule', p_rule_id,
    private.compliance_rule_snapshot(v_old),
    private.compliance_rule_snapshot(v_new)
  );

  return jsonb_build_object(
    'ok', true, 'entity', private.compliance_rule_snapshot(v_new)
  );
end;
$function$;

alter function public.verify_compliance_rule(
  uuid, uuid, bigint, boolean, uuid, uuid, text, text
) owner to postgres;
revoke all on function public.verify_compliance_rule(
  uuid, uuid, bigint, boolean, uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.verify_compliance_rule(
  uuid, uuid, bigint, boolean, uuid, uuid, text, text
) to authenticated;

comment on function public.verify_compliance_rule(
  uuid, uuid, bigint, boolean, uuid, uuid, text, text
) is
  'Records that a named person checked a rule against its source, or withdraws '
  'that. Its own command because editing a rule states the law and verifying '
  'it vouches for the statement -- one action cannot be both, and an edit '
  'therefore drops the rule back to unverified.';
