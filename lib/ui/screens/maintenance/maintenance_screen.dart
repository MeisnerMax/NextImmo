import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/maintenance.dart';
import '../../../core/models/property.dart';
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
  String _categoryFilter = 'all';
  String _assigneeFilter = 'all';
  String _dueFilter = 'all';
  String _viewMode = 'list';
  List<PropertyRecord> _properties = const [];
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
    final visibleTickets = _visibleTickets;
    final openCount =
        visibleTickets
            .where(
              (ticket) =>
                  !_isClosedStatus(ticket.ticket.status),
            )
            .length;
    final linkedTaskCount = visibleTickets.fold<int>(
      0,
      (sum, ticket) => sum + ticket.linkedTaskCount,
    );
    final assigneeOptions = _assigneeOptions;

    return ListFilterTemplate(
      title: 'Maintenance',
      breadcrumbs: const ['Daily Business', 'Maintenance'],
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
            child: DropdownButtonFormField<String>(
              value: _assetPropertyId.isEmpty ? 'all' : _assetPropertyId,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All properties')),
                ..._properties.map(
                  (property) => DropdownMenuItem(
                    value: property.id,
                    child: Text(property.name),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _assetPropertyId = value == 'all' ? '' : value;
                  _selectedTicket = null;
                });
                _reload();
              },
              decoration: const InputDecoration(labelText: 'Property'),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All statuses')),
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(value: 'planned', child: Text('Planned')),
                DropdownMenuItem(
                  value: 'commissioned',
                  child: Text('Commissioned'),
                ),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('In progress'),
                ),
                DropdownMenuItem(
                  value: 'waiting_material',
                  child: Text('Waiting for material'),
                ),
                DropdownMenuItem(
                  value: 'waiting_reply',
                  child: Text('Waiting for reply'),
                ),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'billed', child: Text('Billed')),
                DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                DropdownMenuItem(value: 'closed', child: Text('Closed')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _statusFilter = value;
                  _selectedTicket = null;
                });
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
                setState(() {
                  _priorityFilter = value;
                  _selectedTicket = null;
                });
                _reload();
              },
              decoration: const InputDecoration(labelText: 'Priority'),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              value: _categoryFilter,
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
                if (value == null) {
                  return;
                }
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
                if (value == null) {
                  return;
                }
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
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Alle Termine')),
                DropdownMenuItem(value: 'overdue', child: Text('Überfällig')),
                DropdownMenuItem(value: 'today', child: Text('Heute')),
                DropdownMenuItem(value: 'week', child: Text('Diese Woche')),
                DropdownMenuItem(value: 'later', child: Text('Später')),
                DropdownMenuItem(value: 'none', child: Text('Ohne Termin')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
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
              items: const [
                DropdownMenuItem(value: 'list', child: Text('Liste')),
                DropdownMenuItem(value: 'board', child: Text('Board')),
                DropdownMenuItem(value: 'calendar', child: Text('Termine')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
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
      ),
      content:
          visibleTickets.isEmpty
              ? const NxEmptyState(
                title: 'No tickets found',
                description:
                    'Create a ticket or widen the current filters to inspect maintenance work.',
                icon: Icons.build_outlined,
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  if (_viewMode == 'board') {
                    return Column(
                      children: [
                        _MaintenanceDashboard(
                          tickets: visibleTickets,
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
                        Expanded(child: _buildBoard(visibleTickets)),
                      ],
                    );
                  }
                  if (_viewMode == 'calendar') {
                    return Column(
                      children: [
                        _MaintenanceDashboard(
                          tickets: visibleTickets,
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
                        Expanded(child: _buildDuePlanner(visibleTickets)),
                      ],
                    );
                  }
                  final stacked = constraints.maxWidth < 1060;
                  if (stacked) {
                    return Column(
                      children: [
                        _MaintenanceDashboard(
                          tickets: visibleTickets,
                          onStatusFilter: (status) {
                            setState(() => _statusFilter = status);
                          },
                          onDueFilter: (filter) {
                            setState(() => _dueFilter = filter);
                          },
                        ),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(flex: 3, child: _buildTicketList(visibleTickets)),
                        const SizedBox(height: AppSpacing.component),
                        Expanded(flex: 2, child: _buildTicketDetail()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _MaintenanceDashboard(
                        tickets: visibleTickets,
                        onStatusFilter: (status) {
                          setState(() => _statusFilter = status);
                        },
                        onDueFilter: (filter) {
                          setState(() => _dueFilter = filter);
                        },
                      ),
                      const SizedBox(height: AppSpacing.component),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _buildTicketList(visibleTickets)),
                            const SizedBox(width: AppSpacing.component),
                            Expanded(child: _buildTicketDetail()),
                          ],
                        ),
                      ),
                    ],
                  );
                },
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
      _assetPropertyId = '';
      _statusFilter = 'all';
      _priorityFilter = 'all';
      _categoryFilter = 'all';
      _assigneeFilter = 'all';
      _dueFilter = 'all';
      _viewMode = 'list';
    });
    _reload();
  }

  Widget _buildTicketList(List<MaintenanceWorkflowRecord> tickets) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
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
            _MaintenanceBoardColumn(
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

  Widget _buildDuePlanner(List<MaintenanceWorkflowRecord> tickets) {
    final buckets = <_MaintenanceDueBucket>[
      _MaintenanceDueBucket('Überfällig', 'overdue'),
      _MaintenanceDueBucket('Heute', 'today'),
      _MaintenanceDueBucket('Diese Woche', 'week'),
      _MaintenanceDueBucket('Später', 'later'),
      _MaintenanceDueBucket('Ohne Termin', 'none'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth =
            constraints.maxWidth < 760 ? constraints.maxWidth : 240.0;
        return SingleChildScrollView(
          child: Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              for (final bucket in buckets)
                _MaintenanceDueCard(
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
          ),
        );
      },
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
                    _isClosedStatus(ticket.status)
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
          const SizedBox(height: 4),
          Text('Ticketart: ${_categoryLabel(ticket.category)}'),
          if (ticket.damageLocation != null &&
              ticket.damageLocation!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Schadenort: ${ticket.damageLocation}'),
          ],
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
          Text('Bearbeiter/Firma: ${ticket.vendorName ?? 'Nicht zugewiesen'}'),
          const SizedBox(height: 4),
          Text('Versicherung: ${_insuranceLabel(ticket)}'),
          const SizedBox(height: 4),
          Text('Document: ${workflow.documentName ?? 'No linked document'}'),
          const SizedBox(height: 4),
          Text('Follow-up task: ${workflow.linkedTaskCount} linked'),
          const SizedBox(height: 12),
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
                    style: Theme.of(context).textTheme.titleSmall,
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
          const SizedBox(height: 12),
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
    final properties = await ref.read(propertyRepositoryProvider).list();
    final tickets = await ref
        .read(maintenanceRepositoryProvider)
        .listWorkflowTickets(
          assetPropertyId: _assetPropertyId.isEmpty ? null : _assetPropertyId,
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
      _properties = properties;
      _tickets = tickets;
      _selectedTicket =
          selectedTicket ?? (tickets.isEmpty ? null : tickets.first);
    });
  }

  Future<void> _createTicketDialog() async {
    final titleCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final costEstimateCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    final damageLocationCtrl = TextEditingController();
    final insuranceClaimCtrl = TextEditingController();
    String assetPropertyId =
        _assetPropertyId.isNotEmpty
            ? _assetPropertyId
            : (_properties.isEmpty ? '' : _properties.first.id);
    String category = 'damage';
    String priority = 'normal';
    String insuranceStatus = 'reported';
    bool createTask = true;
    bool insuranceCase = false;
    DateTime? dueDate;

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Create Maintenance Ticket'),
                  content: SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        DropdownButtonFormField<String>(
                          value: assetPropertyId.isEmpty ? null : assetPropertyId,
                          items: _properties
                              .map(
                                (property) => DropdownMenuItem(
                                  value: property.id,
                                  child: Text(property.name),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => assetPropertyId = value);
                            }
                          },
                          decoration: const InputDecoration(labelText: 'Property'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: descCtrl,
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
                          decoration: const InputDecoration(labelText: 'Category'),
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
                              dueCtrl.text = _formatDate(
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
                          const SizedBox(height: 8),
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
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
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

    titleCtrl.dispose();
    dueCtrl.dispose();
    descCtrl.dispose();
    costEstimateCtrl.dispose();
    vendorCtrl.dispose();
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
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
    var category = ticket.category;
    var priority = ticket.priority;
    var status = ticket.status;
    var insuranceStatus = ticket.insuranceStatus ?? 'reported';
    var insuranceCase = ticket.insuranceCase;
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
                    width: 500,
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
                            items: _categoryItems(category),
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
                              DropdownMenuItem(
                                value: 'normal',
                                child: Text('normal'),
                              ),
                              DropdownMenuItem(value: 'high', child: Text('high')),
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
                            decoration: const InputDecoration(labelText: 'Priorität'),
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
                                  IconButton(
                                    tooltip: 'Termin löschen',
                                    onPressed: () {
                                      setDialogState(() {
                                        dueDate = null;
                                        dueCtrl.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                                  const Icon(Icons.calendar_today),
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
                              if (picked == null) {
                                return;
                              }
                              setDialogState(() {
                                dueDate = picked;
                                dueCtrl.text =
                                    _formatDate(picked.millisecondsSinceEpoch);
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
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) {
                          return;
                        }
                        final updated = MaintenanceTicketRecord(
                          id: ticket.id,
                          assetPropertyId: ticket.assetPropertyId,
                          unitId: ticket.unitId,
                          title: title,
                          description:
                              descCtrl.text.trim().isEmpty
                                  ? null
                                  : descCtrl.text.trim(),
                          category: category,
                          status: status,
                          priority: priority,
                          reportedAt: ticket.reportedAt,
                          dueAt: dueDate?.millisecondsSinceEpoch,
                          resolvedAt:
                              _isClosedStatus(status)
                                  ? (ticket.resolvedAt ??
                                      DateTime.now().millisecondsSinceEpoch)
                                  : null,
                          costEstimate: _parseMoney(costEstimateCtrl.text),
                          costActual: _parseMoney(costActualCtrl.text),
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
    descCtrl.dispose();
    dueCtrl.dispose();
    costEstimateCtrl.dispose();
    costActualCtrl.dispose();
    vendorCtrl.dispose();
    damageLocationCtrl.dispose();
    insuranceClaimCtrl.dispose();
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
}

class _MaintenanceDashboard extends StatelessWidget {
  const _MaintenanceDashboard({
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
            _MaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Offen',
              value: open.toString(),
              icon: Icons.pending_actions_outlined,
              onTap: () => onStatusFilter('open'),
            ),
            _MaintenanceSignalTile(
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
            _MaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Diese Woche',
              value: dueSoon.toString(),
              icon: Icons.event_available_outlined,
              onTap: () => onDueFilter('week'),
            ),
            _MaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Schäden',
              value: damage.toString(),
              icon: Icons.report_problem_outlined,
            ),
            _MaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 180,
              label: 'Versicherung',
              value: insurance.toString(),
              icon: Icons.policy_outlined,
            ),
            _MaintenanceSignalTile(
              width: narrow ? constraints.maxWidth : 220,
              label: 'Kostenrisiko',
              value: _formatMaintenanceCurrency(exposure),
              icon: Icons.payments_outlined,
            ),
            _MaintenanceStatusBars(
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

class _MaintenanceSignalTile extends StatelessWidget {
  const _MaintenanceSignalTile({
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

class _MaintenanceStatusBars extends StatelessWidget {
  const _MaintenanceStatusBars({
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

class _MaintenanceBoardColumn extends StatelessWidget {
  const _MaintenanceBoardColumn({
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
          Expanded(
            child:
                tickets.isEmpty
                    ? Center(
                      child: Text(
                        'Keine Tickets',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      itemCount: tickets.length,
                      itemBuilder: (context, index) {
                        final workflow = tickets[index];
                        final ticket = workflow.ticket;
                        return _MaintenanceMiniTicket(
                          selected: selectedId == ticket.id,
                          workflow: workflow,
                          onOpen: () => onOpen(workflow),
                          onEdit: () => onEdit(workflow),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceDueCard extends StatelessWidget {
  const _MaintenanceDueCard({
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
              _MaintenanceMiniTicket(
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

class _MaintenanceMiniTicket extends StatelessWidget {
  const _MaintenanceMiniTicket({
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
                '${workflow.propertyName ?? ticket.assetPropertyId} · ${ticket.priority}',
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

class _MaintenanceDueBucket {
  const _MaintenanceDueBucket(this.label, this.key);

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
