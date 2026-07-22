import 'package:flutter/material.dart';

import '../../../core/models/scenario.dart';
import '../../state/app_state.dart';
import 'analysis_screen.dart';
import 'asset_workbook_screen.dart';
import 'budget_vs_actual_screen.dart';
import 'comps_screen.dart';
import 'covenants_screen.dart';
import 'criteria_check_screen.dart';
import 'inputs_screen.dart';
import 'leases_screen.dart';
import 'maintenance_screen.dart';
import 'operations_alerts_screen.dart';
import 'operations_overview_screen.dart';
import 'offer_screen.dart';
import 'overview_screen.dart';
import 'property_documents_screen.dart';
import 'property_tasks_screen.dart';
import 'property_type_module_screen.dart';
import 'rent_roll_screen.dart';
import 'scenario_versions_screen.dart';
import 'scenarios_screen.dart';
import 'tenants_screen.dart';
import 'units_screen.dart';

/// Enum→screen routing of the property detail shell (BIG-024 split).
/// Pages that call `scenarioId!` are exactly those with
/// `propertyPageRequiresScenario(page) == true` — the shell guards that
/// before routing.
bool propertyPageUsesFullPageScroll(PropertyDetailPage page) {
  switch (page) {
    case PropertyDetailPage.overview:
      return true;
    case PropertyDetailPage.documents:
    case PropertyDetailPage.audit:
    case PropertyDetailPage.reports:
    case PropertyDetailPage.saleData:
    case PropertyDetailPage.buyerInterests:
    case PropertyDetailPage.viewings:
    case PropertyDetailPage.saleOffers:
    case PropertyDetailPage.reservations:
    case PropertyDetailPage.guests:
    case PropertyDetailPage.housekeeping:
    case PropertyDetailPage.hotelRevenue:
    case PropertyDetailPage.parkingStorage:
    case PropertyDetailPage.unitSaleStatus:
      return true;
    case PropertyDetailPage.inputs:
    case PropertyDetailPage.analysis:
    case PropertyDetailPage.comps:
    case PropertyDetailPage.criteria:
    case PropertyDetailPage.offer:
    case PropertyDetailPage.scenarios:
    case PropertyDetailPage.versions:
    case PropertyDetailPage.operationsOverview:
    case PropertyDetailPage.tasks:
    case PropertyDetailPage.units:
    case PropertyDetailPage.tenants:
    case PropertyDetailPage.leases:
    case PropertyDetailPage.rentRoll:
    case PropertyDetailPage.assetWorkbook:
    case PropertyDetailPage.alerts:
    case PropertyDetailPage.budgetVsActual:
    case PropertyDetailPage.maintenance:
    case PropertyDetailPage.covenants:
      return false;
  }
}

Widget buildPropertyDetailPage({
  required PropertyDetailPage page,
  required String propertyId,
  required String? scenarioId,
  required List<ScenarioRecord> scenarios,
}) {
  switch (page) {
    case PropertyDetailPage.overview:
      return OverviewScreen(
        propertyId: propertyId,
        scenarioId: scenarioId!,
        scrollable: false,
      );
    case PropertyDetailPage.inputs:
      return InputsScreen(scenarioId: scenarioId!);
    case PropertyDetailPage.analysis:
      return AnalysisScreen(scenarioId: scenarioId!);
    case PropertyDetailPage.comps:
      return CompsScreen(propertyId: propertyId, scenarioId: scenarioId!);
    case PropertyDetailPage.criteria:
      return CriteriaCheckScreen(scenarioId: scenarioId!);
    case PropertyDetailPage.offer:
      return OfferScreen(scenarioId: scenarioId!);
    case PropertyDetailPage.scenarios:
      return ScenariosScreen(propertyId: propertyId, scenarios: scenarios);
    case PropertyDetailPage.versions:
      return ScenarioVersionsScreen(scenarioId: scenarioId!);
    case PropertyDetailPage.audit:
      return PropertyDocumentsScreen(
        propertyId: propertyId,
        scenarioId: scenarioId,
        initialIndex: 1,
      );
    case PropertyDetailPage.documents:
      return PropertyDocumentsScreen(
        propertyId: propertyId,
        scenarioId: scenarioId,
        initialIndex: 0,
      );
    case PropertyDetailPage.reports:
      return PropertyDocumentsScreen(
        propertyId: propertyId,
        scenarioId: scenarioId,
        initialIndex: 2,
      );
    case PropertyDetailPage.operationsOverview:
      return OperationsOverviewScreen(propertyId: propertyId);
    case PropertyDetailPage.tasks:
      return PropertyTasksScreen(propertyId: propertyId);
    case PropertyDetailPage.units:
      return UnitsScreen(propertyId: propertyId);
    case PropertyDetailPage.tenants:
      return TenantsScreen(propertyId: propertyId);
    case PropertyDetailPage.leases:
      return LeasesScreen(propertyId: propertyId);
    case PropertyDetailPage.rentRoll:
      return RentRollScreen(propertyId: propertyId);
    case PropertyDetailPage.assetWorkbook:
      return AssetWorkbookScreen(propertyId: propertyId);
    case PropertyDetailPage.alerts:
      return OperationsAlertsScreen(propertyId: propertyId);
    case PropertyDetailPage.budgetVsActual:
      return BudgetVsActualScreen(propertyId: propertyId);
    case PropertyDetailPage.maintenance:
      return PropertyMaintenanceScreen(propertyId: propertyId);
    case PropertyDetailPage.covenants:
      return CovenantsScreen(propertyId: propertyId);
    case PropertyDetailPage.saleData:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.saleData,
      );
    case PropertyDetailPage.buyerInterests:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.buyerInterests,
      );
    case PropertyDetailPage.viewings:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.viewings,
      );
    case PropertyDetailPage.saleOffers:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.saleOffers,
      );
    case PropertyDetailPage.reservations:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.reservations,
      );
    case PropertyDetailPage.guests:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.guests,
      );
    case PropertyDetailPage.housekeeping:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.housekeeping,
      );
    case PropertyDetailPage.hotelRevenue:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.hotelRevenue,
      );
    case PropertyDetailPage.parkingStorage:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.parkingStorage,
      );
    case PropertyDetailPage.unitSaleStatus:
      return PropertyTypeModuleScreen(
        propertyId: propertyId,
        module: PropertyTypeModule.unitSaleStatus,
      );
  }
}
