-- P2-X01-AP4 stage 3: the deposit status required for the legacy lease cutover.
--
-- The legacy core tracks whether a security deposit has actually been paid.
-- The P2-D05 lease contract stores the deposit amount but not its payment
-- state, so migrating leases without this column would drop a fact that is
-- populated on 12 of 12 source rows (11 `open`, 1 `paid`) — the same class of
-- silent loss the AP4 property attributes migration closed.
--
-- Additive and nullable: the P2-D05 mutation core, the lease status machine and
-- the row-level policies are untouched. Grants are table-wide and policies are
-- row-scoped, so the column inherits the existing default-deny posture without
-- a new policy.
--
-- The allowed values are exactly the two the legacy core produces. Deliberately
-- not a wider guess: a future state (partial, returned) should arrive with the
-- workflow that produces it, not as an unused placeholder.

alter table public.leases
  add column deposit_status text;

alter table public.leases
  add constraint leases_deposit_status_check check (
    deposit_status is null or deposit_status in ('open', 'paid')
  );

-- A payment state without a deposit would describe money that does not exist.
alter table public.leases
  add constraint leases_deposit_status_requires_amount_check check (
    deposit_status is null or security_deposit is not null
  );

comment on column public.leases.deposit_status is
  'Payment state of the security deposit: open (owed) or paid. Null when the '
  'lease carries no deposit or the state is unknown. Migrated from the legacy '
  'leases.deposit_status column.';
