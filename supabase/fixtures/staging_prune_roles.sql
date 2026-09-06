-- Removes a role the documented model does not have and nobody holds.
--
-- Applied only by `.github/workflows/staging_seed.yml` in `prune-roles` mode,
-- behind the same gates as everything else that touches staging.
--
-- **Why this exists.** The first inventory (DEC-030) turned up a sixth role on
-- staging, `property_manager`, carrying exactly `workspace.read`,
-- `property.read` and `property.update`. The documented model has five —
-- `admin`, `manager`, `analyst`, `operations`, `viewer` — and
-- `supabase/tests/030_permission_catalog.test.sql` pins that as exhaustive.
-- The permission trio matches `supabase/tests_integration/p1_011_setup.sql`
-- exactly, so the role reached the staging workspace through the manual
-- golden-path provisioning, copied from a test fixture. It is not a privilege
-- escalation; it is a divergence between the documented model and the running
-- environment, and a divergence nobody planned is the kind that later gets
-- mistaken for intent.
--
-- **What it will and will not do.** It removes a role only when *all three*
-- hold:
--
--   1. its key is not one of the five the seeder creates,
--   2. no active membership holds it, and
--   3. it is not the workspace's only role.
--
-- Anything else and it refuses loudly rather than deciding. In particular it
-- will not touch a role somebody is using, because that would silently strip
-- a member's access — the opposite of the fail-closed posture everything else
-- here holds. Suspended memberships count as holders too: a suspended member
-- is expected to come back to the access they had.
--
-- It is idempotent: a second run finds nothing to do and says so.

do $prune$
declare
  v_ws          uuid;
  v_role        record;
  v_removed     integer := 0;
  v_kept        integer := 0;
begin
  select w.id into v_ws from public.workspaces as w order by w.created_at limit 1;
  if v_ws is null then
    raise exception 'Kein Workspace vorhanden.';
  end if;

  for v_role in
    select r.id, r.key,
           (
             select count(*) from public.memberships as m
             where m.workspace_id = r.workspace_id and m.role_id = r.id
           ) as holders
    from public.roles as r
    where r.workspace_id = v_ws
      and r.key not in ('admin', 'manager', 'analyst', 'operations', 'viewer')
    order by r.key
  loop
    if v_role.holders > 0 then
      -- Named, not silently skipped: somebody is using it, and that is a
      -- decision for a person rather than for this script.
      raise warning
        'Rolle "%" wird NICHT entfernt: % Mitgliedschaft(en) halten sie. '
        'Erst umhaengen, dann erneut laufen lassen.',
        v_role.key, v_role.holders;
      v_kept := v_kept + 1;
      continue;
    end if;

    if (select count(*) from public.roles where workspace_id = v_ws) <= 1 then
      raise exception
        'Rolle "%" waere die letzte im Workspace — abgebrochen.', v_role.key;
    end if;

    delete from public.role_permissions
    where workspace_id = v_ws and role_id = v_role.id;
    delete from public.roles
    where workspace_id = v_ws and id = v_role.id;

    raise notice 'Rolle "%" entfernt (keine Mitgliedschaft).', v_role.key;
    v_removed := v_removed + 1;
  end loop;

  if v_removed = 0 and v_kept = 0 then
    raise notice
      'Keine Rolle ausserhalb des dokumentierten Modells gefunden — nichts zu tun.';
  else
    raise notice 'Fertig: % entfernt, % behalten.', v_removed, v_kept;
  end if;
end;
$prune$;
