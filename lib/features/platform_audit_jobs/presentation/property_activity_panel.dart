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
    // The chronicle carries bookings only. Opening or closing a period is a
    // workspace act with no property, so it is not here to be labelled.
    PropertyActivityDomain.finance => 'Finanzen',
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
    PropertyActivityDomain.finance => Icons.account_balance_outlined,
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
    'finance_ledger_entry' => 'Buchung',
    'lease_component' => 'Mietbestandteil',
    _ => entityType,
  };
}

/// The verb, resolved from the pair the server actually sends.
///
/// `audit_events.action` follows no single convention and never has. Most
/// writers store an action already qualified with the entity — `lease.create`,
/// `maintenance_ticket.transition_status` — while the FINANCE-01 family stores
/// bare verbs (`create`, `transition`). A build that maps bare verbs only, as
/// this one did, therefore matched nothing the chronicle actually delivers:
/// every row rendered as "Vertrag lease.transition_status".
///
/// So the entity's own prefix is stripped first, and only then mapped. The
/// strip is an exact `<entity_type>.` match, not "everything up to the first
/// dot": three actions in this schema carry a prefix that is *not* their
/// entity type (`security.role_catalog_seeded` on `role_catalog`,
/// `notification.fan_out` on `notification_batch`,
/// `operations_signal.update_status` on `operations_signal_state`), and a
/// naive cut would turn them into words that read like verbs but are not. It
/// would also collapse `membership.invite` and `membership_invitation.invite`
/// onto the same key.
///
/// The parameter list takes the pair, not just the remainder, so a verb that
/// one day means something different for two entity types has a place to say
/// so. Today none does — every remainder below means the same thing wherever
/// it appears — and inventing that machinery before it is needed would only
/// add a lookup nobody reads.
///
/// Returns null for an action this build cannot name. The caller shows the key
/// rather than guessing: a vague "geändert" would hide a delete.
String? propertyActivityVerb(String entityType, String action) {
  final prefix = '$entityType.';
  final bare = action.startsWith(prefix)
      ? action.substring(prefix.length)
      : action;
  return switch (bare) {
    'create' => 'angelegt',
    'update' => 'geändert',
    'updated' => 'geändert',
    'registered' => 'hinzugefügt',
    'add' => 'hinzugefügt',
    'delete' => 'entfernt',
    'archive' => 'archiviert',
    'archived' => 'archiviert',
    'restore' => 'wiederhergestellt',
    'retire' => 'stillgelegt',
    // LEASING-COMPONENTS-01 ends a component instead of deleting it, and
    // says so with its own action rather than reusing `update`.
    'close' => 'beendet',
    'supersede' => 'ersetzt',
    // Three spellings for the same event, from three domains that each chose
    // their own word for it.
    'transition' => 'im Status geändert',
    'transition_status' => 'im Status geändert',
    'status_changed' => 'im Status geändert',
    'verify' => 'geprüft',
    'reject' => 'zurückgewiesen',
    'waive' => 'als verzichtet markiert',
    'content_confirmed' => 'inhaltlich bestätigt',
    'content_rejected' => 'inhaltlich zurückgewiesen',
    'link' => 'verknüpft',
    'unlink' => 'entkoppelt',
    'generation_deduplicated' => 'als Dublette übersprungen',
    'factors_upsert' => 'mit neuen Faktoren gespeichert',
    'variant_create' => 'um eine Variante ergänzt',
    // `valuation_case.<status>` is built by concatenating the target status
    // onto the entity name, so the enum's four values arrive here as verbs.
    'draft' => 'auf Entwurf zurückgesetzt',
    'in_review' => 'zur Prüfung gestellt',
    'approved' => 'freigegeben',
    _ => null,
  };
}

/// The server's composite key for one event, without the doubled prefix.
///
/// `public.property_activity` publishes `event_key` as
/// `entity_type || '.' || action`, which for an already-qualified action
/// yields `lease.lease.transition_status`. Rather than render that, the key is
/// derived here from the two fields it is built from — both of which travel on
/// every row — so this build is correct against the server as it is today and
/// as it will be once the projection is fixed.
String propertyActivityEventKey(PropertyActivityEventDto event) {
  return event.action.contains('.')
      ? event.action
      : '${event.entityType}.${event.action}';
}

/// The sentence for one event.
///
/// Either half missing falls back to the whole key. A half-translated
/// "Vertrag lease.transition_status" is worse than the key it replaces: it
/// reads as a rendering fault rather than as an event this build cannot name
/// yet, which is what it actually is.
String propertyActivitySentence(PropertyActivityEventDto event) {
  final verb = propertyActivityVerb(event.entityType, event.action);
  final entity = _entityLabel(event.entityType);
  if (verb == null || entity == event.entityType) {
    return propertyActivityEventKey(event);
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
    // A domain key this build has no label for is still coverage the reader
    // has. `unknownDomainKeys` is documented as being surfaced for exactly
    // that reason, and until now it was collected and then dropped: a newer
    // server's area vanished from the line that claims to list them all.
    final unnamed = state.unknownDomainKeys;
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
            _coverageLine(covered, unnamed),
            key: const Key('property-activity-coverage'),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// The coverage sentence.
///
/// Names the areas this build can label, and then names the server's own keys
/// for any it cannot. Both halves are coverage; reporting only the first would
/// understate what the reader is seeing, which is the same failure as
/// overstating it.
String _coverageLine(String covered, List<String> unnamed) {
  final buffer = StringBuffer();
  if (covered.isEmpty) {
    buffer.write('Diese Chronik deckt derzeit keinen benannten Bereich ab.');
  } else {
    buffer.write(
      'Diese Chronik deckt die Bereiche ab, die Sie lesen dürfen: $covered.',
    );
  }
  if (unnamed.isNotEmpty) {
    buffer.write(
      unnamed.length == 1
          ? ' Hinzu kommt ein Bereich, den diese App-Version noch nicht '
                'benennen kann: ${unnamed.single}.'
          : ' Hinzu kommen Bereiche, die diese App-Version noch nicht '
                'benennen kann: ${unnamed.join(', ')}.',
    );
  }
  return buffer.toString();
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
