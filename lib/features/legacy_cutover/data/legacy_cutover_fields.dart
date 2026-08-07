/// Shared field mapping and validation for the P2-X01-AP4 domain cutover.
///
/// The rules mirror the target constraints exactly, so a value that passes here
/// is accepted by Postgres and a value that would violate a constraint is
/// rejected with a named issue instead of failing anonymously on apply.
library;

import '../../portfolio_property/application/reference_migration_dry_run.dart';
import '../application/legacy_cutover.dart';

/// One entity family's mapping outcome. Kept separate per mapper so each domain
/// stays readable, then merged into a single plan.
class LegacyCutoverEntityResult {
  const LegacyCutoverEntityResult({
    required this.targets,
    required this.summaries,
    required this.mappings,
    required this.issues,
    this.targetIdsBySourceId = const <String, String>{},
  });

  final Map<LegacyCutoverEntity, List<Map<String, Object?>>> targets;
  final List<LegacyCutoverEntitySummary> summaries;
  final List<LegacyCutoverMapping> mappings;
  final List<LegacyCutoverIssue> issues;

  /// Source id to target id, so a dependent domain can resolve its foreign
  /// keys without re-deriving them.
  final Map<String, String> targetIdsBySourceId;
}

String legacyRowChecksum(Object? value) => referenceMigrationChecksum(value);

List<Map<String, Object?>> sortedLegacyRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort(
      (left, right) => (left['id']?.toString() ?? '').compareTo(
        right['id']?.toString() ?? '',
      ),
    );
  return sorted;
}

LegacyCutoverIssue fieldError(
  String code,
  LegacyCutoverEntity entity,
  String? sourceId,
  String field,
) => LegacyCutoverIssue(
  code: code,
  severity: LegacyCutoverIssueSeverity.error,
  entity: entity,
  sourceId: sourceId,
  field: field,
);

LegacyCutoverIssue fieldWarning(
  String code,
  LegacyCutoverEntity entity,
  String? sourceId,
  String field,
) => LegacyCutoverIssue(
  code: code,
  severity: LegacyCutoverIssueSeverity.warning,
  entity: entity,
  sourceId: sourceId,
  field: field,
);

String? requiredSourceId(
  Map<String, Object?> row,
  LegacyCutoverEntity entity,
  List<LegacyCutoverIssue> issues,
) {
  final value = row['id'];
  if (value is! String || value.isEmpty || value.trim() != value) {
    issues.add(fieldError('source.invalid_id', entity, null, 'id'));
    return null;
  }
  return value;
}

/// An unknown source column fails closed: it means the legacy schema grew a
/// field this contract has never considered, and dropping it silently would be
/// exactly the data loss the cutover exists to prevent.
void reportUnknownFields(
  Map<String, Object?> row, {
  required Set<String> known,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  for (final key in row.keys) {
    if (!known.contains(key) && row[key] != null) {
      issues.add(fieldError('mapping.unknown_field', entity, sourceId, key));
    }
  }
}

/// A known column that is deliberately not carried over is a visible warning,
/// so the exclusion appears in the report rather than in someone's memory.
void reportExcludedFields(
  Map<String, Object?> row, {
  required Set<String> excluded,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  for (final field in excluded) {
    if (row[field] != null) {
      issues.add(fieldWarning('mapping.field_excluded', entity, sourceId, field));
    }
  }
}

String? requiredText(
  Map<String, Object?> row, {
  required String key,
  required int maxLength,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    issues.add(fieldError('source.required_value_missing', entity, sourceId, key));
    return null;
  }
  final normalized = value.trim();
  if (normalized.length > maxLength) {
    issues.add(fieldError('source.text_too_long', entity, sourceId, key));
    return null;
  }
  return normalized;
}

String? optionalText(
  Map<String, Object?> row, {
  required String key,
  required int maxLength,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    issues.add(fieldError('source.invalid_text', entity, sourceId, key));
    return null;
  }
  final normalized = value.trim();
  if (normalized.isEmpty) {
    // The target forbids whitespace-only text; null is the honest equivalent.
    return null;
  }
  if (normalized.length > maxLength) {
    issues.add(fieldError('source.text_too_long', entity, sourceId, key));
    return null;
  }
  return normalized;
}

/// Mirrors `parties_email_normalized_check`: lowercase, trimmed, 3..320 and an
/// `@` that is not the first character.
String? optionalEmail(
  Map<String, Object?> row, {
  required String key,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    issues.add(fieldError('source.invalid_text', entity, sourceId, key));
    return null;
  }
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.length < 3 ||
      normalized.length > 320 ||
      normalized.indexOf('@') < 1) {
    issues.add(fieldError('source.invalid_email', entity, sourceId, key));
    return null;
  }
  return normalized;
}

String? requiredTimestamp(
  Map<String, Object?> row, {
  required String key,
  required LegacyCutoverEntity entity,
  required String? sourceId,
  required List<LegacyCutoverIssue> issues,
}) {
  final value = row[key];
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    issues.add(fieldError('source.invalid_epoch_millis', entity, sourceId, key));
    return null;
  }
  try {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    ).toIso8601String();
  } on RangeError {
    issues.add(fieldError('source.invalid_epoch_millis', entity, sourceId, key));
    return null;
  }
}

LegacyCutoverEntitySummary buildSummary({
  required LegacyCutoverEntity entity,
  required int sourceRows,
  required List<Map<String, Object?>> targets,
  required List<Map<String, Object?>> sourceRowsData,
  required int rejectedRows,
  required List<LegacyCutoverIssue> issues,
}) {
  final entityIssues = issues.where((issue) => issue.entity == entity);
  return LegacyCutoverEntitySummary(
    entity: entity,
    sourceRows: sourceRows,
    mappedRows: targets.length,
    rejectedRows: rejectedRows,
    errorCount: entityIssues.where((issue) => issue.isError).length,
    warningCount: entityIssues.where((issue) => !issue.isError).length,
    sourceChecksum: legacyRowChecksum(sourceRowsData),
    targetChecksum: legacyRowChecksum(targets),
  );
}
