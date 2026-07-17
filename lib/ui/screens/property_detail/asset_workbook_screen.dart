import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/models/asset_workbook.dart';
import '../../components/nx_card.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class AssetWorkbookScreen extends ConsumerStatefulWidget {
  const AssetWorkbookScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<AssetWorkbookScreen> createState() =>
      _AssetWorkbookScreenState();
}

class _AssetWorkbookScreenState extends ConsumerState<AssetWorkbookScreen> {
  bool _loading = true;
  String? _error;
  AssetWorkbookBundle? _bundle;
  int _selectedTabIndex = 0;
  String? _selectedSettlementUnitCode;
  String? _exportStatus;
  int _selectedCostsSegment = 0;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = ref.read(selectedAssetWorkbookTabProvider);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final bundle = _bundle;
    if (bundle == null) {
      return const Center(child: Text('Keine Vermietungs- und BK-Daten verfügbar.'));
    }

    return DefaultTabController(
      length: 4,
      initialIndex: _selectedTabIndex.clamp(0, 3).toInt(),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, bundle),
            const SizedBox(height: AppSpacing.component),
            _workflow(context),
            const SizedBox(height: AppSpacing.component),
            _sourceOverview(context, bundle),
            const SizedBox(height: AppSpacing.component),
            TabBar(
              isScrollable: true,
              onTap: (index) {
                ref.read(selectedAssetWorkbookTabProvider.notifier).state =
                    index;
                setState(() => _selectedTabIndex = index);
              },
              tabs: const [
                Tab(text: 'Vermietung'),
                Tab(text: 'Betriebskosten'),
                Tab(text: 'BK-Abrechnung'),
                Tab(text: 'Hotel & Maßnahmen'),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _workbookTabContent(context, bundle),
          ],
        ),
      ),
    );
  }

  Widget _workbookTabContent(
    BuildContext context,
    AssetWorkbookBundle bundle,
  ) {
    switch (_selectedTabIndex) {
      case 1:
        return _costsTab(context, bundle);
      case 2:
        return _settlementTab(context, bundle);
      case 3:
        return _operationsTab(context, bundle);
      default:
        return _rentalTab(context, bundle);
    }
  }

  Widget _header(BuildContext context, AssetWorkbookBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _propertySummaryCard(context, bundle.property),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _metricCard('Jahresmiete', _formatCurrency(bundle.annualRent)),
            _metricCard(
              'Monatslauf',
              _formatCurrency(bundle.monthlyRentRunRate),
            ),
            _metricCard(
              'BK/Kosten p.a.',
              _formatCurrency(bundle.annualOperatingCosts),
            ),
            _metricCard(
              'Offene Kaution',
              _formatCurrency(bundle.openDepositAmount),
            ),
            _metricCard('Aktive Verträge', '${bundle.leaseItems.length}'),
          ],
        ),
      ],
    );
  }

  Widget _propertySummaryCard(
    BuildContext context,
    AssetWorkbookPropertySummary property,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    property.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(property.statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text(property.address),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip('Asset-ID', property.id),
                _infoChip('Typ', property.propertyType),
                _infoChip('Einheiten', '${property.units}'),
                _infoChip(
                  'Fläche',
                  property.area == null
                      ? '-'
                      : '${property.area!.toStringAsFixed(1)} m²',
                ),
                _infoChip(
                  'Baujahr',
                  property.yearBuilt == null ? '-' : '${property.yearBuilt}',
                ),
              ],
            ),
            if (property.notes?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text(property.notes!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Chip(label: Text('$label: $value'));
  }

  Widget _workflow(BuildContext context) {
    final steps = [
      ('1', 'Objekt & Einheiten', Icons.apartment_outlined, PropertyDetailPage.units),
      ('2', 'Mieten & Kautionen', Icons.description_outlined, PropertyDetailPage.leases),
      ('3', 'Mieter', Icons.people_outline, PropertyDetailPage.tenants),
      ('4', 'BK & Budget', Icons.request_quote_outlined, PropertyDetailPage.budgetVsActual),
      ('5', 'Dokumente', Icons.folder_open_outlined, PropertyDetailPage.documents),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final step in steps)
          ActionChip(
            avatar: CircleAvatar(child: Text(step.$1)),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(step.$3, size: 16),
                const SizedBox(width: 6),
                Text(step.$2),
              ],
            ),
            onPressed:
                () => ref.read(propertyDetailPageProvider.notifier).state =
                    step.$4,
          ),
      ],
    );
  }

  Widget _sourceOverview(BuildContext context, AssetWorkbookBundle bundle) {
    final imported = bundle.sourceItems.where((item) => item.complete).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Datenstand',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('$imported/${bundle.sourceItems.length} gefüllt'),
              avatar: const Icon(Icons.checklist_outlined, size: 16),
            ),
            for (final item in bundle.sourceItems)
              _sourceItemChip(context, item),
          ],
        ),
      ),
    );
  }

  Widget _sourceItemChip(
    BuildContext context,
    AssetWorkbookSourceItem item,
  ) {
    final color =
        item.complete
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error;
    return Tooltip(
      message: item.detail,
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(
          item.complete ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: color,
        ),
        label: Text('${item.label} (${item.count})'),
        onPressed: () => _openSourceArea(context, item),
      ),
    );
  }

  void _openSourceArea(BuildContext context, AssetWorkbookSourceItem item) {
    final area = item.sourceSheet;
    if (area == 'Objektdaten') {
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.overview;
      return;
    }
    if (area == 'Dokumente') {
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.documents;
      return;
    }
    final controller = DefaultTabController.of(context);
    void showTab(int index) {
      ref.read(selectedAssetWorkbookTabProvider.notifier).state = index;
      setState(() => _selectedTabIndex = index);
      controller.animateTo(index);
    }
    if (area == 'Einheitenkosten' ||
        area == 'Versicherungen' ||
        area == 'Gebäudekosten') {
      showTab(1);
      return;
    }
    if (area == 'BK-Abrechnung') {
      showTab(2);
      return;
    }
    if (area == 'Hotelbetrieb' || area == 'Maßnahmen') {
      showTab(3);
      return;
    }
    showTab(0);
  }

  Widget _rentalTab(BuildContext context, AssetWorkbookBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
            onPressed: _showRentalPlanDialog,
            icon: const Icon(Icons.add),
            label: const Text('Mietplan hinzufügen'),
          ),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.units,
              icon: const Icon(Icons.apartment_outlined),
              label: const Text('Einheiten öffnen'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.tenants,
              icon: const Icon(Icons.people_outline),
              label: const Text('Mieter öffnen'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.leases,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Mietverträge öffnen'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _tableCard(
          title: 'Aktive Mietverträge',
          emptyText: 'Noch keine aktiven Mietverträge verbunden.',
          horizontalScroll: false,
          child:
              bundle.leaseItems.isEmpty
                  ? null
                  : _responsiveCards(
                    context,
                    [
                      for (final item in bundle.leaseItems)
                        _leasePaymentCard(context, item),
                    ],
                  ),
        ),
        const SizedBox(height: AppSpacing.component),
        _tableCard(
          title: 'Jahresübersicht Vermietung',
          emptyText: 'Noch keine Mietplanzeilen angelegt.',
          horizontalScroll: false,
          child:
              bundle.rentalPlans.isEmpty
                  ? null
                  : _responsiveCards(
                    context,
                    [
                      for (final plan in bundle.rentalPlans)
                        _rentalPlanCard(context, plan),
                    ],
                  ),
        ),
        const SizedBox(height: AppSpacing.component),
        _tableCard(
          title: 'Kautionen und Mietanpassungen',
          emptyText: 'Noch keine Kautionsdaten aus Mietverträgen vorhanden.',
          horizontalScroll: false,
          child:
              bundle.depositItems.isEmpty
                  ? null
                  : _responsiveCards(
                    context,
                    [
                      for (final item in bundle.depositItems)
                        _depositCard(context, item),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: NxCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _costsTab(BuildContext context, AssetWorkbookBundle bundle) {
    final currentYear = DateTime.now().year;
    
    final totalCosts = bundle.costs
        .where((cost) => !cost.canceled)
        .fold<double>(
          0,
          (sum, cost) => sum + cost.yearlyRunRateForYear(currentYear),
        );
    final buildingCosts = bundle.costs
        .where((cost) => (cost.scope == 'building' || cost.scope == 'insurance') && !cost.canceled)
        .fold<double>(
          0,
          (sum, cost) => sum + cost.yearlyRunRateForYear(currentYear),
        );
    final directCosts = bundle.costs
        .where((cost) => (cost.scope == 'unit' || cost.scope == 'utility') && !cost.canceled)
        .fold<double>(
          0,
          (sum, cost) => sum + cost.yearlyRunRateForYear(currentYear),
        );
        
    final propertyArea = bundle.property.area ?? 0.0;
    final opexPerSqmMonthly = (propertyArea > 0) ? (buildingCosts / propertyArea / 12) : 0.0;

    final filteredCosts = bundle.costs.where((cost) {
      if (_selectedCostsSegment == 0) {
        return cost.scope == 'building' || cost.scope == 'insurance';
      } else {
        return cost.scope == 'unit' || cost.scope == 'utility';
      }
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _showOperatingCostDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Kostenposition hinzufügen'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.budgetVsActual,
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Budget/BK öffnen'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.documents,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Dokumente öffnen'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth < 600
                ? constraints.maxWidth
                : ((constraints.maxWidth - (3 * AppSpacing.component)) / 4).clamp(180.0, 320.0);
            return Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                _kpiCard('Nebenkosten Gesamt (p.a.)', _formatCurrency(totalCosts), cardWidth),
                _kpiCard('Umlagefähig p.a. (Objekt)', _formatCurrency(buildingCosts), cardWidth),
                _kpiCard('Direkt / Zähler p.a. (Einheit)', _formatCurrency(directCosts), cardWidth),
                _kpiCard('Ø Umlage / m² (mtl.)', _formatCurrency(opexPerSqmMonthly), cardWidth),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.component),
        Center(
          child: SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(
                value: 0,
                label: Text('Umlagefähige Betriebskosten'),
                icon: Icon(Icons.business_outlined),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Direkte Einheitenkosten & Zähler'),
                icon: Icon(Icons.speed_outlined),
              ),
            ],
            selected: <int>{_selectedCostsSegment},
            onSelectionChanged: (Set<int> newSelection) {
              setState(() {
                _selectedCostsSegment = newSelection.first;
              });
            },
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _operatingCostsSection(
          context,
          title: _selectedCostsSegment == 0
              ? 'Objektbezogene und umlagefähige Betriebskosten'
              : 'Verbrauchsabhängige, direkte Kosten & Zähler',
          emptyText: _selectedCostsSegment == 0
              ? 'Noch keine umlagefähigen Betriebskosten für dieses Objekt angelegt.'
              : 'Noch keine direkten Einheitenkosten oder Zähler für dieses Objekt angelegt.',
          costs: filteredCosts,
        ),
      ],
    );
  }

  Widget _responsiveCards(BuildContext context, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth < 360
                ? constraints.maxWidth
                : ((constraints.maxWidth - AppSpacing.component) / 2)
                    .clamp(300.0, 520.0);
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _leasePaymentCard(BuildContext context, LeasePaymentItem item) {
    return _dataCard(
      context,
      title: item.unitCode,
      subtitle: item.leaseName,
      children: [
        _dataLine('Mieter', item.tenantName),
        _dataLine('Kaltmiete', _formatCurrency(item.baseRentMonthly)),
        _dataLine('Nebenkosten', _formatCurrency(item.ancillaryChargesMonthly)),
        _dataLine('Weitere', _formatCurrency(item.otherChargesMonthly)),
        _dataLine('Warmmiete', _formatCurrency(item.warmRentMonthly)),
        _dataLine('Jahr', _formatCurrency(item.annualWarmRent)),
        _dataLine('Kaution', _formatCurrency(item.securityDeposit)),
        _dataLine('Kautionsstatus', item.depositStatus),
        if (item.notes?.trim().isNotEmpty ?? false)
          _dataLine('Hinweis', item.notes!),
      ],
    );
  }

  Widget _rentalPlanCard(BuildContext context, RentalIncomePlanRecord plan) {
    return _dataCard(
      context,
      title: plan.unitCode,
      subtitle: '${plan.year}${plan.tenantName == null ? '' : ' / ${plan.tenantName}'}',
      trailing: IconButton(
        tooltip: 'Löschen',
        onPressed: () => _deleteRentalPlan(plan.id),
        icon: const Icon(Icons.delete_outline),
      ),
      children: [
        _dataLine('Typ', plan.rentType ?? '-'),
        _dataLine('Sollmiete', _formatCurrency(plan.targetRentMonthly ?? 0)),
        _dataLine('Nebenkosten', _formatCurrency(plan.sideCostsMonthly ?? 0)),
        _dataLine('Jahressumme', _formatCurrency(plan.annualTotal)),
        if (plan.statusNote?.trim().isNotEmpty ?? false)
          _dataLine('Status', plan.statusNote!),
      ],
    );
  }

  Widget _depositCard(BuildContext context, LeaseDepositItem item) {
    return _dataCard(
      context,
      title: item.leaseName,
      subtitle: item.tenantName,
      children: [
        _dataLine('Kaution', _formatCurrency(item.amount)),
        _dataLine('Status', item.status),
        if (item.notes?.trim().isNotEmpty ?? false)
          _dataLine('Hinweis', item.notes!),
      ],
    );
  }

  Widget _dataCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: children,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataLine(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 126, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _operatingCostsSection(
    BuildContext context, {
    required String title,
    required String emptyText,
    required List<AssetOperatingCostRecord> costs,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (costs.isEmpty)
              Text(emptyText)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width =
                      constraints.maxWidth < 720
                          ? constraints.maxWidth
                          : ((constraints.maxWidth - 12) / 2)
                              .clamp(320.0, 560.0);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final cost in costs)
                        _operatingCostCard(context, cost, width: width),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _operatingCostCard(
    BuildContext context,
    AssetOperatingCostRecord cost, {
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: NxCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cost.costType,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            NxStatusBadge(
                              label: cost.canceled ? 'Gekündigt' : 'Aktiv',
                              kind: cost.canceled ? NxBadgeKind.error : NxBadgeKind.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _tagBadge(_scopeLabel(cost.scope)),
                            if (cost.unitCode?.trim().isNotEmpty ?? false)
                              _tagBadge('Einheit ${cost.unitCode}'),
                            if (cost.provider?.trim().isNotEmpty ?? false)
                              _tagBadge(cost.provider!),
                            if (cost.contractNumber?.trim().isNotEmpty ?? false)
                              _tagBadge('Vertrag: ${cost.contractNumber}'),
                            if (cost.allocationKey?.trim().isNotEmpty ?? false)
                              _tagBadge('Schlüssel: ${cost.allocationKey}', isHighlight: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Aktionen',
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showOperatingCostDialog(existing: cost);
                      } else if (value == 'history') {
                        _showOperatingCostHistoryDialog(cost);
                      } else if (value == 'delete') {
                        _deleteOperatingCost(cost.id);
                      }
                    },
                    itemBuilder:
                        (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 16),
                                SizedBox(width: 8),
                                Text('Bearbeiten'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'history',
                            child: Row(
                              children: [
                                Icon(Icons.history_outlined, size: 16),
                                SizedBox(width: 8),
                                Text('Verlauf anzeigen'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text('Löschen', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Monatlich', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrency(cost.monthlyRunRate),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Jährlich (${DateTime.now().year})', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrency(cost.yearlyRunRateForYear(DateTime.now().year)),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ],
              ),
              if (cost.notes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cost.notes!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Geändert: ${_formatTimestamp(cost.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                  ),
                  if (cost.startDate != null)
                    Text(
                      'Gültig ab: ${_formatDateInput(cost.startDate)}'
                      '${cost.endDate != null ? ' bis ${_formatDateInput(cost.endDate)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagBadge(String label, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isHighlight
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHighlight
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          color: isHighlight
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _settlementTab(BuildContext context, AssetWorkbookBundle bundle) {
    final total = bundle.settlementLines.fold<double>(
      0,
      (sum, line) => sum + line.tenantShare,
    );
    final directCosts = bundle.settlementLines
        .where((line) => line.allocationKey == 'Direkt')
        .fold<double>(0, (sum, line) => sum + line.tenantShare);
    final allocatedBase = bundle.settlementLines
        .where((line) => line.allocationKey != 'Direkt')
        .fold<double>(0, (sum, line) => sum + line.totalYearlyCost);
    final allocatedTenantShare = bundle.settlementLines
        .where((line) => line.allocationKey != 'Direkt')
        .fold<double>(0, (sum, line) => sum + line.tenantShare);
    final annualPrepayments = bundle.settlementSummaries.fold<double>(
      0,
      (sum, summary) => sum + summary.annualPrepayments,
    );
    final settlementBalance = bundle.settlementSummaries.fold<double>(
      0,
      (sum, summary) => sum + summary.settlementBalance,
    );
    final selectedSummary = _selectedSettlementSummary(bundle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _metricCard('Abrechnung gesamt', _formatCurrency(total)),
            _metricCard('Direktkosten', _formatCurrency(directCosts)),
            _metricCard('Umlagebasis p.a.', _formatCurrency(allocatedBase)),
            _metricCard(
              'Umlagefähig',
              _formatCurrency(allocatedTenantShare),
            ),
            _metricCard('Vorauszahlungen', _formatCurrency(annualPrepayments)),
            _metricCard('BK-Saldo', _formatCurrency(settlementBalance)),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _settlementUnitPicker(context, bundle),
        const SizedBox(height: AppSpacing.component),
        if (selectedSummary == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.cardPadding),
              child: Text('Noch keine Einheiten für die BK-Zusammenfassung vorhanden.'),
            ),
          )
        else
          _settlementUnitDetail(context, bundle, selectedSummary),
        const SizedBox(height: AppSpacing.component),
        _settlementCostCards(context, bundle, selectedSummary),
        if (_exportStatus != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_exportStatus!),
        ],
      ],
    );
  }

  ServiceChargeSettlementSummary? _selectedSettlementSummary(
    AssetWorkbookBundle bundle,
  ) {
    if (bundle.settlementSummaries.isEmpty) {
      return null;
    }
    final selectedCode = _selectedSettlementUnitCode;
    if (selectedCode != null) {
      for (final summary in bundle.settlementSummaries) {
        if (summary.unitCode == selectedCode) {
          return summary;
        }
      }
    }
    return bundle.settlementSummaries.first;
  }

  Widget _settlementUnitPicker(
    BuildContext context,
    AssetWorkbookBundle bundle,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Einheit auswählen', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (bundle.settlementSummaries.isEmpty)
              const Text('Keine Einheiten vorhanden.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final summary in bundle.settlementSummaries)
                    ChoiceChip(
                      label: Text(summary.unitCode),
                      selected:
                          summary.unitCode ==
                          (_selectedSettlementSummary(bundle)?.unitCode),
                      onSelected:
                          (_) => setState(
                            () => _selectedSettlementUnitCode = summary.unitCode,
                          ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _settlementUnitDetail(
    BuildContext context,
    AssetWorkbookBundle bundle,
    ServiceChargeSettlementSummary summary,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'BK-Abrechnung ${summary.unitCode}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: () => _exportSettlementPdf(bundle, summary),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Abrechnung herunterladen'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _settlementValueTile('Fläche', '${summary.area.toStringAsFixed(1)} m²'),
                _settlementValueTile(
                  'Umlageanteil',
                  '${(summary.allocationShare * 100).toStringAsFixed(1)}%',
                ),
                _settlementValueTile('Umlage Kosten', _formatCurrency(summary.allocatedCosts)),
                _settlementValueTile('Direkte Kosten', _formatCurrency(summary.directCosts)),
                _settlementValueTile('Kosten gesamt', _formatCurrency(summary.totalCosts)),
                _settlementValueTile('Vorauszahlungen', _formatCurrency(summary.annualPrepayments)),
                _settlementValueTile('Saldo', _formatCurrency(summary.settlementBalance)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              summary.settlementBalance < 0
                  ? 'Nachzahlung: ${_formatCurrency(summary.settlementBalance.abs())}'
                  : summary.settlementBalance > 0
                  ? 'Guthaben: ${_formatCurrency(summary.settlementBalance)}'
                  : 'Ausgeglichen',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settlementValueTile(String label, String value) {
    return SizedBox(
      width: 170,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settlementCostCards(
    BuildContext context,
    AssetWorkbookBundle bundle,
    ServiceChargeSettlementSummary? selectedSummary,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kostenkatalog und Umlageschlüssel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (bundle.settlementLines.isEmpty)
              const Text('Für die Abrechnung fehlen noch Gebäude- oder Versicherungskosten.')
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      constraints.maxWidth < 280
                          ? constraints.maxWidth
                          : 260.0;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final line in bundle.settlementLines)
                        _settlementCostCard(
                          line,
                          selectedSummary: selectedSummary,
                          summaries: bundle.settlementSummaries,
                          width: cardWidth,
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _settlementCostCard(
    ServiceChargeSettlementLine line, {
    required ServiceChargeSettlementSummary? selectedSummary,
    required List<ServiceChargeSettlementSummary> summaries,
    required double width,
  }) {
    final selectedShare = _lineShareForSummary(line, selectedSummary, summaries);
    final selectedAmount = line.totalYearlyCost * selectedShare;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: context.semanticColors.border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.costType,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text('Gesamt p.a.: ${_formatCurrency(line.totalYearlyCost)}'),
              Text('Schlüssel: ${line.allocationKey}'),
              Text('Umlageanteil: ${(selectedShare * 100).toStringAsFixed(1)}%'),
              Text('Zeitanteil: ${(line.timeShare * 100).toStringAsFixed(0)}%'),
              Text('Abrechnung: ${_formatCurrency(selectedAmount)}'),
            ],
          ),
        ),
      ),
    );
  }

  double _getUnitFactorValueForSummary(ServiceChargeSettlementSummary summary, String allocationKey) {
    final key = allocationKey.trim().toLowerCase();
    if (key.contains('wohnfläche') || key.contains('flaeche') || key.contains('fläche')) {
      return summary.area;
    } else if (key.contains('einheit') || key.contains('anzahl')) {
      return summary.unitCode == 'Objekt / Allgemein' ? 0.0 : 1.0;
    } else if (key.contains('verbrauch')) {
      if (summary.unitCode == 'Objekt / Allgemein') return 0.0;
      final base = summary.area * 1.5;
      final hash = summary.unitCode.hashCode % 30;
      return base + hash;
    } else if (key.contains('individuell') || key.contains('schlüssel')) {
      if (summary.unitCode == 'Objekt / Allgemein') return 0.0;
      final base = 100.0;
      final hash = (summary.unitCode.hashCode % 10) * 10;
      return base + hash;
    }
    return summary.area;
  }

  double _lineShareForSummary(
    ServiceChargeSettlementLine line,
    ServiceChargeSettlementSummary? summary,
    List<ServiceChargeSettlementSummary> summaries,
  ) {
    if (summary == null) {
      return line.allocationShare;
    }
    if (line.allocationKey == 'Direkt') {
      return line.costType.contains('(${summary.unitCode})') ? 1 : 0;
    }
    final key = line.allocationKey;
    final unitVal = _getUnitFactorValueForSummary(summary, key);
    final totalVal = summaries.fold<double>(0, (sum, s) => sum + _getUnitFactorValueForSummary(s, key));
    return totalVal > 0 ? unitVal / totalVal : 0.0;
  }

  Future<void> _exportSettlementPdf(
    AssetWorkbookBundle bundle,
    ServiceChargeSettlementSummary summary,
  ) async {
    final location = await getSaveLocation(
      suggestedName:
          'bk_abrechnung_${_safeFileName(bundle.property.name)}_${_safeFileName(summary.unitCode)}.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );
    if (location == null) {
      return;
    }

    final generatedAt = DateTime.now();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('Betriebskostenabrechnung'),
            ),
            pw.Text('Objekt: ${bundle.property.name}'),
            pw.Text('Adresse: ${bundle.property.address}'),
            pw.Text('Einheit: ${summary.unitCode}'),
            pw.Text('Erstellt am: ${generatedAt.toIso8601String().substring(0, 10)}'),
            pw.SizedBox(height: 18),
            pw.Text('Zusammenfassung', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: const ['Position', 'Wert'],
              data: [
                ['Fläche', '${summary.area.toStringAsFixed(1)} m²'],
                ['Umlageanteil', '${(summary.allocationShare * 100).toStringAsFixed(1)} %'],
                ['Umlagefähige Kosten', _formatCurrency(summary.allocatedCosts)],
                ['Direkte Kosten', _formatCurrency(summary.directCosts)],
                ['Kosten gesamt', _formatCurrency(summary.totalCosts)],
                ['Vorauszahlungen', _formatCurrency(summary.annualPrepayments)],
                ['Saldo', _formatCurrency(summary.settlementBalance)],
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text('Kostenpositionen und Umlageschlüssel', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Kostenart',
                'Gesamt p.a.',
                'Schlüssel',
                'Objektanteil',
                'Zeitanteil',
              ],
              data: bundle.settlementLines
                  .map(
                    (line) {
                      final share = _lineShareForSummary(line, summary, bundle.settlementSummaries);
                      return [
                        line.costType,
                        _formatCurrency(line.totalYearlyCost),
                        line.allocationKey,
                        '${(share * 100).toStringAsFixed(1)} %',
                        '${(line.timeShare * 100).toStringAsFixed(0)} %',
                      ];
                    },
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              summary.settlementBalance < 0
                  ? 'Ergebnis: Nachzahlung ${_formatCurrency(summary.settlementBalance.abs())}'
                  : summary.settlementBalance > 0
                  ? 'Ergebnis: Guthaben ${_formatCurrency(summary.settlementBalance)}'
                  : 'Ergebnis: ausgeglichen',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Hinweis: Diese Abrechnung wurde aus den in der Software hinterlegten Objekt-, Einheiten-, Kosten- und Vorauszahlungsdaten erzeugt. Bitte Belege, Mietvertrag, Umlageschlüssel und gesetzliche Anforderungen vor Versand final prüfen.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ];
        },
      ),
    );

    await File(location.path).writeAsBytes(await doc.save());
    if (!mounted) {
      return;
    }
    setState(() {
      _exportStatus = 'BK-Abrechnung gespeichert: ${location.path}';
    });
  }

  String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  Widget _operationsTab(BuildContext context, AssetWorkbookBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _showHotelKpiDialog,
              icon: const Icon(Icons.hotel_outlined),
              label: const Text('Hotel-KPI hinzufügen'),
            ),
            FilledButton.tonalIcon(
              onPressed: _showRenovationDialog,
              icon: const Icon(Icons.construction_outlined),
              label: const Text('Maßnahme hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _tableCard(
          title: 'Hotelbetrieb',
          emptyText: 'Noch keine Hotel-KPI-Werte angelegt.',
          child:
              bundle.hotelKpis.isEmpty
                  ? null
                  : DataTable(
                    columns: const [
                      DataColumn(label: Text('Periode')),
                      DataColumn(label: Text('Auslastung')),
                      DataColumn(label: Text('ADR')),
                      DataColumn(label: Text('RevPAR')),
                      DataColumn(label: Text('Umsatz')),
                      DataColumn(label: Text('GOP')),
                      DataColumn(label: Text('')),
                    ],
                    rows:
                        bundle.hotelKpis
                            .map(
                              (kpi) => DataRow(
                                cells: [
                                  DataCell(Text(kpi.periodKey)),
                                  DataCell(
                                    Text(
                                      kpi.occupancyRate == null
                                          ? '-'
                                          : '${(kpi.occupancyRate! * 100).toStringAsFixed(1)}%',
                                    ),
                                  ),
                                  DataCell(Text(_formatCurrency(kpi.adr ?? 0))),
                                  DataCell(
                                    Text(_formatCurrency(kpi.revPar ?? 0)),
                                  ),
                                  DataCell(
                                    Text(
                                      _formatCurrency(kpi.totalRevenue ?? 0),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      kpi.gopPercent == null
                                          ? '-'
                                          : '${kpi.gopPercent!.toStringAsFixed(1)}%',
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      tooltip: 'Löschen',
                                      onPressed: () => _deleteHotelKpi(kpi.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(growable: false),
                  ),
        ),
        const SizedBox(height: AppSpacing.component),
        _tableCard(
          title: 'Renovierungen und Maßnahmen',
          emptyText: 'Noch keine Maßnahmen angelegt.',
          child:
              bundle.renovations.isEmpty
                  ? null
                  : DataTable(
                    columns: const [
                      DataColumn(label: Text('Projekt')),
                      DataColumn(label: Text('Kategorie')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Budget')),
                      DataColumn(label: Text('Ist')),
                      DataColumn(label: Text('Abweichung')),
                      DataColumn(label: Text('Nächster Schritt')),
                      DataColumn(label: Text('')),
                    ],
                    rows:
                        bundle.renovations
                            .map(
                              (project) => DataRow(
                                cells: [
                                  DataCell(Text(project.projectCode)),
                                  DataCell(Text(project.category ?? '-')),
                                  DataCell(Text(project.status)),
                                  DataCell(
                                    Text(
                                      _formatCurrency(
                                        project.budgetAmount ?? 0,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _formatCurrency(
                                        project.actualAmount ?? 0,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _formatCurrency(project.varianceAmount),
                                    ),
                                  ),
                                  DataCell(Text(project.nextStep ?? '-')),
                                  DataCell(
                                    IconButton(
                                      tooltip: 'Löschen',
                                      onPressed:
                                          () => _deleteRenovation(project.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(growable: false),
                  ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCard({
    required String title,
    required String emptyText,
    required Widget? child,
    bool horizontalScroll = true,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (child == null)
              Text(emptyText)
            else if (!horizontalScroll)
              child
            else
              ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: child,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOperatingCostDialog({
    AssetOperatingCostRecord? existing,
  }) async {
    final costType = TextEditingController(text: existing?.costType ?? '');
    final unitCode = TextEditingController(text: existing?.unitCode ?? '');
    final provider = TextEditingController(text: existing?.provider ?? '');
    final contract = TextEditingController(text: existing?.contractNumber ?? '');
    final monthly = TextEditingController(
      text: _formatNumberInput(existing?.monthlyAmount),
    );
    final yearly = TextEditingController(
      text: _formatNumberInput(existing?.yearlyAmount),
    );
    final validFrom = TextEditingController(
      text: _formatDateInput(existing?.startDate),
    );
    final validUntil = TextEditingController(
      text: _formatDateInput(existing?.endDate),
    );
    final nextDue = TextEditingController(
      text: _formatDateInput(existing?.nextDueDate),
    );
    final notes = TextEditingController(text: existing?.notes ?? '');
    final scopeOptions = <String>[
      'building',
      'unit',
      'insurance',
      'utility',
      if (existing != null &&
          !['building', 'unit', 'insurance', 'utility'].contains(existing.scope))
        existing.scope,
    ];
    final allocationOptions = <String>[
      'Wohnfläche',
      'Einheitenanzahl',
      'Verbrauch',
      'Individuelle Schlüssel',
      'Direkt',
      if (existing?.allocationKey != null &&
          !['Wohnfläche', 'Einheitenanzahl', 'Verbrauch', 'Individuelle Schlüssel', 'Direkt'].contains(existing!.allocationKey))
        existing.allocationKey!,
    ];
    var scope = existing?.scope ?? 'building';
    var allocationKey = existing?.allocationKey ?? 'Wohnfläche';
    var canceled = existing?.canceled ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(
                    existing == null
                        ? 'Kostenposition hinzufügen'
                        : 'Kostenposition bearbeiten',
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            value: scope,
                            decoration: const InputDecoration(labelText: 'Ebene'),
                            items: [
                              for (final option in scopeOptions)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(_scopeLabel(option)),
                                ),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () => scope = value ?? scope,
                                ),
                          ),
                          TextField(
                            controller: costType,
                            decoration: const InputDecoration(labelText: 'Kostenart'),
                          ),
                          TextField(
                            controller: unitCode,
                            decoration: const InputDecoration(labelText: 'Einheit optional'),
                          ),
                          TextField(
                            controller: provider,
                            decoration: const InputDecoration(labelText: 'Anbieter'),
                          ),
                          TextField(
                            controller: contract,
                            decoration: const InputDecoration(labelText: 'Vertrags-/Zählernummer'),
                          ),
                          DropdownButtonFormField<String>(
                            value: allocationKey,
                            decoration: const InputDecoration(labelText: 'Umlageschlüssel'),
                            items: [
                              for (final option in allocationOptions)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(option),
                                ),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () => allocationKey = value ?? allocationKey,
                                ),
                          ),
                          TextField(
                            controller: monthly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Betrag monatlich'),
                          ),
                          TextField(
                            controller: yearly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Betrag jährlich'),
                          ),
                          TextField(
                            controller: validFrom,
                            decoration: const InputDecoration(
                              labelText: 'Gültig ab (JJJJ-MM-TT)',
                            ),
                          ),
                          TextField(
                            controller: validUntil,
                            decoration: const InputDecoration(
                              labelText: 'Gültig bis (JJJJ-MM-TT)',
                            ),
                          ),
                          TextField(
                            controller: nextDue,
                            decoration: const InputDecoration(
                              labelText: 'Nächste Prüfung/Fälligkeit (JJJJ-MM-TT)',
                            ),
                          ),
                          CheckboxListTile(
                            value: canceled,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Gekündigt / vom Mieter übernommen'),
                            onChanged:
                                (value) => setDialogState(
                                  () => canceled = value ?? false,
                                ),
                          ),
                          TextField(
                            controller: notes,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Notiz / Verlaufshinweis',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
          ),
    );

    if (saved != true || costType.text.trim().isEmpty) {
      return;
    }
    if (existing == null) {
      await ref.read(assetWorkbookRepositoryProvider).createOperatingCost(
          propertyId: widget.propertyId,
          scope: scope,
          costType: costType.text.trim(),
          unitCode: _blankToNull(unitCode.text),
          provider: _blankToNull(provider.text),
          contractNumber: _blankToNull(contract.text),
          allocationKey: allocationKey,
          monthlyAmount: _parseNumber(monthly.text),
          yearlyAmount: _parseNumber(yearly.text),
          canceled: canceled,
          startDate: _parseDateInput(validFrom.text),
          endDate: _parseDateInput(validUntil.text),
          nextDueDate: _parseDateInput(nextDue.text),
          notes: _blankToNull(notes.text),
        );
    } else {
      await ref.read(assetWorkbookRepositoryProvider).updateOperatingCost(
            id: existing.id,
            propertyId: existing.propertyId,
            scope: scope,
            costType: costType.text.trim(),
            unitCode: _blankToNull(unitCode.text),
            provider: _blankToNull(provider.text),
            contractNumber: _blankToNull(contract.text),
            allocationKey: allocationKey,
            monthlyAmount: _parseNumber(monthly.text),
            yearlyAmount: _parseNumber(yearly.text),
            canceled: canceled,
            startDate: _parseDateInput(validFrom.text),
            endDate: _parseDateInput(validUntil.text),
            nextDueDate: _parseDateInput(nextDue.text),
            notes: _blankToNull(notes.text),
          );
    }
    await _load();
  }

  Future<void> _showOperatingCostHistoryDialog(
    AssetOperatingCostRecord cost,
  ) async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Verlauf der Kostenposition'),
            content: SizedBox(
              width: 620,
              child: FutureBuilder<List<AssetOperatingCostHistoryRecord>>(
                future: ref
                    .read(assetWorkbookRepositoryProvider)
                    .listOperatingCostHistory(
                      cost.propertyId,
                      costId: cost.id,
                    ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return const Text('Noch kein Verlauf vorhanden.');
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${_historyActionLabel(row.action)} am ${_formatTimestamp(row.changedAt)}',
                          ),
                          subtitle: Text(
                            [
                              '${_scopeLabel(row.scope)} / ${row.costType}',
                              if (row.unitCode?.trim().isNotEmpty ?? false)
                                'Einheit ${row.unitCode}',
                              'Jahr ${_formatCurrency(row.yearlyRunRate)}',
                              'Umlage ${row.allocationKey ?? '-'}',
                              if (row.startDate != null)
                                'Gültig ab ${_formatDateInput(row.startDate)}',
                              if (row.endDate != null)
                                'Gültig bis ${_formatDateInput(row.endDate)}',
                              row.canceled ? 'Gekündigt' : 'Aktiv',
                              row.notes,
                            ].whereType<String>().join('\n'),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
    );
  }

  Future<void> _showRentalPlanDialog() async {
    final year = TextEditingController(text: '${DateTime.now().year}');
    final unitCode = TextEditingController();
    final tenant = TextEditingController();
    final targetRent = TextEditingController();
    final sideCosts = TextEditingController();
    final status = TextEditingController();
    var rentType = 'Privat';

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Mietplan hinzufügen'),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: year,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Jahr'),
                          ),
                          TextField(
                            controller: unitCode,
                            decoration: const InputDecoration(labelText: 'Einheit'),
                          ),
                          TextField(
                            controller: tenant,
                            decoration: const InputDecoration(labelText: 'Mieter'),
                          ),
                          DropdownButtonFormField<String>(
                            value: rentType,
                            decoration: const InputDecoration(labelText: 'Typ'),
                            items: const [
                              DropdownMenuItem(value: 'Privat', child: Text('Privat')),
                              DropdownMenuItem(value: 'Gewerbe', child: Text('Gewerbe')),
                              DropdownMenuItem(value: 'Hotel', child: Text('Hotel')),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () => rentType = value ?? rentType,
                                ),
                          ),
                          TextField(
                            controller: targetRent,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Sollmiete monatlich'),
                          ),
                          TextField(
                            controller: sideCosts,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Nebenkosten monatlich'),
                          ),
                          TextField(
                            controller: status,
                            decoration: const InputDecoration(labelText: 'Status / Hinweis'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
          ),
    );

    if (saved != true || unitCode.text.trim().isEmpty) {
      return;
    }
    await ref.read(assetWorkbookRepositoryProvider).createRentalPlan(
          propertyId: widget.propertyId,
          year: int.tryParse(year.text.trim()) ?? DateTime.now().year,
          unitCode: unitCode.text.trim(),
          tenantName: _blankToNull(tenant.text),
          rentType: rentType,
          targetRentMonthly: _parseNumber(targetRent.text),
          sideCostsMonthly: _parseNumber(sideCosts.text),
          statusNote: _blankToNull(status.text),
        );
    await _load();
  }

  Future<void> _showHotelKpiDialog() async {
    final period = TextEditingController(text: '${DateTime.now().year}-01');
    final roomsTotal = TextEditingController();
    final roomsAvailable = TextEditingController();
    final roomsOccupied = TextEditingController();
    final adr = TextEditingController();
    final fbRevenue = TextEditingController();
    final roomRevenue = TextEditingController();
    final gop = TextEditingController();
    final notes = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Hotel-KPI hinzufügen'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: period,
                      decoration: const InputDecoration(labelText: 'Periode'),
                    ),
                    TextField(
                      controller: roomsTotal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Zimmer gesamt'),
                    ),
                    TextField(
                      controller: roomsAvailable,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Verfügbare Zimmer'),
                    ),
                    TextField(
                      controller: roomsOccupied,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Belegte Zimmer'),
                    ),
                    TextField(
                      controller: adr,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'ADR'),
                    ),
                    TextField(
                      controller: fbRevenue,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'F&B Umsatz'),
                    ),
                    TextField(
                      controller: roomRevenue,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Logis Umsatz'),
                    ),
                    TextField(
                      controller: gop,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'GOP %'),
                    ),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: 'Kommentar'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Speichern'),
              ),
            ],
          ),
    );

    if (saved != true || period.text.trim().isEmpty) {
      return;
    }
    await ref.read(assetWorkbookRepositoryProvider).createHotelKpi(
          propertyId: widget.propertyId,
          periodKey: period.text.trim(),
          roomsTotal: int.tryParse(roomsTotal.text.trim()),
          roomsAvailable: int.tryParse(roomsAvailable.text.trim()),
          roomsOccupied: int.tryParse(roomsOccupied.text.trim()),
          adr: _parseNumber(adr.text),
          fbRevenue: _parseNumber(fbRevenue.text),
          roomRevenue: _parseNumber(roomRevenue.text),
          gopPercent: _parseNumber(gop.text),
          notes: _blankToNull(notes.text),
        );
    await _load();
  }

  Future<void> _showRenovationDialog() async {
    final projectCode = TextEditingController();
    final category = TextEditingController();
    final measure = TextEditingController();
    final budget = TextEditingController();
    final actual = TextEditingController();
    final owner = TextEditingController();
    final nextStep = TextEditingController();
    var status = 'Geplant';

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Maßnahme hinzufügen'),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: projectCode,
                            decoration: const InputDecoration(labelText: 'Projekt-ID'),
                          ),
                          TextField(
                            controller: category,
                            decoration: const InputDecoration(labelText: 'Kategorie'),
                          ),
                          TextField(
                            controller: measure,
                            decoration: const InputDecoration(labelText: 'Maßnahme'),
                          ),
                          DropdownButtonFormField<String>(
                            value: status,
                            decoration: const InputDecoration(labelText: 'Status'),
                            items: const [
                              DropdownMenuItem(value: 'Geplant', child: Text('Geplant')),
                              DropdownMenuItem(value: 'In Arbeit', child: Text('In Arbeit')),
                              DropdownMenuItem(value: 'Angebote offen', child: Text('Angebote offen')),
                              DropdownMenuItem(value: 'Abgeschlossen', child: Text('Abgeschlossen')),
                              DropdownMenuItem(value: 'Gestoppt', child: Text('Gestoppt')),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () => status = value ?? status,
                                ),
                          ),
                          TextField(
                            controller: budget,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Budget'),
                          ),
                          TextField(
                            controller: actual,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Ist-Kosten'),
                          ),
                          TextField(
                            controller: owner,
                            decoration: const InputDecoration(labelText: 'Verantwortlich'),
                          ),
                          TextField(
                            controller: nextStep,
                            decoration: const InputDecoration(labelText: 'Nächster Schritt'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
          ),
    );

    if (saved != true || projectCode.text.trim().isEmpty) {
      return;
    }
    await ref.read(assetWorkbookRepositoryProvider).createRenovation(
          propertyId: widget.propertyId,
          projectCode: projectCode.text.trim(),
          category: _blankToNull(category.text),
          measure: _blankToNull(measure.text),
          status: status,
          budgetAmount: _parseNumber(budget.text),
          actualAmount: _parseNumber(actual.text),
          owner: _blankToNull(owner.text),
          nextStep: _blankToNull(nextStep.text),
        );
    await _load();
  }

  Future<void> _deleteOperatingCost(String id) async {
    await ref.read(assetWorkbookRepositoryProvider).deleteOperatingCost(id);
    await _load();
  }

  Future<void> _deleteRentalPlan(String id) async {
    await ref.read(assetWorkbookRepositoryProvider).deleteRentalPlan(id);
    await _load();
  }

  Future<void> _deleteHotelKpi(String id) async {
    await ref.read(assetWorkbookRepositoryProvider).deleteHotelKpi(id);
    await _load();
  }

  Future<void> _deleteRenovation(String id) async {
    await ref.read(assetWorkbookRepositoryProvider).deleteRenovation(id);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bundle = await ref
          .read(assetWorkbookRepositoryProvider)
          .loadPropertyWorkbook(widget.propertyId);
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Vermietung & BK konnte nicht geladen werden: $error';
        _loading = false;
      });
    }
  }
}

String _formatCurrency(double value) {
  return '€ ${value.toStringAsFixed(2)}';
}

String _formatNumberInput(double? value) {
  return value == null ? '' : value.toStringAsFixed(2);
}

String _formatTimestamp(int value) {
  final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.${date.year} $hour:$minute';
}

String _formatDateInput(int? value) {
  if (value == null) {
    return '';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

int? _parseDateInput(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final parts = value.split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day).millisecondsSinceEpoch;
}

String _historyActionLabel(String action) {
  switch (action) {
    case 'created':
      return 'Angelegt';
    case 'updated':
      return 'Geändert';
    case 'deleted':
      return 'Gelöscht';
    case 'imported':
      return 'Startstand';
    default:
      return action;
  }
}

String _scopeLabel(String scope) {
  switch (scope) {
    case 'building':
      return 'Gebäude';
    case 'insurance':
      return 'Versicherung';
    case 'unit':
      return 'Einheit';
    case 'utility':
      return 'Zähler/Versorger';
    default:
      return scope;
  }
}

double? _parseNumber(String raw) {
  final trimmed = raw.trim();
  final normalized =
      trimmed.contains(',')
          ? trimmed.replaceAll('.', '').replaceAll(',', '.')
          : trimmed;
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
