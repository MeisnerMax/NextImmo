/// The cost types, and which of them may be passed on to tenants
/// (`FINANCE-COST-TYPES-01` and `COST-ALLOCATION-RULES-01`, P-2a).
///
/// **One list, two questions.** Which cost types exist, and which of them a
/// tenant pays. They were nearly two screens; they are one, because a second
/// list of the same accounts is a second place for the same fact to be wrong.
/// Creating a cost type here decides nothing about apportionment — the new row
/// appears unclassified, which is the state the count below exists to drive to
/// zero.
///
/// **The § 2 BetrKV catalogue is offered, never applied.** `DEC-014` records
/// it as source-contradictory, so it is a list of suggestions the workspace
/// adopts one at a time and edits freely. Nothing validates against it, and a
/// cost type that appears on no list is accepted exactly as readily.
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
import '../../../features/finance_ledger/domain/betrkv_catalogue.dart';
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
import 'finance_account_dialog.dart';

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
            title: 'Kostenarten',
            subtitle:
                'Welche Kostenarten es gibt, welche davon auf Mieter umgelegt '
                'werden dürfen und nach welchem Prinzip sie abgerechnet '
                'werden.',
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
        if (controller.canMutate) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('finance-account-create'),
              onPressed: () => _editAccount(controller, null, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Kostenart anlegen'),
            ),
          ),
          _BetrkvPanel(
            outstanding: outstandingBetrkvSuggestions(
              state.accounts.map(
                (CostAccountAllocationDto account) =>
                    account.rule?.betrkvPosition,
              ),
            ),
            onAdopt: (BetrkvSuggestion suggestion) =>
                _editAccount(controller, null, suggestion),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (state.accounts.isEmpty)
          NxCard(
            child: NxEmptyState(
              key: const Key('cost-allocation-empty'),
              title: 'Noch keine Kostenarten angelegt',
              description: controller.canMutate
                  ? 'Legen Sie an, was Sie abrechnen: Versicherung, Heizung, '
                        'Hausmeister, Allgemeinstrom, Wasser. Der Vorschlag '
                        'nach § 2 BetrKV oben nimmt Ihnen das Tippen ab.'
                  : 'Es sind keine Kostenarten erfasst, und zum Anlegen fehlt '
                        'die Berechtigung zur Finanzverwaltung.',
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
                onRename: controller.canMutate && account.isEditable
                    ? () => _editAccount(controller, account, null)
                    : null,
              ),
            ),
      ],
    );
  }

  /// Creates a cost type, or renames one. The dialog runs the command itself
  /// and stays open on a refusal — a taken code is the usual one — so the
  /// reader keeps what they typed.
  Future<void> _editAccount(
    CostAllocationController controller,
    CostAccountAllocationDto? account,
    BetrkvSuggestion? suggestion,
  ) async {
    await showFinanceAccountDialog(
      context,
      account: account,
      suggestion: suggestion,
      onSubmit: (FinanceAccountFormResult result) => account == null
          ? controller.createAccount(
              code: result.code,
              name: result.name,
              accountType: result.accountType,
            )
          : controller.updateAccount(
              accountId: account.financeAccountId,
              name: result.name,
              isActive: result.isActive,
            ),
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
    this.onRename,
  });

  final CostAccountAllocationDto account;
  final bool canMutate;
  final VoidCallback onEdit;

  /// Null when the account cannot be changed — no permission, or a server that
  /// sent no version. Offering the action then would offer a refusal.
  final VoidCallback? onRename;

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
          if (!account.isActive) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Inaktiv — bleibt in allen Buchungen, die sie zitieren, wird '
              'aber nicht mehr angeboten.',
              key: const Key('finance-account-inactive'),
              style: muted,
            ),
          ],
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
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  key: Key('cost-allocation-edit-${account.financeAccountId}'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: Text(rule == null ? 'Einordnen' : 'Ändern'),
                ),
                if (onRename != null)
                  TextButton.icon(
                    key: Key('finance-account-edit-${account.financeAccountId}'),
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Bezeichnung'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// The § 2 BetrKV starting point, as suggestions the workspace adopts one at a
/// time.
///
/// Collapsed by default and gone entirely once every position has been taken
/// up: a panel that kept offering seventeen items to somebody who has finished
/// is a panel that gets ignored. Nothing here validates anything — `DEC-014`
/// records the catalogue as source-contradictory, so the list is a convenience
/// with its source named, and a workspace that never touches it is not
/// missing a step.
class _BetrkvPanel extends StatelessWidget {
  const _BetrkvPanel({required this.outstanding, required this.onAdopt});

  final List<BetrkvSuggestion> outstanding;
  final ValueChanged<BetrkvSuggestion> onAdopt;

  @override
  Widget build(BuildContext context) {
    if (outstanding.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: NxCard(
        child: ExpansionTile(
          key: const Key('betrkv-panel'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            'Vorschlag nach § 2 BetrKV (${outstanding.length} offen)',
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            'Ein Ausgangspunkt, keine Vorgabe: die Positionen sind einzeln '
            'übernehmbar und danach frei änderbar. Der Katalog ist in DEC-014 '
            'als quellenwidersprüchlich vermerkt, deshalb prüft nichts im '
            'System dagegen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: <Widget>[
            for (final BetrkvSuggestion suggestion in outstanding)
              ListTile(
                key: Key('betrkv-suggestion-${suggestion.position}'),
                contentPadding: EdgeInsets.zero,
                title: Text('§ 2 Nr. ${suggestion.position} — ${suggestion.name}'),
                subtitle: Text(
                  suggestion.note == null
                      ? suggestion.positionText
                      : '${suggestion.positionText} · ${suggestion.note}',
                ),
                isThreeLine: suggestion.note != null,
                trailing: TextButton(
                  onPressed: () => onAdopt(suggestion),
                  child: const Text('Übernehmen'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
