/// Cost pools and allocation keys (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// **The unresolvable count is the point of the screen.** It comes from the
/// server over every key in force on the chosen day, and it is what a
/// settlement run would be unable to use. Four of the seven distribution bases
/// have no store in this schema yet, and one missing unit area is enough to
/// make a key unresolvable — so a key that cannot compute is listed with its
/// reason rather than hidden, and the reason is the server's own words.
///
/// **A pool at a scope with no entity says so permanently.** Building,
/// entrance and Zählergruppe exist nowhere in this schema; a pool at one of
/// those scopes holds costs somebody assigns by hand and cannot be distributed
/// automatically. That is a statement about the model, not a data defect, and
/// it is drawn differently from a key that merely lacks values.
///
/// **The date is shown, never assumed.** A key is in force on a day or it is
/// not, and the server decides which day "today" is. The header states the
/// date the answer is about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/finance_ledger/application/cost_allocation_controller.dart';
import '../../../features/finance_ledger/application/cost_pool_controller.dart';
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../../features/portfolio_property/application/property_repository.dart';
import '../../../features/portfolio_property/domain/property_dto.dart';
import '../../../features/portfolio_property/presentation/property_switcher_dialog.dart';
import '../../../features/identity_access/application/workspace_session_scope.dart';
import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_section_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'allocation_key_dialog.dart';
import 'cost_pool_dialog.dart';

String allocationUnresolvableReasonLabel(
  AllocationUnresolvableReason? reason,
) => switch (reason) {
  AllocationUnresolvableReason.noBasisStore => 'Keine Datenbasis vorhanden',
  AllocationUnresolvableReason.noMeters => 'Keine Zähler erfasst',
  AllocationUnresolvableReason.noUnits => 'Keine Einheiten erfasst',
  AllocationUnresolvableReason.incompleteBasis => 'Werte unvollständig',
  AllocationUnresolvableReason.unknown => 'Unbekannter Grund',
  null => 'Auflösbar',
};

class CostPoolScreen extends ConsumerStatefulWidget {
  const CostPoolScreen({super.key, this.propertyId});

  /// Null is the workspace-wide reading. A property screen passes its own id
  /// so the keys shown are the ones that answer for that building.
  final String? propertyId;

  @override
  ConsumerState<CostPoolScreen> createState() => _CostPoolScreenState();
}

