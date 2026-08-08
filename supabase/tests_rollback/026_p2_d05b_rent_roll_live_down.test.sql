begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

-- P2-D05b adds a read and nothing else: one public function, one private
-- helper, no table, no column, no grant on data. The down path therefore has to
-- leave the whole P2-D05 rent roll exactly as it was — if rolling back a
-- read-only addition could damage the frozen documents, the addition was not
-- read-only.

select hasnt_function('public', 'rent_roll_live', array['uuid', 'uuid', 'date'],
  'the live read is removed');
select hasnt_function('private', 'rent_roll_unit_currencies',
  array['uuid', 'uuid', 'date'], 'its per-unit currency helper is removed');

-- The shared computation belongs to P2-D05 and must survive: create_rent_roll_
-- snapshot still depends on it.
select has_function('private', 'rent_roll_unit_rows', array['uuid', 'uuid', 'date'],
  'the shared unit computation remains');
select has_function('private', 'rent_roll_currencies', array['uuid', 'uuid', 'date'],
  'the shared currency helper remains');
select has_function('public', 'create_rent_roll_snapshot',
  array['uuid', 'uuid', 'date', 'uuid', 'uuid', 'text', 'text'],
  'freezing a snapshot still works');

select ok(
  (select bool_and(class.relrowsecurity and class.relforcerowsecurity)
   from pg_class as class
   where class.oid in (
     'public.rent_roll_snapshots'::regclass,
     'public.rent_roll_snapshot_lines'::regclass
   )),
  'the frozen documents keep their row level security'
);

select * from finish();

rollback;
