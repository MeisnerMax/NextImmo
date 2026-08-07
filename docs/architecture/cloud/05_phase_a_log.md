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

## Offene Punkte am Ende dieses Blocks

| # | Punkt | Zuständig | Blockiert |
|---|---|---|---|
| 1 | `gh auth login`, dann Push von Branch und Tags, PR gegen `main` | Nutzer | Hosted-CI-Nachweis, Abschluss A2/A3 |
| 2 | Branch Protection auf `main` mit vier Required Checks | Nutzer | A3 |
| 3 | Zweites Vercel-Projekt für die Flutter-Web-App plus Secrets | Nutzer | A4 |
| 4 | Interaktiver Golden-Path im sichtbaren Browser-Pane | gemeinsam | A5 |
| 5 | Entscheidung Szenariovergleich | Nutzer | `AP-X02-5` |
| 6 | `AP-X02-1`: Charter Z. 21 und `CLAUDE.md` an `DEC-024` angleichen | Umsetzung | `P2-X02` |
| 7 | `DEC-015`..`DEC-017` entscheiden | Nutzer | Phase C, jede nicht-lokale Umgebung |
