import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_data_table_shell.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/components/nx_page_header.dart';
import '../../../ui/components/nx_split_view.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/templates/list_filter_template.dart';
import '../../../ui/theme/app_theme.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/identity_access_repository.dart';
import '../application/members_admin_controller.dart';
import '../application/membership_admin_repository.dart';
import 'membership_badges.dart';
import 'widgets/member_dialogs.dart';
import 'widgets/role_capability_list.dart';

export 'widgets/member_dialogs.dart'
    show
        AdminMembersChangeRoleSubmit,
        AdminMembersInviteSubmit,
        AdminMembersRevokeInvitationSubmit,
        AdminMembersUpdateStatusSubmit;

/// ADMIN-AREA-01 A1: the product V2 members administration surface
/// ("Mitglieder", `GlobalPage.adminUsers`, route `/members`), replacing the
/// reference-slice presentation. Tabs Mitglieder / Einladungen / Rollen;
/// the Aktivität tab is increment A2, the invite-accept relocation is
/// package B — until B lands, the own-invitations zone stays functional here.
class AdminMembersScreen extends ConsumerWidget {
  const AdminMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(referenceSliceControllerProvider);

    if (reference.authPhase == ReferenceAuthPhase.loading) {
      return const Center(
        key: Key('admin-members-auth-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (reference.authPhase != ReferenceAuthPhase.authenticated ||
        reference.userId == null) {
      return Padding(
        padding: EdgeInsets.all(context.adaptivePagePadding),
        child: const NxEmptyState(
          key: Key('admin-members-signed-out'),
          title: 'Anmeldung erforderlich',
          description:
              'Die Mitgliederverwaltung ist nach der Anmeldung verfügbar.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final access = reference.selectedWorkspace;
    final scope = MembersAdminScope(
      workspaceId: access?.workspace.id,
      actorId: reference.userId!,
      permissions: access?.permissions ?? const <String>{},
      canMutate: reference.assuranceLevel == AuthenticationAssuranceLevel.aal2,
    );
    final state = ref.watch(membersAdminControllerProvider(scope));
    final controller = ref.read(membersAdminControllerProvider(scope).notifier);

    ref.listen<MembersAdminState>(membersAdminControllerProvider(scope), (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      switch (next.actionPhase) {
        case MembersActionPhase.succeeded:
        case MembersActionPhase.forbidden:
        case MembersActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case MembersActionPhase.idle:
        case MembersActionPhase.submitting:
        case MembersActionPhase.conflict:
        case MembersActionPhase.validationFailed:
          // Conflict and validation outcomes are handled inline by the
          // dialogs/confirm flows that triggered them.
          break;
      }
    });

    return AdminMembersView(
      key: ValueKey<String?>(access?.workspace.id),
      state: state,
      workspaceName: access?.workspace.name,
      canManage: controller.canManageMembers,
      canMutate: controller.canMutate,
      onRefresh: controller.refreshAll,
      onReloadDirectory: controller.reloadDirectory,
      onReloadInvitations: controller.reloadInvitations,
      onReloadRoles: controller.reloadRoles,
      onReloadPending: controller.reloadPending,
      onInvite: controller.invite,
      onChangeRole: controller.changeRole,
      onUpdateStatus: controller.updateStatus,
      onRevokeInvitation: controller.revokeInvitation,
      onAcceptOwnInvitation: controller.acceptOwnInvitation,
    );
  }
}

class AdminMembersView extends StatefulWidget {
  const AdminMembersView({
    super.key,
    required this.state,
    required this.workspaceName,
    required this.canManage,
    required this.canMutate,
    required this.onRefresh,
    required this.onReloadDirectory,
    required this.onReloadInvitations,
    required this.onReloadRoles,
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
  final Future<void> Function() onRefresh;
  final Future<void> Function() onReloadDirectory;
  final Future<void> Function() onReloadInvitations;
  final Future<void> Function() onReloadRoles;
  final Future<void> Function() onReloadPending;
  final AdminMembersInviteSubmit onInvite;
  final AdminMembersChangeRoleSubmit onChangeRole;
  final AdminMembersUpdateStatusSubmit onUpdateStatus;
  final AdminMembersRevokeInvitationSubmit onRevokeInvitation;
  final Future<void> Function(PendingInvitationEntry entry)
  onAcceptOwnInvitation;

  @override
  State<AdminMembersView> createState() => _AdminMembersViewState();
}

class _AdminMembersViewState extends State<AdminMembersView>
    with SingleTickerProviderStateMixin {
  static const _aal2Tooltip =
      'Erfordert Multi-Faktor-Authentifizierung (AAL2). Siehe Hinweis oben.';

  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  final TextEditingController _search = TextEditingController();
  String? _roleFilter;
  MembershipStatus? _statusFilter;
  String? _selectedMembershipId;

  @override
  void dispose() {
    _tabController.dispose();
    _search.dispose();
    super.dispose();
  }

  MembersAdminState get _state => widget.state;

  @override
  Widget build(BuildContext context) {
    final padding = context.adaptivePagePadding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
          child: NxPageHeader(
            key: const Key('admin-members-header'),
            title: 'Mitglieder',
            breadcrumbs: const ['Setup & Verwaltung', 'Mitglieder'],
            subtitle:
                widget.workspaceName == null
                    ? 'Verwaltung der Workspace-Mitglieder.'
                    : 'Mitglieder von ${widget.workspaceName}.',
            secondaryActions: [
              OutlinedButton.icon(
                key: const Key('admin-members-refresh'),
                onPressed: _state.refreshing ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _state.refreshing ? 'Aktualisiert …' : 'Aktualisieren',
                ),
              ),
            ],
            primaryAction: _inviteButton(context),
          ),
        ),
        ..._pendingZone(context, padding),
        if (widget.canManage && !widget.canMutate)
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              AppSpacing.component,
              padding,
              0,
            ),
            child: const NxNotice(
              key: Key('admin-members-mfa-hint'),
              kind: NxNoticeKind.warning,
              message:
                  'Richte Multi-Faktor-Authentifizierung ein, um Mitglieder '
                  'zu ändern. Ansehen ist jetzt möglich.',
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            AppSpacing.component,
            padding,
            0,
          ),
          child: NxCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(
                  key: Key('admin-members-tab-members'),
                  text: 'Mitglieder',
                ),
                Tab(
                  key: const Key('admin-members-tab-invitations'),
                  text:
                      _state.invitations.isEmpty
                          ? 'Einladungen'
                          : 'Einladungen (${_state.invitations.length})',
                ),
                const Tab(key: Key('admin-members-tab-roles'), text: 'Rollen'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  AppSpacing.component,
                  padding,
                  padding,
                ),
                child: _membersTab(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  AppSpacing.component,
                  padding,
                  padding,
                ),
                child: _invitationsTab(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  AppSpacing.component,
                  padding,
                  padding,
                ),
                child: _rolesTab(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Header actions -------------------------------------------------------

  Widget _inviteButton(BuildContext context) {
    final rolesReady = _state.roles.isNotEmpty;
    final enabled = widget.canManage && widget.canMutate && rolesReady;
    final tooltip =
        !widget.canManage
            ? 'Benötigt die Berechtigung (security.manage)'
            : !widget.canMutate
            ? _aal2Tooltip
            : !rolesReady
            ? 'Rollen sind noch nicht geladen.'
            : 'Neues Mitglied per E-Mail einladen';
    return Tooltip(
      key: const Key('admin-members-invite'),
      message: tooltip,
      child: FilledButton.icon(
        onPressed: enabled ? _openInviteDialog : null,
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Mitglied einladen'),
      ),
    );
  }

  void _openInviteDialog() {
    showInviteMemberDialog(
      context,
      roles: _state.roles,
      capabilitiesByRole: roleCapabilitiesByRole(_state.roleCapabilities),
      onSubmit: widget.onInvite,
    );
  }

  // --- Own invitations (stays until package B) ------------------------------

  List<Widget> _pendingZone(BuildContext context, double padding) {
    switch (_state.pendingPhase) {
      case MembersPendingPhase.loading:
      case MembersPendingPhase.empty:
        return const <Widget>[];
      case MembersPendingPhase.error:
        return <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              AppSpacing.component,
              padding,
              0,
            ),
            child: NxCard(
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Deine Einladungen konnten nicht geladen werden.',
                    ),
                  ),
                  TextButton(
                    key: const Key('admin-members-pending-retry'),
                    onPressed: widget.onReloadPending,
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ];
      case MembersPendingPhase.ready:
        return <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              AppSpacing.component,
              padding,
              0,
            ),
            child: Column(
              key: const Key('admin-members-pending-zone'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Deine Einladungen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final entry in _state.pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _pendingCard(context, entry),
                  ),
              ],
            ),
          ),
        ];
    }
  }

  Widget _pendingCard(BuildContext context, PendingInvitationEntry entry) {
    final submitting = _state.actionPhase == MembersActionPhase.submitting;
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
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Eingeladen als ${entry.roleName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: widget.canMutate ? 'Einladung annehmen' : _aal2Tooltip,
            child: FilledButton.tonal(
              key: Key('admin-members-accept-${entry.workspaceId}'),
              onPressed:
                  submitting || !widget.canMutate
                      ? null
                      : () => widget.onAcceptOwnInvitation(entry),
              child: const Text('Annehmen'),
            ),
          ),
        ],
      ),
    );
  }

  // --- Mitglieder tab -------------------------------------------------------

  Widget _membersTab(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AppBreakpoints.mobileMax) {
          return _membersTabMobile(context);
        }
        final phase = _state.directoryPhase;
        final showFilters =
            phase == MembersTabPhase.ready || phase == MembersTabPhase.empty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showFilters) ...[
              _filterBar(context),
              const SizedBox(height: AppSpacing.component),
            ],
            Expanded(child: _membersContent(context)),
          ],
        );
      },
    );
  }

  /// Phone layout (Foundation §15): one targeted scroll region holding the
  /// filter bar and the ListTile rows; an open detail replaces the list with
  /// a "Zur Liste" back affordance, mirroring the NxSplitView narrow pattern.
  Widget _membersTabMobile(BuildContext context) {
    final phase = _state.directoryPhase;
    if (phase == MembersTabPhase.ready && _selectedMembershipId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedMembershipId = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Zur Liste'),
            ),
          ),
          Expanded(child: _memberDetail(context)),
        ],
      );
    }
    final showFilters =
        phase == MembersTabPhase.ready || phase == MembersTabPhase.empty;
    final children = <Widget>[
      if (showFilters) ...[
        _filterBar(context),
        const SizedBox(height: AppSpacing.component),
      ],
    ];
    if (phase == MembersTabPhase.ready) {
      final filtered = _filteredDirectory();
      if (filtered.isEmpty) {
        children.add(_noMatchState());
      } else {
        children.addAll(_mobileTiles(context, filtered));
      }
    } else {
      children.add(_directoryStateWidget(context));
    }
    return ListView(
      key: const Key('admin-members-mobile-list'),
      children: children,
    );
  }

  Widget _filterBar(BuildContext context) {
    final compact = context.compactLayout;
    final filtered = _filteredDirectory();
    return ListFilterBar(
      trailing: NxStatusBadge(
        key: const Key('admin-members-count'),
        label:
            filtered.length == 1
                ? '1 Mitglied'
                : '${filtered.length} Mitglieder',
      ),
      children: [
        SizedBox(
          width: compact ? 180 : 260,
          child: TextField(
            key: const Key('admin-members-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Suche',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: const Key('admin-members-role-filter'),
            value: _roleFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Rolle'),
            items: [
              const DropdownMenuItem<String?>(
                key: Key('admin-members-role-filter-all'),
                value: null,
                child: Text('Alle Rollen'),
              ),
              for (final role in _state.roles)
                DropdownMenuItem<String?>(
                  key: Key('admin-members-role-filter-${role.id}'),
                  value: role.id,
                  child: Text(role.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _roleFilter = value),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<MembershipStatus?>(
            key: const Key('admin-members-status-filter'),
            value: _statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem<MembershipStatus?>(
                key: Key('admin-members-status-filter-all'),
                value: null,
                child: Text('Alle aktiven'),
              ),
              for (final status in MembershipStatus.values)
                DropdownMenuItem<MembershipStatus?>(
                  key: Key('admin-members-status-filter-${status.name}'),
                  value: status,
                  child: Text(membershipStatusLabel(status)),
                ),
            ],
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
        ),
      ],
    );
  }

  List<WorkspaceMemberDirectoryEntry> _filteredDirectory() {
    return filterMemberDirectory(
      _state.directory,
      query: _search.text,
      roleId: _roleFilter,
      status: _statusFilter,
    );
  }

  Widget _membersContent(BuildContext context) {
    if (_state.directoryPhase != MembersTabPhase.ready) {
      return _directoryStateWidget(context);
    }
    final filtered = _filteredDirectory();
    if (filtered.isEmpty) {
      return _noMatchState();
    }
    return NxSplitView(
      list: _memberTable(context, filtered),
      detail: _memberDetail(context),
      showDetail: _selectedMembershipId != null,
      onBackToList: () => setState(() => _selectedMembershipId = null),
    );
  }

  Widget _directoryStateWidget(BuildContext context) {
    switch (_state.directoryPhase) {
      case MembersTabPhase.idle:
        return const NxEmptyState(
          key: Key('admin-members-directory-idle'),
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Wähle einen Workspace, um dessen Mitglieder zu verwalten.',
          icon: Icons.workspaces_outline,
        );
      case MembersTabPhase.loading:
        return const NxListSkeleton(
          key: Key('admin-members-directory-skeleton'),
        );
      case MembersTabPhase.forbidden:
        return const NxEmptyState(
          key: Key('admin-members-directory-forbidden'),
          title: 'Kein Zugriff auf Mitglieder',
          description:
              'Die Mitgliederverwaltung benötigt die Berechtigung '
              '(security.manage).',
          icon: Icons.lock_outline,
        );
      case MembersTabPhase.error:
        return NxEmptyState.error(
          key: const Key('admin-members-directory-error'),
          description:
              'Das Mitglieder-Verzeichnis konnte nicht geladen werden.',
          onRetry: widget.onReloadDirectory,
        );
      case MembersTabPhase.empty:
        return NxEmptyState(
          key: const Key('admin-members-directory-empty'),
          title: 'Noch keine Mitglieder',
          description: 'Lade die erste Person in diesen Workspace ein.',
          icon: Icons.group_outlined,
          primaryAction:
              widget.canManage
                  ? Tooltip(
                    message:
                        widget.canMutate
                            ? 'Neues Mitglied per E-Mail einladen'
                            : _aal2Tooltip,
                    child: OutlinedButton.icon(
                      key: const Key('admin-members-empty-invite'),
                      onPressed:
                          widget.canMutate && _state.roles.isNotEmpty
                              ? _openInviteDialog
                              : null,
                      icon: const Icon(Icons.person_add_alt_outlined),
                      label: const Text('Mitglied einladen'),
                    ),
                  )
                  : null,
        );
      case MembersTabPhase.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _noMatchState() {
    return NxEmptyState(
      key: const Key('admin-members-no-match'),
      title: 'Keine Treffer',
      description: 'Keine Treffer für diesen Filter.',
      icon: Icons.filter_alt_off_outlined,
      primaryAction: OutlinedButton(
        key: const Key('admin-members-reset-filters'),
        onPressed:
            () => setState(() {
              _search.clear();
              _roleFilter = null;
              _statusFilter = null;
            }),
        child: const Text('Filter zurücksetzen'),
      ),
    );
  }

  Widget _memberTable(
    BuildContext context,
    List<WorkspaceMemberDirectoryEntry> entries,
  ) {
    return NxDataTableShell(
      minTableWidth: 760,
      mobileBreakpoint: 640,
      mobileChild: _memberMobileList(context, entries),
      child: _memberDataTable(context, entries),
    );
  }

  Widget _memberDataTable(
    BuildContext context,
    List<WorkspaceMemberDirectoryEntry> entries,
  ) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return DataTable(
      showCheckboxColumn: false,
      columns: [
        DataColumn(label: Text('NAME', style: labelStyle)),
        DataColumn(label: Text('E-MAIL', style: labelStyle)),
        DataColumn(label: Text('ROLLE', style: labelStyle)),
        DataColumn(label: Text('STATUS', style: labelStyle)),
        DataColumn(label: Text('SEIT', style: labelStyle)),
        DataColumn(label: Text('', style: labelStyle)),
      ],
      rows: [
        for (final entry in entries)
          DataRow(
            key: ValueKey<String>('admin-members-row-${entry.membershipId}'),
            selected: entry.membershipId == _selectedMembershipId,
            onSelectChanged:
                (_) =>
                    setState(() => _selectedMembershipId = entry.membershipId),
            cells: [
              DataCell(Text(_displayName(entry))),
              DataCell(
                Text(entry.email ?? '—', overflow: TextOverflow.ellipsis),
              ),
              DataCell(NxStatusBadge(label: entry.roleName)),
              DataCell(
                NxStatusBadge(
                  label: membershipStatusLabel(entry.status),
                  kind: membershipStatusBadgeKind(entry.status),
                ),
              ),
              DataCell(
                Text(
                  _formatDate(entry.createdAt),
                  style: context.tabularNumericStyle,
                ),
              ),
              DataCell(_rowMenu(context, entry)),
            ],
          ),
      ],
    );
  }

  Widget _memberMobileList(
    BuildContext context,
    List<WorkspaceMemberDirectoryEntry> entries,
  ) {
    return ListView(
      key: const Key('admin-members-mobile-list'),
      children: _mobileTiles(context, entries),
    );
  }

  List<Widget> _mobileTiles(
    BuildContext context,
    List<WorkspaceMemberDirectoryEntry> entries,
  ) {
    return [
      for (final entry in entries)
        ListTile(
          key: Key('admin-members-mobile-row-${entry.membershipId}'),
          selected: entry.membershipId == _selectedMembershipId,
          leading: const Icon(Icons.person_outline),
          title: Text(_displayName(entry), overflow: TextOverflow.ellipsis),
          subtitle: Text(
            entry.email ?? entry.roleName,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NxStatusBadge(
                label: membershipStatusLabel(entry.status),
                kind: membershipStatusBadgeKind(entry.status),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap:
              () => setState(() => _selectedMembershipId = entry.membershipId),
        ),
    ];
  }

  Widget _rowMenu(BuildContext context, WorkspaceMemberDirectoryEntry entry) {
    if (!widget.canManage || entry.status == MembershipStatus.revoked) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: widget.canMutate ? 'Aktionen' : _aal2Tooltip,
      child: PopupMenuButton<String>(
        key: Key('admin-members-row-menu-${entry.membershipId}'),
        enabled: widget.canMutate,
        icon: const Icon(Icons.more_vert),
        itemBuilder:
            (_) => [
              const PopupMenuItem(
                key: Key('admin-members-menu-change-role'),
                value: 'role',
                child: Text('Rolle ändern'),
              ),
              if (entry.status == MembershipStatus.active)
                const PopupMenuItem(
                  key: Key('admin-members-menu-suspend'),
                  value: 'suspend',
                  child: Text('Suspendieren'),
                ),
              if (entry.status == MembershipStatus.suspended)
                const PopupMenuItem(
                  key: Key('admin-members-menu-reactivate'),
                  value: 'reactivate',
                  child: Text('Reaktivieren'),
                ),
              const PopupMenuItem(
                key: Key('admin-members-menu-revoke'),
                value: 'revoke',
                child: Text('Zugriff entziehen'),
              ),
            ],
        onSelected: (action) {
          switch (action) {
            case 'role':
              _openChangeRoleDialog(entry);
            case 'suspend':
              unawaited(_confirmSuspend(entry));
            case 'reactivate':
              unawaited(_confirmReactivate(entry));
            case 'revoke':
              unawaited(_confirmRevoke(entry));
          }
        },
      ),
    );
  }

  Widget _memberDetail(BuildContext context) {
    final selectedId = _selectedMembershipId;
    if (selectedId == null) {
      return const NxCard(
        key: Key('admin-members-detail-idle'),
        child: Center(child: Text('Wähle ein Mitglied.')),
      );
    }
    WorkspaceMemberDirectoryEntry? entry;
    for (final candidate in _state.directory) {
      if (candidate.membershipId == selectedId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return const NxCard(
        key: Key('admin-members-detail-missing'),
        child: Center(
          child: Text(
            'Das Mitglied wurde entfernt oder geändert, während die Liste '
            'geöffnet war.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    final roleCapabilities =
        roleCapabilitiesByRole(_state.roleCapabilities)[entry.roleId] ??
        const <WorkspaceRoleCapability>[];
    return NxCard(
      key: const Key('admin-members-detail'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayName(entry),
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                NxStatusBadge(
                  label: membershipStatusLabel(entry.status),
                  kind: membershipStatusBadgeKind(entry.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _fact(context, 'E-Mail', entry.email ?? '—'),
            _fact(context, 'Rolle', entry.roleName),
            _fact(context, 'Status', membershipStatusLabel(entry.status)),
            _fact(
              context,
              entry.status == MembershipStatus.invited
                  ? 'Eingeladen am'
                  : 'Mitglied seit',
              _formatDate(entry.createdAt),
            ),
            _fact(context, 'Zuletzt geändert', _formatDate(entry.updatedAt)),
            if (entry.displayName == null && entry.email == null)
              _fact(context, 'Nutzer-ID', entry.userId),
            const SizedBox(height: AppSpacing.section),
            Text('Rolle & Berechtigungen', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (_state.rolesPhase == MembersTabPhase.ready)
              RoleCapabilityList(
                capabilities: roleCapabilities,
                title: Text(
                  '${roleCapabilities.length} Berechtigungen',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Text(
                'Berechtigungen sind derzeit nicht verfügbar.',
                style: theme.textTheme.bodySmall,
              ),
            if (widget.canManage &&
                entry.status != MembershipStatus.revoked) ...[
              const SizedBox(height: AppSpacing.section),
              Text('Aktionen', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              _detailActions(context, entry),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _detailActions(
    BuildContext context,
    WorkspaceMemberDirectoryEntry entry,
  ) {
    Widget action({
      required Key key,
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return Tooltip(
        key: key,
        message: widget.canMutate ? label : _aal2Tooltip,
        child: OutlinedButton.icon(
          onPressed: widget.canMutate ? onPressed : null,
          icon: Icon(icon, color: color),
          label: Text(
            label,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        action(
          key: const Key('admin-members-action-change-role'),
          label: 'Rolle ändern',
          icon: Icons.manage_accounts_outlined,
          onPressed: () => _openChangeRoleDialog(entry),
        ),
        if (entry.status == MembershipStatus.active)
          action(
            key: const Key('admin-members-action-suspend'),
            label: 'Suspendieren',
            icon: Icons.pause_circle_outline,
            onPressed: () => _confirmSuspend(entry),
          ),
        if (entry.status == MembershipStatus.suspended)
          action(
            key: const Key('admin-members-action-reactivate'),
            label: 'Reaktivieren',
            icon: Icons.play_circle_outline,
            onPressed: () => _confirmReactivate(entry),
          ),
        action(
          key: const Key('admin-members-action-revoke'),
          label: 'Zugriff entziehen',
          icon: Icons.person_off_outlined,
          onPressed: () => _confirmRevoke(entry),
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }

  // --- Membership actions ---------------------------------------------------

  void _openChangeRoleDialog(WorkspaceMemberDirectoryEntry entry) {
    showChangeMemberRoleDialog(
      context,
      member: entry,
      roles: _state.roles,
      capabilitiesByRole: roleCapabilitiesByRole(_state.roleCapabilities),
      onSubmit: widget.onChangeRole,
    );
  }

  Future<void> _confirmSuspend(WorkspaceMemberDirectoryEntry entry) async {
    final name = _displayName(entry);
    final result = await showMemberConfirmDialog(
      context,
      title: 'Mitglied suspendieren?',
      message:
          '„$name" verliert den Zugriff, bis die Mitgliedschaft wieder '
          'aktiviert wird. Das ist umkehrbar.',
      confirmLabel: 'Suspendieren',
      style: MemberConfirmStyle.warning,
    );
    if (result == null) {
      return;
    }
    final outcome = await widget.onUpdateStatus(
      membershipId: entry.membershipId,
      newStatus: MembershipStatus.suspended,
      expectedVersion: entry.version,
      reason: result.reason,
    );
    _handleConfirmFlowOutcome(outcome, name);
  }

  Future<void> _confirmReactivate(WorkspaceMemberDirectoryEntry entry) async {
    final name = _displayName(entry);
    final result = await showMemberConfirmDialog(
      context,
      title: 'Mitglied reaktivieren?',
      message: '„$name" erhält den vorherigen Zugriff zurück.',
      confirmLabel: 'Reaktivieren',
    );
    if (result == null) {
      return;
    }
    final outcome = await widget.onUpdateStatus(
      membershipId: entry.membershipId,
      newStatus: MembershipStatus.active,
      expectedVersion: entry.version,
      reason: result.reason,
    );
    _handleConfirmFlowOutcome(outcome, name);
  }

  Future<void> _confirmRevoke(WorkspaceMemberDirectoryEntry entry) async {
    final name = _displayName(entry);
    final result = await showMemberConfirmDialog(
      context,
      title: 'Zugriff entziehen?',
      message:
          'Endgültig. „$name" verliert den Zugriff dauerhaft; die '
          'Mitgliedschaft kann nicht wiederhergestellt und die Person mit '
          'dieser Mitgliedschaft nicht erneut eingeladen werden.',
      confirmLabel: 'Entziehen',
      style: MemberConfirmStyle.danger,
    );
    if (result == null) {
      return;
    }
    final outcome = await widget.onUpdateStatus(
      membershipId: entry.membershipId,
      newStatus: MembershipStatus.revoked,
      expectedVersion: entry.version,
      reason: result.reason,
    );
    _handleConfirmFlowOutcome(outcome, name);
  }

  /// Confirm-flow failures that the screen's SnackBar listener deliberately
  /// skips (validation, last manager, conflict) get their German explanation
  /// here — the confirm dialog is already closed when the server answers.
  void _handleConfirmFlowOutcome(MembersActionOutcome outcome, String name) {
    if (!mounted) {
      return;
    }
    final message = switch (outcome.kind) {
      MembersActionResultKind.lastSecurityManager =>
        '„$name" ist die letzte Person mit Sicherheitsverwaltung in diesem '
            'Workspace. Übertrage die Berechtigung zuerst an jemand anderen.',
      MembersActionResultKind.validationFailed => outcome.message,
      MembersActionResultKind.versionConflict =>
        'Der Eintrag wurde zwischenzeitlich geändert. Die Liste wurde '
            'aktualisiert – bitte prüfe den Stand und versuche es erneut.',
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- Einladungen tab ------------------------------------------------------

  Widget _invitationsTab(BuildContext context) {
    switch (_state.invitationsPhase) {
      case MembersTabPhase.idle:
        return const NxEmptyState(
          key: Key('admin-members-invitations-idle'),
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Wähle einen Workspace, um dessen Einladungen zu verwalten.',
          icon: Icons.workspaces_outline,
        );
      case MembersTabPhase.loading:
        return const NxListSkeleton(
          key: Key('admin-members-invitations-skeleton'),
          rows: 3,
        );
      case MembersTabPhase.forbidden:
        return const NxEmptyState(
          key: Key('admin-members-invitations-forbidden'),
          title: 'Kein Zugriff auf Einladungen',
          description:
              'Die Einladungsverwaltung benötigt die Berechtigung '
              '(security.manage).',
          icon: Icons.lock_outline,
        );
      case MembersTabPhase.error:
        return NxEmptyState.error(
          key: const Key('admin-members-invitations-error'),
          description: 'Die Einladungen konnten nicht geladen werden.',
          onRetry: widget.onReloadInvitations,
        );
      case MembersTabPhase.empty:
        return const NxEmptyState(
          key: Key('admin-members-invitations-empty'),
          title: 'Keine offenen Einladungen',
          description: 'Neue Einladungen legst du über „Mitglied einladen" an.',
          icon: Icons.mark_email_read_outlined,
        );
      case MembersTabPhase.ready:
        return ListView(
          children: [
            for (final invitation in _state.invitations)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _invitationCard(context, invitation),
              ),
          ],
        );
    }
  }

  Widget _invitationCard(
    BuildContext context,
    MembershipInvitation invitation,
  ) {
    final roleName = _roleNameById(invitation.roleId);
    return NxCard(
      key: Key('admin-members-invitation-card-${invitation.id}'),
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
                  '$roleName · Ausstehend seit '
                  '${_formatDate(invitation.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const NxStatusBadge(label: 'Ausstehend', kind: NxBadgeKind.info),
          if (widget.canManage) ...[
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: widget.canMutate ? 'Einladung widerrufen' : _aal2Tooltip,
              child: OutlinedButton(
                key: Key('admin-members-invitation-revoke-${invitation.id}'),
                onPressed:
                    widget.canMutate
                        ? () => _confirmRevokeInvitation(invitation)
                        : null,
                child: const Text('Widerrufen'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRevokeInvitation(MembershipInvitation invitation) async {
    final result = await showMemberConfirmDialog(
      context,
      title: 'Einladung widerrufen?',
      message:
          'Die Einladung an „${invitation.email}" wird widerrufen. Die '
          'Person kann später neu eingeladen werden.',
      confirmLabel: 'Widerrufen',
      style: MemberConfirmStyle.danger,
    );
    if (result == null) {
      return;
    }
    final outcome = await widget.onRevokeInvitation(
      invitationId: invitation.id,
      expectedVersion: invitation.version,
      reason: result.reason,
    );
    _handleConfirmFlowOutcome(outcome, invitation.email);
  }

  // --- Rollen tab (read-only) ----------------------------------------------

  Widget _rolesTab(BuildContext context) {
    switch (_state.rolesPhase) {
      case MembersTabPhase.idle:
        return const NxEmptyState(
          key: Key('admin-members-roles-idle'),
          title: 'Kein Arbeitsbereich aktiv',
          description: 'Wähle einen Workspace, um dessen Rollen einzusehen.',
          icon: Icons.workspaces_outline,
        );
      case MembersTabPhase.loading:
        return const NxListSkeleton(
          key: Key('admin-members-roles-skeleton'),
          rows: 4,
          rowHeight: 56,
        );
      case MembersTabPhase.forbidden:
        return const NxEmptyState(
          key: Key('admin-members-roles-forbidden'),
          title: 'Kein Zugriff auf Rollen',
          description:
              'Die Rollenübersicht benötigt die Berechtigung '
              '(workspace.read).',
          icon: Icons.lock_outline,
        );
      case MembersTabPhase.error:
        return NxEmptyState.error(
          key: const Key('admin-members-roles-error'),
          description:
              'Rollen und Berechtigungen konnten nicht geladen werden.',
          onRetry: widget.onReloadRoles,
        );
      case MembersTabPhase.empty:
        return const NxEmptyState(
          key: Key('admin-members-roles-empty'),
          title: 'Keine Rollen definiert',
          description:
              'Für diesen Workspace sind noch keine Rollen hinterlegt.',
          icon: Icons.badge_outlined,
        );
      case MembersTabPhase.ready:
        final capabilitiesByRole = roleCapabilitiesByRole(
          _state.roleCapabilities,
        );
        return ListView(
          children: [
            for (final role in _state.roles)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _roleCard(
                  context,
                  role,
                  capabilitiesByRole[role.id] ??
                      const <WorkspaceRoleCapability>[],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Rollen und Berechtigungen werden zentral gepflegt und sind '
                'hier nur einsehbar.',
                key: const Key('admin-members-roles-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
    }
  }

  Widget _roleCard(
    BuildContext context,
    WorkspaceRole role,
    List<WorkspaceRoleCapability> capabilities,
  ) {
    final memberCount =
        _state.directoryPhase == MembersTabPhase.ready
            ? _state.directory
                .where(
                  (entry) =>
                      entry.roleId == role.id &&
                      entry.status != MembershipStatus.revoked,
                )
                .length
            : null;
    final countText =
        memberCount == null
            ? ''
            : memberCount == 1
            ? '1 Mitglied · '
            : '$memberCount Mitglieder · ';
    return NxCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: RoleCapabilityList(
        key: Key('admin-members-role-card-${role.id}'),
        capabilities: capabilities,
        title: Row(
          children: [
            Expanded(
              child: Text(
                role.name,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(role.key, style: context.dataMonoStyle),
          ],
        ),
        subtitle: Text(
          '${countText}Diese Rolle bündelt ${capabilities.length} '
          'Berechtigungen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  // --- Shared helpers -------------------------------------------------------

  String _displayName(WorkspaceMemberDirectoryEntry entry) {
    return entry.displayName ?? entry.email ?? '—';
  }

  String _roleNameById(String roleId) {
    for (final role in _state.roles) {
      if (role.id == roleId) {
        return role.name;
      }
    }
    return '—';
  }
}

String _formatDate(DateTime timestamp) {
  final local = timestamp.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}
