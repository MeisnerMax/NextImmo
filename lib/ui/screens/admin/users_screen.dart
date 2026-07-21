import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/security.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../navigation/app_navigation.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

/// User / role administration (SCR-061, Phase 2 Wave 1 / AP7c). The screen is
/// gated on the same role check the navigation uses
/// ([isPageAllowedForRole] for [GlobalPage.adminUsers]); a user who reaches it
/// without permission sees an explicit "kein Zugriff" state rather than an
/// empty surface (fail closed). Loading shows a skeleton instead of a
/// full-surface spinner, and role changes require a confirmation. The user
/// list stays a responsive `NxCard` list (already system-standard, and better
/// for the rich per-row controls than a raw `DataTable`).
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
  bool _requestedLoad = false;

  @override
  Widget build(BuildContext context) {
    final securityAsync = ref.watch(securityControllerProvider);
    return securityAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.page),
        child: _UsersSkeleton(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Center(
          child: NxEmptyState(
            title: 'Sicherheitskontext konnte nicht geladen werden',
            description:
                'Der aktuelle Workspace-Kontext ist nicht verfügbar. '
                'Bitte versuchen Sie es erneut.',
            icon: Icons.error_outline,
            primaryAction: ElevatedButton.icon(
              onPressed: () => ref.invalidate(securityControllerProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ),
        ),
      ),
      data: (security) {
        final role = security.context.user.role;
        if (!isPageAllowedForRole(GlobalPage.adminUsers, role)) {
          return const _UsersForbidden();
        }
        // Load the workspace users once the security context is available.
        if (!_requestedLoad) {
          _requestedLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _load();
            }
          });
        }
        return _buildAllowed(security);
      },
    );
  }

  Widget _buildAllowed(SecurityState security) {
    final activeWorkspace = security.context.workspace;
    final activeUserId = security.context.user.id;
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
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Alle Rollen')),
                ..._roleItems,
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
              child: Text('Workspace: ${activeWorkspace.name}'),
            ),
          ],
        ),
      ),
      content: _userListContent(activeUserId),
    );
  }

  Widget _userListContent(String activeUserId) {
    if (_loading) {
      return const _UsersSkeleton();
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: NxEmptyState(
          title: 'Benutzer konnten nicht geladen werden',
          description:
              'Beim Laden der Benutzer ist ein Fehler aufgetreten. '
              'Bitte versuchen Sie es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ),
      );
    }
    final filtered = _users
        .where((user) => _roleFilter == 'all' || user.role == _roleFilter)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return const SingleChildScrollView(
        child: NxEmptyState(
          title: 'Keine Benutzer',
          description: 'Filter ändern oder Benutzer anlegen.',
          icon: Icons.people_outline,
        ),
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.component),
      itemBuilder: (context, index) {
        final user = filtered[index];
        return _UserCard(
          user: user,
          isActiveUser: user.id == activeUserId,
          onRoleChanged: (role) => _updateRole(user: user, role: role),
          onSetPassword: () => _setPasswordDialog(user),
          onDelete: () => _confirmDelete(user),
        );
      },
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
    final passwordController = TextEditingController();
    String role = 'asset_manager';
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Startpasswort optional',
                        prefixIcon: Icon(Icons.lock_outline),
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
                          .createUserWithPassword(
                            workspaceId: state.context.workspace.id,
                            displayName: displayName,
                            email: emailController.text.trim().isEmpty
                                ? null
                                : emailController.text.trim(),
                            role: role,
                            password:
                                passwordController.text.trim().isEmpty
                                    ? null
                                    : passwordController.text,
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
    passwordController.dispose();
  }

  Future<void> _updateRole({
    required LocalUserRecord user,
    required String role,
  }) async {
    if (role == user.role) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rolle ändern'),
        content: Text(
          'Die Rolle von "${user.displayName}" wird auf '
          '"${_roleLabel(role)}" geändert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ändern'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
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

  Future<void> _setPasswordDialog(LocalUserRecord user) async {
    final passwordController = TextEditingController();
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: Text('Passwort für ${user.displayName} setzen'),
                content: TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Neues Passwort',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    errorText: errorText,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final password = passwordController.text.trim();
                      if (password.isEmpty) {
                        setDialogState(() {
                          errorText = 'Passwort ist erforderlich.';
                        });
                        return;
                      }
                      try {
                        await ref
                            .read(securityControllerProvider.notifier)
                            .setUserPassword(
                              userId: user.id,
                              password: password,
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
                    child: const Text('Speichern'),
                  ),
                ],
              ),
        );
      },
    );
    passwordController.dispose();
  }

  String _formatError(Object error) {
    final message = error.toString();
    final cleaned = message
        .replaceFirst('Bad state: ', '')
        .replaceFirst('SecurityOperationException: ', '');
    return cleaned;
  }

  String _roleLabel(String role) {
    const labels = <String, String>{
      'admin': 'Administrator',
      'asset_manager': 'Asset Manager',
      'hausmeister': 'Hausmeister',
      'bauleiter': 'Bauleiter',
      'bauarbeiter': 'Bauarbeiter',
      'buchhaltung': 'Buchhaltung',
      'vermietung': 'Vermietung',
      'buerokraft': 'Bürokraft',
      'housekeeping': 'Housekeeping',
      'externer_dienstleister': 'Externer Dienstleister',
      'viewer': 'Nur Lesen',
    };
    return labels[role] ?? role;
  }
}

