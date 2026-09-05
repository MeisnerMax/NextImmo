-- PROPERTY-MEDIA-DATA-01: property photos and floor plans.
--
-- A real-estate product without a picture of the building is a spreadsheet.
-- The gallery was removed in 2026-07 because there was no contract behind it
-- and the only alternative was to misuse `documents` as an image store -- which
-- the spec forbids in as many words. This is that contract.
--
-- Five decisions shape it.
--
--   1. **No new permission keys.** Media is property master data, not a domain
--      of its own: reading needs entity-scoped `property.read`, changing it
--      needs `property.update`. A new capability would ripple into the role
--      bundles, the permission catalogue test and the client-side mirror of it
--      for something that is, in the end, a field of the property.
--   2. **Entity scope reaches the bytes.** The storage policies parse the
--      workspace *and* the property out of the object path and run the same
--      scoped check the metadata rows use. A membership pinned to one property
--      cannot fetch another property's photo, not even with a path it guessed.
--   3. **Objects are immutable.** There is deliberately no UPDATE and no DELETE
--      policy on `storage.objects` for this bucket. Removing an image is a
--      metadata state change (`archived`), which stops it being served and
--      keeps it auditable; reclaiming the bytes is an operations job with its
--      own authority. A client that could overwrite an object could rewrite
--      history under a stable path.
--   4. **Metadata follows real bytes.** Registration verifies the object exists
--      at the declared path before it writes a row, so a caller cannot claim a
--      path they never uploaded to and cannot register a row that points at
--      nothing.
--   5. **One cover, enforced by the database.** A partial unique index, not
--      application code, decides that a property has at most one cover image.
--
-- Signed URLs are issued by the client SDK against this private bucket and are
-- never stored, logged or shared; the bucket stays private, so a leaked row
-- discloses a path, not an image.

create type public.property_media_kind as enum (
  'photo',
  'floor_plan',
  'site_plan',
  'exterior',
  'interior'
);

create type public.property_media_status as enum ('active', 'archived');

create table public.property_media (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  property_id uuid not null,
  storage_path text not null,
  file_name text not null,
  content_type text not null,
  byte_size bigint not null,
  kind public.property_media_kind not null default 'photo',
  title text,
  sort_order integer not null default 0,
  is_cover boolean not null default false,
  status public.property_media_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null,
  updated_by uuid not null,
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint property_media_workspace_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint property_media_property_fkey foreign key (property_id)
    references public.properties (id) on delete restrict,
  constraint property_media_storage_path_unique unique (storage_path),
  constraint property_media_file_name_check check (
    char_length(btrim(file_name)) between 1 and 255
  ),
  constraint property_media_title_check check (
    title is null or char_length(btrim(title)) between 1 and 200
  ),
  -- Only image types. This bucket is for pictures of a building, not a second
  -- document store, and the check says so rather than a comment somewhere.
  constraint property_media_content_type_check check (
    content_type in ('image/jpeg', 'image/png', 'image/webp')
  ),
  constraint property_media_byte_size_check check (
    byte_size between 1 and 20971520
  ),
  constraint property_media_sort_order_check check (
    sort_order between 0 and 9999
  ),
  -- The tombstone marker travels with the status, exactly as it does for a
  -- property (DEBT-012): archived means "has a deleted_at", and nothing else.
  constraint property_media_archived_marker_check check (
    (status = 'archived') = (deleted_at is not null)
  ),
  -- An archived image cannot be the cover: it is not being served.
  constraint property_media_cover_active_check check (
    not is_cover or status = 'active'
  )
);

comment on table public.property_media is
  'PROPERTY-MEDIA-DATA-01: photos and plans of a property. Bytes live in the '
  'private property-media bucket; this table is the metadata and the '
  'authority on what is served.';

-- The gallery read: one property's active pictures, in their order.
create index property_media_property_idx
  on public.property_media (workspace_id, property_id, sort_order, id)
  where deleted_at is null;

-- Plain indexes for the two foreign keys. The partial index above cannot serve
-- a referential integrity check, because the rows it excludes are exactly the
-- ones such a check must still see.
create index property_media_workspace_idx
  on public.property_media (workspace_id);

create index property_media_property_fk_idx
  on public.property_media (property_id);

-- At most one cover per property, decided by the database rather than by
-- whichever client wrote last.
create unique index property_media_single_cover_idx
  on public.property_media (workspace_id, property_id)
  where is_cover and deleted_at is null;

alter table public.property_media enable row level security;
alter table public.property_media force row level security;

-- Supabase's default privileges hand every new public table to anon and
-- authenticated, so the revoke comes first and the grant is deliberate: the
-- table is readable and nothing more. The policy below then says which rows.
revoke all on table public.property_media from anon, authenticated;
grant select on table public.property_media to authenticated;

