import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/audit/audit_writer.dart';
import '../../core/criteria/criteria_engine.dart';
import '../../core/engine/analysis_engine.dart';
import '../../core/engine/sensitivity.dart';
import '../../core/docs/doc_compliance_engine.dart';
import '../../core/finance/budget_vs_actual.dart';
import '../../core/finance/covenant_engine.dart';
import '../../core/finance/portfolio_irr_engine.dart';
import '../../core/notifications/notification_rules.dart';
import '../../core/offer/offer_solver.dart';
import '../../core/operations/lease_indexation_engine.dart';
import '../../core/operations/rent_roll_engine.dart';
import '../../core/quality/data_quality_service.dart';
import '../../core/services/acquisition_calculation_service.dart';
import '../../core/reports/export_csv.dart';
import '../../core/reports/portfolio_pack_builder.dart';
import '../../core/reports/report_builder.dart';
import '../../core/reports/report_templates.dart';
import '../../core/services/datasheet_builder_service.dart';
import '../../core/services/datasheet_export_service.dart';
import '../../core/services/disposition_calculation_service.dart';
import '../../core/services/formula_audit_service.dart';
import '../../core/services/renovation_calculation_service.dart';
import '../../core/models/investment_modules.dart';
import '../../core/models/settings.dart';
import '../../core/models/valuation.dart';
import '../../core/security/password_hasher.dart';
import '../../core/security/rbac.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/backup_restore_service.dart';
import '../../core/services/ledger_service.dart';
import '../../core/services/zip_service.dart';
import '../../core/services/task_generation_service.dart';
import '../../data/repositories/audit_log_repo.dart';
import '../../data/repositories/asset_workbook_repo.dart';
import '../../data/repositories/budget_repo.dart';
import '../../data/repositories/calculation_datasheet_repo.dart';
import '../../data/repositories/contractor_repo.dart';
import '../../data/repositories/capital_events_repo.dart';
import '../../data/repositories/comps_repo.dart';
import '../../data/repositories/compare_repo.dart';
import '../../data/repositories/covenant_repo.dart';
import '../../data/repositories/criteria_repo.dart';
import '../../data/repositories/data_quality_repo.dart';
import '../../data/repositories/document_types_repo.dart';
import '../../data/repositories/documents_repo.dart';
import '../../data/repositories/esg_repo.dart';
import '../../data/repositories/imports_repo.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/lease_repo.dart';
import '../../data/repositories/ledger_repo.dart';
import '../../data/repositories/maintenance_repo.dart';
import '../../data/repositories/notes_repo.dart';
import '../../data/repositories/notifications_repo.dart';
import '../../data/repositories/operations_repo.dart';
import '../../data/repositories/permission_guard.dart';
import '../../data/repositories/portfolio_analytics_repo.dart';
import '../../data/repositories/portfolio_repo.dart';
import '../../data/repositories/property_modules_repo.dart';
import '../../data/repositories/property_repo.dart';
import '../../data/repositories/property_profile_repo.dart';
import '../../data/repositories/rent_roll_repo.dart';
import '../../data/repositories/required_documents_repo.dart';
import '../../data/repositories/reports_repo.dart';
import '../../data/repositories/scenario_repo.dart';
import '../../data/repositories/scenario_version_repo.dart';
import '../../data/repositories/scenario_valuation_repo.dart';
import '../../data/repositories/search_repo.dart';
import '../../data/repositories/security_repo.dart';
import '../../data/repositories/tasks_repo.dart';
import '../../data/repositories/valuation_data_repo.dart';
import '../../data/repositories/workspace_repo.dart';
import '../../data/sqlite/db.dart';
import '../../data/sqlite/migrations.dart';

enum GlobalPage {
  dashboard,
  properties,
  ledger,
  budgets,
  maintenance,
  contractors,
  tasks,
  taskTemplates,
  portfolios,
  imports,
  notifications,
  esg,
  documents,
  audit,
  compare,
  quickScreening,
  renovationValue,
  dispositionExit,
  criteriaSets,
  reportTemplates,
  adminUsers,
  settings,
  help,
}

enum PropertyDetailPage {
  overview,
  inputs,
  analysis,
  comps,
  criteria,
  offer,
  scenarios,
  versions,
  audit,
  documents,
  reports,
  operationsOverview,
  tasks,
  units,
  tenants,
  leases,
  rentRoll,
  assetWorkbook,
  alerts,
  budgetVsActual,
  maintenance,
  covenants,
  saleData,
  buyerInterests,
  viewings,
  saleOffers,
  reservations,
  guests,
  housekeeping,
  hotelRevenue,
  parkingStorage,
  unitSaleStatus,
}

