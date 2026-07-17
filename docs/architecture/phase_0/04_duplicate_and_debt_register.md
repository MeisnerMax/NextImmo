# Doppelungs- und Schuldenregister

Stand: 2026-07-12  
Statuswerte: `verified`, `inferred`, `open`. Dispositionen sind Phase-0-Empfehlungen, keine bereits ausgefuehrten Aenderungen.

## V1/V2 und funktionale Doppelungen

| ID | Befund | Status | Disposition | Evidenz |
|---|---|---|---|---|
| DUP-001 | Legacy- und V2-App-Shell (Sidebar/Topbar) werden parallel gepflegt und per Flag umgeschaltet. | verified | `merge`: V2 behalten, V1 nach Referenztests entfernen | `lib/ui/shell/app_scaffold.dart:55-158`, `lib/ui/shell/sidebar.dart`, `lib/ui/shell/v2/sidebar_v2.dart`, `lib/ui/shell/topbar.dart`, `lib/ui/shell/v2/topbar_v2.dart` |
| DUP-002 | `DashboardScreen` ist nur Wrapper auf `DashboardScreenV2`; das Flag erzeugt keine echte V1-Ausweichimplementierung. | verified | `remove_candidate`: Wrapper/Flag nach Integrationsreview entfernen | `lib/ui/screens/dashboard_screen.dart:5`, `lib/ui/shell/app_scaffold.dart:204` |
| DUP-003 | `PropertiesScreen` und `PropertiesScreenV2` sind echte Parallelimplementierungen fuer Liste/Detail-Einstieg. | verified | `merge`: V2 behalten, fehlende V1-Faelle vorher als Tests sichern | `lib/ui/screens/properties_screen.dart:13`, `lib/ui/screens/v2/properties_screen_v2.dart:23`, `lib/ui/shell/app_scaffold.dart:209` |
| DUP-004 | `PropertyShellV2` delegiert ausschliesslich an `PropertyShell`; das V2-Flag ist strukturell wirkungslos. | verified | `remove_candidate`: Wrapper/Flag entfernen, Shell spaeter modularisieren | `lib/ui/screens/v2/property_detail/property_shell_v2.dart:5`, `lib/ui/screens/v2/properties_screen_v2.dart:44` |
| DUP-005 | Vier Feature-Flags sind statische In-Memory-Defaults und kein persistenter Rolloutmechanismus. | verified | `replace`: Phase 1 mit konfigurierbaren, testbaren Flags oder nach Bereinigung entfernen | `lib/ui/state/ui_feature_flags.dart:3-28` |
| DUP-006 | Globale und objektbezogene Maintenance-Screens ueberlappen fachlich, haben aber verschiedene Scope- und Workflow-Implementierungen. | verified | `merge`: gemeinsames Application-Modul, getrennte Views | `lib/ui/screens/maintenance/maintenance_screen.dart:16`, `lib/ui/screens/property_detail/maintenance_screen.dart:17` |
| DUP-007 | Globale und objektbezogene Dokument-, Audit- und Task-Screens duplizieren Filter-, Dialog- und Tabellenlogik. | inferred | `merge`: gemeinsame ViewModels/Komponenten, Scope-Views behalten | `lib/ui/screens/docs/documents_screen.dart`, `lib/ui/screens/property_detail/property_documents_screen.dart`, `lib/ui/screens/audit/audit_screen.dart`, `lib/ui/screens/property_detail/property_audit_screen.dart`, `lib/ui/screens/tasks/tasks_screen.dart`, `lib/ui/screens/property_detail/property_tasks_screen.dart` |
| DUP-008 | `maintenance_ticket_history` wird in zwei Migrationen identisch mit `CREATE TABLE IF NOT EXISTS` angelegt. | verified | `merge`: bei Migrationszerlegung eine kanonische Definition | `lib/data/sqlite/migrations.dart:1157`, `lib/data/sqlite/migrations.dart:2224` |
| DUP-009 | `users` und `local_users` modellieren Benutzer parallel; produktive Security-Repositories verwenden nur `local_users`. | verified | `remove_candidate`: `users` nach Datenpruefung/migrationssicherer Ablosung | `lib/data/sqlite/migrations.dart:202`, `lib/data/sqlite/migrations.dart:1465`, `lib/data/repositories/security_repo.dart:32` |
| DUP-010 | `contacts`, `tenants`, `contractors` und freie Vendor-/Counterparty-Felder bilden Parteien mehrfach und ohne gemeinsame Identitaet ab. | verified | `merge`: kanonisches Party-Modell in Phase 2, fachliche Rollen erhalten | `lib/data/sqlite/migrations.dart:960`, `lib/data/sqlite/migrations.dart:3663`, `lib/data/sqlite/migrations.dart:4193`, `lib/data/sqlite/migrations.dart:798` |
| DUP-011 | Property-Onboarding-Dokumente (`property_document_checklist`) und allgemeines Dokument-Compliance-Modell (`documents`/`required_documents`) ueberlappen. | inferred | `merge`: Checkliste als Requirement/Workflow-Projektion | `lib/data/sqlite/migrations.dart:1392-1444`, `lib/data/sqlite/migrations.dart:3777` |
| DUP-012 | Quick Screening existiert als `quick_screenings` und `acquisition_quick_evaluations` mit aehnlichen Inputs/Resultaten. | verified | `merge`: eine Acquisition-Aggregatgrenze festlegen | `lib/data/sqlite/migrations.dart:3689`, `lib/data/sqlite/migrations.dart:3803` |
| DUP-013 | Sanierungsdaten liegen sowohl in `renovation_projects`/Asset Workbook als auch im neueren Szenario-/Impact-Modell. | verified | `merge`: Projekt als Root, Szenarien/Impacts als Children | `lib/data/sqlite/migrations.dart:2036`, `lib/data/sqlite/migrations.dart:3930-4016`, `lib/core/models/asset_workbook.dart` |
| DUP-014 | Datenqualitaet besteht aus Repository-Snapshots, `DataQualityService`, `DataQualityRulesV2` und `DataQualityScoring`. | verified | `merge`: eine Regelregistry und ein Ergebnisvertrag | `lib/data/repositories/data_quality_repo.dart`, `lib/core/quality/data_quality_service.dart`, `lib/core/quality/data_quality_rules_v2.dart`, `lib/core/quality/data_quality_scoring.dart` |

