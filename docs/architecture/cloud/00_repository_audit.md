# Cloud Foundation Stabilization — Repository Audit (Phase A / A1)

Stand: 2026-08-07
Ausgangs-HEAD: `6ad3431` (`main`, lokal, ungepusht) · Sicherungstag `pre-cloud-stabilization-2026-08-07`
Zweck: Belegter Ist-Zustand von Repository, CI und Deployment vor der Cloud-Migration.
Autoritative Statusquelle für Domänen/Wellen bleibt `phase_2/00_phase_2_status.md`; dieses
Dokument beschreibt ausschließlich den Foundation-Layer (Git, CI, Deployment, Build, Secrets).

Jeder Befund nennt Evidenz, Schweregrad, Handlung und ob er ein Blocker für Phase A ist.

---

## 1. Zusammenfassung

Der technische Zustand ist deutlich besser als der Planungszustand. Der Code ist grün
(1482 Tests, Analyzer sauber), die Cloud-Basis ist weit fortgeschritten, und die
Git-Divergenz war additiv und konfliktfrei auflösbar. Die realen Lücken liegen in
Deployment, CI-Governance und in Planungsdokumenten, die dem Code hinterherhinken.

Drei Befunde waren Blocker, alle drei sind in diesem Arbeitsblock geschlossen:
`F-01` (roter Working Tree), `F-02` (Branch-Divergenz), `F-03` (fehlendes `marketing/`).

---

## 2. Korrekturen an der Ausgangsannahme

