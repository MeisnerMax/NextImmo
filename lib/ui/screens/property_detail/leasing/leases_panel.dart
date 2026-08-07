/// The leases surface of a property, on the P2-D05 contract (Welle 3, AP3).
///
/// Built as the pair of [LeaseDetailView] because list and detail share the
/// status mapping, the form and the transition confirmation — the three things
/// the legacy `leases_screen.dart` (1211 LOC, `BIG-020`) and
/// `lease_detail_screen.dart` (920 LOC) each carried their own copy of.
///
/// Domain rules that are visible here, not merely obeyed:
///
///   * **STM-005 is guided.** Every row leads to a detail whose primary action
///     is the one lawful next step. There is no status dropdown, because six of
///     its seven entries would be refused.
///   * **A unit may hold several concurrent leases (OPN-DOM-001).** The unit
///     filter therefore lists *all* leases of that unit; nothing here speaks of
///     "the" lease of a unit.
///   * **A tenant is a party role (AGG-005).** The tenant filter reads the
///     party directory with `roleType: tenant`; there is no tenants table.
///
/// Deliberately absent: deletion (`OPN-DOM-005` is open, so this domain has no
/// delete path anywhere) and the legacy rent-schedule/indexation actions —
/// `lease_rent_schedule`/`lease_indexation_rules` are explicitly out of Welle 3
/// (`04c`, "Nicht in W3"), and inventing a client-side stand-in for them would
/// be exactly the improvisation that plan forbids.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/leases_controller.dart';
import '../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import 'lease_detail_view.dart';
import 'widgets/lease_form_dialog.dart';
import 'widgets/lease_lifecycle.dart';
import 'widgets/leasing_badges.dart';

class LeasesPanel extends ConsumerStatefulWidget {
  const LeasesPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<LeasesPanel> createState() => _LeasesPanelState();
}

