/// COMPLIANCE-RULES-01 (V-4) on screen.
///
/// Two things must be visible at all times, because they are what stop a
/// researched legal position from being read as settled law:
///
///   * **the state of every rule** — unchecked, confirmed, or requiring a human
///     decision;
///   * **the date it is being read for**, which is the whole feature: a
///     retrospective correction applies the law of its own period.
///
/// And one thing must be absent: a "confirm" button on a rule the law leaves to
/// judgement. Not disabled — absent. A greyed-out button invites asking why it
/// is greyed out; no button at all matches the fact that confirming such a rule
/// is not a thing that exists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/compliance_rules/application/compliance_rules_providers.dart';
import 'package:neximmo_app/features/compliance_rules/application/compliance_rules_repository.dart';
import 'package:neximmo_app/features/compliance_rules/domain/compliance_rule_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/compliance/compliance_rule_proposals.dart';
import 'package:neximmo_app/ui/screens/compliance/compliance_rules_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ComplianceRuleDto _rule({
  String id = 'rule-1',
  String ruleKey = 'co2_price_eur_per_tonne',
  ComplianceRuleConfidence confidence = ComplianceRuleConfidence.unverified,
  Object? value = 60,
}) {
  return ComplianceRuleDto(
    id: id,
    workspaceId: 'ws-1',
    ruleKey: ruleKey,
    jurisdiction: 'DE',
    validFrom: DateTime(2026, 1, 1),
    value: value,
    unit: 'EUR/t',
    sourceReference: 'BEHG Anlage 1',
    confidence: confidence,
    version: 1,
    verifiedAt: confidence == ComplianceRuleConfidence.verified
        ? DateTime(2026, 9, 7)
        : null,
    verifiedBy: confidence == ComplianceRuleConfidence.verified
        ? 'actor-a'
        : null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakePort port,
  Set<String> permissions = const <String>{'workspace.read', 'security.manage'},
  Size viewport = const Size(1200, 1100),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        complianceRulesPortProvider.overrideWithValue(port),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'actor-a',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ComplianceRulesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows each rule with its period, value and source', (
    tester,
  ) async {
    await _pump(tester, port: _FakePort());

    expect(find.text('co2_price_eur_per_tonne'), findsOneWidget);
    expect(find.textContaining('2026-01-01'), findsWidgets);
    expect(find.textContaining('60 EUR/t'), findsOneWidget);
    expect(
      find.textContaining('Quelle: BEHG Anlage 1'),
      findsOneWidget,
      reason: 'a legal figure without a visible source is a number somebody '
          'remembered',
    );
  });

  testWidgets('an unchecked rule says so', (tester) async {
    await _pump(tester, port: _FakePort());

    expect(find.text('Ungeprüft'), findsOneWidget);
    expect(find.text('Bestätigt'), findsNothing);
  });

  testWidgets('a confirmed rule shows who and when, and offers to withdraw', (
    tester,
  ) async {
    await _pump(
      tester,
      port: _FakePort(
        rules: <ComplianceRuleDto>[
          _rule(confidence: ComplianceRuleConfidence.verified),
        ],
      ),
    );

    expect(find.text('Bestätigt'), findsOneWidget);
    expect(find.textContaining('Bestätigt am 2026-09-07'), findsOneWidget);
    expect(find.text('Bestätigung zurückziehen'), findsOneWidget);
  });

  testWidgets('a rule the law leaves to judgement has no confirm button at all',
      (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        rules: <ComplianceRuleDto>[
          _rule(
            ruleKey: 'co2kostaufg_5d_haertefall',
            confidence: ComplianceRuleConfidence.decisionSupport,
          ),
        ],
      ),
    );

    // The card renders, so the absence below is about the button and not about
    // the screen having failed to build.
    expect(find.text('co2kostaufg_5d_haertefall'), findsOneWidget);
    expect(find.text('Entscheidung nötig'), findsOneWidget);
    expect(
      find.byKey(const Key('compliance-rule-decision-note')),
      findsOneWidget,
    );
    expect(
      find.text('Bestätigen'),
      findsNothing,
      reason: 'not disabled -- absent. A greyed-out button invites asking why; '
          'no button matches the fact that confirming it does not exist',
    );
  });

  testWidgets('the counts are the server\'s, not a count of the cards', (
    tester,
  ) async {
    // One rule on screen, nine unchecked in the set.
    await _pump(tester, port: _FakePort(unverified: 9, decisionSupport: 3));

    expect(find.text('9'), findsOneWidget);
    expect(
      find.text('3'),
      findsOneWidget,
      reason: 'the server counted over the whole matched set. Counting the '
          'visible cards would report "1 unchecked" while nine were',
    );
  });

  testWidgets('the as-of date is shown as the one the server used', (
    tester,
  ) async {
    await _pump(tester, port: _FakePort(asOfDate: DateTime(2024, 6, 30)));

    expect(
      find.text('Stichtag: 2024-06-30'),
      findsOneWidget,
      reason: 'the date the answer was computed for, not the one the reader '
          'typed. When they asked for nothing the server chose, and implying '
          'otherwise would hide whose "today" it was',
    );
  });

  testWidgets('a member who may only read gets no write actions', (
    tester,
  ) async {
    await _pump(
      tester,
      port: _FakePort(),
      permissions: const <String>{'workspace.read'},
    );

    expect(find.text('co2_price_eur_per_tonne'), findsOneWidget);
    expect(find.byKey(const Key('compliance-rule-create')), findsNothing);
    expect(find.byKey(const Key('compliance-rule-proposals')), findsNothing);
    expect(find.text('Bestätigen'), findsNothing);
  });

  testWidgets('an empty rule set is not an error', (tester) async {
    await _pump(
      tester,
      port: _FakePort(rules: const <ComplianceRuleDto>[], unverified: 0),
    );

    expect(find.byKey(const Key('compliance-rules-empty')), findsOneWidget);
    expect(find.byKey(const Key('compliance-rules-error')), findsNothing);
  });

  testWidgets('a failed read is not an empty rule set', (tester) async {
    await _pump(
      tester,
      port: _FakePort(failure: ComplianceRulesFailureKind.infrastructureFailure),
    );

    expect(find.byKey(const Key('compliance-rules-error')), findsOneWidget);
    expect(
      find.byKey(const Key('compliance-rules-empty')),
      findsNothing,
      reason: '"nothing is recorded" is itself a legal position, and a broken '
          'read must not be able to state one',
    );
  });

  testWidgets('the proposal catalogue offers only researched entries', (
    tester,
  ) async {
    await _pump(tester, port: _FakePort());

    await tester.tap(find.byKey(const Key('compliance-rule-proposals')));
    await tester.pumpAndSettle();

    expect(find.text('CO₂-Preis 2026'), findsOneWidget);
    expect(find.text('§ 5d CO2KostAufG: Härtefall'), findsOneWidget);
  });

  testWidgets('every proposal carries a source', (tester) async {
    for (final ComplianceRuleProposal proposal in complianceRuleProposals) {
      expect(
        proposal.sourceReference.trim(),
        isNotEmpty,
        reason: '${proposal.ruleKey} would otherwise be a number somebody '
            'remembered, offered by the product as if it were researched',
      );
    }
    expect(complianceRuleProposals, isNotEmpty);
  });

  testWidgets('the three contested points are proposed as decision support', (
    tester,
  ) async {
    final decisionKeys = complianceRuleProposals
        .where((ComplianceRuleProposal p) => p.decisionSupport)
        .map((ComplianceRuleProposal p) => p.ruleKey)
        .toSet();

    expect(
      decisionKeys,
      containsAll(<String>[
        'co2kostaufg_5d_haertefall',
        'heizkostenv_12_kuerzung_kumulierbar',
        'ust_optierte_gewerbevermietung',
      ]),
      reason: 'the research calls these contradictory in its sources, and the '
          'owner approval that unblocked this package could not make them '
          'unambiguous. They are proposed and never applied automatically',
    );
  });

  testWidgets('renders without overflow at a phone width', (tester) async {
    await _pump(
      tester,
      port: _FakePort(
        rules: <ComplianceRuleDto>[
          _rule(
            ruleKey: 'heizkostenv_70_percent_conditions',
            value: const <String, Object>{
              'no_wschv_1994_standard': true,
              'oil_or_gas_heating': true,
              'mostly_insulated_exposed_pipes': true,
            },
          ),
        ],
      ),
      viewport: const Size(380, 820),
    );

    expect(tester.takeException(), isNull);
  });
}

