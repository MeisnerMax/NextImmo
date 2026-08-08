import 'package:flutter/material.dart';

import '../../../../../features/valuation/application/valuation_case_controller.dart';
import '../../../../../features/valuation/domain/valuation_case.dart';
import '../../../../../features/valuation/domain/valuation_factor.dart';
import '../../../../../features/valuation/domain/valuation_factor_catalog.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_status_badge.dart';

/// State of one workflow step. `done` is earned, never assumed: a step is green
/// because its condition holds, not because the user walked past it.
enum ValuationStepState { done, current, open, blocked }

class ValuationWorkflowStep {
  const ValuationWorkflowStep({
    required this.index,
    required this.title,
    required this.state,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final int index;
  final String title;
  final ValuationStepState state;

  /// What is still missing, or what the step concluded — never a bare status
  /// word.
  final String detail;

  final String? actionLabel;
  final VoidCallback? onAction;
}

/// The five-step valuation workflow (Welle 5, AP4).
///
/// It guides without gating: every step stays reachable, and step 3 is
/// explicitly usable while methods report "nicht ermittelbar" — the reconciled
/// value is then derived from the available methods and the rest is named. A
/// workflow that blocked on missing factors would push people to invent
/// numbers, which is the behaviour this whole rewrite removed.
class ValuationWorkflowStepper extends StatelessWidget {
  const ValuationWorkflowStepper({
    super.key,
    required this.state,
    this.onGoToFactors,
    this.onPublish,
    this.onSubmitForReview,
    this.onReturnToDraft,
    this.onApprove,
  });

  final ValuationCaseState state;
  final VoidCallback? onGoToFactors;
  final VoidCallback? onPublish;
  final VoidCallback? onSubmitForReview;
  final VoidCallback? onReturnToDraft;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final steps = buildSteps();
    return NxCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 5
              : constraints.maxWidth >= 700
              ? 2
              : 1;
          const spacing = 12.0;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: <Widget>[
              for (final step in steps)
                SizedBox(width: width, child: _StepTile(step: step)),
            ],
          );
        },
      ),
    );
  }

  /// Public so the same conditions can be asserted in tests without pumping a
  /// widget tree.
  List<ValuationWorkflowStep> buildSteps() {
    final valuationCase = state.valuationCase;
    final status = valuationCase?.status;
    final isClosed =
        status == ValuationCaseStatus.approved ||
        status == ValuationCaseStatus.archived;

    final factorsDone = state.missingFactors.isEmpty && state.liveReport != null;
    final report = state.detail?.report;
    final resultDone = report != null && !state.isReportStale;
    final reviewDone =
        status == ValuationCaseStatus.inReview || isClosed;
    final approved = status == ValuationCaseStatus.approved;

    return <ValuationWorkflowStep>[
      ValuationWorkflowStep(
        index: 1,
        title: 'Objekt & Art',
        state: valuationCase == null
            ? ValuationStepState.open
            : ValuationStepState.done,
        detail: valuationCase == null
            ? 'Noch keine Bewertung angelegt.'
            : '${valuationCase.kind.labelDe} · ${valuationCase.title}',
      ),
      ValuationWorkflowStep(
        index: 2,
        title: 'Faktoren',
        state: factorsDone
            ? ValuationStepState.done
            : (isClosed ? ValuationStepState.blocked : ValuationStepState.current),
        detail: _factorDetail(factorsDone),
        actionLabel: factorsDone ? null : 'Zu den Faktoren',
        onAction: isClosed ? null : onGoToFactors,
      ),
      ValuationWorkflowStep(
        index: 3,
        title: 'Ergebnis',
        state: resultDone
            ? ValuationStepState.done
            : (isClosed ? ValuationStepState.blocked : ValuationStepState.open),
        detail: switch ((report, state.isReportStale)) {
          (null, _) => 'Noch kein Bericht veröffentlicht.',
          (_, true) => 'Bericht beruht auf einem älteren Faktorstand.',
          _ => 'Bericht veröffentlicht.',
        },
        actionLabel: resultDone ? null : 'Bericht veröffentlichen',
        onAction: isClosed ? null : onPublish,
      ),
      ValuationWorkflowStep(
        index: 4,
        title: 'Prüfung',
        state: reviewDone
            ? ValuationStepState.done
            : (resultDone ? ValuationStepState.open : ValuationStepState.blocked),
        detail: switch (status) {
          ValuationCaseStatus.inReview => 'Liegt zur Prüfung.',
          ValuationCaseStatus.approved => 'Geprüft und freigegeben.',
          ValuationCaseStatus.archived => 'Archiviert.',
          _ => resultDone
              ? 'Bereit zur Prüfung.'
              : 'Erst nach einem veröffentlichten Bericht.',
        },
        actionLabel: status == ValuationCaseStatus.inReview
            ? 'Zurück in Bearbeitung'
            : (resultDone && !isClosed ? 'Zur Prüfung geben' : null),
        onAction: status == ValuationCaseStatus.inReview
            ? onReturnToDraft
            : (resultDone && !isClosed ? onSubmitForReview : null),
      ),
      ValuationWorkflowStep(
        index: 5,
        title: 'Freigabe',
        state: approved
            ? ValuationStepState.done
            : (reviewDone && !isClosed
                  ? ValuationStepState.open
                  : ValuationStepState.blocked),
        detail: approved
            ? 'Freigegeben — unveränderlich, Änderungen brauchen eine neue '
                  'Bewertung.'
            : 'Freigabe ist endgültig und erfordert die Berechtigung dafür.',
        actionLabel: approved || !reviewDone ? null : 'Freigeben',
        onAction: approved || !reviewDone ? null : onApprove,
      ),
    ];
  }

  String _factorDetail(bool done) {
    if (state.detail == null) return 'Noch keine Bewertung angelegt.';
    if (done) return 'Alle benötigten Faktoren liegen vor.';
    final missing = state.missingFactors.length;
    final open = ValuationFactorCatalog.groups
        .where(
          (group) => !group.isComplete(
            (id) =>
                state.detail!.factors.any(
                  (factor) =>
                      factor.factorId == id && factor.provenance.isUsable,
                ),
          ),
        )
        .length;
    return missing == 0
        ? '$open Verfahren noch unvollständig.'
        : '$missing Faktor(en) offen in $open Verfahren.';
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final ValuationWorkflowStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, kind) = switch (step.state) {
      ValuationStepState.done => ('erledigt', NxBadgeKind.success),
      ValuationStepState.current => ('offen', NxBadgeKind.warning),
      ValuationStepState.open => ('offen', NxBadgeKind.info),
      ValuationStepState.blocked => ('wartet', NxBadgeKind.neutral),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 12,
              backgroundColor: step.state == ValuationStepState.done
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                '${step.index}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: step.state == ValuationStepState.done
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(step.title, style: theme.textTheme.titleSmall),
            ),
          ],
        ),
        const SizedBox(height: 6),
        NxStatusBadge(label: label, kind: kind),
        const SizedBox(height: 6),
        Text(step.detail, style: theme.textTheme.bodySmall),
        // Only render an action that can actually run. A disabled button would
        // claim the step is the user's to advance when the backend or their
        // permissions say otherwise — the step's detail line says why instead.
        if (step.actionLabel != null && step.onAction != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: step.onAction,
              child: Text(step.actionLabel!),
            ),
          ),
      ],
    );
  }
}
