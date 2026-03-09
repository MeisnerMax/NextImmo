import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/security.dart';
import '../../state/security_state.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityControllerProvider).valueOrNull;
    final activeWorkspace = security?.context.workspace;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User Management',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text('Workspace: ${activeWorkspace?.name ?? '-'}'),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: _openCreateDialog,
                child: const Text('Add User'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _load, child: const Text('Refresh')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return Card(
                          child: ListTile(
                            title: Text(user.displayName),
                            subtitle: Text(
                              '${user.role} · ${user.email ?? '-'}',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(securityControllerProvider.notifier)
                                      .deleteUser(user.id);
                                  await _load();
                                } catch (error) {
                                  if (!mounted) {
                                    return;
                                  }
                                  setState(() {
                                    _error = _formatError(error);
                                  });
                                }
                              },
                              child: const Text('Delete'),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
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
        throw StateError('Security context not ready.');
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
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create User'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('admin')),
                        DropdownMenuItem(
                          value: 'analyst',
                          child: Text('analyst'),
                        ),
                        DropdownMenuItem(
                          value: 'viewer',
                          child: Text('viewer'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => role = value);
                      },
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final state =
                        ref.read(securityControllerProvider).valueOrNull;
                    if (state == null) {
                      return;
                    }
                    await ref
                        .read(securityControllerProvider.notifier)
                        .createUser(
                          workspaceId: state.context.workspace.id,
                          displayName: displayNameController.text.trim(),
                          email: emailController.text.trim(),
                          role: role,
                        );
                    if (!mounted) {
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _load();
                  },
                  child: const Text('Create'),
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

  String _formatError(Object error) {
    final message = error.toString();
    if (message.startsWith('Bad state: ')) {
      return message.substring('Bad state: '.length);
    }
    return message;
  }
}
