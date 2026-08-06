-- Run with `psql -v ON_ERROR_STOP=1 -f supabase/seed.sql` for manual local
-- bootstrapping. The CLI's own migration-down/reset seeding path sends this
-- file as raw SQL (not through psql), so it cannot contain psql meta-commands
-- like `\set` — the previous first line broke exactly that path with a
-- syntax error, never caught because CI always resets with --no-seed.
--
-- The fixed identifiers below are RFC-4122 conformant (version nibble 4,
-- variant nibble 8) rather than zero-padded placeholders. This matters beyond
-- cosmetics: the P2-X01-AP4 property cutover derives every target property id
-- as a UUIDv5 in the namespace of the workspace id, and a malformed namespace
-- is rejected by the dry-run contract, which would block the data migration.

do $$
declare
  v_user_id uuid;
  v_workspace_id uuid;
  v_role_id uuid;
begin
  select id
    into v_user_id
    from auth.users
   where lower(email) = lower('admin@neximmo.com')
   limit 1;

  if v_user_id is null then
    v_user_id := 'a7000000-0000-4000-8000-000000000001';
    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) values (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'admin@neximmo.com',
      null,
      now(),
      '',
      '',
      '',
      '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    );
  end if;

  -- auth.identities.email is a generated column
  -- (lower(identity_data ->> 'email')) and must not be written explicitly.
  insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    created_at,
    updated_at
  ) values (
    'a7100000-0000-4000-8000-000000000001',
    'admin@neximmo.com',
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', 'admin@neximmo.com',
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now()
  )
  on conflict (provider_id, provider) do update
    set user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = now();

  select id
    into v_workspace_id
    from public.workspaces
   where key = 'neximmo'
   limit 1;

  if v_workspace_id is null then
    v_workspace_id := 'a1000000-0000-4000-8000-000000000001';
    insert into public.workspaces (id, key, name)
    values (v_workspace_id, 'neximmo', 'NexImmo');
  end if;

  select id
    into v_role_id
    from public.roles
   where workspace_id = v_workspace_id
     and key = 'admin'
   limit 1;

  if v_role_id is null then
    v_role_id := 'a2000000-0000-4000-8000-000000000001';
    insert into public.roles (id, workspace_id, key, name)
    values (v_role_id, v_workspace_id, 'admin', 'Admin');
  end if;

  -- Permission catalogue. Migrations intentionally do not seed public.permissions
  -- (pgTAP fixtures insert their own rows and would collide on permissions_key_unique),
  -- so the local bootstrap provides the keys enforced by RLS/RPCs plus the
  -- reporting capability gated in the Flutter navigation.
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

  insert into public.user_profiles (user_id, display_name)
  values (v_user_id, 'NexImmo Admin')
  on conflict (user_id) do update
    set display_name = excluded.display_name;

  insert into public.role_permissions (workspace_id, role_id, permission_id)
  select v_workspace_id, v_role_id, permission.id
    from public.permissions permission
  on conflict do nothing;

  insert into public.memberships (
    id,
    workspace_id,
    user_id,
    role_id,
    status
  ) values (
    'a4000000-0000-4000-8000-000000000001',
    v_workspace_id,
    v_user_id,
    v_role_id,
    'active'
  )
  on conflict (workspace_id, user_id) do update
    set role_id = excluded.role_id,
        status = 'active',
        updated_at = now();
end
$$;
