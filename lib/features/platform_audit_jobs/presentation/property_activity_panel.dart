/// `Aktivität → Aktivität` in the property workspace (PROPERTY-ACTIVITY-01,
/// `PROPERTY_ACTIVITY_V2.md`): a readable chronicle of what happened to this
/// property, grouped by day, newest first.
///
/// The sibling `Protokoll` surface is the forensic trail and reads like one.
/// This one reads like a history: one sentence per event, the domain it came
/// from, the time, and a drilldown to the record. It has no split view because
/// the detail is the source record in its own domain, not a payload to inspect
/// here.
///
/// Two rules it enforces at the render layer:
///
///   * **A partial timeline says so.** The server names the domains this
///     membership covers; where that is fewer than all of them, the coverage
///     line lists them. It never reports how many events were withheld,
///     because a count of records someone else may read is still a
///     disclosure — and there is no such number in the payload to render.
///   * **An unknown event is shown, not dropped.** A server key this build has
///     no sentence for is rendered as the key. A newer server is then visible
///     as "something happened here that this app cannot name yet", which is
///     the honest reading; silently skipping the row would make the history
///     look complete when it is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/theme/app_theme.dart';
import '../../portfolio_property/presentation/property_presentation.dart';
import '../application/property_activity_controller.dart';
import '../domain/property_activity_dto.dart';

/// German label for a workspace domain, matching the workspace navigation so
/// a filter chip and the area it filters read the same.
String propertyActivityDomainLabel(PropertyActivityDomain domain) {
  return switch (domain) {
    PropertyActivityDomain.property => 'Objekt',
    PropertyActivityDomain.leasing => 'Vermietung',
    PropertyActivityDomain.maintenance => 'Wartung',
    PropertyActivityDomain.capex => 'CapEx',
    PropertyActivityDomain.tasks => 'Aufgaben',
    PropertyActivityDomain.documents => 'Dokumente',
    PropertyActivityDomain.valuation => 'Bewertung',
  };
}

IconData propertyActivityDomainIcon(PropertyActivityDomain domain) {
  return switch (domain) {
    PropertyActivityDomain.property => Icons.apartment_outlined,
    PropertyActivityDomain.leasing => Icons.assignment_outlined,
    PropertyActivityDomain.maintenance => Icons.build_outlined,
    PropertyActivityDomain.capex => Icons.construction_outlined,
    PropertyActivityDomain.tasks => Icons.checklist_outlined,
    PropertyActivityDomain.documents => Icons.folder_outlined,
    PropertyActivityDomain.valuation => Icons.insights_outlined,
  };
}

/// The record kind, in the words the rest of the product uses for it.
String _entityLabel(String entityType) {
  return switch (entityType) {
    'property' => 'Objekt',
    'property_media' => 'Objektbild',
    'unit' => 'Fläche',
    'lease' => 'Vertrag',
    'leasing_case' => 'Vermietungsfall',
    'rent_roll_snapshot' => 'Rent-Roll-Snapshot',
    'maintenance_ticket' => 'Wartungsticket',
    'capex_project' => 'CapEx-Projekt',
    'task' => 'Aufgabe',
    'document' => 'Dokument',
    'document_version' => 'Dokumentversion',
    'document_link' => 'Dokumentverknüpfung',
    'required_document' => 'Dokumentanforderung',
    'valuation_case' => 'Bewertungsfall',
    _ => entityType,
  };
}

/// What happened, as a verb. An action this build does not know keeps its
/// server word rather than becoming a vague "geändert" that hides a delete.
String _actionLabel(String action) {
  return switch (action) {
    'create' => 'angelegt',
    'update' => 'geändert',
    'transition' => 'im Status geändert',
    'archive' => 'archiviert',
    'restore' => 'wiederhergestellt',
    'delete' => 'entfernt',
    'verify' => 'geprüft',
    'waive' => 'als verzichtet markiert',
    'link' => 'verknüpft',
    'unlink' => 'entkoppelt',
    _ => action,
  };
}

/// The sentence for one event. Falls back to the raw event key, so an
/// unmapped server event is visible instead of missing.
String propertyActivitySentence(PropertyActivityEventDto event) {
  final entity = _entityLabel(event.entityType);
  final verb = _actionLabel(event.action);
  if (entity == event.entityType && verb == event.action) {
    return event.eventKey;
  }
  return '$entity $verb';
}

