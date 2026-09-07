begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-CARD-METRICS-01 (P-1b).
--
-- The batch read exists to stop the card grid being uninformative. Its risk is
-- not performance, it is **disagreement**: a card that says four open tickets
-- next to a detail screen that says three destroys trust in both. So the
-- centrepiece of this file is not a count, it is an equality — the batch's
-- leasing and maintenance blocks must be the overview's, whole object against
-- whole object, for the same property.
--
-- That assertion is what makes the duplicated expressions in the migration
-- safe. They were copied rather than extracted, deliberately (extracting them
-- means dropping and recreating a 350-line security-sensitive function), and
-- this is the price: an edit to either side that changes a number fails here.
--
-- The rest pins what the batch does that the single read never had to: a cap,
-- a withheld list that refuses to say why, and zeros that mean zero while
-- absent sections mean absent.
--
-- One note for whoever edits this next. The per-field count assertions above
-- the equality look redundant next to it, and they are not: they are what
-- stops the equality passing vacuously. `is(null, null)` succeeds, so two
-- helpers that both stopped returning anything would agree perfectly. Pinning
-- the card's own numbers first means the comparison always has a real object
-- on at least one side. The fixture is built so those numbers are non-zero --
-- an all-zero fixture would compare two empty answers and prove nothing.

select plan(37);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_function('public', 'property_card_metrics',
  'the batch card read exists');

select is(
  (select prosecdef from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_card_metrics'),
  true,
  'it is security definer, like every other public read');

select is(
  (select provolatile from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'property_card_metrics'),
  's'::"char",
  'and stable: a read, never a mutation');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_card_metrics'
     and acl.grantee::oid in ('anon'::regrole::oid, 0)),
  0,
  'neither anon nor PUBLIC can call it -- revoke names public explicitly, '
  'because a bare grant leaves PUBLIC its default EXECUTE');

