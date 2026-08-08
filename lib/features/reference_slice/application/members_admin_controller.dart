import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/authorization_port.dart';
import '../../identity_access/application/membership_admin_repository.dart';

const _unchanged = Object();

/// Directory zone: the workspace member table plus its pending email
/// invitations. Both require `security.manage`, so they share one phase.
enum MembersDirectoryPhase { idle, loading, ready, empty, forbidden, error }

/// Own-invitations zone: the signed-in user's pending invitations, readable by
/// anyone (an invited user has no workspace access yet).
enum MembersPendingPhase { loading, ready, empty, error }

enum MembersActionPhase {
  idle,
  submitting,
  succeeded,
  conflict,
  forbidden,
  failed,
}

/// Identifies the workspace/actor a [MembersAdminController] is bound to.
/// [workspaceId] is null when the user has no active workspace (e.g. an
/// invited-only user): the own-invitations zone still loads, the directory
/// stays idle. Value equality keeps the Riverpod family stable across rebuilds.
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
    required this.pendingPhase,
    this.actionPhase = MembersActionPhase.idle,
    this.directory = const <WorkspaceMemberDirectoryEntry>[],
    this.roles = const <WorkspaceRole>[],
    this.invitations = const <MembershipInvitation>[],
    this.pending = const <PendingInvitationEntry>[],
    this.message,
    this.actionMessage,
  });

  const MembersAdminState.loading()
    : this(
        directoryPhase: MembersDirectoryPhase.loading,
        pendingPhase: MembersPendingPhase.loading,
      );

  final MembersDirectoryPhase directoryPhase;
  final MembersPendingPhase pendingPhase;
  final MembersActionPhase actionPhase;
  final List<WorkspaceMemberDirectoryEntry> directory;
  final List<WorkspaceRole> roles;
  final List<MembershipInvitation> invitations;
  final List<PendingInvitationEntry> pending;
  final String? message;
  final String? actionMessage;

  MembersAdminState copyWith({
    MembersDirectoryPhase? directoryPhase,
    MembersPendingPhase? pendingPhase,
    MembersActionPhase? actionPhase,
    List<WorkspaceMemberDirectoryEntry>? directory,
    List<WorkspaceRole>? roles,
    List<MembershipInvitation>? invitations,
    List<PendingInvitationEntry>? pending,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
  }) {
    return MembersAdminState(
      directoryPhase: directoryPhase ?? this.directoryPhase,
      pendingPhase: pendingPhase ?? this.pendingPhase,
      actionPhase: actionPhase ?? this.actionPhase,
      directory: directory ?? this.directory,
      roles: roles ?? this.roles,
      invitations: invitations ?? this.invitations,
      pending: pending ?? this.pending,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
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

  final MembershipAdminRepository _repository;
  final String _actorId;
  final AuthorizationPort _authorization;
  final bool _canMutate;
  final String? _workspaceId;
  final MembersIdFactory _idFactory;

  int _generation = 0;

  bool get canManageMembers =>
      _workspaceId != null && _authorization.can(manageMembersPermission);

  bool get canMutate => _canMutate;

  Future<void> load() async {
    final generation = ++_generation;
    await Future.wait(<Future<void>>[
      _loadPending(generation),
      _loadDirectory(generation),
    ]);
  }

  Future<void> reloadDirectory() async {
    final generation = ++_generation;
    await _loadDirectory(generation);
  }

  Future<void> reloadPending() async {
    final generation = ++_generation;
    await _loadPending(generation);
  }

  Future<void> _loadPending(int generation) async {
    if (generation != _generation) {
      return;
    }
    state = state.copyWith(pendingPhase: MembersPendingPhase.loading);
    final result = await _repository.listMyPendingInvitations();
    if (generation != _generation) {
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
        state = state.copyWith(
          pendingPhase: MembersPendingPhase.error,
          pending: const <PendingInvitationEntry>[],
        );
    }
  }

  Future<void> _loadDirectory(int generation) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        directoryPhase: MembersDirectoryPhase.idle,
        directory: const <WorkspaceMemberDirectoryEntry>[],
        roles: const <WorkspaceRole>[],
        invitations: const <MembershipInvitation>[],
        message: null,
      );
      return;
    }
    if (!_authorization.can(manageMembersPermission)) {
      state = state.copyWith(
        directoryPhase: MembersDirectoryPhase.forbidden,
        directory: const <WorkspaceMemberDirectoryEntry>[],
        roles: const <WorkspaceRole>[],
        invitations: const <MembershipInvitation>[],
        message: null,
      );
      return;
    }
    state = state.copyWith(
      directoryPhase: MembersDirectoryPhase.loading,
      message: null,
    );
    final directoryResult = await _repository.listMemberDirectory(
      workspaceId: workspaceId,
    );
    if (generation != _generation) {
      return;
    }
    if (directoryResult is MembershipAdminFailure<
        List<WorkspaceMemberDirectoryEntry>>) {
      state = state.copyWith(
        directoryPhase:
            directoryResult.kind == MembershipAdminFailureKind.forbidden
                ? MembersDirectoryPhase.forbidden
                : MembersDirectoryPhase.error,
        directory: const <WorkspaceMemberDirectoryEntry>[],
        message: directoryResult.message,
      );
      return;
    }
    final directory =
        (directoryResult as MembershipAdminSuccess<
                List<WorkspaceMemberDirectoryEntry>>)
            .value;
    final rolesResult = await _repository.listRoles(workspaceId: workspaceId);
    final invitationsResult = await _repository.listInvitations(
      workspaceId: workspaceId,
    );
    if (generation != _generation) {
      return;
    }
    final roles = switch (rolesResult) {
      MembershipAdminSuccess<List<WorkspaceRole>>() => rolesResult.value,
      MembershipAdminFailure<List<WorkspaceRole>>() => const <WorkspaceRole>[],
    };
    final invitations = switch (invitationsResult) {
      MembershipAdminSuccess<List<MembershipInvitation>>() =>
        invitationsResult.value,
      MembershipAdminFailure<List<MembershipInvitation>>() =>
        const <MembershipInvitation>[],
    };
    state = state.copyWith(
      directoryPhase:
          directory.isEmpty
              ? MembersDirectoryPhase.empty
              : MembersDirectoryPhase.ready,
      directory: directory,
      roles: roles,
      invitations: invitations,
      message: null,
    );
  }

  MembershipCommandContext _context(String workspaceId) {
    return MembershipCommandContext(
      workspaceId: workspaceId,
      actorId: _actorId,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }

  bool _blockMutation() {
    if (!_canMutate) {
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage:
            'Multi-factor authentication (AAL2) is required for member changes.',
      );
      return true;
    }
    if (!canManageMembers) {
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage: 'Your workspace role cannot manage members.',
      );
      return true;
    }
    return false;
  }

  Future<void> invite({required String email, required String roleId}) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || _blockMutation()) {
      return;
    }
    await _runMutation(
      () => _repository.invite(
        InviteMemberCommand(
          context: _context(workspaceId),
          email: email,
          roleId: roleId,
        ),
      ),
      successMessage: 'Invitation sent.',
    );
  }

  Future<void> changeRole({
    required String membershipId,
    required String newRoleId,
    required int expectedVersion,
  }) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || _blockMutation()) {
      return;
    }
    await _runMutation(
      () => _repository.changeRole(
        ChangeMembershipRoleCommand(
          context: _context(workspaceId),
          membershipId: membershipId,
          newRoleId: newRoleId,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage: 'Member role updated.',
    );
  }

  Future<void> updateStatus({
    required String membershipId,
    required MembershipStatus newStatus,
    required int expectedVersion,
  }) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || _blockMutation()) {
      return;
    }
    await _runMutation(
      () => _repository.updateStatus(
        UpdateMembershipStatusCommand(
          context: _context(workspaceId),
          membershipId: membershipId,
          newStatus: newStatus,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage: switch (newStatus) {
        MembershipStatus.suspended => 'Member suspended.',
        MembershipStatus.active => 'Member reactivated.',
        MembershipStatus.revoked => 'Member access revoked.',
        MembershipStatus.invited => 'Member updated.',
      },
    );
  }

  Future<void> revokeInvitation({
    required String invitationId,
    required int expectedVersion,
  }) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || _blockMutation()) {
      return;
    }
    await _runMutation(
      () => _repository.revokeInvitation(
        RevokeInvitationCommand(
          context: _context(workspaceId),
          invitationId: invitationId,
          expectedVersion: expectedVersion,
        ),
      ),
      successMessage: 'Invitation revoked.',
    );
  }

  /// Accepts one of the signed-in user's own pending invitations. Unlike the
  /// admin mutations this does not require `security.manage` (the invitee acts
  /// on their own row), but it is still AAL2-gated server-side.
  Future<void> acceptOwnInvitation(PendingInvitationEntry entry) async {
    if (!_canMutate) {
      state = state.copyWith(
        actionPhase: MembersActionPhase.forbidden,
        actionMessage:
            'Multi-factor authentication (AAL2) is required to accept an invitation.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      actionPhase: MembersActionPhase.submitting,
      actionMessage: null,
    );
    final result = await _repository.accept(
      AcceptInvitationCommand(context: _context(entry.workspaceId)),
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<WorkspaceMember>():
        state = state.copyWith(
          actionPhase: MembersActionPhase.succeeded,
          actionMessage:
              'Invitation to ${entry.workspaceName} accepted. '
              'Reopen the workspace to continue.',
        );
        await _loadPending(generation);
        await _loadDirectory(generation);
      case MembershipAdminFailure<WorkspaceMember>():
        state = state.copyWith(
          actionPhase: _actionPhaseForFailure(result.kind),
          actionMessage: _actionMessageForFailure(result),
        );
    }
  }

  Future<void> _runMutation(
    Future<MembershipAdminResult<Object?>> Function() run, {
    required String successMessage,
  }) async {
    final generation = ++_generation;
    state = state.copyWith(
      actionPhase: MembersActionPhase.submitting,
      actionMessage: null,
    );
    final result = await run();
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case MembershipAdminSuccess<Object?>():
        state = state.copyWith(
          actionPhase: MembersActionPhase.succeeded,
          actionMessage: successMessage,
        );
        await _loadDirectory(generation);
      case MembershipAdminFailure<Object?>():
        state = state.copyWith(
          actionPhase: _actionPhaseForFailure(result.kind),
          actionMessage: _actionMessageForFailure(result),
        );
        if (result.kind == MembershipAdminFailureKind.versionConflict) {
          await _loadDirectory(generation);
        }
    }
  }

  MembersActionPhase _actionPhaseForFailure(MembershipAdminFailureKind kind) {
    return switch (kind) {
      MembershipAdminFailureKind.forbidden => MembersActionPhase.forbidden,
      MembershipAdminFailureKind.versionConflict => MembersActionPhase.conflict,
      _ => MembersActionPhase.failed,
    };
  }

  String _actionMessageForFailure(MembershipAdminFailure<Object?> failure) {
    if (failure.kind == MembershipAdminFailureKind.versionConflict) {
      return 'This member changed since you loaded the list. The refreshed '
          'directory is shown; please try again.';
    }
    return failure.message;
  }
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
