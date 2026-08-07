# Phase A — Cloud Foundation Stabilization: Arbeitsprotokoll

Fortlaufend. Ein Eintrag je Arbeitspaket mit Datum, Commit, Dateien, Entscheidung,
ausgeführten Tests, bekannten Abweichungen, offenen Risiken und nächstem Schritt
(Masterplan §29). Ein Arbeitspaket wird nur `done`, wenn seine Gates **ausgeführt**
und bestanden wurden.

---

## 2026-08-07 · A0 — Working Tree stabilisiert

**Commits:** `388e719` (Parkbranch), `0337e65`

**Ausgangslage:** `flutter analyze --no-pub` war **rot**. Vier uncommittete Dateien
enthielten eine unfertige Entfernung von `GlobalPage.compare`.

**Entscheidung (Nutzer):** stabilisieren, ohne die fachliche Frage zu entscheiden.
Da `test/ui/navigation/app_navigation_test.dart:118` den Szenariovergleich weiterhin
in der Navigationsgruppe erwartet, hätte ein reiner Switch-Fix den Analyzer grün und
die Suite rot gemacht. Der unfertige Stand wurde deshalb vollständig geparkt statt
teilweise repariert.

**Dateien:** `lib/ui/navigation/app_navigation.dart`, `lib/ui/navigation/navigation_actions.dart`
(geparkt) · `lib/ui/screens/maintenance/maintenance_tickets_panel.dart`,
`test/ui/screens/maintenance/maintenance_tickets_panel_test.dart` (übernommen, committet)

**Aufbewahrung:** Branch `wip/compare-removal-2026-08-07`, Tag
`archive/wip-compare-removal-2026-08-07`. Nichts verworfen.

**Tests:** `flutter analyze --no-pub` grün · `flutter test --no-pub` **1482 grün / 18 Skips**

**Offen:** Die Entscheidung über den Szenariovergleich gehört zu `P2-X02` `AP-X02-5`.
`phase_2/04e` Z. 67 führt sie als „offen"; `phase_2/04y` `AP-X02-5` führt `compare`
weiter als Migrationsziel. Beide Stellen sind beim Entscheiden anzugleichen.

---

## 2026-08-07 · A2 — Branch-Konsolidierung

**Commits:** `6420ab0` (Merge)

**Befund:** Der Entwicklungshead war das lokale `main` (15 voraus / 3 zurück gegenüber
`origin/main`), **nicht** `docs/add-claude-md`. Die drei Gegen-Commits berühren
ausschließlich `marketing/`.

**Handlung:** Sicherungstag `pre-cloud-stabilization-2026-08-07` auf `6ad3431`;
Arbeitsbranch `cloud/foundation-stabilization`; `origin/main` additiv gemergt,
**null Konflikte**. Kein Rebase, kein Force-Push, keine History-Rewrites.

**Archiviert:** `archive/docs-add-claude-md` (`9675e4a`, feingranulare Phase-2-Historie,
die `main` durch den Checkpoint-Commit `25f6269` verloren hat),
`archive/codex-setze-neues-design-um` (`1da5433`, keine eigenen Commits).

**Tests:** `flutter analyze --no-pub` grün nach dem Merge.

**Offen:** Branches und Worktrees dürfen erst gelöscht werden, **nachdem** die Tags
gepusht sind — bis dahin existiert die archivierte Historie nur lokal.

---

## 2026-08-07 · A1/A3/A4 — Audit, CI-Härtung, Deployment-Trennung

**Commit:** `93cc7a6`

**Dateien:** `docs/architecture/cloud/00_repository_audit.md` (neu),
`.github/workflows/flutter.yml`, `.github/workflows/web_deploy.yml` (neu),
`.github/dependabot.yml` (neu), `.gitignore`, `marketing/vercel.json` (neu)

**Entscheidungen:**
- Die Flutter-Web-App wird **in GitHub Actions** gebaut und prebuilt zu Vercel
  deployt, nicht im Vercel-Build-Image. Begründung: dort existiert keine
  Flutter-Toolchain, und ein nachinstalliertes SDK würde von der in CI gepinnten
  Version abdriften.
