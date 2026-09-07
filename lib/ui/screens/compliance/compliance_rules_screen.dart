/// The workspace's legal rule set (`COMPLIANCE-RULES-01`, V-4, `DEC-014`).
///
/// **The date at the top is the feature.** The screen shows what the law said
/// on a day the reader chooses, because a retrospective correction has to apply
/// the law of its own period — an operating-cost statement for 2024 runs under
/// different rules than one for 2026. A screen that could only show today would
/// make that impossible to check.
///
/// **Nothing here is presented as settled unless somebody said so.** Every rule
/// carries its state — unchecked, confirmed by a named person, or requiring a
/// human decision — and the summary at the top counts the first two across the
/// whole set rather than across the visible list. A calculation built on these
/// rules has to be able to say what it rests on.
///
/// **Proposals are proposals.** The researched catalogue pre-fills the form; it
/// is never written in bulk and never arrives confirmed. That is the shape the
/// owner's approval authorised: the product proposes, a named person confirms,
/// and the confirmation is an event with a date and an author.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/compliance_rules/application/compliance_rules_controller.dart';
import '../../../features/compliance_rules/domain/compliance_rule_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'compliance_rule_form_dialog.dart';
import 'compliance_rule_proposals.dart';

String complianceConfidenceLabel(ComplianceRuleDto rule) => switch (rule.confidence) {
  ComplianceRuleConfidence.verified => 'Bestätigt',
  ComplianceRuleConfidence.unverified => 'Ungeprüft',
  ComplianceRuleConfidence.decisionSupport => 'Entscheidung nötig',
  // Shown by its raw key rather than guessed at: a state this build does not
  // know could be stricter than anything it does know.
  ComplianceRuleConfidence.unknown => rule.rawConfidenceKey ?? 'Unbekannt',
};

NxBadgeKind complianceConfidenceKind(ComplianceRuleConfidence confidence) =>
    switch (confidence) {
      ComplianceRuleConfidence.verified => NxBadgeKind.success,
      ComplianceRuleConfidence.unverified => NxBadgeKind.neutral,
      ComplianceRuleConfidence.decisionSupport => NxBadgeKind.warning,
      ComplianceRuleConfidence.unknown => NxBadgeKind.warning,
    };

class ComplianceRulesScreen extends ConsumerStatefulWidget {
  const ComplianceRulesScreen({super.key});

  @override
  ConsumerState<ComplianceRulesScreen> createState() =>
      _ComplianceRulesScreenState();
}

