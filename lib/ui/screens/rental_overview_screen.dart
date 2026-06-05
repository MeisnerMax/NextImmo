import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/asset_workbook.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class RentalOverviewScreen extends ConsumerWidget {
  const RentalOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(_rentalOverviewProvider);
    return overviewAsync.when(
      data: (overview) => _RentalOverviewContent(
        overview: overview,
        onOpenProperty: (propertyId) {
          ref.read(selectedAssetWorkbookTabProvider.notifier).state = 0;
          ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.assetWorkbook;
          ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        },
        onOpenPropertyWorkflow: (propertyId, page, workbookTab) {
          ref.read(selectedAssetWorkbookTabProvider.notifier).state =
              workbookTab;
          ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
          ref.read(propertyDetailPageProvider.notifier).state = page;
          ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        },
        onOpenPage: (page) {
          ref.read(selectedPropertyIdProvider.notifier).state = null;
          ref.read(selectedScenarioIdProvider.notifier).state = null;
          ref.read(globalPageProvider.notifier).state = page;
        },
        onRefresh: () => ref.invalidate(_rentalOverviewProvider),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Text('Vermietung & BK konnte nicht geladen werden: $error'),
            ),
          ),
    );
  }
}

final _rentalOverviewProvider =
    FutureProvider.autoDispose<PortfolioRentalOverview>((ref) {
  return ref.watch(assetWorkbookRepositoryProvider).loadPortfolioOverview();
});

class _RentalOverviewContent extends StatefulWidget {
  const _RentalOverviewContent({
    required this.overview,
    required this.onOpenProperty,
    required this.onOpenPropertyWorkflow,
    required this.onOpenPage,
    required this.onRefresh,
  });

  final PortfolioRentalOverview overview;
  final ValueChanged<String> onOpenProperty;
  final void Function(String propertyId, PropertyDetailPage page, int workbookTab)
  onOpenPropertyWorkflow;
  final ValueChanged<GlobalPage> onOpenPage;
  final VoidCallback onRefresh;

  @override
  State<_RentalOverviewContent> createState() => _RentalOverviewContentState();
}

