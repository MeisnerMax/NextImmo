import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property.dart';
import '../../../core/models/scenario.dart';
import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/scenario_state.dart';
import '../../templates/detail_template.dart';
import '../../theme/app_theme.dart';
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

final _autoScenarioCreationInFlightProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

class PropertyShell extends ConsumerStatefulWidget {
  const PropertyShell({super.key});

  static const Color _assetCanvas = Color(0xFFF8FAFC);
  static const Color _assetSidebar = Color(0xFF0F172A);
  static const Color _assetPanel = Color(0xFFFFFFFF);
  static const Color _assetPanelHigh = Color(0xFFF1F5F9);
  static const Color _assetBorder = Color(0xFFE2E8F0);
  static const Color _assetText = Color(0xFF0F172A);
  static const Color _assetMuted = Color(0xFF64748B);
  static const Color _assetAccent = Color(0xFF2563EB);
  static const Color _assetMenuText = Color(0xFFEAF2FF);
  static const Color _assetMenuMuted = Color(0xFFBFD0EA);
  static const Color _assetMenuSelected = Color(0xFF1E293B);

  @override
  ConsumerState<PropertyShell> createState() => _PropertyShellState();
}

class _PropertyShellState extends ConsumerState<PropertyShell> {
  final Map<String, bool> _expanded = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final propertyId = ref.watch(selectedPropertyIdProvider);
    if (propertyId == null) {
      return const SizedBox.shrink();
    }