- Der Deploy-Workflow bekommt **keinen** Production-Pfad. Production bleibt eine
  manuelle, geprüfte Promotion.
- Der zweite Web-Build in `verify` nutzt bewusst die Werte des lokalen Stacks:
  deterministisch, ohne Secrets, und ausreichend, um den Cloud-Entrypoint zu
  kompilieren.

**Tests:** `marketing`: `npm ci` + `npm run build` grün (8 statische Routen) ·
`flutter analyze --no-pub` grün · `marketing/.env.example` weiterhin getrackt und von
den neuen Ignore-Regeln nicht erfasst (`git check-ignore` negativ).

**Nicht verifizierbar aus dieser Sitzung:** die neuen CI-Jobs selbst. `gh` ist nicht
authentifiziert, YAML-Parser lokal nicht verfügbar; die Struktur wurde manuell geprüft.
Erster echter Nachweis ist der PR-Lauf.

---

## 2026-08-07 · A5 — Cloud-Build im Browser (teilweise)

**Aufbau:** lokaler Supabase-Stack (`API_URL http://127.0.0.1:54321`) plus
`.claude/launch.json`-Profil `neximmo-cloud`
(`NEXIMMO_ENV=local`, `NEXIMMO_DATA_BACKEND=supabase`).

**Verifiziert:**
- Der Cloud-Entrypoint kompiliert und bootet (`flutter-view` im DOM).
- `supabase.supabase_flutter: INFO: ***** Supabase init completed *****` bei jedem Laden.
- Konsole nach Service-Worker-Refresh **fehlerfrei**. Die anfänglichen
  `web_entrypoint.dart.js`-MIME-Fehler stammten von einem veralteten Service Worker
  einer früheren Sitzung und traten nach dessen Deregistrierung nicht wieder auf.
- Deep Link: Kaltstart auf `/properties` bootet fehlerfrei, die URL bleibt erhalten
  (kein Rewrite auf `/`).
- Reload: drei aufeinanderfolgende Ladevorgänge, jeweils sauber.

**Nicht verifiziert:** Auth-Smoke-Test, Workspace-Auswahl, Route-Klickpfad und jede
visuelle Prüfung. Der Browser-Tab lief im Hintergrund (`visibilityState: hidden`),
weshalb Flutter keine Frames baut und der Semantics-Baum leer bleibt. Der interaktive
Teil braucht einen sichtbaren Browser-Pane.

**Status:** `partial`.

---

## 2026-08-07 · A2 (Fortsetzung) — Push, Archivierung, Aufräumen

**Gepusht:** Branch `cloud/foundation-stabilization` (`bdddef8`) sowie alle vier Tags.
Remote existieren damit nur noch `main` und `cloud/foundation-stabilization`.

**Gelöscht (lokal und remote):** `docs/add-claude-md`, `codex/setze-neues-design-um`.
Beide sind vollständig durch gepushte Tags abgedeckt und jederzeit wiederherstellbar.

**Abbruch: Worktrees bleiben unangetastet.** Die geplante Worktree-Bereinigung wurde
gestoppt, weil zwei der drei Worktrees ungesicherte Arbeit enthalten:

| Worktree | Branch | Ungesichert |
|---|---|---|
| `.claude/worktrees/codex-ai-ph00-baseline` | `codex/ai-ph00-baseline` | **11 modifizierte, 6 untracked Pfade.** Darunter ein vollständiges `docs/ai/`-Set (Masterplan, Execution-Prompt, Implementation-Backlog, Test-/Acceptance-Plan), `lib/ui/shell/cloud_app_scaffold.dart` samt Test, und die Migration `20260802190000_ph01_entity_scope_enforcement.sql` mit pgTAP- und Rollback-Test. Zusätzlich geändert: `.github/workflows/flutter.yml`, `supabase/config.toml`, `11_decision_register.md`, `07_security_and_tenancy_baseline.md`, `lib/app.dart` |
| `.claude/worktrees/exciting-lamport-6ffa71` | `claude/exciting-lamport-6ffa71` | `lib/ui/screens/property_detail/property_tasks_screen.dart` modifiziert |
| `.claude/worktrees/hungry-shamir-795855` | detached `bacc36a` | nichts (`bacc36a` ist Vorfahr von `main`) |

