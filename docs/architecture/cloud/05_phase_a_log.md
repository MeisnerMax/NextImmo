# Phase A — Cloud Foundation Stabilization: Arbeitsprotokoll

Fortlaufend. Ein Eintrag je Arbeitspaket mit Datum, Commit, Dateien, Entscheidung,
ausgeführten Tests, bekannten Abweichungen, offenen Risiken und nächstem Schritt
(Masterplan §29). Ein Arbeitspaket wird nur `done`, wenn seine Gates **ausgeführt**
und bestanden wurden.

---

## 2026-08-08 · `AP-X02-2b` — SQLite als App-Laufzeit-Backend entfernt

**`SQLite removed as an application runtime backend. Two former runtime adapter implementations
remain only as non-runtime migration/test support, and legacy comparables remain deferred.`**

### Der Re-Audit hat einen Fehler im eigenen Audit gefunden

Der Audit vom 07.08. behauptete für Gruppe A „Migrations-Refs: keine". Falsch — die Suche deckte
`sqlite_to_postgres_*` und die Integrationstests nicht ab. Zwei der sieben Adapter haben
**Non-Runtime**-Abhängigkeiten, die §17 bzw. §15 des Auftrags ausdrücklich schützen:

| Adapter | Abhängigkeit | Warum sie zählt |
|---|---|---|
| `LegacySqliteDocumentRepositoryAdapter` | `sqlite_to_postgres_documents_compliance_dry_run_mapper.dart` | ruft `typeKeyFor(...)` an zwei Stellen — Migrationstooling, das nicht umgebaut werden darf |
| `LegacySqliteOperationsSignalsAdapter` | `supabase_operations_signals_integration_test.dart` | Paritätsnachweis Legacy ↔ Cloud, den der `database`-Job über `verify_p2_d05a_integration.ps1` fährt |

Beide Dateien bleiben — **unwired**. Das ursprüngliche Ziel „sieben Dateien gelöscht" war zu stark
formuliert; maßgeblich ist **Runtime-Erreichbarkeit**, nicht physische Existenz.

### Was entfernt wurde

Fünf Adapter und ihre fünf Testdateien, **5817 physische Dateizeilen** (3016 + 2801). Dazu der
`DataBackend.sqlite`-Zweig der Composition Root, der SQLite-Bootstrap in `main.dart`
(`sqfliteFfiInit`, `databaseFactoryFfi`, `AppDatabase`, `SecurityRepo.bootstrapDefaults`,
`StartupTaskService.runIfDue`, lokale DB-Provider) und der Backend-Split in `app.dart`.
Git-Diff: **+425 / −6970** über 17 Dateien.

`app.dart` verliert dabei nichts Sichtbares: der Cloud-Modus las die lokalen Settings ohnehin nie,
lief also schon vorher auf denselben Defaults (`comfort`, `dark`).

### Environment

`NEXIMMO_DATA_BACKEND` **bleibt** als Deployment-Guard, `DataBackend` behält genau ein Mitglied.
Fail-closed bei fehlendem, leerem, unbekanntem und dem stillgelegten `sqlite`-Wert, dazu bei
fehlender/ungültiger URL und fehlendem Key — 12 Fälle in `app_environment_test.dart`.

### Runtime Regression Guard

`test/app_runtime_guard_test.dart` (11 Fälle) prüft **die Wiring-Grenze, nicht die Existenz von
SQLite-Code**: keine `DataBackend.sqlite`, keine Legacy-Adapter und kein SQLite-Bootstrap in
`main.dart`, `app.dart`, `app_backend_wiring.dart`. Zwei Assertions sichern die Gegenrichtung —
Dry-Run-Mapper und Paritätstest **müssen** ihre Referenz auf die retained Adapter behalten, damit
niemand sie bei einem späteren Cleanup mitlöscht.

### Testdifferenz, vollständig aufgelöst

1464 → **1355** grün bei unverändert 24 Skips. Die 109 sind exakt erklärt, gemessen statt gezählt:

| Position | vorher | nachher | Δ |
|---|---|---|---|
| fünf gelöschte Legacy-Testdateien | 111 | 0 | −111 |
| `app_backend_wiring_test.dart` | 25 | 8 | −17 |
| `app_environment_test.dart` | 4 | 12 | +8 |
| `app_runtime_guard_test.dart` | 0 | 11 | +11 |

Eine bewusste Streichung darin: „refuses to build cloud overrides without a client" entfällt, weil
`client` jetzt ein nicht-nullbarer `required`-Parameter ist — aus einer Laufzeitprüfung wurde eine
Compile-Zeit-Garantie.

### Nebenbefunde

**Provider-Superset:** vorher Supabase 33, SQLite 28, **kein** Provider nur im SQLite-Zweig; die
fünf Mehr-Bindungen waren die Realtime-Invalidierungen. Endzustand unverändert 33 plus Comparables —
kein konsumierter Port bleibt ungebunden.

**Platform-Ports:** `platform_providers.dart` exponiert nur `taskRepositoryProvider`.
`NotificationPort`, `JobRepository`, `SearchIndexPort` sind implementiert, aber nie gebunden. Das
erlaubte die Entfernung — es macht sie fachlich **nicht** fertig.

**`DEBT-009` bleibt OPEN.** `StartupTaskService` ist aus der Laufzeit entfernt; ein Server-Scheduler
existiert weiterhin nicht.

### Verifikation

Analyzer sauber · volle Suite 1355 / 24 Skips · `verify_p2_d05a_integration.ps1` **Exit 0** (das
Paritäts-KEEP-Gate) · `verify_p2_d03_integration.ps1` Exit 0 · Documents-Dry-Run-Mapper-Test 21 grün
· beide Web-Builds grün · **Windows-Cloud-Build grün** (`neximmo_app.exe`).

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

**Gelöst (`b3d613a`).** Neuer Workflow `.github/workflows/goldens.yml`: lädt erst die
Diffs als Artefakt hoch, regeneriert dann mit `--update-goldens` auf ubuntu und prüft
abschließend, dass die neuen Bilder dort bestehen. Er triggert auf `goldens/**`-Pushes,
weil GitHub `workflow_dispatch` nur für Dateien anbietet, die bereits auf dem
Default-Branch liegen — dorthin kommt diese Datei erst, wenn CI grün ist, also genau
das, was sie behebt.

**Diff-Prüfung vor der Übernahme:** die `isolatedDiff`-Bilder zeigen ausschließlich
Glyphenkanten und Text-Unterstriche; nichts ist verschoben, nichts fehlt. `masterImage`
und `testImage` liegen in der Dateigröße um unter 100 Byte auseinander
(z. B. 46488 vs. 46479). Damit ist belegt: Rasterung, kein Layout-Regress. Erst danach
wurden die sechs PNGs ersetzt.

**Plattform-Gate:** die Golden-Tests laufen jetzt nur noch auf Linux
(`skip: !Platform.isLinux`). Ein Golden ist ein Byte-Vergleich; ihn gegen einen Renderer
laufen zu lassen, der ihn nie erzeugt hat, schlägt aus Gründen fehl, die nichts über den
Widget-Baum aussagen. Layout-, Overflow- und Verhaltenstests derselben Datei laufen
weiterhin überall. Lokal auf Windows: 13 grün, 6 übersprungen; volle Suite
**1476 grün / 24 Skips**.

