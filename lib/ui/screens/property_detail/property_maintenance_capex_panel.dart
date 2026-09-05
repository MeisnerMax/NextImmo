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
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_section_header.dart';
import '../../components/nx_split_view.dart';
import '../../theme/app_theme.dart';
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
    final list = Column(
      key: const Key('maintenance-tickets'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TicketFilterBar(state: state, controller: controller),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message:
                controller.canManageTickets
                    ? 'Neues Wartungsticket für dieses Objekt anlegen'
                    : 'Benötigt die Berechtigung (maintenance.manage).',
            child: FilledButton.icon(
              key: const Key('maintenance-ticket-create'),
              onPressed:
                  controller.canManageTickets
                      ? () => _createTicket(context, controller)
                      : null,
              icon: const Icon(Icons.add),
              label: const Text('Ticket anlegen'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(context)),
      ],
    );
    return NxSplitView(
      list: list,
      detail: _TicketDetail(state: state, controller: controller),
      showDetail: state.selectedTicketId != null,
      onBackToList: controller.clearTicketSelection,
      backLabel: 'Zur Ticketliste',
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
        // A filtered empty list is not an empty property, and the way out of
        // each is different.
        return state.hasTicketFilter
            ? NxEmptyState(
              key: const Key('maintenance-tickets-filtered-empty'),
              title: 'Keine Tickets mit diesem Filter',
              description:
                  'Für dieses Objekt gibt es keine Tickets, die dem Filter '
                  'entsprechen.',
              icon: Icons.filter_alt_off_outlined,
              primaryAction: OutlinedButton.icon(
                key: const Key('maintenance-tickets-filter-reset'),
                onPressed:
                    () => unawaited(
                      controller.setTicketFilters(status: null, priority: null),
                    ),
                icon: const Icon(Icons.close),
                label: const Text('Filter zurücksetzen'),
              ),
            )
            : const NxEmptyState(
              key: Key('maintenance-tickets-empty'),
              title: 'Noch keine Tickets',
              description:
                  'Lege das erste Wartungsticket für dieses Objekt '
                  'an.',
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
              DataColumn(label: Text('Fällig')),
              DataColumn(label: Text('')),
            ],
            rows: <DataRow>[
              for (final ticket in state.tickets)
                DataRow(
                  key: ValueKey<String>('maintenance-ticket-${ticket.id}'),
                  selected: ticket.id == state.selectedTicketId,
                  onSelectChanged:
                      (_) => unawaited(controller.selectTicket(ticket.id)),
                  cells: <DataCell>[
                    DataCell(Text(ticket.title)),
                    DataCell(
                      MaintenanceTicketStatusBadge(status: ticket.status),
                    ),
                    DataCell(
                      MaintenanceTicketPriorityBadge(priority: ticket.priority),
                    ),
                    DataCell(Text(_formatDate(ticket.dueAt))),
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
    final list = Column(
      key: const Key('capex-projects'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CapexFilterBar(state: state, controller: controller),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message:
                controller.canManageCapex
                    ? 'Neues CapEx-Projekt für dieses Objekt anlegen'
                    : 'Benötigt die Berechtigung (capex.manage).',
            child: FilledButton.icon(
              key: const Key('capex-project-create'),
              onPressed:
                  controller.canManageCapex
                      ? () => _createProject(context, controller)
                      : null,
              icon: const Icon(Icons.add),
              label: const Text('Projekt anlegen'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(context)),
      ],
    );
    return NxSplitView(
      list: list,
      detail: _ProjectDetail(state: state, controller: controller),
      showDetail: state.selectedProjectId != null,
      onBackToList: controller.clearProjectSelection,
      backLabel: 'Zur Projektliste',
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
        return state.hasCapexFilter
            ? NxEmptyState(
              key: const Key('capex-projects-filtered-empty'),
              title: 'Keine Projekte mit diesem Filter',
              description:
                  'Für dieses Objekt gibt es keine Projekte in diesem Status.',
              icon: Icons.filter_alt_off_outlined,
              primaryAction: OutlinedButton.icon(
                key: const Key('capex-projects-filter-reset'),
                onPressed:
                    () => unawaited(controller.setCapexStatusFilter(null)),
                icon: const Icon(Icons.close),
                label: const Text('Filter zurücksetzen'),
              ),
            )
            : const NxEmptyState(
              key: Key('capex-projects-empty'),
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
                  key: ValueKey<String>('capex-project-${project.id}'),
                  selected: project.id == state.selectedProjectId,
                  onSelectChanged:
                      (_) => unawaited(controller.selectProject(project.id)),
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

// --- Filters -----------------------------------------------------------

/// Server-side filters (`PROPERTY_OPERATIONS_V2.md` §4/§11).
///
/// Every one of these re-reads the list. None of them narrows an already
/// loaded page: a client-side filter would report a count for the slice that
/// happens to be in memory rather than for the property, which is the same
/// dishonesty the property list search exists to avoid.
class _TicketFilterBar extends StatelessWidget {
  const _TicketFilterBar({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<MaintenanceTicketStatus?>(
            key: const Key('maintenance-filter-status'),
            value: state.ticketStatusFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
            items: <DropdownMenuItem<MaintenanceTicketStatus?>>[
              const DropdownMenuItem<MaintenanceTicketStatus?>(
                child: Text('Alle Status'),
              ),
              for (final status in MaintenanceTicketStatus.values)
                DropdownMenuItem<MaintenanceTicketStatus?>(
                  value: status,
                  child: Text(maintenanceTicketStatusLabel(status)),
                ),
            ],
            onChanged:
                (value) =>
                    unawaited(controller.setTicketFilters(status: value)),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<MaintenanceTicketPriority?>(
            key: const Key('maintenance-filter-priority'),
            value: state.ticketPriorityFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Priorität',
              isDense: true,
            ),
            items: <DropdownMenuItem<MaintenanceTicketPriority?>>[
              const DropdownMenuItem<MaintenanceTicketPriority?>(
                child: Text('Alle Prioritäten'),
              ),
              for (final priority in MaintenanceTicketPriority.values)
                DropdownMenuItem<MaintenanceTicketPriority?>(
                  value: priority,
                  child: Text(maintenanceTicketPriorityLabel(priority)),
                ),
            ],
            onChanged:
                (value) =>
                    unawaited(controller.setTicketFilters(priority: value)),
          ),
        ),
        if (state.hasTicketFilter)
          TextButton.icon(
            key: const Key('maintenance-filter-clear'),
            onPressed:
                () => unawaited(
                  controller.setTicketFilters(status: null, priority: null),
                ),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Filter zurücksetzen'),
          ),
      ],
    );
  }
}

class _CapexFilterBar extends StatelessWidget {
  const _CapexFilterBar({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<CapexProjectStatus?>(
            key: const Key('capex-filter-status'),
            value: state.capexStatusFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
            items: <DropdownMenuItem<CapexProjectStatus?>>[
              const DropdownMenuItem<CapexProjectStatus?>(
                child: Text('Alle Status'),
              ),
              for (final status in CapexProjectStatus.values)
                DropdownMenuItem<CapexProjectStatus?>(
                  value: status,
                  child: Text(capexProjectStatusLabel(status)),
                ),
            ],
            onChanged:
                (value) => unawaited(controller.setCapexStatusFilter(value)),
          ),
        ),
        if (state.hasCapexFilter)
          TextButton.icon(
            key: const Key('capex-filter-clear'),
            onPressed: () => unawaited(controller.setCapexStatusFilter(null)),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Filter zurücksetzen'),
          ),
      ],
    );
  }
}

// --- Details -----------------------------------------------------------

/// The canonical ticket, read by id rather than taken from the list row.
///
/// The row is a summary projection; editing from it would send an
/// `expectedVersion` that may already be stale and would hide the fields the
/// summary drops (description, damage location, insurance, cost actuals).
class _TicketDetail extends StatelessWidget {
  const _TicketDetail({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    if (state.selectedTicketId == null) {
      return const NxEmptyState(
        key: Key('maintenance-ticket-detail-idle'),
        title: 'Kein Ticket ausgewählt',
        description: 'Wähle ein Ticket aus der Liste, um Details zu sehen.',
        icon: Icons.build_outlined,
      );
    }
    switch (state.ticketDetailPhase) {
      case PropertyMaintenanceDetailPhase.idle:
      case PropertyMaintenanceDetailPhase.loading:
        return const _Skeleton();
      case PropertyMaintenanceDetailPhase.notFound:
        return const NxEmptyState(
          key: Key('maintenance-ticket-detail-not-found'),
          title: 'Ticket nicht gefunden',
          description: 'Dieses Ticket ist nicht mehr verfügbar.',
          icon: Icons.search_off_outlined,
        );
      case PropertyMaintenanceDetailPhase.forbidden:
        return const NxEmptyState(
          key: Key('maintenance-ticket-detail-forbidden'),
          title: 'Kein Zugriff auf dieses Ticket',
          description:
              'Das Öffnen benötigt die Berechtigung '
              '(maintenance.read).',
          icon: Icons.lock_outline,
        );
      case PropertyMaintenanceDetailPhase.error:
        return NxEmptyState.error(
          key: const Key('maintenance-ticket-detail-error'),
          title: 'Ticket konnte nicht geladen werden',
          description:
              state.ticketDetailMessage ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          onRetry:
              () => unawaited(controller.selectTicket(state.selectedTicketId!)),
        );
      case PropertyMaintenanceDetailPhase.ready:
        return _ticket(context, state.selectedTicket!);
    }
  }

  Widget _ticket(BuildContext context, MaintenanceTicketDto ticket) {
    return SingleChildScrollView(
      key: const Key('maintenance-ticket-detail'),
      child: NxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            NxSectionHeader(
              title: ticket.title,
              compact: true,
              actions: <Widget>[
                Tooltip(
                  message:
                      controller.canManageTickets
                          ? 'Ticketdaten bearbeiten'
                          : 'Benötigt die Berechtigung (maintenance.manage).',
                  child: OutlinedButton.icon(
                    key: const Key('maintenance-ticket-edit'),
                    onPressed:
                        controller.canManageTickets
                            ? () => unawaited(_edit(context, ticket))
                            : null,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Bearbeiten'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                MaintenanceTicketStatusBadge(status: ticket.status),
                MaintenanceTicketPriorityBadge(priority: ticket.priority),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _FactRow(label: 'Kategorie', value: ticket.category),
            _FactRow(
              label: 'Beschreibung',
              value: ticket.description,
              multiline: true,
            ),
            _FactRow(label: 'Gemeldet', value: _formatDate(ticket.reportedAt)),
            _FactRow(label: 'Fällig', value: _formatDate(ticket.dueAt)),
            _FactRow(label: 'Erledigt', value: _formatDate(ticket.resolvedAt)),
            _FactRow(label: 'Schadensort', value: ticket.damageLocation),
            _FactRow(label: 'Fläche', value: ticket.unitId),
            _FactRow(
              label: 'Kosten geschätzt',
              value: _formatMoney(ticket.costEstimate, ticket.currencyCode),
            ),
            _FactRow(
              label: 'Kosten tatsächlich',
              value: _formatMoney(ticket.costActual, ticket.currencyCode),
            ),
            _FactRow(label: 'Dienstleister', value: ticket.contractorPartyId),
            _FactRow(
              label: 'Versicherungsfall',
              value: ticket.insuranceCase ? 'Ja' : 'Nein',
            ),
            if (ticket.insuranceCase) ...<Widget>[
              _FactRow(
                label: 'Versicherungsstatus',
                value: ticket.insuranceStatus,
              ),
              _FactRow(
                label: 'Schadensnummer',
                value: ticket.insuranceClaimNumber,
              ),
            ],
            const Divider(height: AppSpacing.lg),
            _FactRow(
              label: 'Zuletzt geändert',
              value: _formatDate(ticket.updatedAt),
            ),
            _FactRow(label: 'Version', value: '${ticket.version}'),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, MaintenanceTicketDto ticket) async {
    final changes = await _showTicketEditDialog(context, ticket);
    if (changes == null) {
      return;
    }
    await controller.updateTicket(changes);
  }
}

class _ProjectDetail extends StatelessWidget {
  const _ProjectDetail({required this.state, required this.controller});

  final PropertyMaintenanceCapexState state;
  final PropertyMaintenanceCapexController controller;

  @override
  Widget build(BuildContext context) {
    if (state.selectedProjectId == null) {
      return const NxEmptyState(
        key: Key('capex-project-detail-idle'),
        title: 'Kein Projekt ausgewählt',
        description: 'Wähle ein Projekt aus der Liste, um Details zu sehen.',
        icon: Icons.construction_outlined,
      );
    }
    switch (state.projectDetailPhase) {
      case PropertyMaintenanceDetailPhase.idle:
      case PropertyMaintenanceDetailPhase.loading:
        return const _Skeleton();
      case PropertyMaintenanceDetailPhase.notFound:
        return const NxEmptyState(
          key: Key('capex-project-detail-not-found'),
          title: 'Projekt nicht gefunden',
          description: 'Dieses Projekt ist nicht mehr verfügbar.',
          icon: Icons.search_off_outlined,
        );
      case PropertyMaintenanceDetailPhase.forbidden:
        return const NxEmptyState(
          key: Key('capex-project-detail-forbidden'),
          title: 'Kein Zugriff auf dieses Projekt',
          description: 'Das Öffnen benötigt die Berechtigung (capex.read).',
          icon: Icons.lock_outline,
        );
      case PropertyMaintenanceDetailPhase.error:
        return NxEmptyState.error(
          key: const Key('capex-project-detail-error'),
          title: 'Projekt konnte nicht geladen werden',
          description:
              state.projectDetailMessage ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          onRetry:
              () =>
                  unawaited(controller.selectProject(state.selectedProjectId!)),
        );
      case PropertyMaintenanceDetailPhase.ready:
        return _project(context, state.selectedProject!);
    }
  }

  Widget _project(BuildContext context, CapexProjectDto project) {
    return SingleChildScrollView(
      key: const Key('capex-project-detail'),
      child: NxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            NxSectionHeader(
              title: project.projectCode,
              compact: true,
              actions: <Widget>[
                Tooltip(
                  message:
                      controller.canManageCapex
                          ? 'Projektdaten bearbeiten'
                          : 'Benötigt die Berechtigung (capex.manage).',
                  child: OutlinedButton.icon(
                    key: const Key('capex-project-edit'),
                    onPressed:
                        controller.canManageCapex
                            ? () => unawaited(_edit(context, project))
                            : null,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Bearbeiten'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: CapexProjectStatusBadge(status: project.status),
            ),
            const SizedBox(height: AppSpacing.component),
            _FactRow(label: 'Kategorie', value: project.category),
            _FactRow(
              label: 'Maßnahme',
              value: project.measure,
              multiline: true,
            ),
            _FactRow(label: 'Verantwortlich', value: project.owner),
            _FactRow(label: 'Nächster Schritt', value: project.nextStep),
            _FactRow(label: 'Start', value: _formatDate(project.startDate)),
            _FactRow(
              label: 'Geplantes Ende',
              value: _formatDate(project.plannedEndDate),
            ),
            _FactRow(
              label: 'Tatsächliches Ende',
              value: _formatDate(project.actualEndDate),
            ),
            _FactRow(
              label: 'Budget',
              value: _formatMoney(project.budgetAmount, project.currencyCode),
            ),
            _FactRow(
              label: 'Forecast',
              value: _formatMoney(project.forecastAmount, project.currencyCode),
            ),
            _FactRow(
              label: 'Ist',
              value: _formatMoney(project.actualAmount, project.currencyCode),
            ),
            _FactRow(label: 'Dienstleister', value: project.contractorPartyId),
            const Divider(height: AppSpacing.lg),
            // Approval comes from the transition, never from an edit — the
            // detail shows it, it does not offer to set it.
            _FactRow(label: 'Freigegeben von', value: project.approvedBy),
            _FactRow(
              label: 'Freigegeben am',
              value: _formatDate(project.approvedAt),
            ),
            _FactRow(
              label: 'Zuletzt geändert',
              value: _formatDate(project.updatedAt),
            ),
            _FactRow(label: 'Version', value: '${project.version}'),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, CapexProjectDto project) async {
    final changes = await _showProjectEditDialog(context, project);
    if (changes == null) {
      return;
    }
    await controller.updateCapexProject(changes);
  }
}

/// One label/value line. An absent value renders as an em dash rather than
/// disappearing, so the reader can tell "not set" from "not shown".
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String? value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final text = (value == null || value!.trim().isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
              maxLines: multiline ? 6 : 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}

String _formatMoney(double? amount, String? currencyCode) {
  if (amount == null) {
    return '—';
  }
  final text =
      amount == amount.roundToDouble()
          ? amount.toInt().toString()
          : amount.toStringAsFixed(2);
  // DEC-011: an amount without its currency is not a fact anyone can act on.
  return currencyCode == null
      ? text.replaceAll('.', ',')
      : '${text.replaceAll('.', ',')} $currencyCode';
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

/// Edits a ticket's attributes.
///
/// Status is absent on purpose: it only moves through the audited transition
/// contract, and offering it here would be a second, unaudited path to the
/// same column. The update RPC is `coalesce(param, existing)` per field, so a
/// field left untouched is *not* sent — an empty box therefore keeps the
/// stored value rather than clearing it, which is what the contract can do.
Future<MaintenanceTicketUpdateDto?> _showTicketEditDialog(
  BuildContext context,
  MaintenanceTicketDto ticket,
) async {
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController(text: ticket.title);
  final descriptionController = TextEditingController(
    text: ticket.description ?? '',
  );
  final categoryController = TextEditingController(text: ticket.category);
  final damageController = TextEditingController(
    text: ticket.damageLocation ?? '',
  );
  final estimateController = TextEditingController(
    text: ticket.costEstimate?.toString() ?? '',
  );
  final actualController = TextEditingController(
    text: ticket.costActual?.toString() ?? '',
  );
  var priority = ticket.priority;
  var insuranceCase = ticket.insuranceCase;

  String? changed(TextEditingController controller, String? current) {
    final value = controller.text.trim();
    if (value.isEmpty || value == (current ?? '')) {
      return null;
    }
    return value;
  }

  double? changedAmount(TextEditingController controller, double? current) {
    final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return parsed == null || parsed == current ? null : parsed;
  }

  return showDialog<MaintenanceTicketUpdateDto>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (dialogContext, setState) => AlertDialog(
                key: const Key('maintenance-ticket-edit-dialog'),
                title: const Text('Ticket bearbeiten'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextFormField(
                            key: const Key('maintenance-ticket-edit-title'),
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: 'Titel',
                            ),
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
                          TextFormField(
                            controller: categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Kategorie',
                            ),
                          ),
                          TextFormField(
                            controller: damageController,
                            decoration: const InputDecoration(
                              labelText: 'Schadensort',
                            ),
                          ),
                          DropdownButtonFormField<MaintenanceTicketPriority>(
                            value: priority,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Priorität',
                            ),
                            items:
                                <DropdownMenuItem<MaintenanceTicketPriority>>[
                                  for (final p
                                      in MaintenanceTicketPriority.values)
                                    DropdownMenuItem(
                                      value: p,
                                      child: Text(
                                        maintenanceTicketPriorityLabel(p),
                                      ),
                                    ),
                                ],
                            onChanged:
                                (value) => setState(
                                  () => priority = value ?? priority,
                                ),
                          ),
                          TextFormField(
                            controller: estimateController,
                            decoration: const InputDecoration(
                              labelText: 'Kosten geschätzt',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          TextFormField(
                            controller: actualController,
                            decoration: const InputDecoration(
                              labelText: 'Kosten tatsächlich',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Versicherungsfall'),
                            value: insuranceCase,
                            onChanged:
                                (value) =>
                                    setState(() => insuranceCase = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    key: const Key('maintenance-ticket-edit-submit'),
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(
                        MaintenanceTicketUpdateDto(
                          title: changed(titleController, ticket.title),
                          description: changed(
                            descriptionController,
                            ticket.description,
                          ),
                          category: changed(
                            categoryController,
                            ticket.category,
                          ),
                          priority:
                              priority == ticket.priority ? null : priority,
                          costEstimate: changedAmount(
                            estimateController,
                            ticket.costEstimate,
                          ),
                          costActual: changedAmount(
                            actualController,
                            ticket.costActual,
                          ),
                          damageLocation: changed(
                            damageController,
                            ticket.damageLocation,
                          ),
                          insuranceCase:
                              insuranceCase == ticket.insuranceCase
                                  ? null
                                  : insuranceCase,
                        ),
                      );
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
        ),
  );
}

/// Edits a CapEx project's attributes. Status and approval are absent for the
/// same reason as on the ticket: they belong to the transition contract.
Future<CapexProjectUpdateDto?> _showProjectEditDialog(
  BuildContext context,
  CapexProjectDto project,
) async {
  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController(text: project.projectCode);
  final categoryController = TextEditingController(
    text: project.category ?? '',
  );
  final measureController = TextEditingController(text: project.measure ?? '');
  final ownerController = TextEditingController(text: project.owner ?? '');
  final nextStepController = TextEditingController(
    text: project.nextStep ?? '',
  );
  final budgetController = TextEditingController(
    text: project.budgetAmount?.toString() ?? '',
  );
  final forecastController = TextEditingController(
    text: project.forecastAmount?.toString() ?? '',
  );

  String? changed(TextEditingController controller, String? current) {
    final value = controller.text.trim();
    if (value.isEmpty || value == (current ?? '')) {
      return null;
    }
    return value;
  }

  double? changedAmount(TextEditingController controller, double? current) {
    final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return parsed == null || parsed == current ? null : parsed;
  }

  return showDialog<CapexProjectUpdateDto>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          key: const Key('capex-project-edit-dialog'),
          title: const Text('Projekt bearbeiten'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      key: const Key('capex-project-edit-code'),
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Projektcode',
                      ),
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
                      controller: measureController,
                      decoration: const InputDecoration(labelText: 'Maßnahme'),
                      maxLines: 3,
                    ),
                    TextFormField(
                      controller: ownerController,
                      decoration: const InputDecoration(
                        labelText: 'Verantwortlich',
                      ),
                    ),
                    TextFormField(
                      controller: nextStepController,
                      decoration: const InputDecoration(
                        labelText: 'Nächster Schritt',
                      ),
                    ),
                    TextFormField(
                      controller: budgetController,
                      decoration: const InputDecoration(labelText: 'Budget'),
                      keyboardType: TextInputType.number,
                    ),
                    TextFormField(
                      controller: forecastController,
                      decoration: const InputDecoration(labelText: 'Forecast'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('capex-project-edit-submit'),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.of(dialogContext).pop(
                  CapexProjectUpdateDto(
                    projectCode: changed(codeController, project.projectCode),
                    category: changed(categoryController, project.category),
                    measure: changed(measureController, project.measure),
                    owner: changed(ownerController, project.owner),
                    nextStep: changed(nextStepController, project.nextStep),
                    budgetAmount: changedAmount(
                      budgetController,
                      project.budgetAmount,
                    ),
                    forecastAmount: changedAmount(
                      forecastController,
                      project.forecastAmount,
                    ),
                  ),
                );
              },
              child: const Text('Speichern'),
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
