import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'authorization_port.dart';
import 'membership_admin_repository.dart';

const _unchanged = Object();

/// Tab-zone phase vocabulary of the Mitglieder admin screen (Foundation §11):
/// the Mitglieder, Einladungen and Rollen tabs each hold their own phase so a
/// broken read on one tab never blocks the others.
enum MembersTabPhase { idle, loading, ready, empty, forbidden, error }

/// Own-invitations zone: the signed-in user's pending invitations, readable by
/// anyone (an invited user has no workspace access yet). Stays functional
/// until package B moves the accept surface onto the workspace gate.
enum MembersPendingPhase { loading, ready, empty, error }

enum MembersActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  validationFailed,
  forbidden,
  failed,
}

/// Classified result of one admin mutation, returned to the calling surface
/// so dialogs can keep input alive (conflict banner, inline validation)
/// while SnackBar feedback stays with the screen's `ref.listen`.
enum MembersActionResultKind {
  success,
  validationFailed,
  lastSecurityManager,
  versionConflict,
  forbidden,
  failed,
}

class MembersActionOutcome {
  const MembersActionOutcome({
    required this.kind,
    required this.message,
    this.conflict,
  }) : assert(
         kind == MembersActionResultKind.versionConflict
             ? conflict != null
             : conflict == null,
       );

  final MembersActionResultKind kind;

  /// German, user-presentable message for this outcome.
  final String message;
  final MembershipVersionConflict? conflict;

  bool get isSuccess => kind == MembersActionResultKind.success;
}

/// Identifies the workspace/actor a [MembersAdminController] is bound to.
/// [workspaceId] is null when the user has no active workspace (e.g. an
/// invited-only user): the own-invitations zone still loads, the admin zones
/// stay idle. Value equality keeps the Riverpod family stable across rebuilds.
class MembersAdminScope {
  MembersAdminScope({
    required this.workspaceId,
    required this.actorId,
    required Set<String> permissions,
    required this.canMutate,
  }) : permissions = Set<String>.unmodifiable(permissions);

  final String? workspaceId;
  final String actorId;
  final Set<String> permissions;

  /// Whether the session is at AAL2 (membership mutations are AAL2-gated
  /// server-side; the UI reflects the gate rather than letting a doomed call
  /// through).
  final bool canMutate;

  @override
  bool operator ==(Object other) {
    return other is MembersAdminScope &&
        other.workspaceId == workspaceId &&
        other.actorId == actorId &&
        other.canMutate == canMutate &&
        other.permissions.length == permissions.length &&
        other.permissions.containsAll(permissions);
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    actorId,
    canMutate,
    Object.hashAllUnordered(permissions),
  );
}

class MembersAdminState {
  const MembersAdminState({
    required this.directoryPhase,
    required this.invitationsPhase,
    required this.rolesPhase,
    required this.pendingPhase,
    this.activityPhase = MembersTabPhase.loading,
    this.actionPhase = MembersActionPhase.idle,
    this.directory = const <WorkspaceMemberDirectoryEntry>[],
    this.roles = const <WorkspaceRole>[],
    this.roleCapabilities = const <WorkspaceRoleCapability>[],
    this.invitations = const <MembershipInvitation>[],
    this.pending = const <PendingInvitationEntry>[],
    this.activity = const <MembershipAuditEvent>[],
    this.activityHasMore = false,
    this.activityLoadingMore = false,
    this.activityCursor,
    this.refreshing = false,
    this.actionMessage,
    this.actionConflict,
  });

  const MembersAdminState.loading()
    : this(
        directoryPhase: MembersTabPhase.loading,
        invitationsPhase: MembersTabPhase.loading,
        rolesPhase: MembersTabPhase.loading,
        pendingPhase: MembersPendingPhase.loading,
      );

  final MembersTabPhase directoryPhase;
  final MembersTabPhase invitationsPhase;
  final MembersTabPhase rolesPhase;
  final MembersPendingPhase pendingPhase;