-- Default deny: exactly one policy, and it is a read. Every write goes through
-- the audited RPCs below, which run as definer.
create policy property_media_select_property_read
on public.property_media
for select
to authenticated
using (
  private.has_scoped_entity_permission(
    workspace_id, 'property.read', 'property', property_id
  )
);

-- -----------------------------------------------------------------------------
-- Private storage bucket + RLS on storage.objects
-- -----------------------------------------------------------------------------

-- Idempotent for the same reason the documents bucket is: `migration down`
-- restores table data from a dump, so this row outlives a rollback while every
-- schema artifact around it does not.
insert into storage.buckets (id, name, public, file_size_limit)
values ('property-media', 'property-media', false, 20971520)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit;

-- Safe parse of `{workspace}/{property}/{media}/{filename}`. Any name that is
-- not shaped like that yields null, and every policy below then fails closed
-- because has_scoped_entity_permission(null, ...) is false.
create function private.property_media_path_workspace(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when object_name is null then null
    when split_part(object_name, '/', 1)
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then split_part(object_name, '/', 1)::uuid
    else null
  end;
$$;

create function private.property_media_path_property(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when object_name is null then null
    when split_part(object_name, '/', 2)
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then split_part(object_name, '/', 2)::uuid
    else null
  end;
$$;

alter function private.property_media_path_workspace(text) owner to postgres;
alter function private.property_media_path_property(text) owner to postgres;
revoke all on function private.property_media_path_workspace(text)
  from public, anon, authenticated;
revoke all on function private.property_media_path_property(text)
  from public, anon, authenticated;
grant execute on function private.property_media_path_workspace(text)
  to authenticated;
grant execute on function private.property_media_path_property(text)
  to authenticated;

-- Reading the bytes needs exactly what reading the property needs, entity
-- scope included. This is stricter than the documents bucket, which checks the
-- workspace only; there is no reason to be looser here.
create policy property_media_bucket_select_property_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'property-media'
  and private.has_scoped_entity_permission(
    private.property_media_path_workspace(name),
    'property.read',
    'property',
    private.property_media_path_property(name)
  )
);

create policy property_media_bucket_insert_property_update
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'property-media'
  and private.has_scoped_entity_permission(
    private.property_media_path_workspace(name),
    'property.update',
    'property',
    private.property_media_path_property(name)
  )
  -- {workspace}/{property}/{media}/{filename}: three folders plus a name.
  and array_length(storage.foldername(name), 1) >= 3
);

-- -----------------------------------------------------------------------------
-- Mutations. Same envelope as every other property mutation: AAL2, permission
-- and entity scope, idempotency by mutation id, append-only audit.
-- -----------------------------------------------------------------------------

create function private.property_media_command_gate(
  p_workspace_id uuid,
  p_property_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_reason text
)
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
        'message', 'AAL2 is required for property media changes'
      )
    );
  end if;

  if p_workspace_id is null or p_property_id is null
     or p_mutation_id is null or p_correlation_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Command identifiers are required'
      )
    );
  end if;

  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.update', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Property changes are not permitted'
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

  return null;
end;
$$;

alter function private.property_media_command_gate(uuid, uuid, uuid, uuid, text)
  owner to postgres;
revoke all on function private.property_media_command_gate(uuid, uuid, uuid, uuid, text)
  from public, anon, authenticated;

-- Snapshot used by the audit trail and by the idempotent replay.
create function private.property_media_snapshot(p_media public.property_media)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_media.id,
    'workspace_id', p_media.workspace_id,
    'property_id', p_media.property_id,
    'storage_path', p_media.storage_path,
    'file_name', p_media.file_name,
    'content_type', p_media.content_type,
    'byte_size', p_media.byte_size,
    'kind', p_media.kind,
    'title', p_media.title,
    'sort_order', p_media.sort_order,
    'is_cover', p_media.is_cover,
    'status', p_media.status,
    'created_at', p_media.created_at,
    'updated_at', p_media.updated_at,
    'created_by', p_media.created_by,
    'updated_by', p_media.updated_by,
    'version', p_media.version
  );
$$;

alter function private.property_media_snapshot(public.property_media)
  owner to postgres;
revoke all on function private.property_media_snapshot(public.property_media)
  from public, anon, authenticated;

