-- SECURITY-AAL-ENFORCEMENT-01
--
-- The AAL2 boundary for workspace business access. Threat model: a compromised
-- password alone must not expose workspace business data. The password is the
-- first factor only; workspace business data requires a verified second factor.
-- Identity and MFA bootstrap surfaces stay reachable at aal1 -- they live in
-- GoTrue, not behind these policies, so nothing here gates them.
--
-- Every aal1 assertion below is driven by an actor who *holds the permission*
-- and *is an active member*. That is deliberate: a denial caused by a missing
-- fixture would prove nothing, so the only variable left is the assurance level.
-- The aal2 control arm re-runs the identical read and must succeed.

begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

-- === Fixtures ============================================================

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'a2700000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'aal-a@example.test', '', now(), '{}', '{}', now(), now()
  ),
  (
    'b2700000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'aal-b@example.test', '', now(), '{}', '{}', now(), now()
  );

insert into public.workspaces (id, key, name) values
  ('12700000-0000-0000-0000-000000000001', 'aal-a', 'AAL A'),
  ('22700000-0000-0000-0000-000000000001', 'aal-b', 'AAL B');

insert into public.roles (id, workspace_id, key, name) values
  ('12700000-0000-0000-0000-000000000002', '12700000-0000-0000-0000-000000000001', 'manager', 'Manager A'),
  ('22700000-0000-0000-0000-000000000002', '22700000-0000-0000-0000-000000000001', 'manager', 'Manager B');

insert into public.permissions (id, key, name) values
  ('32700000-0000-0000-0000-000000000001', 'property.read', 'Property Read'),
  ('32700000-0000-0000-0000-000000000002', 'workspace.read', 'Workspace Read'),
  ('32700000-0000-0000-0000-000000000003', 'notification.read', 'Notification Read'),
  ('32700000-0000-0000-0000-000000000004', 'security.manage', 'Security Manage'),
  ('32700000-0000-0000-0000-000000000005', 'lease.read', 'Lease Read');

-- Actor A holds every permission the assertions below exercise, so an aal1
-- denial can only come from the assurance level.
insert into public.role_permissions (workspace_id, role_id, permission_id)
select '12700000-0000-0000-0000-000000000001'::uuid,
       '12700000-0000-0000-0000-000000000002'::uuid,
       permission.id
from public.permissions as permission;

insert into public.role_permissions (workspace_id, role_id, permission_id)
select '22700000-0000-0000-0000-000000000001'::uuid,
       '22700000-0000-0000-0000-000000000002'::uuid,
       permission.id
from public.permissions as permission;

insert into public.memberships (workspace_id, user_id, role_id, status) values
  (
    '12700000-0000-0000-0000-000000000001',
    'a2700000-0000-0000-0000-000000000001',
    '12700000-0000-0000-0000-000000000002',
    'active'
  ),
  (
    '22700000-0000-0000-0000-000000000001',
    'b2700000-0000-0000-0000-000000000001',
    '22700000-0000-0000-0000-000000000002',
    'active'
  );

insert into public.properties (
  id, workspace_id, name, address_line1, zip, city, country, property_type,
  units, status, created_by, updated_by
) values
  (
    '72700000-0000-0000-0000-000000000001',
    '12700000-0000-0000-0000-000000000001',
    'AAL Property A', 'A Street 1', '10115', 'Berlin', 'de', 'office', 1, 'active',
    'a2700000-0000-0000-0000-000000000001', 'a2700000-0000-0000-0000-000000000001'
  ),
  (
    '72700000-0000-0000-0000-000000000002',
    '22700000-0000-0000-0000-000000000001',
    'AAL Property B', 'B Street 1', '20095', 'Hamburg', 'de', 'office', 1, 'active',
    'b2700000-0000-0000-0000-000000000001', 'b2700000-0000-0000-0000-000000000001'
  );

insert into public.notifications (
  id, workspace_id, recipient_user_id, kind, title, body, created_by, updated_by
) values (
  '82700000-0000-0000-0000-000000000001',
  '12700000-0000-0000-0000-000000000001',
  'a2700000-0000-0000-0000-000000000001',
  'task_assigned', 'AAL notification', 'Body that must stay hidden at aal1',
  'a2700000-0000-0000-0000-000000000001', 'a2700000-0000-0000-0000-000000000001'
);

-- === A. aal1 is denied across the business read surface ==================
-- Actor A is an active member and holds every permission used here.

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a2700000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);

select is((select count(*)::integer from public.properties), 0,
  'A1: aal1 cannot read properties even holding property.read');
select is((select count(*)::integer from public.workspaces), 0,
  'A2: aal1 cannot read workspaces even holding workspace.read');
select is((select count(*)::integer from public.roles), 0,
  'A3: aal1 cannot read roles');
select is((select count(*)::integer from public.role_permissions), 0,
  'A4: aal1 cannot read role_permissions');
