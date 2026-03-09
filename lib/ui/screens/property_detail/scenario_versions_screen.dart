import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario_version.dart';
import '../../components/responsive_constraints.dart';
import '../../state/scenario_versions_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

class ScenarioVersionsScreen extends ConsumerStatefulWidget {
  const ScenarioVersionsScreen({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<ScenarioVersionsScreen> createState() =>
      _ScenarioVersionsScreenState();
}

class _ScenarioVersionsScreenState
    extends ConsumerState<ScenarioVersionsScreen> {
  bool _showAllRows = false;

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(
      scenarioVersionsControllerProvider(widget.scenarioId),
    );
    final controller = ref.read(
      scenarioVersionsControllerProvider(widget.scenarioId).notifier,
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: versionsAsync.when(
        data: (state) {
          final versions =
              state.showArchived
                  ? state.versions
                  : state.versions
                      .where((version) => !version.archived)
                      .toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: state.isBusy ? null : _openSaveDialog,
                    child: const Text('Save Version'),
                  ),
                  OutlinedButton(
                    onPressed: controller.reload,
                    child: const Text('Refresh'),
                  ),
                  const Tooltip(
                    message:
                        'Versions are immutable snapshots of scenario inputs and lines.',
                    child: Icon(Icons.info_outline, size: 18),
                  ),
                  Switch(
                    value: state.showArchived,
                    onChanged: controller.toggleShowArchived,
                  ),
                  const Text('Show archived'),
                  if (state.isBusy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(state.error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 1100;

                    final listPane = Card(
                      child:
                          versions.isEmpty
                              ? const Center(
                                child: Text(
                                  'No versions available in current filter.',
                                ),
                              )
                              : ListView.builder(
                                itemCount: versions.length,
                                itemBuilder: (context, index) {
                                  final version = versions[index];
                                  return ListTile(
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(version.label)),
                                        if (version.archived)
                                          const Chip(
                                            label: Text('Archived'),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      [
                                        '${DateTime.fromMillisecondsSinceEpoch(version.createdAt).toIso8601String()}'
                                            ' | ${version.createdBy ?? '-'}'
                                            ' | ${version.baseHash.substring(0, 8)}',
                                        if ((version.notes ?? '').isNotEmpty)
                                          'Note: ${version.notes}',
                                      ].join('\n'),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        switch (value) {
                                          case 'view':
                                            await ref
                                                .read(
                                                  scenarioVersionsControllerProvider(
                                                    widget.scenarioId,
                                                  ).notifier,
                                                )
                                                .compareVersions(
                                                  version.id,
                                                  version.id,
                                                );
                                            return;
                                          case 'compare':
                                            await _openCompareDialog(
                                              version.id,
                                            );
                                            return;
                                          case 'rollback':
                                            await _confirmRollback(version.id);
                                            return;
                                          case 'rename':
                                            await _openRenameDialog(version);
                                            return;
                                          case 'notes':
                                            await _openNotesDialog(version);
                                            return;
                                          case 'archive':
                                            await ref
                                                .read(
                                                  scenarioVersionsControllerProvider(
                                                    widget.scenarioId,
                                                  ).notifier,
                                                )
                                                .setVersionArchived(
                                                  versionId: version.id,
                                                  archived: true,
                                                );
                                            return;
                                          case 'unarchive':
                                            await ref
                                                .read(
                                                  scenarioVersionsControllerProvider(
                                                    widget.scenarioId,
                                                  ).notifier,
                                                )
                                                .setVersionArchived(
                                                  versionId: version.id,
                                                  archived: false,
                                                );
                                            return;
                                        }
                                      },
                                      itemBuilder:
                                          (context) => [
                                            const PopupMenuItem(
                                              value: 'view',
                                              child: Text('View'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'compare',
                                              child: Text('Compare'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'rollback',
                                              child: Text('Rollback'),
                                            ),
                                            const PopupMenuDivider(),
                                            const PopupMenuItem(
                                              value: 'rename',
                                              child: Text('Rename'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'notes',
                                              child: Text('Edit Note'),
                                            ),
                                            PopupMenuItem(
                                              value:
                                                  version.archived
                                                      ? 'unarchive'
                                                      : 'archive',
                                              child: Text(
                                                version.archived
                                                    ? 'Unarchive'
                                                    : 'Archive',
                                              ),
                                            ),
                                          ],
                                    ),
                                  );
                                },
                              ),
                    );

                    final diffPane = Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Diff',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                Switch(
                                  value: _showAllRows,
                                  onChanged: (value) {
                                    setState(() => _showAllRows = value);
                                  },
                                ),
                                const Text('Show all'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child:
                                  state.diff.isEmpty
                                      ? const Center(
                                        child: Text(
                                          'Select compare to see changes.',
                                        ),
                                      )
                                      : ListView(
                                        children: state.diff
                                            .where((item) {
                                              if (_showAllRows) {
                                                return true;
                                              }
                                              return item.changeType !=
                                                  'unchanged';
                                            })
                                            .map((item) {
                                              return ListTile(
                                                dense: true,
                                                title: Text(
                                                  '${item.section} · ${item.fieldKey}',
                                                ),
                                                subtitle: Text(
                                                  'Before: ${item.before ?? '-'}\nAfter: ${item.after ?? '-'}',
                                                ),
                                              );
                                            })
                                            .toList(growable: false),
                                      ),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(child: listPane),
                          const SizedBox(height: 12),
                          Expanded(child: diffPane),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 2, child: listPane),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: diffPane),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Future<void> _openSaveDialog() async {
    final labelController = TextEditingController();
    final notesController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Version'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Label *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes'),
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
                final label = labelController.text.trim();
                if (label.isEmpty) {
                  return;
                }
                final user =
                    ref
                        .read(securityControllerProvider)
                        .valueOrNull
                        ?.context
                        .user;
                await ref
                    .read(
                      scenarioVersionsControllerProvider(
                        widget.scenarioId,
                      ).notifier,
                    )
                    .saveVersion(
                      label: label,
                      notes: notesController.text.trim(),
                      createdBy: user?.displayName,
                    );
                if (!mounted) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    labelController.dispose();
    notesController.dispose();
  }

  Future<void> _openCompareDialog(String baseVersionId) async {
    final versionsState = ref.read(
      scenarioVersionsControllerProvider(widget.scenarioId),
    );
    final versions = versionsState.valueOrNull?.versions ?? const [];
    final candidates = versions
        .where((version) => version.id != baseVersionId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return;
    }
    String? compareId = candidates.first.id;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Compare Versions'),
          content: DropdownButtonFormField<String>(
            value: compareId,
            items: candidates
                .map(
                  (version) => DropdownMenuItem<String>(
                    value: version.id,
                    child: Text(version.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => compareId = value,
            decoration: const InputDecoration(labelText: 'Compare against'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (compareId == null) {
                  return;
                }
                await ref
                    .read(
                      scenarioVersionsControllerProvider(
                        widget.scenarioId,
                      ).notifier,
                    )
                    .compareVersions(baseVersionId, compareId!);
                if (!mounted) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Compare'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRenameDialog(ScenarioVersionRecord version) async {
    final controller = TextEditingController(text: version.label);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Version'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final label = controller.text.trim();
                if (label.isEmpty) {
                  return;
                }
                await ref
                    .read(
                      scenarioVersionsControllerProvider(
                        widget.scenarioId,
                      ).notifier,
                    )
                    .renameVersion(versionId: version.id, label: label);
                if (!mounted || !context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _openNotesDialog(ScenarioVersionRecord version) async {
    final controller = TextEditingController(text: version.notes ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Version Note'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
            child: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await ref
                    .read(
                      scenarioVersionsControllerProvider(
                        widget.scenarioId,
                      ).notifier,
                    )
                    .updateVersionNotes(
                      versionId: version.id,
                      notes: controller.text.trim(),
                    );
                if (!mounted || !context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _confirmRollback(String versionId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rollback Scenario'),
          content: const Text(
            'Rollback will replace current working state. '
            'A safety version will be created automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Rollback'),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return;
    }
    final user = ref.read(securityControllerProvider).valueOrNull?.context.user;
    await ref
        .read(scenarioVersionsControllerProvider(widget.scenarioId).notifier)
        .rollbackToVersion(versionId: versionId, rollbackBy: user?.displayName);
  }
}
