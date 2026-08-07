/// The portfolio-wide maintenance ticket surface (Welle 4, SCR-039), built on
/// the `maintenance_capex` feature contract's workspace-wide read (P2-D06
/// follow-up RPC — see `maintenance_tickets_controller.dart`).
///
/// Cloud-only (`04d_wave4_maintenance_capex.md`): the legacy
/// `maintenance/maintenance_screen.dart` stays untouched and is still the
/// only workspace-wide maintenance surface in SQLite mode; this panel never
/// mounts there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/maintenance_capex/application/maintenance_tickets_controller.dart';
import '../../../features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import '../../../features/portfolio_property/domain/property_dto.dart';
import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../navigation/app_navigation.dart';
import 'widgets/maintenance_capex_badges.dart';

class MaintenanceTicketsPanel extends ConsumerStatefulWidget {
  const MaintenanceTicketsPanel({super.key});

  @override
  ConsumerState<MaintenanceTicketsPanel> createState() =>
      _MaintenanceTicketsPanelState();
}

class _MaintenanceTicketsPanelState
    extends ConsumerState<MaintenanceTicketsPanel> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(maintenanceTicketsControllerProvider);
    final controller = ref.read(maintenanceTicketsControllerProvider.notifier);
    final properties = ref.watch(referenceSliceControllerProvider).properties;
    _listenForActionFeedback();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          state: state,
          canMutate: controller.canMutate,
          onStatusChanged: (value) =>
              unawaited(controller.updateFilters(status: value)),
          onPriorityChanged: (value) =>
              unawaited(controller.updateFilters(priority: value)),
          onCreate: properties.isEmpty
              ? null
              : () => _createTicket(controller, properties),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(state, controller, properties)),
      ],
    );
  }

  Widget _buildContent(
    MaintenanceTicketsState state,
    MaintenanceTicketsController controller,
    List<PropertySummaryDto> properties,
  ) {
    switch (state.listPhase) {
      case MaintenanceTicketsListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Wartungstickets werden je Arbeitsbereich geführt. Melde dich '
              'an oder wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case MaintenanceTicketsListPhase.loading:
        return const _TicketsSkeleton();
      case MaintenanceTicketsListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Wartungstickets',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung '
              '(maintenance.read).',
          icon: Icons.lock_outline,
        );
      case MaintenanceTicketsListPhase.error:
        return NxEmptyState(
          title: 'Tickets konnten nicht geladen werden',
          description:
              state.message ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case MaintenanceTicketsListPhase.empty:
        return NxEmptyState(
          title: 'Keine offenen Tickets',
          description:
              state.statusFilter != null || state.priorityFilter != null
              ? 'Für diesen Filter gibt es keine Treffer.'
              : 'Lege das erste Wartungsticket an.',
          icon: Icons.build_outlined,
          primaryAction: properties.isEmpty
              ? null
              : FilledButton.icon(
                  onPressed: controller.canMutate
                      ? () => _createTicket(controller, properties)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Ticket anlegen'),
                ),
        );
      case MaintenanceTicketsListPhase.ready:
        return _TicketsTable(
          tickets: state.tickets,
          properties: properties,
          canMutate: controller.canMutate,
          onTransition: (ticket, target) =>
              _transition(controller, ticket, target),
          // The property-scoped panel (tickets + CapEx for one object) has no
          // sidebar destination of its own — it is object-scoped. This list is
          // its in-app entry point: a ticket names an object, so opening that
          // object's maintenance surface from here is the natural move.
          onOpenProperty: (propertyId) => Navigator.of(
            context,
          ).pushNamed(propertyMaintenanceRouteFor(propertyId)),
        );
    }
  }

  void _listenForActionFeedback() {
    ref.listen<MaintenanceTicketsState>(maintenanceTicketsControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(maintenanceTicketsControllerProvider.notifier);
      switch (next.actionPhase) {
        case MaintenanceTicketsActionPhase.conflict:
          unawaited(
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Ticket wurde zwischenzeitlich geändert'),
                content: Text(
                  next.versionConflict?.currentTicket == null
                      ? 'Jemand anderes hat dieses Ticket bearbeitet. Lade '
                            'die Liste neu und wiederhole die Änderung.'
                      : 'Jemand anderes hat dieses Ticket bearbeitet (jetzt '
                            'Version '
                            '${next.versionConflict!.currentTicket!.version}'
                            '). Deine Änderung wurde nicht gespeichert.',
                ),
                actions: <Widget>[
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      controller.clearAction();
                      unawaited(controller.load());
                    },
                    child: const Text('Neu laden'),
                  ),
                ],
              ),
            ),
          );
        case MaintenanceTicketsActionPhase.succeeded:
        case MaintenanceTicketsActionPhase.forbidden:
        case MaintenanceTicketsActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case MaintenanceTicketsActionPhase.idle:
        case MaintenanceTicketsActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _createTicket(
    MaintenanceTicketsController controller,
    List<PropertySummaryDto> properties,
  ) async {
    final result = await showMaintenanceTicketFormDialog(
      context,
      properties: properties,
    );
    if (result == null) {
      return;
    }
    await controller.createTicket(result);
  }

  Future<void> _transition(
    MaintenanceTicketsController controller,
    MaintenanceTicketSummaryDto ticket,
    MaintenanceTicketStatus target,
  ) async {
    double? costActual;
    if (target == MaintenanceTicketStatus.resolved ||
        target == MaintenanceTicketStatus.invoiced) {
      costActual = await showMaintenanceTicketCostDialog(context);
    }
    await controller.transition(
      ticket: ticket,
      target: target,
      costActual: costActual,
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.canMutate,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onCreate,
  });

  final MaintenanceTicketsState state;
  final bool canMutate;
  final ValueChanged<MaintenanceTicketStatus?> onStatusChanged;
  final ValueChanged<MaintenanceTicketPriority?> onPriorityChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<MaintenanceTicketStatus?>(
            value: state.statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: <DropdownMenuItem<MaintenanceTicketStatus?>>[
              const DropdownMenuItem(value: null, child: Text('Alle Status')),
              for (final status in MaintenanceTicketStatus.values)
                DropdownMenuItem(
                  value: status,
                  child: Text(maintenanceTicketStatusLabel(status)),
                ),
            ],
            onChanged: onStatusChanged,
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<MaintenanceTicketPriority?>(
            value: state.priorityFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Priorität'),
            items: <DropdownMenuItem<MaintenanceTicketPriority?>>[
              const DropdownMenuItem(
                value: null,
                child: Text('Alle Prioritäten'),
              ),
              for (final priority in MaintenanceTicketPriority.values)
                DropdownMenuItem(
                  value: priority,
                  child: Text(maintenanceTicketPriorityLabel(priority)),
                ),
            ],
            onChanged: onPriorityChanged,
          ),
        ),
        FilledButton.icon(
          onPressed: canMutate ? onCreate : null,
          icon: const Icon(Icons.add),
          label: const Text('Ticket anlegen'),
        ),
      ],
    );
  }
}