-- ---------------------------------------------------------------------------
-- Fixture: one workspace, three properties, plus a second workspace as the
-- cross-tenant canary.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('11200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'card-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('11200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'card-viewer@example.test', '', now(), '{}', '{}', now(), now()),
  ('11200000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'card-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('11100000-0000-0000-0000-000000000001', 'card-a', 'Card A'),
  ('11100000-0000-0000-0000-000000000002', 'card-b', 'Card B');
select private.seed_workspace_role_catalog('11100000-0000-0000-0000-000000000001');
select private.seed_workspace_role_catalog('11100000-0000-0000-0000-000000000002');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '11100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('11200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  -- viewer holds property.read and lease.read but NOT maintenance.read: the
  -- one actor that can prove a section goes absent rather than to zero.
  ('11200000-0000-0000-0000-000000000002'::uuid, 'viewer')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '11100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('11500000-0000-0000-0000-000000000001', '11100000-0000-0000-0000-000000000001',
   'Kartenhaus A', 'Kartenweg 1', '10115', 'Berlin', 'de', 'residential', 2,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11500000-0000-0000-0000-000000000002', '11100000-0000-0000-0000-000000000001',
   'Kartenhaus B', 'Kartenweg 2', '10115', 'Berlin', 'de', 'residential', 1,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  -- Nothing has ever been recorded against C. Its numbers must be 0, and
  -- 0 must be distinguishable from "you may not see this".
  ('11500000-0000-0000-0000-000000000003', '11100000-0000-0000-0000-000000000001',
   'Leerhaus C', 'Kartenweg 3', '10115', 'Berlin', 'de', 'residential', 0,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11500000-0000-0000-0000-000000000009', '11100000-0000-0000-0000-000000000002',
   'Fremdhaus', 'Fremdweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001');

insert into public.units (
  id, workspace_id, property_id, unit_code, status, vacancy_since,
  created_by, updated_by
) values
  ('11600000-0000-0000-0000-000000000001', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', 'A-01', 'occupied', null,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11600000-0000-0000-0000-000000000002', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', 'A-02', 'vacant', current_date,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11600000-0000-0000-0000-000000000003', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000002', 'B-01', 'vacant', current_date,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001');

-- An active lease ending inside 90 days, so the leasing block is not all
-- zeroes when it is compared against the overview's.
insert into public.leases (
  id, workspace_id, property_id, unit_id, lease_name, status,
  start_date, end_date, move_out_date, ended_at,
  base_rent_monthly, currency_code, created_by, updated_by
) values
  ('11700000-0000-0000-0000-000000000001', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', '11600000-0000-0000-0000-000000000001',
   'Laufend A', 'active', current_date - 200, current_date + 30, null, null,
   1000, 'EUR',
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001');

insert into public.maintenance_tickets (
  id, workspace_id, property_id, title, status, priority, due_at, resolved_at,
  created_by, updated_by
) values
  ('11800000-0000-0000-0000-000000000001', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', 'Heizung', 'new', 'urgent',
   now() - interval '2 days', null,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11800000-0000-0000-0000-000000000002', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', 'Fenster', 'triage', 'normal',
   now() + interval '10 days', null,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11800000-0000-0000-0000-000000000003', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000001', 'Erledigt', 'archived', 'normal', null,
   now() - interval '1 day',
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001'),
  ('11800000-0000-0000-0000-000000000004', '11100000-0000-0000-0000-000000000001',
   '11500000-0000-0000-0000-000000000002', 'Nachbar-Ticket', 'new', 'normal',
   null, null,
   '11200000-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function pg_temp.act_as(p_user uuid, p_aal text)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated',
                      'aal', p_aal)::text,
    true
  );
end;
$$;

create or replace function pg_temp.cards(
  p_user uuid,
  p_ids uuid[],
  p_aal text default 'aal2',
  p_workspace uuid default '11100000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, p_aal);
  v_result := public.property_card_metrics(p_workspace, p_ids);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v_result;
end;
$$;

-- The card for one property, out of a batch that also asked for others.
create or replace function pg_temp.card_of(p_user uuid, p_property uuid)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(
    pg_temp.cards(p_user, array[
      '11500000-0000-0000-0000-000000000001'::uuid,
      '11500000-0000-0000-0000-000000000002'::uuid,
      '11500000-0000-0000-0000-000000000003'::uuid
    ]) #> '{entity,properties}'
  ) as entry
  where entry ->> 'property_id' = p_property::text;
$$;

create or replace function pg_temp.overview_of(p_user uuid, p_property uuid)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, 'aal2');
  v_result := public.property_overview(
    '11100000-0000-0000-0000-000000000001', p_property
  );
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

select is(
  public.property_card_metrics(
    '11100000-0000-0000-0000-000000000001',
    array['11500000-0000-0000-0000-000000000001'::uuid]
  ) #>> '{error,code}',
  'forbidden',
  'an unauthenticated caller is refused');

select is(
  pg_temp.cards('11200000-0000-0000-0000-000000000001',
                array['11500000-0000-0000-0000-000000000001'::uuid], 'aal1')
    #>> '{error,code}',
  'forbidden',
  'an aal1 session is refused (DEC-025), before any id is looked at');

select is(
  pg_temp.cards('11200000-0000-0000-0000-000000000001',
                array['11500000-0000-0000-0000-000000000001'::uuid],
                'aal2', null)
    #>> '{error,field}',
  'workspaceId',
  'a missing workspace is a validation failure, not a silent empty page');

select is(
  pg_temp.cards('11200000-0000-0000-0000-000000000001', null::uuid[])
    #>> '{error,field}',
  'propertyIds',
  'and so is a missing id list -- null is not "all properties"');

-- ---------------------------------------------------------------------------
-- The cap
-- ---------------------------------------------------------------------------

select is(
  pg_temp.cards(
    '11200000-0000-0000-0000-000000000001',
    (select array_agg(gen_random_uuid()) from generate_series(1, 201))
  ) #>> '{error,code}',
  'validation_failed',
  'past the cap the read refuses. An uncapped = any(...) is a way to ask one '
  'statement to scan the whole tenant');

select is(
  pg_temp.cards(
    '11200000-0000-0000-0000-000000000001',
    array['11500000-0000-0000-0000-000000000001'::uuid]
      || (select array_agg(gen_random_uuid()) from generate_series(1, 199))
  ) -> 'ok',
  to_jsonb(true),
  'exactly at the cap it does not: the boundary is 200, not 199');

select is(
  jsonb_array_length(
    pg_temp.cards('11200000-0000-0000-0000-000000000001',
                  array[]::uuid[]) #> '{entity,properties}'
  ),
  0,
  'an empty list is an empty answer, not an error -- a grid with no page to '
  'fill asked a well-formed question');

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000001',
      array['11500000-0000-0000-0000-000000000001'::uuid,
            '11500000-0000-0000-0000-000000000001'::uuid,
            null]
    ) #> '{entity,properties}'
  ),
  1,
  'duplicates collapse and nulls drop before the cap is measured: asking for '
  'one property forty times asked for one property');

-- ---------------------------------------------------------------------------
-- The numbers, and that they belong to the right property
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000001',
      array['11500000-0000-0000-0000-000000000001'::uuid,
            '11500000-0000-0000-0000-000000000002'::uuid,
            '11500000-0000-0000-0000-000000000003'::uuid]
    ) #> '{entity,properties}'
  ),
  3,
  'three properties come back from one call -- the whole point of the package');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001')
    #> '{leasing,units_total}',
  to_jsonb(2),
  'A has two units');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001')
    #> '{leasing,units_occupied}',
  to_jsonb(1),
  'one of them occupied. Occupied and total are both reported; the ratio is '
  'not, because by-unit or by-area is an owner decision nobody has taken');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001')
    #> '{leasing,leases_ending_90d}',
  to_jsonb(1),
  'and one lease running out inside 90 days');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001')
    #> '{maintenance,tickets_open}',
  to_jsonb(2),
  'two open tickets on A -- the archived one is not open');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001')
    #> '{maintenance,tickets_overdue}',
  to_jsonb(1),
  'one of them past its due date');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000002')
    #> '{leasing,units_total}',
  to_jsonb(1),
  'B counts only its own unit. Batching is where a group-by mistake would '
  'quietly give every card the whole workspace');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000002')
    #> '{maintenance,tickets_open}',
  to_jsonb(1),
  'and only its own ticket');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000003')
    #> '{leasing,units_total}',
  to_jsonb(0),
  'C has nothing recorded and reports 0 -- the outer join must not turn an '
  'empty property into a null');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000003')
    #> '{leasing,available}',
  to_jsonb(true),
  'while still saying the section is available. Zero and absent are different '
  'answers and must never render the same');

