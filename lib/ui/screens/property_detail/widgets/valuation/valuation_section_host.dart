import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../features/valuation/application/valuation_case_controller.dart';
import '../../../../../features/identity_access/application/workspace_session_scope.dart';
import '../../../../../features/valuation/application/valuation_case_lookup.dart';
import '../../../../../features/valuation/application/valuation_repository.dart';
import '../../../../../features/valuation/domain/valuation_case.dart';
import '../../../../state/scenario_state.dart';
import 'valuation_section.dart';

/// Binds [ValuationSection] to the valuation contract for one scenario.
///
/// The section itself stays pure presentation; everything that needs a provider
/// — resolving the scenario's case, creating one, and the mutation callbacks —
/// lives here.
class ValuationSectionHost extends ConsumerWidget {
  const ValuationSectionHost({
    super.key,
    required this.scenarioId,
    this.propertyId,
    this.onJumpToFactor,
  });

  final String scenarioId;

  /// Null while the scenario's property is unknown — then no case can be
  /// created, and the empty state says so by simply not offering the action.
  final String? propertyId;

  final void Function(String factorId)? onJumpToFactor;

  ValuationScenarioRef get _scenarioRef =>
      (scenarioId: scenarioId, propertyId: propertyId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(valuationCaseForScenarioProvider(_scenarioRef));
    // A backend that cannot mutate is not offered a create action at all; the
    // empty state then simply states that there is no valuation yet.
    final canCreate =
        propertyId != null &&
        ref.watch(workspaceSessionScopeProvider).mutationsSupported;

    return lookup.when(
      loading: () => const ValuationSection(
        state: ValuationCaseState.loading(),
      ),
      error: (error, _) => ValuationSection(
        state: const ValuationCaseState(
          loadPhase: ValuationLoadPhase.error,
          message: 'Die Bewertung konnte nicht geladen werden.',
        ),
        onRetry: () =>
            ref.invalidate(valuationCaseForScenarioProvider(_scenarioRef)),
      ),
      data: (result) => switch (result) {
        ValuationCaseFound(:final valuationCaseId) => _CaseSection(
          valuationCaseId: valuationCaseId,
          onJumpToFactor: onJumpToFactor,
        ),
        ValuationCaseAbsent() => ValuationSection(
          state: const ValuationCaseState(loadPhase: ValuationLoadPhase.empty),
          onCreateCase: canCreate ? () => _createCase(context, ref) : null,
        ),
        ValuationCaseLookupForbidden(:final message) => ValuationSection(
          state: ValuationCaseState(
            loadPhase: ValuationLoadPhase.forbidden,
            message: message,
          ),
        ),
        ValuationCaseLookupFailed(:final message) => ValuationSection(
          state: ValuationCaseState(
            loadPhase: ValuationLoadPhase.error,
            message: message,
          ),
          onRetry: () =>
              ref.invalidate(valuationCaseForScenarioProvider(_scenarioRef)),
        ),
      },
    );
  }

  /// The scenario's own name titles the case. It comes from the scenario list
  /// the shell already loads; when that list is not ready the case still gets a
  /// truthful generic title rather than a placeholder that looks like data.
  String _title(WidgetRef ref) {
    final property = propertyId;
    if (property == null) return 'Bewertung zum Szenario';
    final scenarios = ref
        .read(scenariosByPropertyProvider(property))
        .valueOrNull;
    final match = scenarios
        ?.where((scenario) => scenario.id == scenarioId)
        .firstOrNull;
    return match?.name ?? 'Bewertung zum Szenario';
  }

  Future<void> _createCase(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(valuationCaseCreatorProvider)
        .create(
          scenarioId: scenarioId,
          propertyId: propertyId!,
          title: _title(ref),
        );
    if (result case ValuationRepositoryFailure(:final message)) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _CaseSection extends ConsumerWidget {
  const _CaseSection({required this.valuationCaseId, this.onJumpToFactor});

  final String valuationCaseId;
  final void Function(String factorId)? onJumpToFactor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = valuationCaseControllerProvider(valuationCaseId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    // A closed record offers no write affordances at all — the notice explains
    // why, instead of a button that is certain to fail.
    final isClosed =
        state.valuationCase?.status == ValuationCaseStatus.approved ||
        state.valuationCase?.status == ValuationCaseStatus.archived;
    final canWrite = controller.canManage && !isClosed;

    return ValuationSection(
      state: state,
      onRetry: controller.load,
      onPublish: canWrite ? () => controller.publishReport() : null,
      onApprove:
          controller.canApprove &&
              state.valuationCase?.status == ValuationCaseStatus.inReview
          ? () => _confirmApproval(context, controller)
          : null,
      onAcceptSuggestion: canWrite ? controller.acceptSuggestion : null,
      onJumpToFactor: onJumpToFactor,
    );
  }

  /// Approval is irreversible (`AGG-014`): the case becomes a record and the
  /// server refuses every later edit. Announcing that before the click is the
  /// point of the dialog.
  Future<void> _confirmApproval(
    BuildContext context,
    ValuationCaseController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bewertung freigeben?'),
        content: const Text(
          'Eine freigegebene Bewertung ist unveränderlich. Spätere Änderungen '
          'erfordern eine neue Bewertung.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Freigeben'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.transitionStatus(ValuationCaseStatus.approved);
    }
  }
}
