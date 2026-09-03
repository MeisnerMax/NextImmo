import 'package:flutter/material.dart';

import '../../../../ui/theme/app_theme.dart';
import '../../domain/notification_dto.dart';
import '../notification_formatting.dart';
import '../notification_kind_labels.dart';
import 'entity_ref_chip.dart';

/// One inbox row (§5): unread is triple-coded (dot, weight, semantics), the
/// kind renders as its German label (raw wire only in a tooltip for unknown
/// kinds), time is relative with an absolute screenreader label — never a
/// raw id, never ISO-8601.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.notification,
    required this.now,
    required this.onSelect,
    required this.onMarkRead,
    this.onOpenTarget,
    this.selected = false,
    this.mobile = false,
  });

  final NotificationDto notification;
  final DateTime now;
  final VoidCallback onSelect;
  final VoidCallback onMarkRead;

  /// Set when §9 resolves a target; null renders the disabled "Öffnen"
  /// (`notification-target-unavailable`).
  final VoidCallback? onOpenTarget;
  final bool selected;

  /// Mobile (§5): ListTile with chevron, tap jumps directly (or opens the
  /// detail when the target is unresolvable), body inline with two lines.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = notification.readAt == null;
    final kind = notificationKindPresentation(notification.kind);
    final metaParts = <String>[
      kind.label,
      if (notification.entity != null)
        platformEntityTypeLabel(notification.entity!.type),
      notificationRelativeTime(notification.createdAt, now: now),
    ];
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    final timeSemantics = notificationAbsoluteTime(notification.createdAt);

    if (mobile) {
      return ListTile(
        key: Key('notification-mobile-row-${notification.id}'),
        selected: selected,
        onTap: onOpenTarget ?? onSelect,
        leading: _UnreadDot(unread: unread),
        title: Text(
          notification.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body != null &&
                notification.body!.trim().isNotEmpty)
              Text(
                notification.body!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            Semantics(
              label: timeSemantics,
              child: Text(
                metaParts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              IconButton(
                key: Key('notification-mark-read-${notification.id}'),
                tooltip: 'Als gelesen markieren: ${notification.title}',
                onPressed: onMarkRead,
                icon: const Icon(Icons.check),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }

    return InkWell(
      key: Key('notification-row-${notification.id}'),
      onTap: onSelect,
      borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _UnreadDot(unread: unread),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 2),
                  Semantics(
                    label: timeSemantics,
                    child: Row(
                      children: [
                        Icon(
                          kind.icon,
                          size: 14,
                          color: context.semanticColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Tooltip(
                            message: isUnknownNotificationKind(
                              notification.kind,
                            )
                                ? notification.kind
                                : kind.label,
                            child: Text(
                              metaParts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: Key('notification-open-${notification.id}'),
              onPressed: onOpenTarget,
              child: onOpenTarget == null
                  ? Tooltip(
                      key: Key(
                        'notification-target-unavailable-${notification.id}',
                      ),
                      message: 'Ziel ist noch nicht verfügbar',
                      child: const Text('Öffnen'),
                    )
                  : const Text('Öffnen'),
            ),
            if (unread)
              IconButton(
                key: Key('notification-mark-read-${notification.id}'),
                tooltip: 'Als gelesen markieren: ${notification.title}',
                onPressed: onMarkRead,
                icon: const Icon(Icons.check),
              ),
          ],
        ),
      ),
    );
  }
}

/// The unread dot: visible when unread, and — crucially — a `Semantics`
/// label so the signal exists without color or weight perception (§15).
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    if (!unread) {
      return const SizedBox(width: 10, height: 10);
    }
    return Semantics(
      label: 'Ungelesen',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
