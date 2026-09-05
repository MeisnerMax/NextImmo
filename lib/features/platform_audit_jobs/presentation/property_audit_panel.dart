import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/components/nx_section_header.dart';
import '../../../ui/components/nx_split_view.dart';
import '../../../ui/theme/app_theme.dart';
import '../application/property_audit_controller.dart';
import '../domain/audit_event_dto.dart';

/// `Aktivität → Audit` in the property workspace (AUDIT-01,
/// `PROPERTY_AUDIT_V2.md`): who changed what on this property, when, and why.
///
/// The surface is deliberately plain, because an audit trail earns trust by
/// being literal. It renders exactly what the read port published — including
/// the fact that a change is reported by **field name**, never by value — and
/// it never renders raw JSON. Where the server sent nothing, the row says so
/// rather than filling the gap.
class PropertyAuditPanel extends ConsumerWidget {
  const PropertyAuditPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = propertyAuditControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return NxSplitView(
      list: _AuditList(state: state, controller: controller),
      detail: _AuditDetail(event: state.selectedEvent),
      showDetail: state.selectedEventId != null,
      onBackToList: () => controller.select(null),
      backLabel: 'Zur Ereignisliste',
    );
  }
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.state, required this.controller});

  final PropertyAuditState state;
  final PropertyAuditController controller;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case PropertyAuditPhase.idle:
      case PropertyAuditPhase.loading:
        return const NxListSkeleton(key: Key('property-audit-skeleton'));
      case PropertyAuditPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-audit-forbidden'),
          title: 'Kein Zugriff auf das Protokoll',
          description:
              'Das Protokoll benötigt die Berechtigung (audit.read) und '
              'Zugriff auf dieses Objekt.',
          icon: Icons.lock_outline,
        );
      case PropertyAuditPhase.error:
        return NxEmptyState.error(
          key: const Key('property-audit-error'),
          title: 'Protokoll konnte nicht geladen werden',
          description:
              state.message ??
              'Die Verbindung zur Datenquelle ist '
                  'fehlgeschlagen.',
          onRetry: () => unawaited(controller.load()),
        );
      case PropertyAuditPhase.empty:
        return const NxEmptyState(
          key: Key('property-audit-empty'),
          title: 'Noch keine Ereignisse',
          description:
              'Für dieses Objekt wurde noch keine protokollierte Änderung '
              'aufgezeichnet.',
          icon: Icons.history_outlined,
        );
      case PropertyAuditPhase.ready:
        return _events(context);
    }
  }

  Widget _events(BuildContext context) {
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
    return ListView.builder(
      key: const Key('property-audit-list'),
      itemCount: state.events.length + (state.hasMore ? 1 : 0) + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // The scope of what is shown, stated once at the top: this is the
          // property's trail, not the workspace's.
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Änderungen an diesem Objekt und seinen Datensätzen, '
                  'neueste zuerst.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
                if (state.loadMoreMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  NxNotice(
                    key: const Key('property-audit-load-more-error'),
                    kind: NxNoticeKind.warning,
                    message:
                        'Weitere Ereignisse konnten nicht geladen werden. '
                        'Die bereits geladenen bleiben sichtbar.',
                    action: TextButton(
                      onPressed: () => unawaited(controller.loadMore()),
                      child: const Text('Erneut versuchen'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        final eventIndex = index - 1;
        if (eventIndex >= state.events.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: OutlinedButton.icon(
              key: const Key('property-audit-load-more'),
              onPressed:
                  state.loadingMore
                      ? null
                      : () => unawaited(controller.loadMore()),
              icon:
                  state.loadingMore
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.expand_more),
              label: Text(
                state.loadingMore ? 'Lädt …' : 'Weitere Ereignisse laden',
              ),
            ),
          );
        }
        final event = state.events[eventIndex];
        return ListTile(
          key: Key('property-audit-event-${event.id}'),
          selected: event.id == state.selectedEventId,
          onTap: () => controller.select(event.id),
          title: Text(
            auditActionLabel(event.action),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${formatAuditTimestamp(event.occurredAt)} · '
            '${auditActorLabel(event)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            auditEntityLabel(event.entityType),
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
        );
      },
    );
  }
}

class _AuditDetail extends StatelessWidget {
  const _AuditDetail({required this.event});

  final AuditEventDto? event;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    if (event == null) {
      return const NxEmptyState(
        key: Key('property-audit-detail-idle'),
        title: 'Kein Ereignis ausgewählt',
        description:
            'Wähle ein Ereignis aus der Liste, um Actor, Zeitpunkt und '
            'geänderte Felder zu sehen.',
        icon: Icons.history_outlined,
      );
    }
    return SingleChildScrollView(
      key: const Key('property-audit-detail'),
      child: NxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NxSectionHeader(
              title: auditActionLabel(event.action),
              compact: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _Fact(
              label: 'Zeitpunkt',
              value: formatAuditTimestamp(event.occurredAt),
            ),
            _Fact(label: 'Ausgelöst von', value: auditActorLabel(event)),
            _Fact(label: 'Rolle zum Zeitpunkt', value: event.roleKey),
            _Fact(
              label: 'Betroffener Datensatz',
              value: auditEntityLabel(event.entityType),
            ),
            _Fact(label: 'Datensatz-ID', value: event.entityId),
            if (event.parentEntityId != null)
              _Fact(
                label: 'Gehört zu',
                value:
                    '${auditEntityLabel(event.parentEntityType ?? '')} '
                    '${event.parentEntityId}',
              ),
            _Fact(label: 'Grund', value: event.reason),
            const Divider(height: AppSpacing.lg),
            _ChangedFields(fields: event.changedFields),
            const Divider(height: AppSpacing.lg),
            _Fact(label: 'Quelle', value: event.source),
            _Fact(label: 'Vorgangs-ID', value: event.correlationId),
            _Fact(label: 'Mutations-ID', value: event.mutationId),
          ],
        ),
      ),
    );
  }
}

