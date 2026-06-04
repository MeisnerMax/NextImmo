import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class OperationsAlertsScreen extends ConsumerStatefulWidget {
  const OperationsAlertsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<OperationsAlertsScreen> createState() =>
      _OperationsAlertsScreenState();
}

class _OperationsAlertsScreenState
    extends ConsumerState<OperationsAlertsScreen> {
  bool _loading = true;
  String? _error;
  List<OperationsAlertRecord> _alerts = const [];
  String _statusFilter = 'open';
  String _severityFilter = 'all';
  String _categoryFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryStrip(alerts: _alerts),
          const SizedBox(height: AppSpacing.component),
          _buildFilters(),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: _filteredAlerts.isEmpty
                ? const Card(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.cardPadding),
                        child: Text('No matching operational alerts.'),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filteredAlerts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.component),
                    itemBuilder: (context, index) {
                      return _AlertCard(
                        alert: _filteredAlerts[index],
                        onOpen: () => _openAlertSource(_filteredAlerts[index]),
                        onDismiss: () => _updateStatus(
                          _filteredAlerts[index],
                          'dismissed',
                        ),
                        onResolve: () => _resolve(_filteredAlerts[index]),
                        onCreateTask: () => _createTask(_filteredAlerts[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<OperationsAlertRecord> get _filteredAlerts {
    return _alerts.where((alert) {
      final severityMatches =
          _severityFilter == 'all' || alert.severity == _severityFilter;
      final categoryMatches =
          _categoryFilter == 'all' || _alertCategory(alert) == _categoryFilter;
      return severityMatches && categoryMatches;
    }).toList(growable: false);
  }

  Widget _buildFilters() {
    final categories = _alerts
        .map(_alertCategory)
        .toSet()
        .toList(growable: false)
      ..sort();
    final categoryItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('All categories')),
      ...categories.map(
        (category) => DropdownMenuItem(
          value: category,
          child: Text(_categoryLabel(category)),
        ),
      ),
    ];

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
          children: [
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'all', child: Text('All status')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _statusFilter = value);
                    _load();
                  }
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ),
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: _severityFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All priorities')),
                  DropdownMenuItem(value: 'critical', child: Text('Critical')),
                  DropdownMenuItem(value: 'warning', child: Text('Warning')),
                  DropdownMenuItem(value: 'info', child: Text('Info')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _severityFilter = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Priority'),
              ),
            ),
            SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                value: _categoryFilter,
                items: categoryItems,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _categoryFilter = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
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
      final alerts = await ref.read(operationsRepositoryProvider).loadAlerts(
            widget.propertyId,
            status: _statusFilter == 'all' ? null : _statusFilter,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _alerts = alerts;
        if (_categoryFilter != 'all' &&
            !_alerts.map(_alertCategory).contains(_categoryFilter)) {
          _categoryFilter = 'all';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load alerts: $error';
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(OperationsAlertRecord alert, String status) async {
    await ref.read(operationsRepositoryProvider).updateAlertStatus(
          alertId: alert.id!,
          propertyId: widget.propertyId,
          status: status,
        );
    await _load();
  }

  Future<void> _resolve(OperationsAlertRecord alert) async {
    final noteCtrl = TextEditingController(text: alert.resolutionNote ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Alert'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Resolution Note'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(operationsRepositoryProvider).updateAlertStatus(
                    alertId: alert.id!,
                    propertyId: widget.propertyId,
                    status: 'resolved',
                    resolutionNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              await _load();
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    noteCtrl.dispose();
  }

  Future<void> _createTask(OperationsAlertRecord alert) async {
    await showCreateTaskDialog(
      context: context,
      ref: ref,
      entityType: _taskEntityType(alert),
      entityId: _taskEntityId(alert),
      defaultTitle: alert.recommendedAction ?? alert.message,
    );
  }

  void _openAlertSource(OperationsAlertRecord alert) {
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    ref.read(selectedPropertyIdProvider.notifier).state = widget.propertyId;
    if (alert.leaseId != null) {
      ref.read(selectedOperationsLeaseIdProvider.notifier).state = alert.leaseId;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.leases;
      return;
    }
    if (alert.tenantId != null) {
      ref.read(selectedOperationsTenantIdProvider.notifier).state =
          alert.tenantId;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.tenants;
      return;
    }
    if (alert.unitId != null) {
      ref.read(selectedOperationsUnitIdProvider.notifier).state = alert.unitId;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.units;
      return;
    }
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.operationsOverview;
  }

  String _taskEntityType(OperationsAlertRecord alert) {
    if (alert.leaseId != null) {
      return 'lease';
    }
    if (alert.tenantId != null) {
      return 'tenant';
    }
    return 'unit';
  }

  String _taskEntityId(OperationsAlertRecord alert) {
    return alert.leaseId ?? alert.tenantId ?? alert.unitId ?? widget.propertyId;
  }

  String _alertCategory(OperationsAlertRecord alert) {
    if (alert.type.contains('lease')) {
      return 'lease';
    }
    if (alert.type.contains('rent_roll')) {
      return 'rent_roll';
    }
    if (alert.type.contains('tenant')) {
      return 'tenant';
    }
    if (alert.type.contains('unit')) {
      return 'unit';
    }
    return 'data_quality';
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'lease':
        return 'Lease';
      case 'rent_roll':
        return 'Rent Roll';
      case 'tenant':
        return 'Tenant';
      case 'unit':
        return 'Unit';
      default:
        return 'Data Quality';
    }
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.alerts});

  final List<OperationsAlertRecord> alerts;

  @override
  Widget build(BuildContext context) {
    final open = alerts.where((alert) => alert.status == 'open').length;
    final critical =
        alerts.where((alert) => alert.severity == 'critical').length;
    final warning = alerts.where((alert) => alert.severity == 'warning').length;
    final resolved = alerts.where((alert) => alert.status == 'resolved').length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 680
            ? constraints.maxWidth
            : (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryTile(label: 'Open', value: open.toString(), width: width),
            _SummaryTile(
              label: 'Critical',
              value: critical.toString(),
              width: width,
            ),
            _SummaryTile(
              label: 'Warning',
              value: warning.toString(),
              width: width,
            ),
            _SummaryTile(
              label: 'Resolved',
              value: resolved.toString(),
              width: width,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onOpen,
    required this.onDismiss,
    required this.onResolve,
    required this.onCreateTask,
  });

  final OperationsAlertRecord alert;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onResolve;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    final createdAt = alert.createdAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(alert.createdAt!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _severityIcon(alert.severity),
                  color: _severityColor(alert.severity),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.message,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SeverityChip(severity: alert.severity),
                          _Pill(label: alert.status.toUpperCase()),
                          _Pill(label: alert.type.replaceAll('_', ' ')),
                          if (createdAt != null)
                            _Pill(label: 'Created ${_formatDate(createdAt)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (alert.recommendedAction != null) ...[
              const SizedBox(height: 12),
              Text(alert.recommendedAction!),
            ],
            if (alert.resolutionNote != null &&
                alert.resolutionNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Resolution: ${alert.resolutionNote!}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
                if (alert.status == 'open')
                  TextButton.icon(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Dismiss'),
                  ),
                if (alert.status != 'resolved')
                  TextButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Resolve'),
                  ),
                TextButton.icon(
                  onPressed: onCreateTask,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Create Task'),
                ),
              ],
            ),
          ],
        ),
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

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final color =
        severity == 'critical'
            ? Colors.red
            : severity == 'warning'
            ? Colors.orange
            : Colors.blueGrey;
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
