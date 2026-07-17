# Systeminventar

Stand: 2026-07-12  
Status: `verified`  
Scope: produktiver Dart-Code unter `lib/` und Tests unter `test/`. Primaerdomaenen: `identity_access` (IA), `portfolio_property` (PP), `contacts_parties` (CP), `leasing_operations` (LO), `maintenance_capex` (MC), `documents_compliance` (DC), `finance_debt` (FD), `valuation_transactions` (VT), `reporting_analytics` (RA), `platform_audit_jobs` (PA).

## Laufzeit und Navigation

| ID | Element | Primaerdomaene | Status | Evidenz |
|---|---|---|---|---|
| SYS-001 | Windows-/Desktop-Start mit SQLite-FFI, Security-Bootstrap und periodischer Task-Erzeugung | PA | verified | `lib/main.dart:14`, `lib/data/sqlite/db.dart:10` |
| SYS-002 | `MaterialApp` mit `SecurityGate` als einzigem Root | IA | verified | `lib/app.dart:8`, `lib/app.dart:30` |
| SYS-003 | Zustandsbasierte Navigation ohne deklarativen Router; 23 globale Ziele | PA | verified | `lib/ui/state/app_state.dart:80`, `lib/ui/shell/app_scaffold.dart:199` |
| SYS-004 | Property-Navigation ueber `PropertyDetailPage`; 32 Zielwerte, teils generische Modulseiten | PP | verified | `lib/ui/state/app_state.dart:107`, `lib/ui/screens/property_detail/property_shell.dart:40` |
| SYS-005 | V1/V2-Auswahl ueber vier In-Memory-Feature-Flags; Defaults alle `true` | PA | verified | `lib/ui/state/ui_feature_flags.dart:3`, `lib/ui/shell/app_scaffold.dart:55` |
| SYS-006 | Zentraler Riverpod-Composition-Root fuer Datenbank, Repositories, Engines und Services | PA | verified | `lib/ui/state/app_state.dart:140` |

Globale Ziele (`verified`): `dashboard`, `properties`, `ledger`, `budgets`, `maintenance`, `contractors`, `tasks`, `taskTemplates`, `portfolios`, `imports`, `notifications`, `esg`, `documents`, `audit`, `compare`, `quickScreening`, `renovationValue`, `dispositionExit`, `criteriaSets`, `reportTemplates`, `adminUsers`, `settings`, `help`.

Property-Ziele (`verified`): `overview`, `inputs`, `analysis`, `comps`, `criteria`, `offer`, `scenarios`, `versions`, `audit`, `documents`, `reports`, `operationsOverview`, `tasks`, `units`, `tenants`, `leases`, `rentRoll`, `assetWorkbook`, `alerts`, `budgetVsActual`, `maintenance`, `covenants`, `saleData`, `buyerInterests`, `viewings`, `saleOffers`, `reservations`, `guests`, `housekeeping`, `hotelRevenue`, `parkingStorage`, `unitSaleStatus`.

## Produktive Screens

`aktiv` bedeutet direkt aus Shell, Gate oder Property-Shell erreichbar; `eingebettet` wird von einem aktiven Screen/Dialog geoeffnet; `wrapper` delegiert ohne eigene Fachfunktion. LOC ist der Dateiumfang zum Inventarzeitpunkt.

