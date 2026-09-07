/// Which costs may be passed on to tenants (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// **The unclassified count is the point of the screen.** It comes from the
/// server over every account in the workspace, and it is the number this work
/// drives to zero. An account nobody has classified is listed alongside the
/// classified ones rather than filtered away — a list of only the finished
/// work makes the work look finished, and this is the work that decides which
/// costs a tenant pays.
///
/// **Unclassified and "not apportionable" look different**, deliberately. They
/// mean different things to a settlement run and to the person doing the
/// classification, and a screen that drew them alike would make the count
/// unexplainable.
///
/// **A HeizkostenV position offers only the performance principle.** Not as a
/// warning after the fact: the control simply does not offer the other one,
/// because BGH VIII ZR 156/11 leaves no choice and a disabled option invites
/// asking why it is disabled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/finance_ledger/application/cost_allocation_controller.dart';
import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'cost_allocation_dialog.dart';

String costSettlementPrincipleLabel(CostSettlementPrinciple? principle) =>
    switch (principle) {
      CostSettlementPrinciple.performance => 'Leistungsprinzip',
      CostSettlementPrinciple.outflow => 'Abflussprinzip',
      CostSettlementPrinciple.unknown => 'Unbekanntes Prinzip',
      null => '—',
    };

class CostAllocationScreen extends ConsumerStatefulWidget {
  const CostAllocationScreen({super.key});

  @override
  ConsumerState<CostAllocationScreen> createState() =>
      _CostAllocationScreenState();
}

class _CostAllocationScreenState extends ConsumerState<CostAllocationScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(costAllocationControllerProvider);
    final controller = ref.read(costAllocationControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NxPageHeader(
            title: 'Umlagefähigkeit',
            subtitle:
                'Welche Kosten auf Mieter umgelegt werden dürfen und nach '
                'welchem Prinzip sie abgerechnet werden.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CostAllocationState state,
    CostAllocationController controller,
  ) {
    switch (state.phase) {
      case CostAllocationPhase.idle:
      case CostAllocationPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('cost-allocation-loading')),
        );
      case CostAllocationPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('cost-allocation-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für die Umlagefähigkeit fehlt die Leseberechtigung für '
                    'Finanzdaten.',
            icon: Icons.lock_outline,
          ),
        );
      case CostAllocationPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('cost-allocation-error'),
            title: 'Die Kostenarten konnten nicht geladen werden',
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case CostAllocationPhase.ready:
        return _ready(context, state, controller);
    }
  }

  Widget _ready(
    BuildContext context,
    CostAllocationState state,
    CostAllocationController controller,
  ) {
    final semantic = context.semanticColors;

    return ListView(
      key: const Key('cost-allocation-list'),
      children: <Widget>[
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Nicht eingeordnet',
              value: '${state.unclassifiedCount}',
              status: state.unclassifiedCount > 0 ? semantic.warning : null,
              // The number the work drives to zero, counted by the server over
              // every account -- not over the rows below.
              caption: 'im gesamten Workspace',
            ),
            NxKpiTile(
              label: 'Eingeordnet',
              value: '${state.classifiedCount}',
              caption: 'im gesamten Workspace',
            ),
            NxKpiTile(
              label: 'Kostenarten',
              value: '${state.totalCount}',
              caption: 'insgesamt',
            ),
          ],
        ),
        if (state.actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('cost-allocation-action-message'),
            message: state.actionMessage!,
            kind: state.actionPhase == CostAllocationActionPhase.failed
                ? NxNoticeKind.error
                : NxNoticeKind.info,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (state.accounts.isEmpty)
          const NxCard(
            child: NxEmptyState(
              key: Key('cost-allocation-empty'),
              title: 'Keine Kostenarten angelegt',
              description:
                  'Die Umlagefähigkeit hängt an den Finanzkonten. Ohne Konten '
                  'gibt es nichts einzuordnen.',
              icon: Icons.account_tree_outlined,
            ),
          )
        else
          for (final CostAccountAllocationDto account in state.accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _AccountRow(
                account: account,
                canMutate: controller.canMutate,
                onEdit: () => _edit(controller, account),
              ),
            ),
      ],
    );
  }

  Future<void> _edit(
    CostAllocationController controller,
    CostAccountAllocationDto account,
  ) async {
    final result = await showCostAllocationDialog(context, account: account);
    if (result == null) {
      return;
    }
    await controller.setRule(
      account: account,
      allocatable: result.allocatable,
      settlementPrinciple: result.settlementPrinciple,
      betrkvPosition: result.betrkvPosition,
      underHeatingCostRegulation: result.underHeatingCostRegulation,
      note: result.note,
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.canMutate,
    required this.onEdit,
  });

  final CostAccountAllocationDto account;
  final bool canMutate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final CostAllocationRuleDto? rule = account.rule;

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
                  '${account.code} · ${account.name}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Three states, drawn three ways. "Not classified" and "not
              // apportionable" mean different things and must not look alike.
              if (rule == null)
                const NxStatusBadge(
                  key: Key('cost-allocation-unclassified'),
                  label: 'Nicht eingeordnet',
                  kind: NxBadgeKind.warning,
                )
              else if (rule.allocatable)
                const NxStatusBadge(label: 'Umlagefähig', kind: NxBadgeKind.success)
              else
                const NxStatusBadge(
                  label: 'Nicht umlagefähig',
                  kind: NxBadgeKind.neutral,
                ),
            ],
          ),
          if (rule != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            if (rule.allocatable)
              Text(
                costSettlementPrincipleLabel(rule.settlementPrinciple),
                style: muted,
              ),
            if (rule.underHeatingCostRegulation)
              Text(
                'HeizkostenV — Leistungsprinzip ist vorgeschrieben',
                key: const Key('cost-allocation-heating'),
                style: muted,
              ),
            if (rule.betrkvPosition != null)
              Text('BetrKV: ${rule.betrkvPosition}', style: muted),
            if (rule.note != null) Text(rule.note!, style: muted),
          ] else ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Noch nicht entschieden, ob diese Kosten umgelegt werden dürfen.',
              style: muted,
            ),
          ],
          if (canMutate) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: Key('cost-allocation-edit-${account.financeAccountId}'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: Text(rule == null ? 'Einordnen' : 'Ändern'),
            ),
          ],
        ],
      ),
    );
  }
}
