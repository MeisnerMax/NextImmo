/// Screen-facing orchestration for the workspace document registry
/// (DOCUMENTS-V2 increment B1): the `Typen` and `Pflichtregeln` tabs on the
/// existing `RequirementPolicyRepository` contract.
///
/// Two contract facts shape both controllers:
///
/// * **Everything is an upsert.** `upsert_document_type` keys on the type key,
///   `upsert_required_document` on the live rule identity (level, entity,
///   scope key, document type); neither takes an `expectedVersion`, and an
///   existing row is updated in place rather than rejected. So "create" and
///   "edit" are the same command, the client refuses a *create* that would
///   silently overwrite an existing row (the lists are complete, so this check
///   is honest), and there is no version-conflict path to render.
/// * **Nothing is deleted.** Types are deactivated (`is_active = false`, they
///   stay named on existing documents and rules); rules are retired
///   (`retired_at`, filtered out of every read — "history, not policy").
///
/// The B2 catalogue decision (curated default types / prefill) is blocked and
/// not pre-empted here: the registry starts empty and is filled by the
/// workspace.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/document_dto.dart';
import 'document_mutation_outcome.dart';
import 'document_providers.dart';
import 'document_repository.dart';

const Object _unchanged = Object();

enum DocumentRegistryPhase { idle, loading, ready, empty, forbidden, error }

enum DocumentRegistryActionPhase {
  idle,
  submitting,
  succeeded,
  forbidden,
  failed,
}

typedef DocumentRegistryIdFactory = String Function();

/// Client-side pattern mirror of the server rule for document type keys
/// (`upsert_document_type`: `^[a-z0-9]+(?:[._-][a-z0-9]+)*$`, 2–100 chars).
/// Only to fail fast with a German sentence; the server stays the authority.
final RegExp documentTypeKeyPattern = RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$');

/// Suggests a key from a display name the way the legacy registry did by
/// hand: lowercase, umlauts transliterated, everything else collapsed to `_`.
String suggestDocumentTypeKey(String name) {
  var value = name.trim().toLowerCase();
  const replacements = <String, String>{
    'ä': 'ae',
    'ö': 'oe',
    'ü': 'ue',
    'ß': 'ss',
    'é': 'e',
    'è': 'e',
    'à': 'a',
  };
  replacements.forEach((from, to) => value = value.replaceAll(from, to));
  value = value.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  value = value.replaceAll(RegExp(r'^_+|_+$'), '');
  if (value.length > 100) {
    value = value.substring(0, 100).replaceAll(RegExp(r'_+$'), '');
  }
  return value;
}

String? validateDocumentTypeKey(String? value) {
  final key = (value ?? '').trim();
  if (key.isEmpty) {
    return 'Pflichtfeld';
  }
  if (key.length < 2 || key.length > 100) {
    return 'Der Key braucht 2 bis 100 Zeichen.';
  }
  if (!documentTypeKeyPattern.hasMatch(key)) {
    return 'Nur Kleinbuchstaben, Ziffern sowie . _ - zwischen Zeichen.';
  }
  return null;
}

// --- Typen -------------------------------------------------------------------

class DocumentTypesState {
  const DocumentTypesState({
    required this.phase,
    this.types = const <DocumentTypeDto>[],
    this.showInactive = false,
    this.query = '',
    this.actionPhase = DocumentRegistryActionPhase.idle,
    this.actionMessage,
    this.message,
  });

  const DocumentTypesState.loading()
    : this(phase: DocumentRegistryPhase.loading);

  final DocumentRegistryPhase phase;

  /// The complete registry, active and inactive — `listTypes` is not
  /// paginated, which is what makes the client-side search and sort below
  /// legitimate (Foundation §7).
  final List<DocumentTypeDto> types;
  final bool showInactive;
  final String query;
  final DocumentRegistryActionPhase actionPhase;
  final String? actionMessage;
  final String? message;

  bool get hasFilter => query.trim().isNotEmpty || showInactive;

