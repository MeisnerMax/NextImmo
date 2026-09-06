begin;

create extension if not exists pgtap with schema extensions;

-- SECURITY-REGRESSION-TESTS-01.
--
-- REMOTE-SECURITY-GATE-01 audited all 65 public SECURITY DEFINER RPCs before any
-- staging authentication existed and found no privilege escalation, tenant escape
-- or AAL bypass. Those proofs were temporary. This file makes the ones that were
-- not already permanent part of every CI run.
--
-- Deliberately NOT duplicated here: anonymous RPC denial, cross-workspace and
-- foreign-entity denial, membership and role escalation, AAL1-deny/AAL2-allow,
-- direct table mutation, audit append-only and version_conflict. All of those are
-- already proven at runtime by the feature suites (002, 003, 005, 007, 008, 009,
-- 010, 011, ... 025) and re-proving them would only add maintenance surface.
--
-- What those suites cannot catch is the inventory itself. Every one of their
-- catalog assertions is scoped with `proname in (...)`, so a NEW function that
-- ships with EXECUTE to PUBLIC, or without a pinned search_path, passes all of
-- them. The assertions below are deliberately unscoped: they hold across the
-- whole schema, so a regression has to be introduced visibly rather than
-- silently.

select plan(34);

-- === Function grant surface, across the entire public schema ============

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(function.proacl) as acl
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and acl.privilege_type = 'EXECUTE'
     and acl.grantee = 0),
  0,
  'SR-17: no public function grants EXECUTE to PUBLIC'
);

-- A null proacl is not "no privileges": PostgreSQL then applies the built-in
-- default, which is EXECUTE to PUBLIC. Checking aclexplode alone would miss it,
-- because aclexplode(null) yields no rows at all.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.proacl is null),
  0,
  'SR-17: no public function relies on the default EXECUTE-to-PUBLIC acl'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(function.proacl) as acl
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and acl.privilege_type = 'EXECUTE'
     and acl.grantee = 'anon'::regrole),
  0,
  'SR-18: no public function grants EXECUTE to anon'
);

-- service_role is deliberately not asserted absent. Hosted Supabase grants it by
-- default and REMOTE-SECURITY-GATE-01 accepted that: the role already bypasses
-- RLS, its key never reaches a client, and without a user JWT auth.uid() is null
-- so every gate fails closed. Pinning "service_role must never hold EXECUTE"
-- here would encode a false expectation that local and hosted disagree on.

-- === search_path, across the entire public schema =======================

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef
     and not (coalesce(function.proconfig, '{}'::text[]) @> array['search_path=""']::text[])),
  0,
  'SR-19: every public SECURITY DEFINER function pins search_path to the empty string'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   join pg_roles as owner on owner.oid = function.proowner
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef
     and owner.rolname <> 'postgres'),
  0,
  'SR-19: every public SECURITY DEFINER function is owned by postgres'
);

-- === Inventory drift has to be a visible, reviewed change ===============

-- Not a freeze. Adding a function is allowed -- but the number below has to be
-- updated in the same pull request, which puts the new function's grants and
-- search_path in front of a reviewer instead of letting them ship unnoticed.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef),
  82,
  'SR-20: the public SECURITY DEFINER inventory is still 82 -- update this expectation deliberately when it changes'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and not function.prosecdef),
  0,
  'SR-20: no public function is SECURITY INVOKER, so none escapes the audited contract'
);

-- === Internal helpers stay unreachable ==================================

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(function.proacl) as acl
   where namespace.nspname = 'private'
     and acl.privilege_type = 'EXECUTE'
     and acl.grantee = 'anon'::regrole),
  0,
  'SR-09: no private helper grants EXECUTE to anon'
);

-- private functions with a null acl inherit EXECUTE to PUBLIC. That is tolerable
-- only while such a function either cannot be invoked directly at all (a trigger
-- function) or runs as SECURITY INVOKER, where the caller's own grants and RLS
-- still apply. A SECURITY DEFINER helper reachable this way would run with the
-- owner's privileges and is the exact escalation this asserts against.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.prokind = 'f'
     and function.prosecdef
     and function.proacl is null
     and pg_get_function_result(function.oid) <> 'trigger'),
  0,
  'SR-09: no directly invocable private SECURITY DEFINER helper is left executable by PUBLIC'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(function.proacl) as acl
   where namespace.nspname = 'private'
     and function.prosecdef
     and acl.privilege_type = 'EXECUTE'
     and acl.grantee = 'authenticated'::regrole
     and function.proname not in (
       -- Authorization predicates. They are safe to expose because each one
       -- answers only about the caller's own auth.uid(), and 002/005 already
       -- prove they return false for foreign workspaces.
       'has_workspace_permission', 'has_entity_scope',
       'has_scoped_entity_permission', 'is_active_workspace_member',
       'is_current_active_membership'
     )),
  0,
  'SR-09: only the caller-scoped authorization predicates are executable by authenticated in private'
);

