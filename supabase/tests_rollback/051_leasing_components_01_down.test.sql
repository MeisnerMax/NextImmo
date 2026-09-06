begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back LEASING-COMPONENTS-01 (V-2).
--
-- This package only adds, so the revert only removes, and the assertions are
-- correspondingly plain. What is worth pinning is the other half: what the
-- revert must **not** take with it.
--
-- The three flat columns on `public.leases` are the case that matters.
-- DEC-029 keeps them as the inception figures the lease was signed at, and
-- this package deliberately did not migrate, shadow or deprecate them. A
-- revert that removed them — on the reasoning that components had replaced
-- them — would destroy the only record of what a lease started at, in a
-- direction no migration describes and no backup obviously covers.
--
-- `private.lease_is_effective_on` is the second. The as-of read leans on it,
-- but it belongs to LEASING-ASOF-01 (migration 50), and a revert that swept up
-- everything the read touched would silently reopen the rent-roll defect that
-- predicate was written to close.
--
-- `btree_gist` is asserted absent rather than present, and that is a statement
-- about the replay model rather than about extensions: CI reverts by rebuilding
-- the history up to N-1, and no earlier migration creates it. If a later
-- package needs it too, this expectation changes deliberately, in the pull
-- request that moves it.

select plan(13);

-- ---------------------------------------------------------------------------
-- Gone
-- ---------------------------------------------------------------------------

select hasnt_table('public', 'lease_components',
  'the component table is gone');

select is(
  (select count(*)::integer from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname in ('lease_component_type', 'lease_component_vat_mode')),
  0, 'and both enums with it -- a type left behind would block the replay');

select hasnt_function('public', 'create_lease_component',
  'the create command is gone');
select hasnt_function('public', 'update_lease_component',
  'the update command is gone');
select hasnt_function('public', 'close_lease_component',
  'the close command is gone');
select hasnt_function('public', 'lease_components_as_of',
  'the as-of read is gone');
select hasnt_function('private', 'apply_lease_component_update',
  'and the shared private write path behind the two commands');
select hasnt_function('private', 'enforce_lease_component_currency',
  'as well as the currency trigger function');

select is(
  (select count(*)::integer from pg_extension where extname = 'btree_gist'),
  0,
  'btree_gist is absent: nothing before this package created it, and the '
  'rollback replay rebuilds the history without it');

-- ---------------------------------------------------------------------------
-- Untouched
-- ---------------------------------------------------------------------------

select has_column('public', 'leases', 'base_rent_monthly',
  'the inception base rent survives the revert -- DEC-029 keeps these columns, '
  'and losing them would destroy what the lease was signed at');
select has_column('public', 'leases', 'ancillary_charges_monthly',
  'as does the ancillary figure');
select has_column('public', 'leases', 'parking_other_charges_monthly',
  'and the parking figure');

select has_function('private', 'lease_is_effective_on',
  'and LEASING-ASOF-01''s effectiveness predicate is still there: the as-of '
  'read used it, but never owned it');

select * from finish();
rollback;