create function public.register_property_media(
  p_workspace_id uuid,
  p_property_id uuid,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_storage_path text,
  p_file_name text,
  p_content_type text,
  p_byte_size bigint,
  p_kind text default 'photo',
  p_title text default null,
  p_is_cover boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_media public.property_media%rowtype;
  v_snapshot jsonb;
  v_kind public.property_media_kind;
  v_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_now timestamptz;
  v_sort integer;
begin
  v_gate := private.property_media_command_gate(
    p_workspace_id, p_property_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  begin
    v_kind := coalesce(p_kind, 'photo')::public.property_media_kind;
  exception when invalid_text_representation then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Unknown media kind',
        'field', 'kind'
      )
    );
  end;

  -- The path must be the one this property's uploads live under. Anything else
  -- would let a caller attach another property's bytes to this record.
  if p_storage_path is null
     or private.property_media_path_workspace(p_storage_path)
        is distinct from p_workspace_id
     or private.property_media_path_property(p_storage_path)
        is distinct from p_property_id then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Storage path does not belong to this property',
        'field', 'storage_path'
      )
    );
  end if;

  -- And the bytes must actually be there: a row that points at nothing would
  -- be a gallery entry that renders as a broken image forever.
  if not exists (
    select 1 from storage.objects as object
    where object.bucket_id = 'property-media'
      and object.name = p_storage_path
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'No uploaded object exists at this path',
        'field', 'storage_path'
      )
    );
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'register_property_media',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'storage_path', p_storage_path,
        'file_name', p_file_name,
        'content_type', p_content_type,
        'byte_size', p_byte_size,
        'kind', v_kind,
        'title', v_title,
        'is_cover', coalesce(p_is_cover, false),
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
    select receipt.* into v_receipt
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

    if v_receipt.status = 'succeeded' then
      select audit.new_values into v_snapshot
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'property_media';

      if v_snapshot is null then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'infrastructure_failure',
            'message', 'Successful mutation result is unavailable'
          )
        );
      end if;
      return jsonb_build_object('ok', true, 'media', v_snapshot);
    end if;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'in_progress', 'message', 'Mutation is already in progress'
      )
    );
  end if;

  v_now := now();

  -- New images go last. The order is the operator's, not the upload clock's,
  -- and it stays editable.
  select coalesce(max(media.sort_order), -1) + 1
  into v_sort
  from public.property_media as media
  where media.workspace_id = p_workspace_id
    and media.property_id = p_property_id
    and media.deleted_at is null;

  -- The first active image of a property is its cover unless one exists.
  if coalesce(p_is_cover, false) then
    update public.property_media
    set is_cover = false, updated_at = v_now, updated_by = v_actor_id,
        version = version + 1
    where workspace_id = p_workspace_id
      and property_id = p_property_id
      and is_cover
      and deleted_at is null;
  end if;

  insert into public.property_media (
    workspace_id, property_id, storage_path, file_name, content_type,
    byte_size, kind, title, sort_order, is_cover, status,
    created_at, updated_at, created_by, updated_by
  ) values (
    p_workspace_id, p_property_id, p_storage_path, btrim(p_file_name),
    p_content_type, p_byte_size, v_kind, v_title, v_sort,
    coalesce(p_is_cover, false)
      or not exists (
        select 1 from public.property_media as existing
        where existing.workspace_id = p_workspace_id
          and existing.property_id = p_property_id
          and existing.is_cover
          and existing.deleted_at is null
      ),
    'active', v_now, v_now, v_actor_id, v_actor_id
  )
  returning * into v_media;

  v_snapshot := private.property_media_snapshot(v_media);

  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, action, entity_type, entity_id,
    parent_entity_type, parent_entity_id, source, correlation_id, mutation_id,
    reason, new_values, created_by, updated_by
  ) values (
    p_workspace_id, 'user', v_actor_id, 'property_media.registered',
    'property_media', v_media.id, 'property', p_property_id, 'rpc',
    p_correlation_id, p_mutation_id, p_reason, v_snapshot,
    v_actor_id, v_actor_id
  );

  update public.mutation_receipts
  set status = 'succeeded', updated_at = v_now, updated_by = v_actor_id
  where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

  return jsonb_build_object('ok', true, 'media', v_snapshot);
end;
$$;