    final selectedPage = ref.watch(propertyDetailPageProvider);
    final selectedScenarioId = ref.watch(selectedScenarioIdProvider);
    final scenariosAsync = ref.watch(scenariosByPropertyProvider(propertyId));
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final hasHotelModules = ref
        .watch(propertyHasHotelModulesProvider(propertyId))
        .valueOrNull ?? false;
    final currentProperty = propertiesAsync.maybeWhen(
      data: (items) {
        for (final property in items) {
          if (property.id == propertyId) {
            return property;
          }
        }
        return null;
      },
      orElse: () => null,
    );
    final propertyName =
        currentProperty?.name ??
        propertiesAsync.maybeWhen(
          data: (items) {
            for (final property in items) {
              if (property.id == propertyId) {
                return property.name;
              }
            }
            return propertyId;
          },
          orElse: () => propertyId,
        ) ??
        propertyId;
    final effectivePage = _resolveVisiblePage(selectedPage, currentProperty);
    if (effectivePage != selectedPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(propertyDetailPageProvider.notifier).state = effectivePage;
      });
    }
    final section = propertySectionForPage(effectivePage);
    final destination = propertyDestinationForPage(effectivePage);

    // Auto-expand active section
    _expanded[section.title] = true;

    return scenariosAsync.when(
      data: (scenarios) {
        if (scenarios.isEmpty) {
          _ensureBaseScenario(propertyId: propertyId);
        }
        final activeScenarioId = _resolveScenarioSelection(
          scenarios: scenarios,
          selectedScenarioId: selectedScenarioId,
        );
        final detailContent = _buildDetailContent(
          context: context,
          page: effectivePage,
          propertyId: propertyId,
          scenarioId: activeScenarioId,
          scenarios: scenarios,
        );

        return Theme(
          data: _propertyWorkspaceTheme(context),
          child: Container(
            color: PropertyShell._assetCanvas,
            child: DetailTemplate(
              title: propertyName,
              breadcrumbs: propertyBreadcrumbs(
                propertyName: propertyName,
                page: effectivePage,
              ).map(s.text).toList(growable: false),
              subtitle: '${s.text(section.title)} / ${s.text(destination.label)}',
              contextBar: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _scenarioSelector(
                  context: context,
                  scenarios: scenarios,
                  selectedScenarioId: activeScenarioId,
                ),
              ),
              plainHeader: true,
              fullPageScroll: _usesFullPageScroll(effectivePage),
              pagePadding: AppSpacing.xl,
              topNavigation: true,
              navigation: _propertyNavigation(
                context: context,
                selectedPage: effectivePage,
                property: currentProperty,
                hasHotelModules: hasHotelModules,
              ),
              content: detailContent,
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) =>
              Center(child: Text(s.errorWithPrefix(s.text('Error'), error))),
    );
  }

  ThemeData _propertyWorkspaceTheme(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: PropertyShell._assetAccent,
      secondary: const Color(0xFF0F172A),
      surface: PropertyShell._assetPanel,
      surfaceContainerHighest: PropertyShell._assetPanelHigh,
      onSurface: PropertyShell._assetText,
      onPrimary: Colors.white,
      outline: PropertyShell._assetBorder,
      error: const Color(0xFFDC2626),
    );
    final densityConfig = base.extension<AppDensityConfig>();
    final extensions = <ThemeExtension<dynamic>>[
      if (densityConfig != null) densityConfig,
      const AppSemanticColors(
        success: Color(0xFF16A34A),
        warning: Color(0xFFD97706),
        error: Color(0xFFDC2626),
        info: PropertyShell._assetAccent,
        border: PropertyShell._assetBorder,
        surfaceAlt: PropertyShell._assetPanelHigh,
        textSecondary: PropertyShell._assetMuted,
      ),
    ];
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: PropertyShell._assetCanvas,
      dividerColor: PropertyShell._assetBorder,
      textTheme: base.textTheme.apply(
        bodyColor: PropertyShell._assetText,
        displayColor: PropertyShell._assetText,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: PropertyShell._assetPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: const BorderSide(color: PropertyShell._assetBorder),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: PropertyShell._assetMuted),
        helperStyle: const TextStyle(color: PropertyShell._assetMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          borderSide: const BorderSide(color: PropertyShell._assetAccent),
        ),
      ),
      dataTableTheme: base.dataTableTheme.copyWith(
        headingTextStyle: const TextStyle(
          color: PropertyShell._assetMuted,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: const TextStyle(
          color: PropertyShell._assetText,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: PropertyShell._assetPanelHigh,
        side: const BorderSide(color: PropertyShell._assetBorder),
        labelStyle: const TextStyle(
          color: PropertyShell._assetText,
          fontWeight: FontWeight.w600,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PropertyShell._assetText,
          side: const BorderSide(color: PropertyShell._assetBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          ),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        textStyle: TextStyle(color: PropertyShell._assetText),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: PropertyShell._assetMuted),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: PropertyShell._assetText,
        iconColor: PropertyShell._assetMuted,
        selectedColor: PropertyShell._assetAccent,
        selectedTileColor: PropertyShell._assetPanelHigh,
      ),
      extensions: extensions,
    );
  }

  bool _usesFullPageScroll(PropertyDetailPage page) {
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

  String? _resolveScenarioSelection({
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    if (scenarios.isEmpty) {
      if (selectedScenarioId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(selectedScenarioIdProvider.notifier).state = null;
        });
      }
      return null;
    }
    for (final scenario in scenarios) {
      if (scenario.id == selectedScenarioId) {
        return selectedScenarioId;
      }
    }
    final nextScenarioId = scenarios.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedScenarioIdProvider.notifier).state = nextScenarioId;
    });
    return nextScenarioId;
  }

  void _ensureBaseScenario({
    required String propertyId,
  }) {
    final inFlight = ref.read(_autoScenarioCreationInFlightProvider);
    if (inFlight.contains(propertyId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final current = ref.read(_autoScenarioCreationInFlightProvider);
      if (current.contains(propertyId)) {
        return;
      }
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          <String>{...current, propertyId};
      final scenario = await ref
          .read(scenariosByPropertyProvider(propertyId).notifier)
          .create(name: 'Basis Vermietung', strategyType: 'rental');
      if (scenario != null) {
        ref.read(selectedScenarioIdProvider.notifier).state = scenario.id;
      }
      final after = ref.read(_autoScenarioCreationInFlightProvider);
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          after.where((id) => id != propertyId).toSet();
    });
  }

  Widget _propertyNavigation({
    required BuildContext context,
    required PropertyDetailPage selectedPage,
    required PropertyRecord? property,
    required bool hasHotelModules,
  }) {
    final zone = context.desktopLayoutZone;
    final sections = _visibleNavigationSections(
      property,
      hasHotelModules: hasHotelModules,
    );
    if (zone == AppDesktopLayoutZone.narrow) {
      return _buildNarrowNavigation(
        context: context,
        selectedPage: selectedPage,
        sections: sections,
        property: property,
      );
    }
    return _buildTopNavigation(
      context: context,
      selectedPage: selectedPage,
      sections: sections,
      property: property,
    );
  }

  Widget _buildTopNavigation({
    required BuildContext context,
    required PropertyDetailPage selectedPage,
    required List<PropertyNavigationSection> sections,
    required PropertyRecord? property,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PropertyShell._assetSidebar,
        border: Border.all(color: PropertyShell._assetBorder),
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
                _buildTopNavigationSection(
                  context: context,
                  section: section,
                  selectedPage: selectedPage,
                  property: property,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavigationSection({
    required BuildContext context,
    required PropertyNavigationSection section,
    required PropertyDetailPage selectedPage,
    required PropertyRecord? property,
  }) {
    final selected = section.items.any((item) => item.page == selectedPage);
    final selectedDestination =
        selected ? propertyDestinationForPage(selectedPage) : null;

    return PopupMenuButton<PropertyDetailPage>(
      tooltip: context.strings.text(section.title),
      onSelected: (value) {
        ref.read(propertyDetailPageProvider.notifier).state = value;
      },
      itemBuilder: (context) => [
        for (final item in section.items)
          PopupMenuItem<PropertyDetailPage>(
            value: item.page,
            child: Row(
              children: [
                Icon(_iconForPropertyPage(item.page), size: 18),
                const SizedBox(width: 10),
                Text(context.strings.text(_labelForPage(item.page, property))),
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
          color: selected
              ? PropertyShell._assetMenuSelected
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          border: Border.all(
            color: selected ? Colors.white24 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedDestination == null
                  ? Icons.folder_open_outlined
                  : _iconForPropertyPage(selectedPage),
              size: 18,
              color: selected ? Colors.white : PropertyShell._assetMenuMuted,
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
                    color: PropertyShell._assetMenuMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                if (selectedDestination != null)
                  Text(
                    context.strings.text(_labelForPage(selectedPage, property)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 18,
              color: selected ? Colors.white : PropertyShell._assetMenuMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowNavigation({
    required BuildContext context,
    required PropertyDetailPage selectedPage,
    required List<PropertyNavigationSection> sections,
    required PropertyRecord? property,
  }) {
    final selectedSection = propertySectionForPage(selectedPage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PropertyShell._assetSidebar,
        border: Border.all(color: PropertyShell._assetBorder),
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
                color: PropertyShell._assetMenuText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.strings.text(selectedSection.title)} / ${context.strings.text(_labelForPage(selectedPage, property))}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PropertyShell._assetMenuMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<PropertyDetailPage>(
              value:
                  _menuContainsPage(sections, selectedPage)
                      ? selectedPage
                      : null,
              isExpanded: true,
              items: sections
                  .expand(
                    (section) => section.items.map(
                      (item) => DropdownMenuItem<PropertyDetailPage>(
                        value: item.page,
                        child: Text(
                          '${context.strings.text(section.title)} / ${context.strings.text(_labelForPage(item.page, property))}',
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  ref.read(propertyDetailPageProvider.notifier).state = value;
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

  List<PropertyNavigationSection> _visibleNavigationSections(
    PropertyRecord? property, {
    required bool hasHotelModules,
  }) {
    if (property == null) {
      return propertyNavigationSections;
    }
    final allowedPages = _allowedPagesForPropertyType(
      property.propertyType,
      hasHotelModules: hasHotelModules,
    );
    return _sectionsForPages(allowedPages);
  }

  PropertyDetailPage _resolveVisiblePage(
    PropertyDetailPage selectedPage,
    PropertyRecord? property,
  ) {
    if (property == null) {
      return selectedPage;
    }
    final hasHotelModules = ref
            .read(propertyHasHotelModulesProvider(property.id))
            .valueOrNull ??
        false;
    final allowedPages = _allowedPagesForPropertyType(
      property.propertyType,
      hasHotelModules: hasHotelModules,
    );
    if (allowedPages.contains(selectedPage)) {
      return selectedPage;
    }
    return PropertyDetailPage.overview;
  }

  Set<PropertyDetailPage> _allowedPagesForPropertyType(
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

  String _labelForPage(PropertyDetailPage page, PropertyRecord? property) {
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

  List<PropertyNavigationSection> _sectionsForPages(
    Set<PropertyDetailPage> allowedPages,
  ) {
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

  bool _menuContainsPage(
    List<PropertyNavigationSection> sections,
    PropertyDetailPage page,
  ) {
    return sections.any(
      (section) => section.items.any((item) => item.page == page),
    );
  }

  Widget _buildAccordionSection({
    required BuildContext context,
    required PropertyNavigationSection section,
    required PropertyDetailPage selectedPage,
  }) {
    final title = section.title;
    final expanded = _expanded[title] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expanded[title] = !expanded;
            });
          },
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.strings.text(title).toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: PropertyShell._assetMenuMuted,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: PropertyShell._assetMenuMuted,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              const SizedBox(height: 4),
              for (final item in section.items)
                _buildNavTile(
                  context: context,
                  item: item,
                  selectedPage: selectedPage,
                ),
              const SizedBox(height: 8),
            ],
          ),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 140),
        ),
      ],
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required PropertyNavigationDestination item,
    required PropertyDetailPage selectedPage,
  }) {
    final selected = item.page == selectedPage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: selected ? PropertyShell._assetMenuSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                _iconForPropertyPage(item.page),
                size: 20,
                color: selected ? Colors.white : PropertyShell._assetMenuMuted,
              ),
              title: Text(
                context.strings.text(_labelForPage(item.page, null)),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : PropertyShell._assetMenuMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                ref.read(propertyDetailPageProvider.notifier).state = item.page;
              },
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              width: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForPropertyPage(PropertyDetailPage page) {
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

  Widget _scenarioSelector({
    required BuildContext context,
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    final zone = context.desktopLayoutZone;
    final selected =
        scenarios.any((scenario) => scenario.id == selectedScenarioId)
            ? selectedScenarioId
            : (scenarios.isNotEmpty ? scenarios.first.id : null);
    if (selected == null) {
      return Text(context.strings.text('Basisszenario wird erstellt...'));
    }
    if (scenarios.length <= 3 && zone != AppDesktopLayoutZone.narrow) {
      return SegmentedButton<String>(
        segments: scenarios
            .map(
              (scenario) => ButtonSegment<String>(
                value: scenario.id,
                label: Text(scenario.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        selected: <String>{selected},
        onSelectionChanged: (selection) {
          final next = selection.isEmpty ? null : selection.first;
          final previousScenarioId = selectedScenarioId;
          if (previousScenarioId != null) {
            ref
                .read(
                  scenarioAnalysisControllerProvider(
                    previousScenarioId,
                  ).notifier,
                )
                .flushPendingSave();
          }
          ref.read(selectedScenarioIdProvider.notifier).state = next;
        },
      );
    }
    return DropdownButtonFormField<String>(
      value: selected,
      items: scenarios
          .map(
            (scenario) => DropdownMenuItem<String>(
              value: scenario.id,
              child: Text(scenario.name),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        final previousScenarioId = selectedScenarioId;
        if (previousScenarioId != null) {
          ref
              .read(
                scenarioAnalysisControllerProvider(previousScenarioId).notifier,
              )
              .flushPendingSave();
        }
        ref.read(selectedScenarioIdProvider.notifier).state = value;
      },
      decoration: InputDecoration(labelText: context.strings.text('Scenario')),
    );
  }

  Widget _buildDetailContent({
    required BuildContext context,
    required PropertyDetailPage page,
    required String propertyId,
    required String? scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    if (propertyPageRequiresScenario(page) && scenarioId == null) {
      return Center(
        child: Text(
          context.strings.text('Basisszenario wird erstellt...'),
        ),
      );
    }
    return _buildDetailPage(
      page: page,
      propertyId: propertyId,
      scenarioId: scenarioId,
      scenarios: scenarios,
    );
  }

  Widget _buildDetailPage({
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
}