  List<DocumentTypeDto> get visibleTypes {
    final needle = query.trim().toLowerCase();
    final visible =
        types.where((type) {
          if (!showInactive && !type.isActive) {
            return false;
          }
          if (needle.isEmpty) {
            return true;
          }
          return type.name.toLowerCase().contains(needle) ||
              type.key.toLowerCase().contains(needle);
        }).toList();
    visible.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List<DocumentTypeDto>.unmodifiable(visible);
  }

  DocumentTypesState copyWith({
    DocumentRegistryPhase? phase,
    List<DocumentTypeDto>? types,
    bool? showInactive,
    String? query,
    DocumentRegistryActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
    Object? message = _unchanged,
  }) {
    return DocumentTypesState(
      phase: phase ?? this.phase,
      types: types ?? this.types,
      showInactive: showInactive ?? this.showInactive,
      query: query ?? this.query,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class DocumentTypesController extends StateNotifier<DocumentTypesState> {
  DocumentTypesController({
    required RequirementPolicyRepository registry,
    required WorkspaceSessionScope scope,
    DocumentRegistryIdFactory? idFactory,
  }) : _registry = registry,
       _scope = scope,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const DocumentTypesState.loading());

  static const String managePermission = 'document.manage';

  final RequirementPolicyRepository _registry;
  final WorkspaceSessionScope _scope;
  final DocumentRegistryIdFactory _idFactory;
  int _generation = 0;

  bool get canManage =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _scope.authorization.can(managePermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: DocumentRegistryPhase.idle,
        types: const <DocumentTypeDto>[],
        message: null,
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: DocumentRegistryPhase.loading, message: null);
    final result = await _registry.listTypes(
      workspaceId: workspaceId,
      activeOnly: false,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case DocumentRepositorySuccess<List<DocumentTypeDto>>(:final value):
        state = state.copyWith(
          phase:
              value.isEmpty
                  ? DocumentRegistryPhase.empty
                  : DocumentRegistryPhase.ready,
          types: value,
          message: null,
        );
      case DocumentRepositoryFailure<List<DocumentTypeDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? DocumentRegistryPhase.forbidden
                  : DocumentRegistryPhase.error,
          types: const <DocumentTypeDto>[],
          message: message,
        );
    }
  }

  void setShowInactive(bool value) {
    if (value != state.showInactive) {
      state = state.copyWith(showInactive: value);
    }
  }

  void setQuery(String value) {
    if (value != state.query) {
      state = state.copyWith(query: value);
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: DocumentRegistryActionPhase.idle,
      actionMessage: null,
    );
  }

  /// Creates or edits a type. [isNew] guards against the upsert's silent
  /// update of an existing key — the server would happily "create" over it.
  Future<DocumentMutationOutcome> saveType(
    DocumentTypeDraft draft, {
    required bool isNew,
    String? reason,
  }) async {
    final denied = _guard();
    if (denied != null) {
      return denied;
    }
    if (isNew && state.types.any((type) => type.key == draft.key)) {
      return DocumentMutationRejected(
        kind: DocumentRepositoryFailureKind.validationFailed,
        message:
            'Der Key „${draft.key}" ist in diesem Arbeitsbereich bereits '
            'vergeben. Bearbeite den bestehenden Dokumenttyp.',
      );
    }
    state = state.copyWith(
      actionPhase: DocumentRegistryActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _registry.upsertType(
      UpsertDocumentTypeCommand(
        context: _commandContext(reason: reason),
        draft: draft,
      ),
    );
    switch (result) {
      case DocumentRepositorySuccess<DocumentTypeDto>(:final value):
        final next = <DocumentTypeDto>[
          for (final type in state.types)
            if (type.key != value.key) type,
          value,
        ];
        state = state.copyWith(
          phase: DocumentRegistryPhase.ready,
          types: next,
          actionPhase: DocumentRegistryActionPhase.succeeded,
          actionMessage:
              isNew
                  ? 'Dokumenttyp angelegt.'
                  : value.isActive
                  ? 'Dokumenttyp gespeichert.'
                  : 'Dokumenttyp deaktiviert.',
        );
        return const DocumentMutationSucceeded();
      case DocumentRepositoryFailure<DocumentTypeDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          actionPhase: _phaseForFailure(kind),
          actionMessage: message,
        );
        return DocumentMutationRejected(kind: kind, message: message);
    }
  }

