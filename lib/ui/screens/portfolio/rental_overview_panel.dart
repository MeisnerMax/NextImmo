/// The portfolio-wide rental view (Welle 3, AP7 — SCR-065).
///
/// Revives a screen that had become unreachable (`DEAD-002`) as a portfolio
/// page on the P2-D05 contract: occupancy, vacancy, rent volume and expiring
/// leases across **all** properties, with a jump into the single object. The
/// figures come from the same computation the per-property rent roll uses, so
/// the portfolio total and the object detail cannot tell different stories.
///
/// Two honesty rules the page keeps:
///
///   * a bounded workspace-wide read **says when it was bounded** — a silently
///     truncated portfolio reads as a smaller portfolio;
///   * rents in different currencies are named, not added (DEC-011).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/leasing_operations/application/rental_overview_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../property_detail/leasing/widgets/lease_lifecycle.dart';

class RentalOverviewPanel extends ConsumerWidget {
  const RentalOverviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rentalOverviewControllerProvider);
    final controller = ref.read(rentalOverviewControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxPageHeader(
          title: 'Vermietung',
          subtitle: state.asOfDate == null
              ? 'Belegung und Mieten über alle Objekte.'
              : 'Belegung und Mieten über alle Objekte, Stand '
                    '${formatLeaseDate(state.asOfDate)}.',
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, ref, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    RentalOverviewState state,
    RentalOverviewController controller,
  ) {
    switch (state.phase) {
      case RentalOverviewPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Die Vermietungssicht wird je Arbeitsbereich geführt. Melde dich '
              'an oder wähle einen Arbeitsbereich.',
          icon: Icons.workspaces_outline,
        );
      case RentalOverviewPhase.loading:
        return const _OverviewSkeleton();
      case RentalOverviewPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf die Vermietungssicht',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Einheiten und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case RentalOverviewPhase.error:
        return NxEmptyState(
          title: 'Vermietungssicht konnte nicht geladen werden',
          description:
              state.message ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case RentalOverviewPhase.empty:
        return const NxEmptyState(
          title: 'Noch keine Einheit im Portfolio',
          description:
              'Die Vermietungssicht fasst die Einheiten aller Objekte '
              'zusammen. Lege in einem Objekt die erste Einheit an.',
          icon: Icons.meeting_room_outlined,
        );
      case RentalOverviewPhase.ready:
        return _buildReady(context, ref, state);
    }
  }

  Widget _buildReady(
    BuildContext context,
    WidgetRef ref,
    RentalOverviewState state,
  ) {
    final totals = state.totals;
    return ListView(
      children: <Widget>[
        if (state.truncated) ...<Widget>[
          _TruncationNotice(),
          const SizedBox(height: AppSpacing.component),
        ],
        if (totals != null) ...<Widget>[
          _TotalsCard(totals: totals),
          const SizedBox(height: AppSpacing.component),
        ],
        NxCard(
          child: NxDataTableShell(
            child: DataTable(
              showCheckboxColumn: false,
              columns: const <DataColumn>[
                DataColumn(label: Text('Objekt')),
                DataColumn(label: Text('Ort')),
                DataColumn(label: Text('Einheiten')),
                DataColumn(label: Text('Vermietet')),
                DataColumn(label: Text('Leer')),
                DataColumn(label: Text('Belegung')),
                DataColumn(label: Text('Läuft aus')),
                DataColumn(label: Text('Grundmiete')),
              ],
              rows: <DataRow>[
                for (final row in state.rows)
                  DataRow(
                    onSelectChanged: (_) => _openProperty(ref, row.propertyId),
                    cells: <DataCell>[
                      DataCell(Text(row.propertyName)),
                      DataCell(Text(row.city)),
                      DataCell(Text('${row.summary.unitCount}')),
                      DataCell(Text('${row.summary.occupiedUnitCount}')),
                      DataCell(Text('${row.summary.vacantUnitCount}')),
                      DataCell(Text(_rate(row.summary.occupancyRate))),
                      DataCell(Text('${row.expiringLeaseCount}')),
                      DataCell(
                        Text(
                          row.summary.hasMixedCurrencies
                              ? row.summary.currencies.join(' + ')
                              : formatLeaseMoney(
                                  row.summary.totalBaseRentMonthly,
                                  row.summary.currencyCode,
                                ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Pure navigation: open the property on its rent roll, which is the page
  /// this row summarises.
  void _openProperty(WidgetRef ref, String propertyId) {
    ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.rentRoll;
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
  }
}

String _rate(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final RentalOverviewTotals totals;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: <Widget>[
              _Kpi(label: 'Objekte', value: '${totals.propertyCount}'),
              _Kpi(label: 'Einheiten', value: '${totals.unitCount}'),
              _Kpi(label: 'Vermietet', value: '${totals.occupiedUnitCount}'),
              _Kpi(label: 'Leer', value: '${totals.vacantUnitCount}'),
              _Kpi(label: 'Offline', value: '${totals.offlineUnitCount}'),
              _Kpi(
                label: 'Belegungsquote',
                value: _rate(totals.occupancyRate),
              ),
              _Kpi(
                label: 'Läuft in 90 Tagen aus',
                value: '${totals.expiringLeaseCount}',
              ),
              _Kpi(
                label: 'Grundmiete / Monat',
                value: totals.hasMixedCurrencies
                    ? totals.currencies.join(' + ')
                    : formatLeaseMoney(
                        totals.totalBaseRentMonthly,
                        totals.currencyCode,
                      ),
              ),
            ],
          ),
          if (totals.hasMixedCurrencies) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Die Verträge des Portfolios sind in '
              '${totals.currencies.join(' und ')} geführt — Beträge '
              'verschiedener Währungen werden nicht addiert.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// A bounded read that says it was bounded.
class _TruncationNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: semantic.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: semantic.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Nur ein Teil des Portfolios',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Der Bestand überschreitet, was diese Sicht in einem Zug '
                  'liest. Die Zahlen unten beschreiben deshalb nur die '
                  'gelesenen Objekte — nicht das ganze Portfolio.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 5; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}
