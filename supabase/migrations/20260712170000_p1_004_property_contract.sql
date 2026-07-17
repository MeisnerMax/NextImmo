create type public.property_status as enum (
  'draft',
  'active',
  'archived'
);

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  name text not null,
  address_line1 text not null,
  address_line2 text,
  zip text not null,
  city text not null,
  country text not null,
  property_type text not null,
  units integer not null default 0,
  sqft numeric,
  year_built smallint,
  notes text,
  status public.property_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  version bigint not null default 1,
  deleted_at timestamptz,
  constraint properties_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint properties_name_check check (char_length(btrim(name)) between 1 and 200),
  constraint properties_address_line1_check check (
    char_length(btrim(address_line1)) between 1 and 300
  ),
  constraint properties_address_line2_check check (
    address_line2 is null or char_length(btrim(address_line2)) between 1 and 300
  ),
  constraint properties_zip_check check (char_length(btrim(zip)) between 1 and 30),
  constraint properties_city_check check (char_length(btrim(city)) between 1 and 200),
  constraint properties_country_normalized_check check (
    country = lower(btrim(country))
    and char_length(country) between 2 and 100
    and country ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint properties_property_type_normalized_check check (
    property_type = lower(btrim(property_type))
    and char_length(property_type) between 1 and 100
    and property_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint properties_units_check check (units >= 0),
  constraint properties_sqft_check check (
    sqft is null or (sqft > 0 and sqft <> 'NaN'::numeric)
  ),
  constraint properties_year_built_check check (
    year_built is null or year_built between 1000 and 2100
  ),
  constraint properties_notes_check check (
    notes is null or char_length(notes) <= 10000
  ),
  constraint properties_version_check check (version >= 1),
  constraint properties_archived_deleted_at_check check (
    (status = 'archived'::public.property_status) = (deleted_at is not null)
  )
);

create trigger properties_protected_columns
before update on public.properties
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'created_at', 'created_by'
);

alter table public.properties enable row level security;
alter table public.properties force row level security;

create policy properties_select_property_read
on public.properties
for select
to authenticated
using (private.has_workspace_permission(workspace_id, 'property.read'));

revoke all on table public.properties from anon, authenticated;
grant select on table public.properties to authenticated;

