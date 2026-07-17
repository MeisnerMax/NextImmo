create schema if not exists private;

create type public.membership_status as enum (
  'invited',
  'active',
  'suspended',
  'revoked'
);

create type public.audit_actor_type as enum (
  'user',
  'system',
  'service'
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  name text not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint workspaces_key_unique unique (key),
  constraint workspaces_key_normalized_check check (
    key = lower(btrim(key))
    and char_length(key) between 1 and 100
    and key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint workspaces_name_check check (char_length(btrim(name)) between 1 and 200),
  constraint workspaces_version_check check (version >= 1)
);

create table public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint user_profiles_user_id_unique unique (user_id),
  constraint user_profiles_user_id_fkey foreign key (user_id)
    references auth.users (id) on delete cascade,
  constraint user_profiles_display_name_check check (
    display_name is null or char_length(btrim(display_name)) between 1 and 200
  ),
  constraint user_profiles_version_check check (version >= 1)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  key text not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint roles_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint roles_workspace_id_id_unique unique (workspace_id, id),
  constraint roles_workspace_id_key_unique unique (workspace_id, key),
  constraint roles_key_normalized_check check (
    key = lower(btrim(key))
    and char_length(key) between 1 and 100
    and key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint roles_name_check check (char_length(btrim(name)) between 1 and 200),
  constraint roles_version_check check (version >= 1)
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint permissions_key_unique unique (key),
  constraint permissions_key_normalized_check check (
    key = lower(btrim(key))
    and char_length(key) between 1 and 100
    and key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint permissions_name_check check (char_length(btrim(name)) between 1 and 200)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  user_id uuid not null,
  role_id uuid not null,
  status public.membership_status not null default 'invited',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint memberships_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint memberships_user_id_fkey foreign key (user_id)
    references auth.users (id) on delete restrict,
  constraint memberships_workspace_role_fkey foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict,
  constraint memberships_workspace_id_id_unique unique (workspace_id, id),
  constraint memberships_workspace_user_unique unique (workspace_id, user_id),
  constraint memberships_version_check check (version >= 1)
);

create table public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  role_id uuid not null,
  permission_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint role_permissions_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint role_permissions_workspace_role_fkey foreign key (workspace_id, role_id)
    references public.roles (workspace_id, id) on delete restrict,
  constraint role_permissions_permission_id_fkey foreign key (permission_id)
    references public.permissions (id) on delete restrict,
  constraint role_permissions_workspace_role_permission_unique
    unique (workspace_id, role_id, permission_id)
);

create table public.entity_scopes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  membership_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint entity_scopes_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint entity_scopes_workspace_membership_fkey foreign key (workspace_id, membership_id)
    references public.memberships (workspace_id, id) on delete restrict,
  constraint entity_scopes_entity_type_normalized_check check (
    entity_type = lower(btrim(entity_type))
    and char_length(entity_type) between 1 and 100
    and entity_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint entity_scopes_target_unique
    unique (workspace_id, membership_id, entity_type, entity_id)
);

create table public.mutation_receipts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  mutation_id uuid not null,
  request_hash bytea not null,
  status text not null default 'pending',
  result_entity_type text,
  result_entity_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint mutation_receipts_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint mutation_receipts_workspace_mutation_unique unique (workspace_id, mutation_id),
  constraint mutation_receipts_request_hash_check check (octet_length(request_hash) = 32),
  constraint mutation_receipts_status_check check (status in ('pending', 'succeeded', 'failed')),
  constraint mutation_receipts_result_entity_type_check check (
    result_entity_type is null or (
      result_entity_type = lower(btrim(result_entity_type))
      and char_length(result_entity_type) between 1 and 100
      and result_entity_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
    )
  ),
  constraint mutation_receipts_result_pair_check check (
    (result_entity_type is null) = (result_entity_id is null)
  ),
  constraint mutation_receipts_version_check check (version >= 1)
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  actor_type public.audit_actor_type not null,
  actor_user_id uuid,
  actor_identifier text,
  role_key text,
  scope_snapshot jsonb not null default '{}'::jsonb,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  parent_entity_type text,
  parent_entity_id uuid,
  source text not null,
  correlation_id uuid not null,
  mutation_id uuid,
  reason text,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  version bigint not null default 1,
  constraint audit_events_workspace_id_fkey foreign key (workspace_id)
    references public.workspaces (id) on delete restrict,
  constraint audit_events_workspace_mutation_unique unique (workspace_id, mutation_id),
  constraint audit_events_actor_check check (
    (actor_type = 'user' and actor_user_id is not null)
    or (actor_type in ('system', 'service') and actor_identifier is not null)
  ),
  constraint audit_events_actor_identifier_check check (
    actor_identifier is null or char_length(btrim(actor_identifier)) between 1 and 200
  ),
  constraint audit_events_role_key_normalized_check check (
    role_key is null or (
      role_key = lower(btrim(role_key))
      and char_length(role_key) between 1 and 100
      and role_key ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
    )
  ),
  constraint audit_events_action_normalized_check check (
    action = lower(btrim(action))
    and char_length(action) between 1 and 100
    and action ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint audit_events_entity_type_normalized_check check (
    entity_type = lower(btrim(entity_type))
    and char_length(entity_type) between 1 and 100
    and entity_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint audit_events_parent_pair_check check (
    (parent_entity_type is null) = (parent_entity_id is null)
  ),
  constraint audit_events_parent_entity_type_check check (
    parent_entity_type is null or (
      parent_entity_type = lower(btrim(parent_entity_type))
      and char_length(parent_entity_type) between 1 and 100
      and parent_entity_type ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
    )
  ),
  constraint audit_events_source_normalized_check check (
    source = lower(btrim(source))
    and char_length(source) between 1 and 100
    and source ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'
  ),
  constraint audit_events_scope_snapshot_check check (jsonb_typeof(scope_snapshot) = 'object'),
  constraint audit_events_old_values_check check (
    old_values is null or jsonb_typeof(old_values) = 'object'
  ),
  constraint audit_events_new_values_check check (
    new_values is null or jsonb_typeof(new_values) = 'object'
  ),
  constraint audit_events_append_shape_check check (
    updated_at = created_at
    and updated_by is not distinct from created_by
    and version = 1
  )
);

create function private.reject_protected_column_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  protected_column text;
begin
  foreach protected_column in array tg_argv loop
    if to_jsonb(new) -> protected_column is distinct from to_jsonb(old) -> protected_column then
      raise exception '% is immutable on %.%', protected_column, tg_table_schema, tg_table_name
        using errcode = '23000';
    end if;
  end loop;
  return new;
end;
$$;

create function private.prepare_audit_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := new.created_at;
  new.updated_by := new.created_by;
  new.version := 1;
  return new;
end;
$$;

create function private.reject_audit_event_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_events is append-only' using errcode = 'P0001';
end;
$$;

create trigger workspaces_protected_columns
before update on public.workspaces
for each row execute function private.reject_protected_column_update('id', 'key', 'created_at', 'created_by');

create trigger user_profiles_protected_columns
before update on public.user_profiles
for each row execute function private.reject_protected_column_update('id', 'user_id', 'created_at', 'created_by');

create trigger roles_protected_columns
before update on public.roles
for each row execute function private.reject_protected_column_update('id', 'workspace_id', 'key', 'created_at', 'created_by');

create trigger permissions_protected_columns
before update on public.permissions
for each row execute function private.reject_protected_column_update('id', 'key', 'created_at', 'created_by');

create trigger memberships_protected_columns
before update on public.memberships
for each row execute function private.reject_protected_column_update('id', 'workspace_id', 'user_id', 'created_at', 'created_by');

create trigger role_permissions_protected_columns
before update on public.role_permissions
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'role_id', 'permission_id', 'created_at', 'created_by'
);

create trigger entity_scopes_protected_columns
before update on public.entity_scopes
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'membership_id', 'entity_type', 'entity_id', 'created_at', 'created_by'
);

