-- PROPERTY-DATA-02: property creation.
--
-- The property contract has carried list/getById/update since P1-004.
-- Archiving and restoring already exist as the audited tombstone path of
-- `update_property` (DEBT-012: status -> archived sets deleted_at, status ->
-- active restores it), so this migration adds the one verb that was actually
-- missing: creating a property.
--
-- Deliberately NOT added: a hard delete. The lifecycle stays the restorable,
-- append-only-audited tombstone.
--
-- Shape follows the established command RPCs (create_unit, create_document):
-- authentication, AAL2 (DEC-025), workspace permission, field validation,
-- idempotency through mutation_receipts, an append-only audit event and the
-- canonical entity in the result. Unlike update_property there is no
-- entity-scope check and no expected_version -- the row does not exist yet, so
-- the workspace-wide `property.create` capability is the authority.

-- 1. Catalog: property.create joins the canonical permission catalog. The
--    client mirrors this key in Permission.serverCatalog (rbac.dart), pinned
--    by permission_catalog_parity_test.dart.
--
--    Seeded exclusively through the PERMISSION-CATALOG-02 seeder, never as a
--    bare INSERT: an empty database must stay empty. Every pgTAP suite builds
--    its own catalog per file, and an unconditional row here would leak into
--    all of them (and into the RLS/AAL fixtures that count catalog rows).
create or replace function private.ensure_permission_catalog()
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
    ('reporting.generate', 'Reporting Generate')
  on conflict (key) do nothing;
end;
$$;

alter function private.ensure_permission_catalog() owner to postgres;
revoke all on function private.ensure_permission_catalog()
  from public, anon, authenticated;

-- 2. Role bundles. Opening a new asset is a portfolio decision, so
--    `property.create` follows `admin` (whole catalog) and `manager` only.
--    `analyst` and `operations` keep `property.update` -- they maintain
--    existing assets -- and `viewer` still reads. The PERMISSION-CATALOG-02
--    seeder is extended in place rather than shadowed by a second function, so
--    workspaces created later get the identical bundle from one source.
create or replace function private.seed_workspace_role_catalog(p_workspace_id uuid)
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
        'property.read', 'property.create', 'property.update',
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

-- Workspaces that exist at migration time gain the new key and the one new
-- grant. Guarded on an existing workspace so an empty database (local CI
-- reset, every pgTAP file) stays untouched -- the same rule
-- PERMISSION-CATALOG-02 follows. Hand-made roles are safe: only `admin` and
-- `manager` are targeted and existing rows are never modified.
do $$
begin
  if exists (select 1 from public.workspaces) then
    perform private.ensure_permission_catalog();

    insert into public.role_permissions (workspace_id, role_id, permission_id)
    select role.workspace_id, role.id, permission.id
    from public.roles as role
    cross join public.permissions as permission
    where permission.key = 'property.create'
      and role.key in ('admin', 'manager')
    on conflict do nothing;
  end if;
end;
$$;

