/// The units surface of a property, on the P2-D05 contract (Welle 3, AP1).
///
/// Pattern proof for the wave, mirroring the Welle-2 `PartiesScreen`: the panel
/// reads only the backend-selected feature providers, all orchestration lives in
/// [UnitsController], and every mandatory state of `03_design_system.md` is a
/// phase in the state rather than an ad hoc widget branch.
///
/// Two domain rules are visible in the UI on purpose:
///
///   * **Occupancy is derived (AGG-004).** There is no "mark as occupied"
///     control, because the server refuses it. The panel says where the status
///     comes from instead of offering an edit that cannot work.
///   * **A unit may hold several concurrent leases (OPN-DOM-001).** Nothing here
///     says "the lease of this unit"; the lease list per unit belongs to AP2 and
///     is a list, never a single value.
///
/// Deliberately absent: the legacy "archivieren" action. `archived` is the local
/// soft-delete and has no `UnitStatus` counterpart — and with `OPN-DOM-005` open
/// there is no delete path anywhere in this domain.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/units_controller.dart';
import '../../../../features/leasing_operations/domain/unit_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import 'unit_detail_view.dart';
import 'widgets/leasing_badges.dart';

class UnitsPanel extends ConsumerStatefulWidget {
  const UnitsPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<UnitsPanel> createState() => _UnitsPanelState();
}

class _UnitsPanelState extends ConsumerState<UnitsPanel> {
  /// Width at which list and detail fit side by side without either becoming
  /// unreadably narrow (same threshold as the Welle-2 parties screen).
  static const double _splitViewBreakpoint = 1200;
  static const String _allStatuses = '__all__';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// The last deep-linked unit this panel acted on. Other screens navigate to a
  /// unit by setting [selectedOperationsUnitIdProvider]; the legacy screen
  /// honoured that and so does this one (caught up with AP3).
  String? _appliedDeepLink;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = unitsControllerProvider(widget.propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForActionFeedback(provider);
    _applyDeepLink(state, controller);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          searchController: _searchController,
          statusFilter: state.statusFilter,
          canMutate: controller.canMutate,
          readOnlyBackend: controller.isReadOnlyBackend,
          onQueryChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          onStatusChanged: controller.setStatusFilter,
          onCreate: () => _createUnit(controller),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    UnitsState state,
    UnitsController controller,
  ) {
    switch (state.listPhase) {
      case UnitsListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Einheiten werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case UnitsListPhase.loading:
        return const _UnitsSkeleton();
      case UnitsListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Einheiten',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Einheiten und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case UnitsListPhase.error:
        return _ErrorState(
          message: state.message,
          onRetry: () => unawaited(controller.load()),
        );
      case UnitsListPhase.empty:
        return NxEmptyState(
          title: 'Noch keine Einheit',
          description:
              'Lege die erste Einheit dieses Objekts an, um Verträge, Belegung '
              'und Rent Roll darauf aufzubauen.',
          icon: Icons.meeting_room_outlined,
          primaryAction: FilledButton.icon(
            onPressed:
                controller.canMutate ? () => _createUnit(controller) : null,
            icon: const Icon(Icons.add),
            label: const Text('Einheit anlegen'),
          ),
        );
      case UnitsListPhase.ready:
        return _buildReady(context, state, controller);
    }
  }

  /// Opens the unit another screen navigated to. The selection lives in the
  /// controller; the shared provider only carries the intent, so it is applied
  /// once per id rather than fought over on every rebuild.
  void _applyDeepLink(UnitsState state, UnitsController controller) {
    final requested = ref.watch(selectedOperationsUnitIdProvider);
    if (requested == null ||
        requested == _appliedDeepLink ||
        requested == state.selectedUnitId) {
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
  /// here (and the one navigated back from) sees the same unit.
  void _select(UnitsController controller, String unitId) {
    _appliedDeepLink = unitId;
    ref.read(selectedOperationsUnitIdProvider.notifier).state = unitId;
    unawaited(controller.select(unitId));
  }

  Widget _buildReady(
    BuildContext context,
    UnitsState state,
    UnitsController controller,
  ) {
    final visible = _filter(state.units);
    if (visible.isEmpty) {
      // A filter that matches nothing is its own state, not "no units".
      return NxEmptyState(
        title: 'Keine Einheit für diesen Filter',
        description:
            'Für Suche und Statusfilter gibt es keinen Treffer. Setze den '
            'Filter zurück, um wieder alle Einheiten zu sehen.',
        icon: Icons.filter_alt_off_outlined,
        primaryAction: TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _query = '');
            unawaited(controller.setStatusFilter(null));
          },
          child: const Text('Filter zurücksetzen'),
        ),
      );
    }

