/// The property-scoped `maintenance_capex` panel (Welle 4), merging SCR-034
/// (PropertyMaintenanceScreen) and the renovation half of SCR-031
/// (AssetWorkbookScreen's "Hotel & Maßnahmen" tab) into one panel with two
/// tabs — see `04d_wave4_maintenance_capex.md` for why they are one
/// surface, not two.
///
/// Deliberately separate from both legacy screens, which stay untouched and
/// SQLite-only: this panel touches nothing but the feature contract, which is
/// what makes it mountable on its own additive cloud route
/// (`propertyMaintenanceRouteFor`), where neither legacy host exists.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/maintenance_capex/application/property_maintenance_capex_controller.dart';
import '../../../features/maintenance_capex/domain/capex_project_dto.dart';
import '../../../features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../maintenance/widgets/maintenance_capex_badges.dart';

/// Which half of the panel to render.
///
/// `both` is the standalone cloud route, which owns its own page header and
/// tab bar. The single-section variants exist for the Property Workspace,
/// where `Betrieb` already supplies the header and the sub-navigation, and
/// where the two halves are separately permissioned sub-areas
/// (`PROPERTY_OPERATIONS_V2.md` §8) rather than two tabs of one screen.
enum PropertyMaintenanceCapexSection { both, maintenance, capex }

class PropertyMaintenanceCapexPanel extends ConsumerStatefulWidget {
  const PropertyMaintenanceCapexPanel({
    super.key,
    required this.propertyId,
    this.section = PropertyMaintenanceCapexSection.both,
    this.embedded = false,
  });

  final String propertyId;
  final PropertyMaintenanceCapexSection section;

  /// Embedded in a host that already provides the page frame: no page header
  /// and no outer padding, so the panel does not indent twice.
  final bool embedded;

  @override
  ConsumerState<PropertyMaintenanceCapexPanel> createState() =>
      _PropertyMaintenanceCapexPanelState();
}

class _PropertyMaintenanceCapexPanelState
    extends ConsumerState<PropertyMaintenanceCapexPanel>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  bool get _tabbed => widget.section == PropertyMaintenanceCapexSection.both;

  @override
  void initState() {
    super.initState();
    if (_tabbed) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = propertyMaintenanceCapexControllerProvider(
      widget.propertyId,
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForActionFeedback(provider);

    final body = switch (widget.section) {
      PropertyMaintenanceCapexSection.maintenance => _TicketsTab(
        state: state,
        controller: controller,
      ),
      PropertyMaintenanceCapexSection.capex => _CapexTab(
        state: state,
        controller: controller,
      ),
      PropertyMaintenanceCapexSection.both => TabBarView(
        controller: _tabController,
        children: <Widget>[
          _TicketsTab(state: state, controller: controller),
          _CapexTab(state: state, controller: controller),
        ],
      ),
    };

    return Padding(
      padding: EdgeInsets.all(widget.embedded ? 0 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!widget.embedded) ...<Widget>[
            const NxPageHeader(title: 'Instandhaltung & CapEx'),
            if (_tabbed)
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const <Tab>[
                  Tab(text: 'Tickets'),
                  Tab(text: 'CapEx-Projekte'),
                ],
              ),
            const SizedBox(height: 16),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }

  void _listenForActionFeedback(
    AutoDisposeStateNotifierProvider<
      PropertyMaintenanceCapexController,
      PropertyMaintenanceCapexState
    >
    provider,
  ) {
    ref.listen<PropertyMaintenanceCapexState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(provider.notifier);
      switch (next.actionPhase) {
        case PropertyMaintenanceActionPhase.conflict:
          unawaited(
            showDialog<void>(
              context: context,
              builder:
                  (dialogContext) => AlertDialog(
                    title: const Text('Wurde zwischenzeitlich geändert'),
                    content: const Text(
                      'Jemand anderes hat diesen Datensatz bearbeitet, während du '
                      'ihn offen hattest. Lade neu und wiederhole die Änderung.',
                    ),
                    actions: <Widget>[
                      FilledButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          controller.clearAction();
                          unawaited(controller.loadAll());
                        },
                        child: const Text('Neu laden'),
                      ),
                    ],
                  ),
            ),
          );
        case PropertyMaintenanceActionPhase.succeeded:
        case PropertyMaintenanceActionPhase.forbidden:
        case PropertyMaintenanceActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case PropertyMaintenanceActionPhase.idle:
        case PropertyMaintenanceActionPhase.submitting:
          return;
      }
    });
  }
}

