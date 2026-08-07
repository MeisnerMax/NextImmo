import 'package:flutter/material.dart';

import '../../../core/models/property.dart';
import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Navigation model + widgets of the property detail shell (BIG-024 split).
///
/// Owns which module pages a property type exposes, how sections/labels/icons
/// resolve, and how the grouped navigation renders (horizontal sections on
/// desktop/tablet, dropdown on phone). Routing itself stays in the shell via
/// the [PropertyNavigationBar.onSelect] callback.
Set<PropertyDetailPage> allowedPropertyPagesForType(
  String propertyType, {
  required bool hasHotelModules,
}) {
  final basic = <PropertyDetailPage>{
    PropertyDetailPage.overview,
    PropertyDetailPage.documents,
  };
  final history = <PropertyDetailPage>{
    PropertyDetailPage.audit,
    PropertyDetailPage.reports,
  };
  final operations = <PropertyDetailPage>{
    PropertyDetailPage.tasks,
    PropertyDetailPage.maintenance,
  };
  final valuation = <PropertyDetailPage>{
    PropertyDetailPage.scenarios,
    PropertyDetailPage.inputs,
    PropertyDetailPage.analysis,
    PropertyDetailPage.offer,
    PropertyDetailPage.budgetVsActual,
  };
  switch (propertyKindFromType(propertyType)) {
    case PropertyKind.rental:
      return <PropertyDetailPage>{
        ...basic,
        ...history,
        ...operations,
        ...valuation,
        PropertyDetailPage.operationsOverview,
        PropertyDetailPage.units,
        PropertyDetailPage.tenants,
        PropertyDetailPage.leases,
        PropertyDetailPage.rentRoll,
        PropertyDetailPage.assetWorkbook,
        PropertyDetailPage.alerts,
        PropertyDetailPage.covenants,
      };
    case PropertyKind.sale:
      return <PropertyDetailPage>{
        ...basic,
        PropertyDetailPage.tasks,
        PropertyDetailPage.saleData,
        PropertyDetailPage.buyerInterests,
        PropertyDetailPage.viewings,
        PropertyDetailPage.saleOffers,
      };
    case PropertyKind.condoSale:
      return <PropertyDetailPage>{
        ...basic,
        PropertyDetailPage.units,
        PropertyDetailPage.buyerInterests,
        PropertyDetailPage.reservations,
        PropertyDetailPage.unitSaleStatus,
        PropertyDetailPage.parkingStorage,
      };
    case PropertyKind.hotel:
      return <PropertyDetailPage>{
        ...basic,
        PropertyDetailPage.maintenance,
        PropertyDetailPage.units,
        PropertyDetailPage.reservations,
        PropertyDetailPage.guests,
        PropertyDetailPage.housekeeping,
        PropertyDetailPage.hotelRevenue,
        PropertyDetailPage.operationsOverview,
        PropertyDetailPage.assetWorkbook,
      };
    case PropertyKind.mixed:
      final pages = <PropertyDetailPage>{
        ...basic,
        ...history,
        ...operations,
        ...valuation,
        PropertyDetailPage.operationsOverview,
        PropertyDetailPage.units,
        PropertyDetailPage.tenants,
        PropertyDetailPage.leases,
        PropertyDetailPage.rentRoll,
        PropertyDetailPage.comps,
        PropertyDetailPage.assetWorkbook,
        PropertyDetailPage.alerts,
        PropertyDetailPage.covenants,
        PropertyDetailPage.saleData,
        PropertyDetailPage.buyerInterests,
        PropertyDetailPage.viewings,
        PropertyDetailPage.saleOffers,
      };
      if (hasHotelModules) {
        pages.addAll(<PropertyDetailPage>{
          PropertyDetailPage.reservations,
          PropertyDetailPage.guests,
          PropertyDetailPage.housekeeping,
          PropertyDetailPage.hotelRevenue,
        });
      }
      return pages;
    case PropertyKind.other:
      return <PropertyDetailPage>{
        ...basic,
        PropertyDetailPage.tasks,
      };
  }
}

