/// The leasing pipeline of a property, on the P2-D05 contract (Welle 3, AP4).
///
/// This surface has **no legacy predecessor to migrate**: today's tab keeps a
/// prospect's stage in `tenants.move_in_reference`, a four-value string on a
/// tenant record, with no case aggregate, no audit, no preconditions and a
/// backward arrow. STM-004 replaces that with ten audited stages, one forward
/// edge, and an abort that must say why (`FTR-024`).
///
/// Two shape decisions worth stating:
///
///   * **Ten stages do not fit side by side.** The board scrolls horizontally
///     with fixed-width columns rather than squeezing ten columns into the
///     viewport — the responsive rule is to scroll the region, not to break the
///     content. Below the board breakpoint it becomes a stacked list with a
///     stage filter.
///   * **The board shows open cases.** Terminal stages are the archive, not the
///     pipeline; switching the filter off adds them back with their own
///     columns.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/leasing_cases_controller.dart';
import '../../../../features/leasing_operations/domain/leasing_case_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../theme/app_theme.dart';
import 'leasing_case_detail_view.dart';
import 'widgets/leasing_badges.dart';
import 'widgets/leasing_case_dialogs.dart';

class LeasingPipelinePanel extends ConsumerStatefulWidget {
  const LeasingPipelinePanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<LeasingPipelinePanel> createState() =>
      _LeasingPipelinePanelState();
}

class _LeasingPipelinePanelState extends ConsumerState<LeasingPipelinePanel> {
  /// Below this the board becomes a stacked list: two 280 px columns plus the
  /// detail panel is the narrowest arrangement that still reads as a board.
  static const double _boardBreakpoint = 900;
  static const double _columnWidth = 280;
  static const String _allStages = '__all__';

