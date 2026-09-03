/// The Notification Inbox (NOTIFICATION-INBOX-01, NOTIFICATIONS-V2): the
/// place where a person learns what concerns them personally and where to
/// jump — an addressed action list, never a workspace activity stream
/// (Shared §4).
///
/// OD-2 governs the surface: exactly two tabs (Ungelesen/Alle over
/// `unreadOnly`), no filter bar, no search, no "Alle als gelesen markieren"
/// and no invented totals — the §17 pretense-regression tests pin the
/// absences. Without `NOTIFICATION-EMITTER-01` the inbox is legitimately
/// empty; the empty-all state says so honestly instead of looking broken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_live_updates_notice.dart';
import '../../../ui/components/nx_split_view.dart';
import '../../../ui/templates/list_filter_template.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/notification_inbox_controller.dart';
import '../domain/notification_dto.dart';
import 'notification_formatting.dart';
import 'notification_kind_labels.dart';
import 'notification_targets.dart';
import 'widgets/entity_ref_chip.dart';
import 'widgets/notification_row.dart';

/// Builds the inbox scope from the authenticated session — shared with the
/// CloudTopBar bell so both surfaces watch the same controller instance.
NotificationInboxScope? notificationInboxScopeOf(ReferenceSliceState state) {
  final access = state.selectedWorkspace;
  if (state.authPhase != ReferenceAuthPhase.authenticated ||
      state.userId == null ||
      access == null) {
    return null;
  }
  return NotificationInboxScope(
    workspaceId: access.workspace.id,
    actorId: state.userId,
    permissions: access.permissions,
    canMutate: state.assuranceLevel == AuthenticationAssuranceLevel.aal2,
  );
}

class NotificationInboxScreen extends ConsumerWidget {
  const NotificationInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(referenceSliceControllerProvider);
    final padding = EdgeInsets.all(context.adaptivePagePadding);
    final scope = notificationInboxScopeOf(reference);

    if (scope == null) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('notification-inbox-idle'),
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Mitteilungen werden nach Anmeldung und Workspace-Auswahl '
              'geladen.',
          icon: Icons.workspaces_outline,
        ),
      );
    }
    // DEC-025: at aal1 the policy returns zero own rows — which must render
    // as this state, never as an empty inbox (§8, pgTAP 027 A6).
    if (!scope.canMutate) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('notification-inbox-aal-required'),
          title: 'Zweiter Faktor erforderlich',
          description:
              'Mitteilungen sind erst nach der Zwei-Faktor-Anmeldung '
              'sichtbar.',
          icon: Icons.shield_outlined,
        ),
      );
    }
    if (!scope.canRead) {
      return Padding(
        padding: padding,
        child: const NxEmptyState(
          key: Key('notification-inbox-forbidden'),
          title: 'Kein Zugriff auf Mitteilungen',
          description:
              'Diese Fläche benötigt die Berechtigung (notification.read).',
          icon: Icons.lock_outline,
        ),
      );
    }

    final state = ref.watch(notificationInboxControllerProvider(scope));
    final controller = ref.read(
      notificationInboxControllerProvider(scope).notifier,
    );

    ref.listen<NotificationInboxState>(
      notificationInboxControllerProvider(scope),
      (previous, next) {
        if (previous?.actionPhase == next.actionPhase) {
          return;
        }
        if (next.actionPhase == NotificationActionPhase.failed ||
            next.actionPhase == NotificationActionPhase.succeeded) {
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        }
      },
    );

    return NotificationInboxView(
      state: state,
      onReload: () => controller.reload(),
      onLoadMore: controller.loadMore,
      onSetTab: (unreadOnly) => controller.setTab(unreadOnly: unreadOnly),
      onSelect: controller.select,
      onCloseDetail: controller.closeDetail,
      onMarkRead: controller.markRead,
      onOpenTarget: (notification, target) {
        // §5: opening the target reads the notification implicitly — whoever
        // jumps has seen it; the check stays for "seen, no action needed".
        controller.markRead(notification);
        Navigator.of(context).pushNamed(target.route);
      },
    );
  }
}