  DocumentMutationRejected? _guard() =>
      _guardScope(_scope, managePermission, (phase, message) {
        state = state.copyWith(actionPhase: phase, actionMessage: message);
      });

  DocumentCommandContext _commandContext({String? reason}) =>
      _contextFor(_scope, _idFactory, reason);
}

// --- Pflichtregeln -----------------------------------------------------------

class RequiredDocumentsState {
  const RequiredDocumentsState({
    required this.phase,
    this.entityType = DocumentLinkEntityType.property,
    this.rules = const <RequiredDocumentDto>[],
    this.types = const <DocumentTypeDto>[],
    this.actionPhase = DocumentRegistryActionPhase.idle,
    this.actionMessage,
    this.message,
  });

  const RequiredDocumentsState.loading()
    : this(phase: DocumentRegistryPhase.loading);

  final DocumentRegistryPhase phase;

  /// The leading, server-side scope: `listRequirements` requires a level.
  final DocumentLinkEntityType entityType;

  /// Live rules of [entityType] (retired ones never arrive).
  final List<RequiredDocumentDto> rules;

  /// Complete type registry, inactive included, so a rule on a deactivated
  /// type is still named.
  final List<DocumentTypeDto> types;
  final DocumentRegistryActionPhase actionPhase;
  final String? actionMessage;
  final String? message;

  String typeName(String documentTypeId) {
    for (final type in types) {
      if (type.id == documentTypeId) {
        return type.name;
      }
    }
    return '—';
  }

  DocumentTypeDto? typeById(String documentTypeId) {
    for (final type in types) {
      if (type.id == documentTypeId) {
        return type;
      }
    }
    return null;
  }

  /// Active types of the current level — the choices a rule may reference.
  List<DocumentTypeDto> get activeTypesForLevel {
    final active =
        types
            .where((type) => type.isActive && type.entityType == entityType)
            .toList();
    active.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<DocumentTypeDto>.unmodifiable(active);
  }

  /// Default order: document type name, then scope (workspace-wide first,
  /// then object types, then instances). Sorting a complete list is allowed.
  List<RequiredDocumentDto> get sortedRules {
    final sorted = List<RequiredDocumentDto>.of(rules);
    int scopeRank(RequiredDocumentDto rule) =>
        rule.entityId != null ? 2 : (rule.scopeKey != null ? 1 : 0);
    sorted.sort((a, b) {
      final byType = typeName(
        a.documentTypeId,
      ).toLowerCase().compareTo(typeName(b.documentTypeId).toLowerCase());
      if (byType != 0) {
        return byType;
      }
      final byScope = scopeRank(a).compareTo(scopeRank(b));
      if (byScope != 0) {
        return byScope;
      }
      return (a.scopeKey ?? a.entityId ?? '').compareTo(
        b.scopeKey ?? b.entityId ?? '',
      );
    });
    return List<RequiredDocumentDto>.unmodifiable(sorted);
  }