Wer sie künftig neu erzeugen muss, pusht einen `goldens/**`-Branch — **nie** lokal
`--update-goldens`, das verschiebt die Diskrepanz nur auf die andere Plattform.

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

**Verifikation (`b3d613a`).** Nach der Änderung bleibt `permissions` über
`db reset --no-seed` und `migration down` hinweg bei 0, und `Seeding data from
supabase/seed.sql...` verschwindet. Anschließend wurde die **vollständige
CI-Rollback-Sequenz lokal nachgefahren** — 27 Down-Schritte mit ihren Rollback-Tests,
`migration up`, volle pgTAP-Suite:

| | vorher | nachher |
|---|---|---|
| Ergebnis | `Result: FAIL` | **`Result: PASS`** |
| Tests | 472 (25 Dateien sterben vorzeitig) | **1246** |
| Seed-Ereignisse im Replay | 27 | **0** |

**Keine Migrationsdatei wurde angefasst.**

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

## 2026-08-07 · Zweiter Hosted-CI-Lauf (`ada10fb`) und `C-04`

`verify` **success** — damit ist `C-01` hosted bestätigt, nicht nur lokal.
`marketing` **success**. `supply_chain` **failure**, aber an anderer Stelle als zuvor:
der Gitleaks-Schritt ist grün (die `.gitleaks.toml`-Allowlist greift, `C-03` geschlossen),
gescheitert ist `npm audit --audit-level=high`.

### `C-04` — High-Advisories in den Marketing-Abhängigkeiten

**Schweregrad:** hoch · **vorbestehend:** ja (seit `3656e60`, 2026-07-18) ·
**durch Phase A verursacht:** nein — der Job macht ihn beim ersten echten Lauf sichtbar

| Paket | Version im Baum | Befund |
|---|---|---|
| `next` | `16.2.10` (exakt gepinnt) | **9 High-Advisories**: Middleware/Proxy-Bypass im App Router, DoS über Server Actions, SSRF in Server Actions und in Rewrites, zwei Cache-Confusion-Fälle, unbegrenzte Server-Action-Payload in der Edge-Runtime, DoS in der Image-Optimization-API über SVGs, unauthentifizierte Offenlegung interner Server-Function-Endpunkte |
| `postcss` | `<=8.5.22` (transitiv) | XSS über unescaptes `</style>`, Pfad-Traversal und Arbitrary-File-Read über `sourceMappingURL` |
| `sharp` | `<0.35.0` (transitiv) | geerbte libvips-CVEs (`CVE-2026-33327/33328/35590/35591`) |
| `nanoid` | `<3.3.17` (transitiv) | Endlosschleife bei `size = 0` |

`npm audit fix --force` will `next@16.3.0` installieren und meldet „outside the stated
dependency range", weil `marketing/package.json` exakt auf `16.2.10` pinnt. Die drei
transitiven Pakete lösen sich mit dem `next`-Upgrade auf.

**Kein Fehlalarm.** Die Marketing-Seite ist öffentlich deployt; SSRF, Cache-Confusion und
die Offenlegung interner Endpunkte sind für ein öffentlich erreichbares Next.js relevant.
**Bis zur Freigabe nicht angefasst** — siehe Arbeitspaket im Bericht.

### `C-05` — Zwei Guard-Skripte leaken einen Exit-Code an GitHub Actions

**Schweregrad:** hoch · **vorbestehend:** ja · **durch Phase A verursacht:** nein ·
**erstmals überhaupt in Hosted CI erreicht**

Nachdem `C-02` Schritt 11 entsperrt hatte, kam der `database`-Job zum ersten Mal bis
Schritt 24 und scheiterte dort:

```
P1-014 target guard tests passed.
##[error]Process completed with exit code 1.
```

Das Skript **besteht** jede seiner Prüfungen und meldet das auch. Der Fehler liegt im
Exit-Code.

**Ursache.** `tool/test_p1_014_backup_restore_guard.ps1` prüft, dass unsichere
Restore-Ziele und Schalterkombinationen **abgelehnt** werden. Dafür ruft es
`verify_p1_014_backup_restore.ps1` als Kindprozess auf und erwartet einen
Nicht-Null-Exit — zuletzt in Z. 49–54. `Write-Output` in Z. 56 setzt `$LASTEXITCODE`
nicht zurück, also endet das Skript mit dem geleakten Code des absichtlich
fehlgeschlagenen Kindprozesses. GitHubs `pwsh`-Shell hängt
`if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }` an und macht
daraus einen Job-Fehler.

**Lokal reproduziert:**

| Aufruf | Exit |
|---|---|
| `pwsh -NoProfile -Command ". './tool/test_p1_014_backup_restore_guard.ps1'"` | **0** |
| derselbe Aufruf **plus GitHubs angehängtem** `exit $LASTEXITCODE` | **1** (`LASTEXITCODE inside = 1`) |

Deshalb war es lokal nie sichtbar: ohne den Wrapper leitet PowerShell `$LASTEXITCODE`
nicht weiter.

**Warum erst jetzt.** Der Schritt wurde in Hosted CI nie erreicht — auf `main` starb der
Job seit 2026-07-18 bei Schritt 12 (`Test P1-004 concurrency`), auf diesem Branch bis
`b3d613a` bei Schritt 11.

**Zweiter betroffener Fall:** `tool/test_p1_021_performance_profile_guard.ps1` (Schritt 28)
hat dieselbe Form — Schleife über absichtlich fehlschlagende Kindprozesse, danach
`Write-Output`, kein `exit`. Er wäre als Nächstes gescheitert. Von 20 `tool/*.ps1` sind
genau diese beiden betroffen; alle anderen enden auf einem erfolgreichen Kommando.

**Auflösung:** je eine Zeile `exit 0` am Skriptende. Noch nicht ausgeführt — wartet auf
Freigabe.

### `C-05` gelöst · Lauf `31221978111`, Commit `6513351`

Beide Guard-Skripte laufen über `Invoke-GuardCase`: Kindprozess ausführen, Exit-Code
sofort sichern, gegen einen **explizit übergebenen** Erwartungswert prüfen, bei Abweichung
`throw` (mit erwartetem und beobachtetem Code in der Meldung), erst danach
`$global:LASTEXITCODE = 0`. Kein `exit` — die Skripte werden dot-sourced, ein `exit 0`
würde den Host beenden und sie als Baustein unbrauchbar machen.

Der Erwartungswert wird auf Gleichheit geprüft, nicht auf „ungleich null". Ein Kind, das
aus anderem Grund fehlschlägt, bleibt damit ein Fehler statt als Ablehnung durchzugehen.
Gemessen über alle 18 Fälle: Annahmepfade `exit 0` (explizit im Verifier),
Ablehnungspfade `1` (`throw` unter `$ErrorActionPreference = 'Stop'`).