-- 3. create_property.
create function public.create_property(
  p_workspace_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_name text,
  p_address_line1 text,
  p_zip text,
  p_city text,
  p_country text,
  p_property_type text,
  p_address_line2 text default null,
  p_units integer default 0,
  p_sqft numeric default null,
  p_year_built smallint default null,
  p_notes text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_property public.properties%rowtype;
  v_new_values jsonb;
  v_role_key text;
  v_now timestamptz;
  v_name text := btrim(coalesce(p_name, ''));
  v_address_line1 text := btrim(coalesce(p_address_line1, ''));
  v_address_line2 text := nullif(btrim(coalesce(p_address_line2, '')), '');
  v_zip text := btrim(coalesce(p_zip, ''));
  v_city text := btrim(coalesce(p_city, ''));
  v_country text := lower(btrim(coalesce(p_country, '')));
  v_property_type text := lower(btrim(coalesce(p_property_type, '')));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_units integer := coalesce(p_units, 0);
begin
  if v_actor_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for property creation'
      )
    );
  end if;

  if p_workspace_id is null
     or p_mutation_id is null
     or p_correlation_id is null then
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

  if not private.has_workspace_permission(p_workspace_id, 'property.create') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Property creation is not permitted'
      )
    );
  end if;

  -- Field validation mirrors the table constraints so the client receives a
  -- typed failure naming the offending field instead of a raw constraint
  -- violation.
  if char_length(v_name) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Name is required',
        'field', 'name'
      )
    );
  end if;

  if char_length(v_address_line1) not between 1 and 300 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Address is required',
        'field', 'address_line1'
      )
    );
  end if;

  if v_address_line2 is not null
     and char_length(v_address_line2) not between 1 and 300 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Address line 2 is too long',
        'field', 'address_line2'
      )
    );
  end if;

  if char_length(v_zip) not between 1 and 30 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Postal code is required',
        'field', 'zip'
      )
    );
  end if;

  if char_length(v_city) not between 1 and 200 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'City is required',
        'field', 'city'
      )
    );
  end if;

  if char_length(v_country) not between 2 and 100
     or v_country !~ '^[a-z0-9]+([._-][a-z0-9]+)*$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Country must be a normalized code',
        'field', 'country'
      )
    );
  end if;

  if char_length(v_property_type) not between 1 and 100
     or v_property_type !~ '^[a-z0-9]+([._-][a-z0-9]+)*$' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Property type must be a normalized code',
        'field', 'property_type'
      )
    );
  end if;

  if v_units < 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Units must be a non-negative integer',
        'field', 'units'
      )
    );
  end if;

  if p_sqft is not null and (p_sqft <= 0 or p_sqft = 'NaN'::numeric) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Square feet must be null or positive',
        'field', 'sqft'
      )
    );
  end if;

  if p_year_built is not null and p_year_built not between 1000 and 2100 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Year built is outside the supported range',
        'field', 'year_built'
      )
    );
  end if;

  if v_notes is not null and char_length(v_notes) > 10000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Notes are too long',
        'field', 'notes'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'create_property',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'name', v_name,
        'address_line1', v_address_line1,
        'address_line2', v_address_line2,
        'zip', v_zip,
        'city', v_city,
        'country', v_country,
        'property_type', v_property_type,
        'units', v_units,
        'sqft', p_sqft,
        'year_built', p_year_built,
        'notes', v_notes,
        'correlation_id', p_correlation_id,
        'reason', p_reason
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  insert into public.mutation_receipts (
    workspace_id, mutation_id, request_hash, status, created_by, updated_by
  ) values (
    p_workspace_id, p_mutation_id, v_request_hash, 'pending',
    v_actor_id, v_actor_id
  )
  on conflict (workspace_id, mutation_id) do nothing
  returning id into v_inserted_receipt_id;

  if v_inserted_receipt_id is null then
    select receipt.*
    into v_receipt
    from public.mutation_receipts as receipt
    where receipt.workspace_id = p_workspace_id
      and receipt.mutation_id = p_mutation_id
    for update;

    if v_receipt.request_hash is distinct from v_request_hash then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'mutation_conflict',
          'message', 'Mutation id was used with a different command'
        )
      );
    end if;

    -- A retried creation replays the audited result instead of inserting a
    -- second property.
    if v_receipt.status = 'succeeded' then
      select audit.new_values
      into v_new_values
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'property';

      if v_new_values is null then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'infrastructure_failure',
            'message', 'Successful mutation result is unavailable'
          )
        );
      end if;

      return jsonb_build_object('ok', true, 'property', v_new_values);
    end if;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'in_progress', 'message', 'Mutation is already in progress'
      )
    );
  end if;

  v_now := now();

  -- A new property starts as a draft: it is not a productive asset yet, and
  -- promoting it to active is an explicit, audited update.
  insert into public.properties (
    workspace_id, name, address_line1, address_line2, zip, city, country,
    property_type, units, sqft, year_built, notes, status,
    created_at, updated_at, created_by, updated_by
  ) values (
    p_workspace_id, v_name, v_address_line1, v_address_line2, v_zip, v_city,
    v_country, v_property_type, v_units, p_sqft, p_year_built, v_notes,
    'draft', v_now, v_now, v_actor_id, v_actor_id
  )
  returning * into v_property;

  v_new_values := jsonb_build_object(
    'id', v_property.id,
    'workspace_id', v_property.workspace_id,
    'name', v_property.name,
    'address_line1', v_property.address_line1,
    'address_line2', v_property.address_line2,
    'zip', v_property.zip,
    'city', v_property.city,
    'country', v_property.country,
    'property_type', v_property.property_type,
    'units', v_property.units,
    'sqft', v_property.sqft,
    'year_built', v_property.year_built,
    'notes', v_property.notes,
    'status', v_property.status,
    'created_at', v_property.created_at,
    'updated_at', v_property.updated_at,
    'created_by', v_property.created_by,
    'updated_by', v_property.updated_by,
    'version', v_property.version,
    'deleted_at', v_property.deleted_at
  );

  select membership_role.key
  into v_role_key
  from public.memberships as membership
  join public.roles as membership_role
    on membership_role.id = membership.role_id
  where membership.workspace_id = p_workspace_id
    and membership.user_id = v_actor_id
    and membership.status = 'active'
  limit 1;

  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, role_key, scope_snapshot, action,
    entity_type, entity_id, source, correlation_id, mutation_id, reason,
    old_values, new_values, created_by, updated_by
  ) values (
    p_workspace_id, 'user', v_actor_id, v_role_key,
    jsonb_build_object('workspace_id', p_workspace_id),
    'property.create', 'property', v_property.id, 'rpc',
    p_correlation_id, p_mutation_id, p_reason,
    null, v_new_values, v_actor_id, v_actor_id
  );

  update public.mutation_receipts
  set
    status = 'succeeded',
    result_entity_type = 'property',
    result_entity_id = v_property.id,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = version + 1
  where id = v_inserted_receipt_id;

  return jsonb_build_object('ok', true, 'property', v_new_values);
end;
$$;

alter function public.create_property(
  uuid, uuid, uuid, text, text, text, text, text, text, text, integer,
  numeric, smallint, text, text
) owner to postgres;

revoke all on function public.create_property(
  uuid, uuid, uuid, text, text, text, text, text, text, text, integer,
  numeric, smallint, text, text
) from public, anon, authenticated;

grant execute on function public.create_property(
  uuid, uuid, uuid, text, text, text, text, text, text, text, integer,
  numeric, smallint, text, text
) to authenticated;
