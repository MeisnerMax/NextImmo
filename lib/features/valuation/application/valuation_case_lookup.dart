/// Resolves the valuation case of a scenario (Welle 5, AP1).
///
/// The analysis screen knows a scenario; the valuation contract is keyed by
/// case. This lookup bridges the two through the contract's own
/// `scenarioId` filter — no extra backend read invented for it.
///
/// The result is a sealed type rather than a nullable id on purpose: "no case
/// yet", "not allowed to look" and "the lookup failed" lead to three different
/// screen states, and collapsing them into `null` would show an invitation to
/// create a case to somebody who may not read them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/valuation_case.dart';
import '../domain/valuation_case_dto.dart';
import '../domain/valuation_case_templates.dart';
import '../domain/valuation_factor.dart';
import 'valuation_case_controller.dart' show ValuationPermissions;
import 'valuation_providers.dart';
import 'valuation_repository.dart';

sealed class ValuationCaseLookup {
  const ValuationCaseLookup();
}

class ValuationCaseFound extends ValuationCaseLookup {
  const ValuationCaseFound(this.valuationCaseId);

  final String valuationCaseId;
}

/// The scenario has no valuation case yet — the one state that offers creating
/// one.
class ValuationCaseAbsent extends ValuationCaseLookup {
  const ValuationCaseAbsent();
}

class ValuationCaseLookupForbidden extends ValuationCaseLookup {
  const ValuationCaseLookupForbidden(this.message);

  final String message;
}

class ValuationCaseLookupFailed extends ValuationCaseLookup {
  const ValuationCaseLookupFailed(this.message);

  final String message;
}

/// Identifies the scenario to look up. The property travels with it because
/// the local backend can only enumerate per property (`ScenarioRepository`
/// lists by property, so its projection needs the owner to find anything) —
/// leaving it out would make every local scenario look like it had no
/// valuation at all.
typedef ValuationScenarioRef = ({String scenarioId, String? propertyId});

final valuationCaseForScenarioProvider = FutureProvider.autoDispose
    .family<ValuationCaseLookup, ValuationScenarioRef>((ref, scenario) async {
      final scope = ref.watch(workspaceSessionScopeProvider);
      final workspaceId = scope.workspaceId;
      if (workspaceId == null ||
          !scope.permissions.contains(ValuationPermissions.read)) {
        return const ValuationCaseLookupForbidden(
          'Keine Berechtigung für Bewertungen.',
        );
      }

      final result = await ref
          .watch(valuationCaseRepositoryProvider)
          .searchValuationCases(
            ValuationCaseListQuery(
              workspaceId: workspaceId,
              propertyId: scenario.propertyId,
              scenarioId: scenario.scenarioId,
              includeArchived: true,
              page: const ValuationPageRequest(limit: 1),
            ),
          );

      return switch (result) {
        ValuationRepositorySuccess(:final value) =>
          value.items.isEmpty
              ? const ValuationCaseAbsent()
              : ValuationCaseFound(value.items.first.id),
        ValuationRepositoryFailure(
          kind: ValuationRepositoryFailureKind.forbidden,
          :final message,
        ) =>
          ValuationCaseLookupForbidden(message),
        ValuationRepositoryFailure(:final message) => ValuationCaseLookupFailed(
          message,
        ),
      };
    });

/// Creates the scenario's valuation case and refreshes the lookup.
///
/// Deliberately minimal: title and kind come from the scenario, factors stay
/// empty. A freshly created case therefore reports every method as
/// "nicht ermittelbar" — which is the truthful starting point, not a defect.
class ValuationCaseCreator {
  const ValuationCaseCreator(this._ref, {String Function()? idFactory})
    : _idFactory = idFactory;

  final Ref _ref;
  final String Function()? _idFactory;

  /// Creates a case from a [ValuationCaseTemplate]: the template decides which
  /// methods start enabled and how they are weighted, and may seed reference
  /// values — as suggestions, which is why seeding is allowed at all.
  ///
  /// [scenarioId] is optional: a case created from the work queue belongs to a
  /// property, not necessarily to a legacy scenario.
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createFromTemplate({
    required String propertyId,
    required String title,
    required ValuationCaseTemplate template,
    String? scenarioId,
    List<ValuationFactor> suggestedFactors = const <ValuationFactor>[],
  }) async {
    final scope = _ref.read(workspaceSessionScopeProvider);
    if (!scope.isResolved || !scope.mutationsSupported) {
      return const ValuationRepositoryFailure(
        kind: ValuationRepositoryFailureKind.unsupportedByBackend,
        message:
            'Im lokalen Bestand schreibgeschützt, bis die Bewertung migriert '
            'ist.',
      );
    }

    final newId = _idFactory ?? () => const Uuid().v4();
    final result = await _ref
        .read(valuationCaseRepositoryProvider)
        .createValuationCase(
          CreateValuationCaseCommand(
            context: ValuationCommandContext(
              workspaceId: scope.workspaceId!,
              actorId: scope.actorId!,
              mutationId: newId(),
              correlationId: newId(),
              reason: 'Bewertung aus Vorlage „${template.headline}" angelegt',
            ),
            propertyId: propertyId,
            scenarioId: scenarioId,
            title: title,
            kind: template.kind,
            dcfTerminal: template.dcfTerminal,
            enabledMethods: template.enabledMethods,
            weightOverrides: template.weights,
            factors: suggestedFactors
                .map(
                  (factor) => ValuationFactorDto.fromDomain(
                    // The server assigns the id; the payload carries the
                    // factors, not their parent.
                    caseId: '',
                    factor: factor,
                  ),
                )
                .toList(growable: false),
          ),
        );

    if (result is ValuationRepositorySuccess<ValuationCaseDetail> &&
        scenarioId != null) {
      _ref.invalidate(
        valuationCaseForScenarioProvider((
          scenarioId: scenarioId,
          propertyId: propertyId,
        )),
      );
    }
    return result;
  }

  Future<ValuationRepositoryResult<ValuationCaseDetail>> create({
    required String scenarioId,
    required String propertyId,
    required String title,
    ValuationCaseKind kind = ValuationCaseKind.holding,
  }) async {
    final scope = _ref.read(workspaceSessionScopeProvider);
    if (!scope.isResolved || !scope.mutationsSupported) {
      return const ValuationRepositoryFailure(
        kind: ValuationRepositoryFailureKind.unsupportedByBackend,
        message:
            'Im lokalen Bestand schreibgeschützt, bis die Bewertung migriert '
            'ist.',
      );
    }

    final newId = _idFactory ?? () => const Uuid().v4();
    final result = await _ref
        .read(valuationCaseRepositoryProvider)
        .createValuationCase(
          CreateValuationCaseCommand(
            context: ValuationCommandContext(
              workspaceId: scope.workspaceId!,
              actorId: scope.actorId!,
              mutationId: newId(),
              correlationId: newId(),
              reason: 'Bewertung zum Szenario angelegt',
            ),
            propertyId: propertyId,
            scenarioId: scenarioId,
            title: title,
            kind: kind,
          ),
        );

    if (result is ValuationRepositorySuccess<ValuationCaseDetail>) {
      _ref.invalidate(
        valuationCaseForScenarioProvider((
          scenarioId: scenarioId,
          propertyId: propertyId,
        )),
      );
    }
    return result;
  }
}

final valuationCaseCreatorProvider = Provider<ValuationCaseCreator>(
  ValuationCaseCreator.new,
);
