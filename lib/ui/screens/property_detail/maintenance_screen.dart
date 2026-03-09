import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/maintenance.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class PropertyMaintenanceScreen extends ConsumerStatefulWidget {
  const PropertyMaintenanceScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyMaintenanceScreen> createState() =>
      _PropertyMaintenanceScreenState();
}

class _PropertyMaintenanceScreenState
    extends ConsumerState<PropertyMaintenanceScreen> {
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
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _createTicketDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Ticket'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Card(
              child:
                  _tickets.isEmpty
                      ? const Center(child: Text('No maintenance tickets.'))
                      : ListView.builder(
                        itemCount: _tickets.length,
                        itemBuilder: (context, index) {
                          final item = _tickets[index];
                          return ListTile(
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.status} | ${item.priority}${item.dueAt == null ? '' : ' | due ${DateTime.fromMillisecondsSinceEpoch(item.dueAt!).toIso8601String().substring(0, 10)}'}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _setDone(item),
                              child: const Text('Resolve'),
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
        .listTickets(assetPropertyId: widget.propertyId);
    if (!mounted) {
      return;
    }
    setState(() {
      _tickets = tickets;
    });
  }

  Future<void> _createTicketDialog() async {
    final titleCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    String priority = 'normal';

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Create Ticket'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(labelText: 'Title'),
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
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: dueCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Due At (epoch ms)',
                          ),
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
                        if (titleCtrl.text.trim().isEmpty) {
                          return;
                        }
                        await ref
                            .read(maintenanceRepositoryProvider)
                            .createTicket(
                              assetPropertyId: widget.propertyId,
                              title: titleCtrl.text.trim(),
                              priority: priority,
                              dueAt:
                                  dueCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(dueCtrl.text.trim()),
                              createTask: true,
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

    titleCtrl.dispose();
    dueCtrl.dispose();
  }

  Future<void> _setDone(MaintenanceTicketRecord ticket) async {
    final updated = MaintenanceTicketRecord(
      id: ticket.id,
      assetPropertyId: ticket.assetPropertyId,
      unitId: ticket.unitId,
      title: ticket.title,
      description: ticket.description,
      status: 'resolved',
      priority: ticket.priority,
      reportedAt: ticket.reportedAt,
      dueAt: ticket.dueAt,
      resolvedAt: DateTime.now().millisecondsSinceEpoch,
      costEstimate: ticket.costEstimate,
      costActual: ticket.costActual,
      vendorName: ticket.vendorName,
      documentId: ticket.documentId,
      createdAt: ticket.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(maintenanceRepositoryProvider).updateTicket(updated);
    await _reload();
  }
}
