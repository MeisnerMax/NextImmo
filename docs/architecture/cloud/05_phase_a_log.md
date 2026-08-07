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
| 0 | `C-04` Marketing-Abhängigkeiten aktualisieren (`next` 16.2.10 → 16.3.0) | **BLOCKER**, Freigabe nötig | grüner `supply_chain`-Job, Merge von PR #1 |
| 0a | `C-06` Pfadauflösung im Cutover-Schritt | **BLOCKER**, Freigabe nötig | grüner `database`-Job, Merge von PR #1 |
| 0b | Ungesicherte Arbeit im Worktree `codex-ai-ph00-baseline` sichten und entscheiden | Nutzer | Worktree-Bereinigung; berührt `flutter.yml` und `supabase/config.toml`, also dieselben Dateien wie Phase A, und blockiert `AP-X02-2b` |
| 1 | PR #1 mergen, sobald der Lauf grün ist | Nutzer | Abschluss A2/A3 |
| 2 | Branch Protection auf `main` mit vier Required Checks | Nutzer (Repo-Settings; API-Aufruf aus der Sitzung heraus abgelehnt) | A3 |
| 3 | Zweites Vercel-Projekt für die Flutter-Web-App plus Secrets | Nutzer | A4 |
| 4 | Interaktiver Golden-Path im sichtbaren Browser-Pane | gemeinsam | A5 |
| 5 | Entscheidung Szenariovergleich | Nutzer | `AP-X02-5` |
| 6 | `DEC-015`..`DEC-017` entscheiden | Nutzer | Phase C, jede nicht-lokale Umgebung |

**Erledigt seit der ersten Fassung dieser Liste:** `C-01` und `C-02` (beide `b3d613a`),
`AP-X02-1` (`101325c` — Charter und `CLAUDE.md` an `DEC-024` angeglichen).