class PropertyActivityPanel extends ConsumerWidget {
  const PropertyActivityPanel({
    super.key,
    required this.propertyId,
    this.onOpenRecord,
  });

  final String propertyId;

  /// Opens the source record. Null leaves rows non-interactive: a row that
  /// looks clickable and does nothing is worse than a plain one.
  final void Function(PropertyActivityEventDto event)? onOpenRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = propertyActivityControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    switch (state.phase) {
      case PropertyActivityPhase.idle:
        return const SizedBox.shrink();
      case PropertyActivityPhase.loading:
        return const SingleChildScrollView(
          key: Key('property-activity-skeleton'),
          padding: EdgeInsets.all(AppSpacing.component),
          child: NxListSkeleton(rows: 6),
        );
      case PropertyActivityPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-activity-forbidden'),
          title: 'Kein Zugriff auf die Aktivität',
          description:
              'Die Aktivität benötigt die Berechtigung (property.read) für '
              'dieses Objekt.',
          icon: Icons.lock_outline,
        );
      case PropertyActivityPhase.error:
        return NxEmptyState.error(
          key: const Key('property-activity-error'),
          title: 'Aktivität konnte nicht geladen werden',
          description:
              state.message ?? 'Die Aktivität ist derzeit nicht verfügbar.',
          onRetry: controller.load,
        );
      case PropertyActivityPhase.empty:
      case PropertyActivityPhase.noMatch:
      case PropertyActivityPhase.ready:
        return _Timeline(
          state: state,
          controller: controller,
          onOpenRecord: onOpenRecord,
        );
    }
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.state,
    required this.controller,
    required this.onOpenRecord,
  });

  final PropertyActivityState state;
  final PropertyActivityController controller;
  final void Function(PropertyActivityEventDto event)? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDay(state.events);
    return ListView(
      key: const Key('property-activity'),
      padding: const EdgeInsets.all(AppSpacing.component),
      children: [
        _FilterBar(state: state, controller: controller),
        const SizedBox(height: AppSpacing.component),
        _CoverageLine(state: state),
        if (state.phase == PropertyActivityPhase.empty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.component),
            child: NxEmptyState(
              key: Key('property-activity-empty'),
              title: 'Noch keine Aktivität',
              description:
                  'Für dieses Objekt wurde in den lesbaren Bereichen noch '
                  'nichts verzeichnet.',
              icon: Icons.history_outlined,
            ),
          )
        else if (state.phase == PropertyActivityPhase.noMatch)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.component),
            child: NxEmptyState(
              key: const Key('property-activity-no-match'),
              title: 'Keine Ereignisse in dieser Auswahl',
              description:
                  'Mit den gewählten Bereichen wurde nichts gefunden. Die '
                  'Auswahl lässt sich zurücksetzen.',
              icon: Icons.filter_alt_off_outlined,
              primaryAction: FilledButton.icon(
                key: const Key('property-activity-clear-filter'),
                onPressed: controller.clearFilter,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Auswahl zurücksetzen'),
              ),
            ),
          )
        else
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.component,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                group.label,
                key: Key('property-activity-day-${group.key}'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final event in group.events)
              _ActivityRow(
                event: event,
                actorNamesVisible: state.actorNamesVisible,
                onOpen: onOpenRecord == null
                    ? null
                    : () => onOpenRecord!(event),
              ),
          ],
        if (state.hasMore) ...[
          const SizedBox(height: AppSpacing.component),
          if (state.loadMoreMessage != null) ...[
            NxNotice(
              key: const Key('property-activity-load-more-error'),
              kind: NxNoticeKind.warning,
              icon: Icons.error_outline,
              title: 'Weitere Ereignisse konnten nicht geladen werden',
              message: state.loadMoreMessage!,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Center(
            child: TextButton(
              key: const Key('property-activity-load-more'),
              onPressed: state.loadingMore ? null : controller.loadMore,
              child: Text(
                state.loadingMore ? 'Wird geladen …' : 'Weitere anzeigen',
              ),
            ),
          ),
        ],
      ],
    );
  }

  static List<_DayGroup> _groupByDay(List<PropertyActivityEventDto> events) {
    final groups = <_DayGroup>[];
    for (final event in events) {
      final local = event.occurredAt.toLocal();
      final key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      if (groups.isNotEmpty && groups.last.key == key) {
        groups.last.events.add(event);
      } else {
        groups.add(
          _DayGroup(
            key: key,
            label:
                '${local.day.toString().padLeft(2, '0')}.'
                '${local.month.toString().padLeft(2, '0')}.${local.year}',
            events: <PropertyActivityEventDto>[event],
          ),
        );
      }
    }
    return groups;
  }
}