class _TicketsTable extends StatelessWidget {
  const _TicketsTable({
    required this.tickets,
    required this.properties,
    required this.canMutate,
    required this.onTransition,
    required this.onOpenProperty,
  });

  final List<MaintenanceTicketSummaryDto> tickets;
  final List<PropertySummaryDto> properties;
  final bool canMutate;
  final void Function(MaintenanceTicketSummaryDto ticket, MaintenanceTicketStatus target)
  onTransition;
  final ValueChanged<String> onOpenProperty;

  String _propertyName(String propertyId) {
    return properties
            .where((property) => property.id == propertyId)
            .map((property) => property.name)
            .firstOrNull ??
        propertyId;
  }

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      child: DataTable(
        showCheckboxColumn: false,
        columns: const <DataColumn>[
          DataColumn(label: Text('Objekt')),
          DataColumn(label: Text('Titel')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Priorität')),
          DataColumn(label: Text('Kosten')),
          DataColumn(label: Text('')),
        ],
        rows: <DataRow>[
          for (final ticket in tickets)
            DataRow(
              cells: <DataCell>[
                DataCell(
                  TextButton(
                    onPressed: () => onOpenProperty(ticket.propertyId),
                    child: Text(_propertyName(ticket.propertyId)),
                  ),
                ),
                DataCell(Text(ticket.title)),
                DataCell(MaintenanceTicketStatusBadge(status: ticket.status)),
                DataCell(MaintenanceTicketPriorityBadge(priority: ticket.priority)),
                DataCell(
                  Text(
                    ticket.costActual != null
                        ? '${ticket.costActual} ${ticket.currencyCode ?? ''}'
                        : (ticket.costEstimate != null
                              ? '~${ticket.costEstimate} ${ticket.currencyCode ?? ''}'
                              : '—'),
                  ),
                ),
                DataCell(
                  ticket.status.allowedNextStatuses.isEmpty || !canMutate
                      ? const SizedBox.shrink()
                      : PopupMenuButton<MaintenanceTicketStatus>(
                          tooltip: 'Status ändern',
                          onSelected: (target) => onTransition(ticket, target),
                          itemBuilder: (context) => <PopupMenuEntry<
                            MaintenanceTicketStatus
                          >>[
                            for (final target in ticket.status.allowedNextStatuses)
                              PopupMenuItem(
                                value: target,
                                child: Text(maintenanceTicketStatusLabel(target)),
                              ),
                          ],
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TicketsSkeleton extends StatelessWidget {
  const _TicketsSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 6; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}

// --- Dialogs -----------------------------------------------------------

Future<MaintenanceTicketDraft?> showMaintenanceTicketFormDialog(
  BuildContext context, {
  required List<PropertySummaryDto> properties,
}) async {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var propertyId = properties.first.id;
  var priority = MaintenanceTicketPriority.normal;

  return showDialog<MaintenanceTicketDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Ticket anlegen'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  value: propertyId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Objekt'),
                  items: <DropdownMenuItem<String>>[
                    for (final property in properties)
                      DropdownMenuItem(
                        value: property.id,
                        child: Text(property.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => propertyId = value ?? propertyId),
                ),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Titel'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld'
                      : null,
                ),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                  maxLines: 3,
                ),
                DropdownButtonFormField<MaintenanceTicketPriority>(
                  value: priority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Priorität'),
                  items: <DropdownMenuItem<MaintenanceTicketPriority>>[
                    for (final p in MaintenanceTicketPriority.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(maintenanceTicketPriorityLabel(p)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => priority = value ?? priority),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.of(dialogContext).pop(
                MaintenanceTicketDraft(
                  propertyId: propertyId,
                  title: titleController.text.trim(),
                  description: descriptionController.text.trim().isEmpty
                      ? null
                      : descriptionController.text.trim(),
                  priority: priority,
                ),
              );
            },
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ),
  );
}

Future<double?> showMaintenanceTicketCostDialog(BuildContext context) async {
  final costController = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ist-Kosten (optional)'),
      content: NxCard(
        child: TextField(
          controller: costController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Ist-Kosten'),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Überspringen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            double.tryParse(costController.text.trim().replaceAll(',', '.')),
          ),
          child: const Text('Übernehmen'),
        ),
      ],
    ),
  );
}
