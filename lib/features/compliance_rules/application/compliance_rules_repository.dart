/// Backend-agnostic contract for the legal rule layer
/// (`COMPLIANCE-RULES-01`, V-4).
///
/// Three operations, and the split between the last two is the point: writing
/// a rule states what the law is, and verifying it is somebody vouching for
/// that statement. One command cannot be both, and the audit trail has to say
/// which happened.
library;

import '../domain/compliance_rule_dto.dart';

/// Actor and idempotency metadata, in the shape every audited command in this
/// product takes.
class ComplianceCommandContext {
  const ComplianceCommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final String correlationId;
  final String? reason;
}

class ComplianceRulesQuery {
  const ComplianceRulesQuery({
    required this.workspaceId,
    this.asOfDate,
    this.ruleKey,
    this.jurisdiction,
  });

  final String workspaceId;

  /// The date the rules are asked about. Null lets the server use its own
  /// today — and the answer always states which date it used, so a screen
  /// never has to assume.
  final DateTime? asOfDate;

  final String? ruleKey;
  final String? jurisdiction;
}

/// Creates a rule, or replaces the content of one.
///
/// [ruleId] and [expectedVersion] travel together: both null creates, both set
/// edits. The server refuses an edit without a version rather than taking the
/// last write.
///
/// There is no `confidence` here on purpose. A write never verifies; it can
/// only mark a rule as needing a human ([decisionSupport]), which is a
/// statement about the *law*, not about who checked it.
class UpsertComplianceRuleCommand {
  const UpsertComplianceRuleCommand({
    required this.context,
    required this.ruleKey,
    required this.validFrom,
    required this.value,
    required this.sourceReference,
    this.ruleId,
    this.expectedVersion,
    this.validTo,
    this.unit,
    this.note,
    this.jurisdiction = 'DE',
    this.decisionSupport = false,
  }) : assert(
         (ruleId == null) == (expectedVersion == null),
         'an edit needs both the id and the version it expects',
       );

  final ComplianceCommandContext context;
  final String? ruleId;
  final int? expectedVersion;
  final String ruleKey;
  final DateTime validFrom;
  final DateTime? validTo;
  final Object value;

  /// Required by the server, and the one validation worth arguing about: a
  /// legal figure without a source is a number somebody remembered.
  final String sourceReference;

  final String? unit;
  final String? note;
  final String jurisdiction;

  /// Marks a rule the law leaves to judgement. It may then be shown and
  /// proposed, and may never be applied automatically — and it cannot be
  /// verified into an automatic one either.
  final bool decisionSupport;
}

/// Records that a named person checked a rule against its source, or withdraws
/// that.
class VerifyComplianceRuleCommand {
  const VerifyComplianceRuleCommand({
    required this.context,
    required this.ruleId,
    required this.expectedVersion,
    required this.verified,
    this.verificationNote,
  });

  final ComplianceCommandContext context;
  final String ruleId;
  final int expectedVersion;

  /// False withdraws a previous confirmation and clears its author with it.
  final bool verified;

  final String? verificationNote;
}

enum ComplianceRulesFailureKind {
  notFound,
  forbidden,
  validationFailed,
  versionConflict,

  /// Another rule with the same key already covers part of that period. The
  /// server refuses it because two rules covering one day would make the law
  /// of that day depend on which row was read first.
  overlap,
  mutationConflict,
  mutationInProgress,
  infrastructureFailure,
}

class ComplianceRuleVersionConflict {
  const ComplianceRuleVersionConflict({
    required this.expectedVersion,
    required this.actualVersion,
    this.currentRule,
  });

  final int expectedVersion;
  final int actualVersion;

  /// The rule as it actually stands, so a stale form can show what it would
  /// have overwritten.
  final ComplianceRuleDto? currentRule;
}

sealed class ComplianceRulesResult<T> {
  const ComplianceRulesResult();
}

class ComplianceRulesSuccess<T> extends ComplianceRulesResult<T> {
  const ComplianceRulesSuccess(this.value);

  final T value;
}

class ComplianceRulesFailure<T> extends ComplianceRulesResult<T> {
  const ComplianceRulesFailure({
    required this.kind,
    required this.message,
    this.field,
    this.versionConflict,
  });

  final ComplianceRulesFailureKind kind;
  final String message;

  /// The contract field the server named, when it named one.
  final String? field;

  final ComplianceRuleVersionConflict? versionConflict;
}

abstract interface class ComplianceRulesPort {
  /// The rules in force on a date, with the counts of what has not been
  /// checked and what needs a human.
  Future<ComplianceRulesResult<ComplianceRuleSetDto>> readAsOf(
    ComplianceRulesQuery query,
  );

  Future<ComplianceRulesResult<ComplianceRuleDto>> upsert(
    UpsertComplianceRuleCommand command,
  );

  /// Separate from [upsert] because stating the law and vouching for the
  /// statement are different acts — and because an edit drops a rule back to
  /// unverified, which only makes sense if the two are distinct commands.
  Future<ComplianceRulesResult<ComplianceRuleDto>> verify(
    VerifyComplianceRuleCommand command,
  );
}