final databaseProvider = Provider<Database>(
  (ref) =>
      throw UnimplementedError(
        'databaseProvider must be overridden in main.dart',
      ),
);
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) =>
      throw UnimplementedError(
        'appDatabaseProvider must be overridden in main.dart',
      ),
);

final globalPageProvider = StateProvider<GlobalPage>(
  (ref) => GlobalPage.dashboard,
);
final settingsRevisionProvider = StateProvider<int>((ref) => 0);
final appSettingsProvider = FutureProvider<AppSettingsRecord>((ref) async {
  ref.watch(settingsRevisionProvider);
  return ref.watch(inputsRepositoryProvider).getSettings();
});
final selectedPropertyIdProvider = StateProvider<String?>((ref) => null);
final selectedScenarioIdProvider = StateProvider<String?>((ref) => null);
final selectedOperationsUnitIdProvider = StateProvider<String?>((ref) => null);
final selectedOperationsTenantIdProvider = StateProvider<String?>(
  (ref) => null,
);
final selectedOperationsLeaseIdProvider = StateProvider<String?>((ref) => null);
final selectedAssetWorkbookTabProvider = StateProvider<int>((ref) => 0);
final tasksRequestedDueFilterProvider = StateProvider<String?>((ref) => null);
final documentsRequestedTabProvider = StateProvider<int?>((ref) => null);
final propertyDetailPageProvider = StateProvider<PropertyDetailPage>(
  (ref) => PropertyDetailPage.overview,
);

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  return PropertyRepository(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
    permissionGuard: ref.watch(permissionGuardProvider),
    securityContextResolver:
        () => ref.read(securityRepositoryProvider).getActiveContext(),
  );
});

final scenarioRepositoryProvider = Provider<ScenarioRepository>((ref) {
  return ScenarioRepository(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
    permissionGuard: ref.watch(permissionGuardProvider),
    securityContextResolver:
        () => ref.read(securityRepositoryProvider).getActiveContext(),
  );
});

final valuationDataRepositoryProvider = Provider<ValuationDataRepo>((ref) {
  return ValuationDataRepo(ref.watch(databaseProvider));
});

final calculationDatasheetRepositoryProvider =
    Provider<CalculationDatasheetRepo>((ref) {
  return CalculationDatasheetRepo(ref.watch(databaseProvider));
});

final formulaAuditServiceProvider = Provider<FormulaAuditService>((ref) {
  return const FormulaAuditService();
});

final acquisitionCalculationServiceProvider =
    Provider<AcquisitionCalculationService>((ref) {
  return AcquisitionCalculationService(
    formulaAuditService: ref.watch(formulaAuditServiceProvider),
  );
});

final renovationCalculationServiceProvider =
    Provider<RenovationCalculationService>((ref) {
  return RenovationCalculationService(
    formulaAuditService: ref.watch(formulaAuditServiceProvider),
  );
});

final dispositionCalculationServiceProvider =
    Provider<DispositionCalculationService>((ref) {
  return DispositionCalculationService(
    formulaAuditService: ref.watch(formulaAuditServiceProvider),
  );
});

final datasheetBuilderServiceProvider = Provider<DatasheetBuilderService>((ref) {
  return const DatasheetBuilderService();
});

final datasheetExportServiceProvider = Provider<DatasheetExportService>((ref) {
  return const DatasheetExportService();
});

final renovationImpactTransferProvider =
    StateProvider<RenovationImpactTransfer?>((ref) => null);

final valuationPropertySnapshotProvider =
    FutureProvider.family<ValuationPropertySnapshot?, String>((ref, scenarioId) {
      return ref
          .watch(valuationDataRepositoryProvider)
          .getPropertySnapshot(scenarioId);
    });

final inputsRepositoryProvider = Provider<InputsRepository>((ref) {
  return InputsRepository(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
  );
});

final compsRepositoryProvider = Provider<CompsRepository>((ref) {
  return CompsRepository(ref.watch(databaseProvider));
});

