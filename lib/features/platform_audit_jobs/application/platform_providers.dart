/// Backend-agnostic Riverpod seam for the `platform_audit_jobs` contract
/// (P2-D04), following the same pattern as `leasing_providers.dart` and
/// `party_providers.dart`: which implementation serves each port is decided
/// by `AppEnvironment.dataBackend` in `app_backend_wiring.dart`. Reading a
/// port before an override is installed fails closed instead of silently
/// binding a default.
///
/// **Only [taskRepositoryProvider] is exposed so far.** P2-D04's backend
/// shipped all four ports (`TaskRepository`, `NotificationPort`,
/// `JobRepository`, `SearchIndexPort`) in one adapter class per backend, but
/// nothing consumed any of them through Riverpod until Wave 3's
/// `OperationsAlertsPanel` needed to create a task from a signal — the same
/// "wire the provider when the first consumer needs it" sequencing Welle 2's
/// AP0 used. Add the other three providers here, following this exact shape,
/// when their first consuming screen lands; do not wire what nothing reads.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => throw StateError('TaskRepository is not configured.'),
);