| ID | Screen/Shell | Domaene | Zustand | LOC | Evidenz |
|---|---|---|---|---:|---|
| SCR-001 | `SecurityGate` | IA | aktiv | 44 | `lib/ui/screens/security/security_gate.dart:9` |
| SCR-002 | `LockScreen` | IA | eingebettet | 93 | `lib/ui/screens/security/lock_screen.dart:5` |
| SCR-003 | `AppScaffold` | PA | aktiv | 279 | `lib/ui/shell/app_scaffold.dart:39` |
| SCR-004 | `DashboardScreenV2` | RA | aktiv | 2633 | `lib/ui/screens/v2/dashboard_screen_v2.dart:254` |
| SCR-005 | `DashboardScreen` | RA | wrapper | 12 | `lib/ui/screens/dashboard_screen.dart:5` |
| SCR-006 | `PropertiesScreenV2` | PP | aktiv | 1029 | `lib/ui/screens/v2/properties_screen_v2.dart:23` |
| SCR-007 | `PropertiesScreen` | PP | alternativ V1 | 339 | `lib/ui/screens/properties_screen.dart:13` |
| SCR-008 | `PropertyCreationWorkflowScreen` | PP | eingebettet | 1791 | `lib/ui/screens/properties/property_creation_workflow_screen.dart:10` |
| SCR-009 | `PropertyShellV2` | PP | wrapper | 12 | `lib/ui/screens/v2/property_detail/property_shell_v2.dart:5` |
| SCR-010 | `PropertyShell` | PP | aktiv | 1162 | `lib/ui/screens/property_detail/property_shell.dart:40` |
| SCR-011 | `OverviewScreen` | PP | aktiv | 2072 | `lib/ui/screens/property_detail/overview_screen.dart:20` |
| SCR-012 | `InputsScreen` | VT | aktiv | 2858 | `lib/ui/screens/property_detail/inputs_screen.dart:24` |
| SCR-013 | `AnalysisScreen` | VT | aktiv | 540 | `lib/ui/screens/property_detail/analysis_screen.dart:12` |
| SCR-014 | `CompsScreen` | VT | aktiv | 457 | `lib/ui/screens/property_detail/comps_screen.dart:11` |
| SCR-015 | `CriteriaCheckScreen` | VT | aktiv | 332 | `lib/ui/screens/property_detail/criteria_check_screen.dart:11` |
| SCR-016 | `OfferScreen` | VT | aktiv | 248 | `lib/ui/screens/property_detail/offer_screen.dart:11` |
| SCR-017 | `ScenariosScreen` | VT | aktiv | 1564 | `lib/ui/screens/property_detail/scenarios_screen.dart:21` |
| SCR-018 | `ScenarioVersionsScreen` | VT | aktiv | 563 | `lib/ui/screens/property_detail/scenario_versions_screen.dart:10` |
| SCR-019 | `PropertyAuditScreen` | PA | aktiv | 473 | `lib/ui/screens/property_detail/property_audit_screen.dart:15` |
| SCR-020 | `PropertyDocumentsScreen` | DC | aktiv | 922 | `lib/ui/screens/property_detail/property_documents_screen.dart:15` |
| SCR-021 | `ReportsScreen` | RA | aktiv | 340 | `lib/ui/screens/property_detail/reports_screen.dart:15` |
| SCR-022 | `OperationsOverviewScreen` | LO | aktiv | 397 | `lib/ui/screens/property_detail/operations_overview_screen.dart:8` |
| SCR-023 | `PropertyTasksScreen` | PA | aktiv | 1407 | `lib/ui/screens/property_detail/property_tasks_screen.dart:9` |
| SCR-024 | `UnitsScreen` | LO | aktiv | 1386 | `lib/ui/screens/property_detail/units_screen.dart:13` |
| SCR-025 | `UnitDetailScreen` | LO | eingebettet | 1399 | `lib/ui/screens/property_detail/unit_detail_screen.dart:13` |
| SCR-026 | `TenantsScreen` | LO | aktiv | 716 | `lib/ui/screens/property_detail/tenants_screen.dart:13` |
| SCR-027 | `TenantDetailScreen` | LO | eingebettet | 395 | `lib/ui/screens/property_detail/tenant_detail_screen.dart:10` |
| SCR-028 | `LeasesScreen` | LO | aktiv | 1321 | `lib/ui/screens/property_detail/leases_screen.dart:11` |
| SCR-029 | `LeaseDetailScreen` | LO | eingebettet | 920 | `lib/ui/screens/property_detail/lease_detail_screen.dart:10` |
| SCR-030 | `RentRollScreen` | LO | aktiv | 567 | `lib/ui/screens/property_detail/rent_roll_screen.dart:9` |
| SCR-031 | `AssetWorkbookScreen` | FD | aktiv | 2309 | `lib/ui/screens/property_detail/asset_workbook_screen.dart:15` |
| SCR-032 | `OperationsAlertsScreen` | LO | aktiv | 609 | `lib/ui/screens/property_detail/operations_alerts_screen.dart:9` |
| SCR-033 | `BudgetVsActualScreen` | FD | aktiv | 3651 | `lib/ui/screens/property_detail/budget_vs_actual_screen.dart:21` |
| SCR-034 | `PropertyMaintenanceScreen` | MC | aktiv | 3966 | `lib/ui/screens/property_detail/maintenance_screen.dart:17` |
| SCR-035 | `CovenantsScreen` | FD | aktiv | 699 | `lib/ui/screens/property_detail/covenants_screen.dart:10` |
| SCR-036 | `PropertyTypeModuleScreen` | PP | aktiv fuer Verkauf/Hotel/Parken | 293 | `lib/ui/screens/property_detail/property_type_module_screen.dart:9` |
| SCR-037 | `LedgerScreen` | FD | aktiv | 719 | `lib/ui/screens/ledger/ledger_screen.dart:10` |
| SCR-038 | `BudgetsScreen` | FD | aktiv | 1398 | `lib/ui/screens/budgets/budgets_screen.dart:14` |
| SCR-039 | `MaintenanceScreen` | MC | aktiv | 2896 | `lib/ui/screens/maintenance/maintenance_screen.dart:16` |
| SCR-040 | `ContractorsScreen` | CP | aktiv | 1020 | `lib/ui/screens/maintenance/contractors_screen.dart:12` |
| SCR-041 | `TasksScreen` | PA | aktiv | 1887 | `lib/ui/screens/tasks/tasks_screen.dart:12` |
| SCR-042 | `TaskTemplatesScreen` | PA | aktiv | 1197 | `lib/ui/screens/tasks/task_templates_screen.dart:11` |
| SCR-043 | `PortfoliosScreen` | PP | aktiv | 3003 | `lib/ui/screens/portfolios_screen.dart:26` |
| SCR-044 | `PortfolioDetailScreen` | PP | eingebettet | 3003 | `lib/ui/screens/portfolios_screen.dart:1591` |
| SCR-045 | `PortfolioAnalyticsScreen` | RA | eingebettet | 498 | `lib/ui/screens/portfolio/portfolio_analytics_screen.dart:14` |
| SCR-046 | `DataQualityDashboardScreen` | RA | eingebettet | 303 | `lib/ui/screens/portfolio/data_quality_dashboard_screen.dart:9` |
| SCR-047 | `PortfolioPackScreen` | RA | eingebettet | 732 | `lib/ui/screens/portfolio/portfolio_pack_screen.dart:21` |
| SCR-048 | `ImportsScreen` | PA | aktiv | 1164 | `lib/ui/screens/imports_screen.dart:19` |
| SCR-049 | `NotificationsScreen` | PA | aktiv | 120 | `lib/ui/screens/notifications_screen.dart:8` |
| SCR-050 | `EsgDashboardScreen` | RA | aktiv | 842 | `lib/ui/screens/esg_dashboard_screen.dart:22` |
| SCR-051 | `DocumentsScreen` | DC | aktiv | 1196 | `lib/ui/screens/docs/documents_screen.dart:14` |
| SCR-052 | `ComplianceDashboardScreen` | DC | eingebettet | 119 | `lib/ui/screens/docs/compliance_dashboard_screen.dart:10` |
| SCR-053 | `AuditScreen` | PA | aktiv | 690 | `lib/ui/screens/audit/audit_screen.dart:19` |
| SCR-054 | `CompareScreen` | VT | aktiv | 746 | `lib/ui/screens/compare_screen.dart:27` |
| SCR-055 | `QuickScreeningScreen` | VT | aktiv | 1371 | `lib/ui/screens/quick_screening_screen.dart:22` |
| SCR-056 | `RenovationValueScreen` | MC | aktiv | 1015 | `lib/ui/screens/renovation_value_screen.dart:13` |
| SCR-057 | `DispositionExitScreen` | VT | aktiv | 1003 | `lib/ui/screens/disposition_exit_screen.dart:13` |
| SCR-058 | `CriteriaSetsScreen` | VT | aktiv | 1000 | `lib/ui/screens/criteria_sets_screen.dart:14` |
| SCR-059 | `_CriteriaSetEditorScreen` | VT | eingebettet/privat | 1000 | `lib/ui/screens/criteria_sets_screen.dart:293` |
| SCR-060 | `ReportTemplatesScreen` | RA | aktiv | 678 | `lib/ui/screens/report_templates_screen.dart:13` |
| SCR-061 | `UsersScreen` | IA | aktiv | 547 | `lib/ui/screens/admin/users_screen.dart:12` |
| SCR-062 | `SettingsScreen` | PA | aktiv | 2211 | `lib/ui/screens/settings_screen.dart:17` |
| SCR-063 | `HelpScreen` | PA | aktiv | 344 | `lib/ui/screens/help_screen.dart:11` |
| SCR-064 | `SearchScreen` | PA | eingebettet ueber Topbar/Palette | 137 | `lib/ui/screens/search_screen.dart:11` |
| SCR-065 | `RentalOverviewScreen` | LO | eingebettet in Portfolio | 523 | `lib/ui/screens/rental_overview_screen.dart:8` |

