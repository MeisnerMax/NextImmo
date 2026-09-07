begin;

create extension if not exists pgtap with schema extensions;

-- FINANCE-COST-TYPES-01.
--
-- One assertion carries this package, and it is a round trip rather than a
-- field check: **create an account, read it back, and change it using only
-- what the read returned.**
--
-- That sequence was impossible until now. `update_finance_account` requires
-- `p_expected_version` with no default, and `cost_allocation_rules` — the only
-- read that lists a workspace's accounts — did not return the version, so an
-- account a client had not itself just created could not be edited from that
-- list. (The number was obtainable by other routes: the create response and
-- the version_conflict payload both carry it. An earlier draft of this
-- description claimed otherwise and was wrong.) A test that only asserted
-- "the payload has a version key" would pass on a key holding null, or the
-- nested rule's version, or a constant; the round trip is what proves the
-- value is the one the command accepts.
--
-- The negative counterpart matters as much: a version that is *not* the one
-- the read returned must be refused. Without it the round trip would also pass
-- against a command that ignored the argument.

select plan(13);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('74200000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'types-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('74200000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'types-analyst@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('74100000-0000-0000-0000-000000000001', 'types', 'Types');
select private.seed_workspace_role_catalog('74100000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select gen_random_uuid(), '74100000-0000-0000-0000-000000000001',
       pairing.user_id, role.id, 'active'
from (values
  ('74200000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('74200000-0000-0000-0000-000000000002'::uuid, 'analyst')
) as pairing(user_id, role_key)
join public.roles as role
  on role.workspace_id = '74100000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

create or replace function pg_temp.as_user(
  p_user uuid,
  p_statement text,
  p_aal text default 'aal2'
)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated',
                      'aal', p_aal)::text,
    true
  );
  execute p_statement into v;
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
  return v;
end;
$$;

create or replace function pg_temp.accounts(
  p_user uuid default '74200000-0000-0000-0000-000000000001'
)
returns jsonb
language sql
as $$
  select pg_temp.as_user(
    p_user,
    format(
      $q$select public.cost_allocation_rules(%L::uuid, false)$q$,
      '74100000-0000-0000-0000-000000000001'
    )
  );
$$;

-- The account the round trip is about, as the read returns it.
create or replace function pg_temp.account(p_code text)
returns jsonb
language sql
as $$
  select entry
  from jsonb_array_elements(pg_temp.accounts() -> 'entity' -> 'accounts')
    as entry
  where entry ->> 'code' = p_code;
$$;

-- ---------------------------------------------------------------------------
-- A workspace with no accounts says so, and can leave that state
-- ---------------------------------------------------------------------------

select is(
  pg_temp.accounts() -> 'entity' ->> 'total_count',
  '0',
  'a fresh workspace has no cost types at all -- which is the state the '
  '"Umlagefähigkeit" surface used to open in, with no way out of it from '
  'inside the application');

select is(
  pg_temp.as_user('74200000-0000-0000-0000-000000000001',
    format(
      $q$select public.create_finance_account(
        %L::uuid, '4300', 'Hausmeister', 'expense', %L::uuid, %L::uuid,
        null, 'Test')$q$,
      '74100000-0000-0000-0000-000000000001',
      gen_random_uuid(), gen_random_uuid()))
    -> 'ok',
  'true'::jsonb,
  'and a cost type can be created');

select is(
  pg_temp.accounts() -> 'entity' ->> 'total_count',
  '1',
  'after which the read lists it');

select is(
  pg_temp.account('4300') ->> 'name',
  'Hausmeister',
  'by name');

select is(
  pg_temp.account('4300') -> 'rule',
  'null'::jsonb,
  'and unclassified, because creating a cost type does not decide whether it '
  'may be passed on to tenants');

-- ---------------------------------------------------------------------------
-- The round trip: change an account using only what the read returned
-- ---------------------------------------------------------------------------

select is(
  (pg_temp.account('4300') ->> 'version')::bigint,
  1::bigint,
  'the read returns the account version -- the field whose absence meant an '
  'account could not be edited from the list that shows it. Not, as an '
  'earlier draft claimed, that the number was unobtainable: the create '
  'response and the version_conflict payload both carry it');

select is(
  pg_temp.as_user('74200000-0000-0000-0000-000000000001',
    format(
      $q$select public.update_finance_account(
        %L::uuid, %L::uuid, %s::bigint, %L::uuid, %L::uuid,
        'Hausmeisterdienst', null, false, null, 'Test')$q$,
      '74100000-0000-0000-0000-000000000001',
      pg_temp.account('4300') ->> 'finance_account_id',
      pg_temp.account('4300') ->> 'version',
      gen_random_uuid(), gen_random_uuid()))
    -> 'ok',
  'true'::jsonb,
  'and the command accepts exactly that version -- the round trip the package '
  'exists to make possible');

select is(
  pg_temp.account('4300') ->> 'name',
  'Hausmeisterdienst',
  'the change is visible in the same read');

select is(
  (pg_temp.account('4300') ->> 'version')::bigint,
  2::bigint,
  'and the version has moved with it');

-- The counterpart. Without it the round trip above would also pass against a
-- command that ignored the argument entirely.
select is(
  pg_temp.as_user('74200000-0000-0000-0000-000000000001',
    format(
      $q$select public.update_finance_account(
        %L::uuid, %L::uuid, 1::bigint, %L::uuid, %L::uuid,
        'Zu spät', null, false, null, 'Test')$q$,
      '74100000-0000-0000-0000-000000000001',
      pg_temp.account('4300') ->> 'finance_account_id',
      gen_random_uuid(), gen_random_uuid()))
    -> 'error' ->> 'code',
  'version_conflict',
  'while the version the read returned *before* that change is refused, so the '
  'number is load-bearing rather than decorative');

-- ---------------------------------------------------------------------------
-- The parent, and who may write
-- ---------------------------------------------------------------------------

select is(
  pg_temp.account('4300') -> 'parent_account_id',
  'null'::jsonb,
  'the read carries the parent as well, so a client can render the tree it '
  'is told about rather than inventing one');

-- Both halves of the sentence, because only one of them was ever run. The
-- read has to succeed for the refusal below to mean "may not create" rather
-- than "may not see".
select is(
  pg_temp.accounts('74200000-0000-0000-0000-000000000002') -> 'ok',
  'true'::jsonb,
  'the analyst may read the cost types');

select is(
  pg_temp.as_user('74200000-0000-0000-0000-000000000002',
    format(
      $q$select public.create_finance_account(
        %L::uuid, '4400', 'Versicherung', 'expense', %L::uuid, %L::uuid,
        null, 'Test')$q$,
      '74100000-0000-0000-0000-000000000001',
      gen_random_uuid(), gen_random_uuid()))
    -> 'error' ->> 'code',
  'forbidden',
  'and may not create one');

select * from finish();
rollback;
