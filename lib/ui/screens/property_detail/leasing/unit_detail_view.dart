/// The full detail of one unit (Welle 3, AP2 — SCR-025).
///
/// Replaces the 1382-LOC legacy `UnitDetailScreen` (`BIG-016`). The load-bearing
/// difference is not the size: the legacy detail was built on
/// `UnitDetailBundle.activeLease`, a **single** lease. `OPN-DOM-001` (decided
/// 2026-07-29, documented default overridden) says a unit may hold several
/// concurrently effective leases, so this view shows a lease **list** and never
/// speaks of "the" lease of a unit. That is the point at which the decision
/// reaches the product rather than only the schema.
///
/// The occupancy status is likewise presented as a consequence (AGG-004): the
/// view states where it comes from instead of offering a control the server
/// would refuse.
library;

import 'package:flutter/material.dart';

import '../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../../features/leasing_operations/domain/unit_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_section_header.dart';
import '../../../components/nx_status_badge.dart';
import 'widgets/leasing_badges.dart';

class UnitDetailView extends StatelessWidget {
  const UnitDetailView({
    super.key,
    required this.unit,
    required this.leases,
    required this.canMutate,
    required this.onEdit,
    required this.onTakeOffline,
    required this.onReturnOnline,
    this.onOpenLease,
  });

  final UnitDto unit;
  final List<LeaseSummaryDto> leases;
  final bool canMutate;
  final VoidCallback onEdit;
  final VoidCallback onTakeOffline;
  final VoidCallback onReturnOnline;
  final ValueChanged<String>? onOpenLease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = unit.status == UnitStatus.offline;
    final effective = leases.where((lease) => lease.isEffective).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      unit.unitCode,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  UnitStatusBadge(status: unit.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _statusExplanation(offline, effective.length),
                style: theme.textTheme.bodySmall,
              ),
              if (offline && unit.offlineReason != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('Grund: ${unit.offlineReason}'),
              ],
              if (!offline &&
                  unit.status == UnitStatus.vacant &&
                  unit.vacancySince != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('Leer seit ${_formatDate(unit.vacancySince)}'),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: canMutate ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Bearbeiten'),
                  ),
                  if (offline)
                    FilledButton.icon(
                      onPressed: canMutate ? onReturnOnline : null,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Zurückholen'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: canMutate ? onTakeOffline : null,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Offline nehmen'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(title: 'Stammdaten'),
              _DetailRow(label: 'Typ', value: unit.unitType ?? '—'),
              _DetailRow(label: 'Etage', value: unit.floor ?? '—'),
              _DetailRow(label: 'Fläche', value: _formatArea(unit.areaSqm)),
              _DetailRow(label: 'Zimmer', value: _formatCount(unit.rooms)),
              _DetailRow(label: 'Bäder', value: _formatCount(unit.bathrooms)),
              const SizedBox(height: 12),
              const NxSectionHeader(title: 'Miete und Vermarktung'),
              _DetailRow(
                label: 'Zielmiete',
                value: _formatMoney(unit.targetRentMonthly, unit.currencyCode),
              ),
              _DetailRow(
                label: 'Marktmiete',
                value: _formatMoney(unit.marketRentMonthly, unit.currencyCode),
              ),
              _DetailRow(
                label: 'Vermarktung',
                value: unit.marketingStatus ?? '—',
              ),
              _DetailRow(
                label: 'Renovierung',
                value: unit.renovationStatus ?? '—',
              ),
              _DetailRow(
                label: 'Bezugsfertig ab',
                value: _formatDate(unit.expectedReadyDate),
              ),
              if (unit.nextAction != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('Nächster Schritt: ${unit.nextAction}'),
              ],
              if (unit.notes != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(unit.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _LeaseSection(leases: leases, onOpenLease: onOpenLease),
      ],
    );
  }

  /// AGG-004 in words. The count matters: with `OPN-DOM-001` "occupied" can mean
  /// more than one lease, and hiding that would be the old single-lease model
  /// leaking back into the UI.
  static String _statusExplanation(bool offline, int effectiveCount) {
    if (offline) {
      return 'Diese Einheit wurde bewusst offline genommen. Solange das gilt, '
          'folgt ihr Status nicht den Verträgen.';
    }
    if (effectiveCount == 0) {
      return 'Der Status folgt aus den wirksamen Verträgen: derzeit gibt es '
          'keinen, deshalb gilt die Einheit als leerstehend.';
    }
    if (effectiveCount == 1) {
      return 'Der Status folgt aus den wirksamen Verträgen: einer ist aktiv, '
          'deshalb gilt die Einheit als vermietet.';
    }
    return 'Der Status folgt aus den wirksamen Verträgen: $effectiveCount sind '
        'gleichzeitig aktiv (Teilflächen-Vermietung), deshalb gilt die Einheit '
        'als vermietet.';
  }
}

class _LeaseSection extends StatelessWidget {
  const _LeaseSection({required this.leases, required this.onOpenLease});

  final List<LeaseSummaryDto> leases;
  final ValueChanged<String>? onOpenLease;

  @override
  Widget build(BuildContext context) {
    if (leases.isEmpty) {
      return const NxCard(
        child: NxEmptyState(
          title: 'Keine Verträge auf dieser Einheit',
          description:
              'Sobald ein Vertrag angelegt und aktiviert ist, erscheint er '
              'hier und die Einheit gilt als vermietet.',
          icon: Icons.description_outlined,
        ),
      );
    }
    final effective = leases.where((lease) => lease.isEffective).length;
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NxSectionHeader(
            title: 'Verträge dieser Einheit',
            // Never "der Vertrag": the count is part of the fact.
            description: '${leases.length} insgesamt, $effective wirksam',
          ),
          const SizedBox(height: 8),
          NxDataTableShell(
            child: DataTable(
              showCheckboxColumn: false,
              columns: const <DataColumn>[
                DataColumn(label: Text('Vertrag')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Wirksam')),
                DataColumn(label: Text('Beginn')),
                DataColumn(label: Text('Ende')),
                DataColumn(label: Text('Grundmiete')),
              ],
              rows: <DataRow>[
                for (final lease in leases)
                  DataRow(
                    onSelectChanged: onOpenLease == null
                        ? null
                        : (_) => onOpenLease!(lease.id),
                    cells: <DataCell>[
                      DataCell(Text(lease.leaseName)),
                      DataCell(LeaseStatusBadge(status: lease.status)),
                      DataCell(
                        lease.isEffective
                            ? const NxStatusBadge(
                                label: 'Ja',
                                kind: NxBadgeKind.success,
                              )
                            : const NxStatusBadge(
                                label: 'Nein',
                                kind: NxBadgeKind.neutral,
                              ),
                      ),
                      DataCell(Text(_formatDate(lease.startDate))),
                      DataCell(Text(_formatDate(lease.endDate))),
                      DataCell(
                        Text(
                          _formatMoney(
                            lease.baseRentMonthly,
                            lease.currencyCode,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _formatArea(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)} m²';

String _formatCount(double? value) =>
    value == null ? '—' : value.toStringAsFixed(1);

/// DEC-011: an amount without its currency is reported as such rather than
/// rendered as a bare number. In SQLite mode that is the normal case for units.
String _formatMoney(double? amount, String? currency) {
  if (amount == null) {
    return '—';
  }
  if (currency == null) {
    return '${amount.toStringAsFixed(2)} (Währung nicht hinterlegt)';
  }
  return '${amount.toStringAsFixed(2)} $currency';
}