  /// Aktivität tab (A2): membership audit feed, read via `audit.read`.
  final MembersTabPhase activityPhase;
  final MembersActionPhase actionPhase;
  final List<WorkspaceMemberDirectoryEntry> directory;
  final List<WorkspaceRole> roles;
  final List<WorkspaceRoleCapability> roleCapabilities;
  final List<MembershipInvitation> invitations;
  final List<PendingInvitationEntry> pending;
  final List<MembershipAuditEvent> activity;
  final bool activityHasMore;
  final bool activityLoadingMore;
  final MembershipAuditCursor? activityCursor;

  /// True while a background "Aktualisieren" pass runs; visible data stays.
  final bool refreshing;
  final String? actionMessage;
  final MembershipVersionConflict? actionConflict;

  MembersAdminState copyWith({
    MembersTabPhase? directoryPhase,
    MembersTabPhase? invitationsPhase,
    MembersTabPhase? rolesPhase,
    MembersPendingPhase? pendingPhase,
    MembersTabPhase? activityPhase,
    MembersActionPhase? actionPhase,
    List<WorkspaceMemberDirectoryEntry>? directory,
    List<WorkspaceRole>? roles,
    List<WorkspaceRoleCapability>? roleCapabilities,
    List<MembershipInvitation>? invitations,
    List<PendingInvitationEntry>? pending,
    List<MembershipAuditEvent>? activity,
    bool? activityHasMore,
    bool? activityLoadingMore,
    Object? activityCursor = _unchanged,
    bool? refreshing,
    Object? actionMessage = _unchanged,
    Object? actionConflict = _unchanged,
  }) {
    return MembersAdminState(
      directoryPhase: directoryPhase ?? this.directoryPhase,
      invitationsPhase: invitationsPhase ?? this.invitationsPhase,
      rolesPhase: rolesPhase ?? this.rolesPhase,
      pendingPhase: pendingPhase ?? this.pendingPhase,
      activityPhase: activityPhase ?? this.activityPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      directory: directory ?? this.directory,
      roles: roles ?? this.roles,
      roleCapabilities: roleCapabilities ?? this.roleCapabilities,
      invitations: invitations ?? this.invitations,
      pending: pending ?? this.pending,
      activity: activity ?? this.activity,
      activityHasMore: activityHasMore ?? this.activityHasMore,
      activityLoadingMore: activityLoadingMore ?? this.activityLoadingMore,
      activityCursor:
          identical(activityCursor, _unchanged)
              ? this.activityCursor
              : activityCursor as MembershipAuditCursor?,
      refreshing: refreshing ?? this.refreshing,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
      actionConflict:
          identical(actionConflict, _unchanged)
              ? this.actionConflict
              : actionConflict as MembershipVersionConflict?,
    );
  }
}

typedef MembersIdFactory = String Function();

