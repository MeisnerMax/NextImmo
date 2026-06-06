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
  String _statusFilter = 'all';
  String _categoryFilter = 'all';
  String _dueFilter = 'all';
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTickets = _visibleTickets;
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
          _MaintenanceSummary(tickets: visibleTickets),
          const SizedBox(height: AppSpacing.component),
          _MaintenanceFilterRow(
            statusFilter: _statusFilter,
            categoryFilter: _categoryFilter,
            dueFilter: _dueFilter,
            onStatusChanged: (value) {
              setState(() => _statusFilter = value);
            },
            onCategoryChanged: (value) {
              setState(() => _categoryFilter = value);
            },
            onDueChanged: (value) {
              setState(() => _dueFilter = value);
            },
            onReset: () {
              setState(() {
                _statusFilter = 'all';
                _categoryFilter = 'all';
                _dueFilter = 'all';
              });
            },
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                visibleTickets.isEmpty
                    ? const Card(
                        child: Center(child: Text('No maintenance tickets.')),
                      )
                    : ListView.separated(
                        itemCount: visibleTickets.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                        itemBuilder: (context, index) {
                          final item = visibleTickets[index];
                          return _MaintenanceTicketCard(
                            ticket: item,
                            onResolve: () => _setDone(item),
                            onEdit: () => _editTicketDialog(item),
                          );
                        },
                      ),
            ),
        ],
      ),
    );
  }

  List<MaintenanceTicketRecord> get _visibleTickets {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekEnd = todayStart.add(const Duration(days: 7));
    return _tickets.where((ticket) {
      if (_statusFilter != 'all' && ticket.status != _statusFilter) {
        return false;
      }
      if (_categoryFilter != 'all' && ticket.category != _categoryFilter) {
        return false;
      }
      final dueAt = ticket.dueAt;
      if (_dueFilter == 'none') {
        return dueAt == null;
      }
      if (_dueFilter != 'all' && dueAt == null) {
        return false;
      }
      if (dueAt != null) {
        if (_dueFilter == 'overdue') {
          return dueAt < todayStart.millisecondsSinceEpoch &&
              !_isClosedMaintenanceStatus(ticket.status);
        }
        if (_dueFilter == 'today') {
          return dueAt >= todayStart.millisecondsSinceEpoch &&
              dueAt < todayEnd.millisecondsSinceEpoch;
        }
        if (_dueFilter == 'week') {
          return dueAt >= todayStart.millisecondsSinceEpoch &&
              dueAt < weekEnd.millisecondsSinceEpoch;
        }
        if (_dueFilter == 'later') {
          return dueAt >= weekEnd.millisecondsSinceEpoch;
        }
      }
      return true;
    }).toList(growable: false);
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
    final damageLocationCtrl = TextEditingController();
    final insuranceClaimCtrl = TextEditingController();
    String category = 'damage';
    String priority = 'normal';
    String insuranceStatus = 'reported';
    bool insuranceCase = false;
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
                    child: SingleChildScrollView(
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
                        TextField(
                          controller: damageLocationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Schadenort / Bereich',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: category,
                          items: const [
                            DropdownMenuItem(
                              value: 'damage',
                              child: Text('Schaden'),
                            ),
                            DropdownMenuItem(
                              value: 'defect',
                              child: Text('Mangel'),
                            ),
                            DropdownMenuItem(
                              value: 'repair',
                              child: Text('Reparatur'),
                            ),
                            DropdownMenuItem(
                              value: 'maintenance',
                              child: Text('Wartung'),
                            ),
                            DropdownMenuItem(
                              value: 'renovation',
                              child: Text('Sanierung'),
                            ),
                            DropdownMenuItem(
                              value: 'modernization',
                              child: Text('Renovierung'),
                            ),
                            DropdownMenuItem(
                              value: 'minor_repair',
                              child: Text('Kleinreparatur'),
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
                          decoration: const InputDecoration(
                            labelText: 'Bearbeiter / Firma / Person',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: insuranceCase,
                          onChanged:
                              (value) => setDialogState(
                                () => insuranceCase = value,
                              ),
                          title: const Text('Versicherungsfall'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (insuranceCase) ...[
                          DropdownButtonFormField<String>(
                            value: insuranceStatus,
                            items: const [
                              DropdownMenuItem(
                                value: 'reported',
                                child: Text('Gemeldet'),
                              ),
                              DropdownMenuItem(
                                value: 'in_review',
                                child: Text('In Prüfung'),
                              ),
                              DropdownMenuItem(
                                value: 'approved',
                                child: Text('Freigegeben'),
                              ),
                              DropdownMenuItem(
                                value: 'declined',
                                child: Text('Abgelehnt'),
                              ),
                              DropdownMenuItem(
                                value: 'settled',
                                child: Text('Reguliert'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() => insuranceStatus = value);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Versicherungsstatus',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: insuranceClaimCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Schadennummer optional',
                            ),
                          ),
                        ],
                        ],
                      ),
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
                              damageLocation:
                                  damageLocationCtrl.text.trim().isEmpty
                                      ? null
                                      : damageLocationCtrl.text.trim(),
                              insuranceCase: insuranceCase,
                              insuranceStatus:
                                  insuranceCase ? insuranceStatus : null,
                              insuranceClaimNumber:
                                  insuranceClaimCtrl.text.trim().isEmpty
                                      ? null
                                      : insuranceClaimCtrl.text.trim(),
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
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
  }

  Future<void> _editTicketDialog(MaintenanceTicketRecord ticket) async {
    final titleCtrl = TextEditingController(text: ticket.title);
    final descriptionCtrl = TextEditingController(text: ticket.description ?? '');
    final dueCtrl = TextEditingController(
      text: ticket.dueAt == null ? '' : _formatDateMs(ticket.dueAt!),
    );
    final costEstimateCtrl = TextEditingController(
      text: ticket.costEstimate?.toStringAsFixed(2) ?? '',
    );
    final costActualCtrl = TextEditingController(
      text: ticket.costActual?.toStringAsFixed(2) ?? '',
    );
    final vendorCtrl = TextEditingController(text: ticket.vendorName ?? '');
    final damageLocationCtrl = TextEditingController(
      text: ticket.damageLocation ?? '',
    );
    final insuranceClaimCtrl = TextEditingController(
      text: ticket.insuranceClaimNumber ?? '',
    );
    var category = ticket.category;
    var priority = ticket.priority;
    var status = ticket.status;
    var insuranceCase = ticket.insuranceCase;
    var insuranceStatus = ticket.insuranceStatus ?? 'reported';
    DateTime? dueDate =
        ticket.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ticket.dueAt!);

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Ticket bearbeiten'),
                  content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(labelText: 'Titel'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: descriptionCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Beschreibung',
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: status,
                            items: _propertyMaintenanceStatusItems(status),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() => status = value);
                            },
                            decoration: const InputDecoration(labelText: 'Status'),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: category,
                            items: _propertyMaintenanceCategoryItems(category),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() => category = value);
                            },
                            decoration: const InputDecoration(labelText: 'Ticketart'),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: priority,
                            items: const [
                              DropdownMenuItem(value: 'low', child: Text('low')),
                              DropdownMenuItem(value: 'normal', child: Text('normal')),
                              DropdownMenuItem(value: 'high', child: Text('high')),
                              DropdownMenuItem(value: 'urgent', child: Text('urgent')),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() => priority = value);
                            },
                            decoration: const InputDecoration(labelText: 'Priorität'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: dueCtrl,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Fälligkeit',
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
                                dueCtrl.text =
                                    _formatDateMs(picked.millisecondsSinceEpoch);
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
                              labelText: 'Kostenschätzung',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: costActualCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: 'Ist-Kosten'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: vendorCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bearbeiter / Firma / Person',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: damageLocationCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Schadenort / Bereich',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            value: insuranceCase,
                            onChanged:
                                (value) => setDialogState(
                                  () => insuranceCase = value,
                                ),
                            title: const Text('Versicherungsfall'),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (insuranceCase) ...[
                            DropdownButtonFormField<String>(
                              value: insuranceStatus,
                              items: const [
                                DropdownMenuItem(
                                  value: 'reported',
                                  child: Text('Gemeldet'),
                                ),
                                DropdownMenuItem(
                                  value: 'in_review',
                                  child: Text('In Prüfung'),
                                ),
                                DropdownMenuItem(
                                  value: 'approved',
                                  child: Text('Freigegeben'),
                                ),
                                DropdownMenuItem(
                                  value: 'declined',
                                  child: Text('Abgelehnt'),
                                ),
                                DropdownMenuItem(
                                  value: 'settled',
                                  child: Text('Reguliert'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() => insuranceStatus = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Versicherungsstatus',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: insuranceClaimCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Schadennummer',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) {
                          return;
                        }
                        final updated = MaintenanceTicketRecord(
                          id: ticket.id,
                          assetPropertyId: ticket.assetPropertyId,
                          unitId: ticket.unitId,
                          title: titleCtrl.text.trim(),
                          description:
                              descriptionCtrl.text.trim().isEmpty
                                  ? null
                                  : descriptionCtrl.text.trim(),
                          category: category,
                          status: status,
                          priority: priority,
                          reportedAt: ticket.reportedAt,
                          dueAt: dueDate?.millisecondsSinceEpoch,
                          resolvedAt:
                              _isClosedMaintenanceStatus(status)
                                  ? (ticket.resolvedAt ??
                                      DateTime.now().millisecondsSinceEpoch)
                                  : null,
                          costEstimate: _parseMaintenanceMoney(
                            costEstimateCtrl.text,
                          ),
                          costActual: _parseMaintenanceMoney(costActualCtrl.text),
                          vendorName:
                              vendorCtrl.text.trim().isEmpty
                                  ? null
                                  : vendorCtrl.text.trim(),
                          documentId: ticket.documentId,
                          damageLocation:
                              damageLocationCtrl.text.trim().isEmpty
                                  ? null
                                  : damageLocationCtrl.text.trim(),
                          insuranceCase: insuranceCase,
                          insuranceStatus: insuranceCase ? insuranceStatus : null,
                          insuranceClaimNumber:
                              insuranceClaimCtrl.text.trim().isEmpty
                                  ? null
                                  : insuranceClaimCtrl.text.trim(),
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
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
          ),
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    dueCtrl.dispose();
    costEstimateCtrl.dispose();
    costActualCtrl.dispose();
    vendorCtrl.dispose();
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
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
      damageLocation: ticket.damageLocation,
      insuranceCase: ticket.insuranceCase,
      insuranceStatus: ticket.insuranceStatus,
      insuranceClaimNumber: ticket.insuranceClaimNumber,
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

bool _isClosedMaintenanceStatus(String status) {
  return const {'completed', 'billed', 'resolved', 'closed'}.contains(status);
}

String _maintenanceCategoryLabel(String value) {
  switch (value) {
    case 'damage':
      return 'Schaden';
    case 'defect':
      return 'Mangel';
    case 'repair':
      return 'Reparatur';
    case 'maintenance':
      return 'Wartung';
    case 'renovation':
      return 'Sanierung';
    case 'modernization':
      return 'Renovierung';
    case 'minor_repair':
      return 'Kleinreparatur';
    default:
      return value.replaceAll('_', ' ');
  }
}

class _MaintenanceSummary extends StatelessWidget {
  const _MaintenanceSummary({required this.tickets});

  final List<MaintenanceTicketRecord> tickets;

  @override
  Widget build(BuildContext context) {
    final open =
        tickets.where((ticket) => !_isClosedMaintenanceStatus(ticket.status)).length;
    final overdue = tickets.where((ticket) {
      final dueAt = ticket.dueAt;
      return dueAt != null &&
          dueAt < DateTime.now().millisecondsSinceEpoch &&
          !_isClosedMaintenanceStatus(ticket.status);
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

class _MaintenanceFilterRow extends StatelessWidget {
  const _MaintenanceFilterRow({
    required this.statusFilter,
    required this.categoryFilter,
    required this.dueFilter,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onDueChanged,
    required this.onReset,
  });

  final String statusFilter;
  final String categoryFilter;
  final String dueFilter;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onDueChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Status')),
              DropdownMenuItem(value: 'open', child: Text('open')),
              DropdownMenuItem(value: 'planned', child: Text('planned')),
              DropdownMenuItem(
                value: 'commissioned',
                child: Text('commissioned'),
              ),
              DropdownMenuItem(
                value: 'in_progress',
                child: Text('in_progress'),
              ),
              DropdownMenuItem(
                value: 'waiting_material',
                child: Text('waiting_material'),
              ),
              DropdownMenuItem(
                value: 'waiting_reply',
                child: Text('waiting_reply'),
              ),
              DropdownMenuItem(value: 'completed', child: Text('completed')),
              DropdownMenuItem(value: 'billed', child: Text('billed')),
              DropdownMenuItem(value: 'resolved', child: Text('resolved')),
              DropdownMenuItem(value: 'closed', child: Text('closed')),
            ],
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
            decoration: const InputDecoration(labelText: 'Status'),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: categoryFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Arten')),
              DropdownMenuItem(value: 'damage', child: Text('Schaden')),
              DropdownMenuItem(value: 'defect', child: Text('Mangel')),
              DropdownMenuItem(value: 'repair', child: Text('Reparatur')),
              DropdownMenuItem(value: 'maintenance', child: Text('Wartung')),
              DropdownMenuItem(value: 'renovation', child: Text('Sanierung')),
              DropdownMenuItem(
                value: 'modernization',
                child: Text('Renovierung'),
              ),
              DropdownMenuItem(
                value: 'minor_repair',
                child: Text('Kleinreparatur'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onCategoryChanged(value);
              }
            },
            decoration: const InputDecoration(labelText: 'Ticketart'),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: dueFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Termine')),
              DropdownMenuItem(value: 'overdue', child: Text('Überfällig')),
              DropdownMenuItem(value: 'today', child: Text('Heute')),
              DropdownMenuItem(value: 'week', child: Text('Diese Woche')),
              DropdownMenuItem(value: 'later', child: Text('Später')),
              DropdownMenuItem(value: 'none', child: Text('Ohne Termin')),
            ],
            onChanged: (value) {
              if (value != null) {
                onDueChanged(value);
              }
            },
            decoration: const InputDecoration(labelText: 'Termin'),
          ),
        ),
        TextButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Reset'),
        ),
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
    required this.onEdit,
  });

  final MaintenanceTicketRecord ticket;
  final VoidCallback onResolve;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final dueLabel =
        ticket.dueAt == null
            ? 'No due date'
            : DateTime.fromMillisecondsSinceEpoch(
              ticket.dueAt!,
            ).toIso8601String().substring(0, 10);
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Bearbeiten',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(ticket.status),
                _Pill(ticket.priority),
                _Pill(_maintenanceCategoryLabel(ticket.category)),
                _Pill('Due $dueLabel'),
                if (ticket.costEstimate != null)
                  _Pill('Estimate ${ticket.costEstimate!.toStringAsFixed(0)}'),
                if (ticket.vendorName != null) _Pill(ticket.vendorName!),
                if (ticket.damageLocation != null &&
                    ticket.damageLocation!.trim().isNotEmpty)
                  _Pill(ticket.damageLocation!),
                if (ticket.insuranceCase)
                  _Pill(
                    'Versicherung ${ticket.insuranceStatus ?? 'offen'}',
                  ),
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
                if (!_isClosedMaintenanceStatus(ticket.status))
                  TextButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Resolve'),
                  ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
              ],
            ),
          ],
        ),
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

List<DropdownMenuItem<String>> _propertyMaintenanceStatusItems(String current) {
  const values = <String>[
    'open',
    'planned',
    'commissioned',
    'in_progress',
    'waiting_material',
    'waiting_reply',
    'completed',
    'billed',
    'resolved',
    'closed',
  ];
  return [
    if (!values.contains(current))
      DropdownMenuItem(value: current, child: Text(current)),
    for (final value in values)
      DropdownMenuItem(value: value, child: Text(value.replaceAll('_', ' '))),
  ];
}

List<DropdownMenuItem<String>> _propertyMaintenanceCategoryItems(
  String current,
) {
  const values = <String>[
    'damage',
    'defect',
    'repair',
    'maintenance',
    'renovation',
    'modernization',
    'minor_repair',
  ];
  return [
    if (!values.contains(current))
      DropdownMenuItem(value: current, child: Text(_maintenanceCategoryLabel(current))),
    for (final value in values)
      DropdownMenuItem(value: value, child: Text(_maintenanceCategoryLabel(value))),
  ];
}

double? _parseMaintenanceMoney(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  return normalized.isEmpty ? null : double.tryParse(normalized);
}
