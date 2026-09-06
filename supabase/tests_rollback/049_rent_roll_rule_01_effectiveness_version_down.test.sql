begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back RENT-ROLL-RULE-01 removes the marker and returns the three
-- functions that carry it to the definitions they had before.
--
-- What that means, stated rather than left to be discovered: the reverted
-- database still computes under rule 2 -- LEASING-ASOF-01 is a separate
-- migration and is untouched here -- it simply stops saying so. That is the
-- state this package was written to end, and it is the correct end state for a
-- rollback: reverting the labelling must not revert the rule, or a rollback
-- would silently change published figures.
--
-- The snapshot table and its immutability triggers belong to P2-D05; this
-- package only added a column to them.

select plan(13);

select hasnt_function('private', 'rent_roll_effectiveness_rule_version',
  'the version constant is removed');

select hasnt_column('public', 'rent_roll_snapshots', 'effectiveness_rule_version',
  'and the marker is off the frozen header');
select is(
  (select count(*)::integer
   from pg_constraint
   where conrelid = 'public.rent_roll_snapshots'::regclass
     and conname = 'rent_roll_snapshots_effectiveness_rule_version_check'),
  0,
  'its check constraint goes with it -- a rollback that left half the change '
  'behind would leave the schema in a state no migration describes'
);

-- The table and the three functions survive: this package replaced them, never
-- created them.
select has_table('public', 'rent_roll_snapshots',
  'the snapshot table survives: P2-D05 owns it');
select has_function('public', 'create_rent_roll_snapshot',
  'and the command that writes one');
select has_function('private', 'rent_roll_snapshot_header',
  'and the header projection');
select has_function('public', 'rent_roll_live',
  'and the live read');

select ok(
  (select pg_get_functiondef(function.oid) not like '%effectiveness_rule_version%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'create_rent_roll_snapshot'),
  'the writer no longer names a rule version'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%effectiveness_rule_version%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private'
     and function.proname = 'rent_roll_snapshot_header'),
  'nor does the frozen document'
);
select ok(
  (select pg_get_functiondef(function.oid) not like '%effectiveness_rule_version%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'rent_roll_live'),
  'nor the live read'
);

-- The rule itself is a different migration and must be exactly where it was.
select has_function('private', 'lease_is_effective_on',
  'the effectiveness predicate survives untouched: LEASING-ASOF-01 owns it, '
  'this package only gave its revision a number'
);
select ok(
  (select pg_get_functiondef(function.oid) like '%lease_is_effective_on%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'private' and function.proname = 'rent_roll_unit_rows'),
  'and the helpers still ask it, so the reverted database computes rule 2 and '
  'merely stops naming it'
);

-- AGG-007 is P2-D05's, and nothing here went near it.
select is(
  (select count(*)::integer
   from pg_trigger as trigger
   where trigger.tgrelid = 'public.rent_roll_snapshots'::regclass
     and not trigger.tgisinternal),
  2,
  'the update and delete rejection triggers survive: a snapshot is still '
  'immutable'
);

select * from finish();

rollback;
