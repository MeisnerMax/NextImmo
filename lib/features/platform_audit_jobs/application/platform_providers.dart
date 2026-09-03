/// Backend-agnostic Riverpod seam for the `platform_audit_jobs` contract
/// (P2-D04), following the same pattern as `leasing_providers.dart` and
/// `party_providers.dart`: which implementation serves each port is decided
/// by `AppEnvironment.dataBackend` in `app_backend_wiring.dart`. Reading a
/// port before an override is installed fails closed instead of silently
/// binding a default.
///
/// [taskRepositoryProvider] arrived with Wave 3's `OperationsAlertsPanel`
/// ("wire the provider when the first consumer needs it").
/// [notificationPortProvider] and [platformQueryInvalidationSourceProvider]
/// are wired by `TASKS-NOTIFICATIONS-CORE-01` (increment A15) as the seam the
/// Task-Center and Notification-Inbox waves build on. `JobRepository` and
/// `SearchIndexPort` stay unexposed until their first consuming screen lands
/// (`IMPORTS-01`, `TASK-QUERY-01`); do not wire what nothing reads.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_query_invalidation_source.dart';
import 'platform_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => throw StateError('TaskRepository is not configured.'),
);

final notificationPortProvider = Provider<NotificationPort>(
  (ref) => throw StateError('NotificationPort is not configured.'),
);

final platformQueryInvalidationSourceProvider =
    Provider<PlatformQueryInvalidationSource>(
      (ref) =>
          throw StateError(
            'PlatformQueryInvalidationSource is not configured.',
          ),
    );
