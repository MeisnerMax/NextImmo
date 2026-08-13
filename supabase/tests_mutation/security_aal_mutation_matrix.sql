-- SECURITY-AAL-ENFORCEMENT-01 -- mutation matrix.
--
-- A gate that never turns red proves nothing. Each block below breaks exactly
-- one security invariant inside a transaction, evaluates the gate that is
-- supposed to notice, prints TRIPPED or NOT-TRIPPED, and rolls the mutation
-- back. tool/test_security_aal_mutation_matrix.ps1 fails the run if any block
-- reports NOT-TRIPPED.
--
-- The mutations run against the real schema rather than a copy, so a gate that
-- only works on a hand-built fixture cannot pass here.

\pset format unaligned
\pset tuples_only on

\echo '--- MUT-1: strip the assurance predicate from the central permission helper'
begin;
create or replace function private.has_workspace_permission(target_workspace_id uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships as membership
    join public.role_permissions as role_permission
      on role_permission.workspace_id = membership.workspace_id
      and role_permission.role_id = membership.role_id
    join public.permissions as permission
      on permission.id = role_permission.permission_id
    where membership.workspace_id = target_workspace_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'::public.membership_status
      and permission.key = permission_key
  );
$$;
select 'MUT-1 ' || case when (
  select pg_get_functiondef(f.oid) ~ 'private\.is_aal2'
  from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'private' and f.proname = 'has_workspace_permission'
) then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-21 helper presence)';
rollback;

\echo '--- MUT-2: strip aal2 from one command gate'
begin;
create or replace function private.platform_command_gate(p_workspace_id uuid, p_mutation_id uuid, p_correlation_id uuid, p_reason text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;
  return null;
end;
$$;
select 'MUT-2 ' || case when (
  select count(*) from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'private' and f.prokind = 'f'
    and f.proname like '%command_gate'
    and pg_get_functiondef(f.oid) !~ 'aal2'
) = 0 then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-21 gate coverage)';
rollback;

\echo '--- MUT-3: re-point a policy at a permissive expression'
begin;
drop policy notifications_select_own_or_read on public.notifications;
create policy notifications_select_own_or_read
  on public.notifications
  for select
  to authenticated
  using (recipient_user_id = (select auth.uid()));
select 'MUT-3 ' || case when (
  select count(*)
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage', 'realtime')
    and not exists (
      select 1 from pg_depend d join pg_proc g on g.oid = d.refobjid
      where d.classid = 'pg_policy'::regclass and d.objid = p.oid
        and d.refclassid = 'pg_proc'::regclass
        and g.proname in ('is_aal2', 'has_workspace_permission', 'has_scoped_entity_permission')
    )
    and p.polname not in ('user_profiles_select_own')
) = 0 then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-22 policy binding)';
rollback;

\echo '--- MUT-4: put the existence probe back in front of authorization'
begin;
create or replace function public.operations_signals(p_workspace_id uuid, p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_signals jsonb;
begin
  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object('ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found'));
  end if;
  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object('ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Operations signals are not permitted'));
  end if;
  return jsonb_build_object('ok', true, 'entity', '[]'::jsonb);
end;
$$;
select 'MUT-4 ' || case when (
  select strpos(pg_get_functiondef(f.oid), 'has_workspace_permission')
       < strpos(pg_get_functiondef(f.oid), 'leasing_property_in_workspace')
  from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'public' and f.proname = 'operations_signals'
) then 'NOT-TRIPPED' else 'TRIPPED' end || '  (027 E1/E2 ordering)';
rollback;

\echo '--- MUT-5: add an unguarded business RPC (the RPC #66 case)'
begin;
create function public.mutation_probe_unguarded_rpc(p_workspace_id uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.properties set name = p_name where workspace_id = p_workspace_id;
  return jsonb_build_object('ok', true);
end;
$$;
select 'MUT-5 ' || case when (
  select count(*) from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'public' and f.prokind = 'f' and f.prosecdef
    and pg_get_functiondef(f.oid) !~
      'private\.(has_workspace_permission|has_scoped_entity_permission|is_aal2|[a-z_]+_command_gate)'
) = 0 then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-21 new RPC)';
rollback;

\echo '--- MUT-6: add an unclassified policy (the new-policy case)'
begin;
create policy mutation_probe_unclassified
  on public.tasks
  for select
  to authenticated
  using (created_by = (select auth.uid()));
select 'MUT-6a ' || case when (
  select count(*)
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage', 'realtime')
    and not exists (
      select 1 from pg_depend d join pg_proc g on g.oid = d.refobjid
      where d.classid = 'pg_policy'::regclass and d.objid = p.oid
        and d.refclassid = 'pg_proc'::regclass
        and g.proname in ('is_aal2', 'has_workspace_permission', 'has_scoped_entity_permission')
    )
    and p.polname not in ('user_profiles_select_own')
) = 0 then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-22 policy binding)';
select 'MUT-6b ' || case when (
  select count(*)
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage', 'realtime')
) = 41 then 'NOT-TRIPPED' else 'TRIPPED' end || '  (SR-22 inventory count)';
rollback;
