/// The operational alerts list of a property (Welle 3, AP10 — SCR-032).
///
/// Fully on the `P2-D05a` contract (Befund 1 in
/// `04c_wave3_leasing_operations.md`): the client reads signals and
/// acknowledges them, it never derives them. Alerts and data-quality issues
/// are one list — see `operations_alerts_controller.dart`'s header.
///
/// **"Create Task" goes through the cloud contract, not the legacy one:** the
/// legacy screen wrote through `tasksRepositoryProvider` (SQLite-only), which
/// the Wave-3 rule ("no cloud screen reads a legacy repository") forbids
/// here. This screen instead uses `platform_audit_jobs.TaskRepository`
/// (P2-D04) — see `OperationsAlertsController.createTaskFrom` and
/// `entityRefFor` for how a signal's unit/lease/tenant references map onto
/// that contract's `PlatformEntityRef`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/operations_alerts_controller.dart';
import '../../../../features/leasing_operations/domain/operations_signal_dto.dart';
import '../../../../features/platform_audit_jobs/domain/task_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_page_header.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';

class OperationsAlertsPanel extends ConsumerWidget {
  const OperationsAlertsPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = operationsAlertsControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxPageHeader(
          title: 'Operative Hinweise',
          subtitle:
              'Vertragsablauf, Leerstand und Datenqualität — serverseitig '
              'berechnet, hier nur gelesen und quittiert.',
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, ref, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    OperationsAlertsState state,
    OperationsAlertsController controller,
  ) {
    switch (state.phase) {
      case OperationsAlertsPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Operative Hinweise werden je Arbeitsbereich geführt. Melde '
              'dich an oder wähle einen Arbeitsbereich.',
          icon: Icons.workspaces_outline,
        );
      case OperationsAlertsPhase.loading:
        return const _AlertsSkeleton();
      case OperationsAlertsPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf die operativen Hinweise',
          description:
              'Für dieses Objekt fehlt die Leseberechtigung für Einheiten '
              'und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case OperationsAlertsPhase.error:
        return NxEmptyState(
          title: 'Hinweise konnten nicht geladen werden',
          description:
              state.message ?? 'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case OperationsAlertsPhase.ready:
        return _buildReady(context, ref, state, controller);
    }
  }

