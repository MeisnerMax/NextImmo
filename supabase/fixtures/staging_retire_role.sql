-- Hängt die Mitgliedschaften einer nicht dokumentierten Rolle auf eine
-- dokumentierte um, damit `staging_prune_roles.sql` sie danach entfernen kann.
--
-- Angewendet ausschliesslich von `.github/workflows/staging_seed.yml` im Modus
-- `retire-role`, hinter denselben Gates wie alles andere, was Staging anfasst.
--
-- **Warum es das gibt.** Die Prune-Fixture weigert sich — absichtlich —, eine
-- *gehaltene* Rolle zu loeschen: das naehme jemandem lautlos den Zugang. Der
-- erste Prune-Lauf (2026-09-06) fand genau diesen Fall, `property_manager` mit
-- einer aktiven Mitgliedschaft, und liess sie stehen. Der Eigentuemer hat
-- daraufhin entschieden, dass es sein altes Ansichts-Konto ist und die Rolle
-- weg soll. Damit ist die fehlende Faehigkeit nicht "haerter loeschen", sondern
-- "den Halter zuerst dokumentiert umhaengen" — und das ist eine allgemeine,
-- wiederverwendbare Verwaltungsoperation, keine Einzelfall-Ausnahme.
--
-- **Parameter.** Der Workflow legt vor dieser Datei eine Tabelle
-- `pg_temp._retire_params(role_key, target_role_key)` an. Er validiert beide
-- Werte vorher gegen ein striktes Muster; diese Datei validiert sie ein zweites
-- Mal, weil eine Fixture, die sich auf ihren Aufrufer verlaesst, beim naechsten
-- Aufrufer falsch ist.
--
-- **Was sie tut und was nicht.**
--   * Sie haengt nur Mitgliedschaften der Quellrolle um — keine anderen.
--   * Die Quellrolle darf keine der fuenf dokumentierten sein.
--   * Die Zielrolle muss eine der fuenf sein und existieren.
--   * Sie loescht keine Mitgliedschaft und kein Konto. Wer die Rolle hielt,
--     behaelt Zugang, nur mit den Rechten der Zielrolle.
--   * Sie entfernt die Rolle selbst *nicht*. Das bleibt Aufgabe von
--     `staging_prune_roles.sql`, das dafuer seine eigenen drei Bedingungen
--     prueft. Zwei enge Schritte statt eines breiten.
--
-- **Berichterstattung.** Das Ergebnis ist ein Result-Set, kein `raise notice`.
-- Der Lauf vom 2026-09-06 hat bewiesen, dass `supabase db query --linked`
-- Servermeldungen verwirft: die Fixture handelte korrekt und sagte es
-- niemandem. Was der Workflow-Log nicht zeigt, ist nicht passiert — jedenfalls
-- nicht nachweisbar.
--
-- Sie ist idempotent: ein zweiter Lauf findet die Quellrolle nicht mehr oder
-- ohne Halter und meldet genau das.

drop table if exists pg_temp._retire_report;
create temporary table _retire_report (
  outcome    text not null,
  role_key   text,
  target_key text,
  moved      integer not null default 0,
  detail     text
);

do $retire$
declare
  v_role_key   text;
  v_target_key text;
  v_ws         uuid;
  v_role       uuid;
  v_target     uuid;
  v_moved      integer := 0;
  c_documented constant text[] :=
    array['admin', 'manager', 'analyst', 'operations', 'viewer'];
begin
  select p.role_key, p.target_role_key
  into v_role_key, v_target_key
  from pg_temp._retire_params as p;

  if v_role_key is null or v_target_key is null then
    raise exception 'Parameter fehlen: _retire_params ist leer.';
  end if;

  -- Zweite Validierung, unabhaengig vom Aufrufer.
  if v_role_key = any (c_documented) then
    raise exception
      'Quellrolle "%" gehoert zum dokumentierten Modell und wird nicht '
      'zurueckgebaut.', v_role_key;
  end if;
  if not (v_target_key = any (c_documented)) then
    raise exception
      'Zielrolle "%" gehoert nicht zum dokumentierten Modell.', v_target_key;
  end if;

  select w.id into v_ws from public.workspaces as w order by w.created_at limit 1;
  if v_ws is null then
    raise exception 'Kein Workspace vorhanden.';
  end if;

  select r.id into v_role
  from public.roles as r
  where r.workspace_id = v_ws and r.key = v_role_key;

  if v_role is null then
    insert into _retire_report (outcome, role_key, target_key, moved, detail)
    values ('absent', v_role_key, v_target_key, 0,
            'Rolle existiert im Workspace nicht — nichts umzuhaengen.');
    return;
  end if;

  select r.id into v_target
  from public.roles as r
  where r.workspace_id = v_ws and r.key = v_target_key;

  if v_target is null then
    raise exception
      'Zielrolle "%" existiert im Workspace nicht — abgebrochen, bevor '
      'jemand ohne Rolle dasteht.', v_target_key;
  end if;

  -- `role_id` ist auf memberships nicht immutable (nur id, workspace_id,
  -- user_id, created_at, created_by sind es), und UNIQUE (workspace_id,
  -- user_id) garantiert, dass niemand schon eine zweite Mitgliedschaft in
  -- derselben Workspace hat, mit der das hier kollidieren koennte.
  -- `memberships_entitlement_broadcast` feuert bei role_id-Wechsel und schickt
  -- dem betroffenen Konto eine Revalidierung, die Sitzung zieht also nach.
  update public.memberships as m
  set role_id = v_target,
      updated_at = now(),
      version = m.version + 1
  where m.workspace_id = v_ws and m.role_id = v_role;
  get diagnostics v_moved = row_count;

  insert into _retire_report (outcome, role_key, target_key, moved, detail)
  values (
    case when v_moved > 0 then 'moved' else 'no_holders' end,
    v_role_key, v_target_key, v_moved,
    case
      when v_moved > 0 then
        'Mitgliedschaft(en) auf die Zielrolle umgehaengt; die Rolle ist jetzt '
        'ungehalten und fuer prune-roles freigegeben.'
      else
        'Rolle existiert, wird aber von niemandem gehalten — prune-roles '
        'haette sie ohnehin entfernt.'
    end
  );
end;
$retire$;

select jsonb_pretty(jsonb_build_object(
  'outcome', r.outcome,
  'role_key', r.role_key,
  'target_role_key', r.target_key,
  'memberships_moved', r.moved,
  'detail', r.detail
)) as retire_report
from _retire_report as r;