  RequiredDocumentsState copyWith({
    DocumentRegistryPhase? phase,
    DocumentLinkEntityType? entityType,
    List<RequiredDocumentDto>? rules,
    List<DocumentTypeDto>? types,
    DocumentRegistryActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
    Object? message = _unchanged,
  }) {
    return RequiredDocumentsState(
      phase: phase ?? this.phase,
      entityType: entityType ?? this.entityType,
      rules: rules ?? this.rules,
      types: types ?? this.types,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class RequiredDocumentsController
    extends StateNotifier<RequiredDocumentsState> {
  RequiredDocumentsController({
    required RequirementPolicyRepository registry,
    required WorkspaceSessionScope scope,
    DocumentRegistryIdFactory? idFactory,
  }) : _registry = registry,
       _scope = scope,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const RequiredDocumentsState.loading());

  static const String managePermission = 'document.manage';

  final RequirementPolicyRepository _registry;
  final WorkspaceSessionScope _scope;
  final DocumentRegistryIdFactory _idFactory;
  int _generation = 0;

  bool get canManage =>
      _scope.mutationsSupported &&
      _scope.isResolved &&
      _scope.authorization.can(managePermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: DocumentRegistryPhase.idle,
        rules: const <RequiredDocumentDto>[],
        message: null,
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: DocumentRegistryPhase.loading, message: null);
    final results = await Future.wait(<Future<Object>>[
      _registry.listRequirements(
        workspaceId: workspaceId,
        entityType: state.entityType,
      ),
      _registry.listTypes(workspaceId: workspaceId, activeOnly: false),
    ]);
    if (generation != _generation) {
      return;
    }
    final rulesResult =
        results.first as DocumentRepositoryResult<List<RequiredDocumentDto>>;
    final typesResult =
        results.last as DocumentRepositoryResult<List<DocumentTypeDto>>;
    // A missing type registry degrades names to '—'; it never takes the rule
    // list into an error state.
    final types = switch (typesResult) {
      DocumentRepositorySuccess<List<DocumentTypeDto>>(:final value) => value,
      DocumentRepositoryFailure<List<DocumentTypeDto>>() => state.types,
    };
    switch (rulesResult) {
      case DocumentRepositorySuccess<List<RequiredDocumentDto>>(:final value):
        state = state.copyWith(
          phase:
              value.isEmpty
                  ? DocumentRegistryPhase.empty
                  : DocumentRegistryPhase.ready,
          rules: value,
          types: types,
          message: null,
        );
      case DocumentRepositoryFailure<List<RequiredDocumentDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase:
              kind == DocumentRepositoryFailureKind.forbidden
                  ? DocumentRegistryPhase.forbidden
                  : DocumentRegistryPhase.error,
          rules: const <RequiredDocumentDto>[],
          types: types,
          message: message,
        );
    }
  }

  Future<void> setEntityType(DocumentLinkEntityType entityType) async {
    if (entityType == state.entityType) {
      return;
    }
    state = state.copyWith(entityType: entityType);
    await load();
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: DocumentRegistryActionPhase.idle,
      actionMessage: null,
    );
  }

  /// Creates or edits a rule. A *create* whose identity already lives is
  /// refused here, because the upsert would update that rule in place and the
  /// user would never learn that "Anlegen" edited something else.
  Future<DocumentMutationOutcome> saveRule(
    RequiredDocumentDraft draft, {
    required bool isNew,
    String? reason,
  }) async {
    final denied = _guard();
    if (denied != null) {
      return denied;
    }
    if (isNew && state.rules.any((rule) => _sameIdentity(rule, draft))) {
      return const DocumentMutationRejected(
        kind: DocumentRepositoryFailureKind.validationFailed,
        message:
            'Für diese Kombination aus Ebene, Dokumenttyp und Geltung '
            'existiert bereits eine Regel. Bearbeite sie in der Liste.',
      );
    }
    return _upsert(
      draft,
      reason: reason,
      successMessage:
          isNew ? 'Pflichtregel angelegt.' : 'Pflichtregel gespeichert.',
    );
  }

  /// Retires a rule: the upsert with `retired = true`, carrying the rule's own
  /// values so the audited old/new snapshot shows only the retirement.
  Future<DocumentMutationOutcome> retireRule(
    RequiredDocumentDto rule, {
    String? reason,
  }) async {
    final denied = _guard();
    if (denied != null) {
      return denied;
    }
    return _upsert(
      RequiredDocumentDraft(
        entityType: rule.entityType,
        documentTypeId: rule.documentTypeId,
        entityId: rule.entityId,
        scopeKey: rule.scopeKey,
        isMandatory: rule.isMandatory,
        dueAt: rule.dueAt,
        validityMonths: rule.validityMonths,
        ownerUserId: rule.ownerUserId,
        note: rule.note,
        requested: rule.requestedAt != null,
        waived: rule.waivedAt != null,
        waiverReason: rule.waivedAt != null ? rule.waiverReason : null,
        retired: true,
      ),
      reason: reason,
      successMessage: 'Pflichtregel zurückgezogen.',
    );
  }

  Future<DocumentMutationOutcome> _upsert(
    RequiredDocumentDraft draft, {
    required String successMessage,
    String? reason,
  }) async {
    state = state.copyWith(
      actionPhase: DocumentRegistryActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _registry.upsertRequirement(
      UpsertRequiredDocumentCommand(
        context: _commandContext(reason: reason),
        draft: draft,
      ),
    );
    switch (result) {
      case DocumentRepositorySuccess<RequiredDocumentDto>(:final value):
        final next = <RequiredDocumentDto>[
          for (final rule in state.rules)
            if (rule.id != value.id) rule,
          if (!value.isRetired && value.entityType == state.entityType) value,
        ];
        state = state.copyWith(
          phase:
              next.isEmpty
                  ? DocumentRegistryPhase.empty
                  : DocumentRegistryPhase.ready,
          rules: next,
          actionPhase: DocumentRegistryActionPhase.succeeded,
          actionMessage: successMessage,
        );
        return const DocumentMutationSucceeded();
      case DocumentRepositoryFailure<RequiredDocumentDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          actionPhase: _phaseForFailure(kind),
          actionMessage: message,
        );
        return DocumentMutationRejected(kind: kind, message: message);
    }
  }

  static bool _sameIdentity(
    RequiredDocumentDto rule,
    RequiredDocumentDraft draft,
  ) {
    return !rule.isRetired &&
        rule.entityType == draft.entityType &&
        rule.documentTypeId == draft.documentTypeId &&
        rule.entityId == draft.entityId &&
        rule.scopeKey == draft.scopeKey;
  }

  DocumentMutationRejected? _guard() =>
      _guardScope(_scope, managePermission, (phase, message) {
        state = state.copyWith(actionPhase: phase, actionMessage: message);
      });

  DocumentCommandContext _commandContext({String? reason}) =>
      _contextFor(_scope, _idFactory, reason);
}

