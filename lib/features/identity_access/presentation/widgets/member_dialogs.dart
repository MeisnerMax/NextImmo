import 'package:flutter/material.dart';

import '../../../../ui/components/nx_notice.dart';
import '../../../../ui/components/responsive_constraints.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../application/members_admin_controller.dart';
import '../../application/membership_admin_repository.dart';
import 'role_capability_list.dart';

/// Modal dialogs of the Mitglieder admin screen (Foundation §10/§14):
/// invite, role change with capability diff and in-dialog conflict banner,
/// and the reason-carrying confirmation dialog. User input is never thrown
/// away — validation and version conflicts keep the dialog open.

typedef AdminMembersInviteSubmit =
    Future<MembersActionOutcome> Function({
      required String email,
      required String roleId,
      String? reason,
    });

typedef AdminMembersChangeRoleSubmit =
    Future<MembersActionOutcome> Function({
      required String membershipId,
      required String newRoleId,
      required int expectedVersion,
      String? reason,
    });

typedef AdminMembersUpdateStatusSubmit =
    Future<MembersActionOutcome> Function({
      required String membershipId,
      required MembershipStatus newStatus,
      required int expectedVersion,
      String? reason,
    });

typedef AdminMembersRevokeInvitationSubmit =
    Future<MembersActionOutcome> Function({
      required String invitationId,
      required int expectedVersion,
      String? reason,
    });

const _reasonLabel = 'Grund (optional, wird protokolliert)';
const _reasonMaxLength = 500;