## Tote oder unklare Pfade

| ID | Befund | Status | Disposition | Evidenz |
|---|---|---|---|---|
| DEAD-001 | `SearchScreen` wird produktiv nicht importiert/instanziiert; nur ein Widget-Test referenziert ihn. Die Topbars nutzen eigene Such-/Palettenlogik. | verified | `open`: integrieren oder entfernen, Entscheidung vor Phase-1-Routing | `lib/ui/screens/search_screen.dart:11`, `test/ui/search/search_screen_test.dart:7`, `lib/ui/components/command_palette.dart` |
| DEAD-002 | `RentalOverviewScreen` ist in `AppScaffold` importiert, aber keinem `GlobalPage`-Zweig zugeordnet und sonst nicht instanziiert. | verified | `remove_candidate` oder als Portfolio-Unterseite anbinden | `lib/ui/shell/app_scaffold.dart:25`, `lib/ui/screens/rental_overview_screen.dart:8`, `lib/ui/state/app_state.dart:80` |
| DEAD-003 | Mehrere `PropertyDetailPage`-Werte fuer Verkauf, Hotel und Parken landen im generischen `PropertyTypeModuleScreen` statt eigenen Workflows. | verified | `open`: Produktumfang je Modultyp vor Phase 3/5 entscheiden | `lib/ui/state/app_state.dart:107`, `lib/ui/screens/property_detail/property_shell.dart`, `lib/ui/screens/property_detail/property_type_module_screen.dart:9` |

## Uebergrosse Dateien