| Probe | Erwartung | Ergebnis |
|---|---|---|
| Positiv P1-014 unter GitHubs Wrapper | 0 | 0 |
| Positiv P1-021 unter GitHubs Wrapper | 0 | 0 |
| Negativ A: gültiges Ziel in die Ungültig-Liste verschoben | ≠ 0 | 1 |
| Negativ B: Erwartungswert auf einen nie gelieferten Code gesetzt | ≠ 0 | 1 |

Manipulationen zurückgenommen, per `Get-FileHash` byteidentisch bestätigt.
`flutter analyze` sauber, volle Suite 1476 grün / 24 Skips.

**Wirkung:** die Schritte 24–29 des `database`-Jobs sind **erstmals überhaupt gelaufen**
und alle grün — die vier P1-014-Backup-/Restore-/Crash-Recovery-Drills, der
P1-021-Parameter-Guard und das P1-021-Kalibrierungsprofil.

---

## 2026-08-07 · `C-06` — Cutover-Schritt scheitert an Pfadsemantik

**Schweregrad:** hoch · **vorbestehend:** ja · **durch Phase A verursacht:** nein ·
**erstmals überhaupt in Hosted CI erreicht** · Schritt 30, Lauf `31221978111`

```
Unhandled exception:
SqfliteFfiException(error, Bad state: file
  /home/runner/work/NextImmo/NextImmo/.dart_tool/sqflite_common_ffi/databases/build/cutover_fixture.db
  not found)
```

**Ursache: Erzeuger und Leser deuten denselben relativen Pfad verschieden.**
Der Workflow ruft beide mit `build/cutover_fixture.db` auf (`flutter.yml:263–265`).

| | Auflösung von `build/cutover_fixture.db` |
|---|---|
| `tool/generate_cutover_fixture.dart` | relativ zum **Arbeitsverzeichnis** → `…/NextImmo/build/cutover_fixture.db` ✔ geschrieben |
| `tool/p2_x01_property_cutover.dart` über `sqflite_common_ffi` | relativ zum **Datenbankverzeichnis der Factory** → `…/.dart_tool/sqflite_common_ffi/databases/build/cutover_fixture.db` ✘ existiert nicht |

Die Fixture wurde also korrekt erzeugt — das Log zeigt ihren Inhalt
(`properties: 2, tenants: 2, units: 2, leases: 1, scenarios: 1`) — und danach am falschen
Ort gesucht. Das PowerShell-Skript meldet daraufhin
`Property dry run failed or is not import ready. Output:` mit leerer Ausgabe.

**Nicht durch die Seeding-Änderung verursacht.** Das Log belegt das Gegenteil: die
Cutover-Skripte erkennen den fehlenden Workspace und bootstrappen selbst
(`Workspace or admin user missing; running the local bootstrap first.`,
`verify_p2_x01_property_cutover.ps1:67–68`, `verify_p2_x01_domain_cutover.ps1:59–60`).
Genau dafür ist der Zweig gebaut, und er hat funktioniert.

**Warum erst jetzt.** Der CI-Schritt kam mit `4d0f892` (Wave 3 AP8) — einem Commit der
lokalen `main`-Linie, die nie auf `origin/main` lag. Er ist damit nie in Hosted CI
ausgeführt worden; in jedem früheren Lauf starb der Job vorher.

**Nicht repariert** — wartet auf Freigabe.

---

## 2026-08-07 · Laufzeitprofil des `database`-Jobs

| | |
|---|---|
| Gesamtlaufzeit | **16,0 min** (21:57:00 → 22:13:02 UTC) |
| Timeout | 35 min |
| Reserve | **19,0 min ≈ 54 %** |

Teuerste Schritte: `11` Rollback-Replay 1,88 min · `6` Supabase-Start 1,85 min ·
`13` P1-007 1,57 min · `21` P2-D05 1,27 min · `14` P1-011 0,93 min. Der Rest liegt
jeweils unter einer Minute.

**Keine Workflow-Aufteilung nötig.** Die Reserve liegt deutlich über der 20-%-Schwelle.
Einschränkung: Schritt 30 brach früh ab; ein durchlaufender Cutover kostet schätzungsweise
1–2 Minuten mehr, was die Reserve bei rund 50 % beließe. Empfehlung: nach dem ersten
vollständig grünen Lauf erneut messen und erst bei unter 20 % über eine Aufteilung
nachdenken — dann wäre `database` in `migrations+pgTAP` und `integration+drills` zu
trennen, nicht ein Gate zu streichen.

---

## 2026-08-08 · `C-04` — Zielversion: Begründung **vor** dem Upgrade

Vorgabe war, die kleinste nachweislich sichere Änderung zu wählen und `16.2.11` zuerst zu
prüfen, weil Next.js diese Version als gepatchte Active-LTS veröffentlicht hat. Die Prüfung
bestätigt das für Next selbst — und widerlegt es für die drei mitgelieferten Pakete.

**Befund aus der Registry:**

| `next` | `dependencies.postcss` | `optionalDependencies.sharp` |
|---|---|---|
| 16.2.10 (aktuell) | `8.4.31` **exakt** | `^0.34.5` |
| 16.2.11 | `8.4.31` **exakt** | `^0.34.5` |
| 16.2.12 | `8.4.31` **exakt** | `^0.34.5` |
| **16.3.0** | `8.5.23` | `^0.35.3` |

Erforderlich sind `postcss > 8.5.22` und `sharp >= 0.35.0`.

`16.2.11` beseitigt **alle neun Next-eigenen Advisories** — deren Range ist durchgehend
`>=16.0.0 <16.2.11`. Es beseitigt aber **keines** der drei übrigen:

- **postcss** ist in 16.2.11 und 16.2.12 **exakt** auf die verwundbare `8.4.31` gepinnt.
  Ein reines Lockfile-Update kann eine exakte Pin nicht überschreiten.
- **sharp** ist per Caret auf `^0.34.5` begrenzt; auf einer `0.x`-Linie schließt Caret die
  nächste Minor aus, `0.35.0` ist damit unerreichbar.
- **nanoid** kommt über postcss; `postcss@8.5.23` fordert `^3.3.16`, was auf `3.3.18`
  auflöst und das Advisory (`<3.3.17`) mit erledigt.

**Verbleibende Optionen und die Wahl.**

*Option 1 — `16.2.12` plus `overrides` auf postcss und sharp.* Kleinere Versionsnummer,
aber es erzwingt eine Kombination, die der Hersteller nie ausgeliefert und nie getestet
hat. Besonders `sharp` 0.34 → 0.35 ist auf einer `0.x`-Linie ein bruchförmiger Sprung
(neue libvips-Generation), und Next 16.2.x ist nicht dagegen gebaut. Die exakte
postcss-Pin existiert genau deshalb: Next koppelt seine CSS-Pipeline eng an eine
bestimmte postcss-Version.

*Option 2 — `16.3.0`.* Genau die Kombination, die der Hersteller ausliefert und testet
(`postcss 8.5.23` + `sharp ^0.35.3`), Minor innerhalb derselben Major. npms eigene
Bewertung: `fixAvailable: {name: next, version: 16.3.0, isSemVerMajor: false}`.
Die `peerDependencies` für `react`/`react-dom` sind zwischen 16.2.10 und 16.3.0
**identisch**, `react@19.2.7` bleibt gültig — keine Folgeänderung.

