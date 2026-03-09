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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('open')),
                    DropdownMenuItem(value: 'dismissed', child: Text('dismissed')),
                    DropdownMenuItem(value: 'resolved', child: Text('resolved')),
                    DropdownMenuItem(value: 'all', child: Text('all')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _statusFilter = value);
                      _load();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Alert Status'),
                ),
              ),
              OutlinedButton(onPressed: _load, child: const Text('Refresh')),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Card(
              child:
                  _alerts.isEmpty
                      ? const Center(child: Text('No operational alerts.'))
                      : ListView.builder(
                        itemCount: _alerts.length,
                        itemBuilder: (context, index) {
                          final alert = _alerts[index];
                          final severity = alert.severity;
                          return ListTile(
                            leading: Icon(
                              severity == 'critical'
                                  ? Icons.error_outline
                                  : severity == 'warning'
                                  ? Icons.warning_amber_outlined
                                  : Icons.info_outline,
                              color:
                                  severity == 'critical'
                                      ? Colors.red
                                      : severity == 'warning'
                                      ? Colors.orange
                                      : Colors.blueGrey,
                            ),
                            title: Text(alert.message),
                            subtitle: Text(
                              '${alert.type} · ${alert.status}${alert.recommendedAction == null ? '' : '\n${alert.recommendedAction}'}',
                            ),
                            isThreeLine: alert.recommendedAction != null,
                            trailing: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _SeverityChip(severity: severity),
                                if (alert.status == 'open')
                                  TextButton(
                                    onPressed: () => _updateStatus(alert, 'dismissed'),
                                    child: const Text('Dismiss'),
                                  ),
                                if (alert.status != 'resolved')
                                  TextButton(
                                    onPressed: () => _resolve(alert),
                                    child: const Text('Resolve'),
                                  ),
                                TextButton(
                                  onPressed: () async {
                                    await showCreateTaskDialog(
                                      context: context,
                                      ref: ref,
                                      entityType: _taskEntityType(alert),
                                      entityId: _taskEntityId(alert),
                                      defaultTitle: alert.recommendedAction ?? alert.message,
                                    );
                                  },
                                  child: const Text('Create Task'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
      final alerts = await ref.read(operationsRepositoryProvider).loadAlerts(
            widget.propertyId,
            status: _statusFilter == 'all' ? null : _statusFilter,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _alerts = alerts;
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
