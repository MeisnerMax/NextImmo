import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/maintenance.dart';
import '../../../core/models/property.dart';
import '../../../core/models/operations.dart';
import '../../../core/models/task.dart';
import '../../../core/models/documents.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

class PropertyMaintenanceScreen extends ConsumerStatefulWidget {
  const PropertyMaintenanceScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyMaintenanceScreen> createState() =>
      _PropertyMaintenanceScreenState();
}
class _PropertyMaintenanceScreenState
    extends ConsumerState<PropertyMaintenanceScreen> with SingleTickerProviderStateMixin {
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String _categoryFilter = 'all';
  String _assigneeFilter = 'all';
  String _dueFilter = 'all';
  String _unitFilter = 'all';
  String _viewMode = 'list';
  List<MaintenanceWorkflowRecord> _tickets = const [];
  MaintenanceWorkflowRecord? _selectedTicket;
  String? _status;
  PropertyRecord? _property;
  List<UnitRecord> _units = const [];
  // Bauteilzustand state
  final Map<String, _BauteilStatusEntry> _bauteilStatus = {};
  late TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _tabIndex = _tabController.index;
        });
      }
    });
    _reload();
  }  @override
  void didUpdateWidget(PropertyMaintenanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _tickets
        .where((w) => !_isClosedStatus(w.ticket.status))
        .length;
    final linkedTaskCount = _tickets.fold<int>(
      0,
      (sum, w) => sum + w.linkedTaskCount,
    );

    return ListFilterTemplate(
      title: 'Instandhaltung & CapEx',
      breadcrumbs: ['Objekte', _property?.name ?? widget.propertyId, 'Instandhaltung'],
      subtitle: 'Tickets, Sanierungen, CapEx-Planung und Gewährleistungen verwalten.',
      expandContent: false,
      primaryAction: ElevatedButton.icon(
        onPressed: _createTicketDialog,
        icon: const Icon(Icons.add),
        label: const Text('Neues Ticket'),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: _runDueNotifications,
          child: const Text('Fälligkeiten prüfen'),
        ),
        OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
      ],
      contextBar: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Tickets'),
              Tab(text: 'Sanierungen'),
              Tab(text: 'CapEx-Planung'),
              Tab(text: 'Gewährleistung'),
              Tab(text: 'Bauteilzustand'),
            ],
          ),
        ),
      ),
      content: _buildActiveTab(),
    );
  }

  Widget _buildActiveTab() {
    switch (_tabIndex) {
      case 0:
        return _buildTicketsTab();
      case 1:
        return _buildRenovationsTab();
      case 2:
        return _buildCapexTab();
      case 3:
        return _buildWarrantiesTab();
      case 4:
        return _buildBauteilzustandTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTicketsTab() {
    final tickets = _visibleTickets.where((w) {
      final cat = w.ticket.category;
      return cat == 'damage' ||
          cat == 'defect' ||
          cat == 'repair' ||
          cat == 'minor_repair' ||
          cat == 'maintenance';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTicketsFiltersBar(),
        const SizedBox(height: AppSpacing.component),
        tickets.isEmpty
            ? const NxEmptyState(
                title: 'Keine Tickets gefunden',
                description: 'Erstellen Sie ein neues Ticket für dieses Objekt oder passen Sie die Filter an.',
                icon: Icons.build_outlined,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (_viewMode == 'board') {
                    return Column(
                      children: [
                        _PropertyMaintenanceDashboard(
                          tickets: tickets,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _dueFilter = filter;
                              _viewMode = 'list';
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildBoard(tickets),
                      ],
                    );
                  }
                  if (_viewMode == 'calendar') {
                    return Column(
                      children: [
                        _PropertyMaintenanceDashboard(
                          tickets: tickets,
                          onStatusFilter: (status) {
                            setState(() {
                              _statusFilter = status;
                              _viewMode = 'list';
                            });
                          },
                          onDueFilter: (filter) {
                            setState(() {
                              _dueFilter = filter;
                              _viewMode = 'list';
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildDuePlanner(tickets),
                      ],
                    );
                  }
                  final stacked = constraints.maxWidth < 1060;
                  if (stacked) {
                    return Column(
                      children: [
                        _PropertyMaintenanceDashboard(
                          tickets: tickets,
                          onStatusFilter: (status) {
                            setState(() => _statusFilter = status);
                          },
                          onDueFilter: (filter) {
                            setState(() => _dueFilter = filter);
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        _buildTicketList(tickets),
                        const SizedBox(height: AppSpacing.component),
                        _buildTicketDetail(),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _PropertyMaintenanceDashboard(
                        tickets: tickets,
                        onStatusFilter: (status) {
                          setState(() => _statusFilter = status);
                        },
                        onDueFilter: (filter) {
                          setState(() => _dueFilter = filter);
                        },
                      ),
                      const SizedBox(height: AppSpacing.component),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTicketList(tickets)),
                          const SizedBox(width: AppSpacing.component),
                          Expanded(child: _buildTicketDetail()),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ],
    );
  }

  Widget _buildTicketsFiltersBar() {
    final assigneeOptions = _assigneeOptions;
    return ListFilterBar(
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: _unitFilter == 'all' ? 'all' : (_units.any((u) => u.id == _unitFilter) ? _unitFilter : 'all'),
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('Alle Einheiten')),
              ..._units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.unitCode))),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _unitFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Einheit'),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: _statusFilter,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Status')),
              DropdownMenuItem(value: 'open', child: Text('Open')),
              DropdownMenuItem(value: 'planned', child: Text('Planned')),
              DropdownMenuItem(value: 'commissioned', child: Text('Commissioned')),
              DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
              DropdownMenuItem(value: 'waiting_material', child: Text('Waiting for material')),
              DropdownMenuItem(value: 'waiting_reply', child: Text('Waiting for reply')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'billed', child: Text('Billed')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'closed', child: Text('Closed')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _statusFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Status'),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            value: _priorityFilter,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Prioritäten')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'normal', child: Text('Normal')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _priorityFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Priorität'),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: _categoryFilter,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Arten')),
              DropdownMenuItem(value: 'damage', child: Text('Schaden')),
              DropdownMenuItem(value: 'defect', child: Text('Mangel')),
              DropdownMenuItem(value: 'repair', child: Text('Reparatur')),
              DropdownMenuItem(value: 'maintenance', child: Text('Wartung')),
              DropdownMenuItem(value: 'minor_repair', child: Text('Kleinreparatur')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _categoryFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Ticketart'),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            value: _assigneeFilter,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('Alle Bearbeiter')),
              const DropdownMenuItem(value: 'unassigned', child: Text('Nicht zugewiesen')),
              ...assigneeOptions.map(
                (assignee) => DropdownMenuItem(
                  value: assignee,
                  child: Text(assignee, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _assigneeFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Bearbeiter'),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: _dueFilter,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle Termine')),
              DropdownMenuItem(value: 'overdue', child: Text('Überfällig')),
              DropdownMenuItem(value: 'today', child: Text('Heute')),
              DropdownMenuItem(value: 'week', child: Text('Diese Woche')),
              DropdownMenuItem(value: 'later', child: Text('Später')),
              DropdownMenuItem(value: 'none', child: Text('Ohne Termin')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dueFilter = value;
                _selectedTicket = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Termin'),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            value: _viewMode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'list', child: Text('Liste')),
              DropdownMenuItem(value: 'board', child: Text('Board')),
              DropdownMenuItem(value: 'calendar', child: Text('Termine')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _viewMode = value);
            },
            decoration: const InputDecoration(labelText: 'Ansicht'),
          ),
        ),
        TextButton.icon(
          onPressed: _resetFilters,
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _buildRenovationsTab() {
    final renovations = _tickets.where((w) {
      final cat = w.ticket.category;
      return cat == 'renovation' || cat == 'modernization';
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _createTicketDialog(initialCategory: 'renovation'),
                icon: const Icon(Icons.add),
                label: const Text('Sanierung anlegen'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          renovations.isEmpty
              ? const NxEmptyState(
                  title: 'Keine Sanierungen gefunden',
                  description: 'Legen Sie ein neues Sanierungsprojekt an.',
                  icon: Icons.construction_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: renovations.length,
                  itemBuilder: (context, index) {
                    final workflow = renovations[index];
                    final ticket = workflow.ticket;
                    double progress = 0.0;
                    if (ticket.status == 'completed' || ticket.status == 'resolved' || ticket.status == 'closed') {
                      progress = 1.0;
                    } else if (ticket.startDate != null && ticket.endDate != null) {
                      final now = DateTime.now().millisecondsSinceEpoch;
                      if (now >= ticket.endDate!) {
                        progress = 1.0;
                      } else if (now <= ticket.startDate!) {
                        progress = 0.0;
                      } else {
                        progress = (now - ticket.startDate!) / (ticket.endDate! - ticket.startDate!);
                      }
                    } else if (ticket.status == 'in_progress') {
                      progress = 0.5;
                    }

                    final costEstimate = ticket.costEstimate ?? 0.0;
                      final costActual = ticket.costActual ?? 0.0;
                      final overBudget = costActual > costEstimate && costEstimate > 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.component),
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
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  NxStatusBadge(
                                    label: ticket.status.replaceAll('_', ' '),
                                    kind: _isClosedStatus(ticket.status)
                                        ? NxBadgeKind.success
                                        : NxBadgeKind.info,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editTicketDialog(ticket),
                                  ),
                                ],
                              ),
                              if (ticket.description != null && ticket.description!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  ticket.description!,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (ticket.startDate != null) ...[
                                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Start: ${_shortDate(ticket.startDate!)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  if (ticket.endDate != null) ...[
                                    const Icon(Icons.event, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ende: ${_shortDate(ticket.endDate!)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  if (ticket.vendorName != null) ...[
                                    const Icon(Icons.business, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      ticket.vendorName!,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'Fortschritt: ${(progress * 100).toStringAsFixed(0)}%',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.green,
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Geschätzte Kosten: ${_formatCurrency(costEstimate)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    'Tatsächliche Kosten: ${_formatCurrency(costActual)}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: overBudget ? Colors.red : null,
                                          fontWeight: overBudget ? FontWeight.bold : null,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ],
      ),
    );
  }

  Widget _buildCapexTab() {
    final capexTickets = _tickets.where((w) {
      final t = w.ticket;
      return t.status == 'planned' || t.status == 'idea' ||
             t.category == 'renovation' || t.category == 'modernization';
    }).toList();

    double totalPlanned = 0.0;
    double totalCommitted = 0.0;
    double totalCompleted = 0.0;

    for (final workflow in capexTickets) {
      final t = workflow.ticket;
      final est = t.costEstimate ?? 0.0;
      final act = t.costActual ?? 0.0;
      if (t.status == 'completed' || t.status == 'resolved' || t.status == 'closed') {
        totalCompleted += act;
      } else if (t.status == 'planned' || t.status == 'idea') {
        totalPlanned += est;
      } else {
        totalCommitted += est;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _createTicketDialog(initialCategory: 'renovation', initialStatus: 'planned'),
                icon: const Icon(Icons.add),
                label: const Text('CapEx-Maßnahme planen'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Geplantes CapEx (Idee/Geplant)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(totalPlanned), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Beauftragtes CapEx (Aktiv)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(totalCommitted), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Investiertes CapEx (Abgeschlossen)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(totalCompleted), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          capexTickets.isEmpty
              ? const NxEmptyState(
                  title: 'Keine CapEx-Maßnahmen geplant',
                  description: 'Planen Sie eine neue wertsteigernde Investition.',
                  icon: Icons.trending_up,
                )
              : Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Maßnahme')),
                            DataColumn(label: Text('Kategorie')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Schätzung')),
                            DataColumn(label: Text('Ist-Kosten')),
                            DataColumn(label: Text('Abweichung')),
                            DataColumn(label: Text('Aktionen')),
                          ],
                          rows: capexTickets.map((workflow) {
                            final ticket = workflow.ticket;
                            final est = ticket.costEstimate ?? 0.0;
                            final act = ticket.costActual ?? 0.0;
                            final diff = act - est;
                            final isCompleted = ticket.status == 'completed' || ticket.status == 'resolved' || ticket.status == 'closed';
                            final hasOverrun = diff > 0 && isCompleted;

                            return DataRow(
                              cells: [
                                DataCell(Text(ticket.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(_categoryLabel(ticket.category))),
                                DataCell(NxStatusBadge(
                                  label: ticket.status.replaceAll('_', ' '),
                                  kind: isCompleted ? NxBadgeKind.success : NxBadgeKind.info,
                                )),
                                DataCell(Text(_formatCurrency(est), style: context.tabularNumericStyle)),
                                DataCell(Text(isCompleted ? _formatCurrency(act) : '-', style: context.tabularNumericStyle)),
                                DataCell(
                                  Text(
                                    isCompleted ? _formatCurrency(diff) : '-',
                                    style: context.tabularNumericStyle.copyWith(
                                      color: hasOverrun ? Colors.red : (isCompleted ? Colors.green : null),
                                      fontWeight: isCompleted ? FontWeight.bold : null,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => _editTicketDialog(ticket),
                                      ),
                                      if (ticket.status == 'planned' || ticket.status == 'idea')
                                        TextButton(
                                          child: const Text('Freigeben'),
                                          onPressed: () async {
                                            final updated = MaintenanceTicketRecord(
                                              id: ticket.id,
                                              assetPropertyId: ticket.assetPropertyId,
                                              unitId: ticket.unitId,
                                              title: ticket.title,
                                              description: ticket.description,
                                              category: ticket.category,
                                              status: 'commissioned',
                                              priority: ticket.priority,
                                              reportedAt: ticket.reportedAt,
                                              dueAt: ticket.dueAt,
                                              resolvedAt: ticket.resolvedAt,
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
                                              startDate: ticket.startDate ?? DateTime.now().millisecondsSinceEpoch,
                                              endDate: ticket.endDate,
                                              assigneeType: ticket.assigneeType,
                                              assigneeName: ticket.assigneeName,
                                              building: ticket.building,
                                              area: ticket.area,
                                              technical: ticket.technical,
                                              outdoor: ticket.outdoor,
                                            );
                                            await ref.read(maintenanceRepositoryProvider).updateTicket(updated);
                                            await _reload();
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildWarrantiesTab() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final warrantyTickets = _tickets.where((w) {
      final t = w.ticket;
      final isWarrantyCategory = t.category == 'warranty';
      final isCompletedJob = (t.status == 'completed' || t.status == 'resolved' || t.status == 'closed') &&
          (t.category == 'renovation' || t.category == 'modernization' || t.category == 'repair');
      return isWarrantyCategory || isCompletedJob;
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _createTicketDialog(initialCategory: 'warranty'),
                icon: const Icon(Icons.add),
                label: const Text('Gewährleistung erfassen'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          warrantyTickets.isEmpty
              ? const NxEmptyState(
                  title: 'Keine Gewährleistungen gefunden',
                  description: 'Erfassen Sie Gewährleistungen für Ihre Maßnahmen.',
                  icon: Icons.verified_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: warrantyTickets.length,
                  itemBuilder: (context, index) {
                      final workflow = warrantyTickets[index];
                      final ticket = workflow.ticket;
                      
                      final start = ticket.startDate ?? ticket.resolvedAt ?? ticket.reportedAt;
                      final end = ticket.endDate ?? (start + (5 * 365 * 24 * 60 * 60 * 1000));
                      
                      final remainingDays = ((end - nowMs) / (24 * 60 * 60 * 1000)).ceil();
                      final isExpired = remainingDays < 0;
                      
                      NxBadgeKind badgeKind = NxBadgeKind.success;
                      if (isExpired) {
                        badgeKind = NxBadgeKind.error;
                      } else if (remainingDays <= 90) {
                        badgeKind = NxBadgeKind.warning;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.component),
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
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  NxStatusBadge(
                                    label: isExpired ? 'Abgelaufen' : '$remainingDays Tage übrig',
                                    kind: badgeKind,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editTicketDialog(ticket),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (ticket.vendorName != null) ...[
                                    const Icon(Icons.business, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Firma: ${ticket.vendorName!}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  const Icon(Icons.date_range, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Gewährleistung: ${_shortDate(start)} bis ${_shortDate(end)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.report_gmailerrorred, size: 16),
                                    label: const Text('Mangel melden'),
                                    onPressed: () => _createTicketDialog(
                                      initialCategory: 'defect',
                                      initialStatus: 'open',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ],
      ),
    );
  }

  List<MaintenanceWorkflowRecord> get _visibleTickets {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekEnd = todayStart.add(const Duration(days: 7));
    return _tickets.where((workflow) {
      final ticket = workflow.ticket;
      if (_statusFilter != 'all' && ticket.status != _statusFilter) {
        return false;
      }
      if (_unitFilter != 'all' && ticket.unitId != _unitFilter) {
        return false;
      }
      if (_priorityFilter != 'all' && ticket.priority != _priorityFilter) {
        return false;
      }
      if (_categoryFilter != 'all' && ticket.category != _categoryFilter) {
        return false;
      }
      if (_assigneeFilter == 'unassigned' &&
          (ticket.vendorName?.trim().isNotEmpty ?? false)) {
        return false;
      }
      if (_assigneeFilter != 'all' &&
          _assigneeFilter != 'unassigned' &&
          ticket.vendorName != _assigneeFilter) {
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
              !_isClosedStatus(ticket.status);
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

  List<String> get _assigneeOptions {
    final values = _tickets
        .map((workflow) => workflow.ticket.vendorName?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'all';
      _priorityFilter = 'all';
      _categoryFilter = 'all';
      _assigneeFilter = 'all';
      _dueFilter = 'all';
      _unitFilter = 'all';
      _viewMode = 'list';
    });
    _reload();
  }

  Widget _buildTicketList(List<MaintenanceWorkflowRecord> tickets) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tickets.length,
        separatorBuilder:
            (_, __) => Divider(height: 1, color: context.semanticColors.border),
        itemBuilder: (context, index) {
          final workflow = tickets[index];
          final ticket = workflow.ticket;
          return ListTile(
            selected: _selectedTicket?.ticket.id == ticket.id,
            title: Text(ticket.title),
            subtitle: Text(
              '${ticket.status} · ${ticket.priority}${ticket.dueAt == null ? '' : ' · due ${_formatDate(ticket.dueAt)}'}',
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
            onLongPress: () => _editTicketDialog(ticket),
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<MaintenanceWorkflowRecord> tickets) {
    const columns = <String>[
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in columns)
            _PropertyMaintenanceBoardColumn(
              title: status.replaceAll('_', ' '),
              tickets: tickets
                  .where((workflow) => workflow.ticket.status == status)
                  .toList(growable: false),
              selectedId: _selectedTicket?.ticket.id,
              onOpen: (workflow) {
                setState(() {
                  _selectedTicket = workflow;
                  _viewMode = 'list';
                });
              },
              onEdit: (workflow) => _editTicketDialog(workflow.ticket),
            ),
        ],
      ),
    );
  }

  String _calendarTab = 'timeline';

  Widget _buildDuePlanner(List<MaintenanceWorkflowRecord> tickets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text(
                'Terminkalender & Zeitplanung',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'timeline',
                    label: Text('Zeitplan'),
                    icon: Icon(Icons.line_axis_outlined),
                  ),
                  ButtonSegment(
                    value: 'buckets',
                    label: Text('Fälligkeit'),
                    icon: Icon(Icons.view_week_outlined),
                  ),
                ],
                selected: {_calendarTab},
                onSelectionChanged: (val) {
                  setState(() {
                    _calendarTab = val.first;
                  });
                },
              ),
            ],
          ),
        ),
        _calendarTab == 'timeline'
            ? _buildTimelineView(tickets)
            : _buildBucketsView(tickets),
      ],
    );
  }

  Widget _buildTimelineView(List<MaintenanceWorkflowRecord> tickets) {
    final datedTickets = tickets.where((w) => w.ticket.startDate != null || w.ticket.dueAt != null).toList()
      ..sort((a, b) {
        final valA = a.ticket.startDate ?? a.ticket.dueAt ?? 0;
        final valB = b.ticket.startDate ?? b.ticket.dueAt ?? 0;
        return valA.compareTo(valB);
      });

    final undatedTickets = tickets.where((w) => w.ticket.startDate == null && w.ticket.dueAt == null).toList();

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (datedTickets.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('Keine geplanten Termine vorhanden.')),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aktive Maßnahmen & Zeiträume',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  ...datedTickets.map((workflow) {
                    final ticket = workflow.ticket;
                    final start = ticket.startDate;
                    final end = ticket.endDate ?? ticket.dueAt;
                    final isRenovation = ticket.category == 'renovation';
                    
                    String rangeLabel = '';
                    double visualProgress = 0.0;
                    if (start != null && end != null) {
                      rangeLabel = '${_formatDate(start)} - ${_formatDate(end)}';
                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      if (nowMs < start) {
                        visualProgress = 0.0;
                      } else if (nowMs > end) {
                        visualProgress = 1.0;
                      } else {
                        final totalSpan = end - start;
                        visualProgress = totalSpan == 0 ? 0.5 : (nowMs - start) / totalSpan;
                      }
                    } else if (ticket.dueAt != null) {
                      rangeLabel = 'Fällig am ${_formatDate(ticket.dueAt)}';
                      visualProgress = 0.5;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: InkWell(
                        onTap: () => setState(() => _selectedTicket = workflow),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.semanticColors.border),
                            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                            color: isRenovation 
                                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15)
                                : Theme.of(context).colorScheme.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      ticket.title,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  NxStatusBadge(
                                    label: ticket.status,
                                    kind: _isClosedStatus(ticket.status) 
                                        ? NxBadgeKind.success 
                                        : NxBadgeKind.info,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_categoryLabel(ticket.category)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.date_range_outlined, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    rangeLabel,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  if (ticket.vendorName != null)
                                    Text(
                                      'Bearbeiter: ${ticket.vendorName}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: visualProgress,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                                color: isRenovation 
                                    ? Colors.orangeAccent 
                                    : Theme.of(context).colorScheme.primary,
                                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        if (undatedTickets.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ohne zeitliche Zuordnung (${undatedTickets.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...undatedTickets.map((workflow) => ListTile(
                        title: Text(workflow.ticket.title),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                        onTap: () => setState(() => _selectedTicket = workflow),
                      )),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBucketsView(List<MaintenanceWorkflowRecord> tickets) {
    final buckets = <_PropertyMaintenanceDueBucket>[
      _PropertyMaintenanceDueBucket('Überfällig', 'overdue'),
      _PropertyMaintenanceDueBucket('Heute', 'today'),
      _PropertyMaintenanceDueBucket('Diese Woche', 'week'),
      _PropertyMaintenanceDueBucket('Später', 'later'),
      _PropertyMaintenanceDueBucket('Ohne Termin', 'none'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            constraints.maxWidth < 760 ? constraints.maxWidth : 240.0;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
              for (final bucket in buckets)
                _PropertyMaintenanceDueCard(
                  width: cardWidth,
                  title: bucket.label,
                  tickets: tickets
                      .where((workflow) => _matchesDueBucket(workflow, bucket.key))
                      .toList(growable: false),
                  onOpen: (workflow) {
                    setState(() {
                      _selectedTicket = workflow;
                      _viewMode = 'list';
                    });
                  },
                  onEdit: (workflow) => _editTicketDialog(workflow.ticket),
                ),
            ],
        );
      },
    );
  }

  final _newSubtaskCtrl = TextEditingController();

  @override
  void dispose() {
    _newSubtaskCtrl.dispose();
    super.dispose();
  }

  Widget _buildTicketDetail() {
    final workflow = _selectedTicket;
    if (workflow == null) {
      return const NxCard(child: Center(child: Text('Wählen Sie ein Ticket aus')));
    }
    final ticket = workflow.ticket;
    
    final unitFuture = ticket.unitId == null
        ? Future<UnitRecord?>.value(null)
        : ref.read(rentRollRepositoryProvider).listUnitsByAsset(ticket.assetPropertyId)
            .then((units) {
                for (final u in units) {
                  if (u.id == ticket.unitId) return u;
                }
                return null;
              });

    final isRenovation = ticket.category == 'renovation';

    return NxCard(
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Text(ticket.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NxStatusBadge(
                label: ticket.status,
                kind: _isClosedStatus(ticket.status)
                    ? NxBadgeKind.success
                    : NxBadgeKind.info,
              ),
              NxStatusBadge(
                label: ticket.priority,
                kind: ticket.priority == 'urgent'
                    ? NxBadgeKind.error
                    : ticket.priority == 'high'
                    ? NxBadgeKind.warning
                    : NxBadgeKind.neutral,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<UnitRecord?>(
            future: unitFuture,
            builder: (context, snapshot) {
              final unit = snapshot.data;
              if (unit == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: Text('Einheit: ${unit.unitCode} (Typ: ${unit.unitType ?? "-"})'),
              );
            },
          ),
          Text('Ticketart: ${_categoryLabel(ticket.category)}'),
          const SizedBox(height: 4),
          Text('Gebäude: ${ticket.building ?? "-"}'),
          const SizedBox(height: 4),
          Text('Bereich: ${ticket.area ?? "-"}'),
          const SizedBox(height: 4),
          Text('Technik: ${ticket.technical ?? "-"}'),
          const SizedBox(height: 4),
          Text('Außenanlage: ${ticket.outdoor ?? "-"}'),
          
          if (ticket.damageLocation != null && ticket.damageLocation!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Schadenort: ${ticket.damageLocation}'),
          ],
          if (ticket.description != null && ticket.description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text('Beschreibung: ${ticket.description}'),
            ),
          
          const Divider(height: 24),
          Text('Terminplanung', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Startdatum: ${ticket.startDate == null ? "Nicht festgelegt" : _formatDate(ticket.startDate)}'),
          const SizedBox(height: 4),
          Text('Enddatum: ${ticket.endDate == null ? "Nicht festgelegt" : _formatDate(ticket.endDate)}'),
          const SizedBox(height: 4),
          Text('Fälligkeit: ${ticket.dueAt == null ? "Nicht festgelegt" : _formatDate(ticket.dueAt)}'),
          
          const Divider(height: 24),
          Text('Bearbeiter details', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Bearbeitergruppe: ${ticket.assigneeType ?? "-"}'),
          const SizedBox(height: 4),
          Text('Name des Bearbeiters: ${ticket.assigneeName ?? "-"}'),
          const SizedBox(height: 4),
          Text('Zugeordnete Firma: ${ticket.vendorName ?? "-"}'),
          const SizedBox(height: 4),
          Text('Versicherung: ${_insuranceLabel(ticket)}'),

          const Divider(height: 24),
          Text('Budget & Kosten', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Budget / Schätzung: ${ticket.costEstimate == null ? "N/A" : _formatCurrency(ticket.costEstimate!)}'),
          const SizedBox(height: 4),
          Text('Tatsächliche Kosten: ${ticket.costActual == null ? "N/A" : _formatCurrency(ticket.costActual!)}'),
          if (ticket.costEstimate != null && ticket.costActual != null) ...[
            const SizedBox(height: 4),
            Builder(builder: (context) {
              final dev = ticket.costActual! - ticket.costEstimate!;
              return Text(
                'Abweichung: ${_formatCurrency(dev)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: dev > 0 ? Colors.red : Colors.green,
                ),
              );
            }),
          ],

          FutureBuilder<List<TaskRecord>>(
            future: ref.read(tasksRepositoryProvider).listTasks(
              entityType: 'maintenance_ticket',
              entityId: ticket.id,
            ),
            builder: (context, taskSnapshot) {
              final tasks = taskSnapshot.data ?? [];
              final total = tasks.length;
              final completed = tasks.where((t) => t.status == 'done').length;
              final percent = total == 0 ? 0.0 : completed / total;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text(
                        isRenovation ? 'Sanierungsfortschritt: ${(percent * 100).toStringAsFixed(0)}%' : 'Fortschritt: ${(percent * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 12),
                  Text('Checkliste / Aufgaben (${completed}/${total})', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (tasks.isEmpty)
                    const Text('Keine Aufgaben angelegt.')
                  else
                    ...tasks.map((task) => CheckboxListTile(
                      value: task.status == 'done',
                      onChanged: (val) async {
                        final updatedTask = TaskRecord(
                          id: task.id,
                          entityType: task.entityType,
                          entityId: task.entityId,
                          title: task.title,
                          description: task.description,
                          category: task.category,
                          assignedTo: task.assignedTo,
                          estimatedCost: task.estimatedCost,
                          status: (val ?? false) ? 'done' : 'todo',
                          priority: task.priority,
                          dueAt: task.dueAt,
                          createdAt: task.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                          createdBy: task.createdBy,
                        );
                        await ref.read(tasksRepositoryProvider).updateTask(updatedTask);
                        setState(() {});
                      },
                      title: Text(task.title),
                      subtitle: task.description != null ? Text(task.description!) : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newSubtaskCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Neue Teilaufgabe...',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final text = _newSubtaskCtrl.text.trim();
                          if (text.isEmpty) return;
                          await ref.read(tasksRepositoryProvider).createTask(
                            entityType: 'maintenance_ticket',
                            entityId: ticket.id,
                            title: text,
                            priority: ticket.priority,
                            dueAt: ticket.dueAt,
                          );
                          _newSubtaskCtrl.clear();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              );
            }
          ),

          FutureBuilder<List<DocumentRecord>>(
            future: ref.read(documentsRepositoryProvider).listDocuments(
              entityType: 'maintenance_ticket',
              entityId: ticket.id,
            ),
            builder: (context, docSnapshot) {
              final docs = docSnapshot.data ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text('Dokumente & Bilder (${docs.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Verknüpfen'),
                        onPressed: () => _linkDocumentDialog(ticket),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (docs.isEmpty)
                    const Text('Keine Dokumente verknüpft.')
                  else
                    Column(
                      children: docs.map((doc) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          (doc.fileName.toLowerCase().endsWith('.png') ||
                           doc.fileName.toLowerCase().endsWith('.jpg') ||
                           doc.fileName.toLowerCase().endsWith('.jpeg'))
                              ? Icons.image
                              : Icons.picture_as_pdf,
                        ),
                        title: Text(doc.fileName),
                        subtitle: Text(doc.filePath, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off),
                          onPressed: () async {
                            final updatedDoc = DocumentRecord(
                              id: doc.id,
                              entityType: '',
                              entityId: '',
                              typeId: doc.typeId,
                              fileName: doc.fileName,
                              filePath: doc.filePath,
                              sizeBytes: doc.sizeBytes,
                              sha256: doc.sha256,
                              mimeType: doc.mimeType,
                              createdBy: doc.createdBy,
                              createdAt: doc.createdAt,
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            );
                            await ref.read(documentsRepositoryProvider).updateDocument(updatedDoc);
                            setState(() {});
                          },
                        ),
                      )).toList(),
                    ),
                ],
              );
            }
          ),

          const Divider(height: 24),
          FutureBuilder<List<MaintenanceTicketHistoryRecord>>(
            future: ref
                .read(maintenanceRepositoryProvider)
                .listTicketHistory(ticket.id),
            builder: (context, snapshot) {
              final history = snapshot.data ?? const [];
              if (history.isEmpty) {
                return const Text('Historie: Noch keine Einträge.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Historie',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...history.take(4).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_formatDate(entry.createdAt)} · ${entry.action}${entry.note == null ? '' : ' · ${entry.note}'}',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _editTicketDialog(ticket),
                child: const Text('Bearbeiten'),
              ),
              OutlinedButton(
                onPressed: () => _changeStatusDialog(ticket),
                child: const Text('Update Status'),
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

  Future<void> _linkDocumentDialog(MaintenanceTicketRecord ticket) async {
    final docs = await ref.read(documentsRepositoryProvider).listDocuments(
      entityType: 'property',
      entityId: ticket.assetPropertyId,
    );
    if (!mounted) return;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Dokumente beim Objekt vorhanden, die verknüpft werden könnten.')),
      );
      return;
    }
    
    DocumentRecord? selectedDoc = docs.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dokument verknüpfen'),
          content: DropdownButtonFormField<DocumentRecord>(
            value: selectedDoc,
            items: docs.map((doc) => DropdownMenuItem(value: doc, child: Text(doc.fileName))).toList(),
            onChanged: (val) {
              setDialogState(() => selectedDoc = val);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Verknüpfen')),
          ],
        ),
      ),
    );
    
    if (ok == true && selectedDoc != null) {
      final updated = DocumentRecord(
        id: selectedDoc!.id,
        entityType: 'maintenance_ticket',
        entityId: ticket.id,
        typeId: selectedDoc!.typeId,
        fileName: selectedDoc!.fileName,
        filePath: selectedDoc!.filePath,
        sizeBytes: selectedDoc!.sizeBytes,
        sha256: selectedDoc!.sha256,
        mimeType: selectedDoc!.mimeType,
        createdBy: selectedDoc!.createdBy,
        createdAt: selectedDoc!.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(documentsRepositoryProvider).updateDocument(updated);
      setState(() {});
    }
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
                        value: 'planned',
                        child: Text('planned'),
                      ),
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
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('completed'),
                      ),
                      DropdownMenuItem(
                        value: 'billed',
                        child: Text('billed'),
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
                          category: ticket.category,
                          status: status,
                          priority: ticket.priority,
                          reportedAt: ticket.reportedAt,
                          dueAt: ticket.dueAt,
                          resolvedAt:
                              _isClosedStatus(status)
                                  ? DateTime.now().millisecondsSinceEpoch
                                  : ticket.resolvedAt,
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
                          startDate: ticket.startDate,
                          endDate: ticket.endDate,
                          assigneeType: ticket.assigneeType,
                          assigneeName: ticket.assigneeName,
                          building: ticket.building,
                          area: ticket.area,
                          technical: ticket.technical,
                          outdoor: ticket.outdoor,
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

  Future<void> _reload() async {
    final properties = await ref.read(propertyRepositoryProvider).list();
    if (!mounted) return;
    final prop = properties.any((p) => p.id == widget.propertyId)
        ? properties.firstWhere((p) => p.id == widget.propertyId)
        : null;
    final tickets = await ref
        .read(maintenanceRepositoryProvider)
        .listWorkflowTickets(
          assetPropertyId: widget.propertyId,
        );
    if (!mounted) return;
    final units = await ref
        .read(rentRollRepositoryProvider)
        .listUnitsByAsset(widget.propertyId);
    if (!mounted) return;
    
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
      _property = prop;
      _tickets = tickets;
      _units = units;
      _selectedTicket =
          selectedTicket ?? (tickets.isEmpty ? null : tickets.first);
    });
  }

  Future<void> _createTicketDialog({String? initialCategory, String? initialStatus}) async {
    final titleCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final costEstimateCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    final damageLocationCtrl = TextEditingController();
    final insuranceClaimCtrl = TextEditingController();

    // V37 fields controllers
    final startDateCtrl = TextEditingController();
    final endDateCtrl = TextEditingController();
    final assigneeNameCtrl = TextEditingController();
    final buildingCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final technicalCtrl = TextEditingController();
    final outdoorCtrl = TextEditingController();

    String category = initialCategory ?? 'damage';
    String status = initialStatus ?? 'open';
    String priority = 'normal';
    String insuranceStatus = 'reported';
    bool createTask = true;
    bool insuranceCase = false;
    DateTime? dueDate;

    // V37 fields states
    DateTime? startDate;
    DateTime? endDate;
    String? assigneeType;
    List<UnitRecord> dialogUnits = [];
    String? selectedUnitId;
    bool isLoadingUnits = false;

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) {
                  if (dialogUnits.isEmpty && !isLoadingUnits) {
                    Future.microtask(() async {
                      setDialogState(() => isLoadingUnits = true);
                      try {
                        final units = await ref.read(rentRollRepositoryProvider).listUnitsByAsset(widget.propertyId);
                        setDialogState(() {
                          dialogUnits = units;
                          isLoadingUnits = false;
                        });
                      } catch (_) {
                        setDialogState(() => isLoadingUnits = false);
                      }
                    });
                  }

                  return AlertDialog(
                    title: const Text('Neues Maintenance Ticket'),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Allgemeine Daten', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: selectedUnitId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Keine Einheit (Gesamtobjekt)')),
                                ...dialogUnits.map(
                                  (unit) => DropdownMenuItem(
                                    value: unit.id,
                                    child: Text(unit.unitCode),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() => selectedUnitId = value);
                              },
                              decoration: const InputDecoration(labelText: 'Einheit'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: titleCtrl,
                              decoration: const InputDecoration(labelText: 'Titel *'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: descCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Beschreibung',
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: category,
                              items: const [
                                DropdownMenuItem(value: 'damage', child: Text('Schaden')),
                                DropdownMenuItem(value: 'defect', child: Text('Mangel')),
                                DropdownMenuItem(value: 'repair', child: Text('Reparatur')),
                                DropdownMenuItem(value: 'maintenance', child: Text('Wartung')),
                                DropdownMenuItem(value: 'renovation', child: Text('Sanierung')),
                                DropdownMenuItem(value: 'modernization', child: Text('Renovierung')),
                                DropdownMenuItem(value: 'minor_repair', child: Text('Kleinreparatur')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => category = value);
                                }
                              },
                              decoration: const InputDecoration(labelText: 'Kategorie'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: priority,
                              items: const [
                                DropdownMenuItem(value: 'low', child: Text('Niedrig (low)')),
                                DropdownMenuItem(value: 'normal', child: Text('Normal (normal)')),
                                DropdownMenuItem(value: 'high', child: Text('Hoch (high)')),
                                DropdownMenuItem(value: 'urgent', child: Text('Dringend (urgent)')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => priority = value);
                                }
                              },
                              decoration: const InputDecoration(labelText: 'Priorität'),
                            ),
                            const Divider(height: 24),
                            Text('Zeitplanung', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: startDateCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Startdatum',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (startDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            startDate = null;
                                            startDateCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    startDate = picked;
                                    startDateCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: endDateCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Enddatum',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (endDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            endDate = null;
                                            endDateCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: endDate ?? (startDate ?? DateTime.now()),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    endDate = picked;
                                    endDateCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: dueCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Fälligkeitsdatum',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (dueDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            dueDate = null;
                                            dueCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: dueDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    dueDate = picked;
                                    dueCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const Divider(height: 24),
                            Text('Zuweisung & Bearbeiter', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: assigneeType,
                              items: const [
                                DropdownMenuItem(value: null, child: Text('Keine Bearbeitergruppe')),
                                DropdownMenuItem(value: 'Hausmeister', child: Text('Hausmeister')),
                                DropdownMenuItem(value: 'Bauleiter', child: Text('Bauleiter')),
                                DropdownMenuItem(value: 'Bauarbeiter', child: Text('Bauarbeiter')),
                                DropdownMenuItem(value: 'Housekeeping', child: Text('Housekeeping')),
                                DropdownMenuItem(value: 'Externer Dienstleister', child: Text('Externer Dienstleister')),
                                DropdownMenuItem(value: 'Mitarbeiter', child: Text('Mitarbeiter')),
                                DropdownMenuItem(value: 'Dienstleister', child: Text('Dienstleister')),
                                DropdownMenuItem(value: 'Externe Firmen', child: Text('Externe Firmen')),
                              ],
                              onChanged: (value) {
                                setDialogState(() => assigneeType = value);
                              },
                              decoration: const InputDecoration(labelText: 'Bearbeitergruppe'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: assigneeNameCtrl,
                              decoration: const InputDecoration(labelText: 'Name des Bearbeiters'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: vendorCtrl,
                              decoration: const InputDecoration(labelText: 'Zugeordnete Firma (Dienstleister)'),
                            ),
                            const Divider(height: 24),
                            Text('Ort / Bereich', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: buildingCtrl,
                              decoration: const InputDecoration(labelText: 'Gebäude'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: areaCtrl,
                              decoration: const InputDecoration(labelText: 'Bereich'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: technicalCtrl,
                              decoration: const InputDecoration(labelText: 'Technik (z.B. Heizung)'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: outdoorCtrl,
                              decoration: const InputDecoration(labelText: 'Außenanlage'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: damageLocationCtrl,
                              decoration: const InputDecoration(labelText: 'Genauer Schadenort'),
                            ),
                            const Divider(height: 24),
                            Text('Kosten & Versicherung', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: costEstimateCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Kostenschätzung (€)'),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              value: insuranceCase,
                              onChanged: (value) => setDialogState(() => insuranceCase = value),
                              title: const Text('Versicherungsfall'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (insuranceCase) ...[
                              DropdownButtonFormField<String>(
                                value: insuranceStatus,
                                items: const [
                                  DropdownMenuItem(value: 'reported', child: Text('Gemeldet')),
                                  DropdownMenuItem(value: 'in_review', child: Text('In Prüfung')),
                                  DropdownMenuItem(value: 'approved', child: Text('Freigegeben')),
                                  DropdownMenuItem(value: 'declined', child: Text('Abgelehnt')),
                                  DropdownMenuItem(value: 'settled', child: Text('Reguliert')),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => insuranceStatus = value);
                                  }
                                },
                                decoration: const InputDecoration(labelText: 'Versicherungsstatus'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: insuranceClaimCtrl,
                                decoration: const InputDecoration(labelText: 'Schadennummer'),
                              ),
                            ],
                            const Divider(height: 24),
                            SwitchListTile(
                              value: createTask,
                              onChanged: (value) => setDialogState(() => createTask = value),
                              title: const Text('Verknüpfte Aufgabe erstellen'),
                              contentPadding: EdgeInsets.zero,
                            ),
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
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            return;
                          }
                          await ref
                              .read(maintenanceRepositoryProvider)
                              .createTicket(
                                assetPropertyId: widget.propertyId,
                                unitId: selectedUnitId,
                                title: title,
                                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                                category: category,
                                status: status,
                                priority: priority,
                                dueAt: dueDate?.millisecondsSinceEpoch,
                                costEstimate: costEstimateCtrl.text.trim().isEmpty
                                    ? null
                                    : double.tryParse(costEstimateCtrl.text.trim()),
                                vendorName: vendorCtrl.text.trim().isEmpty ? null : vendorCtrl.text.trim(),
                                damageLocation: damageLocationCtrl.text.trim().isEmpty ? null : damageLocationCtrl.text.trim(),
                                insuranceCase: insuranceCase,
                                insuranceStatus: insuranceCase ? insuranceStatus : null,
                                insuranceClaimNumber: insuranceClaimCtrl.text.trim().isEmpty ? null : insuranceClaimCtrl.text.trim(),
                                createTask: createTask,
                                startDate: startDate?.millisecondsSinceEpoch,
                                endDate: endDate?.millisecondsSinceEpoch,
                                assigneeType: assigneeType,
                                assigneeName: assigneeNameCtrl.text.trim().isEmpty ? null : assigneeNameCtrl.text.trim(),
                                building: buildingCtrl.text.trim().isEmpty ? null : buildingCtrl.text.trim(),
                                area: areaCtrl.text.trim().isEmpty ? null : areaCtrl.text.trim(),
                                technical: technicalCtrl.text.trim().isEmpty ? null : technicalCtrl.text.trim(),
                                outdoor: outdoorCtrl.text.trim().isEmpty ? null : outdoorCtrl.text.trim(),
                              );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          await _reload();
                        },
                        child: const Text('Erstellen'),
                      ),
                    ],
                  );
                },
          ),
    );

    titleCtrl.dispose();
    dueCtrl.dispose();
    descCtrl.dispose();
    costEstimateCtrl.dispose();
    vendorCtrl.dispose();
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
    startDateCtrl.dispose();
    endDateCtrl.dispose();
    assigneeNameCtrl.dispose();
    buildingCtrl.dispose();
    areaCtrl.dispose();
    technicalCtrl.dispose();
    outdoorCtrl.dispose();
  }

  Future<void> _editTicketDialog(MaintenanceTicketRecord ticket) async {
    final titleCtrl = TextEditingController(text: ticket.title);
    final descCtrl = TextEditingController(text: ticket.description ?? '');
    final dueCtrl = TextEditingController(text: _formatDate(ticket.dueAt));
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

    // V37 controllers
    final startDateCtrl = TextEditingController(text: _formatDate(ticket.startDate));
    final endDateCtrl = TextEditingController(text: _formatDate(ticket.endDate));
    final assigneeNameCtrl = TextEditingController(text: ticket.assigneeName ?? '');
    final buildingCtrl = TextEditingController(text: ticket.building ?? '');
    final areaCtrl = TextEditingController(text: ticket.area ?? '');
    final technicalCtrl = TextEditingController(text: ticket.technical ?? '');
    final outdoorCtrl = TextEditingController(text: ticket.outdoor ?? '');

    var category = ticket.category;
    var priority = ticket.priority;
    var status = ticket.status;
    var insuranceStatus = ticket.insuranceStatus ?? 'reported';
    var insuranceCase = ticket.insuranceCase;

    DateTime? dueDate =
        ticket.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ticket.dueAt!);
    DateTime? startDate =
        ticket.startDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ticket.startDate!);
    DateTime? endDate =
        ticket.endDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ticket.endDate!);
    String? assigneeType = ticket.assigneeType;
    List<UnitRecord> dialogUnits = [];
    String? selectedUnitId = ticket.unitId;
    bool isLoadingUnits = false;

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) {
                  if (dialogUnits.isEmpty && !isLoadingUnits) {
                    Future.microtask(() async {
                      setDialogState(() => isLoadingUnits = true);
                      try {
                        final units = await ref.read(rentRollRepositoryProvider).listUnitsByAsset(ticket.assetPropertyId);
                        setDialogState(() {
                          dialogUnits = units;
                          isLoadingUnits = false;
                        });
                      } catch (_) {
                        setDialogState(() => isLoadingUnits = false);
                      }
                    });
                  }

                  return AlertDialog(
                    title: const Text('Ticket bearbeiten'),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Allgemeine Daten', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: selectedUnitId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Keine Einheit (Gesamtobjekt)')),
                                ...dialogUnits.map(
                                  (unit) => DropdownMenuItem(
                                    value: unit.id,
                                    child: Text(unit.unitCode),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() => selectedUnitId = value);
                              },
                              decoration: const InputDecoration(labelText: 'Einheit'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: titleCtrl,
                              decoration: const InputDecoration(labelText: 'Titel *'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: descCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Beschreibung',
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: status,
                              items: _statusItems(status),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => status = value);
                                }
                              },
                              decoration: const InputDecoration(labelText: 'Status'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: category,
                              items: _categoryItems(category),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => category = value);
                                }
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
                                if (value != null) {
                                  setDialogState(() => priority = value);
                                }
                              },
                              decoration: const InputDecoration(labelText: 'Priorität'),
                            ),
                            const Divider(height: 24),
                            Text('Zeitplanung', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: startDateCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Startdatum',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (startDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            startDate = null;
                                            startDateCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    startDate = picked;
                                    startDateCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: endDateCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Enddatum',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (endDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            endDate = null;
                                            endDateCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: endDate ?? (startDate ?? DateTime.now()),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    endDate = picked;
                                    endDateCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: dueCtrl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Fälligkeit',
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (dueDate != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          setDialogState(() {
                                            dueDate = null;
                                            dueCtrl.clear();
                                          });
                                        },
                                      ),
                                    const Icon(Icons.calendar_today, size: 18),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: dueDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    dueDate = picked;
                                    dueCtrl.text = _formatDate(picked.millisecondsSinceEpoch);
                                  });
                                }
                              },
                            ),
                            const Divider(height: 24),
                            Text('Zuweisung & Bearbeiter', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              value: assigneeType,
                              items: const [
                                DropdownMenuItem(value: null, child: Text('Keine Bearbeitergruppe')),
                                DropdownMenuItem(value: 'Hausmeister', child: Text('Hausmeister')),
                                DropdownMenuItem(value: 'Bauleiter', child: Text('Bauleiter')),
                                DropdownMenuItem(value: 'Bauarbeiter', child: Text('Bauarbeiter')),
                                DropdownMenuItem(value: 'Housekeeping', child: Text('Housekeeping')),
                                DropdownMenuItem(value: 'Externer Dienstleister', child: Text('Externer Dienstleister')),
                                DropdownMenuItem(value: 'Mitarbeiter', child: Text('Mitarbeiter')),
                                DropdownMenuItem(value: 'Dienstleister', child: Text('Dienstleister')),
                                DropdownMenuItem(value: 'Externe Firmen', child: Text('Externe Firmen')),
                              ],
                              onChanged: (value) {
                                setDialogState(() => assigneeType = value);
                              },
                              decoration: const InputDecoration(labelText: 'Bearbeitergruppe'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: assigneeNameCtrl,
                              decoration: const InputDecoration(labelText: 'Name des Bearbeiters'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: vendorCtrl,
                              decoration: const InputDecoration(labelText: 'Zugeordnete Firma (Dienstleister)'),
                            ),
                            const Divider(height: 24),
                            Text('Ort / Bereich', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: buildingCtrl,
                              decoration: const InputDecoration(labelText: 'Gebäude'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: areaCtrl,
                              decoration: const InputDecoration(labelText: 'Bereich'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: technicalCtrl,
                              decoration: const InputDecoration(labelText: 'Technik (z.B. Heizung)'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: outdoorCtrl,
                              decoration: const InputDecoration(labelText: 'Außenanlage'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: damageLocationCtrl,
                              decoration: const InputDecoration(labelText: 'Genauer Schadenort'),
                            ),
                            const Divider(height: 24),
                            Text('Kosten & Versicherung', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: costEstimateCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Kostenschätzung (€)'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: costActualCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Ist-Kosten (€)'),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              value: insuranceCase,
                              onChanged: (value) => setDialogState(() => insuranceCase = value),
                              title: const Text('Versicherungsfall'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (insuranceCase) ...[
                              DropdownButtonFormField<String>(
                                value: insuranceStatus,
                                items: const [
                                  DropdownMenuItem(value: 'reported', child: Text('Gemeldet')),
                                  DropdownMenuItem(value: 'in_review', child: Text('In Prüfung')),
                                  DropdownMenuItem(value: 'approved', child: Text('Freigegeben')),
                                  DropdownMenuItem(value: 'declined', child: Text('Abgelehnt')),
                                  DropdownMenuItem(value: 'settled', child: Text('Reguliert')),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => insuranceStatus = value);
                                  }
                                },
                                decoration: const InputDecoration(labelText: 'Versicherungsstatus'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: insuranceClaimCtrl,
                                decoration: const InputDecoration(labelText: 'Schadennummer'),
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
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            return;
                          }
                          final updated = MaintenanceTicketRecord(
                            id: ticket.id,
                            assetPropertyId: ticket.assetPropertyId,
                            unitId: selectedUnitId,
                            title: title,
                            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            category: category,
                            status: status,
                            priority: priority,
                            reportedAt: ticket.reportedAt,
                            dueAt: dueDate?.millisecondsSinceEpoch,
                            resolvedAt: _isClosedStatus(status)
                                ? (ticket.resolvedAt ?? DateTime.now().millisecondsSinceEpoch)
                                : null,
                            costEstimate: _parseMoney(costEstimateCtrl.text),
                            costActual: _parseMoney(costActualCtrl.text),
                            vendorName: vendorCtrl.text.trim().isEmpty ? null : vendorCtrl.text.trim(),
                            documentId: ticket.documentId,
                            damageLocation: damageLocationCtrl.text.trim().isEmpty ? null : damageLocationCtrl.text.trim(),
                            insuranceCase: insuranceCase,
                            insuranceStatus: insuranceCase ? insuranceStatus : null,
                            insuranceClaimNumber: insuranceClaimCtrl.text.trim().isEmpty ? null : insuranceClaimCtrl.text.trim(),
                            createdAt: ticket.createdAt,
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                            startDate: startDate?.millisecondsSinceEpoch,
                            endDate: endDate?.millisecondsSinceEpoch,
                            assigneeType: assigneeType,
                            assigneeName: assigneeNameCtrl.text.trim().isEmpty ? null : assigneeNameCtrl.text.trim(),
                            building: buildingCtrl.text.trim().isEmpty ? null : buildingCtrl.text.trim(),
                            area: areaCtrl.text.trim().isEmpty ? null : areaCtrl.text.trim(),
                            technical: technicalCtrl.text.trim().isEmpty ? null : technicalCtrl.text.trim(),
                            outdoor: outdoorCtrl.text.trim().isEmpty ? null : outdoorCtrl.text.trim(),
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
                  );
                },
          ),
    );

    titleCtrl.dispose();
    descCtrl.dispose();
    dueCtrl.dispose();
    costEstimateCtrl.dispose();
    costActualCtrl.dispose();
    vendorCtrl.dispose();
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
    startDateCtrl.dispose();
    endDateCtrl.dispose();
    assigneeNameCtrl.dispose();
    buildingCtrl.dispose();
    areaCtrl.dispose();
    technicalCtrl.dispose();
    outdoorCtrl.dispose();
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
      _status = 'Es wurden $created Instandhaltungs-Benachrichtigungen erstellt.';
    });
  }

  bool _matchesDueBucket(MaintenanceWorkflowRecord workflow, String bucket) {
    final ticket = workflow.ticket;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekEnd = todayStart.add(const Duration(days: 7));
    final dueAt = ticket.dueAt;
    if (bucket == 'none') {
      return dueAt == null;
    }
    if (dueAt == null) {
      return false;
    }
    if (bucket == 'overdue') {
      return dueAt < todayStart.millisecondsSinceEpoch &&
          !_isClosedStatus(ticket.status);
    }
    if (bucket == 'today') {
      return dueAt >= todayStart.millisecondsSinceEpoch &&
          dueAt < todayEnd.millisecondsSinceEpoch;
    }
    if (bucket == 'week') {
      return dueAt >= todayStart.millisecondsSinceEpoch &&
          dueAt < weekEnd.millisecondsSinceEpoch;
    }
    if (bucket == 'later') {
      return dueAt >= weekEnd.millisecondsSinceEpoch;
    }
    return false;
  }

  double? _parseMoney(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return normalized.isEmpty ? null : double.tryParse(normalized);
  }

  List<DropdownMenuItem<String>> _statusItems(String current) {
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

  List<DropdownMenuItem<String>> _categoryItems(String current) {
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
        DropdownMenuItem(value: current, child: Text(_categoryLabel(current))),
      for (final value in values)
        DropdownMenuItem(value: value, child: Text(_categoryLabel(value))),
    ];
  }

  String _formatDate(int? value) {
    if (value == null) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(
      value,
    ).toIso8601String().substring(0, 10);
  }

  String _insuranceLabel(MaintenanceTicketRecord ticket) {
    if (!ticket.insuranceCase) {
      return 'Kein Versicherungsfall';
    }
    final claim =
        ticket.insuranceClaimNumber == null ||
                ticket.insuranceClaimNumber!.trim().isEmpty
            ? ''
            : ' · ${ticket.insuranceClaimNumber}';
    return '${ticket.insuranceStatus ?? 'offen'}$claim';
  }

  bool _isClosedStatus(String status) {
    return const {'completed', 'billed', 'resolved', 'closed'}.contains(status);
  }

  String _categoryLabel(String value) {
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

  // =============================================================================
  // TAB 5: BAUTEILZUSTAND
  // =============================================================================
  static const List<({String id, String label, IconData icon})> _bauteilComponents = [
    (id: 'dach',         label: 'Dach',          icon: Icons.roofing_outlined),
    (id: 'fassade',      label: 'Fassade',        icon: Icons.home_outlined),
    (id: 'fenster',      label: 'Fenster',        icon: Icons.window_outlined),
    (id: 'heizung',      label: 'Heizung',        icon: Icons.thermostat_outlined),
    (id: 'elektrik',     label: 'Elektrik',       icon: Icons.electrical_services_outlined),
    (id: 'sanitaer',     label: 'Sanitär',        icon: Icons.plumbing_outlined),
    (id: 'boeden',       label: 'Böden',          icon: Icons.layers_outlined),
    (id: 'tueren',       label: 'Türen',          icon: Icons.door_front_door_outlined),
    (id: 'treppenhaus',  label: 'Treppenhaus',    icon: Icons.stairs_outlined),
    (id: 'aussenanlage', label: 'Außenanlage',    icon: Icons.park_outlined),
    (id: 'brandschutz',  label: 'Brandschutz',    icon: Icons.fire_extinguisher_outlined),
    (id: 'aufzug',       label: 'Aufzug',         icon: Icons.elevator_outlined),
    (id: 'keller',       label: 'Keller',         icon: Icons.foundation_outlined),
  ];

  _BauteilStatusEntry _getBauteil(String id, String label) {
    return _bauteilStatus.putIfAbsent(id, () => _BauteilStatusEntry(id: id, label: label));
  }

  Widget _buildBauteilzustandTab() {
    // Summary counts
    int gut = 0, prufen = 0, kritisch = 0;
    for (final comp in _bauteilComponents) {
      final entry = _getBauteil(comp.id, comp.label);
      switch (entry.status) {
        case 'kritisch': kritisch++; break;
        case 'prufen':   prufen++; break;
        default:         gut++; break;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Summary header ───────────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _bauteilSummaryCard(
                label: 'Gut',
                count: gut,
                color: const Color(0xFF16A34A),
                bgColor: const Color(0xFFDCFCE7),
                icon: Icons.check_circle_outline,
              ),
              _bauteilSummaryCard(
                label: 'Zu prüfen',
                count: prufen,
                color: const Color(0xFFD97706),
                bgColor: const Color(0xFFFEF9C3),
                icon: Icons.warning_amber_outlined,
              ),
              _bauteilSummaryCard(
                label: 'Kritisch',
                count: kritisch,
                color: const Color(0xFFDC2626),
                bgColor: const Color(0xFFFEE2E2),
                icon: Icons.error_outline,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          // ─── Component matrix ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 980 ? 2 : 1;
              final cardWidth = cols == 2
                  ? (constraints.maxWidth - AppSpacing.component) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: _bauteilComponents.map((comp) {
                  final entry = _getBauteil(comp.id, comp.label);
                  final openTickets = _tickets.where((w) =>
                    !_closedMaintenanceStatus(w.ticket.status) &&
                    (w.ticket.area == comp.id ||
                     w.ticket.building == comp.id ||
                     w.ticket.technical == comp.id ||
                     w.ticket.outdoor == comp.id),
                  ).length;
                  return SizedBox(
                    width: cardWidth,
                    child: _bauteilCard(
                      context: context,
                      comp: comp,
                      entry: entry,
                      openTickets: openTickets,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bauteilSummaryCard({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bauteilCard({
    required BuildContext context,
    required ({String id, String label, IconData icon}) comp,
    required _BauteilStatusEntry entry,
    required int openTickets,
  }) {
    final now = DateTime.now();
    String lastServiceText = 'Nicht erfasst';
    String nextServiceText = 'Nicht geplant';
    bool overdueService = false;

    if (entry.lastService != null) {
      final diff = now.difference(entry.lastService!).inDays;
      lastServiceText = diff == 0
          ? 'Heute'
          : 'Vor ${diff} Tagen (${entry.lastService!.year}-${entry.lastService!.month.toString().padLeft(2, '0')}-${entry.lastService!.day.toString().padLeft(2, '0')})';
    }
    if (entry.nextService != null) {
      final diff = entry.nextService!.difference(now).inDays;
      if (diff < 0) {
        nextServiceText = 'Überfällig (${(-diff)} Tage)';
        overdueService = true;
      } else if (diff == 0) {
        nextServiceText = 'Heute';
      } else {
        nextServiceText = 'In ${diff} Tagen (${entry.nextService!.year}-${entry.nextService!.month.toString().padLeft(2, '0')}-${entry.nextService!.day.toString().padLeft(2, '0')})';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: entry.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                  ),
                  child: Icon(comp.icon, color: entry.statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comp.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(entry.statusIcon, color: entry.statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            entry.statusLabel,
                            style: TextStyle(
                              color: entry.statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tickets verknüpfen',
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: () => _showLinkTicketsDialog(comp),
                ),
                IconButton(
                  tooltip: 'Status bearbeiten',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editBauteilDialog(comp, entry),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _bauteilInfoRow(
                    context: context,
                    icon: Icons.history,
                    label: 'Letzte Wartung',
                    value: lastServiceText,
                    valueColor: null,
                  ),
                ),
                Expanded(
                  child: _bauteilInfoRow(
                    context: context,
                    icon: Icons.event_outlined,
                    label: 'Nächste Wartung',
                    value: nextServiceText,
                    valueColor: overdueService ? const Color(0xFFDC2626) : null,
                  ),
                ),
              ],
            ),
            if (openTickets > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.build_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(
                    '$openTickets offene${openTickets == 1 ? 's Ticket' : ' Tickets'}',
                    style: const TextStyle(
                      color: Color(0xFFD97706),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bauteilInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: valueColor,
            fontWeight: valueColor != null ? FontWeight.w600 : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  void _showLinkTicketsDialog(({String id, String label, IconData icon}) comp) {
    final relevantWorkflows = _tickets.where((w) {
      final isLinked = w.ticket.area == comp.id ||
                       w.ticket.building == comp.id ||
                       w.ticket.technical == comp.id ||
                       w.ticket.outdoor == comp.id;
      final isActive = !_closedMaintenanceStatus(w.ticket.status);
      return isLinked || isActive;
    }).toList();

    if (relevantWorkflows.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${comp.label}: Tickets verknüpfen'),
          content: const Text('Keine aktiven Tickets für diese Immobilie vorhanden.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }

    final Set<String> selectedTicketIds = relevantWorkflows
        .where((w) => w.ticket.area == comp.id ||
                      w.ticket.building == comp.id ||
                      w.ticket.technical == comp.id ||
                      w.ticket.outdoor == comp.id)
        .map((w) => w.ticket.id)
        .toSet();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${comp.label}: Tickets verknüpfen'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: relevantWorkflows.map((w) {
                  final ticket = w.ticket;
                  final isChecked = selectedTicketIds.contains(ticket.id);
                  return CheckboxListTile(
                    title: Text(ticket.title),
                    subtitle: Text(
                      'Status: ${ticket.status} · Priorität: ${ticket.priority}',
                    ),
                    value: isChecked,
                    onChanged: (bool? val) {
                      setDialogState(() {
                        if (val == true) {
                          selectedTicketIds.add(ticket.id);
                        } else {
                          selectedTicketIds.remove(ticket.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                for (final w in relevantWorkflows) {
                  final ticket = w.ticket;
                  final wasChecked = ticket.area == comp.id ||
                                     ticket.building == comp.id ||
                                     ticket.technical == comp.id ||
                                     ticket.outdoor == comp.id;
                  final isChecked = selectedTicketIds.contains(ticket.id);
                  if (wasChecked != isChecked) {
                    final updated = MaintenanceTicketRecord(
                      id: ticket.id,
                      assetPropertyId: ticket.assetPropertyId,
                      unitId: ticket.unitId,
                      title: ticket.title,
                      description: ticket.description,
                      category: ticket.category,
                      status: ticket.status,
                      priority: ticket.priority,
                      reportedAt: ticket.reportedAt,
                      dueAt: ticket.dueAt,
                      resolvedAt: ticket.resolvedAt,
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
                      startDate: ticket.startDate,
                      endDate: ticket.endDate,
                      assigneeType: ticket.assigneeType,
                      assigneeName: ticket.assigneeName,
                      building: isChecked ? comp.id : null,
                      area: isChecked ? comp.id : null,
                      technical: isChecked ? comp.id : null,
                      outdoor: isChecked ? comp.id : null,
                    );
                    await ref
                        .read(maintenanceRepositoryProvider)
                        .updateTicket(updated);
                  }
                }
                await _reload();
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _editBauteilDialog(
    ({String id, String label, IconData icon}) comp,
    _BauteilStatusEntry entry,
  ) {
    String selectedStatus = entry.status;
    final lastCtrl = TextEditingController(
      text: entry.lastService != null
          ? '${entry.lastService!.year}-${entry.lastService!.month.toString().padLeft(2, '0')}-${entry.lastService!.day.toString().padLeft(2, '0')}'
          : '',
    );
    final nextCtrl = TextEditingController(
      text: entry.nextService != null
          ? '${entry.nextService!.year}-${entry.nextService!.month.toString().padLeft(2, '0')}-${entry.nextService!.day.toString().padLeft(2, '0')}'
          : '',
    );
    final notesCtrl = TextEditingController(text: entry.notes ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(
            children: [
              Icon(comp.icon, size: 20),
              const SizedBox(width: 8),
              Text('${comp.label} – Zustand'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gut',      label: Text('Gut'),     icon: Icon(Icons.check_circle_outline, size: 16)),
                    ButtonSegment(value: 'prufen',   label: Text('Prüfen'),  icon: Icon(Icons.warning_amber_outlined, size: 16)),
                    ButtonSegment(value: 'kritisch', label: Text('Kritisch'),icon: Icon(Icons.error_outline, size: 16)),
                  ],
                  selected: {selectedStatus},
                  onSelectionChanged: (val) => setS(() => selectedStatus = val.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lastCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Letzte Wartung (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nextCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nächste Wartung (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notizen',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                setState(() {
                  entry.status = selectedStatus;
                  entry.lastService = _parseDateSafe(lastCtrl.text);
                  entry.nextService = _parseDateSafe(nextCtrl.text);
                  entry.notes = notesCtrl.text.isEmpty ? null : notesCtrl.text;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _parseDateSafe(String s) {
    if (s.trim().isEmpty) return null;
    try { return DateTime.parse(s.trim()); } catch (_) { return null; }
  }
}


class _PropertyMaintenanceDashboard extends StatelessWidget {
  const _PropertyMaintenanceDashboard({
    required this.tickets,
    required this.onStatusFilter,
    required this.onDueFilter,
  });

  final List<MaintenanceWorkflowRecord> tickets;
  final ValueChanged<String> onStatusFilter;
  final ValueChanged<String> onDueFilter;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekEnd = todayStart.add(const Duration(days: 7));
    final open =
        tickets.where((item) => !_closedMaintenanceStatus(item.ticket.status)).length;
    final overdue = tickets.where((item) {
      final dueAt = item.ticket.dueAt;
      return dueAt != null &&
          dueAt < todayStart.millisecondsSinceEpoch &&
          !_closedMaintenanceStatus(item.ticket.status);
    }).length;
    final dueSoon = tickets.where((item) {
      final dueAt = item.ticket.dueAt;
      return dueAt != null &&
          dueAt >= todayStart.millisecondsSinceEpoch &&
          dueAt < weekEnd.millisecondsSinceEpoch &&
          !_closedMaintenanceStatus(item.ticket.status);
    }).length;
    final damage = tickets.where((item) => item.ticket.category == 'damage').length;
    final insurance =
        tickets.where((item) => item.ticket.insuranceCase).length;
    final exposure = tickets.fold<double>(
      0,
      (sum, item) => sum + (item.ticket.costActual ?? item.ticket.costEstimate ?? 0),
    );
    final byStatus = <String, int>{};
    for (final item in tickets) {
      byStatus[item.ticket.status] = (byStatus[item.ticket.status] ?? 0) + 1;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Offen',
              value: open.toString(),
              icon: Icons.pending_actions_outlined,
              onTap: () => onStatusFilter('open'),
            ),
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Überfällig',
              value: overdue.toString(),
              icon: Icons.warning_amber_outlined,
              tone:
                  overdue == 0
                      ? context.semanticColors.success
                      : Theme.of(context).colorScheme.error,
              onTap: () => onDueFilter('overdue'),
            ),
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Diese Woche',
              value: dueSoon.toString(),
              icon: Icons.event_available_outlined,
              onTap: () => onDueFilter('week'),
            ),
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Schäden',
              value: damage.toString(),
              icon: Icons.report_problem_outlined,
            ),
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Versicherung',
              value: insurance.toString(),
              icon: Icons.policy_outlined,
            ),
            _PropertyMaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 220,
              label: 'Kostenrisiko',
              value: _formatMaintenanceCurrency(exposure),
              icon: Icons.payments_outlined,
            ),
            _PropertyMaintenanceStatusBars(
              width: narrow ? constraints.maxWidth : 360,
              values: byStatus,
              onStatusFilter: onStatusFilter,
            ),
          ],
        );
      },
    );
  }
}

class _PropertyMaintenanceSignalTile extends StatelessWidget {
  const _PropertyMaintenanceSignalTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.onTap,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.component),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: context.semanticColors.border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyMaintenanceStatusBars extends StatelessWidget {
  const _PropertyMaintenanceStatusBars({
    required this.width,
    required this.values,
    required this.onStatusFilter,
  });

  final double width;
  final Map<String, int> values;
  final ValueChanged<String> onStatusFilter;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    final denominator = maxValue == 0 ? 1.0 : maxValue.toDouble();
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statusverteilung', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text('Keine Daten', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final entry in entries.take(5)) ...[
              InkWell(
                onTap: () => onStatusFilter(entry.key),
                child: Row(
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        entry.key.replaceAll('_', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: entry.value / denominator,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(entry.value.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _PropertyMaintenanceBoardColumn extends StatelessWidget {
  const _PropertyMaintenanceBoardColumn({
    required this.title,
    required this.tickets,
    required this.selectedId,
    required this.onOpen,
    required this.onEdit,
  });

  final String title;
  final List<MaintenanceWorkflowRecord> tickets;
  final String? selectedId;
  final ValueChanged<MaintenanceWorkflowRecord> onOpen;
  final ValueChanged<MaintenanceWorkflowRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.component),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                ),
                NxStatusBadge(label: tickets.length.toString(), kind: NxBadgeKind.info),
              ],
            ),
          ),
          Divider(height: 1, color: context.semanticColors.border),
          tickets.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.component),
                  child: Text(
                    'Keine Tickets',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
              : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                        final workflow = tickets[index];
                        final ticket = workflow.ticket;
                        return _PropertyMaintenanceMiniTicket(
                          selected: selectedId == ticket.id,
                          workflow: workflow,
                          onOpen: () => onOpen(workflow),
                          onEdit: () => onEdit(workflow),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}

class _PropertyMaintenanceDueCard extends StatelessWidget {
  const _PropertyMaintenanceDueCard({
    required this.width,
    required this.title,
    required this.tickets,
    required this.onOpen,
    required this.onEdit,
  });

  final double width;
  final String title;
  final List<MaintenanceWorkflowRecord> tickets;
  final ValueChanged<MaintenanceWorkflowRecord> onOpen;
  final ValueChanged<MaintenanceWorkflowRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              NxStatusBadge(label: tickets.length.toString(), kind: NxBadgeKind.info),
            ],
          ),
          const SizedBox(height: 10),
          if (tickets.isEmpty)
            Text('Keine Tickets', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final workflow in tickets.take(5)) ...[
              _PropertyMaintenanceMiniTicket(
                workflow: workflow,
                selected: false,
                onOpen: () => onOpen(workflow),
                onEdit: () => onEdit(workflow),
              ),
            ],
        ],
      ),
    );
  }
}

class _PropertyMaintenanceMiniTicket extends StatelessWidget {
  const _PropertyMaintenanceMiniTicket({
    required this.workflow,
    required this.selected,
    required this.onOpen,
    required this.onEdit,
  });

  final MaintenanceWorkflowRecord workflow;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ticket = workflow.ticket;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color:
                selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            border: Border.all(
              color:
                  selected
                    ? Theme.of(context).colorScheme.primary
                    : context.semanticColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bearbeiten',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${ticket.priority}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                ticket.dueAt == null ? 'Ohne Termin' : _shortDate(ticket.dueAt!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _PropertyMaintenanceDueBucket {
  const _PropertyMaintenanceDueBucket(this.label, this.key);

  final String label;
  final String key;
}

bool _closedMaintenanceStatus(String status) {
  return const {'completed', 'billed', 'resolved', 'closed'}.contains(status);
}

String _shortDate(int value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value,
  ).toIso8601String().substring(0, 10);
}

String _formatMaintenanceCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '$sign€ ${(absValue / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absValue >= 1000) {
    return '$sign€ ${(absValue / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absValue.toStringAsFixed(0)}';
}

String _formatCurrency(double value) {
  return '€ ${value.toStringAsFixed(2)}';
}

// =============================================================================
// BAUTEILZUSTAND DATA MODEL
// =============================================================================
class _BauteilStatusEntry {
  _BauteilStatusEntry({
    required this.id,
    required this.label,
    this.status = 'gut',
    this.lastService,
    this.nextService,
    this.notes,
  });

  final String id;
  final String label;
  String status; // 'gut' | 'prufen' | 'kritisch'
  DateTime? lastService;
  DateTime? nextService;
  String? notes;

  Color get statusColor {
    switch (status) {
      case 'kritisch': return const Color(0xFFDC2626);
      case 'prufen':   return const Color(0xFFD97706);
      default:         return const Color(0xFF16A34A);
    }
  }

  String get statusLabel {
    switch (status) {
      case 'kritisch': return 'Kritisch';
      case 'prufen':   return 'Prüfen';
      default:         return 'Gut';
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'kritisch': return Icons.error_outline;
      case 'prufen':   return Icons.warning_amber_outlined;
      default:         return Icons.check_circle_outline;
    }
  }
}