class _ComplianceRulesScreenState extends ConsumerState<ComplianceRulesScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(complianceRulesControllerProvider);
    final controller = ref.read(complianceRulesControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NxPageHeader(
            title: 'Rechtsregeln',
            subtitle:
                'Was am Stichtag galt. Eine rückwirkende Korrektur muss das '
                'Recht ihres eigenen Zeitraums anwenden.',
            primaryAction: controller.canMutate
                ? FilledButton.icon(
                    key: const Key('compliance-rule-create'),
                    onPressed: () => _openForm(controller),
                    icon: const Icon(Icons.add),
                    label: const Text('Regel anlegen'),
                  )
                : null,
            secondaryActions: <Widget>[
              if (controller.canMutate)
                _ProposalMenu(onSelected: (p) => _openForm(controller, proposal: p)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ComplianceRulesState state,
    ComplianceRulesController controller,
  ) {
    switch (state.phase) {
      case ComplianceRulesPhase.idle:
      case ComplianceRulesPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('compliance-rules-loading')),
        );
      case ComplianceRulesPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('compliance-rules-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ?? 'Für die Rechtsregeln fehlt die Berechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case ComplianceRulesPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('compliance-rules-error'),
            title: 'Die Regeln konnten nicht geladen werden',
            // Never an empty list here: "nothing is recorded" is itself a
            // legal position, and a failed read must not be able to state one.
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case ComplianceRulesPhase.ready:
        return _ready(context, state, controller);
    }
  }

  Widget _ready(
    BuildContext context,
    ComplianceRulesState state,
    ComplianceRulesController controller,
  ) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    return ListView(
      key: const Key('compliance-rules-list'),
      children: <Widget>[
        _AsOfControl(state: state, controller: controller),
        const SizedBox(height: AppSpacing.md),
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Regeln am Stichtag',
              value: '${state.rules.length}',
              caption: 'in Kraft',
            ),
            NxKpiTile(
              label: 'Ungeprüft',
              value: '${state.unverifiedCount}',
              status: state.unverifiedCount > 0 ? semantic.warning : null,
              caption: 'noch niemand bestätigt',
            ),
            NxKpiTile(
              label: 'Entscheidung nötig',
              value: '${state.decisionSupportCount}',
              status: state.decisionSupportCount > 0 ? semantic.warning : null,
              caption: 'nie automatisch',
            ),
          ],
        ),
        if (state.actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('compliance-rules-action-message'),
            message: state.actionMessage!,
            kind: state.actionPhase == ComplianceRulesActionPhase.failed
                ? NxNoticeKind.error
                : NxNoticeKind.info,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (state.rules.isEmpty)
          NxCard(
            child: NxEmptyState(
              key: const Key('compliance-rules-empty'),
              title: 'Für diesen Stichtag ist keine Regel hinterlegt',
              description: controller.canMutate
                  ? 'Der Vorschlagskatalog füllt das Formular mit den '
                        'recherchierten Werten vor. Jede Regel wird einzeln '
                        'gelesen und gespeichert — nichts wird im Block '
                        'übernommen.'
                  : 'Es wurde noch nichts erfasst.',
              icon: Icons.gavel_outlined,
            ),
          )
        else
          for (final ComplianceRuleDto rule in state.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _RuleCard(
                rule: rule,
                canMutate: controller.canMutate,
                theme: theme,
                onEdit: () => _openForm(controller, existing: rule),
                onToggleVerified: () => controller.verify(
                  rule: rule,
                  verified: !rule.isVerified,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _openForm(
    ComplianceRulesController controller, {
    ComplianceRuleDto? existing,
    ComplianceRuleProposal? proposal,
  }) async {
    final result = await showComplianceRuleFormDialog(
      context,
      existing: existing,
      proposal: proposal,
    );
    if (result == null) {
      return;
    }
    await controller.upsert(
      ruleKey: result.ruleKey,
      validFrom: result.validFrom,
      validTo: result.validTo,
      value: result.value,
      sourceReference: result.sourceReference,
      unit: result.unit,
      note: result.note,
      decisionSupport: result.decisionSupport,
      existing: existing,
    );
  }
}

class _AsOfControl extends StatelessWidget {
  const _AsOfControl({required this.state, required this.controller});

  final ComplianceRulesState state;
  final ComplianceRulesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final DateTime? effective = state.effectiveDate;

    return NxCard(
      child: Row(
        children: <Widget>[
          const Icon(Icons.event_outlined, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              effective == null
                  ? 'Stichtag: heute'
                  // The date the server actually used, not the one the reader
                  // typed. When they asked for nothing the server chose, and
                  // implying otherwise would hide whose "today" it was.
                  : 'Stichtag: ${formatComplianceDate(effective)}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton.icon(
            key: const Key('compliance-rules-pick-date'),
            onPressed: () => _pick(context),
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            label: const Text('Stichtag ändern'),
          ),
          if (state.asOfDate != null)
            TextButton(
              key: const Key('compliance-rules-reset-date'),
              onPressed: () => controller.setAsOfDate(null),
              child: const Text('Heute'),
            ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: state.effectiveDate ?? DateTime.now(),
      // Wide enough to reach both a correction for an old accounting year and
      // a rule that takes effect next year.
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      await controller.setAsOfDate(picked);
    }
  }
}

class _ProposalMenu extends StatelessWidget {
  const _ProposalMenu({required this.onSelected});

  final void Function(ComplianceRuleProposal proposal) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ComplianceRuleProposal>(
      key: const Key('compliance-rule-proposals'),
      tooltip: 'Recherchierte Vorschläge',
      onSelected: onSelected,
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<ComplianceRuleProposal>>[
            for (final ComplianceRuleProposal proposal
                in complianceRuleProposals)
              PopupMenuItem<ComplianceRuleProposal>(
                value: proposal,
                child: Text(proposal.label),
              ),
          ],
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lightbulb_outline, size: 18),
            SizedBox(width: AppSpacing.xxs),
            Text('Vorschläge'),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.canMutate,
    required this.theme,
    required this.onEdit,
    required this.onToggleVerified,
  });

  final ComplianceRuleDto rule;
  final bool canMutate;
  final ThemeData theme;
  final VoidCallback onEdit;
  final VoidCallback onToggleVerified;

  @override
  Widget build(BuildContext context) {
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
                child: Text(rule.ruleKey, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: AppSpacing.xs),
              NxStatusBadge(
                label: complianceConfidenceLabel(rule),
                kind: complianceConfidenceKind(rule.confidence),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${formatComplianceDate(rule.validFrom)} – '
            '${rule.validTo == null ? 'offen' : formatComplianceDate(rule.validTo)}',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.xs),
          // Wrapped in its own scroll region: a three-part value is wide, and
          // a screen that scrolls sideways because of one card is worse than a
          // card that scrolls on its own.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              '${formatComplianceValue(rule.value)}'
              '${rule.unit == null ? '' : ' ${rule.unit}'}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('Quelle: ${rule.sourceReference}', style: muted),
          if (rule.note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(rule.note!, style: muted),
          ],
          if (rule.isVerified) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Bestätigt am '
              '${rule.verifiedAt == null ? '—' : formatComplianceDate(rule.verifiedAt)}',
              style: muted,
            ),
          ],
          if (rule.needsHumanDecision) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Wird vorgeschlagen, nie automatisch angewendet.',
              key: const Key('compliance-rule-decision-note'),
              style: muted,
            ),
          ],
          if (canMutate) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Bearbeiten'),
                ),
                // Absent, not disabled, for a rule the law leaves to
                // judgement. A greyed-out "confirm" invites asking why it is
                // greyed out; no button at all matches the fact that
                // confirming it is not a thing that exists.
                if (!rule.needsHumanDecision)
                  OutlinedButton.icon(
                    key: Key('compliance-rule-verify-${rule.id}'),
                    onPressed: onToggleVerified,
                    icon: Icon(
                      rule.isVerified
                          ? Icons.undo_outlined
                          : Icons.verified_outlined,
                      size: 18,
                    ),
                    label: Text(
                      rule.isVerified
                          ? 'Bestätigung zurückziehen'
                          : 'Bestätigen',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
