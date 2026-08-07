begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

-- P2-X01-AP4 stage 3 deposit status is removed on the down path. The migration
-- is purely additive, so the P2-D05 lease contract must remain untouched.

select hasnt_column('public', 'leases', 'deposit_status', 'deposit_status is removed');
select ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.leases'::regclass
      and conname in (
        'leases_deposit_status_check',
        'leases_deposit_status_requires_amount_check'
      )
  ),
  'the deposit status constraints are removed'
);

select has_table('public', 'leases', 'P2-D05 leases remains');
select has_column('public', 'leases', 'security_deposit', 'the deposit amount remains');
select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.leases'::regclass),
  'row level security remains enabled and forced'
);

select * from finish();

rollback;