create function public.update_property(
  p_workspace_id uuid,
  p_property_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_changes jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_allowed_keys constant text[] := array[
    'name', 'address_line1', 'address_line2', 'zip', 'city', 'country',
    'property_type', 'units', 'sqft', 'year_built', 'notes', 'status'
  ];
  v_unknown_keys text[];
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_old public.properties%rowtype;
  v_new public.properties%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_role_key text;
  v_now timestamptz;
begin
  if v_actor_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null or p_property_id is null or p_mutation_id is null
     or p_correlation_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Command identifiers and expected version are required'
      )
    );
  end if;

  if p_reason is not null
     and char_length(btrim(p_reason)) not between 1 and 2000 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Reason must contain at most 2000 characters', 'field', 'reason'
      )
    );
  end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object' or p_changes = '{}'::jsonb then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Changes must be a non-empty object', 'field', 'changes'
      )
    );
  end if;

  select array_agg(change_key order by change_key)
  into v_unknown_keys
  from jsonb_object_keys(p_changes) as change(change_key)
  where not (change_key = any (v_allowed_keys));

  if v_unknown_keys is not null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Changes contain unsupported fields',
        'fields', to_jsonb(v_unknown_keys)
      )
    );
  end if;

  if (p_changes ? 'name' and (
        jsonb_typeof(p_changes -> 'name') <> 'string'
        or char_length(btrim(p_changes ->> 'name')) not between 1 and 200
      ))
     or (p_changes ? 'address_line1' and (
        jsonb_typeof(p_changes -> 'address_line1') <> 'string'
        or char_length(btrim(p_changes ->> 'address_line1')) not between 1 and 300
      ))
     or (p_changes ? 'address_line2' and not (
        jsonb_typeof(p_changes -> 'address_line2') = 'null'
        or (
          jsonb_typeof(p_changes -> 'address_line2') = 'string'
          and char_length(btrim(p_changes ->> 'address_line2')) between 1 and 300
        )
      ))
     or (p_changes ? 'zip' and (
        jsonb_typeof(p_changes -> 'zip') <> 'string'
        or char_length(btrim(p_changes ->> 'zip')) not between 1 and 30
      ))
     or (p_changes ? 'city' and (
        jsonb_typeof(p_changes -> 'city') <> 'string'
        or char_length(btrim(p_changes ->> 'city')) not between 1 and 200
      ))
     or (p_changes ? 'notes' and not (
        jsonb_typeof(p_changes -> 'notes') = 'null'
        or (
          jsonb_typeof(p_changes -> 'notes') = 'string'
          and char_length(p_changes ->> 'notes') <= 10000
        )
      )) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Invalid text field value'
      )
    );
  end if;

  if (p_changes ? 'country' and (
        jsonb_typeof(p_changes -> 'country') <> 'string'
        or p_changes ->> 'country' <> lower(btrim(p_changes ->> 'country'))
        or char_length(p_changes ->> 'country') not between 2 and 100
        or p_changes ->> 'country' !~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
      ))
     or (p_changes ? 'property_type' and (
        jsonb_typeof(p_changes -> 'property_type') <> 'string'
        or p_changes ->> 'property_type' <> lower(btrim(p_changes ->> 'property_type'))
        or char_length(p_changes ->> 'property_type') not between 1 and 100
        or p_changes ->> 'property_type' !~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
      )) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Country and property type must be normalized'
      )
    );
  end if;

  if p_changes ? 'units' and jsonb_typeof(p_changes -> 'units') <> 'number' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Units must be a non-negative integer', 'field', 'units'
      )
    );
  end if;

  if p_changes ? 'units' and (
       (p_changes ->> 'units')::numeric <> trunc((p_changes ->> 'units')::numeric)
       or (p_changes ->> 'units')::numeric not between 0 and 2147483647
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Units must be a non-negative integer', 'field', 'units'
      )
    );
  end if;

  if p_changes ? 'sqft'
     and jsonb_typeof(p_changes -> 'sqft') not in ('null', 'number') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Square feet must be null or positive', 'field', 'sqft'
      )
    );
  end if;

  if p_changes ? 'sqft'
     and jsonb_typeof(p_changes -> 'sqft') = 'number'
     and (p_changes ->> 'sqft')::numeric <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Square feet must be null or positive', 'field', 'sqft'
      )
    );
  end if;

  if p_changes ? 'year_built'
     and jsonb_typeof(p_changes -> 'year_built') not in ('null', 'number') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Year built is outside the supported range', 'field', 'year_built'
      )
    );
  end if;

  if p_changes ? 'year_built'
     and jsonb_typeof(p_changes -> 'year_built') = 'number'
     and (
       (p_changes ->> 'year_built')::numeric <> trunc((p_changes ->> 'year_built')::numeric)
       or (p_changes ->> 'year_built')::numeric not between 1000 and 2100
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Year built is outside the supported range', 'field', 'year_built'
      )
    );
  end if;

  if p_changes ? 'status' and (
       jsonb_typeof(p_changes -> 'status') <> 'string'
       or p_changes ->> 'status' not in ('draft', 'active', 'archived')
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Invalid property status', 'field', 'status'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'property.update')
     or not private.has_workspace_permission(p_workspace_id, 'property.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Property update is not permitted')
    );
  end if;

  select role.key
  into v_role_key
  from public.memberships as membership
  join public.roles as role
    on role.workspace_id = membership.workspace_id
    and role.id = membership.role_id
  where membership.workspace_id = p_workspace_id
    and membership.user_id = v_actor_id
    and membership.status = 'active'::public.membership_status;

  select property.*
  into v_old
  from public.properties as property
  where property.id = p_property_id
    and property.workspace_id = p_workspace_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'expected_version', p_expected_version,
        'correlation_id', p_correlation_id,
        'reason', p_reason,
        'changes', p_changes
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  insert into public.mutation_receipts (
    workspace_id, mutation_id, request_hash, status, created_by, updated_by
  ) values (
    p_workspace_id, p_mutation_id, v_request_hash, 'pending', v_actor_id, v_actor_id
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
          'code', 'mutation_conflict', 'message', 'Mutation id was used with a different command'
        )
      );
    end if;

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
            'code', 'infrastructure_failure', 'message', 'Successful mutation result is unavailable'
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

  if v_old.version <> p_expected_version then
    delete from public.mutation_receipts
    where id = v_inserted_receipt_id;

    v_old_values := jsonb_build_object(
      'id', v_old.id,
      'workspace_id', v_old.workspace_id,
      'name', v_old.name,
      'address_line1', v_old.address_line1,
      'address_line2', v_old.address_line2,
      'zip', v_old.zip,
      'city', v_old.city,
      'country', v_old.country,
      'property_type', v_old.property_type,
      'units', v_old.units,
      'sqft', v_old.sqft,
      'year_built', v_old.year_built,
      'notes', v_old.notes,
      'status', v_old.status,
      'created_at', v_old.created_at,
      'updated_at', v_old.updated_at,
      'created_by', v_old.created_by,
      'updated_by', v_old.updated_by,
      'version', v_old.version,
      'deleted_at', v_old.deleted_at
    );

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Property version is stale',
        'expected_version', p_expected_version,
        'actual_version', v_old.version,
        'current_property', v_old_values
      )
    );
  end if;

  v_now := now();

  update public.properties as property
  set
    name = case when p_changes ? 'name' then p_changes ->> 'name' else property.name end,
    address_line1 = case
      when p_changes ? 'address_line1' then p_changes ->> 'address_line1'
      else property.address_line1
    end,
    address_line2 = case
      when p_changes ? 'address_line2' then nullif(p_changes ->> 'address_line2', '')
      else property.address_line2
    end,
    zip = case when p_changes ? 'zip' then p_changes ->> 'zip' else property.zip end,
    city = case when p_changes ? 'city' then p_changes ->> 'city' else property.city end,
    country = case when p_changes ? 'country' then p_changes ->> 'country' else property.country end,
    property_type = case
      when p_changes ? 'property_type' then p_changes ->> 'property_type'
      else property.property_type
    end,
    units = case
      when p_changes ? 'units' then (p_changes ->> 'units')::integer
      else property.units
    end,
    sqft = case
      when p_changes ? 'sqft' then (p_changes ->> 'sqft')::numeric
      else property.sqft
    end,
    year_built = case
      when p_changes ? 'year_built' then (p_changes ->> 'year_built')::smallint
      else property.year_built
    end,
    notes = case
      when p_changes ? 'notes' then nullif(p_changes ->> 'notes', '')
      else property.notes
    end,
    status = case
      when p_changes ? 'status' then (p_changes ->> 'status')::public.property_status
      else property.status
    end,
    deleted_at = case
      when coalesce(p_changes ->> 'status', property.status::text) = 'archived'
        then coalesce(property.deleted_at, v_now)
      else null
    end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = property.version + 1
  where property.id = p_property_id
    and property.workspace_id = p_workspace_id
  returning property.* into v_new;

  v_old_values := jsonb_build_object(
    'id', v_old.id,
    'workspace_id', v_old.workspace_id,
    'name', v_old.name,
    'address_line1', v_old.address_line1,
    'address_line2', v_old.address_line2,
    'zip', v_old.zip,
    'city', v_old.city,
    'country', v_old.country,
    'property_type', v_old.property_type,
    'units', v_old.units,
    'sqft', v_old.sqft,
    'year_built', v_old.year_built,
    'notes', v_old.notes,
    'status', v_old.status,
    'created_at', v_old.created_at,
    'updated_at', v_old.updated_at,
    'created_by', v_old.created_by,
    'updated_by', v_old.updated_by,
    'version', v_old.version,
    'deleted_at', v_old.deleted_at
  );

  v_new_values := jsonb_build_object(
    'id', v_new.id,
    'workspace_id', v_new.workspace_id,
    'name', v_new.name,
    'address_line1', v_new.address_line1,
    'address_line2', v_new.address_line2,
    'zip', v_new.zip,
    'city', v_new.city,
    'country', v_new.country,
    'property_type', v_new.property_type,
    'units', v_new.units,
    'sqft', v_new.sqft,
    'year_built', v_new.year_built,
    'notes', v_new.notes,
    'status', v_new.status,
    'created_at', v_new.created_at,
    'updated_at', v_new.updated_at,
    'created_by', v_new.created_by,
    'updated_by', v_new.updated_by,
    'version', v_new.version,
    'deleted_at', v_new.deleted_at
  );

  insert into public.audit_events (
    workspace_id,
    actor_type,
    actor_user_id,
    role_key,
    scope_snapshot,
    action,
    entity_type,
    entity_id,
    source,
    correlation_id,
    mutation_id,
    reason,
    old_values,
    new_values,
    created_by,
    updated_by
  ) values (
    p_workspace_id,
    'user',
    v_actor_id,
    v_role_key,
    jsonb_build_object('workspace_id', p_workspace_id),
    'property.update',
    'property',
    p_property_id,
    'rpc',
    p_correlation_id,
    p_mutation_id,
    p_reason,
    v_old_values,
    v_new_values,
    v_actor_id,
    v_actor_id
  );

  update public.mutation_receipts
  set
    status = 'succeeded',
    result_entity_type = 'property',
    result_entity_id = p_property_id,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = version + 1
  where id = v_inserted_receipt_id;

  return jsonb_build_object('ok', true, 'property', v_new_values);
end;
$$;

alter function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
owner to postgres;

revoke all on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
from public, anon, authenticated;

grant execute on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
to authenticated;
