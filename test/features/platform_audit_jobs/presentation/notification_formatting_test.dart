import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/presentation/notification_formatting.dart';

void main() {
  // Wednesday, 2026-09-03 10:00 local.
  final now = DateTime(2026, 9, 3, 10);

  test('buckets by local day and Monday-start week (§4/§17)', () {
    expect(
      notificationTimeBucket(DateTime(2026, 9, 3, 0, 5), now: now),
      NotificationTimeBucket.today,
    );
    // Yesterday (Tuesday) is this week, not today.
    expect(
      notificationTimeBucket(DateTime(2026, 9, 2, 23, 55), now: now),
      NotificationTimeBucket.thisWeek,
    );
    // Monday of this week just after midnight stays this week.
    expect(
      notificationTimeBucket(DateTime(2026, 8, 31, 0, 1), now: now),
      NotificationTimeBucket.thisWeek,
    );
    // Sunday before this week's Monday is older.
    expect(
      notificationTimeBucket(DateTime(2026, 8, 30, 23, 59), now: now),
      NotificationTimeBucket.older,
    );
  });

  test('relative time up to seven days, then the date — never ISO-8601', () {
    expect(
      notificationRelativeTime(DateTime(2026, 9, 3, 9, 59, 40), now: now),
      'gerade eben',
    );
    expect(
      notificationRelativeTime(DateTime(2026, 9, 3, 9, 58), now: now),
      'vor 2 Minuten',
    );
    expect(
      notificationRelativeTime(DateTime(2026, 9, 3, 8), now: now),
      'vor 2 Stunden',
    );
    expect(
      notificationRelativeTime(DateTime(2026, 9, 1, 9), now: now),
      'vor 2 Tagen',
    );
    final beyond = notificationRelativeTime(
      DateTime(2026, 8, 20, 9),
      now: now,
    );
    expect(beyond, '20.08.2026');
    expect(beyond, isNot(contains('T')));
  });

  test('the absolute screenreader form is German and local (§15)', () {
    expect(
      notificationAbsoluteTime(DateTime(2026, 8, 28, 14, 12)),
      '28. August 2026, 14:12',
    );
  });
}
