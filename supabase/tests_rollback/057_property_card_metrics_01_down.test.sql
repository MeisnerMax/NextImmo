begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back PROPERTY-CARD-METRICS-01 (P-1b).
--
-- One function, no schema. The revert is therefore plain — but the thing this
-- package reads is a *single-property* read that predates it, and the risk in
-- reverting a batch is taking the thing it batched. `property_overview` is
-- PROPERTY-OVERVIEW-DATA-01's, not this package's; losing it would blank the
-- property detail screen while only the card grid was meant to lose its
-- numbers.
--
-- The last two assertions are the ones that matter most. The migration
-- deliberately repeats the overview's counting expressions rather than sharing
-- them, and the equality test in `049` is what keeps the two honest -- so a
-- revert that damaged the overview would leave that guard with nothing to
-- compare against. Its grant is checked as well as its existence, because a
-- function that survives with its EXECUTE revoked looks intact in the catalogue
-- and fails for every caller.

select plan(6);

select hasnt_function('public', 'property_card_metrics',
  'the batch card read is gone -- this package created it and nothing else');

select has_function('public', 'property_overview',
  'the single-property overview stays: it is the older package, and the card '
  'grid losing its numbers must not blank the detail screen too');

select has_function('private', 'has_scoped_entity_permission',
  'and PH01''s entity scope stays -- reverting it here would drop the check '
  'that decides which properties a caller may see at all');

select has_function('private', 'has_workspace_permission',
  'as does the workspace permission check the sections are gated on');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname like 'property_card%'),
  0,
  'nothing card-shaped is left behind under another name');

select is(
  (select count(*)::integer
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   cross join lateral aclexplode(coalesce(function.proacl, '{}'::aclitem[])) as acl
   where namespace.nspname = 'public'
     and function.proname = 'property_overview'
     and acl.grantee = 'authenticated'::regrole
     and acl.privilege_type = 'EXECUTE'),
  1,
  'and the overview is still callable by authenticated. Presence is not '
  'enough: a revert that dropped and recreated it would leave the function '
  'there with its grant gone, and the detail screen would fail for everyone '
  'while the schema looked intact');

select * from finish();
rollback;