select is(
  (select count(*)::integer
   from pg_namespace as namespace
   cross join lateral aclexplode(namespace.nspacl) as acl
   where namespace.nspname = 'private'
     and acl.grantee = 'anon'::regrole),
  0,
  'SR-09: anon holds no privilege on the private schema'
);

-- === Table surface: every mutation must pass the RPC layer ==============

select is(
  (select count(*)::integer
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   cross join lateral aclexplode(class.relacl) as acl
   where namespace.nspname = 'public'
     and class.relkind = 'r'
     and acl.grantee = 'authenticated'::regrole
     and acl.privilege_type <> 'SELECT'),
  0,
  'SR-13: authenticated holds no write privilege on any public table'
);

select is(
  (select count(*)::integer
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   cross join lateral aclexplode(class.relacl) as acl
   where namespace.nspname = 'public'
     and class.relkind = 'r'
     and acl.grantee in (0, 'anon'::regrole)),
  0,
  'SR-13: neither anon nor PUBLIC holds any privilege on any public table'
);

select is(
  (select count(*)::integer
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'public'
     and class.relkind = 'r'
     and not class.relrowsecurity),
  0,
  'SR-03: every public table has row level security enabled'
);

select is(
  (select count(*)::integer
   from pg_class as class
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   cross join lateral aclexplode(class.relacl) as acl
   where namespace.nspname = 'public'
     and class.relname = 'mutation_receipts'
     and acl.grantee in (0, 'anon'::regrole, 'authenticated'::regrole)),
  0,
  'SR-14: mutation_receipts stays closed to every client role'
);

-- === Caller identity is never a parameter ===============================

-- The audit found identity is always taken from auth.uid() in a DECLARE
-- initialiser. This keeps the parameter surface itself free of actor identity, so
-- a future signature cannot quietly start accepting "who am I" from the client.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and pg_get_function_identity_arguments(function.oid)
           ~ 'p_(actor|caller|principal|created_by|updated_by)'),
  0,
  'SR-06: no public RPC accepts an actor identity as a parameter'
);

-- public.upsert_required_document(..., p_owner_user_id uuid, ...) does take a
-- user id, but as a business assignment -- who owes the document -- not as an
-- identity. It must never reach an authorization predicate.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and pg_get_functiondef(function.oid) ~ 'has_workspace_permission\([^)]*p_owner_user_id'),
  0,
  'SR-06: p_owner_user_id never feeds an authorization predicate'
);

-- === DEC-016: privileged capabilities keep their server-side AAL2 gate ===

-- pg_depend does not record calls made from a plpgsql body, so a dependency walk
-- cannot see which RPC reaches the gate. The definition is the only available
-- evidence, so it is used -- but as an invariant over the whole schema rather
-- than a spot check: whatever set of functions mutates membership state, all of
-- them must route through the gate.
select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and pg_get_functiondef(function.oid)
           ~* '(insert into|update|delete from)\s+public\.(memberships|membership_invitations)'
     and pg_get_functiondef(function.oid) !~ 'private\.membership_command_gate'),
  0,
  'SR-12: every RPC that mutates membership state routes through the membership command gate'
);

-- and the gate it routes through must still be the thing that enforces AAL2
select ok(
  (select pg_get_functiondef(function.oid) ~ 'aal2'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'membership_command_gate'),
  'SR-12: the membership command gate still enforces aal2'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and pg_get_functiondef(function.oid)
           ~* '(insert into|update|delete from)\s+public\.(memberships|membership_invitations)'),
  5,
  'SR-12: the DEC-016 membership capability set is still the audited five'
);

-- === No dynamic SQL anywhere in the authorization surface ===============

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.prokind = 'f'
     and pg_get_functiondef(function.oid) ~* '(^|[^a-z_])execute\s+(format|''|"|quote_)'),
  0,
  'SR-08: no function in the authorization surface builds and executes dynamic SQL'
);