create trigger mutation_receipts_protected_columns
before update on public.mutation_receipts
for each row execute function private.reject_protected_column_update(
  'id', 'workspace_id', 'mutation_id', 'request_hash', 'created_at', 'created_by'
);

create trigger audit_events_prepare_insert
before insert on public.audit_events
for each row execute function private.prepare_audit_event();

create trigger audit_events_append_only
before update or delete on public.audit_events
for each row execute function private.reject_audit_event_change();

alter table public.workspaces enable row level security;
alter table public.workspaces force row level security;
alter table public.user_profiles enable row level security;
alter table public.user_profiles force row level security;
alter table public.roles enable row level security;
alter table public.roles force row level security;
alter table public.permissions enable row level security;
alter table public.permissions force row level security;
alter table public.memberships enable row level security;
alter table public.memberships force row level security;
alter table public.role_permissions enable row level security;
alter table public.role_permissions force row level security;
alter table public.entity_scopes enable row level security;
alter table public.entity_scopes force row level security;
alter table public.audit_events enable row level security;
alter table public.audit_events force row level security;
alter table public.mutation_receipts enable row level security;
alter table public.mutation_receipts force row level security;

revoke all on table
  public.workspaces,
  public.user_profiles,
  public.roles,
  public.permissions,
  public.memberships,
  public.role_permissions,
  public.entity_scopes,
  public.audit_events,
  public.mutation_receipts
from anon, authenticated;

revoke all on function private.reject_protected_column_update() from public, anon, authenticated;
revoke all on function private.prepare_audit_event() from public, anon, authenticated;
revoke all on function private.reject_audit_event_change() from public, anon, authenticated;