    final table = _UnitsTable(
      units: visible,
      selectedUnitId: state.selectedUnitId,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
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
              if (state.selectedUnitId != null) ...<Widget>[
                const SizedBox(height: 16),
                _UnitDetailCard(
                  state: state,
                  controller: controller,
                  onTakeOffline: () => _takeOffline(controller, state),
                  onReturnOnline: () => _returnOnline(controller, state),
                  onEdit: () => _editUnit(controller, state),
                ),
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
                child: _UnitDetailCard(
                  state: state,
                  controller: controller,
                  onTakeOffline: () => _takeOffline(controller, state),
                  onReturnOnline: () => _returnOnline(controller, state),
                  onEdit: () => _editUnit(controller, state),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Text search is client-side over the loaded keyset pages: `UnitListQuery`
  /// has no text predicate and this wave adds no backend reads (Welle-2
  /// precedent). The status filter is server-side and lives in the controller.
  List<UnitSummaryDto> _filter(List<UnitSummaryDto> units) {
    if (_query.isEmpty) {
      return units;
    }
    return units
        .where(
          (unit) =>
              unit.unitCode.toLowerCase().contains(_query) ||
              (unit.unitType?.toLowerCase().contains(_query) ?? false) ||
              (unit.floor?.toLowerCase().contains(_query) ?? false),
        )
        .toList(growable: false);
  }

  void _listenForActionFeedback(
    AutoDisposeStateNotifierProvider<UnitsController, UnitsState> provider,
  ) {
    ref.listen<UnitsState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(provider.notifier);
      switch (next.actionPhase) {
        case UnitsActionPhase.conflict:
          final conflict = next.versionConflict;
          if (conflict == null) {
            return;
          }
          unawaited(
            _showVersionConflictDialog(
              conflict.currentUnit,
              onReload: () {
                controller.clearAction();
                unawaited(controller.load());
                final selectedId = next.selectedUnitId;
                if (selectedId != null) {
                  unawaited(controller.select(selectedId));
                }
              },
            ),
          );
        case UnitsActionPhase.succeeded:
        case UnitsActionPhase.readOnly:
        case UnitsActionPhase.forbidden:
        case UnitsActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case UnitsActionPhase.idle:
        case UnitsActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _showVersionConflictDialog(
    UnitDto? current, {
    required VoidCallback onReload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Einheit wurde zwischenzeitlich geändert'),
        content: Text(
          current == null
              ? 'Jemand anderes hat diese Einheit bearbeitet, während du sie '
                    'offen hattest. Lade sie neu und wiederhole die Änderung.'
              : 'Jemand anderes hat "${current.unitCode}" bearbeitet, während '
                    'du sie offen hattest (jetzt Version ${current.version}, '
                    'Status ${unitStatusLabel(current.status)}). Deine Änderung '
                    'wurde nicht gespeichert.',
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

  Future<void> _createUnit(UnitsController controller) async {
    final draft = await _showUnitDialog();
    if (draft == null) {
      return;
    }
    await controller.createUnit(
      UnitDraft(
        propertyId: widget.propertyId,
        unitCode: draft.unitCode,
        unitType: draft.unitType,
        floor: draft.floor,
        areaSqm: draft.areaSqm,
        rooms: draft.rooms,
        bathrooms: draft.bathrooms,
        targetRentMonthly: draft.targetRentMonthly,
        currencyCode: draft.currencyCode,
        notes: draft.notes,
      ),
    );
  }

  Future<void> _editUnit(UnitsController controller, UnitsState state) async {
    final unit = state.selectedUnit;
    if (unit == null) {
      return;
    }
    final draft = await _showUnitDialog(existing: unit);
    if (draft == null) {
      return;
    }
    await controller.updateUnit(
      unitId: unit.id,
      expectedVersion: unit.version,
      changes: UnitUpdateDto(
        unitCode: draft.unitCode,
        unitType: draft.unitType,
        floor: draft.floor,
        areaSqm: draft.areaSqm,
        rooms: draft.rooms,
        bathrooms: draft.bathrooms,
        targetRentMonthly: draft.targetRentMonthly,
        marketRentMonthly: unit.marketRentMonthly,
        currencyCode: draft.currencyCode,
        vacancyReason: unit.vacancyReason,
        marketingStatus: unit.marketingStatus,
        renovationStatus: unit.renovationStatus,
        expectedReadyDate: unit.expectedReadyDate,
        nextAction: unit.nextAction,
        notes: draft.notes,
      ),
    );
  }

  Future<void> _takeOffline(
    UnitsController controller,
    UnitsState state,
  ) async {
    final unit = state.selectedUnit;
    if (unit == null) {
      return;
    }
    final reason = await _showOfflineReasonDialog(unit);
    if (reason == null) {
      return;
    }
    await controller.takeOffline(
      unitId: unit.id,
      expectedVersion: unit.version,
      reason: reason,
    );
  }

  Future<void> _returnOnline(
    UnitsController controller,
    UnitsState state,
  ) async {
    final unit = state.selectedUnit;
    if (unit == null) {
      return;
    }
    await controller.returnFromOffline(
      unitId: unit.id,
      expectedVersion: unit.version,
    );
  }

  /// The reason is mandatory and the dialog says what it becomes: the unit's
  /// offline reason *and* the audit reason. One value, one fact — the contract
  /// deliberately has no second field.
  Future<String?> _showOfflineReasonDialog(UnitDto unit) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${unit.unitCode} offline nehmen'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Der Grund wird als Offline-Grund der Einheit gespeichert und '
                'im Änderungsprotokoll festgehalten.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Grund',
                  hintText: 'z. B. Wasserschaden, Sanierung',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Bitte einen Grund angeben.'
                        : null,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Offline nehmen'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<_UnitFormResult?> _showUnitDialog({UnitDto? existing}) async {
    final codeController = TextEditingController(text: existing?.unitCode ?? '');
    final typeController = TextEditingController(text: existing?.unitType ?? '');
    final floorController = TextEditingController(text: existing?.floor ?? '');
    final areaController = TextEditingController(
      text: existing?.areaSqm?.toString() ?? '',
    );
    final roomsController = TextEditingController(
      text: existing?.rooms?.toString() ?? '',
    );
    final bathsController = TextEditingController(
      text: existing?.bathrooms?.toString() ?? '',
    );
    final rentController = TextEditingController(
      text: existing?.targetRentMonthly?.toString() ?? '',
    );
    final currencyController = TextEditingController(
      text: existing?.currencyCode ?? '',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<_UnitFormResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Einheit anlegen' : 'Einheit bearbeiten'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: codeController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Einheitscode *',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Pflichtfeld.'
                            : null,
                  ),
                  TextFormField(
                    controller: typeController,
                    decoration: const InputDecoration(labelText: 'Typ'),
                  ),
                  TextFormField(
                    controller: floorController,
                    decoration: const InputDecoration(labelText: 'Etage'),
                  ),
                  TextFormField(
                    controller: areaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Fläche (m²)'),
                  ),
                  TextFormField(
                    controller: roomsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Zimmer'),
                  ),
                  TextFormField(
                    controller: bathsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Bäder'),
                  ),
                  TextFormField(
                    controller: rentController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Zielmiete / Monat',
                    ),
                  ),
                  TextFormField(
                    controller: currencyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Währung (z. B. EUR)',
                      helperText: 'Pflicht, sobald ein Mietbetrag gesetzt ist.',
                    ),
                    validator: (value) {
                      // DEC-011: an amount never exists without its currency —
                      // the server rejects the row otherwise.
                      final hasAmount = rentController.text.trim().isNotEmpty;
                      final hasCurrency = (value ?? '').trim().isNotEmpty;
                      if (hasAmount && !hasCurrency) {
                        return 'Zu einem Betrag gehört eine Währung.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notizen'),
                  ),
                ],
              ),
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
              Navigator.of(dialogContext).pop(
                _UnitFormResult(
                  unitCode: codeController.text.trim(),
                  unitType: _trimToNull(typeController.text),
                  floor: _trimToNull(floorController.text),
                  areaSqm: _parseDouble(areaController.text),
                  rooms: _parseDouble(roomsController.text),
                  bathrooms: _parseDouble(bathsController.text),
                  targetRentMonthly: _parseDouble(rentController.text),
                  currencyCode: _trimToNull(
                    currencyController.text.toUpperCase(),
                  ),
                  notes: _trimToNull(notesController.text),
                ),
              );
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    for (final controller in <TextEditingController>[
      codeController,
      typeController,
      floorController,
      areaController,
      roomsController,
      bathsController,
      rentController,
      currencyController,
      notesController,
    ]) {
      controller.dispose();
    }
    return result;
  }

  static String? _trimToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _parseDouble(String value) {
    final trimmed = value.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }
}

class _UnitFormResult {
  const _UnitFormResult({
    required this.unitCode,
    this.unitType,
    this.floor,
    this.areaSqm,
    this.rooms,
    this.bathrooms,
    this.targetRentMonthly,
    this.currencyCode,
    this.notes,
  });

  final String unitCode;
  final String? unitType;
  final String? floor;
  final double? areaSqm;
  final double? rooms;
  final double? bathrooms;
  final double? targetRentMonthly;
  final String? currencyCode;
  final String? notes;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.statusFilter,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onCreate,
  });

  final TextEditingController searchController;
  final UnitStatus? statusFilter;
  final bool canMutate;
  final bool readOnlyBackend;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UnitStatus?> onStatusChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final mobile = context.viewport == AppViewport.mobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (readOnlyBackend)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ReadOnlyNotice(),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: mobile ? 180 : 260,
              child: TextField(
                controller: searchController,
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  labelText: 'Einheiten durchsuchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              width: mobile ? 180 : 220,
              child: DropdownButtonFormField<String>(
                value: statusFilter?.name ?? _UnitsPanelState._allStatuses,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _UnitsPanelState._allStatuses,
                    child: Text('Alle Status'),
                  ),
                  for (final status in UnitStatus.values)
                    DropdownMenuItem<String>(
                      value: status.name,
                      child: Text(unitStatusLabel(status)),
                    ),
                ],
                onChanged: (value) => onStatusChanged(
                  value == null || value == _UnitsPanelState._allStatuses
                      ? null
                      : UnitStatus.values.byName(value),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: canMutate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: const Text('Einheit anlegen'),
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
              'Die lokale Datenbank ist für Einheiten schreibgeschützt, bis '
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

class _UnitsTable extends StatelessWidget {
  const _UnitsTable({
    required this.units,
    required this.selectedUnitId,
    required this.hasMore,
    required this.loadingMore,
    required this.onSelect,
    required this.onLoadMore,
  });

  final List<UnitSummaryDto> units;
  final String? selectedUnitId;
  final bool hasMore;
  final bool loadingMore;
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
              DataColumn(label: Text('Einheit')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Typ')),
              DataColumn(label: Text('Etage')),
              DataColumn(label: Text('Fläche')),
              DataColumn(label: Text('Zimmer')),
              DataColumn(label: Text('Leer seit')),
            ],
            rows: <DataRow>[
              for (final unit in units)
                DataRow(
                  selected: unit.id == selectedUnitId,
                  onSelectChanged: (_) => onSelect(unit.id),
                  cells: <DataCell>[
                    DataCell(Text(unit.unitCode)),
                    DataCell(UnitStatusBadge(status: unit.status)),
                    DataCell(Text(unit.unitType ?? '—')),
                    DataCell(Text(unit.floor ?? '—')),
                    DataCell(
                      Text(
                        unit.areaSqm == null
                            ? '—'
                            : '${unit.areaSqm!.toStringAsFixed(1)} m²',
                      ),
                    ),
                    DataCell(Text(unit.rooms?.toStringAsFixed(1) ?? '—')),
                    DataCell(Text(_formatDate(unit.vacancySince))),
                  ],
                ),
            ],
          ),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: loadingMore ? null : onLoadMore,
                child: Text(
                  loadingMore ? 'Lade …' : 'Weitere Einheiten laden',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UnitDetailCard extends StatelessWidget {
  const _UnitDetailCard({
    required this.state,
    required this.controller,
    required this.onTakeOffline,
    required this.onReturnOnline,
    required this.onEdit,
  });

  final UnitsState state;
  final UnitsController controller;
  final VoidCallback onTakeOffline;
  final VoidCallback onReturnOnline;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case UnitsDetailPhase.idle:
        return const NxCard(
          child: Text('Wähle eine Einheit, um ihre Details zu sehen.'),
        );
      case UnitsDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case UnitsDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Einheit nicht gefunden',
            description:
                'Diese Einheit existiert nicht mehr. Vermutlich wurde sie '
                'entfernt, während die Liste offen war.',
            icon: Icons.search_off_outlined,
          ),
        );
      case UnitsDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diese Einheit fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case UnitsDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Die Einheit konnte nicht geladen werden.',
          ),
        );
      case UnitsDetailPhase.ready:
        final unit = state.selectedUnit;
        if (unit == null) {
          return const SizedBox.shrink();
        }
        // AP2: the full detail, including every lease of this unit.
        return UnitDetailView(
          unit: unit,
          leases: state.selectedUnitLeases,
          canMutate: controller.canMutate,
          onEdit: onEdit,
          onTakeOffline: onTakeOffline,
          onReturnOnline: onReturnOnline,
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
      title: 'Einheiten konnten nicht geladen werden',
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

class _UnitsSkeleton extends StatelessWidget {
  const _UnitsSkeleton();

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

String _formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
