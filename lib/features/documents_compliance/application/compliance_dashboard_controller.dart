/// Screen-facing orchestration for the workspace compliance dashboard
/// (SCR-052, Phase 2, Wave 2, Arbeitspaket 2), following the pattern of
/// `PropertyDocumentsController`: explicit phases, a generation guard, and
/// every state the design system requires represented as data.
///
/// What makes this screen different from the other two document surfaces:
///
/// * **It derives nothing.** Every requirement state comes from the server's
///   `evaluate_workspace_document_requirements`; this controller only counts
///   rows for the KPI tiles. Counting a server-derived list is not a second
///   derivation — recomputing the states would be, and that is what `DUP-011`
///   forbids.
/// * **One call, not one per object.** The screen it replaces ran
///   `checkComplianceForEntity` once per property. The whole point of the
///   P2-D03 follow-up increment is that this is now a single round trip.
/// * **It never mutates.** So `versionConflict` and "read-only until migrated"
///   do not apply here; the surface a finding jumps *to* owns those.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../../portfolio_property/application/property_repository.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../domain/document_dto.dart';
import 'document_providers.dart';
import 'document_query_invalidation_source.dart';
import 'document_repository.dart';

const Object _unchanged = Object();

enum CompliancePhase { idle, loading, ready, empty, forbidden, error }

class ComplianceDashboardState {
  const ComplianceDashboardState({
    required this.phase,
    this.requirements = const <DocumentRequirementProjection>[],
    this.entityNames = const <String, String>{},
    this.scopedRuleCount = 0,
    this.onlyUnmet = false,
    this.directoryAvailable = false,
    this.directoryComplete = true,
    this.lastCheckedAt,
  });

  const ComplianceDashboardState.loading()
    : this(phase: CompliancePhase.loading);

  final CompliancePhase phase;
  final List<DocumentRequirementProjection> requirements;

  /// Object id → display name, read from the DOM-002 port. Empty when that port
  /// is not bound, in which case the table falls back to the id.
  final Map<String, String> entityNames;

  /// Rules this pass could not evaluate workspace-wide, reported by the server
  /// rather than dropped. Surfaced so the screen never implies full coverage.
  final int scopedRuleCount;
  final bool onlyUnmet;

  /// Whether the object directory could be read at all. False locally, where
  /// the migrated property port is not bound — objects that have neither a rule
  /// nor a document are then invisible, and the screen says so.
  final bool directoryAvailable;

  /// False when the directory was longer than [ComplianceDashboardController
  /// .maxDirectoryPages] pages, so coverage is partial.
  final bool directoryComplete;
  final DateTime? lastCheckedAt;

  int get outstandingCount =>
      requirements.where((row) => row.state.isOutstanding).length;

  int get expiringCount =>
      requirements
          .where((row) => row.state == DocumentRequirementState.expiring)
          .length;

  int get inReviewCount =>
      requirements
          .where(
            (row) =>
                row.state == DocumentRequirementState.pendingContent ||
                row.state == DocumentRequirementState.pendingVerification,
          )
          .length;

  int get satisfiedCount =>
      requirements
          .where((row) => row.state == DocumentRequirementState.satisfied)
          .length;

  /// Mandatory and unmet — the rows that actually block, as opposed to optional
  /// paperwork that is merely absent.
  int get blockingCount => requirements.where((row) => row.isBlocking).length;

  bool get hasCoverageGap => scopedRuleCount > 0 || !directoryComplete;

  ComplianceDashboardState copyWith({
    CompliancePhase? phase,
    List<DocumentRequirementProjection>? requirements,
    Map<String, String>? entityNames,
    int? scopedRuleCount,
    bool? onlyUnmet,
    bool? directoryAvailable,
    bool? directoryComplete,
    Object? lastCheckedAt = _unchanged,
  }) {
    return ComplianceDashboardState(
      phase: phase ?? this.phase,
      requirements: requirements ?? this.requirements,
      entityNames: entityNames ?? this.entityNames,
      scopedRuleCount: scopedRuleCount ?? this.scopedRuleCount,
      onlyUnmet: onlyUnmet ?? this.onlyUnmet,
      directoryAvailable: directoryAvailable ?? this.directoryAvailable,
      directoryComplete: directoryComplete ?? this.directoryComplete,
      lastCheckedAt:
          identical(lastCheckedAt, _unchanged)
              ? this.lastCheckedAt
              : lastCheckedAt as DateTime?,
    );
  }
}