Schwelle: mindestens 1.000 LOC (`verified`). Prioritaet bewertet Risiko und Aenderungshaeufigkeit, nicht sofortigen Refactoring-Auftrag.

| ID | LOC | Datei | Hauptschuld | Prioritaet |
|---|---:|---|---|---|
| BIG-001 | 4390 | `lib/data/sqlite/migrations.dart` | 94 Tabellen, Schema-Upgrades, Seeds und Datenkorrekturen gekoppelt | kritisch |
| BIG-002 | 3966 | `lib/ui/screens/property_detail/maintenance_screen.dart` | UI, Dialoge und Workflowlogik | hoch |
| BIG-003 | 3651 | `lib/ui/screens/property_detail/budget_vs_actual_screen.dart` | Tabellen, Eingaben und Finanzworkflow | hoch |
| BIG-004 | 3003 | `lib/ui/screens/portfolios_screen.dart` | Liste, Detail und Navigation in einer Datei | hoch |
| BIG-005 | 2896 | `lib/ui/screens/maintenance/maintenance_screen.dart` | globale Listen, Dialoge und Mutationen | hoch |
| BIG-006 | 2858 | `lib/ui/screens/property_detail/inputs_screen.dart` | grosses Bewertungsformular und State-Verknuepfung | hoch |
| BIG-007 | 2633 | `lib/ui/screens/v2/dashboard_screen_v2.dart` | Aggregation, Layout und Dialoge | hoch |
| BIG-008 | 2309 | `lib/ui/screens/property_detail/asset_workbook_screen.dart` | mehrere Fachbereiche/Tabs | hoch |
| BIG-009 | 2211 | `lib/ui/screens/settings_screen.dart` | Plattform-, Security- und Fachdefaults | hoch |
| BIG-010 | 2072 | `lib/ui/screens/property_detail/overview_screen.dart` | KPI-Aufbereitung und UI | mittel |
| BIG-011 | 1887 | `lib/ui/screens/tasks/tasks_screen.dart` | Filter, Listen und Editor | mittel |
| BIG-012 | 1791 | `lib/ui/screens/properties/property_creation_workflow_screen.dart` | Wizard, Validierung und Formulare | hoch |
| BIG-013 | 1564 | `lib/ui/screens/property_detail/scenarios_screen.dart` | Workflow, RBAC und Dialoge | hoch |
| BIG-014 | 1437 | `lib/data/repositories/property_repo.dart` | CRUD, Onboarding, Audit, Suche und Cascade-Delete | kritisch |
| BIG-015 | 1407 | `lib/ui/screens/property_detail/property_tasks_screen.dart` | Objekt-Task-Workflow | mittel |
| BIG-016 | 1399 | `lib/ui/screens/property_detail/unit_detail_screen.dart` | Detail, Formulare und Aktionen | mittel |
| BIG-017 | 1398 | `lib/ui/screens/budgets/budgets_screen.dart` | Budgetlisten und Editor | mittel |
| BIG-018 | 1386 | `lib/ui/screens/property_detail/units_screen.dart` | Liste, Filter und CRUD | mittel |
| BIG-019 | 1371 | `lib/ui/screens/quick_screening_screen.dart` | Inputs, Berechnung und Persistenz | mittel |
| BIG-020 | 1321 | `lib/ui/screens/property_detail/leases_screen.dart` | Vertragsliste und CRUD | hoch |
| BIG-021 | 1197 | `lib/ui/screens/tasks/task_templates_screen.dart` | Template-/Checklistenworkflow | mittel |
| BIG-022 | 1196 | `lib/ui/screens/docs/documents_screen.dart` | Dokumentworkflow und Compliance | hoch |
| BIG-023 | 1164 | `lib/ui/screens/imports_screen.dart` | Import-UI und Mapping | hoch |
| BIG-024 | 1162 | `lib/ui/screens/property_detail/property_shell.dart` | Navigation, Auto-Szenario und Modulrouting | hoch |
| BIG-025 | 1128 | `lib/data/repositories/asset_workbook_repo.dart` | mehrere Aggregate und SQL-Auswertungen | hoch |
| BIG-026 | 1029 | `lib/ui/screens/v2/properties_screen_v2.dart` | Liste, KPI-Laden, Karten und Dialoge | mittel |
| BIG-027 | 1020 | `lib/ui/screens/maintenance/contractors_screen.dart` | Liste und CRUD | mittel |
| BIG-028 | 1015 | `lib/ui/screens/renovation_value_screen.dart` | Inputs, Berechnung und Transfer | mittel |
| BIG-029 | 1014 | `lib/core/models/investment_modules.dart` | drei Domaenenmodule in einer DTO-Datei | mittel |
| BIG-030 | 1003 | `lib/ui/screens/disposition_exit_screen.dart` | Exit-Inputs, Berechnung und Angebote | mittel |
| BIG-031 | 1000 | `lib/ui/screens/criteria_sets_screen.dart` | Liste und Editor-Screen gekoppelt | mittel |

