begin;

create extension if not exists pgtap with schema extensions;

-- PROPERTY-MEDIA-DATA-01: property photos and plans.
--
-- Media is the first property feature whose payload is a *file*, so the tests
-- carry two burdens the metadata packages do not:
--
--   * the bytes must be as scoped as the row. An entity-scoped membership that
--     cannot read a property must not be able to fetch its photo either, and
--     the storage policies are what decide that.
--   * a metadata row must correspond to bytes that exist, at a path that
--     belongs to this property. Otherwise a caller can attach someone else's
--     upload to their own record, or create a gallery entry that renders as a
--     broken image forever.

select plan(54);

-- ---------------------------------------------------------------------------
-- Schema and bucket
-- ---------------------------------------------------------------------------

select has_table('public', 'property_media', 'the media table exists');
select has_index(
  'public', 'property_media', 'property_media_single_cover_idx',
  'one cover per property is a database rule, not a client convention'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public' and class.relname = 'property_media'),
  'row level security is on and forced'
);
select is(
  (select array_agg(policy.policyname::text order by policy.policyname)
   from pg_policies as policy
   where policy.schemaname = 'public' and policy.tablename = 'property_media'),
  array['property_media_select_property_read'],
  'exactly one policy, and it is a read: every write goes through an RPC'
);
select is(
  (select public from storage.buckets where id = 'property-media'),
  false,
  'the bucket is private'
);
select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname like 'property_media_bucket_%'
     and cmd in ('UPDATE', 'DELETE')),
  0,
  'no update and no delete policy: an object cannot be overwritten or removed '
  'by a client'
);
select is(
  (select count(*)::integer
   from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname in (
       'property_media_bucket_select_property_read',
       'property_media_bucket_insert_property_update'
     )),
  2,
  'read and insert are the only two byte-level policies'
);
select is(
  private.property_media_path_workspace('not-a-path'),
  null,
  'a malformed path yields null, which makes every policy fail closed'
);
select is(
  private.property_media_path_property(
    'e1000000-0000-0000-0000-000000000001/e5000000-0000-0000-0000-000000000001/m/f.jpg'
  ),
  'e5000000-0000-0000-0000-000000000001'::uuid,
  'and a well-formed one yields the property it belongs to'
);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'media-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('b2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'media-viewer@example.test', '', now(), '{}', '{}', now(), now()),
  ('b2000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'media-scoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('b2000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'media-outsider@example.test', '', now(), '{}', '{}', now(), now());

insert into public.workspaces (id, key, name) values
  ('b1000000-0000-0000-0000-000000000001', 'media-a', 'Media A');

select private.seed_workspace_role_catalog('b1000000-0000-0000-0000-000000000001');

insert into public.memberships (id, workspace_id, user_id, role_id, status)
select
  pairing.membership_id,
  'b1000000-0000-0000-0000-000000000001',
  pairing.user_id,
  role.id,
  'active'
from (values
  ('b4000000-0000-0000-0000-000000000001'::uuid, 'b2000000-0000-0000-0000-000000000001'::uuid, 'admin'),
  ('b4000000-0000-0000-0000-000000000002'::uuid, 'b2000000-0000-0000-0000-000000000002'::uuid, 'viewer'),
  ('b4000000-0000-0000-0000-000000000003'::uuid, 'b2000000-0000-0000-0000-000000000003'::uuid, 'admin')
) as pairing(membership_id, user_id, role_key)
join public.roles as role
  on role.workspace_id = 'b1000000-0000-0000-0000-000000000001'
  and role.key = pairing.role_key;

-- The scoped admin is pinned to property A.
insert into public.entity_scopes (workspace_id, membership_id, entity_type, entity_id)
values ('b1000000-0000-0000-0000-000000000001',
        'b4000000-0000-0000-0000-000000000003',
        'property', 'b5000000-0000-0000-0000-000000000001');

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('b5000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
   'Bild-Haus', 'Fotoweg 1', '10115', 'Berlin', 'de', 'residential', 4,
   'b2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001'),
  ('b5000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
   'Nachbar-Haus', 'Fotoweg 2', '10115', 'Berlin', 'de', 'residential', 4,
   'b2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001');

-- Uploaded bytes. The registration RPC insists these exist.
insert into storage.objects (bucket_id, name) values
  ('property-media', 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-000000000001/front.jpg'),
  ('property-media', 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-000000000002/plan.png'),
  ('property-media', 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000002/b6000000-0000-0000-0000-000000000003/neighbour.jpg');

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
    json_build_object('sub', p_user::text, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
end;
$$;

create or replace function pg_temp.reset_actor()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'postgres', true);
end;
$$;

create or replace function pg_temp.register(
  p_user uuid,
  p_mutation uuid,
  p_path text default 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-000000000001/front.jpg',
  p_property uuid default 'b5000000-0000-0000-0000-000000000001',
  p_kind text default 'photo',
  p_title text default 'Vorderansicht',
  p_cover boolean default false,
  p_aal text default 'aal2'
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, p_aal);
  v_result := public.register_property_media(
    'b1000000-0000-0000-0000-000000000001',
    p_property,
    p_mutation,
    p_mutation,
    p_path,
    'front.jpg',
    'image/jpeg',
    123456,
    p_kind,
    p_title,
    p_cover,
    null
  );
  perform pg_temp.reset_actor();
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Registration gates
-- ---------------------------------------------------------------------------

select is(
  (select public.register_property_media(
     'b1000000-0000-0000-0000-000000000001',
     'b5000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-00000000000a',
     'b7000000-0000-0000-0000-00000000000a',
     'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-000000000001/front.jpg',
     'front.jpg', 'image/jpeg', 1, 'photo', null, false, null
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an unauthenticated caller is refused'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-00000000000b',
     p_aal => 'aal1'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'an aal1 session is refused'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000004',
     'b7000000-0000-0000-0000-00000000000c'
   ) -> 'error' ->> 'code'),
  'forbidden',
  'a non-member is refused'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000002',
     'b7000000-0000-0000-0000-00000000000d'
   ) -> 'error' ->> 'message'),
  'Property changes are not permitted',
  'a viewer may read a property but not change its pictures'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000003',
     'b7000000-0000-0000-0000-00000000000e',
     p_path => 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000002/b6000000-0000-0000-0000-000000000003/neighbour.jpg',
     p_property => 'b5000000-0000-0000-0000-000000000002'
   ) -> 'error' ->> 'message'),
  'Property changes are not permitted',
  'the scoped admin cannot add a picture to the neighbouring property'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-00000000000f',
     p_kind => 'hologram'
   ) -> 'error' ->> 'field'),
  'kind',
  'an unknown kind is rejected by name'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000010',
     p_path => 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000002/b6000000-0000-0000-0000-000000000003/neighbour.jpg'
   ) -> 'error' ->> 'message'),
  'Storage path does not belong to this property',
  'a path under another property cannot be attached to this record'
);
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000011',
     p_path => 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-0000000000ff/ghost.jpg'
   ) -> 'error' ->> 'message'),
  'No uploaded object exists at this path',
  'a row that points at nothing is refused: it would render as a broken image '
  'forever'
);

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000001'
   ) ->> 'ok'),
  'true',
  'an admin registers the first picture'
);
select is(
  (select count(*)::integer from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'),
  1,
  'and exactly one row exists'
);
select is(
  (select is_cover from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'),
  true,
  'the first picture of a property becomes its cover without being asked'
);
select is(
  (select status::text from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'),
  'active',
  'and it is active'
);
select is(
  (select sort_order from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'),
  0,
  'the first picture sorts first'
);
select is(
  (select count(*)::integer from public.audit_events
   where entity_type = 'property_media'
     and action = 'property_media.registered'),
  1,
  'the registration is audited'
);
select is(
  (select parent_entity_id from public.audit_events
   where entity_type = 'property_media' limit 1),
  'b5000000-0000-0000-0000-000000000001'::uuid,
  'and the audit row names the property, so it appears in its trail'
);
select is(
  (select status::text from public.mutation_receipts
   where mutation_id = 'b7000000-0000-0000-0000-000000000001'),
  'succeeded',
  'the receipt is settled'
);

-- Replay: the same mutation id returns the same picture rather than a second.
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000001'
   ) -> 'media' ->> 'file_name'),
  'front.jpg',
  'a retried registration replays the stored result'
);
select is(
  (select count(*)::integer from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'),
  1,
  'and creates no second row'
);

-- A second picture: not the cover, and it sorts after the first.
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000002',
     p_path => 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000001/b6000000-0000-0000-0000-000000000002/plan.png',
     p_kind => 'floor_plan',
     p_title => 'Grundriss'
   ) -> 'media' ->> 'is_cover'),
  'false',
  'a second picture does not take the cover'
);
select is(
  (select sort_order from public.property_media where title = 'Grundriss'),
  1,
  'and sorts after the first'
);
select is(
  (select count(*)::integer from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001' and is_cover),
  1,
  'there is still exactly one cover'
);

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

create or replace function pg_temp.update_media(
  p_user uuid,
  p_mutation uuid,
  p_media uuid,
  p_expected bigint default null,
  p_title text default null,
  p_kind text default null,
  p_sort integer default null,
  p_cover boolean default null,
  p_archived boolean default null
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform pg_temp.act_as(p_user, 'aal2');
  v_result := public.update_property_media(
    'b1000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    p_media,
    p_expected,
    p_mutation,
    p_mutation,
    p_title,
    p_kind,
    p_sort,
    p_cover,
    p_archived,
    null
  );
  perform pg_temp.reset_actor();
  return v_result;
end;
$$;

select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000003',
     (select id from public.property_media where title = 'Grundriss'),
     p_title => 'Grundriss EG'
   ) -> 'media' ->> 'title'),
  'Grundriss EG',
  'the title is editable'
);
select is(
  (select version from public.property_media where title = 'Grundriss EG'),
  2::bigint,
  'and the version moves'
);
select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000004',
     (select id from public.property_media where title = 'Grundriss EG'),
     p_expected => 99
   ) -> 'error' ->> 'code'),
  'version_conflict',
  'a stale expected version is refused'
);
select isnt(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000005',
     (select id from public.property_media where title = 'Grundriss EG'),
     p_expected => 99
   ) -> 'error' -> 'current_media'),
  null,
  'and hands back the current record so the client can show what changed'
);