/// Presentation of the inbox, driven by state and callbacks so widget tests
/// pump it without a provider graph.
class NotificationInboxView extends StatelessWidget {
  const NotificationInboxView({
    super.key,
    required this.state,
    required this.onReload,
    required this.onLoadMore,
    required this.onSetTab,
    required this.onSelect,
    required this.onCloseDetail,
    required this.onMarkRead,
    required this.onOpenTarget,
    this.now,
  });

  final NotificationInboxState state;
  final Future<void> Function() onReload;
  final Future<void> Function() onLoadMore;
  final Future<void> Function(bool unreadOnly) onSetTab;
  final void Function(NotificationDto notification) onSelect;
  final VoidCallback onCloseDetail;
  final Future<void> Function(NotificationDto notification) onMarkRead;
  final void Function(NotificationDto notification, NotificationTarget target)
  onOpenTarget;

  /// Injectable clock for deterministic grouping and relative time in tests.
  final DateTime? now;

  DateTime get _now => now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile =
            AppLayout.viewportForWidth(constraints.maxWidth) ==
            AppViewport.mobile;
        return ListFilterTemplate(
          title: 'Mitteilungen',
          breadcrumbs: const <String>['Start', 'Mitteilungen'],
          secondaryActions: [
            OutlinedButton.icon(
              key: const Key('notification-inbox-refresh'),
              onPressed: state.refreshing ? null : onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
          contextBar: _contextBar(context),
          content: _content(context, mobile),
        );
      },
    );
  }

  Widget _contextBar(BuildContext context) {
    final unreadLabel = state.unread.loaded
        ? 'Ungelesen (${state.unreadBadgeLabel})'
        : 'Ungelesen';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.liveUpdatesDegraded) ...[
          const NxLiveUpdatesNotice(
            key: Key('notification-inbox-live-degraded'),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            label: state.unreadBadgeCapped
                ? 'mehr als ${state.unreadBadgeCount} ungelesene Mitteilungen'
                : '${state.unreadBadgeCount} ungelesene Mitteilungen',
            child: SegmentedButton<bool>(
              key: const Key('notification-inbox-tabs'),
              segments: [
                ButtonSegment<bool>(value: true, label: Text(unreadLabel)),
                const ButtonSegment<bool>(value: false, label: Text('Alle')),
              ],
              selected: <bool>{state.unreadOnly},
              onSelectionChanged: (selection) => onSetTab(selection.first),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, bool mobile) {
    final detailOpen = state.selectedId != null;
    // §5: on mobile the tap jumps directly; the split's narrow detail still
    // serves unresolvable targets and tablet viewports.
    return NxSplitView(
      list: _list(context, mobile),
      detail: _detail(context),
      showDetail: detailOpen,
      onBackToList: onCloseDetail,
    );
  }

  Widget _list(BuildContext context, bool mobile) {
    final slice = state.active;
    switch (slice.phase) {
      case NotificationFeedPhase.loading:
        return const NxCard(
          key: Key('notification-inbox-loading'),
          child: NxListSkeleton(rows: 8, rowHeight: 56),
        );
      case NotificationFeedPhase.forbidden:
        return const NxEmptyState(
          key: Key('notification-inbox-forbidden'),
          title: 'Kein Zugriff auf Mitteilungen',
          description:
              'Diese Fläche benötigt die Berechtigung (notification.read).',
          icon: Icons.lock_outline,
        );
      case NotificationFeedPhase.error:
        return NxEmptyState.error(
          key: const Key('notification-inbox-error'),
          description:
              slice.message ?? 'Mitteilungen sind derzeit nicht verfügbar.',
          onRetry: onReload,
        );
      case NotificationFeedPhase.ready:
        break;
    }
    if (slice.items.isEmpty) {
      // §10: an emptied Ungelesen tab is the goal state and reads positive;
      // an empty inbox names the missing emitter honestly.
      return state.unreadOnly
          ? const NxEmptyState(
              key: Key('notification-inbox-empty-unread'),
              title: 'Alles gelesen',
              description: 'Neue Mitteilungen erscheinen hier automatisch.',
              icon: Icons.mark_email_read_outlined,
            )
          : const NxEmptyState(
              key: Key('notification-inbox-empty-all'),
              title: 'Noch keine Mitteilungen.',
              description:
                  'Automatische Hinweise zu Aufgaben und Fristen werden '
                  'serverseitig erzeugt und sind noch nicht aktiv.',
              icon: Icons.notifications_none,
            );
    }
    final entries = _groupedEntries(slice.items);
    return NxCard(
      key: const Key('notification-inbox-ready'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.refreshing)
            const LinearProgressIndicator(
              key: Key('notification-inbox-refreshing'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index](context, mobile),
            ),
          ),
          if (slice.nextCursor != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(
              key: const Key('notification-inbox-partial'),
              child: OutlinedButton.icon(
                key: const Key('notification-inbox-load-more'),
                onPressed: slice.loadingMore ? null : onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(
                  slice.loadingMore ? 'Lädt …' : 'Weitere laden',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the grouped render list: a bucket header whenever the (DESC
  /// ordered) feed crosses a boundary, then its rows. Grouping only orders
  /// what is loaded — it claims no completeness the contract lacks (§4).
  List<Widget Function(BuildContext, bool)> _groupedEntries(
    List<NotificationDto> items,
  ) {
    final entries = <Widget Function(BuildContext, bool)>[];
    NotificationTimeBucket? currentBucket;
    for (final item in items) {
      final bucket = notificationTimeBucket(item.createdAt, now: _now);
      if (bucket != currentBucket) {
        currentBucket = bucket;
        entries.add(
          (context, mobile) => Padding(
            key: Key('notification-inbox-group-${bucket.name}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              notificationTimeBucketLabel(bucket),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        );
      }
      entries.add((context, mobile) {
        final target = notificationTargetFor(item);
        return NotificationRow(
          notification: item,
          now: _now,
          mobile: mobile,
          selected: state.selectedId == item.id,
          onSelect: () => onSelect(item),
          onMarkRead: () => onMarkRead(item),
          onOpenTarget: target == null
              ? null
              : () => onOpenTarget(item, target),
        );
      });
    }
    return entries;
  }

  Widget _detail(BuildContext context) {
    final theme = Theme.of(context);
    if (state.selectedId == null) {
      return const NxEmptyState(
        key: Key('notification-detail-idle'),
        title: 'Wähle eine Mitteilung.',
        description: 'Details erscheinen neben der Liste.',
        icon: Icons.notifications_none,
      );
    }
    final notification = state.selected;
    if (notification == null) {
      return const NxEmptyState(
        key: Key('notification-detail-not-found'),
        title: 'Diese Mitteilung ist nicht mehr verfügbar.',
        description: 'Sie wurde entfernt, während die Liste geöffnet war.',
        icon: Icons.search_off_outlined,
      );
    }
    final kind = notificationKindPresentation(notification.kind);
    final target = notificationTargetFor(notification);
    final openButton = FilledButton.icon(
      key: const Key('notification-detail-open'),
      onPressed: target == null
          ? null
          : () => onOpenTarget(notification, target),
      icon: const Icon(Icons.open_in_new),
      label: const Text('Zum Vorgang öffnen'),
    );
    return NxCard(
      key: const Key('notification-detail'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              label: notificationAbsoluteTime(notification.createdAt),
              child: Row(
                children: [
                  Icon(
                    kind.icon,
                    size: 16,
                    color: context.semanticColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Tooltip(
                      message: isUnknownNotificationKind(notification.kind)
                          ? notification.kind
                          : kind.label,
                      child: Text(
                        '${kind.label} · '
                        '${notificationAbsoluteTime(notification.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (notification.entity != null) ...[
              const SizedBox(height: AppSpacing.component),
              EntityRefChip(entity: notification.entity!),
            ],
            if (notification.body != null &&
                notification.body!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.component),
              Text(notification.body!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                target == null
                    ? Tooltip(
                        key: const Key('notification-target-unavailable'),
                        message: 'Ziel ist noch nicht verfügbar',
                        child: openButton,
                      )
                    : openButton,
                if (notification.readAt == null)
                  OutlinedButton.icon(
                    key: const Key('notification-detail-mark-read'),
                    onPressed: () => onMarkRead(notification),
                    icon: const Icon(Icons.check),
                    label: const Text('Als gelesen markieren'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Gelesen',
                      key: const Key('notification-detail-read'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