class _CostPoolScreenState extends ConsumerState<CostPoolScreen> {
  /// Names for property ids the pool and key lists did not carry — filled in
  /// when the switcher hands one back, so a freshly picked property reads as
  /// its name rather than as a uuid.
  final Map<String, String> _pickedNames = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final CostPoolState state = ref.watch(
      costPoolControllerProvider(widget.propertyId),
    );
    final CostPoolController controller = ref.read(
      costPoolControllerProvider(widget.propertyId).notifier,
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NxPageHeader(
            title: 'Kostenpools und Umlageschlüssel',
            subtitle:
                'Welche Kosten zusammen abgerechnet werden und nach welchem '
                'Maßstab sie auf die Einheiten verteilt werden.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CostPoolState state,
    CostPoolController controller,
  ) {
    switch (state.phase) {
      case CostPoolPhase.idle:
      case CostPoolPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('cost-pool-loading')),
        );
      case CostPoolPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('cost-pool-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für Kostenpools und Umlageschlüssel fehlt die '
                    'Leseberechtigung für Finanzdaten.',
            icon: Icons.lock_outline,
          ),
        );
      case CostPoolPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('cost-pool-error'),
            title: 'Die Umlagestruktur konnte nicht geladen werden',
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case CostPoolPhase.ready:
        return _ready(context, state, controller);
    }
  }

  Widget _ready(
    BuildContext context,
    CostPoolState state,
    CostPoolController controller,
  ) {
    final semantic = context.semanticColors;

    return ListView(
      key: const Key('cost-pool-list'),
      children: <Widget>[
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Nicht auflösbar',
              value: '${state.unresolvableCount}',
              status: state.unresolvableCount > 0 ? semantic.warning : null,
              // The server counted over every key in force on this date, not
              // over the rows below.
              caption: 'Schlüssel ohne rechenbare Basis',
            ),
            NxKpiTile(
              label: 'Auflösbar',
              value: '${state.resolvableCount}',
              caption: 'Schlüssel mit vollständiger Basis',
            ),
            NxKpiTile(
              label: 'Stichtag',
              value: state.asOf == null ? '—' : _formatDate(state.asOf!),
              caption: 'Gültigkeit wird für diesen Tag gelesen',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('cost-pool-pick-date'),
            onPressed: () => _pickDate(controller, state),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: const Text('Stichtag ändern'),
          ),
        ),
        if (state.actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('cost-pool-action-message'),
            message: state.actionMessage!,
            kind: state.actionPhase == CostPoolActionPhase.failed
                ? NxNoticeKind.error
                : NxNoticeKind.info,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        NxSectionHeader(
          title: 'Umlageschlüssel',
          description:
              'Je Objekt, Kostenart und Pool gilt an einem Tag genau ein '
              'Schlüssel.',
          actions: <Widget>[
            if (controller.canMutate)
              FilledButton.icon(
                key: const Key('allocation-key-create'),
                onPressed: () => _editKey(controller, state, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Schlüssel anlegen'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (state.keyList.isEmpty)
          const NxCard(
            child: NxEmptyState(
              key: Key('allocation-key-empty'),
              title: 'Für diesen Stichtag gilt kein Schlüssel',
              description:
                  'Ohne Umlageschlüssel lässt sich keine Betriebskosten'
                  'abrechnung erstellen: der Verteilerschlüssel gehört zu den '
                  'vier Mindestangaben.',
              icon: Icons.percent_outlined,
            ),
          )
        else
          for (final AllocationKeyDto key in state.keyList)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _KeyRow(
                allocationKey: key,
                canMutate: controller.canMutate,
                onEdit: () => _editKey(controller, state, key),
              ),
            ),
        const SizedBox(height: AppSpacing.md),
        NxSectionHeader(
          title: 'Kostenpools',
          description:
              'Gebäude, Aufgang und Zählergruppe haben in diesem Modell keine '
              'eigene Entität; solche Pools tragen eine Bezeichnung und werden '
              'nicht automatisch verteilt.',
          actions: <Widget>[
            if (controller.canMutate)
              FilledButton.icon(
                key: const Key('cost-pool-create'),
                onPressed: () => _editPool(controller, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Pool anlegen'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (state.poolList.isEmpty)
          const NxCard(
            child: NxEmptyState(
              key: Key('cost-pool-empty'),
              title: 'Keine Kostenpools angelegt',
              description:
                  'Ein Pool fasst Kosten zusammen, die gemeinsam verteilt '
                  'werden. Ohne Pool wird je Kostenart verteilt.',
              icon: Icons.workspaces_outline,
            ),
          )
        else
          for (final CostPoolDto pool in state.poolList)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _PoolRow(
                pool: pool,
                canMutate: controller.canMutate,
                onEdit: () => _editPool(controller, pool),
              ),
            ),
      ],
    );
  }

  Future<void> _pickDate(
    CostPoolController controller,
    CostPoolState state,
  ) async {
    final DateTime anchor = state.asOf ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(anchor.year, anchor.month, anchor.day),
      firstDate: DateTime(anchor.year - 20),
      lastDate: DateTime(anchor.year + 20),
    );
    if (picked == null) {
      return;
    }
    await controller.showDate(
      DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _editPool(
    CostPoolController controller,
    CostPoolDto? pool,
  ) async {
    final CostPoolFormResult? result = await showCostPoolDialog(
      context,
      pool: pool,
      pickProperty: _pickProperty,
      propertyLabel: _propertyLabel,
    );
    if (result == null) {
      return;
    }
    await controller.savePool(
      existing: pool,
      poolKey: result.poolKey,
      name: result.name,
      scope: result.scope,
      propertyId: result.propertyId,
      scopeLabel: result.scopeLabel,
      note: result.note,
      isActive: result.isActive,
    );
  }

  Future<void> _editKey(
    CostPoolController controller,
    CostPoolState state,
    AllocationKeyDto? allocationKey,
  ) async {
    // The cost account list comes from P-2a's read, which is the same account
    // tree a key points at. Reusing it keeps the two surfaces from disagreeing
    // about what a Kostenart is.
    final CostAllocationState allocation = ref.read(
      costAllocationControllerProvider,
    );
    final AllocationKeyFormResult? result = await showAllocationKeyDialog(
      context,
      allocationKey: allocationKey,
      initialPropertyId: widget.propertyId,
      pools: state.poolList,
      accounts: allocation.accounts,
      pickProperty: _pickProperty,
      propertyLabel: _propertyLabel,
    );
    if (result == null) {
      return;
    }
    await controller.saveKey(
      existing: allocationKey,
      propertyId: result.propertyId,
      basis: result.basis,
      explanation: result.explanation,
      validFrom: result.validFrom,
      validTo: result.validTo,
      financeAccountId: result.financeAccountId,
      costPoolId: result.costPoolId,
      note: result.note,
    );
  }

  /// The workspace-wide property search (`PROPERTY-LOOKUP-01`), not a filter
  /// over whatever this screen happens to have loaded.
  Future<String?> _pickProperty(BuildContext dialogContext) async {
    final PropertyRepository repository = ref.read(
      referencePropertyRepositoryProvider,
    );
    final String? workspaceId = ref
        .read(workspaceSessionScopeProvider)
        .workspaceId;
    final String? chosen = await PropertySwitcherDialog.show(
      dialogContext,
      currentPropertyId: widget.propertyId ?? '',
      loadPage: ({String? cursor, String? searchTerm}) async {
        if (workspaceId == null) {
          return const PropertyRepositoryFailure<PropertyPageResult>(
            kind: PropertyRepositoryFailureKind.forbidden,
            message: 'Kein Workspace ausgewählt.',
          );
        }
        return repository.list(
          PropertyListQuery(
            workspaceId: workspaceId,
            page: PropertyPageRequest(cursor: cursor),
            searchTerm: searchTerm,
          ),
        );
      },
    );
    if (chosen == null || workspaceId == null) {
      return chosen;
    }
    // The switcher hands back an id. Nothing on this screen names a property
    // that has neither a pool nor a key yet, and a form field reading as a
    // uuid is a form field nobody can check -- so the name is fetched once and
    // remembered.
    final PropertyRepositoryResult<PropertyDto> named = await repository
        .getById(workspaceId: workspaceId, propertyId: chosen);
    if (named case PropertyRepositorySuccess<PropertyDto>(:final value)) {
      _pickedNames[chosen] = value.name;
    }
    return chosen;
  }

  String _propertyLabel(String propertyId) {
    final CostPoolState state = ref.read(
      costPoolControllerProvider(widget.propertyId),
    );
    for (final CostPoolDto pool in state.poolList) {
      if (pool.propertyId == propertyId && pool.propertyName != null) {
        return pool.propertyName!;
      }
    }
    for (final AllocationKeyDto key in state.keyList) {
      if (key.propertyId == propertyId && key.propertyName != null) {
        return key.propertyName!;
      }
    }
    // Nothing on screen names it yet — a property just picked, or one with no
    // pools and no keys. The id is shown rather than a placeholder, because a
    // placeholder would make two different properties look like one.
    return _pickedNames[propertyId] ?? propertyId;
  }
}

class _PoolRow extends StatelessWidget {
  const _PoolRow({
    required this.pool,
    required this.canMutate,
    required this.onEdit,
  });

  final CostPoolDto pool;
  final bool canMutate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${pool.poolKey} · ${pool.name}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Two different statements, drawn differently. "Cannot be
              // distributed automatically" is about the model; "inactive" is
              // about this pool.
              if (!pool.scopeResolvable)
                const NxStatusBadge(
                  key: Key('cost-pool-unresolvable'),
                  label: 'Ohne eigene Entität',
                  kind: NxBadgeKind.warning,
                )
              else if (!pool.isActive)
                const NxStatusBadge(label: 'Inaktiv', kind: NxBadgeKind.neutral)
              else
                const NxStatusBadge(label: 'Aktiv', kind: NxBadgeKind.success),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(pool.scopeDescription, style: muted),
          if (!pool.scopeResolvable)
            Text(
              'Kosten können hier gesammelt, aber nicht automatisch verteilt '
              'werden — für Gebäude, Aufgang und Zählergruppe gibt es in '
              'diesem Modell keine eigene Entität.',
              style: muted,
            ),
          if (pool.note != null) Text(pool.note!, style: muted),
          if (canMutate) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: Key('cost-pool-edit-${pool.id}'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: const Text('Ändern'),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.allocationKey,
    required this.canMutate,
    required this.onEdit,
  });

  final AllocationKeyDto allocationKey;
  final bool canMutate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final AllocationBasisResolutionDto resolution =
        allocationKey.basisResolution;

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  allocationBasisLabel(allocationKey.basis),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (allocationKey.isUsableForSettlement)
                NxStatusBadge(
                  label: resolution.total == null
                      ? 'Auflösbar'
                      : 'Basis ${_formatNumber(resolution.total!)}',
                  kind: NxBadgeKind.success,
                )
              else
                NxStatusBadge(
                  key: const Key('allocation-key-unresolvable'),
                  label: allocationUnresolvableReasonLabel(resolution.reason),
                  kind: NxBadgeKind.warning,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            <String>[
              allocationKey.propertyName ?? allocationKey.propertyId,
              if (allocationKey.financeAccountCode != null)
                '${allocationKey.financeAccountCode} · '
                    '${allocationKey.financeAccountName ?? ''}'
              else
                'Alle übrigen Kostenarten',
              if (allocationKey.costPoolKey != null)
                'Pool ${allocationKey.costPoolKey}',
            ].join(' — '),
            style: muted,
          ),
          Text(
            allocationKey.validTo == null
                ? 'ab ${_formatDate(allocationKey.validFrom)}'
                : '${_formatDate(allocationKey.validFrom)} – '
                      '${_formatDate(allocationKey.validTo!)}',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.xxs),
          // The server's own words about where the figure comes from, or why
          // there is none. Shown rather than paraphrased: it names which of
          // this schema's several area figures the key means.
          if (resolution.detail != null)
            Text(
              resolution.detail!,
              key: const Key('allocation-key-detail'),
              style: muted,
            ),
          if (resolution.unitsWithoutValue != null &&
              resolution.unitsWithoutValue! > 0)
            Text(
              '${resolution.unitsWithoutValue} von '
              '${resolution.unitCount ?? '?'} Einheiten ohne Wert — der '
              'fehlende Anteil würde sonst still auf die übrigen verteilt.',
              style: muted,
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(allocationKey.explanation, style: theme.textTheme.bodySmall),
          if (allocationKey.note != null)
            Text(allocationKey.note!, style: muted),
          if (canMutate) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: Key('allocation-key-edit-${allocationKey.id}'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: const Text('Ändern'),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _formatNumber(num value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}