-- Moving the cover clears the previous one, atomically.
select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000006',
     (select id from public.property_media where title = 'Grundriss EG'),
     p_cover => true
   ) -> 'media' ->> 'is_cover'),
  'true',
  'the cover can be moved to another picture'
);
select is(
  (select count(*)::integer from public.property_media
   where property_id = 'b5000000-0000-0000-0000-000000000001'
     and is_cover and deleted_at is null),
  1,
  'and there is still exactly one cover'
);
select is(
  (select is_cover from public.property_media where title = 'Vorderansicht'),
  false,
  'the previous cover gave it up'
);

-- Archiving.
select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000007',
     (select id from public.property_media where title = 'Grundriss EG'),
     p_archived => true
   ) -> 'media' ->> 'status'),
  'archived',
  'a picture can be archived'
);
select isnt(
  (select deleted_at from public.property_media where title = 'Grundriss EG'),
  null,
  'the tombstone marker travels with the status'
);
select is(
  (select is_cover from public.property_media where title = 'Grundriss EG'),
  false,
  'archiving gives up the cover: an unserved picture cannot be the header'
);
select is(
  (select count(*)::integer from public.audit_events
   where entity_type = 'property_media'
     and action = 'property_media.archived'),
  1,
  'archiving is audited under its own action'
);
select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000008',
     (select id from public.property_media where title = 'Grundriss EG'),
     p_archived => false
   ) -> 'media' ->> 'status'),
  'active',
  'and it can be restored'
);
select is(
  (select deleted_at from public.property_media where title = 'Grundriss EG'),
  null,
  'which clears the marker again'
);

