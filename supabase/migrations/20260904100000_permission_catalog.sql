-- PERMISSION-CATALOG-02: one canonical permission catalog, and least-privilege
-- role bundles for the five spec'd roles.
--
-- Until now no migration seeded permissions, roles or role_permissions: the
-- catalog lived in the manual local bootstrap (supabase/seed.sql) and staging
-- carried hand-made fixtures — outside `admin`, nothing was productively
-- granted, which kept the task/notification/search surface admin-only.
--
-- Two deliverables:
--
--   1. private.ensure_permission_catalog — idempotently seeds the 29 canonical
--      permission keys. These are exactly the keys the RLS policies and RPC
--      gates reach through private.has_workspace_permission (28 keys), plus
--      `reporting.generate`, the documented navigation-only gate awaiting its
--      server surface. The client mirrors this list key for key
--      (lib/core/security/rbac.dart `Permission.serverCatalog`, pinned by
--      permission_catalog_parity_test.dart; the server side is pinned by
--      pgTAP 030).
--
--   2. private.seed_workspace_role_catalog(workspace) — idempotently creates
--      the five roles the enterprise target architecture fixes (`admin`,
--      `manager`, `analyst`, `operations`, `viewer`) and grants each its
--      least-privilege bundle. Existing rows are never modified or removed:
--      the seeder only fills gaps (on conflict do nothing), so a workspace
--      with a hand-made admin role keeps it and merely gains the missing
--      grants.
--
-- The migration itself seeds every workspace that exists at migration time —
-- an empty database (local CI resets) is a no-op, the staging project gets
-- its real seed through the authorized deploy workflow. Workspaces created
-- later are seeded by operations through the same helper. Deliberately NOT an
-- AFTER INSERT trigger on workspaces: every pgTAP suite builds its own
-- catalog per file, and an automatic global insert would collide with all of
-- them — the helper keeps production seeding and test isolation compatible.
--
-- Bundle semantics map the client RBAC bundles (rbac.dart) onto the server
-- vocabulary:
--   admin       the full catalog (unchanged behaviour).
--   manager     every operative capability incl. approvals; NOT
--               security.manage, NOT notification.read/manage (workspace-wide
--               notification oversight and hand fan-out stay admin-only — the
--               emitter is server-side since NOTIFICATION-EMITTER-01 and the
--               own feed needs no permission at all), NOT search.reindex.
--   analyst     builds (valuation.manage, task.manage, document.manage,
--               import.manage) but approves nothing and manages no
--               operations.
--   operations  runs maintenance and tasks (maintenance.manage, task.manage,
--               document.manage) but approves nothing and imports nothing.
--   viewer      reads only: no *.manage, no *.approve, no search.read (name
--               resolution degrades to type labels by design).
--
-- No RLS change, no policy change (SR-22 stays 41), no new public function
-- (SR-20 stays 66), no AAL change, no grant to any client role.

create function private.ensure_permission_catalog()
returns void
language sql
set search_path = ''
as $$
  insert into public.permissions (key, name) values
    ('workspace.read', 'Workspace Read'),
    ('security.manage', 'Security Manage'),
    ('audit.read', 'Audit Read'),
    ('property.read', 'Property Read'),
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
    ('reporting.generate', 'Reporting Generate')
  on conflict (key) do nothing;
$$;

alter function private.ensure_permission_catalog() owner to postgres;
revoke all on function private.ensure_permission_catalog()
  from public, anon, authenticated;

create function private.seed_workspace_role_catalog(p_workspace_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
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
        'property.read', 'property.update',
        'party.read', 'party.manage',
        'document.read', 'document.manage', 'document.verify',
        'task.read', 'task.manage',
        'lease.read', 'lease.manage',
        'valuation.read', 'valuation.manage', 'valuation.approve',
        'maintenance.read', 'maintenance.manage',
        'capex.read', 'capex.manage', 'capex.approve',
        'import.read', 'import.manage',
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
        'lease.read', 'valuation.read', 'reporting.generate')
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
$$;

alter function private.seed_workspace_role_catalog(uuid) owner to postgres;
revoke all on function private.seed_workspace_role_catalog(uuid)
  from public, anon, authenticated;

-- Seed every workspace that exists right now. Locally (empty schema after a
-- reset) this is a no-op; on staging it completes the hand-made state.
do $$
declare
  v_workspace_id uuid;
begin
  for v_workspace_id in select id from public.workspaces loop
    perform private.seed_workspace_role_catalog(v_workspace_id);
  end loop;
end
$$;
