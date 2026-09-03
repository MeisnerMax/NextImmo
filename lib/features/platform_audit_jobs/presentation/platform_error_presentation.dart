/// The one RPC-failure → UI-behavior mapping of the TASKS-NOTIFICATIONS
/// shared contract (§12), consumed by both the Task-Center and the
/// Notification-Inbox surfaces so neither invents its own reading of a
/// server rejection.
library;

import '../application/platform_repository.dart';

/// What a surface does with a [PlatformRepositoryFailure], one value per §12
/// table row. The mapping is deliberately behavior-first: two failures that
/// demand the same UI reaction share a disposition even when their wire codes
/// differ.
enum PlatformErrorDisposition {
  /// `validation_failed`: inline error on the field(s) named in
  /// [PlatformRepositoryFailure.validationFields]; the dialog stays open.
  fieldValidation,

  /// `version_conflict`: conflict banner per Foundation §10 — input is kept,
  /// the server's `current_entity` (on [PlatformRepositoryFailure
  /// .versionConflict]) is used to reseed.
  versionConflict,

  /// `mutation_conflict`: the same mutationId was already executed with
  /// different data. Never retried with that id.
  mutationConflict,

  /// `in_progress`: the first execution is still running — keep the submit
  /// button in its loading state and retry once after a short delay.
  retryInProgress,

  /// `not_found`: the detail switches to its notFound state (Foundation §8).
  notFound,

  /// `forbidden` carrying the DEC-025 AAL gate message: render the §11
  /// AAL state ("Zweiter Faktor erforderlich"), never a permission error and
  /// never an empty state — a correctly secured session is not data loss.
  aalStepUpRequired,

  /// Any other `forbidden`: SnackBar with the server's message.
  forbidden,

  /// Infrastructure failures (and [PlatformRepositoryFailureKind
  /// .dependencyConflict], which the Supabase adapter never produces):
  /// `NxEmptyState.error` on reads, SnackBar plus retry on actions.
  infrastructure,
}

/// `private.platform_command_gate` rejects every aal1 mutation with exactly
/// this prefix before any validation runs (DEC-025) — and aal1 *reads* return
/// zero rows instead of failing, so this message is the only client-visible
/// AAL signal there is.
const String aalStepUpMessagePrefix = 'AAL2 is required';

PlatformErrorDisposition platformErrorDispositionOf(
  PlatformRepositoryFailure<Object?> failure,
) {
  return switch (failure.kind) {
    PlatformRepositoryFailureKind.validationFailed =>
      PlatformErrorDisposition.fieldValidation,
    PlatformRepositoryFailureKind.versionConflict =>
      PlatformErrorDisposition.versionConflict,
    PlatformRepositoryFailureKind.mutationConflict =>
      PlatformErrorDisposition.mutationConflict,
    PlatformRepositoryFailureKind.mutationInProgress =>
      PlatformErrorDisposition.retryInProgress,
    PlatformRepositoryFailureKind.notFound => PlatformErrorDisposition.notFound,
    PlatformRepositoryFailureKind.forbidden =>
      failure.message.startsWith(aalStepUpMessagePrefix)
          ? PlatformErrorDisposition.aalStepUpRequired
          : PlatformErrorDisposition.forbidden,
    PlatformRepositoryFailureKind.dependencyConflict ||
    PlatformRepositoryFailureKind.infrastructureFailure =>
      PlatformErrorDisposition.infrastructure,
  };
}

/// The user-facing message per §12: the two rows the contract fixes verbatim
/// get that German copy; every other row passes the server's controlled
/// message through (the adapter already masks uncontrolled infrastructure
/// text before it gets here).
String platformErrorMessageOf(PlatformRepositoryFailure<Object?> failure) {
  return switch (platformErrorDispositionOf(failure)) {
    PlatformErrorDisposition.mutationConflict =>
      'Diese Aktion wurde bereits mit anderen Daten ausgeführt.',
    PlatformErrorDisposition.infrastructure =>
      'Aktion konnte nicht ausgeführt werden.',
    _ => failure.message,
  };
}