-- === SR-02: a caller without an identity gets nothing ===================

-- The feature suites drive RPCs with a sub claim present. This drives one with
-- the claim absent, which is what an unauthenticated-but-role-bearing request
-- looks like, and proves the gate refuses rather than treating null as a match.
-- The property below is never created: the call must fail before touching it.
select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal2"}', true);
set local role authenticated;

select is(
  public.update_property(
    '00000000-0000-0000-0000-0000000000f1'::uuid,
    '00000000-0000-0000-0000-0000000000f2'::uuid,
    1,
    '00000000-0000-0000-0000-0000000000f3'::uuid,
    '00000000-0000-0000-0000-0000000000f4'::uuid,
    '{"name":"identity-less caller"}'::jsonb,
    null
  ) #> '{error}',
  -- Asserting the message, not just the code: a missing workspace would also
  -- answer "forbidden", so the code alone could pass for the wrong reason. Only
  -- the null-identity branch produces this exact payload.
  '{"code": "forbidden", "message": "Authentication required"}'::jsonb,
  'SR-02: an authenticated request without a sub claim is refused for lack of identity'
);

reset role;
reset request.jwt.claims;

-- === The AAL2 boundary stays central ====================================
--
-- SECURITY-AAL-ENFORCEMENT-01. The behavioural proof lives in 027; these are
-- the structural gates, and they turn red when a *new* RPC or policy is added
-- without the boundary -- which no behavioural test can see.
--
-- Two different mechanisms, deliberately. For policies, pg_depend genuinely
-- records the functions an expression references, so the check below is a
-- catalogue dependency: reformatting the expression or renaming through a
-- wrapper cannot evade it. For functions it cannot -- pg_depend does not
-- record calls made from a plpgsql body, as SR-12 above already documents --
-- so there the definition text stays the only available evidence.

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.prokind = 'f'
     and function.prosecdef
     and pg_get_functiondef(function.oid) !~
           'private\.(has_workspace_permission|has_scoped_entity_permission|is_aal2|[a-z_]+_command_gate)'),
  0,
  'SR-21: every public RPC reaches the central AAL2/permission guard'
);

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.prokind = 'f'
     and function.proname like '%command_gate'
     and pg_get_functiondef(function.oid) !~ 'aal2'),
  0,
  'SR-21: every private command gate enforces aal2'
);

-- Asserted in the forward direction on purpose. The rollback suite proves the
-- predicate is absent before the migration; nothing proved it present after,
-- so deleting the call from the helper body would have left every other test
-- green while opening the whole read surface.
select ok(
  (select pg_get_functiondef(function.oid) ~ 'private\.is_aal2'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'has_workspace_permission'),
  'SR-21: the central permission helper still calls the assurance predicate'
);

select is(
  (select count(*)::integer
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname in ('public', 'storage', 'realtime')
     and not exists (
       select 1
       from pg_depend as dependency
       join pg_proc as guard on guard.oid = dependency.refobjid
       where dependency.classid = 'pg_policy'::regclass
         and dependency.objid = policy.oid
         and dependency.refclassid = 'pg_proc'::regclass
         and guard.proname in (
           'is_aal2', 'has_workspace_permission', 'has_scoped_entity_permission'
         )
     )
     and policy.polname not in (
       -- The single deliberate aal1 exception. It answers only about the
       -- caller's own identity row, carries no workspace data, and belongs to
       -- the bootstrap surface a password-only session must still reach.
       'user_profiles_select_own'
     )),
  0,
  'SR-22: every client-reachable policy binds the AAL2 guard or is a named aal1 exception'
);

-- Same intent as SR-20 for functions: a new policy is allowed, but it has to be
-- acknowledged in the pull request that adds it, which puts its USING and WITH
-- CHECK expressions in front of a reviewer.
select is(
  (select count(*)::integer
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname in ('public', 'storage', 'realtime')),
  49,
  'SR-22: the client-reachable policy inventory is still 49 -- update this expectation deliberately'
);

-- === SR-23: the document storage surface ================================
--
-- SECURITY-STORAGE-AAL-03. The behavioural proof runs through the real Storage
-- HTTP API in supabase_storage_aal_integration_test.dart; these are the
-- structural pins that make a silent widening of the surface impossible.
--
-- The bucket's policy family is identified through pg_depend rather than by
-- searching the expression text for 'documents': every policy for this bucket
-- reaches private.document_storage_workspace to derive the owning workspace, so
-- the dependency *is* the membership test, and reformatting cannot evade it.