/// Explicit no-access state for the admin users screen (fail closed): shown
/// when the active role is not permitted to manage users, instead of an empty
/// surface.
class _UsersForbidden extends StatelessWidget {
  const _UsersForbidden();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.page),
      child: Center(
        child: NxEmptyState(
          title: 'Kein Zugriff',
          description:
              'Für die Benutzerverwaltung fehlt Ihrer Rolle die Berechtigung. '
              'Wenden Sie sich an einen Administrator.',
          icon: Icons.lock_outline,
        ),
      ),
    );
  }
}

/// List-shaped loading placeholder (never a full-surface spinner): a few
/// user-card-shaped blocks mirroring the eventual layout.
class _UsersSkeleton extends StatelessWidget {
  const _UsersSkeleton();

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return SingleChildScrollView(
      child: Column(
        key: const ValueKey<String>('users_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.component),
            child: NxCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(180, 14),
                        const SizedBox(height: 10),
                        bar(120, 10),
                      ],
                    ),
                  ),
                  bar(160, 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isActiveUser,
    required this.onRoleChanged,
    required this.onSetPassword,
    required this.onDelete,
  });

  final LocalUserRecord user;
  final bool isActiveUser;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onSetPassword;
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
                  isExpanded: true,
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
                onPressed: onSetPassword,
                icon: Icon(
                  user.passwordHash == null
                      ? Icons.lock_open_outlined
                      : Icons.lock_reset_outlined,
                ),
                label: Text(
                  user.passwordHash == null ? 'Passwort setzen' : 'Passwort',
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
  DropdownMenuItem(value: 'admin', child: Text('Administrator')),
  DropdownMenuItem(value: 'asset_manager', child: Text('Asset Manager')),
  DropdownMenuItem(value: 'hausmeister', child: Text('Hausmeister')),
  DropdownMenuItem(value: 'bauleiter', child: Text('Bauleiter')),
  DropdownMenuItem(value: 'bauarbeiter', child: Text('Bauarbeiter')),
  DropdownMenuItem(value: 'buchhaltung', child: Text('Buchhaltung')),
  DropdownMenuItem(value: 'vermietung', child: Text('Vermietung')),
  DropdownMenuItem(value: 'buerokraft', child: Text('Bürokraft')),
  DropdownMenuItem(value: 'housekeeping', child: Text('Housekeeping')),
  DropdownMenuItem(
    value: 'externer_dienstleister',
    child: Text('Externer Dienstleister'),
  ),
  DropdownMenuItem(value: 'viewer', child: Text('Nur Lesen')),
];
