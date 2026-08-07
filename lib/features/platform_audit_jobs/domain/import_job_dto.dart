/// ImportJob aggregate DTOs (P2-D04, DOM-010, STM-013, AGG-020).
///
/// Mirrors `private.import_job_snapshot` field for field. The pre-commit
/// evidence (dry-run manifest + reconciliation) is modelled as explicit job
/// state rather than a side channel, exactly as the schema models it: the
/// `import_jobs_commit_evidence_check` constraint means no job can reach
/// [ImportJobStatus.ready] — and therefore nothing can commit — without both.
library;

/// STM-013: `draft → validating → ready → running → completed`, failure only
/// out of `validating`/`running`, and both `completed` and `failed` are
/// terminal. A retry is a brand-new job, never a transition out of a terminal
/// state.
enum ImportJobStatus {
  draft('draft'),
  validating('validating'),
  ready('ready'),
  running('running'),
  completed('completed'),
  failed('failed');

  const ImportJobStatus(this.wireName);

  final String wireName;

  static ImportJobStatus? fromWire(String? value) {
    for (final status in ImportJobStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  /// A client-side mirror of `private.import_job_status_can_transition`, for
  /// affordance enablement only. The server remains authoritative.
  bool canTransitionTo(ImportJobStatus target) {
    switch (this) {
      case ImportJobStatus.draft:
        return target == ImportJobStatus.validating;
      case ImportJobStatus.validating:
        return target == ImportJobStatus.ready ||
            target == ImportJobStatus.failed;
      case ImportJobStatus.ready:
        return target == ImportJobStatus.running;
      case ImportJobStatus.running:
        return target == ImportJobStatus.completed ||
            target == ImportJobStatus.failed;
      case ImportJobStatus.completed:
      case ImportJobStatus.failed:
        return false;
    }
  }

  bool get isTerminal =>
      this == ImportJobStatus.completed || this == ImportJobStatus.failed;

  /// Only a draft job may have its mapping, source kind or target scope edited.
  bool get isEditable => this == ImportJobStatus.draft;
}

class ImportJobDto {
  const ImportJobDto({
    required this.id,
    required this.workspaceId,
    required this.sourceKind,
    required this.targetScope,
    required this.status,
    required this.mapping,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.version,
    this.dryRun,
    this.reconciliation,
    this.errorReport,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String workspaceId;

  /// A normalized key identifying the source system/format (`sqlite.legacy`,
  /// `csv`), not display text.
  final String sourceKind;

  /// One job targets one scope, so the legacy per-target `import_mappings` rows
  /// collapse into a single [mapping] object.
  final String targetScope;
  final ImportJobStatus status;
  final Map<String, Object?> mapping;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final int version;

  /// AGG-020 evidence, attached at the `→ ready` transition and frozen after.
  final Map<String, Object?>? dryRun;
  final Map<String, Object?>? reconciliation;

  /// Attached at the `→ failed` transition.
  final Map<String, Object?>? errorReport;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// AGG-020, read back from the server's own state rather than recomputed:
  /// a job carries commit evidence exactly when it has both a dry-run manifest
  /// and a reconciliation.
  bool get hasCommitEvidence => dryRun != null && reconciliation != null;
}

/// Input for `create_import_job`. The job always starts in
/// [ImportJobStatus.draft]; the draft cannot choose a status.
class ImportJobDraft {
  const ImportJobDraft({
    required this.sourceKind,
    required this.targetScope,
    this.mapping = const <String, Object?>{},
  });

  final String sourceKind;
  final String targetScope;
  final Map<String, Object?> mapping;
}

/// A sparse edit for `update_import_job`. Only the three server-accepted change
/// keys are representable, and only while the job is a draft. None of them is
/// nullable server-side, so a plain nullable field is the right shape here
/// (unlike [TaskUpdateDto], whose fields are clearable).
class ImportJobUpdateDto {
  const ImportJobUpdateDto({this.sourceKind, this.targetScope, this.mapping});

  final String? sourceKind;
  final String? targetScope;
  final Map<String, Object?>? mapping;

  bool get isEmpty =>
      sourceKind == null && targetScope == null && mapping == null;
}

/// The artifacts that ride a status transition. The server accepts each on
/// exactly one target status and rejects it on any other, so this type is a
/// closed set of three named constructors rather than a bag of optionals.
class ImportJobTransitionEvidence {
  /// No artifact — the correct payload for `→ validating` and `→ running` and
  /// `→ completed`.
  const ImportJobTransitionEvidence.none()
    : dryRun = null,
      reconciliation = null,
      errorReport = null;

  /// AGG-020 evidence for `→ ready`. Both parameters are non-nullable on
  /// purpose — an initializing formal would widen them to the fields' nullable
  /// type and let a caller construct `ready` evidence carrying nothing, which
  /// is exactly the state the server's commit-evidence check exists to reject.
  const ImportJobTransitionEvidence.ready({
    required Map<String, Object?> manifest,
    required Map<String, Object?> reconciled,
  }) : dryRun = manifest,
       reconciliation = reconciled,
       errorReport = null;

  /// The structured report a `→ failed` transition always carries.
  const ImportJobTransitionEvidence.failure(Map<String, Object?> report)
    : dryRun = null,
      reconciliation = null,
      errorReport = report;

  final Map<String, Object?>? dryRun;
  final Map<String, Object?>? reconciliation;
  final Map<String, Object?>? errorReport;
}