-- ---------------------------------------------------------------------------
-- Agreement with the single-property overview -- the reason the duplicated
-- expressions in the migration are allowed to exist
-- ---------------------------------------------------------------------------

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001') -> 'leasing',
  pg_temp.overview_of('11200000-0000-0000-0000-000000000001',
                      '11500000-0000-0000-0000-000000000001')
    #> '{overview,leasing}',
  'the whole leasing block equals the overview''s, field for field. A card '
  'that disagrees with the screen it links to is worse than a card with no '
  'numbers at all');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000001') -> 'maintenance',
  pg_temp.overview_of('11200000-0000-0000-0000-000000000001',
                      '11500000-0000-0000-0000-000000000001')
    #> '{overview,maintenance}',
  'and so does the whole maintenance block');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000001',
                  '11500000-0000-0000-0000-000000000002') -> 'maintenance',
  pg_temp.overview_of('11200000-0000-0000-0000-000000000001',
                      '11500000-0000-0000-0000-000000000002')
    #> '{overview,maintenance}',
  'for the neighbouring property too -- one matching property could agree by '
  'coincidence, two sharing a workspace could not');

-- ---------------------------------------------------------------------------
-- withheld
-- ---------------------------------------------------------------------------

select is(
  pg_temp.cards(
    '11200000-0000-0000-0000-000000000001',
    array['11500000-0000-0000-0000-000000000001'::uuid,
          '99999999-9999-9999-9999-999999999999'::uuid]
  ) #> '{entity,withheld}',
  jsonb_build_array('99999999-9999-9999-9999-999999999999'),
  'an id that names no property is withheld rather than dropped in silence');

