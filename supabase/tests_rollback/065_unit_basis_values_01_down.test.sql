begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back UNIT-BASIS-VALUES-01 (P-2c).
--
-- This revert has one thing the previous ones did not: the package **dropped
-- and recreated a function it does not own**. `private.allocation_basis_
-- resolution` gained an as-of date, which a `create or replace` cannot do, so
-- P-2c dropped P-2b's three-argument version and built a four-argument one.
--
-- A revert therefore has to put P-2b's version back — and the failure mode
-- worth catching is the silent half of that: a rollback that leaves the
-- four-argument function standing, or leaves neither. The first would mean
-- `allocation_keys_as_of` calling a resolver that reads a table the revert has
-- just dropped; the second would mean P-2b's read is broken by the removal of
-- a package that came after it. Both are asserted by arity, not by name.

select plan(8);

select hasnt_table('public', 'unit_basis_values', 'the basis store is gone');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'unit_basis_values_as_of', 'upsert_unit_basis_value'
     )),
  0,
  'both public functions are gone');

select ok(
  (select count(*) = 0 from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'unit_basis_value_snapshot'),
  'and the private snapshot with them');

-- The neighbouring package's resolver. Exactly one must stand, and it must be
-- P-2b's three-argument version: four arguments would mean a resolver reading
-- a table this revert has just dropped.
select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'allocation_basis_resolution'),
  1,
  'exactly one allocation_basis_resolution stands — not two, and not none');

select is(
  (select function.pronargs::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'allocation_basis_resolution'),
  3,
  'and it is P-2b''s three-argument version: this package replaced it by drop '
  'and create, so the revert is P-2b''s own resolver, not an absence and not '
  'a resolver that still reads a dropped table');

select has_function('public', 'allocation_keys_as_of',
  'P-2b''s as-of read still stands');

select has_table('public', 'allocation_keys',
  'with its own table — a revert of a follow-up must not take the package it '
  'followed with it');

select has_table('public', 'units',
  'and the unit records stay: this package hung values off them and altered '
  'nothing about the units themselves');

select * from finish();
rollback;