**Gewählt: Option 2.** Die höhere Versionsnummer ist hier das *geringere* Risiko: nicht die
Größe des Sprungs entscheidet, sondern ob die resultierende Kombination je zusammen
getestet wurde. Option 1 hätte drei ungetestete Paarungen erzeugt, um eine kleinere Zahl
in `package.json` zu schreiben.

Kein `npm audit fix --force`, kein Major-Upgrade, keine sonstige Modernisierung.

### Ergebnis

| Paket | vorher | nachher | Advisory-Grenze | direkt? |
|---|---|---|---|---|
| `next` | 16.2.10 | **16.3.0** | `<16.2.11` (9 Advisories) | ja, einzige direkte Abhängigkeit |
| `postcss` | 8.4.31 | **8.5.23** | `<=8.5.22` (4 Advisories) | transitiv über `next` |
| `sharp` | 0.34.5 | **0.35.3** | `<0.35.0` (4 libvips-CVEs) | transitiv über `next` (optional) |
| `nanoid` | 3.3.16 | **3.3.18** | `<3.3.17` | transitiv über `postcss` |

`npm audit`: vorher `{high: 4, total: 4}` → nachher `{high: 0, total: 0}`,
über **alle** Schweregrade, `--audit-level=high` liefert **Exit 0**.

**Änderungsumfang.** `package.json`: eine Zeile. `package-lock.json`: 223/183 Zeilen —
vollständig zuordenbar und ohne Fremdanteil. Betroffen sind ausschließlich `next` mit
seinen neun `@next/swc-*`-Plattformbinaries und `@next/env`, `sharp` mit 26
`@img/*`-Paketen (Plattformbinaries plus libvips 1.2.4 → 1.3.2) und `@emnapi/runtime`,
sowie `postcss` und `nanoid`. **`react`, `react-dom`, `typescript` und die `@types/*`
sind unberührt.** Dazu `next-env.d.ts`: eine von `next build` erzeugte Referenzzeile
(`root-params.d.ts`), die Datei ist als generiert gekennzeichnet.

**Build und Smoke.** `npm ci` + `npm run build` grün, **identische Routenliste** und
dieselben 8 statischen Seiten wie vor dem Upgrade, keine neue Warnung mit funktionaler
Relevanz. Lokaler Browser-Smoke gegen `next start`:

- Startseite rendert vollständig, **keine Konsolenfehler**
- CSS greift: 1 Stylesheet, 254 Regeln, eigene Hintergrundfarbe und Schriftfamilie aktiv
  (belegt den PostCSS-Build)
- Assets: `/icon.svg` 200 `image/svg+xml`, **`/opengraph-image` 200 `image/png`**,
  `/manifest.webmanifest` 200, `/robots.txt` 200, `/sitemap.xml` 200 — die Bilderzeugung
  läuft
- keine defekten Bildverweise; Header und Footer vorhanden und befüllt
- Mobile 375×812: **kein horizontaler Überlauf** (`scrollWidth == clientWidth`),
  Überschrift skaliert responsiv

Der dafür nötige `launch.json`-Eintrag war temporär und ist zurückgenommen; die Datei ist
unverändert.

### Hosted CI · Lauf `31223819048`, Commit `0732050`

| Job | Ergebnis | Laufzeit |
|---|---|---|
| `supply_chain` | **PASS** | 0,2 min |
| `marketing` | **PASS** | 0,5 min |
| `verify` | **PASS** | 6,3 min |
| `Web App Deploy` | **PASS** (Preflight überspringt korrekt) | — |
| `database` | FAIL, **ausschließlich Schritt 30** | 16,5 min |

Von 31 Schritten des `database`-Jobs ist genau einer rot. Schritte 24–29 erneut alle grün.
Die Fehlermeldung in Schritt 30 ist **byteidentisch** mit der aus Lauf `31221978111`
(`SqfliteFfiException … .dart_tool/sqflite_common_ffi/databases/build/cutover_fixture.db
not found`) — also unverändert `C-06`, kein Folgefehler aus `C-04`.

**`C-04` ist damit geschlossen.**

Laufzeitreserve unverändert komfortabel: 16,5 min von 35 min → **53 %**. Schritt 30 bricht
weiterhin nach 0,13 min ab; ein durchlaufender Cutover kostet 1–2 min mehr.

---

## 2026-08-08 · `C-06` gelöst — erster vollständig grüner Hosted-CI-Lauf

Commit `a3169d8`, Lauf `31246576387`. **`verify`, `supply_chain`, `marketing`, `database`
und `Web App Deploy` alle PASS.** Alle 31 Schritte des `database`-Jobs liefern erstmals
ein Ergebnis, und alle sind grün.

**Ursache.** Beide Cutover-Tools bauten `File(cliPfad)` und reichten `.path` direkt an
`databaseFactoryFfi.openDatabase`. Damit widersprachen sich zwei Auflösungen: `existsSync()`
löst relativ gegen das Working Directory auf und meldete `true`, sqflite löst relativ gegen
sein **eigenes** Datenbankverzeichnis auf und suchte unter
`.dart_tool/sqflite_common_ffi/databases/build/cutover_fixture.db`. Der vorhandene
Fail-Fast-Check gab dadurch falsche Sicherheit, und der Fehler erschien verkleidet als
Datenbankfehler.

`generate_cutover_fixture.dart` Z. 51–55 kennt genau diese Falle und löst sie über
`File(output).absolute` — **die Leseseite wurde nie angeglichen.**

**Semantik jetzt.** `--database` wird einmal am Tool-Eingang über `package:path`
(bereits direkte Abhängigkeit) zu einem absoluten, normalisierten Dateisystempfad
aufgelöst: relativ gegen das Working Directory, absolut unverändert. Alles danach nutzt
nur diesen Pfad. Die Not-Found-Meldung nennt angeforderten **und** aufgelösten Pfad.

Beide Tools sind eigenständige CLI-Einstiegspunkte, die die Quelle selbst öffnen — der
Domain-Cutover ruft den Property-Cutover **nicht** auf —, deshalb beide identisch
repariert. Kein neuer Helper für zwei Aufrufstellen in zwei Standalone-Skripten.

**Lokale Nachweise.**

| Fall | Ergebnis |
|---|---|
| A relativer Pfad | beide Cutover laufen vollständig durch, Exit 0 |
| B absoluter Pfad | **identische** Manifest-Checksummen (`bb782d2c…`, `e440c3f0…`) — beide Formen lösen auf dieselbe Datei auf |
| C fehlende Datei | klare Meldung mit angefordertem und aufgelöstem Pfad; **keine** Datenbank irgendwo erzeugt; Exit-Code siehe `C-07` |
| D voller Cutover | Property: 2 Quellzeilen, 2 gemappt, 0 abgelehnt, 2 reconciled, idempotent. Domain: 2 Parties, 2 PartyRoles, 2 Units, 1 Lease, 1 ValuationCase, 0 verwaiste Referenzen, idempotent |
| Gegenprobe | Zurücksetzen der zwei Dateien reproduziert lokal **dieselbe** CI-Fehlermeldung; Wiederherstellen behebt sie |

