/// The port binding for the legal rule layer (`COMPLIANCE-RULES-01`, V-4).
///
/// Fails closed: an unconfigured port throws rather than returning an empty
/// rule set, because an empty rule set is a legal position ("nothing is
/// recorded") and a wiring mistake must never be able to state one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compliance_rules_repository.dart';

final complianceRulesPortProvider = Provider<ComplianceRulesPort>(
  (ref) => throw StateError('ComplianceRulesPort is not configured.'),
);