class _LeasesPanelState extends ConsumerState<LeasesPanel> {
  /// Width at which list and detail fit side by side without either becoming
  /// unreadably narrow (same threshold as the units panel).
  static const double _splitViewBreakpoint = 1200;
  static const String _allValues = '__all__';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// The last deep-linked lease this panel acted on. The alerts screen, the
  /// tenant detail, the task list and the app-wide navigation all set
  /// [selectedOperationsLeaseIdProvider] and expect the lease surface to open
  /// on that lease — a behaviour the legacy screen had and this one keeps.
  String? _appliedDeepLink;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = leasesControllerProvider(widget.propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForActionFeedback(provider);
    _applyDeepLink(state, controller);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          searchController: _searchController,
          state: state,
          canMutate: controller.canMutate,
          readOnlyBackend: controller.isReadOnlyBackend,
          onQueryChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          onStatusChanged: controller.setStatusFilter,
          onEffectiveOnlyChanged: controller.setEffectiveOnly,
          onUnitChanged: controller.setUnitFilter,
          onTenantChanged: controller.setTenantFilter,
          onCreate: () => _createLease(controller, state),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    LeasesState state,
    LeasesController controller,
  ) {
    switch (state.listPhase) {
      case LeasesListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Verträge werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case LeasesListPhase.loading:
        return const _LeasesSkeleton();
      case LeasesListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Verträge',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Einheiten und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case LeasesListPhase.error:
        return _ErrorState(
          message: state.message,
          onRetry: () => unawaited(controller.load()),
        );
      case LeasesListPhase.empty:
        // A server-side filter that matches nothing is not "no leases".
        if (state.hasActiveFilter) {
          return _filterEmptyState(controller);
        }
        return NxEmptyState(
          title: 'Noch kein Vertrag',
          description:
              'Lege den ersten Vertrag dieses Objekts an. Er startet als '
              'Entwurf und wird erst durch die Aktivierung wirksam.',
          icon: Icons.description_outlined,
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createLease(controller, state)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Vertrag anlegen'),
          ),
        );
      case LeasesListPhase.ready:
        return _buildReady(context, state, controller);
    }
  }

  /// Opens the lease another screen navigated to. The selection lives in the
  /// controller; the shared provider only carries the intent, so it is applied
  /// once per id rather than fought over on every rebuild.
  void _applyDeepLink(LeasesState state, LeasesController controller) {
    final requested = ref.watch(selectedOperationsLeaseIdProvider);
    if (requested == null ||
        requested == _appliedDeepLink ||
        requested == state.selectedLeaseId) {
      return;
    }
    _appliedDeepLink = requested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(controller.select(requested));
      }
    });
  }

  /// Selecting a row also publishes the intent, so a screen navigated to from
  /// here (and the one navigated back from) sees the same lease.
  void _select(LeasesController controller, String leaseId) {
    _appliedDeepLink = leaseId;
    ref.read(selectedOperationsLeaseIdProvider.notifier).state = leaseId;
    unawaited(controller.select(leaseId));
  }

  Widget _filterEmptyState(LeasesController controller) {
    return NxEmptyState(
      title: 'Kein Vertrag für diesen Filter',
      description:
          'Für Suche und Filter gibt es keinen Treffer. Setze die Filter '
          'zurück, um wieder alle Verträge zu sehen.',
      icon: Icons.filter_alt_off_outlined,
      primaryAction: TextButton(
        onPressed: () {
          _searchController.clear();
          setState(() => _query = '');
          unawaited(controller.clearFilters());
        },
        child: const Text('Filter zurücksetzen'),
      ),
    );
  }

  Widget _buildReady(
    BuildContext context,
    LeasesState state,
    LeasesController controller,
  ) {
    final visible = _filter(state.leases);
    if (visible.isEmpty) {
      return _filterEmptyState(controller);
    }

    final table = _LeasesTable(
      state: state,
      leases: visible,
      onSelect: (id) => _select(controller, id),
      onLoadMore: () => unawaited(controller.loadMore()),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitViewBreakpoint;
        if (!split) {
          return ListView(
            children: <Widget>[
              table,
              if (state.selectedLeaseId != null) ...<Widget>[
                const SizedBox(height: 16),
                _LeaseDetailCard(state: state, controller: controller,
                    onEdit: () => _editLease(controller, state),
                    onAdvance: () => _advanceLease(controller, state),
                    onCancel: () => _cancelLease(controller, state)),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 3, child: SingleChildScrollView(child: table)),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: _LeaseDetailCard(
                  state: state,
                  controller: controller,
                  onEdit: () => _editLease(controller, state),
                  onAdvance: () => _advanceLease(controller, state),
                  onCancel: () => _cancelLease(controller, state),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Text search is client-side over the loaded keyset pages: `LeaseListQuery`
  /// has no text predicate and this wave adds no backend reads (Welle-2
  /// precedent). Status, unit, tenant and "effective only" are server-side and
  /// live in the controller.
  List<LeaseSummaryDto> _filter(List<LeaseSummaryDto> leases) {
    if (_query.isEmpty) {
      return leases;
    }
    final state = ref.read(leasesControllerProvider(widget.propertyId));
    return leases
        .where(
          (lease) =>
              lease.leaseName.toLowerCase().contains(_query) ||
              (state.unitCodeFor(lease.unitId)?.toLowerCase().contains(_query) ??
                  false) ||
              (state
                      .tenantNameFor(lease.tenantPartyId)
                      ?.toLowerCase()
                      .contains(_query) ??
                  false),
        )
        .toList(growable: false);
  }

  void _listenForActionFeedback(
    AutoDisposeStateNotifierProvider<LeasesController, LeasesState> provider,
  ) {
    ref.listen<LeasesState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(provider.notifier);
      switch (next.actionPhase) {
        case LeasesActionPhase.conflict:
          final conflict = next.versionConflict;
          if (conflict == null) {
            return;
          }
          unawaited(
            _showVersionConflictDialog(
              conflict.currentLease,
              onReload: () {
                controller.clearAction();
                unawaited(controller.load());
                final selectedId = next.selectedLeaseId;
                if (selectedId != null) {
                  unawaited(controller.select(selectedId));
                }
              },
            ),
          );
        case LeasesActionPhase.notAllowed:
          // Deliberately not a snackbar: a refused step is rendered inline by
          // the detail view, which can name what STM-005 does allow. Only a
          // rejection-free refusal (a binding lease) carries a message.
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
        case LeasesActionPhase.succeeded:
        case LeasesActionPhase.readOnly:
        case LeasesActionPhase.forbidden:
        case LeasesActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case LeasesActionPhase.idle:
        case LeasesActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _showVersionConflictDialog(
    LeaseDto? current, {
    required VoidCallback onReload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vertrag wurde zwischenzeitlich geändert'),
        content: Text(
          current == null
              ? 'Jemand anderes hat diesen Vertrag bearbeitet, während du ihn '
                    'offen hattest. Lade ihn neu und wiederhole die Änderung.'
              : 'Jemand anderes hat "${current.leaseName}" bearbeitet, während '
                    'du ihn offen hattest (jetzt Version ${current.version}, '
                    'Status ${leaseStatusLabel(current.status)}). Deine '
                    'Änderung wurde nicht gespeichert.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onReload();
            },
            child: const Text('Neu laden'),
          ),
        ],
      ),
    );
  }

  Future<void> _createLease(
    LeasesController controller,
    LeasesState state,
  ) async {
    if (state.units.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Ein Vertrag braucht eine Einheit. Lege zuerst im Reiter '
            '„Einheiten" eine an.',
          ),
        ),
      );
      return;
    }
    final result = await showLeaseFormDialog(
      context,
      units: state.units,
      tenants: state.tenants,
      initialUnitId: state.unitFilter,
    );
    if (result == null) {
      return;
    }
    await controller.createLease(
      LeaseDraft(
        unitId: result.unitId,
        leaseName: result.leaseName,
        startDate: result.startDate,
        baseRentMonthly: result.baseRentMonthly,
        currencyCode: result.currencyCode,
        tenantPartyId: result.tenantPartyId,
        endDate: result.endDate,
        moveInDate: result.moveInDate,
        signedDate: result.signedDate,
        ancillaryChargesMonthly: result.ancillaryChargesMonthly,
        parkingOtherChargesMonthly: result.parkingOtherChargesMonthly,
        securityDeposit: result.securityDeposit,
        paymentDayOfMonth: result.paymentDayOfMonth,
        billingFrequency: result.billingFrequency,
        rentFreePeriodMonths: result.rentFreePeriodMonths,
        notes: result.notes,
      ),
    );
  }

  Future<void> _editLease(
    LeasesController controller,
    LeasesState state,
  ) async {
    final lease = state.selectedLease;
    if (lease == null) {
      return;
    }
    final result = await showLeaseFormDialog(
      context,
      units: state.units,
      tenants: state.tenants,
      existing: lease,
    );
    if (result == null) {
      return;
    }
    await controller.updateLease(
      lease: lease,
      changes: LeaseUpdateDto(
        leaseName: result.leaseName,
        startDate: result.startDate,
        baseRentMonthly: result.baseRentMonthly,
        billingFrequency: result.billingFrequency,
        tenantPartyId: result.tenantPartyId,
        endDate: result.endDate,
        moveInDate: result.moveInDate,
        signedDate: result.signedDate,
        noticeDate: result.noticeDate,
        renewalOptionDate: result.renewalOptionDate,
        breakOptionDate: result.breakOptionDate,
        ancillaryChargesMonthly: result.ancillaryChargesMonthly,
        parkingOtherChargesMonthly: result.parkingOtherChargesMonthly,
        securityDeposit: result.securityDeposit,
        paymentDayOfMonth: result.paymentDayOfMonth,
        rentFreePeriodMonths: result.rentFreePeriodMonths,
        notes: result.notes,
      ),
    );
  }

  Future<void> _advanceLease(
    LeasesController controller,
    LeasesState state,
  ) async {
    final lease = state.selectedLease;
    if (lease == null) {
      return;
    }
    final request = await showLeaseAdvanceDialog(context, lease: lease);
    if (request == null) {
      return;
    }
    await controller.advanceLease(
      lease: lease,
      moveOutDate: request.moveOutDate,
    );
  }

  Future<void> _cancelLease(
    LeasesController controller,
    LeasesState state,
  ) async {
    final lease = state.selectedLease;
    if (lease == null) {
      return;
    }
    final reason = await showLeaseCancellationDialog(context, lease: lease);
    if (reason == null) {
      return;
    }
    await controller.cancelLease(lease: lease, reason: reason);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.state,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onEffectiveOnlyChanged,
    required this.onUnitChanged,
    required this.onTenantChanged,
    required this.onCreate,
  });

  final TextEditingController searchController;
  final LeasesState state;
  final bool canMutate;
  final bool readOnlyBackend;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<LeaseStatus?> onStatusChanged;
  final ValueChanged<bool> onEffectiveOnlyChanged;
  final ValueChanged<String?> onUnitChanged;
  final ValueChanged<String?> onTenantChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final mobile = context.viewport == AppViewport.mobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (readOnlyBackend)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _ReadOnlyNotice(),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: mobile ? 180 : 240,
              child: TextField(
                controller: searchController,
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  labelText: 'Verträge durchsuchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              width: mobile ? 180 : 210,
              child: DropdownButtonFormField<String>(
                value: state.statusFilter?.name ??
                    _LeasesPanelState._allValues,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _LeasesPanelState._allValues,
                    child: Text('Alle Status'),
                  ),
                  for (final status in LeaseStatus.values)
                    DropdownMenuItem<String>(
                      value: status.name,
                      child: Text(leaseStatusLabel(status)),
                    ),
                ],
                onChanged: (value) => onStatusChanged(
                  value == null || value == _LeasesPanelState._allValues
                      ? null
                      : LeaseStatus.values.byName(value),
                ),
              ),
            ),
            SizedBox(
              width: mobile ? 180 : 200,
              child: DropdownButtonFormField<String>(
                value: state.unitFilter ?? _LeasesPanelState._allValues,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Einheit'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _LeasesPanelState._allValues,
                    child: Text('Alle Einheiten'),
                  ),
                  for (final unit in state.units)
                    DropdownMenuItem<String>(
                      value: unit.id,
                      child: Text(unit.unitCode),
                    ),
                ],
                onChanged: (value) => onUnitChanged(
                  value == _LeasesPanelState._allValues ? null : value,
                ),
              ),
            ),
            SizedBox(
              width: mobile ? 180 : 220,
              child: DropdownButtonFormField<String>(
                value: state.tenantFilter ?? _LeasesPanelState._allValues,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mieter'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _LeasesPanelState._allValues,
                    child: Text('Alle Mieter'),
                  ),
                  for (final party in state.tenants)
                    DropdownMenuItem<String>(
                      value: party.id,
                      child: Text(party.displayName),
                    ),
                ],
                onChanged: (value) => onTenantChanged(
                  value == _LeasesPanelState._allValues ? null : value,
                ),
              ),
            ),
            // "Effective" is a status question, not a date one — the tooltip
            // says so, because the difference decides whether a lease counts
            // for occupancy and the rent roll.
            Tooltip(
              message: 'Wirksam heißt: Status aktiv. Das ist etwas anderes als '
                  '„Laufzeit deckt heute ab".',
              child: FilterChip(
                label: const Text('Nur wirksame'),
                selected: state.effectiveOnly,
                onSelected: onEffectiveOnlyChanged,
              ),
            ),
            FilledButton.icon(
              onPressed: canMutate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: const Text('Vertrag anlegen'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The mandatory "read-only until migrated" state. It explains *why* rather
/// than leaving disabled buttons unexplained.
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NxCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_clock_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Die lokale Datenbank ist für Verträge schreibgeschützt, bis '
              'diese Domäne migriert ist. Lesen funktioniert vollständig; '
              'Anlegen, Bearbeiten und Statuswechsel sind erst im '
              'Cloud-Betrieb verfügbar.',
            ),
          ),
        ],
      ),
    );
  }
}

