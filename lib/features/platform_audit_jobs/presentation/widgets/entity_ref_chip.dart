import 'package:flutter/material.dart';

import '../../domain/platform_entity_type.dart';

/// German type labels of the nine registry values (`task_center.md` §6.6).
String platformEntityTypeLabel(PlatformEntityType type) {
  return switch (type) {
    PlatformEntityType.workspace => 'Workspace',
    PlatformEntityType.property => 'Objekt',
    PlatformEntityType.portfolio => 'Portfolio',
    PlatformEntityType.unit => 'Einheit',
    PlatformEntityType.lease => 'Vertrag',
    PlatformEntityType.party => 'Partei',
    PlatformEntityType.maintenanceTicket => 'Ticket',
    PlatformEntityType.capexProject => 'CapEx-Projekt',
    PlatformEntityType.scenario => 'Szenario',
    PlatformEntityType.task => 'Aufgabe',
  };
}

/// The one rendering of a [PlatformEntityRef] (Shared §13, candidate
/// `SHARED-UI-ENTITYREF-01`): until `TASK-QUERY-01` delivers the
/// `search_index` name resolution it shows the **type label and nothing
/// else** — never a raw UUID, never an invented name. [onOpen] is set only
/// where an id-addressed route exists today (the property workspace).
class EntityRefChip extends StatelessWidget {
  const EntityRefChip({super.key, required this.entity, this.onOpen});

  final PlatformEntityRef entity;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final label = platformEntityTypeLabel(entity.type);
    final chip = Chip(
      avatar: Icon(
        switch (entity.type) {
          PlatformEntityType.property => Icons.home_work_outlined,
          PlatformEntityType.unit => Icons.meeting_room_outlined,
          PlatformEntityType.lease => Icons.assignment_outlined,
          PlatformEntityType.party => Icons.person_outline,
          PlatformEntityType.maintenanceTicket => Icons.build_outlined,
          PlatformEntityType.capexProject => Icons.construction_outlined,
          PlatformEntityType.portfolio => Icons.account_tree_outlined,
          PlatformEntityType.scenario => Icons.calculate_outlined,
          PlatformEntityType.task => Icons.task_alt_outlined,
          PlatformEntityType.workspace => Icons.workspaces_outline,
        },
        size: 16,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
    if (onOpen == null) {
      return chip;
    }
    return Tooltip(
      message: '$label öffnen',
      child: InkWell(onTap: onOpen, child: chip),
    );
  }
}
