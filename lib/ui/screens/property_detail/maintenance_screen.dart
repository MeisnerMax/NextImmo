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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _createTicketDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Ticket'),
              ),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          _MaintenanceSummary(tickets: _tickets),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                _tickets.isEmpty
                    ? const Card(
                        child: Center(child: Text('No maintenance tickets.')),
                      )
                    : ListView.separated(
                        itemCount: _tickets.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                        itemBuilder: (context, index) {
                          final item = _tickets[index];
                          return _MaintenanceTicketCard(
                            ticket: item,
                            onResolve: () => _setDone(item),
                          );
                        },
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
    final descriptionCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    final costEstimateCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    String category = 'general';
    String priority = 'normal';
    DateTime? dueDate;

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
                        TextField(
                          controller: descriptionCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: category,
                          items: const [
                            DropdownMenuItem(
                              value: 'general',
                              child: Text('General'),
                            ),
                            DropdownMenuItem(
                              value: 'plumbing',
                              child: Text('Plumbing'),
                            ),
                            DropdownMenuItem(
                              value: 'electrical',
                              child: Text('Electrical'),
                            ),
                            DropdownMenuItem(value: 'hvac', child: Text('HVAC')),
                            DropdownMenuItem(
                              value: 'safety',
                              child: Text('Safety'),
                            ),
                            DropdownMenuItem(
                              value: 'exterior',
                              child: Text('Exterior'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => category = value);
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'Category',
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
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: dueCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Due date',
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dueDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) {
                              return;
                            }
                            setDialogState(() {
                              dueDate = picked;
                              dueCtrl.text = _formatDateMs(
                                picked.millisecondsSinceEpoch,
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: costEstimateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Estimated cost',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: vendorCtrl,
                          decoration: const InputDecoration(labelText: 'Vendor'),
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
                              description:
                                  descriptionCtrl.text.trim().isEmpty
                                      ? null
                                      : descriptionCtrl.text.trim(),
                              category: category,
                              priority: priority,
                              dueAt: dueDate?.millisecondsSinceEpoch,
                              costEstimate:
                                  costEstimateCtrl.text.trim().isEmpty
                                      ? null
                                      : double.tryParse(
                                        costEstimateCtrl.text.trim(),
                                      ),
                              vendorName:
                                  vendorCtrl.text.trim().isEmpty
                                      ? null
                                      : vendorCtrl.text.trim(),
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
    descriptionCtrl.dispose();
    dueCtrl.dispose();
    costEstimateCtrl.dispose();
    vendorCtrl.dispose();
  }

  Future<void> _setDone(MaintenanceTicketRecord ticket) async {
    final updated = MaintenanceTicketRecord(
      id: ticket.id,
      assetPropertyId: ticket.assetPropertyId,
      unitId: ticket.unitId,
      title: ticket.title,
      description: ticket.description,
      category: ticket.category,
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

  String _formatDateMs(int value) {
    return DateTime.fromMillisecondsSinceEpoch(
      value,
    ).toIso8601String().substring(0, 10);
  }
}

class _MaintenanceSummary extends StatelessWidget {
  const _MaintenanceSummary({required this.tickets});

  final List<MaintenanceTicketRecord> tickets;

  @override
  Widget build(BuildContext context) {
    final open =
        tickets.where((ticket) => !{'resolved', 'closed'}.contains(ticket.status)).length;
    final overdue = tickets.where((ticket) {
      final dueAt = ticket.dueAt;
      return dueAt != null &&
          dueAt < DateTime.now().millisecondsSinceEpoch &&
          !{'resolved', 'closed'}.contains(ticket.status);
    }).length;
    final inProgress =
        tickets.where((ticket) => ticket.status == 'in_progress').length;
    final exposure = tickets.fold<double>(
      0,
      (sum, ticket) => sum + (ticket.costActual ?? ticket.costEstimate ?? 0),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryTile(label: 'Open', value: open.toString()),
        _SummaryTile(label: 'Overdue', value: overdue.toString()),
        _SummaryTile(label: 'In progress', value: inProgress.toString()),
        _SummaryTile(label: 'Cost exposure', value: exposure.toStringAsFixed(0)),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
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
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceTicketCard extends StatelessWidget {
  const _MaintenanceTicketCard({
    required this.ticket,
    required this.onResolve,
  });

  final MaintenanceTicketRecord ticket;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final dueLabel =
        ticket.dueAt == null
            ? 'No due date'
            : DateTime.fromMillisecondsSinceEpoch(
              ticket.dueAt!,
            ).toIso8601String().substring(0, 10);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ticket.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(ticket.status),
                _Pill(ticket.priority),
                _Pill(ticket.category.replaceAll('_', ' ')),
                _Pill('Due $dueLabel'),
                if (ticket.costEstimate != null)
                  _Pill('Estimate ${ticket.costEstimate!.toStringAsFixed(0)}'),
              ],
            ),
            if (ticket.description != null &&
                ticket.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(ticket.description!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ticket.status != 'resolved' && ticket.status != 'closed')
                  TextButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Resolve'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