## Modelle

Jede Modell-Datei ist genau einer Primaerdomaene zugeordnet. Symbole sind vollstaendig pro Datei zusammengefasst.

| ID | Domaene | Datei | Hauptsymbole | Status |
|---|---|---|---|---|
| MOD-001 | VT | `lib/core/models/analysis_result.dart` | `DerivedProformaYear`, `DerivedProformaMonth`, `AmortizationEntry`, `AnalysisMetrics`, `AnalysisResult` | verified |
| MOD-002 | FD | `lib/core/models/asset_workbook.dart` | Operating-Cost-, Rental-Plan-, Hotel-KPI-, Renovation-, Settlement-, Deposit-, Payment- und Workbook-Records | verified |
| MOD-003 | PA | `lib/core/models/audit_log.dart` | `AuditDiffItem`, `AuditLogRecord` | verified |
| MOD-004 | FD | `lib/core/models/budget.dart` | `BudgetRecord`, `BudgetLineRecord`, `BudgetVarianceRecord`, `BudgetDetail` | verified |
| MOD-005 | FD | `lib/core/models/capital_event.dart` | `CapitalEventRecord` | verified |
| MOD-006 | VT | `lib/core/models/comps.dart` | `CompSale`, `CompRental` | verified |
| MOD-007 | CP | `lib/core/models/contractor.dart` | `ContractorRecord` | verified |
| MOD-008 | FD | `lib/core/models/covenant.dart` | `LoanRecord`, `LoanPeriodRecord`, `CovenantRecord`, `CovenantCheckRecord` | verified |
| MOD-009 | VT | `lib/core/models/criteria.dart` | `CriteriaSet`, `CriteriaRule`, `RuleEvaluation`, `CriteriaEvaluationResult` | verified |
| MOD-010 | DC | `lib/core/models/documents.dart` | Dokumenttyp, Dokument, Metadaten, Pflichtdokument, Compliance und Workflow | verified |
| MOD-011 | RA | `lib/core/models/esg.dart` | `EsgProfileRecord` | verified |
| MOD-012 | PA | `lib/core/models/import_job.dart` | `ImportJobRecord`, `ImportMappingRecord` | verified |
| MOD-013 | VT | `lib/core/models/inputs.dart` | `IncomeLine`, `ExpenseLine`, `ScenarioInputs`, `NormalizedInputs` | verified |
| MOD-014 | VT | `lib/core/models/investment_modules.dart` | Datasheet/Formelaudit sowie Acquisition-, Renovation- und Disposition-DTOs | verified |
| MOD-015 | FD | `lib/core/models/ledger.dart` | `LedgerAccountRecord`, `LedgerEntryRecord`, `LedgerPeriodAggregate` | verified |
| MOD-016 | MC | `lib/core/models/maintenance.dart` | Ticket, Historie und Workflow | verified |
| MOD-017 | PA | `lib/core/models/note.dart` | `NoteRecord` | verified |
| MOD-018 | PA | `lib/core/models/notification.dart` | `NotificationRecord` | verified |
| MOD-019 | LO | `lib/core/models/operations.dart` | Unit, Tenant, Lease, Rent Roll, Alerts, Detail-Bundles und Rechenergebnisse | verified |
| MOD-020 | RA | `lib/core/models/portfolio_analytics.dart` | Cashflow, IRR, Metrics und Property-KPIs | verified |
| MOD-021 | RA | `lib/core/models/portfolio_pack.dart` | Plan, Datei und Build-Output | verified |
| MOD-022 | PP | `lib/core/models/portfolio.dart` | Portfolio, Property-Link, Profile und KPI-Snapshot | verified |
| MOD-023 | PP | `lib/core/models/property.dart` | `PropertyRecord`, `PropertyKind` | verified |
| MOD-024 | PP | `lib/core/models/property_creation.dart` | Creation-Drafts, Metriken, Assessment, Quality und Step-State | verified |
| MOD-025 | PP | `lib/core/models/property_modules.dart` | Contact, Sale Details, Buyer Interest, Reservation, Unit Sale | verified |
| MOD-027 | RA | `lib/core/models/report_templates.dart` | `ReportTemplateRecord`, `ReportRecord` | verified |
| MOD-028 | RA | `lib/core/models/reports_dto.dart` | `ReportExportDto` | verified |
| MOD-029 | VT | `lib/core/models/scenario.dart` | `ScenarioWorkflowStatus`, `ScenarioRecord` | verified |
| MOD-030 | VT | `lib/core/models/scenario_valuation.dart` | `ScenarioValuationRecord` | verified |
| MOD-031 | VT | `lib/core/models/scenario_version.dart` | Version, Notes-Payload und Blob | verified |
| MOD-032 | PA | `lib/core/models/search.dart` | `SearchIndexRecord` | verified |
| MOD-033 | IA | `lib/core/models/security.dart` | Workspace, LocalUser, Session und SecurityContext | verified |
| MOD-034 | PA | `lib/core/models/settings.dart` | `AppSettingsRecord` | verified |
| MOD-035 | PA | `lib/core/models/task.dart` | Task, Checkliste, Template, Generierung und Workflow | verified |
| MOD-036 | VT | `lib/core/models/valuation.dart` | `ValuationPropertySnapshot`, `QuickScreeningRecord` | verified |

