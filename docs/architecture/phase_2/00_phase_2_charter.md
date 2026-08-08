# Phase 2 Charter — Vollausbau und professionelle Neugestaltung

Stand: 2026-07-19
Status: `proposed`
Baut auf: `docs/architecture/phase_0/*`, `docs/architecture/phase_1/*`, `docs/architecture/enterprise_target_architecture.md`, `Update_V9.1_restore.md`.

## Auftrag

Zwei gleichrangige Ziele, gemeinsam umgesetzt statt nacheinander:

1. **Vollständige Datenbank-Ausweitung**: Jede der zehn Zieldomänen aus `02_domain_map.md` (`DOM-001`..`DOM-010`) bekommt die gleiche Supabase-Cloud-Schicht, die `portfolio_property` (`DOM-002`) in Phase 1 bereits erhalten hat — versioniert, RLS-geschützt, auditiert, realtime-fähig. Kein Modul bleibt bei reinem SQLite-Zugriff aus der UI.
2. **Grundlegende Verbesserung von Code und Nutzererlebnis**: Jeder der 65 Screens aus `01_system_inventory.md` bekommt einen Design-Plan (professionelles, ruhiges Enterprise-Design) und einen Funktionsplan (vollständige, für professionelle Firmen belastbare Umsetzung) — nicht nur die in `Update_V9.1_restore.md` bereits benannten 14 Punkte, sondern die gesamte Anwendung.

## Bindende Entscheidung: Hybrid, nicht Cloud-only

Diese Charter **bestätigt und erweitert** die bestehenden Entscheidungen, sie widerspricht ihnen nicht:

- `DEC-002`: Supabase/PostgreSQL wird zentrale schreibende Wahrheit für alle Domänen, nicht nur Property.
- `DEC-004`: Online-first bleibt Zielmodus für Web/Desktop.
- ~~`DEC-005`: SQLite bleibt als Legacy-Quelle und optionaler späterer Client-Cache erhalten — es wird **nicht** hart entfernt, solange keine Migrations-/Paritätsfreigabe vorliegt (`MIG-BND-001`).~~ **Aufgehoben am 2026-08-06 durch `DEC-024`** (`AP-X02-1`): SQLite wird vollständig entfernt. Der Review-Trigger von `DEC-005` war erreicht — es existieren keine Legacy-Nutzdaten mehr, die Objektdaten waren Testdaten und wurden am 2026-08-04 bewusst entfernt. Damit ist die Migrations-/Paritätsfreigabe gegenstandslos, nicht offen.
- ~~Das bedeutet konkret: Für jede Domäne entsteht **derselbe Adapter-Bruch wie bei Property** — ein `legacy_sqlite_*_adapter` … und ein `supabase_*_adapter` …. Die App bleibt startfähig ohne Internet für den Übergangszeitraum.~~ **Ebenfalls aufgehoben durch `DEC-024`.** Es gilt: **ein Adapter je Domäne**, der Supabase-Adapter. Kein `legacy_sqlite_*_adapter` mehr für neue Domänen — bestehende werden in `AP-X02-2` entfernt. **Die Offline-Startfähigkeit entfällt ersatzlos**; es gibt keinen lokalen Speicher, keinen Lesecache und keinen Offline-Schreibpfad. Umsetzungsplan und Gates: `04y_p2_x02_sqlite_decommission.md`, Zielbild: `docs/architecture/cloud/01_target_cloud_architecture.md`.
- Kein Remote-/Staging-Supabase-Projekt, bis `DEC-015`..`DEC-017` entschieden sind. Alle Phase-2-Arbeit ist zunächst lokal (`supabase start`) zu verifizieren, exakt wie in Phase 1.

## Bindende Prinzipien für Phase 2

