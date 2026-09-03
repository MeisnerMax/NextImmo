/// Pure time presentation of the Notification Inbox (§4/§5): relative up to
/// seven days, a plain date beyond — never ISO-8601, never UTC in the UI —
/// plus the exact time grouping Heute / Diese Woche / Älter.
///
/// The grouping is honest because the feed is strictly `created_at DESC`:
/// the loaded pages are an exact time prefix, so "Heute" and "Diese Woche"
/// are complete as soon as the prefix crosses the week boundary; only
/// "Älter" is naturally partial and carries the load-more (§4).
library;

import 'task_formatting.dart';

enum NotificationTimeBucket { today, thisWeek, older }

String notificationTimeBucketLabel(NotificationTimeBucket bucket) {
  return switch (bucket) {
    NotificationTimeBucket.today => 'Heute',
    NotificationTimeBucket.thisWeek => 'Diese Woche',
    NotificationTimeBucket.older => 'Älter',
  };
}

/// Buckets by local calendar day and calendar week (Monday start — the
/// German reading of "Diese Woche").
NotificationTimeBucket notificationTimeBucket(
  DateTime createdAt, {
  required DateTime now,
}) {
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (!day.isBefore(today)) {
    return NotificationTimeBucket.today;
  }
  final monday = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(monday)) {
    return NotificationTimeBucket.thisWeek;
  }
  return NotificationTimeBucket.older;
}

/// "gerade eben" / "vor N Minuten|Stunden|Tagen" up to seven days, then the
/// dd.MM.yyyy date.
String notificationRelativeTime(DateTime createdAt, {required DateTime now}) {
  final difference = now.difference(createdAt.toLocal());
  if (difference.inMinutes < 1) {
    return 'gerade eben';
  }
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return minutes == 1 ? 'vor 1 Minute' : 'vor $minutes Minuten';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return hours == 1 ? 'vor 1 Stunde' : 'vor $hours Stunden';
  }
  if (difference.inDays <= 7) {
    final days = difference.inDays;
    return days == 1 ? 'vor 1 Tag' : 'vor $days Tagen';
  }
  return formatTaskDate(createdAt);
}

const List<String> _germanMonths = <String>[
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// The absolute, screenreader-friendly form behind every relative display
/// (§15): "28. August 2026, 14:12".
String notificationAbsoluteTime(DateTime createdAt) {
  final local = createdAt.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}. ${_germanMonths[local.month - 1]} ${local.year}, '
      '${local.hour}:$minute';
}
