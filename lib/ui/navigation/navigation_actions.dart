import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search.dart';
import '../state/app_state.dart';

void openGlobalPage(
  WidgetRef ref,
  GlobalPage page, {
  bool resetPropertyContext = true,
}) {
  if (resetPropertyContext) {
    ref.read(selectedPropertyIdProvider.notifier).state = null;
    ref.read(selectedScenarioIdProvider.notifier).state = null;
    ref.read(selectedOperationsUnitIdProvider.notifier).state = null;
    ref.read(selectedOperationsTenantIdProvider.notifier).state = null;
    ref.read(selectedOperationsLeaseIdProvider.notifier).state = null;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.overview;
  }
  ref.read(globalPageProvider.notifier).state = page;
}

void openSearchResult(WidgetRef ref, SearchIndexRecord item) {
  switch (item.entityType) {
    case 'property':
      ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
      ref.read(selectedPropertyIdProvider.notifier).state = item.entityId;
      ref.read(selectedScenarioIdProvider.notifier).state = null;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.overview;
      break;
    case 'scenario':
      final propertyId = _extractToken(item.body, 'property_id');
      ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
      ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
      ref.read(selectedScenarioIdProvider.notifier).state = item.entityId;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.overview;
      break;
    case 'document':
      final propertyId = _extractToken(item.body, 'property_id');
      final nestedEntityType = _extractToken(item.body, 'entity_type');
      final nestedEntityId = _extractToken(item.body, 'entity_id');
      if (propertyId == null || propertyId.trim().isEmpty) {
        openGlobalPage(ref, GlobalPage.documents);
        break;
      }
      ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
      ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
      ref.read(selectedScenarioIdProvider.notifier).state = null;
      switch (nestedEntityType) {
        case 'unit':
          ref.read(selectedOperationsUnitIdProvider.notifier).state =
              nestedEntityId;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.units;
          break;
        case 'tenant':
          ref.read(selectedOperationsTenantIdProvider.notifier).state =
              nestedEntityId;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.tenants;
          break;
        case 'lease':
          ref.read(selectedOperationsLeaseIdProvider.notifier).state =
              nestedEntityId;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.leases;
          break;
        default:
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.documents;
          break;
      }
      break;
    case 'portfolio':
      openGlobalPage(ref, GlobalPage.portfolios);
      break;
    case 'notification':
      openGlobalPage(ref, GlobalPage.notifications);
      break;
    case 'ledger_entry':
      openGlobalPage(ref, GlobalPage.ledger);
      break;
    case 'task':
      openGlobalPage(ref, GlobalPage.tasks);
      break;
    default:
      openGlobalPage(ref, GlobalPage.dashboard);
      break;
  }
}

void executeCommandPaletteAction(WidgetRef ref, String actionId) {
  switch (actionId) {
    case 'new_property':
      openGlobalPage(ref, GlobalPage.properties);
      break;
    case 'open_overdue_tasks':
      ref.read(tasksRequestedDueFilterProvider.notifier).state = 'overdue';
      openGlobalPage(ref, GlobalPage.tasks);
      break;
    case 'jump_missing_documents':
      ref.read(documentsRequestedTabProvider.notifier).state = 3;
      openGlobalPage(ref, GlobalPage.documents);
      break;
    case 'create_report_pack':
      openGlobalPage(ref, GlobalPage.portfolios);
      break;
    case 'open_dashboard':
      openGlobalPage(ref, GlobalPage.dashboard);
      break;
  }
}

String? _extractToken(String? body, String key) {
  if (body == null || body.trim().isEmpty) {
    return null;
  }
  for (final segment in body.split('|')) {
    final parts = segment.split(':');
    if (parts.length < 2) {
      continue;
    }
    if (parts.first == key) {
      return parts.sublist(1).join(':');
    }
  }
  return null;
}
