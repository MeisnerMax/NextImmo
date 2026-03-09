import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/audit_log.dart';
import '../../../core/security/rbac.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

class PropertyAuditScreen extends ConsumerStatefulWidget {
  const PropertyAuditScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyAuditScreen> createState() =>
      _PropertyAuditScreenState();
}

class _PropertyAuditScreenState extends ConsumerState<PropertyAuditScreen> {
  final _userController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  List<AuditLogRecord> _events = const <AuditLogRecord>[];
  AuditLogRecord? _selected;
  bool _isLoading = true;
  String? _error;
  String _moduleFilter = 'all';
  String _actionFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(activeUserRoleProvider);
    final canReadAudit = ref.watch(rbacProvider).canPermission(
      role: role,
      permission: Permission.auditRead,
    );
    if (!canReadAudit) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.page),
        child: Text('You do not have permission to view audit events.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Property Audit',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _load, child: const Text('Apply')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _events.isEmpty ? null : _exportCsv,
                child: const Text('Export View'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _moduleFilter,
                  decoration: const InputDecoration(labelText: 'Module'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'property', child: Text('Property')),
                    DropdownMenuItem(value: 'scenario', child: Text('Scenario')),
                    DropdownMenuItem(
                      value: 'operations',
                      child: Text('Operations'),
                    ),
                    DropdownMenuItem(
                      value: 'document',
                      child: Text('Documents'),
                    ),
                    DropdownMenuItem(value: 'task', child: Text('Tasks')),
                    DropdownMenuItem(value: 'security', child: Text('Security')),
                    DropdownMenuItem(value: 'import', child: Text('Imports')),
                  ],
                  onChanged:
                      (value) => setState(() => _moduleFilter = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _actionFilter,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'create', child: Text('Create')),
                    DropdownMenuItem(value: 'update', child: Text('Update')),
                    DropdownMenuItem(value: 'delete', child: Text('Delete')),
                    DropdownMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    DropdownMenuItem(value: 'in_review', child: Text('In Review')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged:
                      (value) => setState(() => _actionFilter = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: 'User'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _fromController,
                  decoration: const InputDecoration(labelText: 'From YYYY-MM-DD'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _toController,
                  decoration: const InputDecoration(labelText: 'To YYYY-MM-DD'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child:
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Card(
                            child: ListView.builder(
                              itemCount: _events.length,
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                return ListTile(
                                  selected: _selected?.id == event.id,
                                  title: Text(
                                    '${event.action} · ${event.entityType}:${event.entityId}',
                                  ),
                                  subtitle: Text(
                                    '${_formatDate(event.occurredAt)}'
                                    '\n${event.summary ?? '-'}'
                                    '\n${event.actorUserId ?? '-'}',
                                  ),
                                  onTap: () => setState(() => _selected = event),
                                );
                              },
                            ),
                          ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child:
                          _selected == null
                              ? const Center(child: Text('Select an event'))
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Details',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Action: ${_selected!.action}'),
                                  Text('Module: ${_moduleFor(_selected!)}'),
                                  Text('Actor: ${_selected!.actorUserId ?? '-'}'),
                                  Text('Role: ${_selected!.actorRole ?? '-'}'),
                                  Text('Source: ${_selected!.source}'),
                                  Text('Summary: ${_selected!.summary ?? '-'}'),
                                  if (_selected!.reason != null)
                                    Text('Reason: ${_selected!.reason}'),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        _JsonCard(
                                          title: 'Old Values',
                                          value: _selected!.oldValues,
                                        ),
                                        const SizedBox(height: 8),
                                        _JsonCard(
                                          title: 'New Values',
                                          value: _selected!.newValues,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Diff',
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        ..._selected!.diffItems.map(
                                          (item) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(item.fieldKey),
                                            subtitle: Text(
                                              'Before: ${item.before ?? '-'}\nAfter: ${item.after ?? '-'}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final audit = ref.read(auditLogRepositoryProvider);
      final scenarioIds = (await ref
              .read(scenarioRepositoryProvider)
              .listByProperty(widget.propertyId))
          .map((entry) => entry.id)
          .toList(growable: false);
      final fromChangedAt = _parseDateStart(_fromController.text);
      final toChangedAt = _parseDateEnd(_toController.text);
      final userId =
          _userController.text.trim().isEmpty
              ? null
              : _userController.text.trim();
      final action = _actionFilter == 'all' ? null : _actionFilter;

      final directEvents = await audit.list(
        entityType: 'property',
        entityId: widget.propertyId,
        userId: userId,
        action: action,
        fromChangedAt: fromChangedAt,
        toChangedAt: toChangedAt,
        limit: 500,
      );
      final parentScopedEvents = await audit.list(
        parentEntityType: 'property',
        parentEntityId: widget.propertyId,
        userId: userId,
        action: action,
        fromChangedAt: fromChangedAt,
        toChangedAt: toChangedAt,
        limit: 500,
      );
      final scenarioScopedEvents =
          scenarioIds.isEmpty
              ? const <AuditLogRecord>[]
              : await audit.list(
                entityIds: scenarioIds,
                userId: userId,
                action: action,
                fromChangedAt: fromChangedAt,
                toChangedAt: toChangedAt,
                limit: 500,
              );

      final merged = <String, AuditLogRecord>{};
      for (final event in <AuditLogRecord>[
        ...directEvents,
        ...parentScopedEvents,
        ...scenarioScopedEvents,
      ]) {
        if (_moduleFilter != 'all' && _moduleFor(event) != _moduleFilter) {
          continue;
        }
        merged[event.id] = event;
      }
      final rows =
          merged.values.toList(growable: false)
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      if (!mounted) {
        return;
      }
      setState(() {
        _events = rows;
        _selected = rows.isEmpty ? null : rows.first;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _exportCsv() async {
    final saveLocation = await getSaveLocation(
      suggestedName:
          'property_audit_${widget.propertyId}_${DateTime.now().millisecondsSinceEpoch}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (saveLocation == null) {
      return;
    }
    final rows = <List<dynamic>>[
      <dynamic>[
        'occurred_at',
        'entity_type',
        'entity_id',
        'action',
        'actor_user_id',
        'actor_role',
        'summary',
        'source',
      ],
      ..._events.map(
        (event) => <dynamic>[
          event.occurredAt,
          event.entityType,
          event.entityId,
          event.action,
          event.actorUserId,
          event.actorRole,
          event.summary,
          event.source,
        ],
      ),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final file = File(saveLocation.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(csv);
  }

  String _moduleFor(AuditLogRecord event) {
    if (event.entityType.startsWith('scenario')) {
      return 'scenario';
    }
    if (event.entityType == 'property') {
      return 'property';
    }
    if (event.entityType.contains('document')) {
      return 'document';
    }
    if (event.entityType.contains('task')) {
      return 'task';
    }
    if (event.entityType == 'import_job') {
      return 'import';
    }
    if (event.entityType.contains('security') || event.entityType == 'user') {
      return 'security';
    }
    return 'operations';
  }

  int? _parseDateStart(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.tryParse(trimmed)?.millisecondsSinceEpoch;
  }

  int? _parseDateEnd(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    return parsed
        .add(const Duration(hours: 23, minutes: 59, seconds: 59))
        .millisecondsSinceEpoch;
  }

  String _formatDate(int value) {
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd $hh:$min';
  }
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.title, required this.value});

  final String title;
  final Map<String, Object?>? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            value == null ? '-' : const JsonEncoder.withIndent('  ').convert(value),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
