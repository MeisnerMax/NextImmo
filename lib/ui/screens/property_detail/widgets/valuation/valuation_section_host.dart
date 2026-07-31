import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../features/valuation/application/valuation_case_controller.dart';
import '../../../../../features/identity_access/application/workspace_session_scope.dart';
import '../../../../../features/valuation/application/valuation_case_lookup.dart';
import '../../../../../features/valuation/application/valuation_providers.dart';
import '../../../../../features/valuation/application/valuation_variant_group.dart';
import '../../../../../features/valuation/application/valuation_repository.dart';
import '../../../../../features/valuation/domain/valuation_case.dart';
import '../../../../../features/valuation/domain/valuation_case_dto.dart';
import '../../../../state/scenario_state.dart';
import 'valuation_factors_section.dart';
import 'valuation_section.dart';
import 'valuation_variant_bar.dart';
import 'valuation_workflow_stepper.dart';

/// Renders the variant group of the open case. It stays out of the way when a
/// case stands alone: one tile, plus the action that would create a sibling.
class _VariantBar extends ConsumerWidget {
  const _VariantBar({
    required this.state,
    required this.activeCaseId,
    required this.canWrite,
    required this.onSelect,
    required this.onCreateVariant,
  });

  final ValuationCaseState state;
  final String activeCaseId;
  final bool canWrite;
  final void Function(ValuationCaseDto valuationCase) onSelect;
  final VoidCallback onCreateVariant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuationCase = state.valuationCase;
    if (valuationCase == null) return const SizedBox.shrink();

    final groupId = valuationCase.variantGroupId;
    final entries = groupId == null
        ? const AsyncValue<List<ValuationVariantEntry>>.data(
            <ValuationVariantEntry>[],
          )
        : ref.watch(
            valuationVariantGroupProvider((
              propertyId: valuationCase.propertyId,
              groupId: groupId,
            )),
          );

    return ValuationVariantBar(
      entries: entries.valueOrNull ?? const <ValuationVariantEntry>[],
      activeCaseId: activeCaseId,
      onSelect: onSelect,
      onCreateVariant: canWrite ? onCreateVariant : null,
    );
  }
}

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
          state: ValuationCaseState(
            loadPhase: ValuationLoadPhase.empty,
            // Without a create path the empty state has to say why, otherwise
            // the screen is a dead end that looks like a missing feature.
            message: canCreate
                ? null
                : 'Der lokale Bestand kann Bewertungen nur lesen — zum '
                      'Anlegen die App im Supabase-Modus starten.',
          ),
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

class _CaseSection extends ConsumerStatefulWidget {
  const _CaseSection({required this.valuationCaseId, this.onJumpToFactor});

  final String valuationCaseId;
  final void Function(String factorId)? onJumpToFactor;

  @override
  ConsumerState<_CaseSection> createState() => _CaseSectionState();
}

class _CaseSectionState extends ConsumerState<_CaseSection> {
  /// The factor a missing-value reason pointed at. Held here because the
  /// results and the entry form are two widgets that have to agree on it.
  String? _focusFactorId;

  /// The variant currently open, when the user switched away from the case the
  /// scenario lookup resolved.
  String? _selectedVariantCaseId;

  /// Anchor of the entry form. "Zu den Faktoren" scrolls to *this* rather than
  /// relying on a focused factor: there is not always one to focus (a method
  /// can be unavailable for a non-factor reason), and tapping twice with the
  /// same factor would otherwise do nothing at all.
  final GlobalKey _factorsAnchor = GlobalKey();