final criteriaRepositoryProvider = Provider<CriteriaRepository>((ref) {
  return CriteriaRepository(ref.watch(databaseProvider));
});

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(databaseProvider));
});
final portfolioRepositoryProvider = Provider<PortfolioRepository>((ref) {
  return PortfolioRepository(
    ref.watch(databaseProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(
    ref.watch(databaseProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});
final contractorRepositoryProvider = Provider<ContractorRepository>((ref) {
  return ContractorRepository(ref.watch(databaseProvider));
});
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(
    ref.watch(databaseProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});
final esgRepositoryProvider = Provider<EsgRepository>((ref) {
  return EsgRepository(ref.watch(databaseProvider));
});
final importsRepositoryProvider = Provider<ImportsRepository>((ref) {
  return ImportsRepository(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
  );
});
final ledgerServiceProvider = Provider<LedgerService>(
  (ref) => const LedgerService(),
);
final rentRollEngineProvider = Provider<RentRollEngine>(
  (ref) => const RentRollEngine(),
);
final leaseIndexationEngineProvider = Provider<LeaseIndexationEngine>(
  (ref) => const LeaseIndexationEngine(),
);
final budgetVsActualEngineProvider = Provider<BudgetVsActual>(
  (ref) => const BudgetVsActual(),
);
final covenantEngineProvider = Provider<CovenantEngine>(
  (ref) => const CovenantEngine(),
);
final ledgerRepositoryProvider = Provider<LedgerRepo>((ref) {
  return LedgerRepo(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});
final rentRollRepositoryProvider = Provider<RentRollRepo>((ref) {
  return RentRollRepo(
    ref.watch(databaseProvider),
    ref.watch(rentRollEngineProvider),
  );
});
final operationsRepositoryProvider = Provider<OperationsRepo>((ref) {
  return OperationsRepo(ref.watch(databaseProvider));
});
final leaseRepositoryProvider = Provider<LeaseRepo>((ref) {
  return LeaseRepo(
    ref.watch(databaseProvider),
    ref.watch(leaseIndexationEngineProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
  );
});
final budgetRepositoryProvider = Provider<BudgetRepo>((ref) {
  return BudgetRepo(
    ref.watch(databaseProvider),
    ref.watch(budgetVsActualEngineProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
  );
});
final assetWorkbookRepositoryProvider = Provider<AssetWorkbookRepo>((ref) {
  return AssetWorkbookRepo(ref.watch(databaseProvider));
});
final maintenanceRepositoryProvider = Provider<MaintenanceRepo>((ref) {
  return MaintenanceRepo(ref.watch(databaseProvider));
});
final covenantRepositoryProvider = Provider<CovenantRepo>((ref) {
  return CovenantRepo(
    ref.watch(databaseProvider),
    ref.watch(covenantEngineProvider),
  );
});
final searchRepositoryProvider = Provider<SearchRepo>((ref) {
  return SearchRepo(ref.watch(databaseProvider));
});
final compareRepositoryProvider = Provider<CompareRepo>((ref) {
  return CompareRepo(
    ref.watch(databaseProvider),
    ref.watch(inputsRepositoryProvider),
    ref.watch(analysisEngineProvider),
  );
});
final tasksRepositoryProvider = Provider<TasksRepo>((ref) {
  return TasksRepo(
    ref.watch(databaseProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
  );
});
final taskGenerationServiceProvider = Provider<TaskGenerationService>((ref) {
  return TaskGenerationService(
    ref.watch(databaseProvider),
    ref.watch(tasksRepositoryProvider),
  );
});
final backupServiceProvider = Provider<BackupService>(
  (ref) => const BackupService(),
);
final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepository(ref.watch(appDatabaseProvider));
});
final backupRestoreServiceProvider = Provider<BackupRestoreService>((ref) {
  return BackupRestoreService(
    backupService: ref.watch(backupServiceProvider),
    workspaceRepository: ref.watch(workspaceRepositoryProvider),
    inputsRepository: ref.watch(inputsRepositoryProvider),
    searchRepository: ref.watch(searchRepositoryProvider),
    database: ref.watch(databaseProvider),
    dbSchemaVersion: DbMigrations.currentVersion,
    appVersion: '1.0.0+1',
  );
});
final propertyProfileRepositoryProvider = Provider<PropertyProfileRepository>((
  ref,
) {
  return PropertyProfileRepository(ref.watch(databaseProvider));
});
final propertyModulesRepositoryProvider = Provider<PropertyModulesRepo>((ref) {
  return PropertyModulesRepo(ref.watch(databaseProvider));
});
final propertyHasHotelModulesProvider =
    FutureProvider.family<bool, String>((ref, propertyId) {
      return ref
          .watch(propertyModulesRepositoryProvider)
          .hasHotelModules(propertyId);
    });

final analysisEngineProvider = Provider<AnalysisEngine>(
  (ref) => const AnalysisEngine(),
);
final sensitivityEngineProvider = Provider<SensitivityEngine>(
  (ref) => const SensitivityEngine(),
);
final criteriaEngineProvider = Provider<CriteriaEngine>(
  (ref) => const CriteriaEngine(),
);
final offerSolverProvider = Provider<OfferSolver>((ref) => const OfferSolver());
final rbacProvider = Provider<Rbac>((ref) => const Rbac());
final permissionGuardProvider = Provider<PermissionGuard>((ref) {
  return PermissionGuard(ref.watch(rbacProvider));
});
final passwordHasherProvider = Provider<PasswordHasher>(
  (ref) => const PasswordHasher(),
);
final docComplianceEngineProvider = Provider<DocComplianceEngine>(
  (ref) => const DocComplianceEngine(),
);
final reportBuilderProvider = Provider<ReportBuilder>(
  (ref) => const ReportBuilder(),
);
final csvExporterProvider = Provider<CsvExporter>((ref) => const CsvExporter());
final reportTemplateFactoryProvider = Provider<ReportTemplateFactory>(
  (ref) => const ReportTemplateFactory(),
);
final notificationRulesProvider = Provider<NotificationRules>(
  (ref) => const NotificationRules(),
);
final dataQualityServiceProvider = Provider<DataQualityService>(
  (ref) => const DataQualityService(),
);
final portfolioPackBuilderProvider = Provider<PortfolioPackBuilder>(
  (ref) => const PortfolioPackBuilder(),
);
final zipServiceProvider = Provider<ZipService>((ref) => const ZipService());
final scenarioValuationRepositoryProvider = Provider<ScenarioValuationRepo>((
  ref,
) {
  return ScenarioValuationRepo(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
  );
});
final scenarioVersionRepositoryProvider = Provider<ScenarioVersionRepo>((ref) {
  return ScenarioVersionRepo(ref.watch(databaseProvider));
});
final auditLogRepositoryProvider = Provider<AuditLogRepo>((ref) {
  return AuditLogRepo(ref.watch(databaseProvider));
});
final auditWriterProvider = Provider<AuditWriter>((ref) {
  return AuditWriter(
    ref.watch(auditLogRepositoryProvider),
    () => ref.read(securityRepositoryProvider).getActiveContext(),
  );
});
final documentTypesRepositoryProvider = Provider<DocumentTypesRepo>((ref) {
  return DocumentTypesRepo(ref.watch(databaseProvider));
});
final requiredDocumentsRepositoryProvider = Provider<RequiredDocumentsRepo>((
  ref,
) {
  return RequiredDocumentsRepo(ref.watch(databaseProvider));
});
final documentsRepositoryProvider = Provider<DocumentsRepo>((ref) {
  return DocumentsRepo(
    ref.watch(databaseProvider),
    ref.watch(requiredDocumentsRepositoryProvider),
    ref.watch(docComplianceEngineProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
    auditWriter: ref.watch(auditWriterProvider),
    searchRepo: ref.watch(searchRepositoryProvider),
  );
});
final securityRepositoryProvider = Provider<SecurityRepo>((ref) {
  return SecurityRepo(
    ref.watch(databaseProvider),
    auditLogRepo: ref.watch(auditLogRepositoryProvider),
  );
});
final capitalEventsRepositoryProvider = Provider<CapitalEventsRepo>((ref) {
  return CapitalEventsRepo(
    ref.watch(databaseProvider),
    ref.watch(ledgerServiceProvider),
  );
});
final portfolioIrrEngineProvider = Provider<PortfolioIrrEngine>(
  (ref) => const PortfolioIrrEngine(),
);
final portfolioAnalyticsRepositoryProvider = Provider<PortfolioAnalyticsRepo>((
  ref,
) {
  return PortfolioAnalyticsRepo(
    ref.watch(databaseProvider),
    ref.watch(capitalEventsRepositoryProvider),
    ref.watch(portfolioIrrEngineProvider),
    ref.watch(assetWorkbookRepositoryProvider),
  );
});
final dataQualityRepositoryProvider = Provider<DataQualityRepo>((ref) {
  return DataQualityRepo(ref.watch(databaseProvider));
});

final propertyTitleImageProvider = FutureProvider.family<String?, String>((ref, propertyId) async {
  final repo = ref.read(documentsRepositoryProvider);
  final docs = await repo.listWorkflowDocuments(entityType: 'property', entityId: propertyId);
  for (final doc in docs) {
    if (doc.metadata['image_role'] == 'title') {
      return doc.document.filePath;
    }
  }
  return null;
});