class _FakePort implements ComplianceRulesPort {
  _FakePort({
    List<ComplianceRuleDto>? rules,
    this.unverified = 1,
    this.decisionSupport = 0,
    this.failure,
    this.asOfDate,
  }) : rules = rules ?? <ComplianceRuleDto>[_rule()];

  final List<ComplianceRuleDto> rules;
  final int unverified;
  final int decisionSupport;
  final ComplianceRulesFailureKind? failure;
  final DateTime? asOfDate;

  @override
  Future<ComplianceRulesResult<ComplianceRuleSetDto>> readAsOf(
    ComplianceRulesQuery query,
  ) async {
    final kind = failure;
    if (kind != null) {
      return ComplianceRulesFailure<ComplianceRuleSetDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return ComplianceRulesSuccess<ComplianceRuleSetDto>(
      ComplianceRuleSetDto(
        asOfDate: asOfDate ?? DateTime(2026, 9, 7),
        jurisdiction: 'DE',
        rules: rules,
        unverifiedCount: unverified,
        decisionSupportCount: decisionSupport,
      ),
    );
  }

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> upsert(
    UpsertComplianceRuleCommand command,
  ) async => ComplianceRulesSuccess<ComplianceRuleDto>(_rule());

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> verify(
    VerifyComplianceRuleCommand command,
  ) async => ComplianceRulesSuccess<ComplianceRuleDto>(
    _rule(confidence: ComplianceRuleConfidence.verified),
  );
}