Kein Tag und kein Commit deckt diese Arbeit ab. Vor jeder Entfernung ist zu klären,
ob `docs/ai/` und die `ph01_entity_scope_enforcement`-Migration in die Cloud-Planung
gehören oder verworfen werden — das ist eine fachliche Entscheidung, keine Aufräumarbeit.
Insbesondere ändert dieser Worktree `.github/workflows/flutter.yml` und
`supabase/config.toml`, also genau Dateien, die Phase A ebenfalls angefasst hat.

---

## 2026-08-07 · A3 (Fortsetzung) — erster Hosted-CI-Lauf, Triage

PR [#1](https://github.com/MeisnerMax/NextImmo/pull/1) eröffnet. Erster Lauf: `marketing`
grün, `Web App Deploy` grün (Preflight erkennt fehlende Secrets und überspringt korrekt),
`verify`, `database` und `supply_chain` rot.

### Korrektur an Befund `F-08` des Audits

Die Annahme „für den Entwicklungshead existiert kein gehosteter Workflow-Lauf" ist
**falsch, aber schlimmer als gedacht**: Hosted CI läuft auf `main` und ist dort seit
**2026-07-18 durchgehend rot** — sechs aufeinanderfolgende Läufe, alle `failure`.
Es fehlte also nicht der Lauf, sondern die Reaktion darauf.

### C-01 — Sechs Golden-Tests des Reference Slice scheitern auf Linux

**Schweregrad:** hoch · **vorbestehend:** ja · **durch Phase A verursacht:** nein

`test/features/reference_slice/reference_slice_screen_test.dart`, je drei Breakpoints
in hell und dunkel. Auf `main` scheiterten am 2026-07-18 dieselben drei Hell-Goldens;
die drei Dunkel-Varianten kamen später dazu und scheitern genauso. Lokal auf Windows
sind alle grün.

Die Goldens wurden auf Windows erzeugt und liegen seit `3a7e5e8`/`25f6269` so im Baum.
Schriftrasterung unterscheidet sich zwischen Windows und dem Linux-Runner, deshalb ist
ein plattformübergreifend geteiltes Golden strukturell nicht haltbar.

**Empfohlene Auflösung:** Goldens einmalig **auf Linux** neu erzeugen und CI zur
Golden-Autorität machen — nicht erneut lokal regenerieren, das verschiebt den Fehler nur
auf die andere Plattform. `CLAUDE.md` verlangt bewusstes, nicht beiläufiges Regenerieren;
das ist hier erfüllt, sobald die Diff-Artefakte belegen, dass es reine Rasterung und kein
Layout-Regress ist. Der dafür nötige Artefakt-Upload ist mit `9ba1ebc` eingebaut.

### C-02 — Migration-Rollback-Replay stellt das Schema nicht sauber wieder her

**Schweregrad:** hoch · **vorbestehend:** ja · **durch Phase A verursacht:** nein

```
ERROR: duplicate key value violates unique constraint "permissions_key_unique"
DETAIL: Key (key)=(maintenance.read) already exists.
```

Nach den 27 `migration down`-Schritten und dem abschließenden `migration up` bricht der
finale `supabase test db --local` in 25 Dateien ab (`Bad plan. You planned N but ran M`,
`Failed: 0` — die Dateien sterben, sie scheitern nicht).

**Erste Diagnose war falsch** und wird hier korrigiert: vermutet wurden fehlende
`delete`-Anweisungen in den Down-Migrationen. Tatsächlich säen die Migrationen
`public.permissions` **bewusst nicht** — `20260806100000_p2_d06_maintenance_capex.sql`
Z. 35–38 sagt das ausdrücklich, damit die pgTAP-Fixtures ihren eigenen Rechtekatalog
anlegen können, ohne zu kollidieren.

**Tatsächliche Ursache, empirisch belegt:** `supabase migration down` führt einen
vollen Reset aus und spielt dabei `seed.sql` mit ein — es hat kein eigenes
`--no-seed`. Gemessen am lokalen Stack:

| Schritt | `count(*) from public.permissions` |
|---|---|
| `db reset --local --no-seed` | 0 |
| danach `migration down --local --last 1` | **29** (Ausgabe: `Seeding data from supabase/seed.sql...`) |

Der CI-Replay startet also in einer ungeseedeten Datenbank und wird durch den ersten
Down-Schritt stillschweigend zu einer geseedeten. Beim abschließenden Suite-Lauf
existiert der Rechtekatalog dann bereits, und jede pgTAP-Datei stirbt an
`permissions_key_unique`.

Das ist in diesem Repository ein bekanntes Muster: der Kopf von `seed.sql` beschreibt
genau diesen Pfad („The CLI's own migration-down/reset seeding path sends this file as
raw SQL … never caught because CI always resets with `--no-seed`").

**Auflösung:** keine Änderung an Migrationslogik nötig. `supabase/config.toml` bekommt
`[db.seed] enabled = false`. Das entspricht der dokumentierten Absicht — `seed.sql` ist
laut eigenem Kopf ein manuelles Bootstrap-Fixture, sein einziger Konsument
`tool/bootstrap_p2_x01_local.ps1` spielt es explizit per `psql` ein, und **alle**
`tool/verify_*.ps1`-Skripte sowie der CI-Job setzen ohnehin mit `--no-seed` zurück.
Nichts hängt an automatischem Seeding.

**Verifikation:** nach der Änderung bleibt `permissions` über `db reset --no-seed` und
`migration down` hinweg bei 0, und die Zeile `Seeding data from supabase/seed.sql...`
verschwindet.

### C-03 — Gitleaks meldete fünf Funde (behoben)

**Schweregrad:** niedrig · **durch Phase A verursacht:** ja (neuer Job)

Alle fünf Fehlalarme: der Publishable Key des lokalen Stacks in `.claude/launch.json`,
dieselbe Zeile zitiert im Audit-Dokument, und dreimal der Fixture-String
`'monthly-2026-07'` neben einem Feld `generatedKey`.

Behoben mit `9ba1ebc`: `.gitleaks.toml` mit drei eng gefassten Allowlist-Regexes,
Zitat im Audit redigiert, PR-Kommentare deaktiviert (brauchen `pull-requests: write`,
das der Workflow bewusst nicht vergibt). Service Role Key, Secret Key, DB-Passwort und
Access Token bleiben von den Default-Regeln vollständig abgedeckt.

---

## Offene Punkte am Ende dieses Blocks

| # | Punkt | Zuständig | Blockiert |
|---|---|---|---|
| 0 | Ungesicherte Arbeit im Worktree `codex-ai-ph00-baseline` sichten und entscheiden | Nutzer | Worktree-Bereinigung, evtl. Phase A selbst (berührt `flutter.yml` und `supabase/config.toml`) |
| 1a | `C-01` Goldens auf Linux neu erzeugen | Freigabe nötig | grüner CI, Merge von PR #1 |
| 1b | `C-02` Down-Migrationen um das Entfernen ihrer `permissions`-Zeilen ergänzen | Freigabe nötig (Migrationslogik) | grüner CI, Merge von PR #1 |
| 2 | Branch Protection auf `main` mit vier Required Checks | Nutzer (Repo-Settings) | A3 |
| 3 | Zweites Vercel-Projekt für die Flutter-Web-App plus Secrets | Nutzer | A4 |
| 4 | Interaktiver Golden-Path im sichtbaren Browser-Pane | gemeinsam | A5 |
| 5 | Entscheidung Szenariovergleich | Nutzer | `AP-X02-5` |
| 6 | `AP-X02-1`: Charter Z. 21 und `CLAUDE.md` an `DEC-024` angleichen | Umsetzung | `P2-X02` |
| 7 | `DEC-015`..`DEC-017` entscheiden | Nutzer | Phase C, jede nicht-lokale Umgebung |