class _ChangedFields extends StatelessWidget {
  const _ChangedFields({required this.fields});

  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Geänderte Felder', style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        if (fields.isEmpty)
          Text(
            'Dieses Ereignis hat kein Feld verändert.',
            key: const Key('property-audit-no-fields'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          )
        else ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final field in fields)
                Chip(
                  key: Key('property-audit-field-$field'),
                  label: Text(field),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Said plainly, because a reader who expects before/after values
          // should learn why they are absent rather than assume a bug.
          Text(
            'Das Protokoll führt, welches Feld geändert wurde — nicht auf '
            'welchen Wert.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              (value == null || value!.trim().isEmpty) ? '—' : value!,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

/// German label for a server action key. An unmapped key is shown as the key
/// itself: a new server event must stay visible in the trail, and an audit
/// entry that silently disappears is worse than an untranslated one.
String auditActionLabel(String action) {
  return switch (action) {
    'property.created' => 'Objekt angelegt',
    'property.updated' => 'Objekt geändert',
    'property.archived' => 'Objekt archiviert',
    'property.restored' => 'Objekt wiederhergestellt',
    'unit.created' => 'Fläche angelegt',
    'unit.updated' => 'Fläche geändert',
    'lease.created' => 'Vertrag angelegt',
    'lease.updated' => 'Vertrag geändert',
    'maintenance_ticket.created' => 'Ticket angelegt',
    'maintenance_ticket.updated' => 'Ticket geändert',
    'capex_project.created' => 'CapEx-Projekt angelegt',
    'capex_project.updated' => 'CapEx-Projekt geändert',
    'document.created' => 'Dokument angelegt',
    'valuation_case.created' => 'Bewertung angelegt',
    'valuation_case.updated' => 'Bewertung geändert',
    _ => action,
  };
}

String auditEntityLabel(String entityType) {
  return switch (entityType) {
    'property' => 'Objekt',
    'unit' => 'Fläche',
    'lease' => 'Vertrag',
    'maintenance_ticket' => 'Wartungsticket',
    'capex_project' => 'CapEx-Projekt',
    'document' => 'Dokument',
    'valuation_case' => 'Bewertung',
    'task' => 'Aufgabe',
    '' => '—',
    _ => entityType,
  };
}

/// Who acted. A person is named by their user id until a directory read exists
/// to resolve display names; inventing one here would be worse than an id.
String auditActorLabel(AuditEventDto event) {
  return switch (event.actorType) {
    AuditActorType.user => event.actorUserId ?? 'Unbekannter Nutzer',
    AuditActorType.service => 'Dienst: ${event.actorIdentifier ?? 'unbenannt'}',
    AuditActorType.system => 'System: ${event.actorIdentifier ?? 'Plattform'}',
  };
}

String formatAuditTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
