/// The workspace's legal rule set (`COMPLIANCE-RULES-01`, V-4, `DEC-014`).
///
/// A rule is a statement about the law with a validity period, a source, and —
/// when somebody has checked it — the name of who did and when. All three are
/// load-bearing:
///
///   * **The period**, because an operating-cost statement for 2024 runs under
///     different law than one for 2026, and a retrospective correction must
///     apply the law of *then*. Asking for a figure means asking as of a date.
///   * **The source**, because a legal figure without one is a number somebody
///     remembered.
///   * **The confirmation**, because the owner's approval of this rule layer
///     authorised a shape, not a set of answers: the product proposes and a
///     named person confirms.
library;

/// How far a rule may be trusted. Mirrors the server enum exactly, plus
/// [unknown] for a value a newer server sends.
enum ComplianceRuleConfidence {
  /// Nobody has checked it. The normal state of a new rule, not a defect —
  /// and never a reason to hide it. An unchecked figure that is visible gets
  /// challenged; one that is hidden gets used.
  unverified,

  /// A named person confirmed it against its source.
  verified,

  /// The law requires a judgement here. May be shown, may be proposed, may
  /// **never** be applied without a human deciding the individual case.
  /// § 5d CO2KostAufG is the reason this state exists.
  decisionSupport,

  /// From a newer server. Treated as the most cautious thing it could be —
  /// see [ComplianceRuleDto.isApplicableWithoutHumanDecision].
  unknown,
}

ComplianceRuleConfidence complianceRuleConfidenceFromKey(String key) =>
    switch (key) {
      'unverified' => ComplianceRuleConfidence.unverified,
      'verified' => ComplianceRuleConfidence.verified,
      'decision_support' => ComplianceRuleConfidence.decisionSupport,
      _ => ComplianceRuleConfidence.unknown,
    };

String complianceRuleConfidenceKey(ComplianceRuleConfidence value) =>
    switch (value) {
      ComplianceRuleConfidence.unverified => 'unverified',
      ComplianceRuleConfidence.verified => 'verified',
      ComplianceRuleConfidence.decisionSupport => 'decision_support',
      // Never sent: the command layer refuses it rather than guessing what an
      // unfamiliar confidence meant.
      ComplianceRuleConfidence.unknown => 'unknown',
    };

class ComplianceRuleDto {
  const ComplianceRuleDto({
    required this.id,
    required this.workspaceId,
    required this.ruleKey,
    required this.jurisdiction,
    required this.validFrom,
    required this.value,
    required this.sourceReference,
    required this.confidence,
    required this.version,
    this.validTo,
    this.unit,
    this.note,
    this.verifiedBy,
    this.verifiedAt,
    this.verificationNote,
    this.rawConfidenceKey,
  });

  final String id;
  final String workspaceId;

  /// The server's key, e.g. `co2_price_eur_per_tonne`. Free text on purpose:
  /// the rule vocabulary grows with the law.
  final String ruleKey;

  final String jurisdiction;

  /// Inclusive at both ends, as a statute reads. Null [validTo] is open-ended,
  /// which is the normal state of current law.
  final DateTime validFrom;
  final DateTime? validTo;

  /// Shaped by the rule: a number for a price, an object for the three
  /// building attributes of the 70% rule. Deliberately untyped here — a
  /// client-side schema per rule key would be a second place for the rule
  /// vocabulary to live, and it would go stale the first time the legislature
  /// invented a threshold nobody had modelled.
  final Object? value;

  final String? unit;
  final String sourceReference;
  final String? note;

  final ComplianceRuleConfidence confidence;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? verificationNote;

  final int version;

  /// The server's key, kept only when [confidence] came back as
  /// [ComplianceRuleConfidence.unknown].
  final String? rawConfidenceKey;

  bool get isVerified => confidence == ComplianceRuleConfidence.verified;

  bool get needsHumanDecision =>
      confidence == ComplianceRuleConfidence.decisionSupport;

  /// Whether a calculation may apply this rule on its own.
  ///
  /// False for [ComplianceRuleConfidence.decisionSupport], because the law
  /// wants a judgement. False for [ComplianceRuleConfidence.unknown] too: a
  /// confidence this build does not recognise could be a *stricter* state a
  /// newer server introduced, and treating an unrecognised state as permissive
  /// is how an automatic decision gets made in a case that needed a person.
  ///
  /// True for `unverified` — which looks wrong and is not. An unchecked rule
  /// may be used; it simply has to be reported as unchecked wherever it is,
  /// which is what the counts on the answer are for. Blocking it instead would
  /// leave the product unable to compute anything at all until every figure
  /// had been signed off, and the pressure that creates is what makes people
  /// sign things off unread.
  bool get isApplicableWithoutHumanDecision =>
      confidence == ComplianceRuleConfidence.verified ||
      confidence == ComplianceRuleConfidence.unverified;
}

/// The rules in force on one date, with what the answer is standing on.
class ComplianceRuleSetDto {
  const ComplianceRuleSetDto({
    required this.asOfDate,
    required this.jurisdiction,
    required this.rules,
    required this.unverifiedCount,
    required this.decisionSupportCount,
  });

  final DateTime asOfDate;
  final String jurisdiction;
  final List<ComplianceRuleDto> rules;

  /// Counted by the server over the whole matched set. A calculation built on
  /// these has to be able to say what it rests on, and it can only do that if
  /// the read tells it.
  final int unverifiedCount;
  final int decisionSupportCount;

  /// The rule for [ruleKey], or null when none was in force on [asOfDate].
  ///
  /// Null is a real answer: no rule covering the date means the law for that
  /// period was never recorded, which is different from a rule whose value is
  /// zero. There is deliberately no fallback to the nearest rule — reaching
  /// backwards would apply a figure to a year it was not law in.
  ComplianceRuleDto? operator [](String ruleKey) {
    for (final ComplianceRuleDto rule in rules) {
      if (rule.ruleKey == ruleKey) {
        return rule;
      }
    }
    return null;
  }

  bool get isFullyVerified =>
      unverifiedCount == 0 && decisionSupportCount == 0 && rules.isNotEmpty;
}
