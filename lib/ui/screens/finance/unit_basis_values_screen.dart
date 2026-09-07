/// The per-unit distribution basis values (`UNIT-BASIS-VALUES-01`, P-2c).
///
/// **This screen is the answer to a diagnosis.** An allocation key that
/// reports itself unresolvable says why — no values, an incomplete set, or two
/// conventions — and this is where that is fixed. It is opened from the key,
/// for one property and one basis, because that is the pair the verdict is
/// about.
///
/// **The verdict is the server's.** Whether the basis can be used, what it
/// totals and how many units are missing a figure are read, never recomputed
/// here. A screen that derived its own verdict could report the basis ready
/// while the settlement engine refuses it.
///
/// **Units without a figure are listed first, not filtered away.** They are
/// exactly what makes the basis unresolvable, and a list of only the finished
/// work makes the work look finished.
///
/// **The area is shown beside every figure being entered.** It is the one
/// distribution basis this schema already holds, and comparing the two is the
/// cheapest sanity check available to somebody typing head counts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/finance_ledger/application/unit_basis_value_controller.dart';
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'allocation_key_dialog.dart' show allocationBasisLabel;
import 'unit_basis_value_dialog.dart';

/// Opens the basis values for one property and basis. Returns nothing: the
/// caller re-reads its own verdict, which is the server's and may have changed.
Future<void> showUnitBasisValues(
  BuildContext context, {
  required String propertyId,
  required AllocationBasis basis,
  String? propertyName,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext routeContext) => Scaffold(
        appBar: AppBar(title: const Text('Basiswerte je Einheit')),
        body: UnitBasisValuesScreen(
          propertyId: propertyId,
          basis: basis,
          propertyName: propertyName,
        ),
      ),
    ),
  );
}

class UnitBasisValuesScreen extends ConsumerWidget {
  const UnitBasisValuesScreen({
    super.key,
    required this.propertyId,
    required this.basis,
    this.propertyName,
  });

