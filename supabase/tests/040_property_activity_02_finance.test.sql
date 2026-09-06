begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-ACTIVITY-02.
--
-- Two defects that only became visible once the chronicle was pointed at real
-- data. Both of them are about honesty rather than about a missing feature, so
-- most of what is asserted here is again about *exclusion*:
--
--   * the finance domain reaches the chronicle, but ONLY through the one
--     finance record that carries a `property_id`. The three workspace-level
--     finance entity types must stay out: attributing them to a property would
--     let every property in the workspace claim the same event;
--   * `finance` appears in `visible_domains` for a caller who holds
--     `finance.read` and is absent for one who does not, so "no finance
--     activity" stays distinguishable from "finance activity is not shown";
--   * `event_key` no longer doubles the prefix an action already carries.
--
-- The fixture stores the action strings the real writers store: qualified for
-- every domain except FINANCE-01, which writes bare verbs. Getting that wrong
-- is what let both defects ship green in the first place.

select plan(19);

-- ---------------------------------------------------------------------------
-- The taxonomy contract.
-- ---------------------------------------------------------------------------

select is(
  (select domain from private.property_activity_taxonomy()
   where entity_type = 'finance_ledger_entry'),
  'finance',
  'a ledger entry belongs to the finance domain'
);
select is(
  (select required_permission from private.property_activity_taxonomy()
   where entity_type = 'finance_ledger_entry'),
  'finance.read',
  'and is gated on the permission FINANCE-01a added, not on property.read'
);
select is(
  (select count(*)::integer from private.property_activity_taxonomy()
   where entity_type in (
     'finance_account', 'finance_period', 'finance_kpi_definition',
     'finance_kpi_definition_lines'
   )),
  0,
  'the workspace-level finance records stay out: none of them carries a '
  'property_id, so no single property can honestly claim the event'
);
select is(
  (select count(*)::integer from private.property_activity_taxonomy()),
  15,
  'exactly one entity type was added'
);

-- ---------------------------------------------------------------------------
-- Fixture: two properties, a bookkeeper who may read finance and a member who
-- may not, one ledger entry per property plus workspace-level finance events.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin-blind@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('e1000000-0000-0000-0000-000000000001', 'act-fin', 'Activity Finance');

select private.seed_workspace_role_catalog('e1000000-0000-0000-0000-000000000001');

-- A role that reads the property and its leasing but never its money. It is
-- the whole point of the per-row gate.
insert into public.roles (id, workspace_id, key, name) values (
  'e3000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000001',
  'no_finance', 'No Finance'
);
insert into public.role_permissions (workspace_id, role_id, permission_id)
select 'e1000000-0000-0000-0000-000000000001',
       'e3000000-0000-0000-0000-000000000001',
       permission.id