class ComplianceDashboardController
    extends StateNotifier<ComplianceDashboardState> {
  ComplianceDashboardController({
    required RequirementPolicyRepository requirements,
    required WorkspaceSessionScope scope,
    PropertyRepository? propertyDirectory,
    DocumentQueryInvalidationSource? invalidationSource,
    DateTime Function()? clock,
  }) : _requirements = requirements,
       _scope = scope,
       _propertyDirectory = propertyDirectory,
       _invalidationSource = invalidationSource,
       _clock = clock ?? DateTime.now,
       super(const ComplianceDashboardState.loading());

  /// The dashboard is scoped to objects, per `04b`'s SCR-052 plan.
  static const DocumentLinkEntityType entityType =
      DocumentLinkEntityType.property;
  static const int directoryPageSize = 100;

  /// A bound on how much of the object directory is contributed in one call.
  /// Reaching it makes coverage partial, which the screen reports instead of
  /// silently truncating.
  static const int maxDirectoryPages = 10;

  final RequirementPolicyRepository _requirements;
  final WorkspaceSessionScope _scope;
  final PropertyRepository? _propertyDirectory;
  final DocumentQueryInvalidationSource? _invalidationSource;
  final DateTime Function() _clock;

  StreamSubscription<DocumentQueryInvalidation>? _invalidationSubscription;
  int _generation = 0;

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: CompliancePhase.idle,
        requirements: const <DocumentRequirementProjection>[],
      );
      return;
    }
    _subscribeToInvalidation(workspaceId);
    final generation = ++_generation;
    state = state.copyWith(phase: CompliancePhase.loading);

    final directory = await _loadDirectory(workspaceId);
    if (generation != _generation) {
      return;
    }

    final result = await _requirements.evaluateWorkspace(
      WorkspaceDocumentRequirementQuery(
        workspaceId: workspaceId,
        entityType: entityType,
        entityIds: directory.ids,
        onlyUnmet: state.onlyUnmet,
      ),
    );
    if (generation != _generation) {
      return;
    }

    switch (result) {
      case DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
        :final value,
      ):
        state = state.copyWith(
          phase:
              value.requirements.isEmpty
                  ? CompliancePhase.empty
                  : CompliancePhase.ready,
          requirements: value.requirements,
          scopedRuleCount: value.scopedRuleCount,
          entityNames: directory.names,
          directoryAvailable: directory.available,
          directoryComplete: directory.complete,
          lastCheckedAt: _clock(),
        );
      case DocumentRepositoryFailure<WorkspaceDocumentRequirements>(
        :final kind,
      ):
        state = state.copyWith(
          phase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? CompliancePhase.forbidden
                  : CompliancePhase.error,
          requirements: const <DocumentRequirementProjection>[],
          scopedRuleCount: 0,
        );
    }
  }

  Future<void> setOnlyUnmet(bool onlyUnmet) async {
    if (onlyUnmet == state.onlyUnmet) {
      return;
    }
    // Re-queried server-side rather than filtered here: the filter is part of
    // the projection, not a view over a partially loaded list.
    state = state.copyWith(onlyUnmet: onlyUnmet);
    await load();
  }

  /// Object ids and names from the DOM-002 port — ids and DTOs across a module
  /// boundary, which the module contract allows; its tables are never touched.
  /// The ids travel into the projection in one call so an object with neither a
  /// rule nor a document is still evaluated.
  Future<_ObjectDirectory> _loadDirectory(String workspaceId) async {
    final repository = _propertyDirectory;
    if (repository == null) {
      return const _ObjectDirectory(
        ids: <String>[],
        names: <String, String>{},
        available: false,
        complete: true,
      );
    }

    final ids = <String>[];
    final names = <String, String>{};
    String? cursor;
    for (var page = 0; page < maxDirectoryPages; page++) {
      final result = await repository.list(
        PropertyListQuery(
          workspaceId: workspaceId,
          page: PropertyPageRequest(limit: directoryPageSize, cursor: cursor),
        ),
      );
      if (result is! PropertyRepositorySuccess<PropertyPageResult>) {
        // A directory that cannot be read degrades coverage; it must not take
        // the whole compliance view into an error state.
        return _ObjectDirectory(
          ids: ids,
          names: names,
          available: ids.isNotEmpty,
          complete: false,
        );
      }
      for (final property in result.value.items) {
        ids.add(property.id);
        names[property.id] = property.name;
      }
      cursor = result.value.nextCursor;
      if (cursor == null) {
        return _ObjectDirectory(
          ids: ids,
          names: names,
          available: true,
          complete: true,
        );
      }
    }
    return _ObjectDirectory(
      ids: ids,
      names: names,
      available: true,
      complete: false,
    );
  }

  void _subscribeToInvalidation(String workspaceId) {
    final source = _invalidationSource;
    if (source == null || _invalidationSubscription != null) {
      return;
    }
    _invalidationSubscription = source
        .watchWorkspace(workspaceId: workspaceId)
        .listen((invalidation) {
          if (invalidation.workspaceId != _scope.workspaceId) {
            return;
          }
          unawaited(load());
        });
  }

  @override
  void dispose() {
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = null;
    super.dispose();
  }
}

class _ObjectDirectory {
  const _ObjectDirectory({
    required this.ids,
    required this.names,
    required this.available,
    required this.complete,
  });

  final List<String> ids;
  final Map<String, String> names;
  final bool available;
  final bool complete;
}

/// The migrated object port, or null where it is not bound.
///
/// `referencePropertyRepositoryProvider` is overridden only in cloud mode, so
/// reading it locally throws by design (fail closed). The compliance dashboard
/// treats an absent directory as reduced coverage rather than an error, and
/// says so on screen — hence the deliberate catch instead of a crash.
final complianceObjectDirectoryProvider = Provider<PropertyRepository?>((ref) {
  try {
    return ref.watch(referencePropertyRepositoryProvider);
  } on StateError {
    return null;
  }
});

final complianceDashboardControllerProvider = StateNotifierProvider.autoDispose<
  ComplianceDashboardController,
  ComplianceDashboardState
>((ref) {
  final controller = ComplianceDashboardController(
    requirements: ref.watch(requirementPolicyProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
    propertyDirectory: ref.watch(complianceObjectDirectoryProvider),
    invalidationSource: ref.watch(documentQueryInvalidationSourceProvider),
  );
  unawaited(controller.load());
  return controller;
});
