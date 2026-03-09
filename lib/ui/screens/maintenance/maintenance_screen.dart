import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/maintenance.dart';
import '../../state/app_state.dart';
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
  List<MaintenanceTicketRecord> _tickets = const [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
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
                width: 220,
                child: TextFormField(
                  initialValue: _assetPropertyId,
                  decoration: const InputDecoration(
                    labelText: 'Asset Property ID',
                  ),
                  onChanged: (value) => _assetPropertyId = value.trim(),
                  onFieldSubmitted: (_) => _reload(),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('status: all')),
                    DropdownMenuItem(value: 'open', child: Text('open')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('in_progress'),
                    ),
                    DropdownMenuItem(value: 'waiting', child: Text('waiting')),
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
                    setState(() => _statusFilter = value);
                    _reload();
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _priorityFilter,
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('priority: all'),
                    ),
                    DropdownMenuItem(value: 'low', child: Text('low')),
                    DropdownMenuItem(value: 'normal', child: Text('normal')),
                    DropdownMenuItem(value: 'high', child: Text('high')),
                    DropdownMenuItem(value: 'urgent', child: Text('urgent')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _priorityFilter = value);
                    _reload();
                  },
                ),
              ),
              ElevatedButton.icon(
                onPressed: _createTicketDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Ticket'),
              ),
              OutlinedButton(
                onPressed: _runDueNotifications,
                child: const Text('Run Due Notifications'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Card(
              child:
                  _tickets.isEmpty
                      ? const Center(child: Text('No tickets found.'))
                      : ListView.builder(
                        itemCount: _tickets.length,
                        itemBuilder: (context, index) {
                          final ticket = _tickets[index];
                          return ListTile(
                            title: Text(ticket.title),
                            subtitle: Text(
                              '${ticket.status} | ${ticket.priority} | asset ${ticket.assetPropertyId}${ticket.dueAt == null ? '' : ' | due ${DateTime.fromMillisecondsSinceEpoch(ticket.dueAt!).toIso8601String().substring(0, 10)}'}',
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => _changeStatusDialog(ticket),
                                  child: const Text('Status'),
                                ),
                                TextButton(
                                  onPressed: () => _deleteTicket(ticket.id),
                                  child: const Text('Delete'),
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

  Future<void> _reload() async {
    final tickets = await ref
        .read(maintenanceRepositoryProvider)
        .listTickets(
          assetPropertyId: _assetPropertyId.isEmpty ? null : _assetPropertyId,
          status: _statusFilter == 'all' ? null : _statusFilter,
          priority: _priorityFilter == 'all' ? null : _priorityFilter,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _tickets = tickets;
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
}