class _TicketsTab extends StatelessWidget {
  const _TicketsTab({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                controller.canManageTickets
                    ? () => _createTicket(context, controller)
                    : null,
            icon: const Icon(Icons.add),
            label: const Text('Ticket anlegen'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (state.ticketsPhase) {
      case PropertyMaintenanceZonePhase.idle:
      case PropertyMaintenanceZonePhase.loading:
        return const _Skeleton();
      case PropertyMaintenanceZonePhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Tickets',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung '
              '(maintenance.read).',
          icon: Icons.lock_outline,
        );
      case PropertyMaintenanceZonePhase.error:
        return NxEmptyState(
          title: 'Tickets konnten nicht geladen werden',
          description:
              state.ticketsMessage ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.loadTickets()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case PropertyMaintenanceZonePhase.empty:
        return const NxEmptyState(
          title: 'Noch keine Tickets',
          description: 'Lege das erste Wartungsticket für dieses Objekt an.',
          icon: Icons.build_outlined,
        );
      case PropertyMaintenanceZonePhase.ready:
        return NxDataTableShell(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const <DataColumn>[
              DataColumn(label: Text('Titel')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Priorität')),
              DataColumn(label: Text('')),
            ],
            rows: <DataRow>[
              for (final ticket in state.tickets)
                DataRow(
                  cells: <DataCell>[
                    DataCell(Text(ticket.title)),
                    DataCell(
                      MaintenanceTicketStatusBadge(status: ticket.status),
                    ),
                    DataCell(
                      MaintenanceTicketPriorityBadge(priority: ticket.priority),
                    ),
                    DataCell(
                      ticket.status.allowedNextStatuses.isEmpty ||
                              !controller.canManageTickets
                          ? const SizedBox.shrink()
                          : PopupMenuButton<MaintenanceTicketStatus>(
                            tooltip: 'Status ändern',
                            onSelected:
                                (target) => unawaited(
                                  _transition(
                                    context,
                                    controller,
                                    ticket,
                                    target,
                                  ),
                                ),
                            itemBuilder:
                                (
                                  context,
                                ) => <PopupMenuEntry<MaintenanceTicketStatus>>[
                                  for (final target
                                      in ticket.status.allowedNextStatuses)
                                    PopupMenuItem(
                                      value: target,
                                      child: Text(
                                        maintenanceTicketStatusLabel(target),
                                      ),
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

  Future<void> _createTicket(
    BuildContext context,
    PropertyMaintenanceCapexController controller,
  ) async {
    final result = await _showTicketFormDialog(context);
    if (result == null) {
      return;
    }
    await controller.createTicket(
      MaintenanceTicketDraft(
        propertyId: controller.propertyId,
        title: result.title,
        description: result.description,
        priority: result.priority,
      ),
    );
  }

  Future<void> _transition(
    BuildContext context,
    PropertyMaintenanceCapexController controller,
    MaintenanceTicketSummaryDto ticket,
    MaintenanceTicketStatus target,
  ) async {
    await controller.transitionTicket(ticket: ticket, target: target);
  }
}

class _CapexTab extends StatelessWidget {
  const _CapexTab({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                controller.canManageCapex
                    ? () => _createProject(context, controller)
                    : null,
            icon: const Icon(Icons.add),
            label: const Text('Projekt anlegen'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (state.capexPhase) {
      case PropertyMaintenanceZonePhase.idle:
      case PropertyMaintenanceZonePhase.loading:
        return const _Skeleton();
      case PropertyMaintenanceZonePhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf CapEx-Projekte',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung '
              '(capex.read).',
          icon: Icons.lock_outline,
        );
      case PropertyMaintenanceZonePhase.error:
        return NxEmptyState(
          title: 'Projekte konnten nicht geladen werden',
          description:
              state.capexMessage ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.loadCapexProjects()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case PropertyMaintenanceZonePhase.empty:
        return const NxEmptyState(
          title: 'Noch kein CapEx-Projekt',
          description: 'Lege das erste Sanierungs-/Investitionsprojekt an.',
          icon: Icons.construction_outlined,
        );
      case PropertyMaintenanceZonePhase.ready:
        return NxDataTableShell(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const <DataColumn>[
              DataColumn(label: Text('Projektcode')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Budget')),
              DataColumn(label: Text('Ist')),
              DataColumn(label: Text('')),
            ],
            rows: <DataRow>[
              for (final project in state.capexProjects)
                DataRow(
                  cells: <DataCell>[
                    DataCell(Text(project.projectCode)),
                    DataCell(CapexProjectStatusBadge(status: project.status)),
                    DataCell(
                      Text(
                        project.budgetAmount != null
                            ? '${project.budgetAmount} ${project.currencyCode ?? ''}'
                            : '—',
                      ),
                    ),
                    DataCell(
                      Text(
                        project.actualAmount != null
                            ? '${project.actualAmount} ${project.currencyCode ?? ''}'
                            : '—',
                      ),
                    ),
                    DataCell(_buildTransitionMenu(context, project)),
                  ],
                ),
            ],
          ),
        );
    }
  }

  Widget _buildTransitionMenu(
    BuildContext context,
    CapexProjectSummaryDto project,
  ) {
    final next = project.status.nextStatus;
    if (next == null) {
      return const SizedBox.shrink();
    }
    final requiresApprove = next == CapexProjectStatus.approved;
    final allowed =
        requiresApprove
            ? controller.canApproveCapex
            : controller.canManageCapex;
    return TextButton(
      onPressed:
          allowed ? () => unawaited(_transition(context, project, next)) : null,
      child: Text(
        requiresApprove
            ? 'Freigeben (${capexProjectStatusLabel(next)})'
            : '→ ${capexProjectStatusLabel(next)}',
      ),
    );
  }

  Future<void> _createProject(
    BuildContext context,
    PropertyMaintenanceCapexController controller,
  ) async {
    final result = await _showProjectFormDialog(context);
    if (result == null) {
      return;
    }
    await controller.createCapexProject(
      CapexProjectDraft(
        propertyId: controller.propertyId,
        projectCode: result.projectCode,
        category: result.category,
        budgetAmount: result.budgetAmount,
        currencyCode: result.budgetAmount != null ? 'EUR' : null,
      ),
    );
  }

  Future<void> _transition(
    BuildContext context,
    CapexProjectSummaryDto project,
    CapexProjectStatus target,
  ) async {
    double? actualAmount;
    if (target == CapexProjectStatus.completed ||
        target == CapexProjectStatus.invoiced) {
      actualAmount = await _showAmountDialog(context);
    }
    await controller.transitionCapexProject(
      project: project,
      target: target,
      actualAmount: actualAmount,
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

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

class _TicketFormResult {
  const _TicketFormResult({
    required this.title,
    this.description,
    required this.priority,
  });

  final String title;
  final String? description;
  final MaintenanceTicketPriority priority;
}

Future<_TicketFormResult?> _showTicketFormDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var priority = MaintenanceTicketPriority.normal;

  return showDialog<_TicketFormResult>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (dialogContext, setState) => AlertDialog(
                title: const Text('Ticket anlegen'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(labelText: 'Titel'),
                          validator:
                              (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'Pflichtfeld'
                                      : null,
                        ),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Beschreibung',
                          ),
                          maxLines: 3,
                        ),
                        DropdownButtonFormField<MaintenanceTicketPriority>(
                          value: priority,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Priorität',
                          ),
                          items: <DropdownMenuItem<MaintenanceTicketPriority>>[
                            for (final p in MaintenanceTicketPriority.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text(maintenanceTicketPriorityLabel(p)),
                              ),
                          ],
                          onChanged:
                              (value) =>
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
                        _TicketFormResult(
                          title: titleController.text.trim(),
                          description:
                              descriptionController.text.trim().isEmpty
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

class _ProjectFormResult {
  const _ProjectFormResult({
    required this.projectCode,
    this.category,
    this.budgetAmount,
  });

  final String projectCode;
  final String? category;
  final double? budgetAmount;
}

Future<_ProjectFormResult?> _showProjectFormDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final categoryController = TextEditingController();
  final budgetController = TextEditingController();

  return showDialog<_ProjectFormResult>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('CapEx-Projekt anlegen'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(labelText: 'Projektcode'),
                    validator:
                        (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Pflichtfeld'
                                : null,
                  ),
                  TextFormField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Kategorie'),
                  ),
                  TextFormField(
                    controller: budgetController,
                    decoration: const InputDecoration(
                      labelText: 'Budget (EUR)',
                    ),
                    keyboardType: TextInputType.number,
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
                  _ProjectFormResult(
                    projectCode: codeController.text.trim(),
                    category:
                        categoryController.text.trim().isEmpty
                            ? null
                            : categoryController.text.trim(),
                    budgetAmount: double.tryParse(
                      budgetController.text.trim().replaceAll(',', '.'),
                    ),
                  ),
                );
              },
              child: const Text('Anlegen'),
            ),
          ],
        ),
  );
}

Future<double?> _showAmountDialog(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<double>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Ist-Betrag (optional)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Ist-Betrag'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Überspringen'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop(
                    double.tryParse(
                      controller.text.trim().replaceAll(',', '.'),
                    ),
                  ),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
  );
}
