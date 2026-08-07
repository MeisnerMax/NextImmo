/// The rent roll of a property (Welle 3, AP6 — SCR-030).
///
/// Two documents on one page, and the surface never lets them blur:
///
///   * **Live** is the primary view — the current state, one row per unit,
///     recomputed on every read. This is what an operator looks at.
///   * **Snapshots** are frozen documents (AGG-007). They exist for reporting:
///     immutable, several per reporting date allowed, no edit and no delete.
///     A correction is a new snapshot, and the page says so.
///
/// Three figures here look like mistakes and are not, so each is explained
/// rather than merely displayed:
///
///   * a unit that is occupied and still contributes 0,00 — occupancy is
///     status-based, the rent roll additionally needs the lease term to cover
///     the reporting date;
///   * a missing total when the contributing leases disagree on currency —
///     DEC-011, the currencies found are named instead;
///   * a missing occupancy rate at zero units, shown as "—" rather than 0 %.
///
/// V9.1 points 3 and 4 dissolve here: the lines carry unit, status and lease
/// count instead of blanks, and both tables live in an `NxDataTableShell` that
/// scrolls instead of overflowing to the right.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/leasing_repository.dart';
import '../../../../features/leasing_operations/application/rent_roll_controller.dart';
import '../../../../features/leasing_operations/domain/rent_roll_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_page_header.dart';
import '../../../components/nx_section_header.dart';
import '../../../components/responsive_constraints.dart';
import '../../../theme/app_theme.dart';
import 'widgets/lease_lifecycle.dart';
import 'widgets/leasing_badges.dart';

class RentRollPanel extends ConsumerStatefulWidget {
  const RentRollPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<RentRollPanel> createState() => _RentRollPanelState();
}