class _LeasesTable extends StatelessWidget {
  const _LeasesTable({
    required this.state,
    required this.leases,
    required this.onSelect,
    required this.onLoadMore,
  });

  final LeasesState state;
  final List<LeaseSummaryDto> leases;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxDataTableShell(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const <DataColumn>[
              DataColumn(label: Text('Vertrag')),
              DataColumn(label: Text('Einheit')),
              DataColumn(label: Text('Mieter')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Beginn')),
              DataColumn(label: Text('Ende')),
              DataColumn(label: Text('Grundmiete')),
            ],
            rows: <DataRow>[
              for (final lease in leases)
                DataRow(
                  selected: lease.id == state.selectedLeaseId,
                  onSelectChanged: (_) => onSelect(lease.id),
                  cells: <DataCell>[
                    DataCell(Text(lease.leaseName)),
                    DataCell(
                      Text(state.unitCodeFor(lease.unitId) ?? '—'),
                    ),
                    DataCell(Text(_tenantLabel(lease))),
                    DataCell(LeaseStatusBadge(status: lease.status)),
                    DataCell(Text(formatLeaseDate(lease.startDate))),
                    DataCell(
                      Text(
                        lease.endDate == null
                            ? 'Unbefristet'
                            : formatLeaseDate(lease.endDate),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatLeaseMoney(
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
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: state.loadingMore ? null : onLoadMore,
                child: Text(
                  state.loadingMore ? 'Lade …' : 'Weitere Verträge laden',
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _tenantLabel(LeaseSummaryDto lease) {
    if (lease.tenantPartyId == null) {
      return 'Noch nicht benannt';
    }
    return state.tenantNameFor(lease.tenantPartyId) ?? '—';
  }
}

class _LeaseDetailCard extends StatelessWidget {
  const _LeaseDetailCard({
    required this.state,
    required this.controller,
    required this.onEdit,
    required this.onAdvance,
    required this.onCancel,
  });

  final LeasesState state;
  final LeasesController controller;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case LeasesDetailPhase.idle:
        return const NxCard(
          child: Text('Wähle einen Vertrag, um seine Details zu sehen.'),
        );
      case LeasesDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case LeasesDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Vertrag nicht gefunden',
            description:
                'Dieser Vertrag existiert nicht mehr. Vermutlich wurde er '
                'entfernt, während die Liste offen war.',
            icon: Icons.search_off_outlined,
          ),
        );
      case LeasesDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diesen Vertrag fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case LeasesDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Der Vertrag konnte nicht geladen werden.',
          ),
        );
      case LeasesDetailPhase.ready:
        final lease = state.selectedLease;
        if (lease == null) {
          return const SizedBox.shrink();
        }
        return LeaseDetailView(
          lease: lease,
          unitCode: state.unitCodeFor(lease.unitId),
          tenantName: state.tenantNameFor(lease.tenantPartyId),
          canMutate: controller.canMutate,
          rejection: state.actionPhase == LeasesActionPhase.notAllowed
              ? state.rejection
              : null,
          onEdit: onEdit,
          onAdvance: onAdvance,
          onCancel: onCancel,
        );
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: 'Verträge konnten nicht geladen werden',
      description:
          message ??
          'Die Verbindung zur Datenquelle ist fehlgeschlagen. Versuche es '
              'erneut.',
      icon: Icons.cloud_off_outlined,
      primaryAction: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut versuchen'),
      ),
    );
  }
}

class _LeasesSkeleton extends StatelessWidget {
  const _LeasesSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 6; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 44,
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