1. **Kein Neuerfinden des Musters.** Jede Domänen-Migration folgt exakt dem in `10_reference_slice_spec.md` und `12_phase_1_execution_backlog.md` bewiesenen Ablauf: Schema+RLS+Version+Audit-Migration → pgTAP+Rollback-Test → Repository-Contract (`domain/application/data`) → Adapter (legacy + Supabase) → Adapter-Tests → echter lokaler Client-Integrationstest → Realtime-Invalidierung → adaptive UI.
2. **Modulverträge sind bereits spezifiziert.** `05_target_module_contracts.md` definiert Ports, Ereignisse, Invarianten und die erlaubte Abhängigkeitsmatrix je Domäne — verbindlich, nicht neu verhandelbar in Phase 2.
3. **Bekannte Duplikate werden konsolidiert, nicht eingefroren.** `04_duplicate_and_debt_register.md` (`DUP-001`..`014`, `DEBT-001`..`016`, `BIG-001`..`031`) ist die Abarbeitungsliste für die Architektur-Modernisierung — siehe `02_architecture_modernization_backlog.md`.
4. **Design folgt Funktion, nicht umgekehrt.** Eine Domäne wird erst UI-seitig neu gestaltet, wenn ihr Backend-Vertrag steht — sonst entsteht Politur auf einem Fundament, das sich noch ändert.
4a. **Plan vor jeder Änderung, kein Blindstart.** Für jedes Arbeitspaket — Backend-Slice, einzelner Screen oder Refactor — wird vor der ersten Code-Änderung ein kurzer Funktions- und Design-Plan geschrieben und gezeigt (Ablauf in `05_claude_execution_prompt.md`). Ziel ist, einen falschen Ansatz vor dem Schreiben von Code abzufangen, nicht den Backlog-Eintrag zu wiederholen.
5. **Priorisierte Wellen, kein Big Bang.** Siehe `04_screen_redesign_wave_plan.md`. Jede Welle ist ein eigener, abnahmefähiger vertikaler Schnitt (Definition of Done aus `12_phase_1_execution_backlog.md` gilt unverändert plus die Design-Kriterien aus `03_design_system.md`).
6. **Offene Entscheidungen blockieren nicht, werden aber benannt.** `OPEN-001`..`005`, `OPN-DOM-001`..`005`, `DEC-014`..`017` bleiben in Kraft. Jedes Phase-2-Arbeitspaket, das von einer offenen Entscheidung abhängt, nennt sie explizit und schlägt eine Default-Annahme vor (siehe jeweiliges Register), statt sie stillschweigend zu treffen.

## Struktur dieses Ordners

| Datei | Inhalt |
|---|---|
| `00_phase_2_charter.md` | dieses Dokument |
| `01_domain_expansion_backlog.md` | P2-D-Backlog: Supabase-Ausweitung je Domäne, Abhängigkeitsreihenfolge, Gates |
| `02_architecture_modernization_backlog.md` | P2-A-Backlog: Code-Modernisierung, Konsolidierung V1/V2, Party-Modell, Datei-Zerlegung |
| `03_design_system.md` | professionelles Design-System (Tokens, Komponenten, Zustände, Responsive-Regeln) |
| `04_screen_redesign_wave_plan.md` | alle 65 Screens in priorisierten Wellen, mit Design-/Funktionsplan-Vorlage und zwei vollständig ausgearbeiteten Beispielen |
| `04x_p2_x01_supabase_main_host.md` | wellenübergreifender Cutover-Plan vom Reference Slice zur vollständigen Supabase-Hauptanwendung |
| `05_claude_execution_prompt.md` | Ausführungs-Prompt für Claude Code, welle- und domänenweise, modell-/tokenbewusst, mit Subagenten-Einsatz |

## Reihenfolge der Wellen (Kurzfassung, Details in den Backlog-Dateien)

Domänen-Reihenfolge folgt der Abhängigkeitskarte aus `02_domain_map.md` (`identity_access` zuerst, `reporting_analytics` zuletzt, da sie nur Read Models aller anderen konsumiert):

`identity_access` (Vollausbau) → `contacts_parties` (neu, kanonisches Party-Modell) → `documents_compliance` → `platform_audit_jobs` (Vollausbau) → `leasing_operations` → `maintenance_capex` → `valuation_transactions` → `finance_debt` → `reporting_analytics`

`P2-X01` läuft als wellenübergreifendes Host-Gate: AP0–AP3 werden nach Welle 5 und vor Welle 6 umgesetzt; AP4–AP6 schließen mit den verbleibenden Domänenmigrationen und müssen vor dem Phase-2-Gate abgeschlossen sein. Der Reference Slice bleibt Testreferenz, aber nicht dauerhaft die Supabase-Startoberfläche.

`portfolio_property` ist bereits Referenzschnitt und wird in Phase 2 nur noch UI-seitig auf das neue Design-System gehoben (Welle 1), nicht erneut backend-migriert.

## Nicht-Ziele (weiterhin gültig)

Aus `phase_0`/`phase_1` unverändert übernommen: kein Remote-/Produktions-Supabase ohne `DEC-015`..`017`, kein Offline-Schreibpfad außerhalb der in `08_sync_conflict_matrix.md` geprüften Fälle, keine automatisierte Mahnstufen-/Freigabe-Fachlogik ohne externe rechtliche Validierung (`OPN-DOM-003`, `OPN-DOM-004`, `DEC-014`).