**Methodischer Hinweis:** im sqflite-Verzeichnis lag eine Altkopie der Fixture vom
2026-08-05. Ohne sie zu entfernen hätte Fall A **aus dem falschen Grund** bestanden. Nach
dem Löschen bestand er weiterhin, und es entstand keine neue Kopie — erst das belegt die
Auflösung gegen das Working Directory.

Regression: `flutter analyze` sauber, gezielte Cutover-/Mapper-Tests 57 grün, volle Suite
1476 grün / 24 Skips.

### `C-07` — Rückgabewert von `main` erreicht den Prozess nicht

**Schweregrad:** mittel · **vorbestehend:** ja · **nicht repariert** (eigener Befund,
gehört nicht in einen isolierten `C-06`-Commit)

Dart ignoriert den Rückgabewert von `main`. Die drei `tool/*.dart`-Programme geben
`64` (Argumentfehler), `65` (nicht import-ready) und `66` (Quelle fehlt) zurück, der
Prozess endet aber immer mit `0`. Belegt durch einen Aufruf ganz ohne Argumente:
`return 64` → Exit **0**.

Die `verify_p2_x01_*`-Wrapper prüfen jedoch `$LASTEXITCODE -ne 0`. In CI hat bisher
ausschließlich die **unbehandelte Exception** den Prozess mit ≠ 0 beendet; die geplanten
Fehlercodes sind tot.

Die Kette schließt heute trotzdem fail-closed, aber erst über eine spätere Prüfung im
Wrapper (`production_import_ready`), nicht über den Exit-Code. Damit ist Fall C nur
teilweise erfüllt: Meldung ✓, keine erzeugte Datenbank ✓, Exit ≠ 0 ✗.

**Auflösung (Vorschlag, nicht ausgeführt):** in allen drei Tools `exitCode` setzen statt
sich auf den `main`-Rückgabewert zu verlassen, plus je eine Negativprobe.

---

## 2026-08-09 · `C-07` behoben — die Exit-Codes erreichen den Prozess

**Status: DONE.** Der Befund oben bleibt als Ursachenbeschreibung stehen; hier steht, was
tatsächlich ausgeführt wurde.

**Ursache.** Dart verwirft den Rückgabewert von `main`. `return 64` beendet den Prozess
mit `0`. Die `verify_p2_x01_*`-Wrapper lesen `$LASTEXITCODE` — sie lasen also eine
Konstante.

**Betroffene Entrypoints.** Ein repositoryweiter Audit fand exakt drei, keinen weiteren;
keiner nutzte `exit()` oder `exitCode`:

| Tool | vorher | fachliche Codes |
|---|---|---|
| `tool/generate_cutover_fixture.dart` | `Future<int> main` | 0, 64 |
| `tool/p2_x01_property_cutover.dart` | `Future<int> main` | 0, 64, 65, 66 |
| `tool/p2_x01_domain_cutover.dart` | `Future<int> main` | 0, 64, 65, 66 |

**Lösung.** Je Tool `Future<void> main(...) async { exitCode = await _run(args); }`; der
fachliche Code bleibt unverändert in `_run`. Bewusst `exitCode` statt `exit()`: `exit()`
beendet sofort und würde das `finally` überspringen, das die Legacy-Datenbank schließt,
und die stdout-Zeile abschneiden, die der Wrapper als JSON parst. Die Codes selbst wurden
nicht umnummeriert.

**Prozess-Level-Nachweis.** Alle zehn Werte sind echte OS-Prozesscodes, gemessen vor und
nach der Änderung:

| Fall | vorher | nachher |
|---|---:|---:|
| generator usage / property usage / domain usage | 0 | **64** |
| property missing DB / domain missing DB | 0 | **66** |
| property not-ready / domain not-ready | 0 | **65** |
| generator / property / domain success | 0 | 0 |

`65` wurde ohne Codepatch erreicht. Property: ein `--source-workspace-id`, das nicht zur
Fixture passt, erzeugt `ownership.workspace_not_found`. Domain: der Planner validiert
Zeilen statt des Requests, also bekommt eine **temporäre Kopie** der regulär erzeugten
Fixture genau ein Feld geändert — die Lease `FX-L-0001` endet vor ihrem Beginn, was
`source.end_before_start` auslöst. Eine Zeile, ein Feld, ein Fehler; der Generator bleibt
unangetastet und es liegt keine Fixture-Binärdatei im Repository.

**Seiteneffekte unverändert.** `66` legt weder Datenbank noch Ausgabeverzeichnis an, `65`
schreibt `report.json` aber **kein** `import.sql`, `0` schreibt beides — vor und nach der
Änderung identisch.

**Guard.** `test/tool/cutover_cli_exit_code_test.dart` startet jede CLI mit `Process.run`
und prüft den realen Prozesscode; ein Unit-Test von `_run` könnte das nicht, weil genau die
Grenze Rückgabewert → Prozess der Defekt war. Der Test läuft im bestehenden `verify`-Job,
braucht kein Docker und legt keine neue Infrastruktur an. Er prüft zusätzlich stderr, das
Vorhandensein von `report.json`, die Abwesenheit von `import.sql` und den erwarteten
fachlichen Issue — damit steht fest, dass `65` aus dem Planner kam und nicht aus einem
Absturz.

**C-05 berücksichtigt.** Der Guard ist ein Dart-Test, kein dot-sourcetes PowerShell-Skript;
erwartete Negativcodes werden von `Process.run` als Rückgabewert konsumiert und können
nicht als `$LASTEXITCODE` in einen Wrapper lecken.

**C-06 unverändert.** Relativer Pfad → 0, absoluter Pfad → 0, fehlender Pfad → 66 mit
`requested`/`resolved` im Klartext, keine leere SQLite-Datenbank, kein angelegtes
sqflite-Default-Verzeichnis.

**Die Wrapper wurden nicht geschwächt.** `verify_p2_x01_property_cutover.ps1` prüft weiter
`production_import_ready`, Manifest, Checksummen und Idempotenz. Der echte Exit-Code ist
das frühere Fail-Fast, nicht der Ersatz für diese Prüfungen.

---

## 2026-08-08 · Laufzeitprofil des vollständig grünen `database`-Jobs

| | |
|---|---|
| Gesamtlaufzeit | **16,4 min** |
| Timeout | 35 min |
| **Reserve** | **18,6 min ≈ 53 %** |
| Schritt 30 | 0,20 min (läuft jetzt vollständig durch statt nach 0,13 min abzubrechen) |

Teuerste fünf Schritte: `6` Supabase-Start 1,90 · `11` Rollback-Replay 1,90 ·
`13` P1-007 1,68 · `21` P2-D05 1,28 · `14` P1-011 0,92 min.

Reserve deutlich über der 20-%-Schwelle. **Keine Workflow-Aufteilung, kein
Performance-Issue.** Die Messung ist jetzt belastbar, weil erstmals alle Schritte
vollständig durchlaufen sind.

---

## 2026-08-08 · `C-08` — CI fuhr eine nicht deterministische Supabase-CLI

**Schweregrad:** hoch · **vorbestehend:** ja · **gelöst** in `91599b4`

### Vorherige Semantik

Zwei Wege zur CLI, nur einer gepinnt:

