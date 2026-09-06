-- Read-only inventory of the staging workspace (DEC-030, inventory mode).
--
-- Answers one question before anything is written: what can an account on
-- staging actually do today? The suspicion this exists to confirm or refute is
-- that the staging workspace still carries the minimal catalogue it was
-- provisioned with — the read-only census of 2026-08-23 recorded 1 role and 3
-- permissions — because migrations ship `private.seed_workspace_role_catalog`
-- but never call it for a workspace that already exists. If that is still true,
-- the deployed app is functionally hollow no matter how correct the server is,
-- and no amount of seeding business objects would help until it is fixed.
--
-- Writes nothing. Selects only counts and keys — never a name, an address, an
-- email or any other value, because this output lands in a workflow log.

select jsonb_pretty(jsonb_build_object(
  'workspaces', (select count(*) from public.workspaces),
  'workspace_keys', (
    select coalesce(jsonb_agg(w.key order by w.key), '[]'::jsonb)
    from public.workspaces as w
  ),
  'auth_users', (select count(*) from auth.users),
  'memberships_active', (
    select count(*) from public.memberships where status = 'active'
  ),
  'roles', (
    select coalesce(jsonb_agg(r.key order by r.key), '[]'::jsonb)
    from public.roles as r
  ),
  'permissions_total', (select count(*) from public.permissions),
  -- The decisive number: what the roles in this workspace can actually reach.
  'permissions_granted_by_role', (
    select coalesce(jsonb_object_agg(x.role_key, x.n), '{}'::jsonb)
    from (
      select role.key as role_key, count(*) as n
      from public.role_permissions as rp
      join public.roles as role on role.id = rp.role_id
      group by role.key
    ) as x
  ),
  -- Named explicitly because the demo data cannot be created without them.
  'missing_for_demo', (
    select coalesce(jsonb_agg(needed.key order by needed.key), '[]'::jsonb)
    from (values
      ('property.create'), ('property.read'), ('property.update'),
      ('lease.read'), ('lease.manage'),
      ('party.read'), ('party.manage'),
      ('maintenance.read'), ('maintenance.manage'),
      ('finance.read'), ('finance.manage'), ('finance.close')
    ) as needed(key)
    where not exists (
      select 1 from public.permissions as p where p.key = needed.key
    )
  ),
  'business_objects', jsonb_build_object(
    'properties', (select count(*) from public.properties),
    'units', (select count(*) from public.units),
    'leases', (select count(*) from public.leases),
    'parties', (select count(*) from public.parties),
    'maintenance_tickets', (select count(*) from public.maintenance_tickets),
    'finance_ledger_entries', (select count(*) from public.finance_ledger_entries),
    'audit_events', (select count(*) from public.audit_events)
  ),
  -- The golden baseline DEC-030 requires to stay untouched. Reported so a
  -- later run can prove it did.
  'golden_baseline', jsonb_build_object(
    'max_property_version', (select max(version) from public.properties),
    'audit_events', (select count(*) from public.audit_events),
    'storage_objects', (select count(*) from storage.objects)
  )
)) as inventory;