select is(
  pg_temp.cards(
    '11200000-0000-0000-0000-000000000001',
    array['11500000-0000-0000-0000-000000000001'::uuid,
          '11500000-0000-0000-0000-000000000009'::uuid]
  ) #> '{entity,withheld}',
  jsonb_build_array('11500000-0000-0000-0000-000000000009'),
  'so is a property in another workspace -- and it is withheld, not answered');

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000001',
      array['11500000-0000-0000-0000-000000000009'::uuid,
            '99999999-9999-9999-9999-999999999999'::uuid]
    ) #> '{entity,withheld}'
  ),
  2,
  'both land in the same list with no reason attached. Splitting "does not '
  'exist" from "you may not see it" would answer the existence question for '
  'someone the entity scope says may not ask it');

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000001',
      array['11500000-0000-0000-0000-000000000001'::uuid,
            '11500000-0000-0000-0000-000000000009'::uuid]
    ) #> '{entity,properties}'
  ),
  1,
  'and the foreign property produces no card');

-- ---------------------------------------------------------------------------
-- Per-section permission
-- ---------------------------------------------------------------------------

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000002',
                  '11500000-0000-0000-0000-000000000001')
    #> '{leasing,available}',
  to_jsonb(true),
  'the viewer holds lease.read, so the leasing block is there');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000002',
                  '11500000-0000-0000-0000-000000000001')
    #> '{maintenance,available}',
  to_jsonb(false),
  'and does not hold maintenance.read, so that block is not');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000002',
                  '11500000-0000-0000-0000-000000000001')
    #>> '{maintenance,permission}',
  'maintenance.read',
  'named, so the UI can say which permission is missing instead of guessing');

select ok(
  not (pg_temp.card_of('11200000-0000-0000-0000-000000000002',
                       '11500000-0000-0000-0000-000000000001')
       -> 'maintenance' ? 'tickets_open'),
  'the withheld section carries NO numbers. A zero here would read as "nothing '
  'to do" on a card belonging to someone who simply may not look');

select is(
  pg_temp.card_of('11200000-0000-0000-0000-000000000002',
                  '11500000-0000-0000-0000-000000000001')
    #> '{leasing,units_total}',
  to_jsonb(2),
  'while the section it may read carries the same numbers the admin sees');

-- ---------------------------------------------------------------------------
-- A stranger
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000003',
      array['11500000-0000-0000-0000-000000000001'::uuid,
            '11500000-0000-0000-0000-000000000002'::uuid]
    ) #> '{entity,properties}'
  ),
  0,
  'a non-member gets no cards');

select is(
  jsonb_array_length(
    pg_temp.cards(
      '11200000-0000-0000-0000-000000000003',
      array['11500000-0000-0000-0000-000000000001'::uuid,
            '11500000-0000-0000-0000-000000000002'::uuid]
    ) #> '{entity,withheld}'
  ),
  2,
  'everything they asked for is withheld -- which is the same answer they get '
  'for ids that do not exist, and tells them nothing either way');

-- ---------------------------------------------------------------------------
-- Freshness
-- ---------------------------------------------------------------------------

select ok(
  (pg_temp.cards('11200000-0000-0000-0000-000000000001',
                 array['11500000-0000-0000-0000-000000000001'::uuid])
   #>> '{entity,as_of}')::timestamptz
  between now() - interval '1 minute' and now() + interval '1 minute',
  'as_of travels with the payload, so a card can state its freshness instead '
  'of implying it is live');

select * from finish();
rollback;
