import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/audit_log.dart';
import '../../../core/security/rbac.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../templates/list_filter_template.dart';
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
      return const NxEmptyState(
        title: 'Kein Zugriff',
        description: 'Du hast keine Berechtigung für das Audit Log.',
        icon: Icons.lock_outline,
      );
    }

    return ListFilterTemplate(
      title: 'Audit Log',
      breadcrumbs: const ['Administration', 'Audit Log'],
      subtitle:
          'Änderungen, Rollenwechsel, Importe und Systemereignisse nachvollziehen.',
      filters: ListFilterBar(
        children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _entityTypeController,
                  decoration: const InputDecoration(
                    labelText: 'Entität',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _actionFilter,
                  decoration: const InputDecoration(
                    labelText: 'Aktion',
                    prefixIcon: Icon(Icons.bolt_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle')),
                    DropdownMenuItem(value: 'create', child: Text('Erstellt')),
                    DropdownMenuItem(value: 'update', child: Text('Geändert')),
                    DropdownMenuItem(value: 'delete', child: Text('Gelöscht')),
                    DropdownMenuItem(value: 'import', child: Text('Import')),
                    DropdownMenuItem(value: 'approved', child: Text('Freigegeben')),
                    DropdownMenuItem(value: 'rejected', child: Text('Abgelehnt')),
                    DropdownMenuItem(value: 'switch_user', child: Text('Nutzerwechsel')),
                    DropdownMenuItem(
                      value: 'switch_workspace',
                      child: Text('Workspacewechsel'),
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
                  decoration: const InputDecoration(
                    labelText: 'Quelle',
                    prefixIcon: Icon(Icons.source_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Benutzer',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _workspaceController,
                  decoration: const InputDecoration(
                    labelText: 'Workspace',
                    prefixIcon: Icon(Icons.workspaces_outline),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: _AuditDateField(
                  controller: _fromController,
                  label: 'Von',
                  onPick: () => _pickDate(_fromController),
                ),
              ),
              SizedBox(
                width: 140,
                child: _AuditDateField(
                  controller: _toController,
                  label: 'Bis',
                  onPick: () => _pickDate(_toController),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Anwenden'),
              ),
        ],
      ),
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _exportCsv,
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('CSV exportieren'),
        ),
        OutlinedButton.icon(
          onPressed: _selected == null ? null : _exportSelectedJson,
          icon: const Icon(Icons.data_object_outlined),
          label: const Text('JSON exportieren'),
        ),
      ],
      contextBar:
          _error == null
              ? NxCard(
                padding: const EdgeInsets.all(AppSpacing.component),
                child: Row(
                  children: [
                    const Icon(Icons.history_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${_rows.length} Ereignisse geladen')),
                  ],
                ),
              )
              : NxCard(
                padding: const EdgeInsets.all(AppSpacing.component),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final list = _auditListPane(context);
          final details = _auditDetailPane(context);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: list),
                const SizedBox(width: AppSpacing.component),
                Expanded(flex: 2, child: details),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 460, child: list),
                const SizedBox(height: AppSpacing.component),
                SizedBox(height: 520, child: details),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _auditListPane(BuildContext context) {
    return NxCard(
      child:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const NxEmptyState(
                    title: 'Keine Ereignisse',
                    description: 'Filter ändern oder später erneut laden.',
                    icon: Icons.history_toggle_off_outlined,
                  )
                  : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return ListTile(
                        selected: _selected?.id == row.id,
                        selectedTileColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        leading: Icon(_auditIcon(row.action)),
                        title: Text(
                          '${_actionLabel(row.action)} · ${row.entityType}:${row.entityId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_formatDate(row.occurredAt)}\n'
                          '${row.summary ?? '-'}\n'
                          'Quelle: ${row.source}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => setState(() => _selected = row),
                      );
                    },
                  ),
    );
  }

  Widget _auditDetailPane(BuildContext context) {
    final selected = _selected;
    return NxCard(
      child:
          selected == null
              ? const NxEmptyState(
                title: 'Ereignis auswählen',
                description: 'Links ein Audit-Ereignis auswählen.',
                icon: Icons.manage_search_outlined,
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_auditIcon(selected.action), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _actionLabel(selected.action),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      NxStatusBadge(
                        label: selected.isSystemEvent ? 'System' : 'User',
                        kind:
                            selected.isSystemEvent
                                ? NxBadgeKind.info
                                : NxBadgeKind.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.component),
                  Wrap(
                    spacing: AppSpacing.component,
                    runSpacing: AppSpacing.component,
                    children: [
                      _AuditFact(label: 'Quelle', value: selected.source),
                      _AuditFact(
                        label: 'Workspace',
                        value: selected.workspaceId ?? '-',
                      ),
                      _AuditFact(
                        label: 'Benutzer',
                        value: selected.actorUserId ?? '-',
                      ),
                      _AuditFact(
                        label: 'Rolle',
                        value: selected.actorRole ?? '-',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.component),
                  Text(
                    selected.summary ?? 'Keine Zusammenfassung',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (selected.reason != null) ...[
                    const SizedBox(height: 6),
                    Text('Grund: ${selected.reason}'),
                  ],
                  const SizedBox(height: AppSpacing.component),
                  Expanded(
                    child: ListView(
                      children: [
                        _JsonBlock(
                          title: 'Vorher',
                          value: selected.oldValues,
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _JsonBlock(
                          title: 'Nachher',
                          value: selected.newValues,
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Text(
                          'Änderungen',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        if (selected.diffItems.isEmpty)
                          const Text('Keine einzelnen Feldänderungen.')
                        else
                          for (final item in selected.diffItems)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.fieldKey),
                              subtitle: Text(
                                'Vorher: ${item.before ?? '-'}\nNachher: ${item.after ?? '-'}',
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

  Future<void> _pickDate(TextEditingController controller) async {
    final initial =
        DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    controller.text = _formatDateOnly(picked);
  }

  String _formatDateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _AuditDateField extends StatelessWidget {
  const _AuditDateField({
    required this.controller,
    required this.label,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: IconButton(
          onPressed: onPick,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
    );
  }
}

class _AuditFact extends StatelessWidget {
  const _AuditFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.viewport == AppViewport.mobile ? double.infinity : 190,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              value == null
                  ? '-'
                  : const JsonEncoder.withIndent('  ').convert(value),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

String _actionLabel(String action) {
  switch (action) {
    case 'create':
      return 'Erstellt';
    case 'update':
    case 'update_role':
      return 'Geändert';
    case 'delete':
      return 'Gelöscht';
    case 'import':
      return 'Import';
    case 'approved':
      return 'Freigegeben';
    case 'rejected':
      return 'Abgelehnt';
    case 'switch_user':
      return 'Nutzerwechsel';
    case 'switch_workspace':
      return 'Workspacewechsel';
    default:
      return action;
  }
}

IconData _auditIcon(String action) {
  switch (action) {
    case 'create':
      return Icons.add_circle_outline;
    case 'delete':
      return Icons.delete_outline;
    case 'import':
      return Icons.upload_file_outlined;
    case 'approved':
      return Icons.verified_outlined;
    case 'rejected':
      return Icons.block_outlined;
    case 'switch_user':
      return Icons.person_search_outlined;
    case 'switch_workspace':
      return Icons.workspaces_outline;
    default:
      return Icons.edit_outlined;
  }
}
