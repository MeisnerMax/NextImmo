/// The single status vocabulary for the `maintenance_capex` domain
/// (`03_design_system.md`: one badge mapping per status enum, never a
/// per-screen chip). Every Welle-4 surface — the workspace-wide ticket list,
/// the property-scoped ticket/CapEx panel — renders `MaintenanceTicketStatus`,
/// `MaintenanceTicketPriority` and `CapexProjectStatus` through these helpers.
library;

import 'package:flutter/material.dart';

import '../../../../features/maintenance_capex/domain/capex_project_dto.dart';
import '../../../../features/maintenance_capex/domain/maintenance_ticket_dto.dart';
import '../../../components/nx_status_badge.dart';

String maintenanceTicketStatusLabel(MaintenanceTicketStatus status) {
  return switch (status) {
    MaintenanceTicketStatus.newTicket => 'Neu',
    MaintenanceTicketStatus.triage => 'Sichtung',
    MaintenanceTicketStatus.quoteRequested => 'Angebot angefragt',
    MaintenanceTicketStatus.commissioned => 'Beauftragt',
    MaintenanceTicketStatus.scheduled => 'Terminiert',
    MaintenanceTicketStatus.inProgress => 'In Bearbeitung',
    MaintenanceTicketStatus.waiting => 'Wartet',
    MaintenanceTicketStatus.resolved => 'Erledigt',
    MaintenanceTicketStatus.invoiced => 'Abgerechnet',
    MaintenanceTicketStatus.archived => 'Archiviert',
  };
}

class MaintenanceTicketStatusBadge extends StatelessWidget {
  const MaintenanceTicketStatusBadge({super.key, required this.status});

  final MaintenanceTicketStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: maintenanceTicketStatusLabel(status),
      kind: switch (status) {
        MaintenanceTicketStatus.newTicket => NxBadgeKind.info,
        MaintenanceTicketStatus.triage ||
        MaintenanceTicketStatus.quoteRequested ||
        MaintenanceTicketStatus.commissioned ||
        MaintenanceTicketStatus.scheduled => NxBadgeKind.neutral,
        MaintenanceTicketStatus.inProgress => NxBadgeKind.info,
        MaintenanceTicketStatus.waiting => NxBadgeKind.warning,
        MaintenanceTicketStatus.resolved ||
        MaintenanceTicketStatus.invoiced => NxBadgeKind.success,
        MaintenanceTicketStatus.archived => NxBadgeKind.neutral,
      },
    );
  }
}

String maintenanceTicketPriorityLabel(MaintenanceTicketPriority priority) {
  return switch (priority) {
    MaintenanceTicketPriority.low => 'Niedrig',
    MaintenanceTicketPriority.normal => 'Normal',
    MaintenanceTicketPriority.high => 'Hoch',
    MaintenanceTicketPriority.urgent => 'Dringend',
  };
}

class MaintenanceTicketPriorityBadge extends StatelessWidget {
  const MaintenanceTicketPriorityBadge({super.key, required this.priority});

  final MaintenanceTicketPriority priority;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: maintenanceTicketPriorityLabel(priority),
      kind: switch (priority) {
        MaintenanceTicketPriority.low => NxBadgeKind.neutral,
        MaintenanceTicketPriority.normal => NxBadgeKind.info,
        MaintenanceTicketPriority.high => NxBadgeKind.warning,
        MaintenanceTicketPriority.urgent => NxBadgeKind.error,
      },
    );
  }
}

String capexProjectStatusLabel(CapexProjectStatus status) {
  return switch (status) {
    CapexProjectStatus.idea => 'Idee',
    CapexProjectStatus.planned => 'Geplant',
    CapexProjectStatus.quoteRequested => 'Angebot angefragt',
    CapexProjectStatus.approved => 'Freigegeben',
    CapexProjectStatus.inProgress => 'In Umsetzung',
    CapexProjectStatus.completed => 'Abgeschlossen',
    CapexProjectStatus.invoiced => 'Abgerechnet',
    CapexProjectStatus.archived => 'Archiviert',
  };
}

class CapexProjectStatusBadge extends StatelessWidget {
  const CapexProjectStatusBadge({super.key, required this.status});

  final CapexProjectStatus status;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: capexProjectStatusLabel(status),
      kind: switch (status) {
        CapexProjectStatus.idea ||
        CapexProjectStatus.planned ||
        CapexProjectStatus.quoteRequested => NxBadgeKind.neutral,
        CapexProjectStatus.approved || CapexProjectStatus.inProgress =>
          NxBadgeKind.info,
        CapexProjectStatus.completed ||
        CapexProjectStatus.invoiced => NxBadgeKind.success,
        CapexProjectStatus.archived => NxBadgeKind.neutral,
      },
    );
  }
}