  Widget _buildReady(
    BuildContext context,
    WidgetRef ref,
    OperationsAlertsState state,
    OperationsAlertsController controller,
  ) {
    final filtered = state.filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryStrip(state: state),
        const SizedBox(height: AppSpacing.component),
        if (state.actionError != null) ...<Widget>[
          _ActionErrorBanner(message: state.actionError!),
          const SizedBox(height: AppSpacing.component),
        ],
        _FilterBar(state: state, controller: controller),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: filtered.isEmpty
              ? const NxEmptyState(
                  title: 'Keine passenden Hinweise',
                  description: 'Für die gewählten Filter liegt nichts vor.',
                  icon: Icons.filter_alt_off_outlined,
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.component),
                  itemBuilder: (context, index) {
                    final signal = filtered[index];
                    return _AlertCard(
                      signal: signal,
                      canMutate: controller.canMutate,
                      onOpen: () => _openSource(ref, signal),
                      onDismiss: signal.status == 'open'
                          ? () => unawaited(
                              controller.acknowledge(
                                signal: signal,
                                status: 'dismissed',
                              ),
                            )
                          : null,
                      onResolve: signal.status != 'resolved'
                          ? () => _resolve(context, controller, signal)
                          : null,
                      onCreateTask: () => _createTask(context, controller, signal),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Pops with the trimmed note (possibly empty) immediately on confirm, or
  /// `null` on cancel — the dialog's lifecycle never waits on the async
  /// acknowledgement. [noteCtrl] is disposed a frame later
  /// (`addPostFrameCallback`), not synchronously after the pop: the dialog
  /// route still plays its exit transition for one more frame, and disposing
  /// immediately raced that animation into using an already-disposed
  /// controller.
  Future<void> _resolve(
    BuildContext context,
    OperationsAlertsController controller,
    OperationsSignalDto signal,
  ) async {
    final noteCtrl = TextEditingController(text: signal.resolutionNote ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hinweis auflösen'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Auflösungsnotiz'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(noteCtrl.text.trim()),
            child: const Text('Auflösen'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => noteCtrl.dispose());
    if (note == null) {
      return;
    }
    await controller.acknowledge(
      signal: signal,
      status: 'resolved',
      resolutionNote: note.isEmpty ? null : note,
    );
  }

  /// Same pop-then-act shape as [_resolve]: the dialog closes synchronously
  /// on confirm, [titleCtrl] disposes a frame later, and the actual creation
  /// runs after the dialog route is gone.
  Future<void> _createTask(
    BuildContext context,
    OperationsAlertsController controller,
    OperationsSignalDto signal,
  ) async {
    final titleCtrl = TextEditingController(
      text: signal.recommendedAction.isEmpty
          ? signal.message
          : signal.recommendedAction,
    );
    var priority = TaskPriority.normal;
    DateTime? dueDate;
    final draft = await showDialog<({String title, TaskPriority priority, DateTime? dueAt})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Aufgabe erstellen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskPriority>(
                  value: priority,
                  items: const <DropdownMenuItem<TaskPriority>>[
                    DropdownMenuItem(value: TaskPriority.low, child: Text('niedrig')),
                    DropdownMenuItem(
                      value: TaskPriority.normal,
                      child: Text('normal'),
                    ),
                    DropdownMenuItem(value: TaskPriority.high, child: Text('hoch')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => priority = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Priorität'),
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Fälligkeit'),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(dueDate == null ? '—' : _formatDialogDate(dueDate!)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                        child: const Text('Wählen'),
                      ),
                      if (dueDate != null)
                        TextButton(
                          onPressed: () => setDialogState(() => dueDate = null),
                          child: const Text('Löschen'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop((
                  title: title,
                  priority: priority,
                  dueAt: dueDate,
                ));
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => titleCtrl.dispose());
    if (draft == null) {
      return;
    }
    await controller.createTaskFrom(
      signal: signal,
      title: draft.title,
      priority: draft.priority,
      dueAt: draft.dueAt,
    );
  }

  String _formatDialogDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  void _openSource(WidgetRef ref, OperationsSignalDto signal) {
    if (signal.leaseId != null) {
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.leases;
      return;
    }
    if (signal.tenantPartyId != null) {
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.tenants;
      return;
    }
    if (signal.unitId != null) {
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.units;
      return;
    }
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.operationsOverview;
  }
}

class _ActionErrorBanner extends StatelessWidget {
  const _ActionErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: semantic.error),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: semantic.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// One card, an internal [Wrap] of compact label/value pairs — not four
/// separate cards stacked full-width, which overflowed vertically on a
/// 390px viewport (four card-chrome tiles is a lot of height when each one
/// claims the full row).
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.state});

  final OperationsAlertsState state;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: <Widget>[
          _SummaryTile(label: 'Offen', value: '${state.openCount}'),
          _SummaryTile(label: 'Kritisch', value: '${state.criticalCount}'),
          _SummaryTile(label: 'Warnung', value: '${state.warningCount}'),
          _SummaryTile(label: 'Aufgelöst', value: '${state.resolvedCount}'),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.controller});

  final OperationsAlertsState state;
  final OperationsAlertsController controller;

  static const List<String> _categories = <String>[
    'lease',
    'rent_roll',
    'tenant',
    'data_quality',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final filterWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: state.statusFilter,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'open', child: Text('Offen')),
                  DropdownMenuItem(value: 'dismissed', child: Text('Verworfen')),
                  DropdownMenuItem(value: 'resolved', child: Text('Aufgelöst')),
                  DropdownMenuItem(
                    value: statusFilterAll,
                    child: Text('Alle Status'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.setStatusFilter(value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ),
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: state.severityFilter,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: severityFilterAll,
                    child: Text('Alle Prioritäten'),
                  ),
                  DropdownMenuItem(value: 'critical', child: Text('Kritisch')),
                  DropdownMenuItem(value: 'warning', child: Text('Warnung')),
                  DropdownMenuItem(value: 'info', child: Text('Info')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.setSeverityFilter(value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Priorität'),
              ),
            ),
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: state.categoryFilter,
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: categoryFilterAll,
                    child: Text('Alle Kategorien'),
                  ),
                  ..._categories.map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(_categoryLabel(category)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.setCategoryFilter(value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Kategorie'),
              ),
            ),
          ],
        );
      },
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'lease':
        return 'Vertrag';
      case 'rent_roll':
        return 'Rent Roll';
      case 'tenant':
        return 'Mieter';
      default:
        return 'Datenqualität';
    }
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.signal,
    required this.canMutate,
    required this.onOpen,
    required this.onDismiss,
    required this.onResolve,
    required this.onCreateTask,
  });

  final OperationsSignalDto signal;
  final bool canMutate;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;
  final VoidCallback? onResolve;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_severityIcon(signal.severity), color: _severityColor(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(signal.message, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _SeverityChip(severity: signal.severity),
                        _Pill(label: signal.status.toUpperCase()),
                        _Pill(label: signal.type.replaceAll('_', ' ')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(signal.recommendedAction),
          if (signal.resolutionNote != null &&
              signal.resolutionNote!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Auflösung: ${signal.resolutionNote!}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Öffnen'),
              ),
              if (canMutate && onDismiss != null)
                TextButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('Verwerfen'),
                ),
              if (canMutate && onResolve != null)
                TextButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Auflösen'),
                ),
              if (canMutate)
                TextButton.icon(
                  onPressed: onCreateTask,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Aufgabe erstellen'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _severityColor(BuildContext context) {
    switch (signal.severity) {
      case 'critical':
        return context.semanticColors.error;
      case 'warning':
        return context.semanticColors.warning;
      default:
        return context.semanticColors.textSecondary;
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final color = severity == 'critical'
        ? context.semanticColors.error
        : severity == 'warning'
        ? context.semanticColors.warning
        : context.semanticColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AlertsSkeleton extends StatelessWidget {
  const _AlertsSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 4; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}
