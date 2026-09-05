\set ON_ERROR_STOP on

-- SECURITY-STORAGE-AAL-03.
--
-- Three identities against two workspaces, so every denial in the storage
-- matrix is attributable to exactly one cause:
--
--   storage-full     workspace A, document.read + document.manage
--   storage-read     workspace A, document.read only
--   storage-foreign  workspace B, document.read + document.manage
--
-- The read-only and foreign identities exist so a denial can be traced to the
-- missing permission or the wrong workspace rather than to the assurance level,
-- and the full identity is used on both sides of an MFA elevation so the aal1
-- denials cannot be explained by a missing membership.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '5a000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-full@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-read@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'storage-foreign@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name) values
  ('51000000-0000-0000-0000-000000000001', 'storage-a', 'Storage A'),
  ('52000000-0000-0000-0000-000000000001', 'storage-b', 'Storage B');

insert into public.roles (id, workspace_id, key, name) values
  ('51000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001', 'document_manager', 'Document Manager A'),
  ('51000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000001', 'document_reader', 'Document Reader A'),
  ('52000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000001', 'document_manager', 'Document Manager B');

insert into public.permissions (id, key, name) values
  ('53000000-0000-0000-0000-000000000001', 'document.read', 'Document Read'),
  ('53000000-0000-0000-0000-000000000002', 'document.manage', 'Document Manage'),
  ('53000000-0000-0000-0000-000000000003', 'workspace.read', 'Workspace Read');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  -- A / manager: read + manage
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000003'),
  -- A / reader: read only, deliberately no manage
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000001'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000003'),
  -- B / manager: read + manage, but only inside workspace B
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002'),
  ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000003');

insert into public.memberships (workspace_id, user_id, role_id, status) values
  ('51000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002', 'active'),
  ('51000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000003', 'active'),
  ('52000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000002', 'active');

-- ---------------------------------------------------------------------------
-- PROPERTY-MEDIA-DATA-01 arm.
--
-- The media bucket is gated differently from the documents bucket, so it needs
-- its own identities rather than a reuse of the three above:
--
--   * SELECT needs entity-scoped `property.read`, INSERT entity-scoped
--     `property.update`. Both are *entity* scoped, which the documents bucket
--     is not, so this is the only place the entity scope is proved through the
--     real HTTP path.
--   * There is no UPDATE and no DELETE policy at all, which is stricter than
--     the documents bucket's immutability and deserves its own assertions.
--
--   media-manager   workspace A, property.read + property.update, unrestricted
--   media-scoped    workspace A, the same two permissions, but its membership
--                   is scoped to property 1 only
--   media-reader    workspace A, property.read only
--
-- The scoped identity is the load-bearing one: it holds every permission the
-- INSERT policy asks for and must still be refused on property 2, which no
-- permission check alone could explain.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '5a000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'media-manager@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'media-scoped@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  ),
  (
    '5a000000-0000-0000-0000-000000000013',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'media-reader@example.test',
    extensions.crypt('NexImmo-Test-2026!', extensions.gen_salt('bf')),
    now(), '', '', '', '', '{}', '{}', now(), now()
  );

insert into public.permissions (id, key, name) values
  ('53000000-0000-0000-0000-000000000011', 'property.read', 'Property Read'),
  ('53000000-0000-0000-0000-000000000012', 'property.update', 'Property Update');

insert into public.roles (id, workspace_id, key, name) values
  ('51000000-0000-0000-0000-000000000011', '51000000-0000-0000-0000-000000000001',
   'media_manager', 'Media Manager A'),
  ('51000000-0000-0000-0000-000000000012', '51000000-0000-0000-0000-000000000001',
   'media_reader', 'Media Reader A');

insert into public.role_permissions (workspace_id, role_id, permission_id) values
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000011'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000012'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000003'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000012', '53000000-0000-0000-0000-000000000011'),
  ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000012', '53000000-0000-0000-0000-000000000003');

-- Two properties in workspace A, so an entity scope has something to exclude.
insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, created_by, updated_by
) values
  ('54000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001',
   'Medienhaus', 'Bildweg 1', '10115', 'Berlin', 'de', 'residential', 1,
   '5a000000-0000-0000-0000-000000000011', '5a000000-0000-0000-0000-000000000011'),
  ('54000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001',
   'Nebenhaus', 'Bildweg 3', '10115', 'Berlin', 'de', 'residential', 1,
   '5a000000-0000-0000-0000-000000000011', '5a000000-0000-0000-0000-000000000011');

insert into public.memberships (id, workspace_id, user_id, role_id, status) values
  ('55000000-0000-0000-0000-000000000011', '51000000-0000-0000-0000-000000000001',
   '5a000000-0000-0000-0000-000000000011', '51000000-0000-0000-0000-000000000011', 'active'),
  ('55000000-0000-0000-0000-000000000012', '51000000-0000-0000-0000-000000000001',
   '5a000000-0000-0000-0000-000000000012', '51000000-0000-0000-0000-000000000011', 'active'),
  ('55000000-0000-0000-0000-000000000013', '51000000-0000-0000-0000-000000000001',
   '5a000000-0000-0000-0000-000000000013', '51000000-0000-0000-0000-000000000012', 'active');

-- Only the scoped membership carries a scope row. A membership with no rows is
-- unrestricted, which is what makes the manager the control for the scoped
-- identity's denials.
insert into public.entity_scopes (
  workspace_id, membership_id, entity_type, entity_id, created_by
) values (
  '51000000-0000-0000-0000-000000000001',
  '55000000-0000-0000-0000-000000000012',
  'property',
  '54000000-0000-0000-0000-000000000001',
  '5a000000-0000-0000-0000-000000000011'
);