// --- shared ------------------------------------------------------------------

DocumentRegistryActionPhase _phaseForFailure(
  DocumentRepositoryFailureKind kind,
) {
  return switch (kind) {
    DocumentRepositoryFailureKind.forbidden =>
      DocumentRegistryActionPhase.forbidden,
    _ => DocumentRegistryActionPhase.failed,
  };
}

DocumentMutationRejected? _guardScope(
  WorkspaceSessionScope scope,
  String permission,
  void Function(DocumentRegistryActionPhase phase, String message) publish,
) {
  if (!scope.mutationsSupported) {
    const message =
        'Die Registry ist in dieser Sitzung schreibgeschützt. Für Änderungen '
        'ist eine MFA-bestätigte Sitzung (AAL2) erforderlich.';
    publish(DocumentRegistryActionPhase.forbidden, message);
    return const DocumentMutationRejected(message: message);
  }
  if (!scope.isResolved || !scope.authorization.can(permission)) {
    const message = 'Für diese Aktion fehlt die Berechtigung.';
    publish(DocumentRegistryActionPhase.forbidden, message);
    return const DocumentMutationRejected(message: message);
  }
  return null;
}

DocumentCommandContext _contextFor(
  WorkspaceSessionScope scope,
  DocumentRegistryIdFactory idFactory,
  String? reason,
) {
  final trimmed = reason?.trim();
  return DocumentCommandContext(
    workspaceId: scope.workspaceId!,
    actorId: scope.actorId!,
    mutationId: idFactory(),
    correlationId: idFactory(),
    reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
  );
}

final documentTypesControllerProvider = StateNotifierProvider.autoDispose<
  DocumentTypesController,
  DocumentTypesState
>((ref) {
  final controller = DocumentTypesController(
    registry: ref.watch(requirementPolicyProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});

final requiredDocumentsControllerProvider = StateNotifierProvider.autoDispose<
  RequiredDocumentsController,
  RequiredDocumentsState
>((ref) {
  final controller = RequiredDocumentsController(
    registry: ref.watch(requirementPolicyProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});