class _RentRollPanelState extends ConsumerState<RentRollPanel> {
  @override
  Widget build(BuildContext context) {
    final provider = rentRollControllerProvider(widget.propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForActionFeedback(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxPageHeader(
          title: 'Rent Roll',
          subtitle:
              'Der aktuelle Stand, jetzt gerechnet. Ein Snapshot friert ihn '
              'für Berichte ein und bleibt danach unverändert.',
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createSnapshot(controller, state)
                : null,
            icon: const Icon(Icons.ac_unit),
            label: const Text('Snapshot einfrieren'),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: ListView(
            children: <Widget>[
              _LiveSection(state: state, controller: controller),
              const SizedBox(height: AppSpacing.component),
              _HistorySection(
                state: state,
                onSelect: (id) => unawaited(controller.select(id)),
                onLoadMore: () => unawaited(controller.loadMore()),
              ),
              if (state.selectedSnapshotId != null) ...<Widget>[
                const SizedBox(height: AppSpacing.component),
                _SnapshotDetail(state: state),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _listenForActionFeedback(
    AutoDisposeStateNotifierProvider<RentRollController, RentRollState> provider,
  ) {
    ref.listen<RentRollState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(provider.notifier);
      switch (next.actionPhase) {
        case RentRollActionPhase.currencyMismatch:
          // Not a snackbar: the currencies found are the actionable part and
          // belong in front of the user until acknowledged.
          unawaited(
            _showCurrencyMismatchDialog(
              next.currencyMismatch,
              next.actionMessage,
            ),
          );
          controller.clearAction();
        case RentRollActionPhase.succeeded:
        case RentRollActionPhase.readOnly:
        case RentRollActionPhase.forbidden:
        case RentRollActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case RentRollActionPhase.idle:
        case RentRollActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _showCurrencyMismatchDialog(
    RentRollCurrencyMismatch? mismatch,
    String? message,
  ) async {
    final currencies = mismatch?.currencies ?? const <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verträge in unterschiedlichen Währungen'),
        content: Text(
          currencies.isEmpty
              ? 'Die beitragenden Verträge teilen sich keine gemeinsame '
                    'Währung, deshalb wurde kein Snapshot erzeugt: '
                    '${message ?? ''}'
              : 'Die beitragenden Verträge sind in '
                    '${currencies.join(' und ')} geführt. Summen über '
                    'verschiedene Währungen wären falsch, deshalb wurde kein '
                    'Snapshot erzeugt.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Future<void> _createSnapshot(
    RentRollController controller,
    RentRollState state,
  ) async {
    final request = await _showCreateDialog(
      defaultDate: state.live?.asOfDate ?? controller.asOfDate,
      derivableCurrency: state.live?.currencyCode,
      mixedCurrencies: state.live?.hasMixedCurrencies ?? false,
    );
    if (request == null) {
      return;
    }
    await controller.createSnapshot(
      asOfDate: request.asOfDate,
      currencyCode: request.currencyCode,
    );
  }

  Future<_CreateSnapshotRequest?> _showCreateDialog({
    required DateTime defaultDate,
    required String? derivableCurrency,
    required bool mixedCurrencies,
  }) async {
    DateTime asOfDate = defaultDate;
    final currencyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<_CreateSnapshotRequest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Snapshot einfrieren'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 460,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Der Snapshot hält Belegung und Mieten zum Stichtag fest '
                    'und ist danach unveränderlich. Mehrere Snapshots je '
                    'Stichtag sind zulässig — ein späterer ersetzt einen '
                    'früheren nicht, er ergänzt ihn.',
                  ),
                  const SizedBox(height: 16),
                  LeaseDateField(
                    label: 'Stichtag',
                    value: asOfDate,
                    onChanged: (value) =>
                        setDialogState(() => asOfDate = value ?? asOfDate),
                  ),
                  const SizedBox(height: 8),
                  if (mixedCurrencies)
                    const Text(
                      'Achtung: die wirksamen Verträge dieses Objekts sind in '
                      'mehreren Währungen geführt. Der Server verweigert einen '
                      'Snapshot, solange das so ist.',
                    )
                  else
                    TextFormField(
                      controller: currencyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Währung (optional)',
                        helperText: derivableCurrency == null
                            ? 'Kein wirksamer Vertrag gibt eine Währung vor — '
                                  'für ein leerstehendes Objekt ist sie hier '
                                  'anzugeben.'
                            : 'Wird aus den Verträgen abgeleitet '
                                  '($derivableCurrency); eine abweichende '
                                  'Angabe wird abgelehnt.',
                      ),
                      validator: (value) {
                        final trimmed = (value ?? '').trim();
                        if (trimmed.isEmpty || trimmed.length == 3) {
                          return null;
                        }
                        return 'Drei Buchstaben, z. B. EUR.';
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                final currency = currencyController.text.trim().toUpperCase();
                Navigator.of(dialogContext).pop(
                  _CreateSnapshotRequest(
                    asOfDate: asOfDate,
                    currencyCode: currency.isEmpty ? null : currency,
                  ),
                );
              },
              child: const Text('Einfrieren'),
            ),
          ],
        ),
      ),
    );
    currencyController.dispose();
    return result;
  }
}

class _CreateSnapshotRequest {
  const _CreateSnapshotRequest({required this.asOfDate, this.currencyCode});

  final DateTime asOfDate;
  final String? currencyCode;
}

/// The primary half: the current rent roll.
class _LiveSection extends ConsumerWidget {
  const _LiveSection({required this.state, required this.controller});

  final RentRollState state;
  final RentRollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state.livePhase) {
      case RentRollLivePhase.idle:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Arbeitsbereich aktiv',
            description:
                'Der Rent Roll wird je Arbeitsbereich geführt. Melde dich an '
                'oder wähle einen Arbeitsbereich.',
            icon: Icons.workspaces_outline,
          ),
        );
      case RentRollLivePhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case RentRollLivePhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff auf den Rent Roll',
            description:
                'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
                'Einheiten und Verträge (lease.read).',
            icon: Icons.lock_outline,
          ),
        );
      case RentRollLivePhase.error:
        return NxCard(
          child: NxEmptyState(
            title: 'Rent Roll konnte nicht geladen werden',
            description:
                state.liveMessage ??
                'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
            icon: Icons.cloud_off_outlined,
            primaryAction: FilledButton.icon(
              onPressed: () => unawaited(controller.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ),
        );
      case RentRollLivePhase.empty:
        return const NxCard(
          child: NxEmptyState(
            title: 'Noch keine Einheit',
            description:
                'Ein Rent Roll listet die Einheiten eines Objekts. Lege im '
                'Reiter „Einheiten" die erste an.',
            icon: Icons.meeting_room_outlined,
          ),
        );
      case RentRollLivePhase.ready:
        final live = state.live;
        if (live == null) {
          return const SizedBox.shrink();
        }
        return _LiveView(live: live);
    }
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView({required this.live});

  final RentRollLiveDto live;

  @override
  Widget build(BuildContext context) {
    final outsideTerm = live.occupiedOutsideTermLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Aktueller Stand',
                description:
                    'Stichtag ${formatLeaseDate(live.asOfDate)} · jetzt '
                    'gerechnet aus Einheiten und wirksamen Verträgen',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: <Widget>[
                  _Kpi(label: 'Einheiten', value: '${live.unitCount}'),
                  _Kpi(
                    label: 'Vermietet',
                    value: '${live.occupiedUnitCount}',
                  ),
                  _Kpi(label: 'Leer', value: '${live.vacantUnitCount}'),
                  _Kpi(label: 'Offline', value: '${live.offlineUnitCount}'),
                  _Kpi(
                    label: 'Belegungsquote',
                    value: live.occupancyRate == null
                        ? '—'
                        : '${(live.occupancyRate! * 100).toStringAsFixed(1)} %',
                  ),
                  _Kpi(
                    label: 'Wirksame Verträge',
                    value: '${live.effectiveLeaseCount}',
                  ),
                  _Kpi(
                    label: 'Gesamtmiete / Monat',
                    // DEC-011: no cross-currency sum. The server leaves the
                    // total null in that case and names the currencies instead
                    // of returning a number that means nothing.
                    value: live.hasMixedCurrencies
                        ? live.currencies.join(' + ')
                        : formatLeaseMoney(
                            live.totalRentMonthly,
                            live.currencyCode,
                          ),
                  ),
                ],
              ),
              if (live.hasMixedCurrencies) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(
                  title: 'Keine Gesamtsumme möglich',
                  body:
                      'Die wirksamen Verträge sind in '
                      '${live.currencies.join(' und ')} geführt. Beträge '
                      'verschiedener Währungen werden nicht addiert — die '
                      'Zeilen unten zeigen sie einzeln.',
                ),
              ],
              const SizedBox(height: 12),
              _TotalRow(
                label: 'Grundmiete',
                value: live.hasMixedCurrencies
                    ? '—'
                    : formatLeaseMoney(
                        live.totalBaseRentMonthly,
                        live.currencyCode,
                      ),
              ),
              _TotalRow(
                label: 'Nebenkosten',
                value: live.hasMixedCurrencies
                    ? '—'
                    : formatLeaseMoney(
                        live.totalAncillaryChargesMonthly,
                        live.currencyCode,
                      ),
              ),
              _TotalRow(
                label: 'Stellplatz / Sonstiges',
                value: live.hasMixedCurrencies
                    ? '—'
                    : formatLeaseMoney(
                        live.totalParkingOtherChargesMonthly,
                        live.currencyCode,
                      ),
              ),
            ],
          ),
        ),
        if (outsideTerm.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          _OutsideTermNotice(count: outsideTerm.length),
        ],
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Zeilen je Einheit',
                description:
                    '${live.lines.length} Einheiten · Beträge sind Summen '
                    'über die wirksamen Verträge der Einheit',
              ),
              const SizedBox(height: 8),
              NxDataTableShell(
                child: DataTable(
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Einheit')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Verträge')),
                    DataColumn(label: Text('Fläche')),
                    DataColumn(label: Text('Grundmiete')),
                    DataColumn(label: Text('Nebenkosten')),
                    DataColumn(label: Text('Stellplatz')),
                    DataColumn(label: Text('Gesamt')),
                  ],
                  rows: <DataRow>[
                    for (final row in live.lines)
                      DataRow(
                        cells: <DataCell>[
                          DataCell(Text(row.unitCode)),
                          DataCell(UnitStatusBadge(status: row.unitStatus)),
                          DataCell(_LeaseCountCell(row: row)),
                          DataCell(
                            Text(
                              row.areaSqm == null
                                  ? '—'
                                  : '${row.areaSqm!.toStringAsFixed(1)} m²',
                            ),
                          ),
                          DataCell(Text(_money(row, row.baseRentMonthly))),
                          DataCell(
                            Text(_money(row, row.ancillaryChargesMonthly)),
                          ),
                          DataCell(
                            Text(_money(row, row.parkingOtherChargesMonthly)),
                          ),
                          DataCell(Text(_money(row, row.totalRentMonthly))),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row whose leases disagree on currency has no single amount to print, so it
/// names the currencies rather than a sum of unlike things (DEC-011).
String _money(RentRollLiveLineDto row, double value) => row.hasMixedCurrencies
    ? row.currencies.join(' + ')
    : formatLeaseMoney(value, row.currencyCode);

class _LeaseCountCell extends StatelessWidget {
  const _LeaseCountCell({required this.row});

  final RentRollLiveLineDto row;

  @override
  Widget build(BuildContext context) {
    if (!row.isOccupiedButOutsideTerm) {
      return Text('${row.effectiveLeaseCount}');
    }
    return Tooltip(
      message:
          'Vermietet, aber die Vertragslaufzeit deckt den Stichtag nicht ab — '
          'deshalb 0,00.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('${row.effectiveLeaseCount}'),
          const SizedBox(width: 4),
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

/// The frozen half: a history, never a current state.
class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.state,
    required this.onSelect,
    required this.onLoadMore,
  });

  final RentRollState state;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NxSectionHeader(
            title: 'Eingefrorene Snapshots',
            // AGG-007: not unique per date, and that is deliberate.
            description:
                'Neueste zuerst. Mehrere je Stichtag sind zulässig, und keiner '
                'lässt sich ändern oder löschen — eine Korrektur ist ein neuer '
                'Snapshot.',
          ),
          const SizedBox(height: 8),
          switch (state.historyPhase) {
            RentRollHistoryPhase.idle ||
            RentRollHistoryPhase.loading => const LinearProgressIndicator(),
            RentRollHistoryPhase.forbidden => Text(
              'Für Snapshots fehlt die Leseberechtigung.',
              style: theme.textTheme.bodySmall,
            ),
            RentRollHistoryPhase.unsupported => _UnsupportedHistory(
              reason: state.historyMessage,
            ),
            RentRollHistoryPhase.error => Text(
              state.historyMessage ??
                  'Die Snapshot-Historie konnte nicht geladen werden.',
              style: theme.textTheme.bodySmall,
            ),
            RentRollHistoryPhase.empty => Text(
              'Noch kein Snapshot eingefroren. Der aktuelle Stand oben ist '
              'jederzeit sichtbar; ein Snapshot macht ihn zitierfähig.',
              style: theme.textTheme.bodySmall,
            ),
            RentRollHistoryPhase.ready => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final snapshot in state.snapshots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Material(
                      color: snapshot.id == state.selectedSnapshotId
                          ? theme.colorScheme.primary.withValues(alpha: 0.08)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                      child: InkWell(
                        onTap: () => onSelect(snapshot.id),
                        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: <Widget>[
                              Text(
                                'Stichtag ${formatLeaseDate(snapshot.asOfDate)}',
                              ),
                              Text(
                                'Erzeugt ${formatLeaseDate(snapshot.generatedAt)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                formatLeaseMoney(
                                  snapshot.totalRentMonthly,
                                  snapshot.currencyCode,
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (state.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: state.loadingMore ? null : onLoadMore,
                      child: Text(
                        state.loadingMore
                            ? 'Lade …'
                            : 'Ältere Snapshots laden',
                      ),
                    ),
                  ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// Befund 2a, reduced to what it actually is now: the live half works, only the
/// frozen document needs the migration. The adapter's reason is repeated rather
/// than replaced, because it names a real difference between the documents.
class _UnsupportedHistory extends StatelessWidget {
  const _UnsupportedHistory({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Eingefrorene Snapshots gibt es erst nach der Migration. Der lokale '
          'Bestand ist ein anderes Dokument — er wird deshalb nicht als '
          'Snapshot ausgegeben, statt eine leere Historie zu behaupten. Der '
          'aktuelle Stand oben ist davon nicht betroffen.',
        ),
        if (reason != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Begründung des Adapters: $reason',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SnapshotDetail extends StatelessWidget {
  const _SnapshotDetail({required this.state});

  final RentRollState state;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case RentRollDetailPhase.idle:
        return const SizedBox.shrink();
      case RentRollDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case RentRollDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Snapshot nicht gefunden',
            description: 'Dieser Snapshot ist nicht mehr abrufbar.',
            icon: Icons.search_off_outlined,
          ),
        );
      case RentRollDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diesen Snapshot fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case RentRollDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Der Snapshot konnte nicht geladen werden.',
          ),
        );
      case RentRollDetailPhase.ready:
        final snapshot = state.selectedSnapshot;
        if (snapshot == null) {
          return const SizedBox.shrink();
        }
        return _SnapshotView(snapshot: snapshot);
    }
  }
}

class _SnapshotView extends StatelessWidget {
  const _SnapshotView({required this.snapshot});

  final RentRollSnapshotDto snapshot;

  @override
  Widget build(BuildContext context) {
    final outsideTerm = snapshot.occupiedOutsideTermLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title:
                    'Snapshot vom ${formatLeaseDate(snapshot.asOfDate)}',
                description:
                    'Erzeugt am ${formatLeaseDate(snapshot.generatedAt)} · '
                    'eingefroren, nicht bearbeitbar',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: <Widget>[
                  _Kpi(label: 'Einheiten', value: '${snapshot.unitCount}'),
                  _Kpi(
                    label: 'Vermietet',
                    value: '${snapshot.occupiedUnitCount}',
                  ),
                  _Kpi(label: 'Leer', value: '${snapshot.vacantUnitCount}'),
                  _Kpi(label: 'Offline', value: '${snapshot.offlineUnitCount}'),
                  _Kpi(
                    label: 'Belegungsquote',
                    value: snapshot.occupancyRate == null
                        ? '—'
                        : '${(snapshot.occupancyRate! * 100).toStringAsFixed(1)} %',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _TotalRow(
                label: 'Grundmiete',
                value: formatLeaseMoney(
                  snapshot.totalBaseRentMonthly,
                  snapshot.currencyCode,
                ),
              ),
              _TotalRow(
                label: 'Nebenkosten',
                value: formatLeaseMoney(
                  snapshot.totalAncillaryChargesMonthly,
                  snapshot.currencyCode,
                ),
              ),
              _TotalRow(
                label: 'Stellplatz / Sonstiges',
                value: formatLeaseMoney(
                  snapshot.totalParkingOtherChargesMonthly,
                  snapshot.currencyCode,
                ),
              ),
              _TotalRow(
                label: 'Gesamt / Monat',
                value: formatLeaseMoney(
                  snapshot.totalRentMonthly,
                  snapshot.currencyCode,
                ),
              ),
            ],
          ),
        ),
        if (outsideTerm.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          _OutsideTermNotice(count: outsideTerm.length),
        ],
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Eingefrorene Zeilen',
                description:
                    '${snapshot.lines.length} Einheiten · serverseitig '
                    'gerechnet, Summen strukturell an die Zeilen gebunden',
              ),
              const SizedBox(height: 8),
              NxDataTableShell(
                child: DataTable(
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Einheit')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Verträge')),
                    DataColumn(label: Text('Fläche')),
                    DataColumn(label: Text('Grundmiete')),
                    DataColumn(label: Text('Nebenkosten')),
                    DataColumn(label: Text('Stellplatz')),
                    DataColumn(label: Text('Gesamt')),
                  ],
                  rows: <DataRow>[
                    for (final line in snapshot.lines)
                      DataRow(
                        cells: <DataCell>[
                          DataCell(Text(line.unitCode)),
                          DataCell(UnitStatusBadge(status: line.unitStatus)),
                          DataCell(Text('${line.effectiveLeaseCount}')),
                          DataCell(
                            Text(
                              line.areaSqm == null
                                  ? '—'
                                  : '${line.areaSqm!.toStringAsFixed(1)} m²',
                            ),
                          ),
                          DataCell(
                            Text(
                              formatLeaseMoney(
                                line.baseRentMonthly,
                                snapshot.currencyCode,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatLeaseMoney(
                                line.ancillaryChargesMonthly,
                                snapshot.currencyCode,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatLeaseMoney(
                                line.parkingOtherChargesMonthly,
                                snapshot.currencyCode,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatLeaseMoney(
                                line.totalRentMonthly,
                                snapshot.currencyCode,
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
        ),
      ],
    );
  }
}

/// The one figure in this document that looks like a mistake and is not.
class _OutsideTermNotice extends StatelessWidget {
  const _OutsideTermNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      title: count == 1
          ? '1 vermietete Einheit trägt 0,00 bei'
          : '$count vermietete Einheiten tragen 0,00 bei',
      body:
          'Das ist kein Rechenfehler: die Einheit gilt als vermietet, aber die '
          'Laufzeit ihres Vertrags deckt den Stichtag nicht ab. Ein ab Juli '
          'laufender Vertrag trägt zu einem März-Rent-Roll nichts bei.',
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

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
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body),
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

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
