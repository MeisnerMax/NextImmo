import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/security.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/security_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<LocalUserRecord> _users = const <LocalUserRecord>[];
  bool _loading = true;
  String? _error;
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityControllerProvider).valueOrNull;
    final activeWorkspace = security?.context.workspace;
    final activeUserId = security?.context.user.id;
    final filtered = _users
        .where((user) => _roleFilter == 'all' || user.role == _roleFilter)
        .toList(growable: false);

    return ListFilterTemplate(
      title: 'Benutzer',
      breadcrumbs: const ['Administration', 'Benutzer'],
      subtitle:
          'Workspace-Zugriffe, Rollen und lokale Benutzer zentral verwalten.',
      primaryAction: ElevatedButton.icon(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Benutzer anlegen'),
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Aktualisieren'),
        ),
      ],
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              value: _roleFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Alle Rollen')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
                DropdownMenuItem(value: 'operations', child: Text('Operations')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
              ],
              onChanged:
                  (value) => setState(() => _roleFilter = value ?? 'all'),
              decoration: const InputDecoration(
                labelText: 'Rolle',
                prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              ),
            ),
          ),
          NxStatusBadge(
            label: '${filtered.length} Benutzer',
            kind: NxBadgeKind.info,
          ),
        ],
      ),
      contextBar: NxCard(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Row(
          children: [
            const Icon(Icons.workspaces_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Workspace: ${activeWorkspace?.name ?? '-'}'),
            ),
          ],
        ),
      ),
      content:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? NxEmptyState(
                    title: 'Benutzer konnten nicht geladen werden',
                    description: _error!,
                    icon: Icons.error_outline,
                    primaryAction: OutlinedButton(
                      onPressed: _load,
                      child: const Text('Erneut laden'),
                    ),
                  )
                  : filtered.isEmpty
                      ? const NxEmptyState(
                        title: 'Keine Benutzer',
                        description: 'Filter ändern oder Benutzer anlegen.',
                        icon: Icons.people_outline,
                      )
                      : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder:
                            (_, __) =>
                                const SizedBox(height: AppSpacing.component),
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          return _UserCard(
                            user: user,
                            isActiveUser: user.id == activeUserId,
                            onRoleChanged:
                                (role) => _updateRole(user: user, role: role),
                            onDelete: () => _confirmDelete(user),
                          );
                        },
                      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = ref.read(securityControllerProvider).valueOrNull;
      if (state == null) {
        throw StateError('Sicherheitskontext ist noch nicht bereit.');
      }
      final users = await ref
          .read(securityControllerProvider.notifier)
          .listUsers(state.context.workspace.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _formatError(error);
        _loading = false;
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final displayNameController = TextEditingController();
    final emailController = TextEditingController();
    String role = 'viewer';
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Benutzer anlegen'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: displayNameController,
                      decoration: InputDecoration(
                        labelText: 'Anzeigename',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail optional',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: _roleItems,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => role = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Rolle',
                        prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final state =
                        ref.read(securityControllerProvider).valueOrNull;
                    final displayName = displayNameController.text.trim();
                    if (displayName.isEmpty) {
                      setDialogState(() {
                        errorText = 'Anzeigename ist erforderlich.';
                      });
                      return;
                    }
                    if (state == null) {
                      return;
                    }
                    try {
                      await ref
                          .read(securityControllerProvider.notifier)
                          .createUser(
                            workspaceId: state.context.workspace.id,
                            displayName: displayName,
                            email: emailController.text.trim().isEmpty
                                ? null
                                : emailController.text.trim(),
                            role: role,
                          );
                      if (!mounted || !context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                      await _load();
                    } catch (error) {
                      setDialogState(() {
                        errorText = _formatError(error);
                      });
                    }
                  },
                  child: const Text('Anlegen'),
                ),
              ],
            );
          },
        );
      },
    );
    displayNameController.dispose();
    emailController.dispose();
  }

  Future<void> _updateRole({
    required LocalUserRecord user,
    required String role,
  }) async {
    if (role == user.role) {
      return;
    }
    try {
      await ref
          .read(securityControllerProvider.notifier)
          .updateUserRole(userId: user.id, role: role);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _formatError(error);
      });
    }
  }

  Future<void> _confirmDelete(LocalUserRecord user) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Benutzer löschen'),
            content: Text(
              '"${user.displayName}" wird aus diesem Workspace entfernt.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Löschen'),
              ),
            ],
          ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    try {
      await ref.read(securityControllerProvider.notifier).deleteUser(user.id);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _formatError(error);
      });
    }
  }

  String _formatError(Object error) {
    final message = error.toString();
    final cleaned = message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('SecurityOperationException: ', '');
    return cleaned;
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isActiveUser,
    required this.onRoleChanged,
    required this.onDelete,
  });

  final LocalUserRecord user;
  final bool isActiveUser;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (isActiveUser)
                    const NxStatusBadge(
                      label: 'Aktiv',
                      kind: NxBadgeKind.success,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                user.email?.trim().isNotEmpty == true
                    ? user.email!
                    : 'Keine E-Mail hinterlegt',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: user.role,
                  items: _roleItems,
                  onChanged:
                      isActiveUser
                          ? null
                          : (value) {
                            if (value != null) {
                              onRoleChanged(value);
                            }
                          },
                  decoration: const InputDecoration(
                    labelText: 'Rolle',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isActiveUser ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Löschen'),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: AppSpacing.component),
                controls,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identity),
              const SizedBox(width: AppSpacing.component),
              controls,
            ],
          );
        },
      ),
    );
  }
}

const _roleItems = [
  DropdownMenuItem(value: 'admin', child: Text('Admin')),
  DropdownMenuItem(value: 'manager', child: Text('Manager')),
  DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
  DropdownMenuItem(value: 'operations', child: Text('Operations')),
  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
];