from public.permissions as permission
where permission.key in ('property.read', 'lease.read');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'e1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('e4000000-0000-0000-0000-000000000001'::uuid, 'e2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('e4000000-0000-0000-0000-000000000002'::uuid, 'e2000000-0000-0000-0000-000000000002'::uuid, 'no_finance')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'e1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'Kontohaus', 'Bilanzweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  -- The neighbour, so "scoped to this property" is actually tested rather than
  -- assumed from a single-property fixture.
  ('e5000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'Nachbarkonto', 'Bilanzweg 3', '10115', 'Berlin', 'de', 'residential', 1,
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

insert into public.finance_accounts (
  id, workspace_id, code, name, account_type, created_by, updated_by
) values (
  'e6000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  '4000', 'Mietertraege', 'income',
  'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'
);

insert into public.finance_periods (
  id, workspace_id, fiscal_year, period_month, created_by, updated_by
) values (
  'e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  2026, 8,
  'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'
);

insert into public.finance_ledger_entries (
  id, workspace_id, property_id, account_id, period_id, booked_on, amount,
  currency_code, description, created_by, updated_by
) values
  ('e8000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
   'e7000000-0000-0000-0000-000000000001', date '2026-08-31', 1200.00, 'EUR',
   'Miete August',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  ('e8000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-000000000001',
   'e7000000-0000-0000-0000-000000000001', date '2026-08-31', 900.00, 'EUR',
   'Miete August Nachbar',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

-- Audit rows. FINANCE-01 stores bare verbs; everything else stores its action
-- already qualified with its own entity. Both shapes are here on purpose,
-- because `event_key` has to behave correctly for each.
insert into public.audit_events (
  id, workspace_id, actor_type, actor_user_id, actor_identifier, role_key,
  scope_snapshot, action, entity_type, entity_id, source, correlation_id,
  mutation_id, reason, old_values, new_values, created_at, created_by,
  updated_by
) values
  -- The booking on THIS property.
  ('e9000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'user', 'e2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'create', 'finance_ledger_entry', 'e8000000-0000-0000-0000-000000000001', 'rpc',
   'ea000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
   null, null, '{"amount": "1200.00"}',
   now() - interval '5 hours',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  -- The booking on the NEIGHBOUR: right workspace, wrong building.
  ('e9000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'user', 'e2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'create', 'finance_ledger_entry', 'e8000000-0000-0000-0000-000000000002', 'rpc',
   'ea000000-0000-0000-0000-000000000002', 'eb000000-0000-0000-0000-000000000002',
   null, null, '{"amount": "900.00"}',
   now() - interval '4 hours',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  -- Opening a fiscal period: a workspace act. It has no property and must not
  -- be lent one.
  ('e9000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001',
   'user', 'e2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'create', 'finance_period', 'e7000000-0000-0000-0000-000000000001', 'rpc',
   'ea000000-0000-0000-0000-000000000003', 'eb000000-0000-0000-0000-000000000003',
   null, null, '{"period_month": 8}',
   now() - interval '3 hours',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  -- Same for a chart-of-accounts change.
  ('e9000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
   'user', 'e2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'create', 'finance_account', 'e6000000-0000-0000-0000-000000000001', 'rpc',
   'ea000000-0000-0000-0000-000000000004', 'eb000000-0000-0000-0000-000000000004',
   null, null, '{"code": "4000"}',
   now() - interval '2 hours',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001'),
  -- A qualified action, so the key rule is tested against both shapes.
  ('e9000000-0000-0000-0000-000000000005', 'e1000000-0000-0000-0000-000000000001',
   'user', 'e2000000-0000-0000-0000-000000000001', null, 'admin', '{}',
   'property.update', 'property', 'e5000000-0000-0000-0000-000000000001', 'rpc',
   'ea000000-0000-0000-0000-000000000005', 'eb000000-0000-0000-0000-000000000005',
   null, '{"city": "Bonn"}', '{"city": "Berlin"}',
   now() - interval '1 hour',
   'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001');

create or replace function pg_temp.activity(
  p_user uuid,
  p_property uuid default 'e5000000-0000-0000-0000-000000000001',
  p_domains text[] default null
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user::text, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  select public.property_activity(
    'e1000000-0000-0000-0000-000000000001', p_property, p_domains,
    null, null, null, null, 50
  ) into v_result;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- The booking reaches the chronicle, and only its own property's.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  1,
  'the booking on this property is in the chronicle'
);
select is(
  (select event ->> 'entity_id'
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  'e8000000-0000-0000-0000-000000000001',
  'and it is this property''s booking, not the neighbour''s'
);
select is(
  (select event ->> 'domain'
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  'finance',
  'it is filed under finance'
);
select is(
  (select event ->> 'entity_id'
   from jsonb_array_elements(
     pg_temp.activity(
       'e2000000-0000-0000-0000-000000000001',
       'e5000000-0000-0000-0000-000000000002'
     ) -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  'e8000000-0000-0000-0000-000000000002',
  'the neighbour''s chronicle carries the neighbour''s booking'
);

-- ---------------------------------------------------------------------------
-- The workspace-level finance records stay out.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_type' in ('finance_period', 'finance_account')),
  0,
  'opening a period and adding an account are workspace acts: they belong to '
  'no single property and appear in none'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity(
       'e2000000-0000-0000-0000-000000000001',
       'e5000000-0000-0000-0000-000000000002'
     ) -> 'events'
   ) as event
   where event ->> 'entity_type' in ('finance_period', 'finance_account')),
  0,
  'and they do not fall through to the neighbour either'
);

-- ---------------------------------------------------------------------------
-- Coverage: the domain is named, or honestly absent.
-- ---------------------------------------------------------------------------

select ok(
  (pg_temp.activity('e2000000-0000-0000-0000-000000000001')
     -> 'visible_domains') @> '["finance"]'::jsonb,
  'a caller with finance.read is told finance is covered'
);
select ok(
  not (
    (pg_temp.activity('e2000000-0000-0000-0000-000000000002')
       -> 'visible_domains') @> '["finance"]'::jsonb
  ),
  'a caller without it is not: the coverage list is the permission statement, '
  'so "no finance activity" stays distinguishable from "not shown"'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000002') -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  0,
  'and that caller sees no booking, filtered server-side rather than hidden'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity(
       'e2000000-0000-0000-0000-000000000001',
       'e5000000-0000-0000-0000-000000000001',
       array['finance']
     ) -> 'events'
   )),
  1,
  'the domain filter selects finance alone'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity(
       'e2000000-0000-0000-0000-000000000002',
       'e5000000-0000-0000-0000-000000000001',
       array['finance']
     ) -> 'events'
   )),
  0,
  'a filter on a domain the caller cannot see is an empty timeline, not a '
  'refusal'
);

-- ---------------------------------------------------------------------------
-- The event key stops doubling.
-- ---------------------------------------------------------------------------

select is(
  (select event ->> 'event_key'
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_id' = 'e5000000-0000-0000-0000-000000000001'),
  'property.update',
  'an action that already carries its entity is published as it stands, not '
  'as property.property.update'
);
select is(
  (select event ->> 'event_key'
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'entity_type' = 'finance_ledger_entry'),
  'finance_ledger_entry.create',
  'a bare verb still gets its entity, because there it is genuinely missing'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'event_key' like
     (event ->> 'entity_type') || '.' || (event ->> 'entity_type') || '.%'),
  0,
  'no row doubles its prefix'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     pg_temp.activity('e2000000-0000-0000-0000-000000000001') -> 'events'
   ) as event
   where event ->> 'event_key' is null
      or event ->> 'event_key' = ''),
  0,
  'and every row still has one'
);

select * from finish();

rollback;