  @override
  Widget build(BuildContext context) {
    final provider = leasingCasesControllerProvider(widget.propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForActionFeedback(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          state: state,
          canMutate: controller.canMutate,
          readOnlyBackend: controller.isReadOnlyBackend,
          onStageChanged: controller.setStageFilter,
          onOpenOnlyChanged: controller.setOpenOnly,
          onCreate: () => _createCase(controller, state),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    LeasingCasesState state,
    LeasingCasesController controller,
  ) {
    switch (state.listPhase) {
      case LeasingCasesListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Vermietungsfälle werden je Arbeitsbereich geführt. Melde dich '
              'an oder wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case LeasingCasesListPhase.loading:
        return const _PipelineSkeleton();
      case LeasingCasesListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf die Pipeline',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Einheiten und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case LeasingCasesListPhase.error:
        return _ErrorState(
          message: state.message,
          onRetry: () => unawaited(controller.load()),
        );
      case LeasingCasesListPhase.empty:
        if (state.hasActiveFilter) {
          return NxEmptyState(
            title: 'Kein Fall für diesen Filter',
            description:
                'Für die gewählte Stufe gibt es keinen Treffer. Setze den '
                'Filter zurück, um wieder alle offenen Fälle zu sehen.',
            icon: Icons.filter_alt_off_outlined,
            primaryAction: TextButton(
              onPressed: () => unawaited(controller.clearFilters()),
              child: const Text('Filter zurücksetzen'),
            ),
          );
        }
        return NxEmptyState(
          title: 'Noch kein Vermietungsfall',
          description:
              'Lege die erste Anfrage an. Sie durchläuft zehn Stufen bis zur '
              'Übergabe — jede Stufe wird protokolliert, und ein Rückschritt '
              'ist nicht vorgesehen.',
          icon: Icons.filter_alt_outlined,
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createCase(controller, state)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Fall anlegen'),
          ),
        );
      case LeasingCasesListPhase.ready:
        return _buildReady(context, state, controller);
    }
  }

  Widget _buildReady(
    BuildContext context,
    LeasingCasesState state,
    LeasingCasesController controller,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final board = constraints.maxWidth >= _boardBreakpoint;
        final detail = _CaseDetailCard(
          state: state,
          controller: controller,
          onEdit: () => _editCase(controller, state),
          onAdvance: () => _advanceCase(controller, state),
          onCancel: () => _cancelCase(controller, state),
        );
        if (!board) {
          return ListView(
            children: <Widget>[
              _StackedCaseList(
                state: state,
                onSelect: (id) => unawaited(controller.select(id)),
              ),
              if (state.selectedCaseId != null) ...<Widget>[
                const SizedBox(height: 16),
                detail,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: _PipelineBoard(
                state: state,
                columnWidth: _columnWidth,
                onSelect: (id) => unawaited(controller.select(id)),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: SingleChildScrollView(child: detail),
            ),
          ],
        );
      },
    );
  }

  void _listenForActionFeedback(
    AutoDisposeStateNotifierProvider<LeasingCasesController, LeasingCasesState>
    provider,
  ) {
    ref.listen<LeasingCasesState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(provider.notifier);
      switch (next.actionPhase) {
        case LeasingCasesActionPhase.conflict:
          final conflict = next.versionConflict;
          if (conflict == null) {
            return;
          }
          unawaited(
            _showVersionConflictDialog(
              conflict.currentCase,
              onReload: () {
                controller.clearAction();
                unawaited(controller.load());
                final selectedId = next.selectedCaseId;
                if (selectedId != null) {
                  unawaited(controller.select(selectedId));
                }
              },
            ),
          );
        case LeasingCasesActionPhase.blocked:
          // Rendered inline by the detail view, which can name the missing
          // precondition. Only a reason-free block carries a message.
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
        case LeasingCasesActionPhase.succeeded:
        case LeasingCasesActionPhase.readOnly:
        case LeasingCasesActionPhase.forbidden:
        case LeasingCasesActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case LeasingCasesActionPhase.idle:
        case LeasingCasesActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _showVersionConflictDialog(
    LeasingCaseDto? current, {
    required VoidCallback onReload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fall wurde zwischenzeitlich geändert'),
        content: Text(
          current == null
              ? 'Jemand anderes hat diesen Fall bearbeitet, während du ihn '
                    'offen hattest. Lade ihn neu und wiederhole die Änderung.'
              : 'Jemand anderes hat "${current.caseName}" bearbeitet, während '
                    'du ihn offen hattest (jetzt Version ${current.version}, '
                    'Stufe ${leasingCaseStatusLabel(current.status)}). Deine '
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

  Future<void> _createCase(
    LeasingCasesController controller,
    LeasingCasesState state,
  ) async {
    final result = await showLeasingCaseFormDialog(
      context,
      units: state.units,
      parties: state.parties,
    );
    if (result == null) {
      return;
    }
    await controller.createCase(
      LeasingCaseDraft(
        propertyId: widget.propertyId,
        caseName: result.caseName,
        unitId: result.unitId,
        prospectPartyId: result.prospectPartyId,
        source: result.source,
        notes: result.notes,
      ),
    );
  }

  Future<void> _editCase(
    LeasingCasesController controller,
    LeasingCasesState state,
  ) async {
    final leasingCase = state.selectedCase;
    if (leasingCase == null) {
      return;
    }
    final result = await showLeasingCaseFormDialog(
      context,
      units: state.units,
      parties: state.parties,
      existing: leasingCase,
    );
    if (result == null) {
      return;
    }
    await controller.updateCase(
      leasingCase: leasingCase,
      changes: LeasingCaseUpdateDto(
        caseName: result.caseName,
        unitId: result.unitId,
        prospectPartyId: result.prospectPartyId,
        source: result.source,
        notes: result.notes,
      ),
    );
  }

  Future<void> _advanceCase(
    LeasingCasesController controller,
    LeasingCasesState state,
  ) async {
    final leasingCase = state.selectedCase;
    if (leasingCase == null) {
      return;
    }
    final request = await showLeasingCaseAdvanceDialog(
      context,
      leasingCase: leasingCase,
      availableLeases: state.leasesForCase(leasingCase),
    );
    if (request == null) {
      return;
    }
    await controller.advanceCase(
      leasingCase: leasingCase,
      leaseId: request.leaseId,
    );
  }

  Future<void> _cancelCase(
    LeasingCasesController controller,
    LeasingCasesState state,
  ) async {
    final leasingCase = state.selectedCase;
    if (leasingCase == null) {
      return;
    }
    final reason = await showLeasingCaseCancellationDialog(
      context,
      leasingCase: leasingCase,
    );
    if (reason == null) {
      return;
    }
    await controller.cancelCase(leasingCase: leasingCase, reason: reason);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onStageChanged,
    required this.onOpenOnlyChanged,
    required this.onCreate,
  });

  final LeasingCasesState state;
  final bool canMutate;
  final bool readOnlyBackend;
  final ValueChanged<LeasingCaseStatus?> onStageChanged;
  final ValueChanged<bool> onOpenOnlyChanged;
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
              width: mobile ? 200 : 240,
              child: DropdownButtonFormField<String>(
                value: state.stageFilter?.name ??
                    _LeasingPipelinePanelState._allStages,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Stufe',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _LeasingPipelinePanelState._allStages,
                    child: Text('Alle Stufen'),
                  ),
                  for (final status in LeasingCaseStatus.values)
                    DropdownMenuItem<String>(
                      value: status.name,
                      child: Text(leasingCaseStatusLabel(status)),
                    ),
                ],
                onChanged: (value) => onStageChanged(
                  value == null ||
                          value == _LeasingPipelinePanelState._allStages
                      ? null
                      : LeasingCaseStatus.values.byName(value),
                ),
              ),
            ),
            Tooltip(
              message: 'Abgeschlossene und abgebrochene Fälle sind das Archiv, '
                  'nicht die Pipeline.',
              child: FilterChip(
                label: const Text('Nur offene'),
                selected: state.openOnly,
                onSelected: onOpenOnlyChanged,
              ),
            ),
            FilledButton.icon(
              onPressed: canMutate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: const Text('Fall anlegen'),
            ),
          ],
        ),
      ],
    );
  }
}

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
              'Die lokale Datenbank ist für die Vermietungspipeline '
              'schreibgeschützt, bis diese Domäne migriert ist. Lesen '
              'funktioniert vollständig; Anlegen und Stufenwechsel sind erst '
              'im Cloud-Betrieb verfügbar.',
            ),
          ),
        ],
      ),
    );
  }
}