## Repositories, Services und Provider

| ID | Domaene | Inventar | Status/Evidenz |
|---|---|---|---|
| REP-001 | PP | `property_repo`, `property_profile_repo`, `property_modules_repo`, `portfolio_repo` | verified; `lib/data/repositories/` |
| REP-002 | VT | `scenario_repo`, `scenario_version_repo`, `scenario_valuation_repo`, `valuation_data_repo`, `inputs_repo`, `comps_repo`, `criteria_repo`, `compare_repo`, `calculation_datasheet_repo` | verified; `lib/data/repositories/` |
| REP-003 | LO | `operations_repo`, `lease_repo`, `rent_roll_repo` | verified; `lib/data/repositories/` |
| REP-004 | MC | `maintenance_repo`, `contractor_repo` | verified; `lib/data/repositories/` |
| REP-005 | DC | `documents_repo`, `document_types_repo`, `required_documents_repo` | verified; `lib/data/repositories/` |
| REP-006 | FD | `ledger_repo`, `budget_repo`, `covenant_repo`, `capital_events_repo`, `asset_workbook_repo` | verified; `lib/data/repositories/` |
| REP-007 | RA | `reports_repo`, `portfolio_analytics_repo`, `data_quality_repo`, `esg_repo` | verified; `lib/data/repositories/` |
| REP-008 | IA | `security_repo`, `workspace_repo`, `permission_guard` | verified; `lib/data/repositories/` |
| REP-009 | PA | `audit_log_repo`, `tasks_repo`, `notifications_repo`, `notes_repo`, `imports_repo`, `search_repo` | verified; `lib/data/repositories/` |
| SVC-001 | VT | `AcquisitionCalculationService`, `DatasheetBuilderService`, `DatasheetExportService`, `DispositionCalculationService`, `FormulaAuditService`, `RenovationCalculationService`; Engines fuer Analysis, IRR, Proforma, Sensitivity, Offer und Criteria | verified; `lib/core/services/`, `lib/core/engine/`, `lib/core/offer/`, `lib/core/criteria/` |
| SVC-008 | PP | `PropertyCreationValidationService`, `PropertyCreationCalculationsService` | verified; `lib/core/services/property_creation_validation_service.dart` |
| SVC-002 | FD | `LedgerService`, `BudgetVsActual`, `CovenantEngine`, `PortfolioIrrEngine` | verified; `lib/core/services/ledger_service.dart`, `lib/core/finance/` |
| SVC-003 | LO | `LeaseIndexationEngine`, `OperationsDataQualityEngine`, `RentRollEngine` | verified; `lib/core/operations/` |
| SVC-004 | DC | `DocComplianceEngine` | verified; `lib/core/docs/doc_compliance_engine.dart` |
| SVC-005 | RA | `DataQualityService`, `DataQualityRulesV2`, `DataQualityScoring`, `ReportBuilder`, `ReportTemplateFactory`, `PortfolioPackBuilder`, `CsvExporter` | verified; `lib/core/quality/`, `lib/core/reports/` |
| SVC-006 | IA | `Rbac`, `PasswordHasher` | verified; `lib/core/security/` |
| SVC-007 | PA | `AuditService`, `AuditWriter`, `BackupService`, `BackupRestoreService`, `StartupTaskService`, `TaskGenerationService`, `ZipService`, `NotificationRules` | verified; `lib/core/audit/`, `lib/core/services/`, `lib/core/notifications/` |
| PRV-001 | PA | Datenbank- und Navigations-State sowie 40 Repository-/Service-/Engine-Provider in einem Modul | verified; `lib/ui/state/app_state.dart:140` |
| PRV-002 | PP | Property-, Scenario-, Analysis-, Criteria- und Version-Controller | verified; `lib/ui/state/property_state.dart`, `scenario_state.dart`, `analysis_state.dart`, `criteria_state.dart`, `scenario_versions_state.dart` |
| PRV-003 | IA | Security-Controller und aktive User-/Workspace-/Role-Provider | verified; `lib/ui/state/security_state.dart:34` |
| PRV-004 | PA | Vier UI-Feature-Flags | verified; `lib/ui/state/ui_feature_flags.dart:3` |