| Weg | Aufrufstellen | Version |
|---|---|---|
| `setup-cli@v1`-Binary auf `PATH` | **67** nackte `supabase …`-Aufrufe im Workflow | gepinnt `2.109.1` (Literal im Workflow) |
| `npx supabase` → `./node_modules/.bin` | **27** Aufrufe in **13** `tool/*.ps1` | **ungepinnt** — im Runner existierte kein Root-`node_modules` |

Das `npm ci` in `flutter.yml` gehört zum **marketing**-Job (`working-directory: marketing`),
nicht zum Root. Ohne Root-`node_modules` fällt `npx` auf die Registry zurück und zieht die
**neueste** Version. CI hat damit dauerhaft eine andere CLI benutzt als die gepinnte —
unsichtbar, solange es funktionierte.

Sichtbar wurde es, als `supabase@2.113.0` mitten im Lauf veröffentlicht wurde:

```
npm warn exec The following package was not found and will be installed: supabase@2.113.0
npm error code ETARGET  →  No matching version found for supabase@2.113.0
```

auf `94b3139`, einem Commit, der ausschließlich Markdown ändert. Jeder grüne Lauf davor
war ein Zufall des Zeitpunkts, kein reproduzierbares Ergebnis.

### Verworfene Variante: `npx --no`

Gemessen, nicht angenommen:

- `npx --no supabase --version` liefert `11.10.0` — npx konsumiert `--version` selbst;
  erst `npx --no -- supabase --version` ergibt `2.109.1`.
- Mit einem nicht installierten Paket hat `--no` die Registry **trotzdem** befragt
  (`GET https://registry.npmjs.org/… 404`).

`--no` ist damit kein belastbarer Riegel und scheidet aus.

### Neue Semantik

**`package.json` ist die einzige Source of Truth.** `setup-cli` liest die Version dort aus,
statt sie als Literal zu wiederholen — die Nummer steht nur noch an einer Stelle, ein Drift
zwischen beiden ist konstruktiv unmöglich. Eine nicht-exakte Pin lässt den Schritt scheitern.

Ein Root-`npm ci` stellt die gepinnte CLI bereit, sodass die 27 npx-Aufrufe aus
`node_modules` auflösen. **Kein `tool/*.ps1` wurde geändert**; lokal funktionieren sie
unverändert.

### Schutz gegen Versionsdrift

Ein zentraler Schritt vor jeder Datenbankarbeit vergleicht `package.json`, die
`PATH`-Binary und `npx supabase` gegeneinander und schlägt zusätzlich auf den exakten
Marker `will be installed` an, den npx nur beim Registry-Fallback ausgibt. Eine umgangene
Pin kann sich damit nicht als „bloß andere Version" tarnen. Ein Check statt 13 Kopien.

Alle fünf Zweige isoliert durchgespielt: korrekt → 0; Registry-Marker → 1; npx-Drift → 1;
Drift `setup-cli` ↔ `package.json` → 1; abweichendes Ausgabeformat wird korrekt geparst.

**Lokaler Differenzbeweis:** `npx supabase --version` liefert `2.109.1`, während die
Registry-Latest `2.113.0` ist — nur möglich, wenn aus `node_modules` aufgelöst wurde.

### Evidenz beider Hosted-CI-Läufe

Commit `91599b4`, Lauf `31249014807`, **derselbe SHA in beiden Läufen** (Attempt 1 und 2,
kein neuer Commit).

| | Attempt 1 | Attempt 2 |
|---|---|---|
| `verify` / `supply_chain` / `marketing` / `database` | alle **PASS** | alle **PASS** |
| Schritte mit ≠ success | **0** | **0** |
| `expected (package.json)` | 2.109.1 | 2.109.1 |
| `PATH`, Workflow-Schritte | **2.109.1** | **2.109.1** |
| `npx`, `tool/*.ps1` | **2.109.1** | **2.109.1** |
| echte `will be installed`-Meldung | **0** | **0** |
| `database` Laufzeit | 15,9 min | 16,0 min |

Reproduzierbarkeit damit belegt.

### Laufzeit

`database` 15,9 / 16,0 min bei 35 min Timeout → **Reserve ≈ 54 %**. Die vier neuen
Schritte kosten zusammen **0,14 min**. Der Job ist trotz vier zusätzlicher Schritte nicht
langsamer, weil `P1-007` von 1,68 auf 0,90–0,92 min fällt: npx zieht die CLI nicht mehr bei
jedem Aufruf aus der Registry. **Keine Workflow-Aufteilung.**

---

## 2026-08-08 · `HIGH-03` — Decision-Reconciliation der geretteten Owner-Entscheidungen

Quelle: `rescue/codex-ai-ph00-baseline` (`9f4bbc1`), Owner-Entscheidungen vom 2026-08-02,
bestätigt durch Owner-Auftrag am 2026-08-08. Der Rescue-Branch ist historische Evidenz,
**keine** Source of Truth — keine Datei wurde als Ganzes übernommen.

| Rescue-Entscheidung | Inhalt | kanonisches Ziel | Ergebnis |
|---|---|---|---|
| `AI-PH01-DEC-001` | Frankfurt/EU als Zielregion; Provisionierung bleibt separat freigabepflichtig | `DEC-015` | **accepted** (war `proposed`) |
| `AI-PH01-DEC-002` | AAL2 für privilegierte Capabilities; `ai.use` verleiht kein Domainrecht | `DEC-016`, `DEC-SEC-001` | **accepted** (war `proposed`); `DEC-SEC-001` → `partial` |
| `AI-PH01-DEC-003` | Entity-Scope als `property`/`portfolio`-Allowlist, unbekannte Typen Deny | `DEC-SEC-002` | **nicht übernommen** — Review vorgelegt, Entscheidung steht aus |
| `AI-PH01-DEC-004` | keine produktive PII an Provider, keine automatische physische Löschung | `DEC-SEC-003`, `DEC-SEC-004` | **nicht übernommen** — durch diesen Auftrag nicht entschieden |

**`DEC-017` bleibt `open`.** Die drei sind bewusst getrennt: `DEC-015` entscheidet **wo**,
`DEC-016` **wie gesichert**, `DEC-017` ob überhaupt eine Remote-Ressource **angelegt** werden
darf. Kein Production-Projekt, keine bezahlte Ressource, keine Production-Secrets, keine
Datenmigration, kein DNS-Cutover.

**Geänderte kanonische Dokumente:** `phase_0/11_decision_register.md` (DEC-015, DEC-016,
zentraler Index), `phase_0/07_security_and_tenancy_baseline.md` (`DEC-SEC-001` → `partial`),
`cloud/01_target_cloud_architecture.md` (§4, §8, §14), `phase_0/00_phase_status.md`,
`CLAUDE.md`, dieses Protokoll.

**Bewusst nicht umgeschrieben** — zeitpunktbezogene Berichte, die den damaligen Stand
korrekt festhalten: `cloud/00_repository_audit.md`, `phase_0/12_phase_1_execution_backlog.md`,
`phase_1/03_reference_slice_gate_review.md` (`GATE-BLK-002`/`003`),
`phase_1/02_backup_restore_runbook.md`, `phase_1/01_environment_contract.md`,
`phase_2/00_phase_2_charter.md`. Wo sie `DEC-015`..`DEC-017` gemeinsam als Gate nennen, ist
seit dem 2026-08-08 nur noch `DEC-017` offen; der zentrale Index im Register sagt das
ausdrücklich.