  void _goToFactors() {
    final missing = ref
        .read(valuationCaseControllerProvider(
          _selectedVariantCaseId ?? widget.valuationCaseId,
        ))
        .missingFactors
        .firstOrNull
        ?.factorId;
    setState(() => _focusFactorId = missing ?? _focusFactorId);

    final anchor = _factorsAnchor.currentContext;
    if (anchor != null) {
      Scrollable.ensureVisible(
        anchor,
        duration: kThemeAnimationDuration,
        alignment: 0.1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final valuationCaseId = _selectedVariantCaseId ?? widget.valuationCaseId;
    final provider = valuationCaseControllerProvider(valuationCaseId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    // The Vergleichswertverfahren runs on the property's comparables. They are
    // handed to the engine as they arrive; until then the method reports how
    // many suitable comps are still missing, which is the honest state rather
    // than a hidden method.
    final propertyId = state.valuationCase?.propertyId;
    if (propertyId != null) {
      final comparables = ref.watch(valuationComparablesProvider(propertyId));
      final loaded = comparables.valueOrNull;
      if (loaded != null && loaded.length != state.comparables.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.setComparables(loaded);
        });
      }
    }

    // A closed record offers no write affordances at all — the notice explains
    // why, instead of a button that is certain to fail.
    final isClosed =
        state.valuationCase?.status == ValuationCaseStatus.approved ||
        state.valuationCase?.status == ValuationCaseStatus.archived;
    final canWrite = controller.canManage && !isClosed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ValuationWorkflowStepper(
          state: state,
          onGoToFactors: _goToFactors,
          onPublish: canWrite ? () => controller.publishReport() : null,
          onSubmitForReview: canWrite
              ? () => controller.transitionStatus(
                  ValuationCaseStatus.inReview,
                  reason: 'Zur Prüfung gegeben',
                )
              : null,
          onReturnToDraft: canWrite
              ? () => controller.transitionStatus(
                  ValuationCaseStatus.draft,
                  reason: 'Zurück in Bearbeitung',
                )
              : null,
          onApprove: controller.canApprove
              ? () => _confirmApproval(context, controller)
              : null,
        ),
        const SizedBox(height: 16),
        _VariantBar(
          state: state,
          activeCaseId: valuationCaseId,
          canWrite: canWrite,
          onSelect: (selected) =>
              setState(() => _selectedVariantCaseId = selected.id),
          onCreateVariant: () => _createVariant(context, controller, state),
        ),
        const SizedBox(height: 16),
        // Publish and approve live in the stepper, which owns the workflow —
        // offering the same two actions twice on one screen would only make it
        // ambiguous which one is "the" step.
        ValuationSection(
          state: state,
          onRetry: controller.load,
          onAcceptSuggestion: canWrite ? controller.acceptSuggestion : null,
          onJumpToFactor: (factorId) {
            setState(() => _focusFactorId = factorId);
            widget.onJumpToFactor?.call(factorId);
          },
        ),
        const SizedBox(height: 24),
        ValuationFactorsSection(
          key: _factorsAnchor,
          state: state,
          focusFactorId: _focusFactorId,
          onSave: canWrite
              ? (changed) => controller.saveFactors(
                  changed,
                  reason: 'Faktoren erfasst',
                )
              : null,
          onAcceptSuggestion: canWrite ? controller.acceptSuggestion : null,
          onClearFactor: canWrite
              ? (factorId) => controller.saveFactors(
                  const <ValuationFactorDto>[],
                  removeFactorIds: <String>[factorId],
                  reason: 'Faktor entfernt',
                )
              : null,
        ),
      ],
    );
  }

  /// Asks for the variant's name, then copies the case. The copy is a draft
  /// with the same factors and no report — the dialog says so, because a
  /// variant that looked pre-computed would invite trusting a number nobody
  /// derived for it.
  Future<void> _createVariant(
    BuildContext context,
    ValuationCaseController controller,
    ValuationCaseState state,
  ) async {
    final valuationCase = state.valuationCase;
    if (valuationCase == null) return;

    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Variante anlegen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Die Variante übernimmt Faktoren und Verfahren, aber keinen '
              'Bericht — sie wird eigenständig gerechnet und veröffentlicht.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name der Variante',
                hintText: 'z. B. Konservativ',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(labelController.text),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    labelController.dispose();
    if (label == null || label.trim().isEmpty) return;

    final created = await controller.createVariant(variantLabel: label.trim());
    if (!mounted || created == null) return;
    setState(() => _selectedVariantCaseId = created);
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
