-- DEBT-012 / W1-AP9: Supabase parity for the property tombstone.
--
-- On the SQLite core a property "tombstone" is a restorable soft-delete that
-- keeps the row and all children, hides the object from active reads, retains
-- it for audit, and records the acting user in deleted_by. The Supabase
-- property contract (P1-004) already expresses that semantics through the
-- archived status: update_property(status => 'archived') sets deleted_at,
-- keeps the row (there is no cascade delete), is hidden from active reads, is
-- restorable by un-archiving, and is audited append-only. This migration
-- closes the one remaining parity gap -- the acting user of the soft-delete --
-- additively, without touching the P1-004 update_property core, so archive
-- stays the tombstone.

alter table public.properties
  add column deleted_by uuid;

comment on column public.properties.deleted_by is
  'User that tombstoned (archived) the property; null while active. Populated '
  'from auth.uid() on the archive transition and cleared on restore.';

-- Keep deleted_by in lockstep with the existing deleted_at tombstone marker
-- without editing the P1-004 mutation core: a trigger records the acting user
-- when the row transitions into the tombstone and clears it on restore. The
-- deleter is preserved across further updates that keep the row tombstoned.
create function private.properties_apply_delete_marker()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.deleted_at is null then
    -- Active or restored row: there is no deleter.
    new.deleted_by := null;
  elsif tg_op = 'INSERT' or old.deleted_at is null then
    -- Transition into the tombstone: record the acting user. auth.uid() is
    -- null outside a request context (e.g. direct fixtures or seeds), which is
    -- acceptable -- deleted_by is best-effort actor metadata, not a gate.
    new.deleted_by := auth.uid();
  else
    -- Already tombstoned and staying so: preserve the original deleter.
    new.deleted_by := old.deleted_by;
  end if;
  return new;
end;
$$;

alter function private.properties_apply_delete_marker() owner to postgres;

create trigger properties_apply_delete_marker
before insert or update on public.properties
for each row execute function private.properties_apply_delete_marker();