List<PropertyNavigationSection> visiblePropertyNavigationSections(
  PropertyRecord? property, {
  required bool hasHotelModules,
}) {
  if (property == null) {
    return propertyNavigationSections;
  }
  final allowedPages = allowedPropertyPagesForType(
    property.propertyType,
    hasHotelModules: hasHotelModules,
  );
  return allPropertyNavigationSections
      .map(
        (section) => PropertyNavigationSection(
          title: section.title,
          routeKey: section.routeKey,
          items: section.items
              .where((item) => allowedPages.contains(item.page))
              .toList(growable: false),
        ),
      )
      .where((section) => section.items.isNotEmpty)
      .toList(growable: false);
}

/// Falls back to the overview when the selected page is not available for the
/// property's type/module configuration.
PropertyDetailPage resolveVisiblePropertyPage({
  required PropertyDetailPage selectedPage,
  required PropertyRecord? property,
  required bool hasHotelModules,
}) {
  if (property == null) {
    return selectedPage;
  }
  final allowedPages = allowedPropertyPagesForType(
    property.propertyType,
    hasHotelModules: hasHotelModules,
  );
  if (allowedPages.contains(selectedPage)) {
    return selectedPage;
  }
  return PropertyDetailPage.overview;
}

String propertyPageLabel(PropertyDetailPage page, PropertyRecord? property) {
  final kind = property == null
      ? PropertyKind.rental
      : propertyKindFromType(property.propertyType);
  if (page == PropertyDetailPage.units) {
    return switch (kind) {
      PropertyKind.hotel => 'Zimmer',
      PropertyKind.condoSale => 'Wohnungen',
      _ => 'Einheiten',
    };
  }
  if (page == PropertyDetailPage.reservations &&
      kind == PropertyKind.condoSale) {
    return 'Reservierungen';
  }
  return propertyDestinationForPage(page).label;
}

IconData propertyPageIcon(PropertyDetailPage page) {
  switch (page) {
    case PropertyDetailPage.overview:
      return Icons.dashboard_outlined;
    case PropertyDetailPage.audit:
      return Icons.history_outlined;
    case PropertyDetailPage.operationsOverview:
      return Icons.business_center_outlined;
    case PropertyDetailPage.units:
      return Icons.door_front_door_outlined;
    case PropertyDetailPage.tenants:
      return Icons.people_outline;
    case PropertyDetailPage.leases:
      return Icons.description_outlined;
    case PropertyDetailPage.rentRoll:
      return Icons.apartment_outlined;
    case PropertyDetailPage.assetWorkbook:
      return Icons.request_quote_outlined;
    case PropertyDetailPage.budgetVsActual:
      return Icons.account_balance_outlined;
    case PropertyDetailPage.tasks:
      return Icons.add_task_outlined;
    case PropertyDetailPage.maintenance:
      return Icons.build_outlined;
    case PropertyDetailPage.alerts:
      return Icons.notifications_active_outlined;
    case PropertyDetailPage.scenarios:
      return Icons.route_outlined;
    case PropertyDetailPage.inputs:
      return Icons.account_balance_wallet_outlined;
    case PropertyDetailPage.analysis:
      return Icons.analytics_outlined;
    case PropertyDetailPage.comps:
      return Icons.compare_arrows_outlined;
    case PropertyDetailPage.offer:
      return Icons.local_offer_outlined;
    case PropertyDetailPage.criteria:
      return Icons.rule_outlined;
    case PropertyDetailPage.versions:
      return Icons.timeline_outlined;
    case PropertyDetailPage.covenants:
      return Icons.verified_user_outlined;
    case PropertyDetailPage.documents:
      return Icons.folder_open_outlined;
    case PropertyDetailPage.reports:
      return Icons.summarize_outlined;
    case PropertyDetailPage.saleData:
      return Icons.sell_outlined;
    case PropertyDetailPage.buyerInterests:
      return Icons.person_search_outlined;
    case PropertyDetailPage.viewings:
      return Icons.event_available_outlined;
    case PropertyDetailPage.saleOffers:
      return Icons.local_offer_outlined;
    case PropertyDetailPage.reservations:
      return Icons.event_note_outlined;
    case PropertyDetailPage.guests:
      return Icons.badge_outlined;
    case PropertyDetailPage.housekeeping:
      return Icons.cleaning_services_outlined;
    case PropertyDetailPage.hotelRevenue:
      return Icons.query_stats_outlined;
    case PropertyDetailPage.parkingStorage:
      return Icons.local_parking_outlined;
    case PropertyDetailPage.unitSaleStatus:
      return Icons.price_check_outlined;
  }
}