  final String propertyId;
  final AllocationBasis basis;
  final String? propertyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UnitBasisScope scope = UnitBasisScope(
      propertyId: propertyId,
      basis: basis,
    );
    final UnitBasisState state = ref.watch(unitBasisControllerProvider(scope));
    final UnitBasisController controller = ref.read(
      unitBasisControllerProvider(scope).notifier,
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NxPageHeader(
            title: allocationBasisLabel(basis),
            subtitle: <String>[
              if (propertyName != null) propertyName!,
              'Jede Einheit braucht einen Wert, und alle Werte müssen nach '
                  'derselben Konvention ermittelt sein.',
            ].join(' · '),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    UnitBasisState state,
    UnitBasisController controller,
  ) {
    switch (state.phase) {
      case UnitBasisPhase.idle:
      case UnitBasisPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('unit-basis-loading')),
        );
      case UnitBasisPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('unit-basis-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für Basiswerte fehlt die Leseberechtigung für Finanzdaten.',
            icon: Icons.lock_outline,
          ),
        );
      case UnitBasisPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('unit-basis-error'),
            title: 'Die Basiswerte konnten nicht geladen werden',
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case UnitBasisPhase.ready:
        return _ready(context, state, controller);
    }
  }

  Widget _ready(
    BuildContext context,
    UnitBasisState state,
    UnitBasisController controller,
  ) {
    final semantic = context.semanticColors;
    final AllocationBasisResolutionDto? resolution = state.resolution;
    // The server names a shared convention only when there IS one, so a row
    // marker keyed on it could never fire in the state it was meant to
    // explain. When the conventions differ, the majority is computed here --
    // for display only; the verdict above stays the server's.
    final String? majorityConvention = _majorityConvention(state.units);
    // Missing figures first: they are the work, and the ones already recorded
    // are the part that needs no attention.
    final List<UnitBasisRowDto> ordered = <UnitBasisRowDto>[
      ...state.units.where((UnitBasisRowDto row) => !row.hasValue),
      ...state.units.where((UnitBasisRowDto row) => row.hasValue),
    ];

    return ListView(
      key: const Key('unit-basis-list'),
      children: <Widget>[
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Ohne Wert',
              value: '${state.missingCount}',
              status: state.missingCount > 0 ? semantic.warning : null,
              caption: 'Einheiten, die den Maßstab blockieren',
            ),
            NxKpiTile(
              label: 'Erfasst',
              value: '${state.recordedCount}',
              caption: 'von ${state.units.length} Einheiten',
            ),
            NxKpiTile(
              label: 'Summe',
              value: resolution?.total == null
                  ? '—'
                  : _formatNumber(resolution!.total!),
              // Withheld rather than approximated. The server reports no total
              // until every unit has a figure and all of them share one
              // convention, and a dash is the honest rendering of that.
              caption: state.isResolvable
                  ? 'Nenner für die Verteilung'
                  : 'wird erst bei vollständiger Basis gebildet',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (resolution != null)
          NxNotice(
            key: const Key('unit-basis-resolution'),
            message: resolution.detail ?? 'Keine Angabe des Servers.',
            kind: state.isResolvable
                ? NxNoticeKind.info
                : NxNoticeKind.warning,
          ),
        if (state.actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('unit-basis-action-message'),
            message: state.actionMessage!,
            kind: state.actionPhase == UnitBasisActionPhase.failed
                ? NxNoticeKind.error
                : NxNoticeKind.info,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('unit-basis-pick-date'),
            onPressed: () => _pickDate(context, controller, state),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              state.asOf == null
                  ? 'Stichtag wählen'
                  : 'Stichtag ${_formatDate(state.asOf!)}',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.units.isEmpty)
          const NxCard(
            child: NxEmptyState(
              key: Key('unit-basis-empty'),
              title: 'Dieses Objekt hat keine Einheiten',
              description:
                  'Ohne Einheiten gibt es nichts zu verteilen. Der Maßstab '
                  'bleibt nicht auflösbar, bis Einheiten erfasst sind.',
              icon: Icons.door_front_door_outlined,
            ),
          )
        else
          for (final UnitBasisRowDto row in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _UnitRow(
                row: row,
                canMutate: controller.canMutate,
                sharedConvention: resolution?.convention ?? majorityConvention,
                onEdit: () => _edit(context, controller, state, row),
              ),
            ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    UnitBasisController controller,
    UnitBasisState state,
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
    await controller.showDate(DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _edit(
    BuildContext context,
    UnitBasisController controller,
    UnitBasisState state,
    UnitBasisRowDto row,
  ) async {
    await showUnitBasisValueDialog(
      context,
      row: row,
      basis: basis,
      // Offered as the default for a new figure, so the ordinary case ends up
      // with one convention across the property rather than several typed
      // slightly differently.
      suggestedConvention: state.resolution?.convention ??
          state.units
              .map((UnitBasisRowDto other) => other.value?.convention)
              .whereType<String>()
              .firstOrNull,
      defaultValidFrom: state.asOf,
      // No `existing` is passed: the controller reads the current version
      // from its own state at submit time, so a retry after a version
      // conflict from this still-open dialog sends the fresh one.
      onSubmit: (UnitBasisValueFormResult result) => controller.saveValue(
        unitId: row.unitId,
        value: result.value,
        convention: result.convention,
        validFrom: result.validFrom,
        validTo: result.validTo,
        note: result.note,
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.row,
    required this.canMutate,
    required this.onEdit,
    this.sharedConvention,
  });

  final UnitBasisRowDto row;
  final bool canMutate;
  final String? sharedConvention;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final UnitBasisValueDto? value = row.value;
    // Only meaningful once the property agrees on one; while it does not, the
    // resolution reports `mixedConventions` and every row is equally suspect.
    final bool deviates =
        value != null &&
        sharedConvention != null &&
        value.convention != sharedConvention;

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
                  row.unitCode,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (value == null)
                const NxStatusBadge(
                  key: Key('unit-basis-missing'),
                  label: 'Kein Wert',
                  kind: NxBadgeKind.warning,
                )
              else
                NxStatusBadge(
                  label: _formatNumber(value.value),
                  kind: deviates ? NxBadgeKind.warning : NxBadgeKind.success,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (row.areaSqm != null)
            Text(
              // The one basis the schema already holds, shown as a check
              // against the figure being typed.
              '${_formatNumber(row.areaSqm!)} m² Wohnfläche',
              style: muted,
            ),
          if (value != null) ...<Widget>[
            Text('Konvention: ${value.convention}', style: muted),
            if (deviates)
              Text(
                'Weicht von der Konvention der übrigen Einheiten ab. Werte, '
                'die verschieden ermittelt wurden, ergeben zusammen keinen '
                'Nenner.',
                key: const Key('unit-basis-deviating-convention'),
                style: muted,
              ),
            Text(
              value.validTo == null
                  ? 'ab ${_formatDate(value.validFrom)}'
                  : '${_formatDate(value.validFrom)} – '
                        '${_formatDate(value.validTo!)}',
              style: muted,
            ),
            if (value.note != null) Text(value.note!, style: muted),
          ] else
            Text(
              'Für diese Einheit ist noch nichts erfasst. Solange das so '
              'bleibt, rechnet der Maßstab nichts aus.',
              style: muted,
            ),
          if (canMutate) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: Key('unit-basis-edit-${row.unitId}'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: Text(value == null ? 'Erfassen' : 'Ändern'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The convention most units state, when they do not all state the same one.
/// Presentational only — which rows to mark. Whether the basis resolves is the
/// server's answer and is never derived from this.
String? _majorityConvention(List<UnitBasisRowDto> units) {
  final Map<String, int> counts = <String, int>{};
  for (final UnitBasisRowDto row in units) {
    final String? convention = row.value?.convention;
    if (convention != null) {
      counts[convention] = (counts[convention] ?? 0) + 1;
    }
  }
  if (counts.length < 2) {
    return null;
  }
  String? best;
  int bestCount = 0;
  for (final MapEntry<String, int> entry in counts.entries) {
    if (entry.value > bestCount) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best;
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

/// Six decimals are stored, so six are shown — with the trailing zeros
/// trimmed. Rounding to two collapsed distinct co-ownership shares onto the
/// same string and made the displayed total disagree with the sum of the
/// displayed rows.
String _formatNumber(num value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toStringAsFixed(0);
  }
  final String text = value.toStringAsFixed(6);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}
