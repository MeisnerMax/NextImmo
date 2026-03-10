import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/maintenance.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String _assetPropertyId = '';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  List<MaintenanceWorkflowRecord> _tickets = const [];
  MaintenanceWorkflowRecord? _selectedTicket;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final openCount =
        _tickets
            .where(
              (ticket) =>
                  !{'resolved', 'closed'}.contains(ticket.ticket.status),
            )
            .length;
    final linkedTaskCount = _tickets.fold<int>(
      0,
      (sum, ticket) => sum + ticket.linkedTaskCount,
    );

    return ListFilterTemplate(
      title: 'Maintenance',
      breadcrumbs: const ['Operations', 'Maintenance'],
      subtitle:
          'Manage maintenance issues with visible asset context, linked documents and follow-up tasks.',
      primaryAction: ElevatedButton.icon(
        onPressed: _createTicketDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: _runDueNotifications,
          child: const Text('Run Due Notifications'),
        ),
        OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
      ],
      contextBar: ListFilterBar(
        children: [
          NxStatusBadge(
            label: '$openCount open',
            kind: openCount == 0 ? NxBadgeKind.neutral : NxBadgeKind.warning,
          ),
          NxStatusBadge(
            label: '$linkedTaskCount linked tasks',
            kind: NxBadgeKind.info,
          ),
          if (_status != null)
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: 220,
            child: TextFormField(
              initialValue: _assetPropertyId,
              decoration: const InputDecoration(labelText: 'Asset Property ID'),
              onChanged: (value) => _assetPropertyId = value.trim(),
              onFieldSubmitted: (_) => _reload(),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All statuses')),
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('In progress'),
                ),
                DropdownMenuItem(value: 'waiting', child: Text('Waiting')),
                DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                DropdownMenuItem(value: 'closed', child: Text('Closed')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _statusFilter = value);
                _reload();
              },
              decoration: const InputDecoration(labelText: 'Status'),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              value: _priorityFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All priorities')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _priorityFilter = value);
                _reload();
              },
              decoration: const InputDecoration(labelText: 'Priority'),
            ),
          ),
        ],
      ),
      content:
          _tickets.isEmpty
              ? const NxEmptyState(
                title: 'No tickets found',
                description:
                    'Create a ticket or widen the current filters to inspect maintenance work.',
                icon: Icons.build_outlined,
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 1060;
                  if (stacked) {
                    return Column(
                      children: [
                        Expanded(flex: 3, child: _buildTicketList()),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(flex: 2, child: _buildTicketDetail()),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _buildTicketList()),
                      const SizedBox(width: AppSpacing.component),
                      Expanded(child: _buildTicketDetail()),
                    ],
                  );
                },
              ),
    );
  }

  Widget _buildTicketList() {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        itemCount: _tickets.length,
        separatorBuilder:
            (_, __) => Divider(height: 1, color: context.semanticColors.border),
        itemBuilder: (context, index) {
          final workflow = _tickets[index];
          final ticket = workflow.ticket;
          return ListTile(
            selected: _selectedTicket?.ticket.id == ticket.id,
            title: Text(ticket.title),
            subtitle: Text(
              '${workflow.propertyName ?? ticket.assetPropertyId} · ${ticket.status} · ${ticket.priority}${ticket.dueAt == null ? '' : ' · due ${_formatDate(ticket.dueAt)}'}',
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (workflow.linkedTaskCount > 0)
                  NxStatusBadge(
                    label:
                        '${workflow.linkedTaskCount} task${workflow.linkedTaskCount == 1 ? '' : 's'}',
                    kind: NxBadgeKind.info,
                  ),
                if (workflow.documentName != null)
                  const NxStatusBadge(
                    label: 'Document',
                    kind: NxBadgeKind.warning,
                  ),
              ],
            ),
            onTap: () => setState(() => _selectedTicket = workflow),
          );
        },
      ),
    );
  }

  Widget _buildTicketDetail() {
    final workflow = _selectedTicket;
    if (workflow == null) {
      return const NxCard(child: Center(child: Text('Select a ticket')));
    }
    final ticket = workflow.ticket;
    return NxCard(
      child: ListView(
        children: [
          Text(ticket.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NxStatusBadge(
                label: ticket.status,
                kind:
                    ticket.status == 'resolved' || ticket.status == 'closed'
                        ? NxBadgeKind.success
                        : NxBadgeKind.info,
              ),
              NxStatusBadge(
                label: ticket.priority,
                kind:
                    ticket.priority == 'urgent'
                        ? NxBadgeKind.error
                        : ticket.priority == 'high'
                        ? NxBadgeKind.warning
                        : NxBadgeKind.neutral,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Asset: ${workflow.propertyName ?? ticket.assetPropertyId}'),
          if (ticket.description != null &&
              ticket.description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Issue: ${ticket.description}'),
            ),
          const SizedBox(height: 4),
          Text(
            'Deadline: ${ticket.dueAt == null ? 'Not set' : _formatDate(ticket.dueAt)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Budget impact: ${ticket.costActual != null
                ? 'Actual ${ticket.costActual!.toStringAsFixed(2)}'
                : ticket.costEstimate != null
                ? 'Estimate ${ticket.costEstimate!.toStringAsFixed(2)}'
                : 'Pending assessment'}',
          ),
          const SizedBox(height: 4),
          Text(
            'Budget classification: ${ticket.costActual != null || ticket.costEstimate != null ? 'Pending Capex / Opex review' : 'Not assessed yet'}',
          ),
          const SizedBox(height: 4),
          Text('Document: ${workflow.documentName ?? 'No linked document'}'),
          const SizedBox(height: 4),
          Text('Follow-up task: ${workflow.linkedTaskCount} linked'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _changeStatusDialog(ticket),
                child: const Text('Update Status'),
              ),
              OutlinedButton(
                onPressed: () => _openTicketContext(workflow),
                child: const Text('Open Context'),
              ),
              TextButton(
                onPressed: () => _deleteTicket(ticket.id),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final tickets = await ref
        .read(maintenanceRepositoryProvider)
        .listWorkflowTickets(
          assetPropertyId: _assetPropertyId.isEmpty ? null : _assetPropertyId,
          status: _statusFilter == 'all' ? null : _statusFilter,
          priority: _priorityFilter == 'all' ? null : _priorityFilter,
        );
    if (!mounted) {
      return;
    }
    MaintenanceWorkflowRecord? selectedTicket;
    if (_selectedTicket != null) {
      for (final ticket in tickets) {
        if (ticket.ticket.id == _selectedTicket!.ticket.id) {
          selectedTicket = ticket;
          break;
        }
      }
    }
    setState(() {
      _tickets = tickets;
      _selectedTicket =
          selectedTicket ?? (tickets.isEmpty ? null : tickets.first);
    });
  }

  Future<void> _createTicketDialog() async {
    final assetCtrl = TextEditingController(text: _assetPropertyId);
    final titleCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'normal';
    bool createTask = true;

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Create Maintenance Ticket'),
                  content: SizedBox(
                    width: 460,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: assetCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Asset Property ID',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: priority,
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('low')),
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('normal'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('high'),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('urgent'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() => priority = value);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: dueCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Due At (epoch ms, optional)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: createTask,
                          onChanged:
                              (value) =>
                                  setDialogState(() => createTask = value),
                          title: const Text('Create linked task'),
                          contentPadding: EdgeInsets.zero,
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
                        final assetPropertyId = assetCtrl.text.trim();
                        final title = titleCtrl.text.trim();
                        if (assetPropertyId.isEmpty || title.isEmpty) {
                          return;
                        }
                        await ref
                            .read(maintenanceRepositoryProvider)
                            .createTicket(
                              assetPropertyId: assetPropertyId,
                              title: title,
                              description:
                                  descCtrl.text.trim().isEmpty
                                      ? null
                                      : descCtrl.text.trim(),
                              priority: priority,
                              dueAt:
                                  dueCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(dueCtrl.text.trim()),
                              createTask: createTask,
                            );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _reload();
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
          ),
    );

    assetCtrl.dispose();
    titleCtrl.dispose();
    dueCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _changeStatusDialog(MaintenanceTicketRecord ticket) async {
    var status = ticket.status;
    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Update Ticket Status'),
                  content: DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('open')),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('in_progress'),
                      ),
                      DropdownMenuItem(
                        value: 'waiting',
                        child: Text('waiting'),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('resolved'),
                      ),
                      DropdownMenuItem(value: 'closed', child: Text('closed')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() => status = value);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final updated = MaintenanceTicketRecord(
                          id: ticket.id,
                          assetPropertyId: ticket.assetPropertyId,
                          unitId: ticket.unitId,
                          title: ticket.title,
                          description: ticket.description,
                          status: status,
                          priority: ticket.priority,
                          reportedAt: ticket.reportedAt,
                          dueAt: ticket.dueAt,
                          resolvedAt:
                              status == 'resolved' || status == 'closed'
                                  ? DateTime.now().millisecondsSinceEpoch
                                  : ticket.resolvedAt,
                          costEstimate: ticket.costEstimate,
                          costActual: ticket.costActual,
                          vendorName: ticket.vendorName,
                          documentId: ticket.documentId,
                          createdAt: ticket.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                        );
                        await ref
                            .read(maintenanceRepositoryProvider)
                            .updateTicket(updated);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        await _reload();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _deleteTicket(String id) async {
    await ref.read(maintenanceRepositoryProvider).deleteTicket(id);
    await _reload();
  }

  Future<void> _runDueNotifications() async {
    final settings = await ref.read(inputsRepositoryProvider).getSettings();
    final created = await ref
        .read(maintenanceRepositoryProvider)
        .createDueNotifications(dueSoonDays: settings.maintenanceDueSoonDays);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Created $created maintenance notifications.';
    });
  }

  void _openTicketContext(MaintenanceWorkflowRecord workflow) {
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    ref.read(selectedPropertyIdProvider.notifier).state =
        workflow.ticket.assetPropertyId;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.maintenance;
  }

  String _formatDate(int? value) {
    if (value == null) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(
      value,
    ).toIso8601String().substring(0, 10);
  }
}
