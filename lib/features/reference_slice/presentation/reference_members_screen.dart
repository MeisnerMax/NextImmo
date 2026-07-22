import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_page_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/navigation/app_navigation.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../identity_access/application/membership_admin_repository.dart';
import '../application/members_admin_controller.dart';
import '../application/reference_slice_controller.dart';

/// Cloud member administration for the reference slice (P2-D01 increment 3).
/// In Supabase mode the app routes exclusively onto the reference-slice
/// presentation, so the membership admin surface lives here rather than the
/// SQLite-only `UsersScreen`.
class ReferenceMembersScreen extends ConsumerWidget {
  const ReferenceMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(referenceSliceControllerProvider);

    Widget backToProperties() {
      return OutlinedButton.icon(
        key: const Key('members-back'),
        onPressed: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            navigator.pushReplacementNamed(referencePropertiesRoute);
          }
        },
        icon: const Icon(Icons.arrow_back),
        label: const Text('Properties'),
      );
    }

    if (reference.authPhase == ReferenceAuthPhase.loading) {
      return const Scaffold(
        body: Center(
          key: Key('members-auth-loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (reference.authPhase != ReferenceAuthPhase.authenticated ||
        reference.userId == null) {
      return Scaffold(
        body: Padding(
          padding: EdgeInsets.all(context.adaptivePagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: backToProperties()),
              const SizedBox(height: AppSpacing.component),
              const Expanded(
                child: NxEmptyState(
                  key: Key('members-signed-out'),
                  title: 'Sign in required',
                  description:
                      'Members administration is available after signing in.',
                  icon: Icons.lock_outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final access = reference.selectedWorkspace;
    final scope = MembersAdminScope(
      workspaceId: access?.workspace.id,
      actorId: reference.userId!,
      permissions: access?.permissions ?? const <String>{},
      canMutate:
          reference.assuranceLevel == AuthenticationAssuranceLevel.aal2,
    );
    final state = ref.watch(membersAdminControllerProvider(scope));
    final controller = ref.read(membersAdminControllerProvider(scope).notifier);

    return Scaffold(
      body: MembersAdminView(
        state: state,
        workspaceName: access?.workspace.name,
        canManage: controller.canManageMembers,
        canMutate: controller.canMutate,
        onBack: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            navigator.pushReplacementNamed(referencePropertiesRoute);
          }
        },
        onReloadDirectory: controller.reloadDirectory,
        onReloadPending: controller.reloadPending,
        onInvite: (email, roleId) =>
            controller.invite(email: email, roleId: roleId),
        onChangeRole: (membershipId, newRoleId, expectedVersion) =>
            controller.changeRole(
              membershipId: membershipId,
              newRoleId: newRoleId,
              expectedVersion: expectedVersion,
            ),
        onUpdateStatus: (membershipId, newStatus, expectedVersion) =>
            controller.updateStatus(
              membershipId: membershipId,
              newStatus: newStatus,
              expectedVersion: expectedVersion,
            ),
        onRevokeInvitation: (invitationId, expectedVersion) =>
            controller.revokeInvitation(
              invitationId: invitationId,
              expectedVersion: expectedVersion,
            ),
        onAcceptOwnInvitation: controller.acceptOwnInvitation,
      ),
    );
  }
}

class MembersAdminView extends StatefulWidget {
  const MembersAdminView({
    super.key,
    required this.state,
    required this.workspaceName,
    required this.canManage,
    required this.canMutate,
    required this.onBack,
    required this.onReloadDirectory,
    required this.onReloadPending,
    required this.onInvite,
    required this.onChangeRole,
    required this.onUpdateStatus,
    required this.onRevokeInvitation,
    required this.onAcceptOwnInvitation,
  });

  final MembersAdminState state;
  final String? workspaceName;
  final bool canManage;
  final bool canMutate;
  final VoidCallback onBack;
  final Future<void> Function() onReloadDirectory;
  final Future<void> Function() onReloadPending;
  final Future<void> Function(String email, String roleId) onInvite;
  final Future<void> Function(
    String membershipId,
    String newRoleId,
    int expectedVersion,
  )
  onChangeRole;
  final Future<void> Function(
    String membershipId,
    MembershipStatus newStatus,
    int expectedVersion,
  )
  onUpdateStatus;
  final Future<void> Function(String invitationId, int expectedVersion)
  onRevokeInvitation;
  final Future<void> Function(PendingInvitationEntry entry)
  onAcceptOwnInvitation;

  @override
  State<MembersAdminView> createState() => _MembersAdminViewState();
}

class _MembersAdminViewState extends State<MembersAdminView> {
  final TextEditingController _inviteEmail = TextEditingController();
  String? _inviteRoleId;

  @override
  void dispose() {
    _inviteEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxPageHeader(
            title: 'Members',
            breadcrumbs: const ['Reference slice', 'Members'],
            subtitle:
                widget.workspaceName == null
                    ? 'Workspace membership administration.'
                    : 'Members of ${widget.workspaceName}.',
            secondaryActions: [
              OutlinedButton.icon(
                key: const Key('members-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Properties'),
              ),
              OutlinedButton.icon(
                key: const Key('members-refresh'),
                onPressed: () {
                  widget.onReloadPending();
                  widget.onReloadDirectory();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: ListView(
              key: const Key('members-view'),
              children: [
                _actionFeedback(context),
                _pendingZone(context),
                if (widget.canManage && !widget.canMutate) ...[
                  const _InfoBanner(
                    key: Key('members-mfa-hint'),
                    icon: Icons.phonelink_lock_outlined,
                    message:
                        'Set up multi-factor authentication (AAL2) to change '
                        'members. You can view the directory now.',
                  ),
                  const SizedBox(height: AppSpacing.component),
                ],
                _directoryZone(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionFeedback(BuildContext context) {
    final state = widget.state;
    if (state.actionPhase == MembersActionPhase.idle ||
        state.actionMessage == null) {
      return const SizedBox.shrink();
    }
    final icon = switch (state.actionPhase) {
      MembersActionPhase.submitting => Icons.hourglass_top_outlined,
      MembersActionPhase.succeeded => Icons.check_circle_outline,
      MembersActionPhase.conflict => Icons.sync_problem_outlined,
      MembersActionPhase.forbidden => Icons.block_outlined,
      MembersActionPhase.failed => Icons.error_outline,
      MembersActionPhase.idle => Icons.info_outline,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: _InfoBanner(
        key: const Key('members-action-feedback'),
        icon: icon,
        message: state.actionMessage!,
      ),
    );
  }

  Widget _pendingZone(BuildContext context) {
    final state = widget.state;
    switch (state.pendingPhase) {
      case MembersPendingPhase.loading:
        return const SizedBox.shrink();
      case MembersPendingPhase.empty:
        return const SizedBox.shrink();
      case MembersPendingPhase.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.section),
          child: NxCard(
            child: Row(
              children: [
                const Expanded(
                  child: Text('Your pending invitations could not be loaded.'),
                ),
                TextButton(
                  key: const Key('members-pending-retry'),
                  onPressed: widget.onReloadPending,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case MembersPendingPhase.ready:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.section),
          child: Column(
            key: const Key('members-pending-zone'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, 'Your invitations'),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in state.pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _pendingCard(context, entry),
                ),
            ],
          ),
        );
    }
  }

  Widget _pendingCard(BuildContext context, PendingInvitationEntry entry) {
    return NxCard(
      child: Row(
        children: [
          const Icon(Icons.mark_email_read_outlined),
          const SizedBox(width: AppSpacing.component),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.workspaceName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'Invited as ${entry.roleName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            key: Key('members-accept-${entry.workspaceId}'),
            onPressed:
                widget.state.actionPhase == MembersActionPhase.submitting
                    ? null
                    : () => widget.onAcceptOwnInvitation(entry),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _directoryZone(BuildContext context) {
    final state = widget.state;
    switch (state.directoryPhase) {
      case MembersDirectoryPhase.idle:
        return const NxEmptyState(
          key: Key('members-directory-idle'),
          title: 'No workspace selected',
          description:
              'Accept an invitation above, or choose a workspace on the '
              'Properties screen to manage its members.',
          icon: Icons.domain_outlined,
        );
      case MembersDirectoryPhase.loading:
        return const NxCard(
          key: Key('members-directory-skeleton'),
          child: Center(child: CircularProgressIndicator()),
        );
      case MembersDirectoryPhase.forbidden:
        return const NxEmptyState(
          key: Key('members-forbidden'),
          title: 'No member access',
          description:
              'Your workspace role cannot manage members. Ask a workspace '
              'administrator for the security.manage capability.',
          icon: Icons.block_outlined,
        );
      case MembersDirectoryPhase.error:
        return NxEmptyState(
          key: const Key('members-directory-error'),
          title: 'Unable to load members',
          description: state.message ?? 'The member directory could not be loaded.',
          icon: Icons.error_outline,
          primaryAction: OutlinedButton(
            onPressed: widget.onReloadDirectory,
            child: const Text('Retry'),
          ),
        );
      case MembersDirectoryPhase.empty:
      case MembersDirectoryPhase.ready:
        return Column(
          key: const Key('members-directory-zone'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canManage) ...[
              _inviteCard(context),
              const SizedBox(height: AppSpacing.section),
            ],
            _sectionTitle(context, 'Workspace members'),
            const SizedBox(height: AppSpacing.sm),
            if (state.directory.isEmpty)
              const NxEmptyState(
                title: 'No members yet',
                description: 'Invite the first member with an email above.',
                icon: Icons.group_outlined,
              )
            else
              for (final entry in state.directory)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _memberCard(context, entry),
                ),
            if (state.invitations.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.section),
              _sectionTitle(context, 'Pending email invitations'),
              const SizedBox(height: AppSpacing.sm),
              for (final invitation in state.invitations)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _invitationCard(context, invitation),
                ),
            ],
          ],
        );
    }
  }

  Widget _inviteCard(BuildContext context) {
    final roles = widget.state.roles;
    final selectedRole =
        roles.any((role) => role.id == _inviteRoleId)
            ? _inviteRoleId
            : roles.isEmpty
            ? null
            : roles.first.id;
    _inviteRoleId = selectedRole;
    return NxCard(
      key: const Key('members-invite-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(context, 'Invite a member'),
          const SizedBox(height: AppSpacing.component),
          LayoutBuilder(
            builder: (context, constraints) {
              final email = TextField(
                key: const Key('members-invite-email'),
                controller: _inviteEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              );
              final role = DropdownButtonFormField<String>(
                key: const Key('members-invite-role'),
                value: selectedRole,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in roles)
                    DropdownMenuItem(value: role.id, child: Text(role.name)),
                ],
                onChanged:
                    (value) => setState(() => _inviteRoleId = value),
              );
              final button = FilledButton.icon(
                key: const Key('members-invite-submit'),
                onPressed:
                    (!widget.canMutate ||
                            selectedRole == null ||
                            widget.state.actionPhase ==
                                MembersActionPhase.submitting)
                        ? null
                        : () => _submitInvite(selectedRole),
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Send invite'),
              );
              if (constraints.maxWidth < 640) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    email,
                    const SizedBox(height: AppSpacing.component),
                    role,
                    const SizedBox(height: AppSpacing.component),
                    button,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: email),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(flex: 2, child: role),
                  const SizedBox(width: AppSpacing.component),
                  button,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _submitInvite(String roleId) {
    final email = _inviteEmail.text.trim();
    if (email.isEmpty) {
      return;
    }
    widget.onInvite(email, roleId);
    _inviteEmail.clear();
  }

  Widget _memberCard(BuildContext context, WorkspaceMemberDirectoryEntry entry) {
    final title = entry.displayName ?? entry.email ?? entry.userId;
    return NxCard(
      key: Key('member-card-${entry.userId}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (entry.email != null)
                  Text(
                    entry.email!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    NxStatusBadge(label: entry.roleName),
                    NxStatusBadge(
                      label: _statusLabel(entry.status),
                      kind: _statusKind(entry.status),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.canManage) _memberActions(context, entry),
        ],
      ),
    );
  }

  Widget _memberActions(
    BuildContext context,
    WorkspaceMemberDirectoryEntry entry,
  ) {
    final actions = <PopupMenuEntry<String>>[];
    if (entry.status != MembershipStatus.revoked) {
      actions.add(
        const PopupMenuItem(value: 'role', child: Text('Change role')),
      );
    }
    if (entry.status == MembershipStatus.active) {
      actions.add(
        const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
      );
    }
    if (entry.status == MembershipStatus.suspended) {
      actions.add(
        const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
      );
    }
    if (entry.status != MembershipStatus.revoked) {
      actions.add(
        const PopupMenuItem(value: 'revoke', child: Text('Revoke access')),
      );
    }
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      key: Key('member-actions-${entry.membershipId}'),
      enabled: widget.canMutate,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => actions,
      onSelected: (value) => _onMemberAction(context, entry, value),
    );
  }

  Future<void> _onMemberAction(
    BuildContext context,
    WorkspaceMemberDirectoryEntry entry,
    String action,
  ) async {
    switch (action) {
      case 'role':
        await _changeRoleDialog(context, entry);
      case 'suspend':
        if (await _confirm(
          context,
          title: 'Suspend member?',
          message:
              '${entry.displayName ?? entry.email ?? entry.userId} loses access '
              'until reactivated. This is reversible.',
          confirmLabel: 'Suspend',
        )) {
          await widget.onUpdateStatus(
            entry.membershipId,
            MembershipStatus.suspended,
            entry.version,
          );
        }
      case 'reactivate':
        if (await _confirm(
          context,
          title: 'Reactivate member?',
          message:
              '${entry.displayName ?? entry.email ?? entry.userId} regains their '
              'previous workspace access.',
          confirmLabel: 'Reactivate',
        )) {
          await widget.onUpdateStatus(
            entry.membershipId,
            MembershipStatus.active,
            entry.version,
          );
        }
      case 'revoke':
        if (await _confirm(
          context,
          title: 'Revoke access?',
          message:
              'Revoking is permanent — ${entry.displayName ?? entry.email ?? entry.userId} '
              'cannot be re-invited while their membership row remains.',
          confirmLabel: 'Revoke',
          destructive: true,
        )) {
          await widget.onUpdateStatus(
            entry.membershipId,
            MembershipStatus.revoked,
            entry.version,
          );
        }
    }
  }

  Future<void> _changeRoleDialog(
    BuildContext context,
    WorkspaceMemberDirectoryEntry entry,
  ) async {
    final roles = widget.state.roles;
    if (roles.isEmpty) {
      return;
    }
    var selected = entry.roleId;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change role'),
              content: DropdownButtonFormField<String>(
                key: const Key('member-role-dialog-dropdown'),
                value: roles.any((role) => role.id == selected)
                    ? selected
                    : roles.first.id,
                isExpanded: true,
                items: [
                  for (final role in roles)
                    DropdownMenuItem(value: role.id, child: Text(role.name)),
                ],
                onChanged:
                    (value) => setDialogState(() => selected = value ?? selected),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('member-role-dialog-confirm'),
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (chosen != null && chosen != entry.roleId) {
      await widget.onChangeRole(entry.membershipId, chosen, entry.version);
    }
  }

  Widget _invitationCard(BuildContext context, MembershipInvitation invitation) {
    String? roleName;
    for (final role in widget.state.roles) {
      if (role.id == invitation.roleId) {
        roleName = role.name;
        break;
      }
    }
    return NxCard(
      key: Key('invitation-card-${invitation.id}'),
      child: Row(
        children: [
          const Icon(Icons.outgoing_mail),
          const SizedBox(width: AppSpacing.component),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  roleName == null ? 'Pending' : 'Pending · $roleName',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const NxStatusBadge(label: 'pending', kind: NxBadgeKind.info),
          if (widget.canManage) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: Key('invitation-revoke-${invitation.id}'),
              onPressed:
                  !widget.canMutate
                      ? null
                      : () async {
                        if (await _confirm(
                          context,
                          title: 'Revoke invitation?',
                          message:
                              'The invitation to ${invitation.email} is cancelled. '
                              'You can send a new one later.',
                          confirmLabel: 'Revoke',
                          destructive: true,
                        )) {
                          await widget.onRevokeInvitation(
                            invitation.id,
                            invitation.version,
                          );
                        }
                      },
              child: const Text('Revoke'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('members-confirm'),
              style:
                  destructive
                      ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                      : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

String _statusLabel(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.invited => 'invited',
    MembershipStatus.active => 'active',
    MembershipStatus.suspended => 'suspended',
    MembershipStatus.revoked => 'revoked',
  };
}

NxBadgeKind _statusKind(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.invited => NxBadgeKind.info,
    MembershipStatus.active => NxBadgeKind.success,
    MembershipStatus.suspended => NxBadgeKind.warning,
    MembershipStatus.revoked => NxBadgeKind.error,
  };
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