create function public.update_property_media(
  p_workspace_id uuid,
  p_property_id uuid,
  p_media_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_title text default null,
  p_kind text default null,
  p_sort_order integer default null,
  p_is_cover boolean default null,
  p_archived boolean default null,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_gate jsonb;
  v_request_hash bytea;
  v_inserted_receipt_id uuid;
  v_receipt public.mutation_receipts%rowtype;
  v_media public.property_media%rowtype;
  v_old jsonb;
  v_snapshot jsonb;
  v_kind public.property_media_kind;
  v_now timestamptz;
  v_archive boolean;
  v_cover boolean;
begin
  v_gate := private.property_media_command_gate(
    p_workspace_id, p_property_id, p_mutation_id, p_correlation_id, p_reason
  );
  if v_gate is not null then
    return v_gate;
  end if;

  select media.* into v_media
  from public.property_media as media
  where media.workspace_id = p_workspace_id
    and media.property_id = p_property_id
    and media.id = p_media_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Media not found')
    );
  end if;

  if p_expected_version is not null
     and v_media.version is distinct from p_expected_version then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'version_conflict',
        'message', 'Media was changed by someone else',
        'expected_version', p_expected_version,
        'actual_version', v_media.version,
        'current_media', private.property_media_snapshot(v_media)
      )
    );
  end if;

  if p_kind is not null then
    begin
      v_kind := p_kind::public.property_media_kind;
    exception when invalid_text_representation then
      return jsonb_build_object(
        'ok', false,
        'error', jsonb_build_object(
          'code', 'validation_failed',
          'message', 'Unknown media kind',
          'field', 'kind'
        )
      );
    end;
  else
    v_kind := v_media.kind;
  end if;

  v_archive := coalesce(p_archived, v_media.status = 'archived');
  v_cover := coalesce(p_is_cover, v_media.is_cover);

  -- Archiving takes the cover with it: an image that is not served cannot be
  -- the one on the header.
  if v_archive then
    v_cover := false;
  end if;

  v_request_hash := extensions.digest(
    convert_to(
      jsonb_build_object(
        'command', 'update_property_media',
        'actor_id', v_actor_id,
        'workspace_id', p_workspace_id,
        'property_id', p_property_id,
        'media_id', p_media_id,
        'expected_version', p_expected_version,
        'title', p_title,
        'kind', v_kind,
        'sort_order', p_sort_order,
        'is_cover', v_cover,
        'archived', v_archive,
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
    select receipt.* into v_receipt
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

    if v_receipt.status = 'succeeded' then
      select audit.new_values into v_snapshot
      from public.audit_events as audit
      where audit.workspace_id = p_workspace_id
        and audit.mutation_id = p_mutation_id
        and audit.entity_type = 'property_media';

      if v_snapshot is null then
        return jsonb_build_object(
          'ok', false,
          'error', jsonb_build_object(
            'code', 'infrastructure_failure',
            'message', 'Successful mutation result is unavailable'
          )
        );
      end if;
      return jsonb_build_object('ok', true, 'media', v_snapshot);
    end if;

    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'in_progress', 'message', 'Mutation is already in progress'
      )
    );
  end if;

  v_now := now();
  v_old := private.property_media_snapshot(v_media);

  if v_cover and not v_media.is_cover then
    update public.property_media
    set is_cover = false, updated_at = v_now, updated_by = v_actor_id,
        version = version + 1
    where workspace_id = p_workspace_id
      and property_id = p_property_id
      and is_cover
      and deleted_at is null
      and id <> p_media_id;
  end if;

  update public.property_media
  set
    title = case
      when p_title is null then title
      when btrim(p_title) = '' then null
      else btrim(p_title)
    end,
    kind = v_kind,
    sort_order = coalesce(p_sort_order, sort_order),
    is_cover = v_cover,
    status = (
      case when v_archive then 'archived' else 'active' end
    )::public.property_media_status,
    deleted_at = case when v_archive then coalesce(deleted_at, v_now) else null end,
    updated_at = v_now,
    updated_by = v_actor_id,
    version = version + 1
  where id = p_media_id
  returning * into v_media;

  v_snapshot := private.property_media_snapshot(v_media);

  insert into public.audit_events (
    workspace_id, actor_type, actor_user_id, action, entity_type, entity_id,
    parent_entity_type, parent_entity_id, source, correlation_id, mutation_id,
    reason, old_values, new_values, created_by, updated_by
  ) values (
    p_workspace_id, 'user', v_actor_id,
    case when v_archive then 'property_media.archived'
         else 'property_media.updated' end,
    'property_media', p_media_id, 'property', p_property_id, 'rpc',
    p_correlation_id, p_mutation_id, p_reason, v_old, v_snapshot,
    v_actor_id, v_actor_id
  );

  update public.mutation_receipts
  set status = 'succeeded', updated_at = v_now, updated_by = v_actor_id
  where workspace_id = p_workspace_id and mutation_id = p_mutation_id;

  return jsonb_build_object('ok', true, 'media', v_snapshot);
end;
$$;

alter function public.register_property_media(
  uuid, uuid, uuid, uuid, text, text, text, bigint, text, text, boolean, text
) owner to postgres;
alter function public.update_property_media(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, integer, boolean, boolean,
  text
) owner to postgres;

revoke all on function public.register_property_media(
  uuid, uuid, uuid, uuid, text, text, text, bigint, text, text, boolean, text
) from public, anon, authenticated;
revoke all on function public.update_property_media(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, integer, boolean, boolean,
  text
) from public, anon, authenticated;

grant execute on function public.register_property_media(
  uuid, uuid, uuid, uuid, text, text, text, bigint, text, text, boolean, text
) to authenticated;
grant execute on function public.update_property_media(
  uuid, uuid, uuid, bigint, uuid, uuid, text, text, integer, boolean, boolean,
  text
) to authenticated;