Hinweis: Alle 39 Dateien unter `lib/data/repositories/` und alle 35 Dateien unter `lib/core/models/` sind durch REP-001..009 bzw. MOD-001..036 abgedeckt.

## Testinventar

| ID | Ebene | Anzahl | Vollstaendige Dateievidenz | Status |
|---|---|---:|---|---|
| TST-001 | Core Unit | 24 | `test/core/criteria/criteria_engine_test.dart`, `test/core/docs/doc_compliance_engine_test.dart`, `test/core/engine/{analysis_engine,irr,proforma,sensitivity}_test.dart`, `test/core/finance/{budget_vs_actual,covenant_engine,portfolio_irr_engine}_test.dart`, `test/core/models/scenario_inputs_defaults_test.dart`, `test/core/notifications/notification_rules_test.dart`, `test/core/offer/offer_solver_test.dart`, `test/core/operations/{lease_indexation_engine,operations_data_quality_engine,rent_roll_engine}_test.dart`, `test/core/quality/data_quality_scoring_test.dart`, `test/core/reports/{portfolio_pack_builder,report_builder}_test.dart`, `test/core/security/{password_hasher,rbac}_test.dart`, `test/core/services/{backup_service,ledger_service,task_generation_service}_test.dart`, `test/core/versioning/scenario_versioning_test.dart` | verified |
| TST-002 | Repository/SQLite | 27 | `test/data/repositories/{audit_log,budget,compare,covenant,criteria,data_quality,documents,esg,imports,inputs,inputs_audit,lease,ledger,maintenance,operations,portfolio_analytics,portfolio,property_modules,rent_roll,reports,scenario,scenario_valuation,scenario_version,search,security,tasks}_repo_test.dart`, `test/data/sqlite/migrations_test.dart` | verified |
| TST-003 | UI/Widget | 26 | `test/ui/audit/audit_screen_test.dart`, `test/ui/dashboard/dashboard_screen_v2_test.dart`, `test/ui/docs/documents_screen_test.dart`, `test/ui/ledger/ledger_screen_test.dart`, `test/ui/portfolio/{data_quality_dashboard_screen,portfolio_analytics_screen}_test.dart`, `test/ui/properties/create_property_dialog_test.dart`, `test/ui/property_detail/{budget_vs_actual_screen,inputs_screen,maintenance_screen,operations_alerts_screen,operations_overview_screen,property_audit_screen,property_shell_navigation,rent_roll_screen,scenarios_rbac}_test.dart`, `test/ui/search/search_screen_test.dart`, `test/ui/security/security_gate_test.dart`, `test/ui/state/{scenario_analysis_load_smoke,ui_feature_flags}_test.dart`, `test/ui/tasks/{task_templates_screen,tasks_screen}_test.dart`, `test/ui/theme/app_theme_test.dart`, `test/ui/utils/number_parse_test.dart`, `test/ui/widgets/{info_tooltip,kpi_tile}_test.dart` | verified |
| TST-004 | Integration | 2 | `test/integration/app_flow_test.dart`, `test/integration/backup_restore_integration_test.dart` | verified |
| TST-005 | Root/Smoke/Layout | 2 | `test/widget_test.dart`, `test/debug_layout_test.dart` | verified |