class _RentalOverviewContentState extends State<_RentalOverviewContent> {
  @override
  Widget build(BuildContext context) {
    final overview = widget.overview;
    final unitsTotal = overview.rentedUnits + overview.emptyUnits;
    final occupancyRate =
        unitsTotal == 0 ? 0.0 : overview.rentedUnits / unitsTotal;
    final netAfterCosts = overview.annualRent - overview.annualOperatingCosts;
    final costRatio =
        overview.annualRent == 0
            ? 0.0
            : overview.annualOperatingCosts / overview.annualRent;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vermietung & BK',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vermietung, Betriebskosten und BK-Abrechnung auf Portfolioebene.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.semanticColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Aktualisieren',
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _metricCard('Assets', '${overview.assetsTotal}'),
            _metricCard('Nicht aktiv', '${overview.assetsNotActive}'),
            _metricCard('Vermietet', '${overview.rentedUnits}'),
            _metricCard('Leer', '${overview.emptyUnits}'),
            _metricCard('Belegung', _formatPercent(occupancyRate)),
            _metricCard('Jahresmiete', _formatCurrency(overview.annualRent)),
            _metricCard('Netto nach Kosten', _formatCurrency(netAfterCosts)),
            _metricCard(
              'Betriebskosten p.a.',
              _formatCurrency(overview.annualOperatingCosts),
            ),
            _metricCard('Kostenquote', _formatPercent(costRatio)),
            _metricCard(
              'Offene Kaution',
              _formatCurrency(overview.openDepositAmount),
            ),
            _metricCard(
              'BK-Saldo',
              _formatCurrency(overview.serviceChargeBalance),
            ),
            _metricCard(
              'Datenabdeckung',
              _formatPercent(overview.sourceCoverageRate),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        _workflowPanel(context),
        const SizedBox(height: AppSpacing.component),
        _priorityPanel(context),
        const SizedBox(height: AppSpacing.component),
        _objectOverviewCard(context, overview),
      ],
    );
  }

  Widget _objectOverviewCard(
    BuildContext context,
    PortfolioRentalOverview overview,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Objektübersicht',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (overview.rows.isEmpty)
              const Text('Noch keine Objekte vorhanden.')
            else
              Column(
                children: [
                  for (final row in overview.rows) ...[
                    _objectOverviewRow(context, row),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _objectOverviewRow(
    BuildContext context,
    PortfolioRentalOverviewRow row,
  ) {
    final costRatio =
        row.annualRent == 0 ? 0.0 : row.annualOperatingCosts / row.annualRent;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.propertyName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.propertyType,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.semanticColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Objekt öffnen',
                  onPressed: () => widget.onOpenProperty(row.propertyId),
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _objectMetric('Einheiten', '${row.units}'),
                _objectMetric('Vermietet', '${row.occupiedUnits}'),
                _objectMetric('Leer', '${row.vacantUnits}'),
                _objectMetric('Jahresmiete', _formatCurrency(row.annualRent)),
                _objectMetric(
                  'BK/Kosten p.a.',
                  _formatCurrency(row.annualOperatingCosts),
                ),
                _objectMetric('Kostenquote', _formatPercent(costRatio)),
                _objectMetric(
                  'Netto',
                  _formatCurrency(row.netAnnualAfterCosts),
                ),
                _objectMetric(
                  'Offene Kaution',
                  _formatCurrency(row.openDepositAmount),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _balanceChip(row.serviceChargeBalance),
                Tooltip(
                  message:
                      row.missingSourceLabels.isEmpty
                          ? 'Alle Bereiche befüllt'
                          : row.missingSourceLabels.join(', '),
                  child: Chip(
                    label: Text(
                      'Daten ${_formatPercent(row.sourceCoverageRate)}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Chip(
                  label: Text(_signalLabel(row)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _objectMetric(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
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

  Widget _workflowPanel(BuildContext context) {
    final targetPropertyId = _defaultWorkflowPropertyId();
    final steps = [
      (
        Icons.home_work_outlined,
        'Assets pflegen',
        'Stammdaten, Einheiten, Flächen und Status prüfen.',
        PropertyDetailPage.units,
        0,
      ),
      (
        Icons.apartment_outlined,
        'Mieten planen',
        'Sollmieten, Nebenkosten, Mietwechsel und Leerstand.',
        PropertyDetailPage.leases,
        0,
      ),
      (
        Icons.request_quote_outlined,
        'Kosten erfassen',
        'Versicherung, Zähler, Gebäude- und Einheitskosten.',
        PropertyDetailPage.assetWorkbook,
        1,
      ),
      (
        Icons.folder_open_outlined,
        'BK & Belege prüfen',
        'Umlageschlüssel, Vorauszahlungen, Verträge und Dokumente.',
        PropertyDetailPage.assetWorkbook,
        2,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (var i = 0; i < steps.length; i++)
              SizedBox(
                width: 280,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(steps[i].$1, size: 18)),
                  title: Text(steps[i].$2),
                  subtitle: Text(steps[i].$3),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: targetPropertyId != null,
                  onTap:
                      targetPropertyId == null
                          ? null
                          : () => widget.onOpenPropertyWorkflow(
                            targetPropertyId,
                            steps[i].$4,
                            steps[i].$5,
                          ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _defaultWorkflowPropertyId() {
    if (widget.overview.rows.isEmpty) {
      return null;
    }
    final issues = widget.overview.rows
        .where((row) => _signalLabel(row) != 'OK')
        .toList(growable: true)
      ..sort((a, b) => _signalPriority(a).compareTo(_signalPriority(b)));
    return issues.isEmpty ? widget.overview.rows.first.propertyId : issues.first.propertyId;
  }

  Widget _priorityPanel(BuildContext context) {
    final issues = widget.overview.rows
        .where((row) => _signalLabel(row) != 'OK')
        .toList(growable: true)
      ..sort((a, b) => _signalPriority(a).compareTo(_signalPriority(b)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Priorisierte Workflows',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (issues.isEmpty)
              const Text('Keine offenen Vermietungs- oder BK-Signale.')
            else
              Column(
                children: [
                  for (final row in issues.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_signalIcon(row)),
                      title: Text(row.propertyName),
                      subtitle: Text(_signalDetail(row)),
                      trailing: TextButton.icon(
                        onPressed: () => widget.onOpenProperty(row.propertyId),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Öffnen'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return SizedBox(
      width: 210,
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
}

Widget _balanceChip(double value) {
  final label =
      value < 0
          ? 'Nachzahlung ${_formatCurrency(value.abs())}'
          : value > 0
          ? 'Guthaben ${_formatCurrency(value)}'
          : 'Ausgeglichen';
  return Chip(
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

String _signalLabel(PortfolioRentalOverviewRow row) {
  if (row.vacantUnits > 0) {
    return 'Leerstand prüfen';
  }
  if (row.annualRent > 0 &&
      row.annualOperatingCosts / row.annualRent > 0.35) {
    return 'Kostenquote hoch';
  }
  if (row.serviceChargeBalance < 0) {
    return 'BK Nachzahlung';
  }
  if (row.openDepositAmount > 0) {
    return 'Kaution offen';
  }
  if (row.missingSourceLabels.isNotEmpty) {
    return 'Daten prüfen';
  }
  return 'OK';
}

IconData _signalIcon(PortfolioRentalOverviewRow row) {
  final signal = _signalLabel(row);
  if (signal == 'Leerstand prüfen') {
    return Icons.apartment_outlined;
  }
  if (signal == 'Kostenquote hoch' || signal == 'BK Nachzahlung') {
    return Icons.request_quote_outlined;
  }
  if (signal == 'Kaution offen') {
    return Icons.account_balance_wallet_outlined;
  }
  if (signal == 'Daten prüfen') {
    return Icons.table_chart_outlined;
  }
  return Icons.check_circle_outline;
}

String _signalDetail(PortfolioRentalOverviewRow row) {
  final signal = _signalLabel(row);
  if (signal == 'Leerstand prüfen') {
    return '${row.vacantUnits} leere Einheit(en), Vermietung und Mietplan prüfen.';
  }
  if (signal == 'Kostenquote hoch') {
    return 'Betriebskostenquote über 35%, Kostenpositionen und Umlage prüfen.';
  }
  if (signal == 'BK Nachzahlung') {
    return 'BK-Saldo negativ, Vorauszahlungen und Abrechnung je Einheit prüfen.';
  }
  if (signal == 'Kaution offen') {
    return 'Offene Kaution ${_formatCurrency(row.openDepositAmount)} prüfen.';
  }
  if (signal == 'Daten prüfen') {
    return 'Fehlende Datenbereiche: ${row.missingSourceLabels.join(', ')}.';
  }
  return 'Keine offenen Signale.';
}

int _signalPriority(PortfolioRentalOverviewRow row) {
  final signal = _signalLabel(row);
  if (signal == 'Leerstand prüfen') {
    return 1;
  }
  if (signal == 'BK Nachzahlung') {
    return 2;
  }
  if (signal == 'Kostenquote hoch') {
    return 3;
  }
  if (signal == 'Kaution offen') {
    return 4;
  }
  if (signal == 'Daten prüfen') {
    return 5;
  }
  return 99;
}

String _formatCurrency(double value) {
  return '€ ${value.toStringAsFixed(2)}';
}

String _formatPercent(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