-- memberships_select_authorized is OR-shaped: the own-row disjunct must not
-- survive the boundary, or every member keeps a workspace-scoped read at aal1.
select is((select count(*)::integer from public.memberships), 0,
  'A5: aal1 cannot read its own membership row');
-- notifications_select_own_or_read is OR-shaped the same way, and the payload
-- carries title/body/entity references.
select is((select count(*)::integer from public.notifications), 0,
  'A6: aal1 cannot read its own notifications');
select is((select count(*)::integer from public.permissions), 0,
  'A7: aal1 cannot read the permission catalogue');

-- === B. aal2 control arm: the identical reads succeed ====================

select set_config(
  'request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select is((select count(*)::integer from public.properties), 1,
  'B1: aal2 reads the authorized property');
select is((select count(*)::integer from public.workspaces), 1,
  'B2: aal2 reads the authorized workspace');
select is((select count(*)::integer from public.memberships), 1,
  'B3: aal2 reads its own membership row');
select is((select count(*)::integer from public.notifications), 1,
  'B4: aal2 reads its own notification');
select is((select count(*)::integer from public.permissions), 5,
  'B5: aal2 reads the permission catalogue');

-- === C. AAL2 does not replace tenant isolation ===========================

select is(
  (select count(*)::integer from public.properties
   where workspace_id = '22700000-0000-0000-0000-000000000001'),
  0,
  'C1: aal2 still cannot read a foreign workspace property');
select is(
  (select id from public.properties),
  '72700000-0000-0000-0000-000000000001'::uuid,
  'C2: aal2 sees exactly its own workspace row');

-- === D. Fail-closed claim matrix =========================================
-- Driven through a helper-gated table read, not through update_property --
-- update_property has its own hand-written wrapper and would pass for the
-- wrong reason. auth.uid() keeps resolving via the singular GUC set above,
-- so the assurance claim is the only variable in every vector.

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":"aal1"}', true);
select is((select count(*)::integer from public.properties), 0, 'D1: aal1 denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":"aal3"}', true);
select is((select count(*)::integer from public.properties), 0, 'D2: aal3 denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":null}', true);
select is((select count(*)::integer from public.properties), 0, 'D3: JSON null denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":2}', true);
select is((select count(*)::integer from public.properties), 0, 'D4: numeric claim denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":["aal2"]}', true);
select is((select count(*)::integer from public.properties), 0, 'D5: array claim denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":{"level":"aal2"}}', true);
select is((select count(*)::integer from public.properties), 0, 'D6: object claim denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":"AAL2"}', true);
select is((select count(*)::integer from public.properties), 0, 'D7: uppercase denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","aal":"aal2 "}', true);
select is((select count(*)::integer from public.properties), 0, 'D8: trailing space denied');

select set_config('request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001"}', true);
select is((select count(*)::integer from public.properties), 0, 'D9: missing claim denied');

select set_config('request.jwt.claims', '', true);
select is((select count(*)::integer from public.properties), 0, 'D10: empty claims GUC denied');

select set_config('request.jwt.claims', '"aal2"', true);
select is((select count(*)::integer from public.properties), 0, 'D11: scalar claims document denied');

-- === E. H1: no pre-authorization existence oracle ========================
-- Actor B is not a member of workspace A. A live property and a nonexistent
-- one in that workspace must be indistinguishable, or the response is an
-- existence oracle for the (workspace, property) relation.

select set_config('request.jwt.claim.sub', 'b2700000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"b2700000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);

select is(
  public.operations_signals(
    '12700000-0000-0000-0000-000000000001',
    '72700000-0000-0000-0000-000000000001'
  ) #>> '{error,code}',
  'forbidden',
  'E1: an unauthorized caller gets forbidden for a live foreign property');
select is(
  public.operations_signals(
    '12700000-0000-0000-0000-000000000001',
    '72700000-0000-0000-0000-0000000000ff'
  ) #>> '{error,code}',
  'forbidden',
  'E2: and the identical answer for one that does not exist');

-- === F. platform_command_gate carries the boundary =======================
-- mark_notification_read reaches no permission helper by design -- its
-- contract is "the recipient may mark their own notification read". It must
-- still inherit AAL2, and it does so through the platform command gate.

select set_config('request.jwt.claim.sub', 'a2700000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);

select is(
  public.mark_notification_read(
    '12700000-0000-0000-0000-000000000001',
    '82700000-0000-0000-0000-000000000001',
    '92700000-0000-0000-0000-000000000001',
    '92700000-0000-0000-0000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'F1: aal1 cannot mark a notification read');

reset role;
select is(
  (select read_at from public.notifications
   where id = '82700000-0000-0000-0000-000000000001'),
  null,
  'F2: and the notification was not mutated');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a2700000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',
  true
);
select is(
  public.mark_notification_read(
    '12700000-0000-0000-0000-000000000001',
    '82700000-0000-0000-0000-000000000001',
    '92700000-0000-0000-0000-000000000003',
    '92700000-0000-0000-0000-000000000004'
  ) ->> 'ok',
  'true',
  'F3: aal2 recipient can still mark it read');

select * from finish();

rollback;