Gesamt: 81 Testdateien. Kein Verzeichnis `integration_test/` vorhanden (`verified`).

## Infrastrukturkopplungen

| ID | Kopplung | Domaene | Status | Evidenz |
|---|---|---|---|---|
| INF-001 | `sqflite_common_ffi` wird im Startpfad global initialisiert | PA | verified | `lib/main.dart:3`, `lib/main.dart:16` |
| INF-002 | Repositories erhalten konkrete `Database`-Instanzen statt Ports/Interfaces | PA | verified | `lib/ui/state/app_state.dart:175`, `lib/data/repositories/property_repo.dart:20` |
| INF-003 | SQLite-Pfad liegt im lokalen Application-Support-Verzeichnis | PA | verified | `lib/data/sqlite/db.dart:43` |
| INF-004 | Dokumente werden als lokaler `file_path` referenziert | DC | verified | `lib/data/sqlite/migrations.dart:1401`, `lib/data/repositories/documents_repo.dart:87` |
| INF-005 | Backup/Restore liest und ersetzt lokale DB-/Dokumentdateien direkt | PA | verified | `lib/core/services/backup_service.dart:50`, `lib/core/services/backup_restore_service.dart:31` |
| INF-006 | Timer fuer Task-Generierung lebt in der UI-Shell | PA | verified | `lib/ui/shell/app_scaffold.dart:46`, `lib/ui/shell/app_scaffold.dart:161` |
| INF-007 | Authentifizierung, Rollen und Sitzungen sind lokale SQLite-Daten | IA | verified | `lib/data/sqlite/migrations.dart:1457`, `lib/data/repositories/security_repo.dart:18` |

## Vollstaendigkeitsstatus

| Gate | Ergebnis | Status |
|---|---|---|
| Alle eindeutigen SQLite-Tabellen erfasst | 94/94; Details in `03_data_dictionary.md` | verified |
| Alle produktiven Screen-Klassen/Shells erfasst | 65 Eintraege inkl. Wrapper und eingebetteter Screens | verified |
| Modelle, Repositories, Services und Provider erfasst | dateibasiert vollstaendig | verified |
| Tests erfasst | 81/81 Dateien | verified |
| Doppelungen, grosse Dateien und Schulden erfasst | siehe `04_duplicate_and_debt_register.md` | verified |