class MembersAdminController extends StateNotifier<MembersAdminState> {
  MembersAdminController({
    required MembershipAdminRepository repository,
    required String actorId,
    required AuthorizationPort authorization,
    required bool canMutate,
    String? workspaceId,
    MembersIdFactory? idFactory,
  }) : _repository = repository,
       _actorId = actorId,
       _authorization = authorization,
       _canMutate = canMutate,
       _workspaceId = workspaceId,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const MembersAdminState.loading());

  static const manageMembersPermission = 'security.manage';
  static const readRolesPermission = 'workspace.read';
  static const readAuditPermission = 'audit.read';
  static const activityPageSize = 50;

  static const _aal2Message =
      'Für Mitglieder-Änderungen ist Multi-Faktor-Authentifizierung (AAL2) '
      'erforderlich.';
  static const _acceptAal2Message =
      'Zum Annehmen einer Einladung ist Multi-Faktor-Authentifizierung (AAL2) '
      'erforderlich.';
  static const _capabilityMessage =
      'Deine Workspace-Rolle kann keine Mitglieder verwalten.';
  static const lastSecurityManagerMessage =
      'Diese Person ist die letzte Person mit Sicherheitsverwaltung in diesem '
      'Workspace. Übertrage die Berechtigung zuerst an jemand anderen.';

  final MembershipAdminRepository _repository;
  final String _actorId;
  final AuthorizationPort _authorization;
  final bool _canMutate;
  final String? _workspaceId;
  final MembersIdFactory _idFactory;

  int _directoryGeneration = 0;
  int _invitationsGeneration = 0;
  int _rolesGeneration = 0;
  int _pendingGeneration = 0;
  int _activityGeneration = 0;

  bool get canManageMembers =>
      _workspaceId != null && _authorization.can(manageMembersPermission);

  bool get canReadRoles =>
      _workspaceId != null && _authorization.can(readRolesPermission);

  bool get canReadAudit =>
      _workspaceId != null && _authorization.can(readAuditPermission);

  bool get canMutate => _canMutate;

  Future<void> load() {
    return Future.wait(<Future<void>>[
      reloadPending(),
      reloadDirectory(),
      reloadInvitations(),
      reloadRoles(),
      reloadActivity(),
    ]);
  }

  /// "Aktualisieren": reloads every zone without blanking visible data
  /// (Foundation §11 — background refresh never replaces content with a
  /// skeleton).
  Future<void> refreshAll() async {
    state = state.copyWith(refreshing: true);
    await Future.wait(<Future<void>>[
      reloadPending(background: true),
      reloadDirectory(background: true),
      reloadInvitations(background: true),
      reloadRoles(background: true),
      reloadActivity(background: true),
    ]);
    if (!mounted) {
      return;
    }
    state = state.copyWith(refreshing: false);
  }

  Future<void> reloadDirectory({bool background = false}) async {
    final generation = ++_directoryGeneration;
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        directoryPhase: MembersTabPhase.idle,
        directory: const <WorkspaceMemberDirectoryEntry>[],
      );
      return;
    }
    if (!canManageMembers) {
      state = state.copyWith(
        directoryPhase: MembersTabPhase.forbidden,
        directory: const <WorkspaceMemberDirectoryEntry>[],
      );
      return;
    }
    final keepVisible =
        background && state.directoryPhase == MembersTabPhase.ready;
    if (!keepVisible) {
      state = state.copyWith(directoryPhase: MembersTabPhase.loading);
    }
    final result = await _repository.listMemberDirectory(
      workspaceId: workspaceId,
    );
    if (!mounted || generation != _directoryGeneration) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<List<WorkspaceMemberDirectoryEntry>>():
        state = state.copyWith(
          directoryPhase:
              result.value.isEmpty
                  ? MembersTabPhase.empty
                  : MembersTabPhase.ready,
          directory: result.value,
        );
      case MembershipAdminFailure<List<WorkspaceMemberDirectoryEntry>>():
        if (keepVisible) {
          return;
        }
        state = state.copyWith(
          directoryPhase:
              result.kind == MembershipAdminFailureKind.forbidden
                  ? MembersTabPhase.forbidden
                  : MembersTabPhase.error,
          directory: const <WorkspaceMemberDirectoryEntry>[],
        );
    }
  }

  Future<void> reloadInvitations({bool background = false}) async {
    final generation = ++_invitationsGeneration;
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        invitationsPhase: MembersTabPhase.idle,
        invitations: const <MembershipInvitation>[],
      );
      return;
    }
    if (!canManageMembers) {
      state = state.copyWith(
        invitationsPhase: MembersTabPhase.forbidden,
        invitations: const <MembershipInvitation>[],
      );
      return;
    }
    final keepVisible =
        background && state.invitationsPhase == MembersTabPhase.ready;
    if (!keepVisible) {
      state = state.copyWith(invitationsPhase: MembersTabPhase.loading);
    }
    final result = await _repository.listInvitations(workspaceId: workspaceId);
    if (!mounted || generation != _invitationsGeneration) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<List<MembershipInvitation>>():
        state = state.copyWith(
          invitationsPhase:
              result.value.isEmpty
                  ? MembersTabPhase.empty
                  : MembersTabPhase.ready,
          invitations: result.value,
        );
      case MembershipAdminFailure<List<MembershipInvitation>>():
        if (keepVisible) {
          return;
        }
        state = state.copyWith(
          invitationsPhase:
              result.kind == MembershipAdminFailureKind.forbidden
                  ? MembersTabPhase.forbidden
                  : MembersTabPhase.error,
          invitations: const <MembershipInvitation>[],
        );
    }
  }

  /// Roles-tab data: role list plus the role→capability catalog. Fails closed
  /// client-side without `workspace.read` (the RLS gate of both tables) so the
  /// tab shows an honest forbidden state instead of silently empty lists.
  Future<void> reloadRoles({bool background = false}) async {
    final generation = ++_rolesGeneration;
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        rolesPhase: MembersTabPhase.idle,
        roles: const <WorkspaceRole>[],
        roleCapabilities: const <WorkspaceRoleCapability>[],
      );
      return;
    }
    if (!canReadRoles) {
      state = state.copyWith(
        rolesPhase: MembersTabPhase.forbidden,
        roles: const <WorkspaceRole>[],
        roleCapabilities: const <WorkspaceRoleCapability>[],
      );
      return;
    }
    final keepVisible = background && state.rolesPhase == MembersTabPhase.ready;
    if (!keepVisible) {
      state = state.copyWith(rolesPhase: MembersTabPhase.loading);
    }
    final results = await Future.wait<Object>(<Future<Object>>[
      _repository.listRoles(workspaceId: workspaceId),
      _repository.listRolePermissions(workspaceId: workspaceId),
    ]);
    if (!mounted || generation != _rolesGeneration) {
      return;
    }
    final rolesResult =
        results[0] as MembershipAdminResult<List<WorkspaceRole>>;
    final capabilitiesResult =
        results[1] as MembershipAdminResult<List<WorkspaceRoleCapability>>;
    if (rolesResult is MembershipAdminFailure<List<WorkspaceRole>> ||
        capabilitiesResult
            is MembershipAdminFailure<List<WorkspaceRoleCapability>>) {
      if (keepVisible) {
        return;
      }
      state = state.copyWith(
        rolesPhase: MembersTabPhase.error,
        roles: const <WorkspaceRole>[],
        roleCapabilities: const <WorkspaceRoleCapability>[],
      );
      return;
    }
    final roles =
        (rolesResult as MembershipAdminSuccess<List<WorkspaceRole>>).value;
    final capabilities =
        (capabilitiesResult
                as MembershipAdminSuccess<List<WorkspaceRoleCapability>>)
            .value;
    state = state.copyWith(
      rolesPhase: roles.isEmpty ? MembersTabPhase.empty : MembersTabPhase.ready,
      roles: roles,
      roleCapabilities: capabilities,
    );
  }

  Future<void> reloadPending({bool background = false}) async {
    final generation = ++_pendingGeneration;
    final keepVisible =
        background && state.pendingPhase == MembersPendingPhase.ready;
    if (!keepVisible) {
      state = state.copyWith(pendingPhase: MembersPendingPhase.loading);
    }
    final result = await _repository.listMyPendingInvitations();
    if (!mounted || generation != _pendingGeneration) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<List<PendingInvitationEntry>>():
        state = state.copyWith(
          pendingPhase:
              result.value.isEmpty
                  ? MembersPendingPhase.empty
                  : MembersPendingPhase.ready,
          pending: result.value,
        );
      case MembershipAdminFailure<List<PendingInvitationEntry>>():
        if (keepVisible) {
          return;
        }
        state = state.copyWith(
          pendingPhase: MembersPendingPhase.error,
          pending: const <PendingInvitationEntry>[],
        );
    }
  }

  /// First page of the Aktivität feed (A2). Fails closed client-side without
  /// `audit.read` — the RLS gate of `audit_events` filters to empty below it,
  /// and an empty list must never impersonate a permission boundary.
  Future<void> reloadActivity({bool background = false}) async {
    final generation = ++_activityGeneration;
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        activityPhase: MembersTabPhase.idle,
        activity: const <MembershipAuditEvent>[],
        activityHasMore: false,
        activityLoadingMore: false,
        activityCursor: null,
      );
      return;
    }
    if (!canReadAudit) {
      state = state.copyWith(
        activityPhase: MembersTabPhase.forbidden,
        activity: const <MembershipAuditEvent>[],
        activityHasMore: false,
        activityLoadingMore: false,
        activityCursor: null,
      );
      return;
    }
    final keepVisible =
        background && state.activityPhase == MembersTabPhase.ready;
    if (!keepVisible) {
      state = state.copyWith(activityPhase: MembersTabPhase.loading);
    }
    final result = await _repository.listMembershipAuditEvents(
      workspaceId: workspaceId,
      limit: activityPageSize,
    );
    if (!mounted || generation != _activityGeneration) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<MembershipAuditPage>():
        final page = result.value;
        state = state.copyWith(
          activityPhase:
              page.events.isEmpty
                  ? MembersTabPhase.empty
                  : MembersTabPhase.ready,
          activity: page.events,
          activityHasMore: page.nextCursor != null,
          activityLoadingMore: false,
          activityCursor: page.nextCursor,
        );
      case MembershipAdminFailure<MembershipAuditPage>():
        if (keepVisible) {
          return;
        }
        state = state.copyWith(
          activityPhase: MembersTabPhase.error,
          activity: const <MembershipAuditEvent>[],
          activityHasMore: false,
          activityLoadingMore: false,
          activityCursor: null,
        );
    }
  }

  /// Next keyset page of the Aktivität feed ("Weitere laden"). Appends
  /// id-deduplicated so a page boundary can never repeat an event.
  Future<void> loadMoreActivity() async {
    final workspaceId = _workspaceId;
    final cursor = state.activityCursor;
    if (workspaceId == null ||
        cursor == null ||
        !canReadAudit ||
        state.activityLoadingMore ||
        state.activityPhase != MembersTabPhase.ready) {
      return;
    }
    final generation = _activityGeneration;
    state = state.copyWith(activityLoadingMore: true);
    final result = await _repository.listMembershipAuditEvents(
      workspaceId: workspaceId,
      limit: activityPageSize,
      before: cursor,
    );
    if (!mounted || generation != _activityGeneration) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<MembershipAuditPage>():
        final page = result.value;
        final knownIds = state.activity.map((event) => event.id).toSet();
        final appended = <MembershipAuditEvent>[
          ...state.activity,
          ...page.events.where((event) => !knownIds.contains(event.id)),
        ];
        state = state.copyWith(
          activity: appended,
          activityHasMore: page.nextCursor != null,
          activityLoadingMore: false,
          activityCursor: page.nextCursor,
        );
      case MembershipAdminFailure<MembershipAuditPage>():
        // The visible feed stays; the affordance simply becomes tappable
        // again for a retry.
        state = state.copyWith(activityLoadingMore: false);
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: MembersActionPhase.idle,
      actionMessage: null,
      actionConflict: null,
    );
  }

  Future<MembersActionOutcome> invite({
    required String email,
    required String roleId,
    String? reason,
  }) async {
    final gate = _gateOutcome();
    if (gate != null) {
      return gate;
    }
    return _runMutation<InviteOutcome>(
      () => _repository.invite(
        InviteMemberCommand(
          context: _context(_workspaceId!, reason: reason),
          email: email,
          roleId: roleId,
        ),
      ),
      successMessage:
          (outcome) =>
              outcome.member != null
                  ? 'Einladung angelegt. $email ist jetzt als eingeladenes Mitglied '
                      'im Mitglieder-Tab sichtbar.'
                  : 'Einladung angelegt. $email sieht sie nach der Anmeldung in '
                      'NexImmo.',
      reloadOnSuccess:
          () => Future.wait(<Future<void>>[
            reloadDirectory(background: true),
            reloadInvitations(background: true),
          ]),
    );
  }

  Future<MembersActionOutcome> changeRole({
    required String membershipId,
    required String newRoleId,
    required int expectedVersion,
    String? reason,
  }) async {
    final gate = _gateOutcome();
    if (gate != null) {
      return gate;
    }
    return _runMutation<WorkspaceMember>(
      () => _repository.changeRole(
        ChangeMembershipRoleCommand(
          context: _context(_workspaceId!, reason: reason),
          membershipId: membershipId,
          newRoleId: newRoleId,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage: (_) => 'Rolle aktualisiert.',
      reloadOnSuccess: () => reloadDirectory(background: true),
    );
  }

  Future<MembersActionOutcome> updateStatus({
    required String membershipId,
    required MembershipStatus newStatus,
    required int expectedVersion,
    String? reason,
  }) async {
    final gate = _gateOutcome();
    if (gate != null) {
      return gate;
    }
    return _runMutation<WorkspaceMember>(
      () => _repository.updateStatus(
        UpdateMembershipStatusCommand(
          context: _context(_workspaceId!, reason: reason),
          membershipId: membershipId,
          newStatus: newStatus,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage:
          (_) => switch (newStatus) {
            MembershipStatus.suspended => 'Mitglied suspendiert.',
            MembershipStatus.active => 'Mitglied reaktiviert.',
            MembershipStatus.revoked => 'Zugriff entzogen.',
            MembershipStatus.invited => 'Mitglied aktualisiert.',
          },
      reloadOnSuccess: () => reloadDirectory(background: true),
    );
  }

  Future<MembersActionOutcome> revokeInvitation({
    required String invitationId,
    required int expectedVersion,
    String? reason,
  }) async {
    final gate = _gateOutcome();
    if (gate != null) {
      return gate;
    }
    return _runMutation<MembershipInvitation>(
      () => _repository.revokeInvitation(
        RevokeInvitationCommand(
          context: _context(_workspaceId!, reason: reason),
          invitationId: invitationId,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage: (_) => 'Einladung widerrufen.',
      reloadOnSuccess: () => reloadInvitations(background: true),
    );
  }

  /// Accepts one of the signed-in user's own pending invitations. Unlike the
  /// admin mutations this does not require `security.manage` (the invitee acts
  /// on their own row), but it is still AAL2-gated server-side.
  Future<MembersActionOutcome> acceptOwnInvitation(
    PendingInvitationEntry entry,
  ) async {
    if (!_canMutate) {
      const outcome = MembersActionOutcome(
        kind: MembersActionResultKind.forbidden,
        message: _acceptAal2Message,
      );
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage: outcome.message,
        actionConflict: null,
      );
      return outcome;
    }
    return _runMutation<WorkspaceMember>(
      () => _repository.accept(
        AcceptInvitationCommand(context: _context(entry.workspaceId)),
      ),
      successMessage:
          (_) =>
              'Einladung für ${entry.workspaceName} angenommen. Öffne den '
              'Workspace anschließend erneut.',
      reloadOnSuccess:
          () => Future.wait(<Future<void>>[
            reloadPending(background: true),
            reloadDirectory(background: true),
            reloadInvitations(background: true),
          ]),
    );
  }

  MembershipCommandContext _context(String workspaceId, {String? reason}) {
    final trimmedReason = reason?.trim();
    return MembershipCommandContext(
      workspaceId: workspaceId,
      actorId: _actorId,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
      reason:
          (trimmedReason == null || trimmedReason.isEmpty)
              ? null
              : trimmedReason,
    );
  }

  MembersActionOutcome? _gateOutcome() {
    if (!_canMutate) {
      const outcome = MembersActionOutcome(
        kind: MembersActionResultKind.forbidden,
        message: _aal2Message,
      );
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage: outcome.message,
        actionConflict: null,
      );
      return outcome;
    }
    if (!canManageMembers) {
      const outcome = MembersActionOutcome(
        kind: MembersActionResultKind.forbidden,
        message: _capabilityMessage,
      );
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage: outcome.message,
        actionConflict: null,
      );
      return outcome;
    }
    return null;
  }

  Future<MembersActionOutcome> _runMutation<T>(
    Future<MembershipAdminResult<T>> Function() run, {
    required String Function(T value) successMessage,
    required Future<void> Function() reloadOnSuccess,
  }) async {
    state = state.copyWith(
      actionPhase: MembersActionPhase.submitting,
      actionMessage: null,
      actionConflict: null,
    );
    final result = await run();
    if (!mounted) {
      return _outcomeForResult(result, successMessage);
    }
    final outcome = _outcomeForResult(result, successMessage);
    state = state.copyWith(
      actionPhase: _phaseForOutcome(outcome.kind),
      actionMessage: outcome.message,
      actionConflict: outcome.conflict,
    );
    if (outcome.kind == MembersActionResultKind.success ||
        outcome.kind == MembersActionResultKind.versionConflict) {
      await reloadOnSuccess();
    }
    return outcome;
  }

  MembersActionOutcome _outcomeForResult<T>(
    MembershipAdminResult<T> result,
    String Function(T value) successMessage,
  ) {
    switch (result) {
      case MembershipAdminSuccess<T>():
        return MembersActionOutcome(
          kind: MembersActionResultKind.success,
          message: successMessage(result.value),
        );
      case MembershipAdminFailure<T>():
        return _outcomeForFailure(result);
    }
  }

  MembersActionOutcome _outcomeForFailure(
    MembershipAdminFailure<Object?> failure,
  ) {
    switch (failure.kind) {
      case MembershipAdminFailureKind.versionConflict:
        return MembersActionOutcome(
          kind: MembersActionResultKind.versionConflict,
          message: 'Der Datensatz wurde zwischenzeitlich geändert.',
          conflict: failure.versionConflict,
        );
      case MembershipAdminFailureKind.forbidden:
        return const MembersActionOutcome(
          kind: MembersActionResultKind.forbidden,
          message:
              'Die Aktion wurde vom Server abgelehnt. Deine Berechtigungen '
              'reichen dafür nicht aus.',
        );
      case MembershipAdminFailureKind.validationFailed:
        if (failure.message.contains('last active security manager')) {
          return const MembersActionOutcome(
            kind: MembersActionResultKind.lastSecurityManager,
            message: lastSecurityManagerMessage,
          );
        }
        return MembersActionOutcome(
          kind: MembersActionResultKind.validationFailed,
          message: _germanValidationMessage(failure.message),
        );
      case MembershipAdminFailureKind.notFound:
        return const MembersActionOutcome(
          kind: MembersActionResultKind.failed,
          message:
              'Der Datensatz wurde nicht gefunden. Aktualisiere die Liste '
              'und versuche es erneut.',
        );
      case MembershipAdminFailureKind.mutationConflict:
      case MembershipAdminFailureKind.mutationInProgress:
      case MembershipAdminFailureKind.dependencyConflict:
      case MembershipAdminFailureKind.infrastructureFailure:
        return const MembersActionOutcome(
          kind: MembersActionResultKind.failed,
          message: 'Die Aktion ist fehlgeschlagen. Versuche es erneut.',
        );
    }
  }

  String _germanValidationMessage(String serverMessage) {
    if (serverMessage.contains('already has a membership')) {
      return 'Diese E-Mail-Adresse hat bereits eine Mitgliedschaft in diesem '
          'Workspace.';
    }
    if (serverMessage.contains('pending invitation for this email')) {
      return 'Für diese E-Mail-Adresse existiert bereits eine offene '
          'Einladung.';
    }
    if (serverMessage.contains('Email is invalid')) {
      return 'Die E-Mail-Adresse ist ungültig.';
    }
    if (serverMessage.contains('already has this role')) {
      return 'Das Mitglied hat diese Rolle bereits.';
    }
    if (serverMessage.contains('Transition')) {
      return 'Dieser Statuswechsel ist nicht zulässig.';
    }
    return 'Die Eingaben wurden vom Server abgelehnt.';
  }

  MembersActionPhase _phaseForOutcome(MembersActionResultKind kind) {
    return switch (kind) {
      MembersActionResultKind.success => MembersActionPhase.succeeded,
      MembersActionResultKind.versionConflict => MembersActionPhase.conflict,
      MembersActionResultKind.validationFailed ||
      MembersActionResultKind
          .lastSecurityManager => MembersActionPhase.validationFailed,
      MembersActionResultKind.forbidden => MembersActionPhase.forbidden,
      MembersActionResultKind.failed => MembersActionPhase.failed,
    };
  }
}

/// Applies the Mitglieder-tab filters: client-side search over name and
/// email, a nullable role filter and a nullable status filter whose default
/// (`null` = "Alle aktiven") hides revoked members. Sorted by display name
/// (email, then user id as fallback), secondary `createdAt`.
List<WorkspaceMemberDirectoryEntry> filterMemberDirectory(
  List<WorkspaceMemberDirectoryEntry> entries, {
  String query = '',
  String? roleId,
  MembershipStatus? status,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = entries
      .where((entry) {
        if (status == null) {
          if (entry.status == MembershipStatus.revoked) {
            return false;
          }
        } else if (entry.status != status) {
          return false;
        }
        if (roleId != null && entry.roleId != roleId) {
          return false;
        }
        if (normalizedQuery.isNotEmpty) {
          final name = entry.displayName?.toLowerCase() ?? '';
          final email = entry.email?.toLowerCase() ?? '';
          if (!name.contains(normalizedQuery) &&
              !email.contains(normalizedQuery)) {
            return false;
          }
        }
        return true;
      })
      .toList(growable: false);
  final sorted = List<WorkspaceMemberDirectoryEntry>.of(filtered)..sort((a, b) {
    final byName = _sortKey(a).compareTo(_sortKey(b));
    if (byName != 0) {
      return byName;
    }
    return a.createdAt.compareTo(b.createdAt);
  });
  return sorted;
}

String _sortKey(WorkspaceMemberDirectoryEntry entry) {
  return (entry.displayName ?? entry.email ?? entry.userId).toLowerCase();
}

class RoleCapabilityDiff {
  const RoleCapabilityDiff({required this.added, required this.removed});

  final List<WorkspaceRoleCapability> added;
  final List<WorkspaceRoleCapability> removed;

  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

/// Capability delta between two roles, compared by permission key. Feeds the
/// "Hinzu kommen / Entfallen" summary of the role-change dialog.
RoleCapabilityDiff computeRoleCapabilityDiff({
  required List<WorkspaceRoleCapability> from,
  required List<WorkspaceRoleCapability> to,
}) {
  final fromByKey = <String, WorkspaceRoleCapability>{
    for (final capability in from) capability.permissionKey: capability,
  };
  final toByKey = <String, WorkspaceRoleCapability>{
    for (final capability in to) capability.permissionKey: capability,
  };
  final added = toByKey.values
      .where((capability) => !fromByKey.containsKey(capability.permissionKey))
      .toList(growable: false)
    ..sort((a, b) => a.permissionKey.compareTo(b.permissionKey));
  final removed = fromByKey.values
      .where((capability) => !toByKey.containsKey(capability.permissionKey))
      .toList(growable: false)
    ..sort((a, b) => a.permissionKey.compareTo(b.permissionKey));
  return RoleCapabilityDiff(added: added, removed: removed);
}

Map<String, List<WorkspaceRoleCapability>> roleCapabilitiesByRole(
  List<WorkspaceRoleCapability> capabilities,
) {
  final byRole = <String, List<WorkspaceRoleCapability>>{};
  for (final capability in capabilities) {
    byRole
        .putIfAbsent(capability.roleId, () => <WorkspaceRoleCapability>[])
        .add(capability);
  }
  return byRole;
}

/// Backend-agnostic membership administration, wired per data backend in
/// `main.dart` (Supabase adapter in cloud mode). Fails closed if read before an
/// override is installed — mirrors [identityAccessRepositoryProvider].
final membershipAdminRepositoryProvider = Provider<MembershipAdminRepository>(
  (ref) => throw StateError('MembershipAdminRepository is not configured.'),
);

final membersAdminControllerProvider = StateNotifierProvider.autoDispose
    .family<MembersAdminController, MembersAdminState, MembersAdminScope>((
      ref,
      scope,
    ) {
      final controller = MembersAdminController(
        repository: ref.watch(membershipAdminRepositoryProvider),
        actorId: scope.actorId,
        authorization: PermissionSetAuthorizationPort(scope.permissions),
        canMutate: scope.canMutate,
        workspaceId: scope.workspaceId,
      );
      unawaited(controller.load());
      return controller;
    });