## Architektur- und Infrastrukturschulden

| ID | Befund/Auswirkung | Status | Disposition | Evidenz |
|---|---|---|---|---|
| DEBT-001 | Startpfad ist an `sqflite_common_ffi` gebunden; Web/Mobile koennen diesen Persistenzpfad nicht gemeinsam nutzen. | verified | `replace` in Phase 1 durch Repository-Ports/Remote-Adapter | `lib/main.dart:3-18`, `lib/data/sqlite/db.dart:16` |
| DEBT-002 | Fast alle Repositories und Services werden in einem 532-LOC-Provider-Modul konstruiert; Domaenen sind nicht isoliert. | verified | `refactor` pro Zielmodul bei vertikaler Migration | `lib/ui/state/app_state.dart:140-532` |
| DEBT-003 | Repositories sprechen konkrete SQLite-`Database` direkt an; Contract-Tests/Remote-Adapter sind nicht durch Interfaces erzwungen. | verified | `refactor` mit Domain-Ports, keine Big-Bang-Umstellung | `lib/data/repositories/*.dart`, `lib/ui/state/app_state.dart:175` |
| DEBT-004 | Nur drei Fachtabellen tragen `workspace_id`; Objekt-, Vertrags-, Finanz- und Dokumentdaten sind nicht per Schema mandantenisoliert. | verified | `replace` im PostgreSQL-Zielschema mit Default-Deny-RLS | `docs/architecture/phase_0/03_data_dictionary.md`, `lib/data/sqlite/migrations.dart:1457-1488` |
| DEBT-005 | Lokale Authentifizierung/Sitzungen und Client-RBAC ersetzen keine serverseitige Autorisierung. | verified | `replace` durch Supabase Auth, Membership und RLS | `lib/data/repositories/security_repo.dart`, `lib/core/security/rbac.dart` |
| DEBT-006 | Polymorphe `entity_type/entity_id`-Referenzen verhindern FK-Integritaet und erschweren RLS/Audit-Aufloesung. | verified | `refactor` je Modul mit typisierten Links oder kontrollierter Entity-Registry | `notes`, `notifications`, `tasks`, `documents`, `budgets`, `ledger_entries`, `search_index` in `migrations.dart` |
| DEBT-007 | Dokumente und Reports referenzieren lokale Dateipfade; Zugriff, Versionierung und zentrale Freigabe fehlen. | verified | `replace` durch private Storage-Objekte und Metadaten | `lib/data/sqlite/migrations.dart:401-437`, `lib/data/sqlite/migrations.dart:1401-1414` |
| DEBT-008 | Backup-Restore extrahiert Archivpfade direkt und ersetzt lokale Daten-/Dokumentverzeichnisse; Hash wird im Manifest erzeugt, im gezeigten Restorepfad aber nicht vor Restore validiert. | verified | `refactor`: Pfadvalidierung, Hashpflicht, Restore-Reconciliation | `lib/core/services/backup_service.dart:50-191`, `lib/core/services/backup_restore_service.dart` |
| DEBT-009 | Periodische Task-Erzeugung wird durch einen stündlichen UI-Timer ausgelöst und ist an eine laufende Client-Shell gekoppelt. | verified | `replace` durch serverseitigen Job; lokale Idempotenz behalten | `lib/ui/shell/app_scaffold.dart:46-51`, `lib/ui/shell/app_scaffold.dart:161-197` |
| DEBT-010 | Fachwerte fuer Geld und Quoten liegen ueberwiegend als SQLite `REAL`; Rundung/Waehrung sind nicht schemaweit erzwungen. | verified | `replace` durch PostgreSQL `numeric` plus Currency/Formula Contracts | `lib/data/sqlite/migrations.dart` |
| DEBT-011 | Mehrere Tabellen haben keine deklarierte Eltern-FK trotz logischer Property-/Entity-Zuordnung; verwaiste Daten sind moeglich. | verified | `refactor` in Migrationsmapping und Reconciliation pruefen | `asset_operating_cost_history`, `operations_alert_states`, polymorphe Tabellen in `migrations.dart` |
| DEBT-012 | `PropertyRepository.deletePermanently` buendelt manuelle Cascade-Logik fuer viele Domaenen; neue Tabellen koennen vergessen werden. | verified | `replace` durch Archivierung/Tombstone und serverseitige Transaktion | `lib/data/repositories/property_repo.dart` |
| DEBT-013 | Mehrere Repositories haben optionale Audit-Abhaengigkeiten; Mutationen koennen ohne AuditWriter ausgefuehrt werden. | verified | `refactor`: Audit fuer kritische Ports verpflichtend | `lib/data/repositories/documents_repo.dart:13-30`, `lib/ui/state/app_state.dart` |
| DEBT-014 | Schema-Definition, inkrementelle ALTERs, Seeds und Datenkorrekturen liegen in einer einzigen Migrationsklasse. | verified | `refactor` nur im Migrationsprojekt; Golden Master vorher sichern | `lib/data/sqlite/migrations.dart:1-4390` |
| DEBT-015 | `app_settings` mischt UI, fachliche Defaults, Backup, aktive Identitaet und lokale Security-Secrets. | verified | `split` nach User Preferences, Workspace Config und Secret/Auth State | `lib/data/sqlite/migrations.dart:210-235`, `lib/data/sqlite/migrations.dart:503-1883` |
| DEBT-016 | Automatisierte Tests decken 81 Dateien ab, aber 65 Screen-Eintraege und 94 Tabellen nicht systematisch per Contract/Responsive/E2E-Matrix. | inferred | `refactor`: risikobasierte Baseline in `09_test_baseline.md` | `test/`, `docs/architecture/phase_0/01_system_inventory.md` |

## Offene Entscheidungen

| ID | Entscheidung | Auswirkung | Default-Annahme | Spaetestens | Status |
|---|---|---|---|---|---|
| OPEN-001 | Kanonisches Party-Modell fuer User, Kontakt, Mieter, Dienstleister und Kaeufer | PII, Rollen, Dubletten, Migration | getrennte fachliche Rollen, gemeinsame Party-ID | vor Phase 2 Schema | open |
| OPEN-002 | Disposition von Legacy `users` | Datenverlust-/Altbestandrisiko | read-only pruefen, nicht ungeprueft loeschen | vor SQLite-Import-Mapping | open |
| OPEN-003 | Produktstatus von Search- und Rental-Overview-Screens | Navigation und Featureumfang | nicht als produktiv zugesichert | vor Phase-1-Routingvertrag | open |
| OPEN-004 | Ein oder zwei Acquisition-Schnellpruefungsmodelle | KPI-/Historienkonsistenz | `acquisition_quick_evaluations` als Ziel, Altbestand mappen | vor Phase 5 | open |
| OPEN-005 | Welche Property-Type-Module produktiv bleiben | Mobile/Tablet-Scope und Datenmodell | bestehende Daten erhalten, neue Workflows defer | vor Phase 2 Importvertrag | open |