class _DayGroup {
  _DayGroup({required this.key, required this.label, required this.events});

  final String key;
  final String label;
  final List<PropertyActivityEventDto> events;
}

/// Chips for the domains the caller can actually see. A chip for a domain the
/// server would return nothing for is a promise the timeline cannot keep.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.controller});

  final PropertyActivityState state;
  final PropertyActivityController controller;

  @override
  Widget build(BuildContext context) {
    final domains =
        PropertyActivityDomain.values
            .where(state.visibleDomains.contains)
            .toList(growable: false);
    if (domains.length < 2) {
      // One domain is not a choice.
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      label: 'Bereiche filtern',
      child: SingleChildScrollView(
        key: const Key('property-activity-filter'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(
              key: const Key('property-activity-filter-all'),
              label: const Text('Alle'),
              selected: !state.isFiltered,
              onSelected: (_) => controller.clearFilter(),
            ),
            for (final domain in domains) ...[
              const SizedBox(width: AppSpacing.xs),
              FilterChip(
                key: Key(
                  'property-activity-filter-'
                  '${propertyActivityDomainToWire(domain)}',
                ),
                label: Text(propertyActivityDomainLabel(domain)),
                selected: state.selectedDomains.contains(domain),
                onSelected: (_) => controller.toggleDomain(domain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `Stand` plus, where the caller sees fewer domains than exist, which ones.
class _CoverageLine extends StatelessWidget {
  const _CoverageLine({required this.state});

  final PropertyActivityState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asOf = state.asOf;
    final covered = PropertyActivityDomain.values
        .where(state.visibleDomains.contains)
        .map(propertyActivityDomainLabel)
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (asOf != null)
          Text(
            'Stand: ${formatPropertyTimestamp(asOf)}',
            key: const Key('property-activity-as-of'),
            style: theme.textTheme.bodySmall,
          ),
        if (state.coverageIsPartial)
          Text(
            covered.isEmpty
                ? 'Diese Chronik deckt derzeit keinen Bereich ab.'
                : 'Diese Chronik deckt die Bereiche ab, die Sie lesen dürfen: '
                      '$covered.',
            key: const Key('property-activity-coverage'),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.event,
    required this.actorNamesVisible,
    required this.onOpen,
  });

  final PropertyActivityEventDto event;
  final bool actorNamesVisible;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domain = event.domain;
    final local = event.occurredAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final sentence = propertyActivitySentence(event);
    final actor = _actorLine(event, actorNamesVisible);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The icon is never the only signal: the domain name is in the
          // metadata line right beside it.
          Icon(
            domain == null
                ? Icons.help_outline
                : propertyActivityDomainIcon(domain),
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sentence, style: theme.textTheme.bodyMedium),
                Text(
                  <String>[
                    time,
                    domain == null
                        ? (event.domainKey ?? 'Unbekannter Bereich')
                        : propertyActivityDomainLabel(domain),
                    if (actor != null) actor,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onOpen != null)
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    return Semantics(
      key: Key('property-activity-event-${event.id}'),
      container: true,
      button: onOpen != null,
      label: '$sentence, $time${actor == null ? '' : ', $actor'}',
      child: onOpen == null
          ? row
          : InkWell(onTap: onOpen, child: row),
    );
  }

  /// Who did it, only as far as the server allowed. "Sie" needs no permission;
  /// naming somebody else does, and when it was withheld the row says the
  /// change was made by a member rather than pretending it had no author.
  static String? _actorLine(PropertyActivityEventDto event, bool namesVisible) {
    if (event.actorIsSelf) {
      return 'durch Sie';
    }
    return switch (event.actorType) {
      AuditActorType.system => 'automatisch',
      AuditActorType.service => 'durch einen Dienst',
      AuditActorType.user =>
        namesVisible && event.actorUserId != null
            ? 'durch ${event.actorUserId}'
            : 'durch ein Mitglied',
    };
  }
}