---

## 2026-08-08 · `main` ist geschützt — Ruleset `main-protection`

Vorher: **keine** klassische Branch Protection (`HTTP 404`) und **kein** Ruleset (`[]`).
Direkte Pushes auf `main` waren möglich — genau die Lücke, mit der Phase A begonnen hat.

Gewählt wurde ein **Repository Ruleset**, nicht klassische Branch Protection. Der Grund ist
der Bypass: klassisch gäbe es nur `enforce_admins` an/aus, und „aus" erlaubt dem Owner auch
den normalen Direktpush. Rulesets kennen `bypass_mode`, und damit lässt sich der Owner im
PR-Workflow halten und trotzdem ein Notausgang offenlassen.

| Regel | Wert |
|---|---|
| Ruleset | `main-protection`, id `20585474` |
| Target / Enforcement | `refs/heads/main` · **active** |
| Require pull request | ja |
| Required approvals | **0** — Solo-Repository; jede Zahl > 0 wäre ein Selbst-Lockout, weil man den eigenen PR nicht freigeben kann |
| Conversation resolution | ja |
| Dismiss stale / last-push / Code Owner | aus |
| Required status checks | `verify`, `supply_chain`, `marketing`, `database` (je `integration_id 15368`) |
| Strict / up to date | ja |
| Force push | blockiert (`non_fast_forward`) |
| Branch-Löschung | blockiert (`deletion`) |
| Owner-Bypass | `RepositoryRole` admin, **`bypass_mode: pull_request`** |
| Merge-Methoden | `merge`/`squash`/`rebase` **unverändert** — Merge-Stil ist ein eigenes Thema |

**Owner-Notausgang, von GitHub selbst bestätigt:** die API meldet
`current_user_can_bypass: "pull_requests_only"`. Der Bypass greift also ausschließlich
innerhalb eines Pull Requests; ein normaler Direktpush auf `main` bleibt auch für den Owner
blockiert, und jeder Notfall hinterlässt einen sichtbaren PR als Audit-Trail.

### Warum genau diese vier Checks

Die Namen wurden **nicht** aus der Dokumentation übernommen, sondern aus echten grünen
Läufen ermittelt (`/commits/{sha}/check-runs`). Das hat zwei Deadlocks verhindert:

- Der Deploy-Workflow erscheint nicht als „Web App Deploy", sondern als `preflight` und
  `deploy_preview`. Ein Required Check auf den Doku-Namen wäre dauerhaft
  „Expected — waiting for status to be reported" geblieben.
- `deploy_preview` ist `skipped`, solange keine Vercel-Secrets existieren. Ein übersprungener
  Check gilt in Rulesets nicht als erfolgreich — als Required Check ein garantierter Deadlock.

Ebenfalls bewusst **nicht** required: der klassische `Vercel`-Status (Marketing-Deployment),
`Vercel Preview Comments`, die `Dependabot`-Läufe und der `goldens/**`-Hilfsworkflow.
Deployment wird später mit Staging/Production als eigenes Deployment-Gate modelliert, nicht
als universelles Merge-Gate.

### Folgen für Dependabot