/// Grouped module navigation of the property shell. Renders horizontal
/// domain sections (desktop/tablet) or a compact dropdown (phone), styled
/// with the shared sidebar navy tokens.
class PropertyNavigationBar extends StatelessWidget {
  const PropertyNavigationBar({
    super.key,
    required this.selectedPage,
    required this.sections,
    required this.property,
    required this.onSelect,
  });

  final PropertyDetailPage selectedPage;
  final List<PropertyNavigationSection> sections;
  final PropertyRecord? property;
  final ValueChanged<PropertyDetailPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final zone = context.desktopLayoutZone;
    if (zone == AppDesktopLayoutZone.narrow) {
      return _buildNarrow(context);
    }
    return _buildTop(context);
  }

  Widget _buildTop(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final section in sections) ...[
                _buildTopSection(context, section),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection(
    BuildContext context,
    PropertyNavigationSection section,
  ) {
    final selected = section.items.any((item) => item.page == selectedPage);
    final selectedDestination =
        selected ? propertyDestinationForPage(selectedPage) : null;

    return PopupMenuButton<PropertyDetailPage>(
      tooltip: context.strings.text(section.title),
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final item in section.items)
          PopupMenuItem<PropertyDetailPage>(
            value: item.page,
            child: Row(
              children: [
                Icon(propertyPageIcon(item.page), size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    context.strings.text(propertyPageLabel(item.page, property)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.component,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.sidebarSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          border: Border.all(
            color: selected
                ? AppColors.sidebarMuted.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedDestination == null
                  ? Icons.folder_open_outlined
                  : propertyPageIcon(selectedPage),
              size: 18,
              color: selected
                  ? AppColors.sidebarTextActive
                  : AppColors.sidebarMuted,
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.strings.text(section.title).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.sidebarMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                if (selectedDestination != null)
                  Text(
                    context.strings.text(
                      propertyPageLabel(selectedPage, property),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.sidebarTextActive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 18,
              color: selected
                  ? AppColors.sidebarTextActive
                  : AppColors.sidebarMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final selectedSection = propertySectionForPage(selectedPage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text('Property Navigation'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.sidebarText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.strings.text(selectedSection.title)} / ${context.strings.text(propertyPageLabel(selectedPage, property))}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.sidebarMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<PropertyDetailPage>(
              value: _sectionsContainPage(selectedPage) ? selectedPage : null,
              isExpanded: true,
              items: sections
                  .expand(
                    (section) => section.items.map(
                      (item) => DropdownMenuItem<PropertyDetailPage>(
                        value: item.page,
                        child: Text(
                          '${context.strings.text(section.title)} / ${context.strings.text(propertyPageLabel(item.page, property))}',
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  onSelect(value);
                }
              },
              decoration: InputDecoration(
                labelText: context.strings.text('Section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sectionsContainPage(PropertyDetailPage page) {
    return sections.any(
      (section) => section.items.any((item) => item.page == page),
    );
  }
}