/// The board. Columns are the stages currently in scope: the nine open ones,
/// plus the terminal ones when the archive filter is off.
class _PipelineBoard extends StatelessWidget {
  const _PipelineBoard({
    required this.state,
    required this.columnWidth,
    required this.onSelect,
  });

  final LeasingCasesState state;
  final double columnWidth;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final stages = <LeasingCaseStatus>[
      for (final status in LeasingCaseStatus.values)
        if (!state.openOnly || !status.isTerminal) status,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final stage in stages)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: columnWidth,
                child: _BoardColumn(
                  stage: stage,
                  state: state,
                  cases: state.cases
                      .where((value) => value.status == stage)
                      .toList(growable: false),
                  onSelect: onSelect,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.stage,
    required this.state,
    required this.cases,
    required this.onSelect,
  });

  final LeasingCaseStatus stage;
  final LeasingCasesState state;
  final List<LeasingCaseSummaryDto> cases;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  leasingCaseStatusLabel(stage),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              LeasingCaseStatusBadge(status: stage),
            ],
          ),
          const SizedBox(height: 8),
          if (cases.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Kein Fall',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final value in cases)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _CaseCard(
                  value: value,
                  state: state,
                  selected: value.id == state.selectedCaseId,
                  onTap: () => onSelect(value.id),
                ),
              ),
        ],
      ),
    );
  }
}

/// Below the board breakpoint: the same cards, grouped by stage in one column.
class _StackedCaseList extends StatelessWidget {
  const _StackedCaseList({required this.state, required this.onSelect});

  final LeasingCasesState state;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final stage in LeasingCaseStatus.values)
          if (state.cases.any((value) => value.status == stage)) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                leasingCaseStatusLabel(stage),
                style: theme.textTheme.labelLarge,
              ),
            ),
            for (final value
                in state.cases.where((value) => value.status == stage))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _CaseCard(
                  value: value,
                  state: state,
                  selected: value.id == state.selectedCaseId,
                  onTap: () => onSelect(value.id),
                ),
              ),
          ],
      ],
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({
    required this.value,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  final LeasingCaseSummaryDto value;
  final LeasingCasesState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.08)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(value.caseName, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                state.partyNameFor(value.prospectPartyId) ??
                    'Interessent offen',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                state.unitCodeFor(value.unitId) ?? 'Einheit offen',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseDetailCard extends StatelessWidget {
  const _CaseDetailCard({
    required this.state,
    required this.controller,
    required this.onEdit,
    required this.onAdvance,
    required this.onCancel,
  });

  final LeasingCasesState state;
  final LeasingCasesController controller;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case LeasingCasesDetailPhase.idle:
        return const NxCard(
          child: Text('Wähle einen Fall, um seine Details zu sehen.'),
        );
      case LeasingCasesDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case LeasingCasesDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Fall nicht gefunden',
            description:
                'Dieser Fall existiert nicht mehr. Vermutlich wurde er '
                'entfernt, während die Liste offen war.',
            icon: Icons.search_off_outlined,
          ),
        );
      case LeasingCasesDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diesen Fall fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case LeasingCasesDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Der Fall konnte nicht geladen werden.',
          ),
        );
      case LeasingCasesDetailPhase.ready:
        final leasingCase = state.selectedCase;
        if (leasingCase == null) {
          return const SizedBox.shrink();
        }
        return LeasingCaseDetailView(
          leasingCase: leasingCase,
          unitCode: state.unitCodeFor(leasingCase.unitId),
          prospectName: state.partyNameFor(leasingCase.prospectPartyId),
          leaseName: state.leaseNameFor(leasingCase.leaseId),
          canMutate: controller.canMutate,
          refusal: state.actionPhase == LeasingCasesActionPhase.blocked
              ? state.refusal
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
      title: 'Die Pipeline konnte nicht geladen werden',
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

class _PipelineSkeleton extends StatelessWidget {
  const _PipelineSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < 3; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