select is(
  (select count(*)::integer
   from storage.buckets
   where id = 'documents' and public = false),
  1,
  'SR-23: the documents bucket exists and is private'
);

-- Exactly one SELECT and one INSERT, and nothing else. The absence of UPDATE
-- and DELETE is what makes DOM-006 immutability structural rather than
-- conventional, so it is asserted as an exact set, not as "at least".
select is(
  (select coalesce(string_agg(distinct policy.polcmd::text, ',' order by policy.polcmd::text), '(none)')
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'storage'
     and class.relname = 'objects'
     and exists (
       select 1
       from pg_depend as dependency
       join pg_proc as parser on parser.oid = dependency.refobjid
       where dependency.classid = 'pg_policy'::regclass
         and dependency.objid = policy.oid
         and dependency.refclassid = 'pg_proc'::regclass
         and parser.proname = 'document_storage_workspace'
     )),
  'a,r',
  'SR-23: the documents bucket has exactly one INSERT and one SELECT policy, no UPDATE and no DELETE'
);

-- Both of them must reach the central permission helper, which is where the
-- AAL2 predicate lives since SECURITY-AAL-ENFORCEMENT-01. A policy that kept
-- the parser but dropped the helper would still scope by workspace while
-- silently losing the assurance boundary.
select is(
  (select count(*)::integer
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'storage'
     and class.relname = 'objects'
     and exists (
       select 1
       from pg_depend as dependency
       join pg_proc as parser on parser.oid = dependency.refobjid
       where dependency.classid = 'pg_policy'::regclass
         and dependency.objid = policy.oid
         and dependency.refclassid = 'pg_proc'::regclass
         and parser.proname = 'document_storage_workspace'
     )
     and not exists (
       select 1
       from pg_depend as dependency
       join pg_proc as guard on guard.oid = dependency.refobjid
       where dependency.classid = 'pg_policy'::regclass
         and dependency.objid = policy.oid
         and dependency.refclassid = 'pg_proc'::regclass
         and guard.proname = 'has_workspace_permission'
     )),
  0,
  'SR-23: every documents bucket policy reaches the AAL2-inheriting permission helper'
);

-- A new policy on storage.objects has to be acknowledged in the pull request
-- that adds it, exactly like SR-20 for functions and SR-22 for public policies.
-- Four since PROPERTY-MEDIA-DATA-01 added a second private bucket: one SELECT
-- and one INSERT per bucket, and still no UPDATE and no DELETE anywhere.
select is(
  (select count(*)::integer
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'storage' and class.relname = 'objects'),
  4,
  'SR-23: the storage.objects policy inventory is still 4 -- update this expectation deliberately'
);

-- SR-24: no bucket may be written twice. Every storage policy in this system
-- is a SELECT or an INSERT; an UPDATE or DELETE policy would let a client
-- overwrite or remove bytes under a stable path, which is how a document
-- version or a property photo would stop being evidence.
select is(
  (select array_agg(distinct policy.polcmd::text order by policy.polcmd::text)
   from pg_policy as policy
   join pg_class as class on class.oid = policy.polrelid
   join pg_namespace as namespace on namespace.oid = class.relnamespace
   where namespace.nspname = 'storage' and class.relname = 'objects'),
  array['a', 'r'],
  'SR-24: every storage.objects policy is an INSERT or a SELECT, in every bucket'
);

-- The workspace prefix parser is the whole isolation story for this bucket: it
-- returns null for anything that is not workspace-prefixed, and
-- has_workspace_permission(null, ...) is false. A permissive parser would hand
-- every policy a workspace the caller does not own.
select is(
  (select count(*)::integer
   from (values
     ('not-a-uuid/doc/1/file.pdf'),
     ('file.pdf'),
     ('../51000000-0000-0000-0000-000000000001/doc/1/file.pdf'),
     ('51000000-0000-0000-0000-000000000001-suffix/doc/1/file.pdf'),
     ('')
   ) as candidate(name)
   where private.document_storage_workspace(candidate.name) is not null),
  0,
  'SR-23: the storage workspace parser fails closed for every malformed name'
);

select is(
  private.document_storage_workspace(
    '51000000-0000-0000-0000-000000000001/doc/1/file.pdf'
  ),
  '51000000-0000-0000-0000-000000000001'::uuid,
  'SR-23: and still parses a well-formed workspace prefix'
);

select * from finish();

rollback;