Future<void> showInviteMemberDialog(
  BuildContext context, {
  required List<WorkspaceRole> roles,
  required Map<String, List<WorkspaceRoleCapability>> capabilitiesByRole,
  required AdminMembersInviteSubmit onSubmit,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => _InviteMemberDialog(
          roles: roles,
          capabilitiesByRole: capabilitiesByRole,
          onSubmit: onSubmit,
        ),
  );
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({
    required this.roles,
    required this.capabilitiesByRole,
    required this.onSubmit,
  });

  final List<WorkspaceRole> roles;
  final Map<String, List<WorkspaceRoleCapability>> capabilitiesByRole;
  final AdminMembersInviteSubmit onSubmit;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _reason = TextEditingController();

  /// Deliberately no preselection: choosing the role is a decision, not a
  /// default (spec §12).
  String? _roleId;
  bool _submitting = false;
  String? _serverError;

  bool get _dirty =>
      _email.text.trim().isNotEmpty ||
      _reason.text.trim().isNotEmpty ||
      _roleId != null;

  @override
  void dispose() {
    _email.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _serverError = null;
    });
    final outcome = await widget.onSubmit(
      email: _email.text.trim(),
      roleId: _roleId!,
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (outcome.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _serverError = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCapabilities =
        _roleId == null
            ? const <WorkspaceRoleCapability>[]
            : widget.capabilitiesByRole[_roleId] ??
                const <WorkspaceRoleCapability>[];
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard(context);
        }
      },
      child: AlertDialog(
        key: const Key('admin-members-invite-dialog'),
        title: const Text('Mitglied einladen'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 480),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('admin-members-invite-email'),
                    controller: _email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return 'Pflichtfeld';
                      }
                      if (trimmed.length < 3 ||
                          trimmed.length > 320 ||
                          !RegExp(r'^\S+@\S+$').hasMatch(trimmed)) {
                        return 'Ungültige E-Mail-Adresse.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.component),
                  DropdownButtonFormField<String?>(
                    key: const Key('admin-members-invite-role'),
                    value: _roleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Rolle'),
                    items: [
                      for (final role in widget.roles)
                        DropdownMenuItem<String?>(
                          key: Key('admin-members-invite-role-${role.id}'),
                          value: role.id,
                          child: Text(
                            '${role.name} · '
                            '${(widget.capabilitiesByRole[role.id] ?? const <WorkspaceRoleCapability>[]).length} '
                            'Berechtigungen',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (value) => value == null ? 'Pflichtfeld' : null,
                    onChanged:
                        _submitting
                            ? null
                            : (value) => setState(() => _roleId = value),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Wähle die Rolle mit den wenigsten nötigen Berechtigungen.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_roleId != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    RoleCapabilityList(
                      capabilities: selectedCapabilities,
                      title: Text(
                        'Berechtigungen dieser Rolle '
                        '(${selectedCapabilities.length})',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.component),
                  TextFormField(
                    key: const Key('admin-members-invite-reason'),
                    controller: _reason,
                    maxLength: _reasonMaxLength,
                    decoration: const InputDecoration(labelText: _reasonLabel),
                  ),
                  if (_serverError != null) ...[
                    const SizedBox(height: AppSpacing.component),
                    NxNotice(
                      key: const Key('admin-members-invite-error'),
                      kind: NxNoticeKind.error,
                      message: _serverError!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('admin-members-invite-cancel'),
            onPressed:
                _submitting ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('admin-members-invite-submit'),
            onPressed: _submitting ? null : _submit,
            child:
                _submitting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Einladen'),
          ),
        ],
      ),
    );
  }
}

Future<void> showChangeMemberRoleDialog(
  BuildContext context, {
  required WorkspaceMemberDirectoryEntry member,
  required List<WorkspaceRole> roles,
  required Map<String, List<WorkspaceRoleCapability>> capabilitiesByRole,
  required AdminMembersChangeRoleSubmit onSubmit,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => _ChangeMemberRoleDialog(
          member: member,
          roles: roles,
          capabilitiesByRole: capabilitiesByRole,
          onSubmit: onSubmit,
        ),
  );
}

class _ChangeMemberRoleDialog extends StatefulWidget {
  const _ChangeMemberRoleDialog({
    required this.member,
    required this.roles,
    required this.capabilitiesByRole,
    required this.onSubmit,
  });

  final WorkspaceMemberDirectoryEntry member;
  final List<WorkspaceRole> roles;
  final Map<String, List<WorkspaceRoleCapability>> capabilitiesByRole;
  final AdminMembersChangeRoleSubmit onSubmit;

  @override
  State<_ChangeMemberRoleDialog> createState() =>
      _ChangeMemberRoleDialogState();
}

class _ChangeMemberRoleDialogState extends State<_ChangeMemberRoleDialog> {
  final _reason = TextEditingController();

  late String _currentRoleId = widget.member.roleId;
  late String _selectedRoleId = widget.member.roleId;
  late int _baselineVersion = widget.member.version;
  bool _submitting = false;
  String? _inlineError;
  MembershipVersionConflict? _conflict;

  String get _memberName =>
      widget.member.displayName ?? widget.member.email ?? widget.member.userId;

  bool get _dirty =>
      _selectedRoleId != _currentRoleId || _reason.text.trim().isNotEmpty;

  List<WorkspaceRoleCapability> _capabilitiesOf(String roleId) =>
      widget.capabilitiesByRole[roleId] ?? const <WorkspaceRoleCapability>[];

  bool _grantsManage(String roleId) => _capabilitiesOf(
    roleId,
  ).any((capability) => capability.permissionKey == 'security.manage');

  String _roleName(String roleId) {
    for (final role in widget.roles) {
      if (role.id == roleId) {
        return role.name;
      }
    }
    return roleId;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submitWithGuard() async {
    if (_selectedRoleId == _currentRoleId) {
      return;
    }
    final fromManage = _grantsManage(_currentRoleId);
    final toManage = _grantsManage(_selectedRoleId);
    if (fromManage != toManage) {
      final consequence =
          toManage
              ? '„$_memberName" erhält mit der Rolle „${_roleName(_selectedRoleId)}" '
                  'die Sicherheitsverwaltung (security.manage) für diesen '
                  'Workspace.'
              : '„$_memberName" verliert mit der Rolle „${_roleName(_selectedRoleId)}" '
                  'die Sicherheitsverwaltung (security.manage) für diesen '
                  'Workspace.';
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (guardContext) => AlertDialog(
              title: const Text('Sicherheitsverwaltung ändern?'),
              content: Text(consequence),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(guardContext).pop(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  key: const Key('admin-members-role-guard-confirm'),
                  onPressed: () => Navigator.of(guardContext).pop(true),
                  child: const Text('Rolle ändern'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await _performSubmit(_baselineVersion);
  }

  Future<void> _performSubmit(int expectedVersion) async {
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final outcome = await widget.onSubmit(
      membershipId: widget.member.membershipId,
      newRoleId: _selectedRoleId,
      expectedVersion: expectedVersion,
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
    );
    if (!mounted) {
      return;
    }
    switch (outcome.kind) {
      case MembersActionResultKind.success:
        Navigator.of(context).pop();
      case MembersActionResultKind.versionConflict:
        setState(() {
          _submitting = false;
          _conflict = outcome.conflict;
        });
      case MembersActionResultKind.lastSecurityManager:
        setState(() {
          _submitting = false;
          _inlineError =
              '„$_memberName" ist die letzte Person mit Sicherheitsverwaltung '
              'in diesem Workspace. Übertrage die Berechtigung zuerst an '
              'jemand anderen.';
        });
      case MembersActionResultKind.validationFailed:
      case MembersActionResultKind.forbidden:
      case MembersActionResultKind.failed:
        setState(() {
          _submitting = false;
          _inlineError = outcome.message;
        });
    }
  }

  void _reseedFromConflict() {
    final conflict = _conflict;
    if (conflict == null) {
      return;
    }
    setState(() {
      _currentRoleId = conflict.currentMember?.roleId ?? _currentRoleId;
      _selectedRoleId = _currentRoleId;
      _baselineVersion = conflict.actualVersion;
      _reason.clear();
      _conflict = null;
      _inlineError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final conflict = _conflict;
    final showDiff = _selectedRoleId != _currentRoleId;
    final diff =
        showDiff
            ? computeRoleCapabilityDiff(
              from: _capabilitiesOf(_currentRoleId),
              to: _capabilitiesOf(_selectedRoleId),
            )
            : null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard(context);
        }
      },
      child: AlertDialog(
        key: const Key('admin-members-role-dialog'),
        title: const Text('Rolle ändern'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _memberName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'Aktuelle Rolle: ${_roleName(_currentRoleId)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (conflict != null) ...[
                  const SizedBox(height: AppSpacing.component),
                  NxNotice(
                    key: const Key('admin-members-role-dialog-conflict'),
                    kind: NxNoticeKind.warning,
                    title: 'Zwischenzeitlich geändert',
                    message:
                        'Auf dem Server liegt inzwischen Version '
                        '${conflict.actualVersion} (deine Basis war Version '
                        '${conflict.expectedVersion}). Deine Auswahl bleibt '
                        'erhalten.',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      OutlinedButton(
                        key: const Key('admin-members-role-dialog-reload'),
                        onPressed: _submitting ? null : _reseedFromConflict,
                        child: const Text('Neu laden'),
                      ),
                      FilledButton(
                        key: const Key('admin-members-role-dialog-retry'),
                        onPressed:
                            _submitting || _selectedRoleId == _currentRoleId
                                ? null
                                : () => _performSubmit(conflict.actualVersion),
                        child: const Text('Erneut speichern'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.component),
                DropdownButtonFormField<String>(
                  key: const Key('admin-members-role-dialog-dropdown'),
                  value: _selectedRoleId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Neue Rolle'),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem<String>(
                        key: Key('admin-members-role-dialog-option-${role.id}'),
                        value: role.id,
                        child: Text(
                          '${role.name} · '
                          '${_capabilitiesOf(role.id).length} Berechtigungen',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged:
                      _submitting
                          ? null
                          : (value) => setState(
                            () => _selectedRoleId = value ?? _selectedRoleId,
                          ),
                ),
                if (diff != null) ...[
                  const SizedBox(height: AppSpacing.component),
                  Column(
                    key: const Key('admin-members-role-dialog-diff'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (diff.isEmpty)
                        Text(
                          'Keine Änderung der Berechtigungen.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (diff.added.isNotEmpty)
                        Text(
                          'Hinzu kommen: ${_diffNames(diff.added)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (diff.removed.isNotEmpty)
                        Text(
                          'Entfallen: ${_diffNames(diff.removed)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.component),
                TextFormField(
                  key: const Key('admin-members-role-dialog-reason'),
                  controller: _reason,
                  maxLength: _reasonMaxLength,
                  decoration: const InputDecoration(labelText: _reasonLabel),
                ),
                if (_inlineError != null) ...[
                  const SizedBox(height: AppSpacing.component),
                  NxNotice(
                    key: const Key('admin-members-role-dialog-error'),
                    kind: NxNoticeKind.error,
                    message: _inlineError!,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('admin-members-role-dialog-submit'),
            onPressed:
                _submitting || _selectedRoleId == _currentRoleId
                    ? null
                    : _submitWithGuard,
            child:
                _submitting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

String _diffNames(List<WorkspaceRoleCapability> capabilities) {
  const maxShown = 6;
  final names = capabilities
      .map((capability) => capability.permissionName)
      .toList(growable: false);
  if (names.length <= maxShown) {
    return names.join(', ');
  }
  final remaining = names.length - maxShown;
  return '${names.take(maxShown).join(', ')} und $remaining weitere';
}

enum MemberConfirmStyle { neutral, warning, danger }

class MemberConfirmResult {
  const MemberConfirmResult({this.reason});

  final String? reason;
}

/// Confirmation dialog per Foundation §14: names the object, states the
/// consequence in one sentence, verb as confirm label, optional audited
/// reason. Returns null when cancelled.
Future<MemberConfirmResult?> showMemberConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  MemberConfirmStyle style = MemberConfirmStyle.neutral,
}) {
  return showDialog<MemberConfirmResult>(
    context: context,
    builder:
        (_) => _MemberConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          style: style,
        ),
  );
}

class _MemberConfirmDialog extends StatefulWidget {
  const _MemberConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.style,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final MemberConfirmStyle style;

  @override
  State<_MemberConfirmDialog> createState() => _MemberConfirmDialogState();
}

class _MemberConfirmDialogState extends State<_MemberConfirmDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  ButtonStyle? _confirmStyle(BuildContext context) {
    final semantic = context.semanticColors;
    return switch (widget.style) {
      MemberConfirmStyle.neutral => null,
      // Mirrors the audited NxStatusBadge warning pairing — deliberately not
      // the error color: the action is reversible.
      MemberConfirmStyle.warning => FilledButton.styleFrom(
        backgroundColor: semantic.warning.withValues(alpha: 0.16),
        foregroundColor: semantic.warning,
      ),
      MemberConfirmStyle.danger => FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.message),
              const SizedBox(height: AppSpacing.component),
              TextFormField(
                key: const Key('admin-members-confirm-reason'),
                controller: _reason,
                maxLength: _reasonMaxLength,
                decoration: const InputDecoration(labelText: _reasonLabel),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('admin-members-confirm'),
          style: _confirmStyle(context),
          onPressed:
              () => Navigator.of(context).pop(
                MemberConfirmResult(
                  reason:
                      _reason.text.trim().isEmpty ? null : _reason.text.trim(),
                ),
              ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<void> _confirmDiscard(BuildContext dialogContext) async {
  final discard = await showDialog<bool>(
    context: dialogContext,
    builder:
        (confirmContext) => AlertDialog(
          title: const Text('Änderungen verwerfen?'),
          content: const Text(
            'Deine Eingaben in diesem Dialog gehen verloren.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('admin-members-discard-confirm'),
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text('Verwerfen'),
            ),
          ],
        ),
  );
  if (discard == true && dialogContext.mounted) {
    Navigator.of(dialogContext).pop();
  }
}