select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000002',
     'b7000000-0000-0000-0000-000000000009',
     (select id from public.property_media where title = 'Vorderansicht'),
     p_title => 'Von der Strasse'
   ) -> 'error' ->> 'message'),
  'Property changes are not permitted',
  'a viewer cannot rename a picture'
);
select is(
  (select pg_temp.update_media(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000012',
     '00000000-0000-0000-0000-0000000000ff'
   ) -> 'error' ->> 'code'),
  'not_found',
  'an unknown picture is not found'
);

-- ---------------------------------------------------------------------------
-- Reading: rows and bytes are scoped the same way
-- ---------------------------------------------------------------------------

-- The neighbouring property gets one picture, so the scope test has something
-- to hide.
select is(
  (select pg_temp.register(
     'b2000000-0000-0000-0000-000000000001',
     'b7000000-0000-0000-0000-000000000013',
     p_path => 'b1000000-0000-0000-0000-000000000001/b5000000-0000-0000-0000-000000000002/b6000000-0000-0000-0000-000000000003/neighbour.jpg',
     p_property => 'b5000000-0000-0000-0000-000000000002',
     p_title => 'Nachbar'
   ) ->> 'ok'),
  'true',
  'the neighbouring property gets a picture too'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b2000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
select is(
  (select count(*)::integer from public.property_media),
  3,
  'the unscoped admin reads every picture in the workspace'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'property-media'),
  3,
  'and can fetch every object'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b2000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}',
  true
);
select is(
  (select count(*)::integer from public.property_media),
  2,
  'the scoped admin reads only their property''s rows'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'property-media'),
  2,
  'and only their property''s bytes: the entity scope reaches the file, not '
  'just the row'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b2000000-0000-0000-0000-000000000004","role":"authenticated","aal":"aal2"}',
  true
);
select is(
  (select count(*)::integer from public.property_media),
  0,
  'a non-member reads nothing'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'property-media'),
  0,
  'and fetches nothing'
);
reset role;

-- aal1: DEC-025 closes the read surface too.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b2000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);
select is(
  (select count(*)::integer from public.property_media),
  0,
  'an aal1 session reads no rows'
);
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'property-media'),
  0,
  'and no bytes'
);
reset role;

select * from finish();

rollback;