Die sieben offenen Dependabot-PRs (#2–#8) erhalten dieselben vier Checks wie jeder andere
PR. `strict` erzwingt bei zwischenzeitlichen `main`-Änderungen gelegentlich ein
„Update branch" — gewollt, damit nichts gegen einen veralteten Basiszustand gemergt wird.

### Verifikation

Nicht am API-201 festgemacht, sondern per Readback: Ruleset-Liste, Einzelabfrage und
`/rules/branches/main` (effective rules) bestätigen alle vier Regeln, `strict`, die vier
Contexts, `approvals=0`, beide Blockaden und den PR-only-Bypass. Klassische Branch
Protection existiert weiterhin nicht — keine doppelte Schutzschicht.

**Dieses Dokument ist zugleich der End-to-End-Selbsttest:** es kam über einen regulären PR
unter den neuen Regeln auf `main`, ohne Bypass.

---

## 2026-08-08 · Phase A: **integrated into main** — nicht „abgeschlossen"

PR [#1](https://github.com/MeisnerMax/NextImmo/pull/1) ist gemergt.

| | |
|---|---|
| Strategie | **Merge-Commit** — kein Squash, kein Rebase, kein Force-Push |
| Merge-SHA | `49eab16a72a1588ffe07d60dd09bf50bf98e84e3` |
| Zeitpunkt | 2026-08-08T11:09:14Z |
| Umfang | 37 Commits, 634 Dateien, +164 380 / −27 530 |
| Vorher `origin/main` | `e46ed00` (Marketing-Commit vom 2026-07-18) |
| Branch | `cloud/foundation-stabilization` **nicht gelöscht** |

Die Merge-Commit-Strategie war eine bewusste Wahl: die 37 Commits sind einzeln
verifizierte Arbeitspakete und Architekturentscheidungen, und genau diese Evidenz soll
nachvollziehbar bleiben.

**Hosted CI auf dem PR-Head `5a6b772`:** alle fünf Jobs PASS.
**Hosted CI auf dem Merge-Commit `49eab16`:** `verify`, `supply_chain`, `marketing` und
`database` (39/39 Schritte, 16,7 min) PASS. CLI-Wächter meldet `2.109.1` aus allen drei
Quellen, null echte Registry-Nachinstallationen, `025_ph01_entity_scope` und
`032_ph01_entity_scope_down` beide `ok`.

**`Web App Deploy` läuft auf `main` nicht** — kein Fehler, sondern der Trigger: die Datei
hat `pull_request` und `workflow_dispatch`, keinen `push`. Auf `main` sind es vier Jobs.
Ein `push`-Trigger wird erst sinnvoll, wenn das zweite Vercel-Projekt existiert; bis dahin
ist der Workflow ohnehin inert.

**Nebenwirkung des Merges:** Dependabot ist auf `main` aktiv geworden (`github_actions`,
`pub`, `npm_and_yarn` in `marketing`) — die erwartete Wirkung der `dependabot.yml`. Es sind
gruppierte Monats-PRs zu erwarten.

### Status: `integrated into main`, **nicht** `complete`

Der Foundation-**Code** ist auf `main`. Die Foundation als Ganzes ist nicht abgeschlossen,
solange offen sind: Branch Protection, `AP-X02-2b`, Desktop-Deep-Link-Port, `C-07`, das
zweite Vercel-Projekt, der interaktive Cloud-Golden-Path und `DEC-017`.

---

## 2026-08-08 · `PH-01` — Entity-Scope-Enforcement, neu implementiert

Nicht die Rescue-Migration portiert. Sie diente als Referenz; drei ihrer Annahmen gelten
nicht mehr (siehe unten). Migration `supabase/migrations/20260808120000_ph01_entity_scope_enforcement.sql`.

### Was gilt

`entity_scopes` ist eine **optionale, verengende Allowlist**: keine Scope-Zeilen bedeutet
workspace-weiter Zugriff; sobald eine Membership mindestens eine Zeile hat, zählt nur noch
ein expliziter Treffer; ein Scope ersetzt **nie** eine fehlende Workspace-Permission.

**Allowlist vorerst nur `property`.** Die Baseline nennt auch `portfolio`, aber im Schema
existieren weder eine `portfolios`-Tabelle noch eine Property→Portfolio-Beziehung — der
Wert kommt ausschließlich als noch nicht migrierter Eintrag im Enum
`document_link_entity_type` vor. Ihn jetzt zu erlauben erzeugte eine Zeile, die schreibbar
ist und nie matchen kann: aus „auf ein Portfolio einschränken" würde stillschweigend
„gar nichts sehen". `portfolio` kommt mit `P2-D09` samt Tabelle und Vererbungsregel.

### Was gegenüber der Rescue-Fassung neu gebaut wurde

| Rescue-Annahme | Realität 2026-08-08 | Konsequenz |
|---|---|---|
| `public.update_property` ist der Kern und wird nach `private` verschoben | Seit `20260718100000_p1_015_aal_hardening.sql` ist `public.update_property` **bereits** der AAL2-Wrapper, der Kern heißt `private.update_property_core` | Der Scope-Guard kommt **in** den bestehenden Wrapper. Kein dritter Layer, keine Umbenennung — `005_p1_015_aal.test.sql` prüft `update_property_core` namentlich |
| Zeitstempel `20260802190000` | liegt vor neun neueren Migrationen | Neuer Zeitstempel `20260808120000` |
| Rollback-Eintrag in der Mitte der Kette | Kette ist strikt LIFO | Neuer Down-Test als **erster** Schritt vor `031_…` |
| Testliste ergänzt `update_property` | folgt aus dem alten Wrapping | Entfällt; nur die zwei neuen Funktionsnamen kommen hinzu |

Wiederverwendet wurden die Idee, die Fail-Closed-Achsen und die Struktur der beiden
Primitive.

### Datenschutz vor Constraint

Die Migration prüft `entity_scopes` **vor** dem Constraint und bricht mit
`check_violation` samt Aufzählung der betroffenen Werte ab, wenn nicht unterstützte
`entity_type`-Werte existieren. Es wird nichts gelöscht und nichts umgeschrieben.

### Lokale Evidenz

| Gate | Ergebnis |
|---|---|
| Supabase-CLI | **2.109.1** (gepinnt) |
| `db reset --no-seed`, `db lint`, Security- und Performance-Advisor | grün (Advisor-Restbefund `rls_enabled_no_policy` auf `mutation_receipts` ist INFO und vorbestehend) |
| volle pgTAP-Suite | **1274 Tests grün**, davon 28 neu in `025_ph01_entity_scope.test.sql` |
| Rollback `032_ph01_entity_scope_down.test.sql` | grün — Primitive weg, Constraint weg, Policy zurück auf die reine Workspace-Permission, **AAL2-Wrapper ohne Scope-Guard wiederhergestellt** |
| `verify_p1_004`, `p1_007`, `p1_011`, `p1_018`, `debt_012`, `p2_d01`, `p2_d05`, beide `p2_x01`-Cutover | alle Exit 0 |

### Sicherheitsstand

**Tatsächlich entity-scoped:** `properties` — SELECT über die Policy, UPDATE über den
öffentlichen RPC (Authentifizierung → AAL2 → Permission-und-Scope → Core).

**Noch nicht:** `units`, `leases`, `maintenance_tickets`, `capex_projects`, `documents`.
Deren RLS ist unverändert. Wo sie heute indirekt über Property-Rechte lesen, erben sie die
Einschränkung faktisch mit; das ist **nicht** dasselbe wie durchgesetztes Child-Scoping und
wird hier ausdrücklich nicht behauptet. Das ist ein eigenes Security-Increment.

---

## 2026-08-07 · `AP-X02-2` — Audit erstellt, nichts gelöscht

`cloud/02_ap_x02_2_legacy_adapter_audit.md`. 24 Artefakte, 12 511 LOC, je Artefakt
Importeure, Composition-Root-Bindung, Backend-Zweig, Tests und Migrations-Abhängigkeit.

Kernbefunde:

- **Eine einzige Naht.** Alle produktiv gebundenen Legacy-Adapter hängen ausschließlich am
  Zweig `case DataBackend.sqlite:` in `app_backend_wiring.dart:345–442`. Kein einziger
  wird im Supabase-Zweig gebunden — Nachweis 1 ist damit strukturell erbracht.
- **Zwei Adapter sind bereits tot** (`legacy_sqlite_membership_admin_*`,
  `legacy_sqlite_property_*`): null `lib/`-Importeure, nur die eigene Testdatei.
- **Abweichung von `04y` §3:** die Dry-Run-Mapper (6492 LOC) hängen nicht am
  Laufzeitmodus und bleiben. Das Cutover-Paket ist `DEFER` bis zur reproduzierten
  Nullmessung.
- **Nebenbefund:** `app_backend_wiring.dart:114–116` behauptet, beide Backends läsen
  Comparables aus dem Legacy-Store; Z. 322 bindet im Cloud-Zweig aber die werfende
  Attrappe. `04y` §4 wiederholt den Fehler.

`AP-X02-2` steht damit auf `audit done, execution pending`.

---

## Offene Punkte am Ende dieses Blocks

| # | Punkt | Zuständig | Blockiert |
|---|---|---|---|
| 0 | Ungesicherte Arbeit im Worktree `codex-ai-ph00-baseline` sichten und entscheiden | **HIGH** | `AP-X02-2b`; berührt `flutter.yml` und `supabase/config.toml` |
| 0b | `C-07` Exit-Codes der drei `tool/*.dart` setzen statt zurückgeben | MEDIUM | Fail-Fast wirkt erst dann über den Exit-Code |
| 0b | Ungesicherte Arbeit im Worktree `codex-ai-ph00-baseline` sichten und entscheiden | Nutzer | Worktree-Bereinigung; berührt `flutter.yml` und `supabase/config.toml`, also dieselben Dateien wie Phase A, und blockiert `AP-X02-2b` |
| 1 | PR #1 mergen, sobald der Lauf grün ist | Nutzer | Abschluss A2/A3 |
| 2 | Branch Protection auf `main` mit vier Required Checks | Nutzer (Repo-Settings; API-Aufruf aus der Sitzung heraus abgelehnt) | A3 |
| 3 | Zweites Vercel-Projekt für die Flutter-Web-App plus Secrets | Nutzer | A4 |
| 4 | Interaktiver Golden-Path im sichtbaren Browser-Pane | gemeinsam | A5 |
| 5 | Entscheidung Szenariovergleich | Nutzer | `AP-X02-5` |
| 6 | `DEC-017` entscheiden (`DEC-015` und `DEC-016` sind am 2026-08-08 accepted) | Nutzer | Phase C, jede nicht-lokale Umgebung |

**Erledigt seit der ersten Fassung dieser Liste:** `C-01` und `C-02` (beide `b3d613a`),
`AP-X02-1` (`101325c` — Charter und `CLAUDE.md` an `DEC-024` angeglichen).