Die Masterprompt-/Masterplan-Vorlage vom 07.08.2026 beschreibt einen überholten Zustand.
Nach Regel 0.1 („Realität gewinnt") werden die Abweichungen hier festgehalten.

| Annahme in der Vorlage | Belegte Realität | Evidenz |
|---|---|---|
| Entwicklungshead ist `docs/add-claude-md`, 43 voraus / 3 hinter `main` | Entwicklungshead ist das **lokale `main`** (15 voraus / 3 hinter `origin/main`). `docs/add-claude-md` ist inhaltlich vollständig in `main` enthalten und fachlich überholt | `git rev-list --left-right --count`; `git diff docs/add-claude-md main` = 232 Dateien |
| Push-CI läuft nur für `main`, kein CI für den Dev-Head | `on: pull_request` gilt für **alle** Branches; ein PR erzeugt sofort den vollen Lauf. Nur der `push`-Trigger ist auf `main` beschränkt | `.github/workflows/flutter.yml:3-6` |
| SQLite bleibt Legacy-Quelle, danach read-only Archiv / optionaler Offline-Cache | `DEC-024` (accepted, 2026-08-06) beschließt den **vollständigen Rückbau**: kein Archiv, kein Cache, keine Offline-Startfähigkeit | `phase_0/11_decision_register.md:28`; `phase_2/04y` |
| Phase L: Legacy→Cloud-Datenmigration pro Domäne | **Gegenstandslos.** Legacy-Objektdaten waren Testdaten und wurden am 2026-08-04 entfernt (`app_data.db`: 0 Properties / 0 Scenarios / 0 Users) | `phase_2/04y` §1, §2; `phase_2/04x` Z. 337 |
| Phase B: Unified Cloud App Shell steht noch aus | Entspricht `P2-X01`; `AP0`–`AP3` sind `done`, `AP4` `partial` (nur `documents`), `AP5`/`AP6` offen. Der `AP4`-Rest entfällt laut `04y` §5 mit dem frühen Schnitt | `phase_2/04x`, Abschnitt „Umsetzungsstand und Evidenz" |
| P2-D05 Leasing offen, P2-D06 Maintenance offen | P2-D05 `done` inkl. real gefahrenem Golden Path (Welle 3); P2-D06 Backend + Welle-4-Panels `done`, offen nur der manuelle Golden Path | `phase_2/00_phase_2_status.md`; Commits `4d0f892`..`6ad3431` |

Konsequenz: Die Phasen L (Datenmigration) und P (SQLite Retirement) der Vorlage sind durch
`phase_2/04y_p2_x02_sqlite_decommission.md` ersetzt. Phase B ist überwiegend erledigt.
Die Vorlage bleibt gültig für die Phasen A, C, J, K, M, N, O.

---

## 3. Befunde

### F-01 — Working Tree war rot (Analyzer-Fehler)

- **Schweregrad:** kritisch · **Blocker:** ja (behoben)
- **Evidenz:** `flutter analyze --no-pub` →
  `error - The type 'GlobalPage' is not exhaustively matched by the switch cases since it
  doesn't match 'GlobalPage.compare' - lib\ui\navigation\app_navigation.dart:262`
- **Ursache:** Vier uncommittete Dateien. `GlobalPage.compare` (Szenariovergleich) war aus
  Navigationsgruppe, Rollenmatrix und `cloudReadPermissionForPage` entfernt, während
  `lib/ui/screens/compare_screen.dart`, `lib/ui/shell/app_scaffold.dart:275` und
  `test/ui/navigation/app_navigation_test.dart:118` ihn weiter referenzierten. Ein reiner
  Switch-Fix hätte den Analyzer grün gemacht, aber die Suite rot gelassen.
- **Handlung:** Der unfertige Stand wurde **verlustfrei geparkt**, nicht verworfen:
  Branch `wip/compare-removal-2026-08-07` (`388e719`), Tag
  `archive/wip-compare-removal-2026-08-07`. Die vierte, davon unabhängige und in sich
  vollständige Änderung (Objektname als Link in `MaintenanceTicketsPanel`) wurde
  zurückgeholt und separat committet (`0337e65`).
- **Offene Entscheidung:** Ob der Szenariovergleich stillgelegt wird, ist **nicht**
  entschieden. `phase_2/04e` Z. 67 führt ihn als „offen"; `phase_2/04y` `AP-X02-5` führt
  `compare` weiter als Migrationsziel. Zuständig ist `AP-X02-5`.

### F-02 — Branch-Divergenz zwischen Entwicklung und `origin/main`

- **Schweregrad:** hoch · **Blocker:** ja (behoben)
- **Evidenz:** `main...origin/main` = 15 voraus / 3 zurück; Merge-Base `3a7e5e8`.
  Die drei Gegen-Commits (`3656e60`, `f9349e5`, `e46ed00`) berühren **ausschließlich**
  `marketing/` (18 Dateien, +4061).
- **Handlung:** Sicherungstag `pre-cloud-stabilization-2026-08-07` auf `6ad3431`;
  Arbeitsbranch `cloud/foundation-stabilization`; `origin/main` additiv gemergt
  (`ort`-Strategie, **null Konflikte**). Kein Rebase, kein Force-Push, keine History-Rewrites.

### F-03 — `marketing/` fehlte auf dem Entwicklungsstand → Vercel-Deploy defekt

- **Schweregrad:** hoch · **Blocker:** ja (behoben)
- **Evidenz:** `Test-Path marketing` = `False` auf `6ad3431`; `git ls-tree origin/main -- marketing`
  listet 18 Dateien. Vercel-Fehler `NOW_SANDBOX_WORKER_ROOTDIR_NOT_EXIST`
  („The specified Root Directory 'marketing' does not exist").
- **Handlung:** Mit `F-02` behoben. Kein Flutter-Codefehler — reine Branch-Folge.

### F-04 — Kein Deployment-Setup für die Flutter-Web-App

- **Schweregrad:** hoch · **Blocker:** nein
- **Evidenz:** Keine `vercel.json` im Repo (`git ls-tree -r origin/main | grep vercel` leer).
  Genau ein Vercel-Projekt (`next-immo`, Next.js), das auf `marketing/` zeigt.
  `.github/workflows/flutter.yml` baut Web, deployt aber nichts.
- **Handlung:** Phase A4 — zwei getrennte Projekte (Marketing / Produkt-App).

### F-05 — Kein Secret-Scan, kein Dependency-Scan, kein Dependabot

- **Schweregrad:** mittel · **Blocker:** nein
- **Evidenz:** `.github/` enthält genau eine Datei (`workflows/flutter.yml`);
  `Test-Path .github/dependabot.yml` = `False`. Der Workflow hat 14 fachliche Gates,
  aber keine Supply-Chain-Gates.
- **Handlung:** Phase A3.

### F-06 — Kein Push-CI für Nicht-`main`-Branches

- **Schweregrad:** niedrig · **Blocker:** nein
- **Evidenz:** `.github/workflows/flutter.yml:5-6` → `push: branches: [main]`.
- **Bewertung:** Weniger gravierend als in der Vorlage angenommen, da `pull_request`
  ungefiltert greift. Fehlt nur für direkte Pushes auf einen Cloud-Branch ohne PR.
- **Handlung:** Phase A3 — `cloud/**` in den Push-Trigger aufnehmen.

### F-07 — `.gitignore` ohne `.env`-Muster

- **Schweregrad:** mittel · **Blocker:** nein
- **Evidenz:** `.gitignore` (50 Zeilen) enthält keine `.env`-Regel. `marketing/` bringt
  `.env.example` mit und damit die Erwartung lokaler `.env`-Dateien; Supabase-CLI erzeugt
  `supabase/.temp/`.
- **Bewertung:** Aktuell **keine** Verletzung — `git ls-files` findet keine `.env`-,
  Secret-, Credential-, `.pem`- oder `.key`-Datei, und `git status` zeigt keine
  untracked Dateien. Der Befund ist präventiv.
- **Handlung:** Phase A3.

### F-08 — Branch Protection auf `main` nicht verifizierbar

- **Schweregrad:** mittel · **Blocker:** nein (extern)
- **Evidenz:** `gh auth status` → „not logged into any GitHub hosts". Weder Branch-Protection
  noch Workflow-Läufe noch PR-Status lassen sich aus dieser Sitzung prüfen.
- **Handlung:** Erfordert Nutzeraktion (`gh auth login`). Bis dahin ist kein
  Hosted-CI-Nachweis möglich — siehe §4.

### F-09 — Getrackte `.claude/launch.json` enthält einen Supabase-Key

- **Schweregrad:** niedrig · **Blocker:** nein
- **Evidenz:** `git ls-files .claude` → `.claude/launch.json`; enthält
  `SUPABASE_PUBLISHABLE_KEY=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH` gegen
  `http://127.0.0.1:54321`.
- **Bewertung:** **Kein Secret.** Publishable Key des lokalen Docker-Stacks, per Design
  clientseitig und ohne Bezug zu gehosteten Umgebungen. `supabase/config.toml` enthält
  keine Secrets. Der Environment-Contract ist eingehalten.
- **Handlung:** Belassen. Bei Staging/Production **niemals** dort eintragen — dann über
  nicht-getrackte lokale Konfiguration bzw. CI-Secrets.

### F-10 — Technische Schuld: große Dateien und Legacy-Umfang

- **Schweregrad:** mittel · **Blocker:** nein
- **Evidenz (gemessen 2026-08-07):**

  | Kennzahl | Wert |
  |---|---|
  | Dart-Dateien `lib/` / `test/` | 464 / 209 |
  | Supabase-Migrationen | 34 |
  | Legacy-Repositories (`lib/data/repositories/`) | 39 |
  | Legacy-/Cutover-Adapter (`lib/features/*/data/legacy_*`) | 16 |
  | Größte Dateien | `property_detail/maintenance_screen.dart` 3798 · `budget_vs_actual_screen.dart` 3406 · `data/sqlite/migrations.dart` 2956 · `maintenance/maintenance_screen.dart` 2819 |
  | `TODO`/`FIXME`/`HACK`/`XXX` in `lib/` | **0** |

- **Bewertung:** Null Marker-Kommentare bei 464 Dateien ist ein ungewöhnlich sauberer
  Wert — die Schuld ist in den Registern dokumentiert, nicht im Code verstreut.
  Die vier größten Dateien sind genau die Screens, die `04y` Strom B/A zum Rückbau
  vorsieht. Kein eigenständiger Handlungsbedarf in Phase A.
- **Handlung:** Bleibt bei `P2-X02` (`AP-X02-6`..`AP-X02-9`) und
  `02_architecture_modernization_backlog.md`.

### F-11 — Überholte Branches und Worktrees

- **Schweregrad:** niedrig · **Blocker:** nein
- **Evidenz:** `docs/add-claude-md` (`9675e4a`, 53 Commits, inhaltlich in `main` enthalten);
  `codex/setze-neues-design-um` (`1da5433`, 0 eigene Commits, 31 hinter `main`);
  drei Worktrees unter `.claude/worktrees/` auf `bacc36a`/`9675e4a`.
- **Handlung:** Als Tags archiviert (`archive/docs-add-claude-md`,
  `archive/codex-setze-neues-design-um`). Löschung erst **nach** erfolgreichem Push der
  Tags — bis dahin existiert die feingranulare Historie nur lokal.

---

## 4. Grenzen dieses Audits

| Nicht prüfbar | Grund | Auflösung |
|---|---|---|
| Hosted-CI-Läufe, PR-Status, Branch Protection | `gh` nicht authentifiziert (`F-08`) | `gh auth login` durch den Nutzer |
| Vercel-Projektkonfiguration | Kein API-Zugang aus dieser Sitzung | Nutzer bestätigt im Vercel-Dashboard |
| Gehostete Supabase-Umgebungen | Existieren nicht; `DEC-015`..`DEC-017` gegated | Phase C |
| Push von Tags und Branch | Erfordert Remote-Credentials | siehe `05_phase_a_log.md` |

Lokal ausgeführte Gates sind kein Ersatz für einen Hosted-CI-Lauf auf exakt dem Commit,
der gemergt wird. Phase A gilt erst mit grünem PR-Lauf als abgeschlossen.

---

## 5. Ausgeführte Evidenz (2026-08-07)

| Gate | Ergebnis |
|---|---|
| `flutter analyze --no-pub` vor Stabilisierung | **rot** — 1 Fehler (`F-01`) |
| `flutter analyze --no-pub` nach Stabilisierung | grün, 0 Issues |
| `flutter test --no-pub` (volle Suite) | **1482 grün / 18 Skips** |
| `flutter analyze --no-pub` nach `marketing/`-Merge | grün, 0 Issues |
| Merge `origin/main` → `cloud/foundation-stabilization` | konfliktfrei, 18 Dateien additiv |
| Hosted CI | **ausstehend** (`F-08`) |

Der `database`-Job (Supabase-Reset, Lint, Advisors, pgTAP, Rollback-Replays,
Integrationsskripte) wurde in diesem Block **nicht** lokal gefahren: keine der
Änderungen berührt `supabase/`, Migrationen oder `tool/`-Skripte. Er läuft im PR.
