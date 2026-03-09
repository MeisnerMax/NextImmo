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

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _entityTypeController = TextEditingController();
  final _sourceController = TextEditingController();
  final _userController = TextEditingController();
  final _workspaceController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  List<AuditLogRecord> _rows = const <AuditLogRecord>[];
  AuditLogRecord? _selected;
  bool _isLoading = true;
  String? _error;
  String _actionFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entityTypeController.dispose();
    _sourceController.dispose();
    _userController.dispose();
    _workspaceController.dispose();
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
        child: Text('You do not have permission to view the audit log.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Audit Log', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _entityTypeController,
                  decoration: const InputDecoration(labelText: 'Entity Type'),
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
                    DropdownMenuItem(value: 'import', child: Text('Import')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                    DropdownMenuItem(value: 'switch_user', child: Text('Switch User')),
                    DropdownMenuItem(
                      value: 'switch_workspace',
                      child: Text('Switch Workspace'),
                    ),
                  ],
                  onChanged:
                      (value) => setState(() => _actionFilter = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _sourceController,
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: 'User'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _workspaceController,
                  decoration: const InputDecoration(labelText: 'Workspace'),
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
              ElevatedButton(onPressed: _load, child: const Text('Apply')),
              OutlinedButton(
                onPressed: _isLoading ? null : _exportCsv,
                child: const Text('Export CSV'),
              ),
              OutlinedButton(
                onPressed: _selected == null ? null : _exportSelectedJson,
                child: const Text('Export Selected JSON'),
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
                              itemCount: _rows.length,
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                return ListTile(
                                  selected: _selected?.id == row.id,
                                  title: Text(
                                    '${row.action} · ${row.entityType}:${row.entityId}',
                                  ),
                                  subtitle: Text(
                                    '${_formatDate(row.occurredAt)}'
                                    '\n${row.summary ?? '-'}'
                                    '\n${row.actorUserId ?? '-'} · ${row.source}',
                                  ),
                                  onTap: () => setState(() => _selected = row),
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
                                  Text('Source: ${_selected!.source}'),
                                  Text('Workspace: ${_selected!.workspaceId ?? '-'}'),
                                  Text('User: ${_selected!.actorUserId ?? '-'}'),
                                  Text('Role: ${_selected!.actorRole ?? '-'}'),
                                  Text('Parent: ${_selected!.parentEntityType ?? '-'}:${_selected!.parentEntityId ?? '-'}'),
                                  if (_selected!.reason != null)
                                    Text('Reason: ${_selected!.reason}'),
                                  Text('System: ${_selected!.isSystemEvent ? 'yes' : 'no'}'),
                                  Text('Summary: ${_selected!.summary ?? '-'}'),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        _JsonBlock(
                                          title: 'Old Values',
                                          value: _selected!.oldValues,
                                        ),
                                        const SizedBox(height: 8),
                                        _JsonBlock(
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
      final rows = await ref.read(auditLogRepositoryProvider).list(
        entityType:
            _entityTypeController.text.trim().isEmpty
                ? null
                : _entityTypeController.text.trim(),
        source:
            _sourceController.text.trim().isEmpty
                ? null
                : _sourceController.text.trim(),
        userId:
            _userController.text.trim().isEmpty
                ? null
                : _userController.text.trim(),
        workspaceId:
            _workspaceController.text.trim().isEmpty
                ? null
                : _workspaceController.text.trim(),
        action: _actionFilter == 'all' ? null : _actionFilter,
        fromChangedAt: _parseDateStart(_fromController.text),
        toChangedAt: _parseDateEnd(_toController.text),
        limit: 500,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
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
      suggestedName: 'audit_log_${DateTime.now().millisecondsSinceEpoch}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (saveLocation == null) {
      return;
    }

    final rows = <List<dynamic>>[
      <dynamic>[
        'id',
        'occurred_at',
        'workspace_id',
        'actor_user_id',
        'actor_role',
        'entity_type',
        'entity_id',
        'parent_entity_type',
        'parent_entity_id',
        'action',
        'source',
        'summary',
        'reason',
        'is_system_event',
      ],
      ..._rows.map(
        (row) => <dynamic>[
          row.id,
          row.occurredAt,
          row.workspaceId,
          row.actorUserId,
          row.actorRole,
          row.entityType,
          row.entityId,
          row.parentEntityType,
          row.parentEntityId,
          row.action,
          row.source,
          row.summary,
          row.reason,
          row.isSystemEvent ? 1 : 0,
        ],
      ),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final file = File(saveLocation.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(csv);
  }

  Future<void> _exportSelectedJson() async {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    final saveLocation = await getSaveLocation(
      suggestedName: 'audit_event_${selected.id}.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (saveLocation == null) {
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(selected.toMap());
    final file = File(saveLocation.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
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

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.title, required this.value});

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
