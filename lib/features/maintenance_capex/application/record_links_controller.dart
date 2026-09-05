/// The evidence and the follow-up work attached to one operations record
/// (`PROPERTY-OPERATIONS-LINKS-01`).
///
/// A ticket without its invoice and its follow-up task is only half a record.
/// Both already exist as contracts — `document_links` and `PlatformEntityRef`
/// have known `maintenance_ticket` and `capex_project` since P2-D03 and P2-D04
/// — so this is a read that was missing, not a capability that was.
///
/// Two independently permissioned zones, loaded independently: a membership
/// that may read documents but not tasks sees the documents and is told about
/// the other, rather than losing both.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../documents_compliance/application/document_providers.dart';
import '../../documents_compliance/application/document_repository.dart';
import '../../documents_compliance/domain/document_dto.dart';
import '../../identity_access/application/workspace_session_scope.dart';
import '../../platform_audit_jobs/application/platform_providers.dart';
import '../../platform_audit_jobs/application/platform_repository.dart';
import '../../platform_audit_jobs/domain/platform_entity_type.dart';
import '../../platform_audit_jobs/domain/task_dto.dart';

enum RecordLinksZonePhase { idle, loading, ready, empty, forbidden, error }

/// Which operations record the links belong to.
class RecordLinksRef {
  const RecordLinksRef({required this.entityType, required this.entityId});

  final PlatformEntityType entityType;
  final String entityId;

  DocumentLinkEntityType get documentEntityType =>
      switch (entityType) {
        PlatformEntityType.maintenanceTicket =>
          DocumentLinkEntityType.maintenanceTicket,
        PlatformEntityType.capexProject => DocumentLinkEntityType.capexProject,
        _ => DocumentLinkEntityType.property,
      };

  @override
  bool operator ==(Object other) =>
      other is RecordLinksRef &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

class RecordLinksState {
  const RecordLinksState({
    this.documentsPhase = RecordLinksZonePhase.idle,
    this.documents = const <DocumentDto>[],
    this.documentsMessage,
    this.tasksPhase = RecordLinksZonePhase.idle,
    this.tasks = const <TaskDto>[],
    this.tasksMessage,
  });

  final RecordLinksZonePhase documentsPhase;
  final List<DocumentDto> documents;
  final String? documentsMessage;

  final RecordLinksZonePhase tasksPhase;
  final List<TaskDto> tasks;
  final String? tasksMessage;

  RecordLinksState copyWith({
    RecordLinksZonePhase? documentsPhase,
    List<DocumentDto>? documents,
    String? documentsMessage,
    RecordLinksZonePhase? tasksPhase,
    List<TaskDto>? tasks,
    String? tasksMessage,
  }) {
    return RecordLinksState(
      documentsPhase: documentsPhase ?? this.documentsPhase,
      documents: documents ?? this.documents,
      documentsMessage: documentsMessage,
      tasksPhase: tasksPhase ?? this.tasksPhase,
      tasks: tasks ?? this.tasks,
      tasksMessage: tasksMessage,
    );
  }
}

class RecordLinksController extends StateNotifier<RecordLinksState> {
  RecordLinksController({
    required this.ref,
    required DocumentRepository documents,
    required TaskRepository tasks,
    required WorkspaceSessionScope scope,
  }) : _documents = documents,
       _tasks = tasks,
       _scope = scope,
       super(const RecordLinksState());

  static const String documentReadPermission = 'document.read';
  static const String taskReadPermission = 'task.read';

  /// How many of each are shown beside the record. This is a summary next to a
  /// detail, not a second list surface: the full ones live in their own
  /// domains, one drilldown away.
  static const int pageSize = 5;

  final RecordLinksRef ref;
  final DocumentRepository _documents;
  final TaskRepository _tasks;
  final WorkspaceSessionScope _scope;

  Future<void> load() async {
    await Future.wait(<Future<void>>[_loadDocuments(), _loadTasks()]);
  }

  Future<void> _loadDocuments() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    if (!_scope.permissions.contains(documentReadPermission)) {
      state = state.copyWith(documentsPhase: RecordLinksZonePhase.forbidden);
      return;
    }
    state = state.copyWith(documentsPhase: RecordLinksZonePhase.loading);
    final result = await _documents.search(
      DocumentListQuery(
        workspaceId: workspaceId,
        entityType: ref.documentEntityType,
        entityId: ref.entityId,
        page: const DocumentPageRequest(limit: pageSize),
      ),
    );
    switch (result) {
      case DocumentRepositorySuccess<DocumentPageResult>(:final value):
        state = state.copyWith(
          documentsPhase:
              value.items.isEmpty
                  ? RecordLinksZonePhase.empty
                  : RecordLinksZonePhase.ready,
          documents: value.items,
        );
      case DocumentRepositoryFailure<DocumentPageResult>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          documentsPhase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? RecordLinksZonePhase.forbidden
                  : RecordLinksZonePhase.error,
          documents: const <DocumentDto>[],
          documentsMessage: message,
        );
    }
  }

  Future<void> _loadTasks() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    if (!_scope.permissions.contains(taskReadPermission)) {
      state = state.copyWith(tasksPhase: RecordLinksZonePhase.forbidden);
      return;
    }
    state = state.copyWith(tasksPhase: RecordLinksZonePhase.loading);
    final result = await _tasks.searchTasks(
      TaskListQuery(
        workspaceId: workspaceId,
        entity: PlatformEntityRef(type: ref.entityType, id: ref.entityId),
        page: const PlatformPageRequest(limit: pageSize),
      ),
    );
    switch (result) {
      case PlatformRepositorySuccess<PlatformPageResult<TaskDto>>(:final value):
        state = state.copyWith(
          tasksPhase:
              value.items.isEmpty
                  ? RecordLinksZonePhase.empty
                  : RecordLinksZonePhase.ready,
          tasks: value.items,
        );
      case PlatformRepositoryFailure<PlatformPageResult<TaskDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          tasksPhase:
              kind == PlatformRepositoryFailureKind.forbidden
                  ? RecordLinksZonePhase.forbidden
                  : RecordLinksZonePhase.error,
          tasks: const <TaskDto>[],
          tasksMessage: message,
        );
    }
  }
}

final recordLinksControllerProvider = StateNotifierProvider.autoDispose
    .family<RecordLinksController, RecordLinksState, RecordLinksRef>((
      providerRef,
      linkRef,
    ) {
      final controller = RecordLinksController(
        ref: linkRef,
        documents: providerRef.watch(documentRepositoryProvider),
        tasks: providerRef.watch(taskRepositoryProvider),
        scope: providerRef.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
