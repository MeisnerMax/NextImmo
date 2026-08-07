/// Notification aggregate DTOs (P2-D04, DOM-010).
///
/// Notifications are recipient-addressed: one platform event fans out to one
/// row per recipient under a single `mutationId`. Mirrors
/// `private.notification_snapshot` field for field.
library;

import 'platform_entity_type.dart';

class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.workspaceId,
    required this.recipientUserId,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.version,
    this.body,
    this.entity,
    this.readAt,
  });

  final String id;
  final String workspaceId;
  final String recipientUserId;

  /// A normalized dot/underscore/dash key (`lease.expiring`, `task_due`), not
  /// display text — the server rejects anything else.
  final String kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final int version;
  final String? body;
  final PlatformEntityRef? entity;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}

/// Input for the `create_notification` fan-out.
class NotificationDraft {
  const NotificationDraft({
    required this.recipientUserIds,
    required this.kind,
    required this.title,
    this.body,
    this.entity,
  });

  /// Every recipient must be an active workspace member, and the list must not
  /// be empty; the server rejects the whole batch otherwise rather than
  /// partially delivering it. Both rules stay server-side (`validation_failed`
  /// on `recipient_user_ids`) — a const-constructible draft cannot assert over
  /// a list's contents, and duplicating the rule in a non-const constructor
  /// would trade a real guarantee for a cosmetic one.
  final List<String> recipientUserIds;
  final String kind;
  final String title;
  final String? body;
  final PlatformEntityRef? entity;
}

/// The result of one fan-out. `create_notification` is a batch command, so it
/// returns the batch — not a single [NotificationDto]. Modelling it as an
/// entity would force an arbitrary "which recipient's row is *the* result"
/// choice that the server deliberately does not make.
class NotificationFanOutReceipt {
  const NotificationFanOutReceipt({
    required this.kind,
    required this.recipientCount,
    required this.notificationIds,
  });

  final String kind;
  final int recipientCount;
  final List<String> notificationIds;
}
