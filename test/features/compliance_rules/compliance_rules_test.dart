/// COMPLIANCE-RULES-01 (V-4): the client half of the legal rule layer.
///
/// `DEC-014` authorised a shape, not a set of answers, and these tests pin the
/// shape where a client could quietly undo it:
///
///   * **A date gets the law of its own period**, and the client never picks a
///     nearby rule when none covers the date. Reaching backwards would apply a
///     figure to a year it was not law in.
///   * **The counts come from the server**, over the whole matched set. A
///     client that counted its own list would report "nothing unchecked" while
///     the filter hid what was.
///   * **An unknown confidence is treated as the strictest thing it could
///     be.** A newer server may introduce a state stricter than any this build
///     knows, and treating an unrecognised state as permissive is how an
///     automatic decision gets made in a case that needed a person.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/compliance_rules/application/compliance_rules_repository.dart';
import 'package:neximmo_app/features/compliance_rules/data/supabase_compliance_rules_adapter.dart';
import 'package:neximmo_app/features/compliance_rules/domain/compliance_rule_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/compliance_rules/application/compliance_rules_controller.dart';

void main() {
  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseComplianceRulesAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseComplianceRulesAdapter.withGateway(gateway);
    });

    test('sends the as-of date as a calendar day, never a UTC instant', () async {
      gateway.result = _ruleSet();

      await adapter.readAsOf(
        ComplianceRulesQuery(
          workspaceId: 'ws-1',
          asOfDate: DateTime(2025, 1, 1),
        ),
      );

      expect(
        gateway.lastParameters?['p_as_of'],
        '2025-01-01',
        reason: 'a statute takes effect on a day. Converting through UTC would '
            'move this to 2024-12-31 west of Greenwich and apply last year\'s '
            'law to the first day of the year',
      );
    });

    test('parses the rules and the counts the server took', () async {
      gateway.result = _ruleSet(unverified: 4, decisionSupport: 2);

      final value = _successOf(await adapter.readAsOf(
        const ComplianceRulesQuery(workspaceId: 'ws-1'),
      ));

      expect(value.rules, hasLength(2));
      expect(value.rules.first.ruleKey, 'co2_price_eur_per_tonne');
      expect(value.rules.first.value, 55);
      expect(
        value.unverifiedCount,
        4,
        reason: 'read, not counted from the two rows returned. The server '
            'counted over the whole matched set',
      );
      expect(value.decisionSupportCount, 2);
    });

    test('an unfamiliar confidence keeps its raw key', () async {
      gateway.result = _ruleSet(confidence: 'court_disputed');

      final value = _successOf(await adapter.readAsOf(
        const ComplianceRulesQuery(workspaceId: 'ws-1'),
      ));

      expect(value.rules.first.confidence, ComplianceRuleConfidence.unknown);
      expect(value.rules.first.rawConfidenceKey, 'court_disputed');
      expect(
        value.rules.first.isApplicableWithoutHumanDecision,
        isFalse,
        reason: 'a state this build does not recognise could be stricter than '
            'any it does. Treating it as permissive is how an automatic '
            'decision gets made in a case that needed a person',
      );
    });

    test('an overlap is its own failure kind, not a generic conflict', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_conflict',
          'message': 'Another rule with this key already covers part of that period',
        },
      };

      final result = await adapter.upsert(_upsert());

      expect(
        (result as ComplianceRulesFailure<ComplianceRuleDto>).kind,
        ComplianceRulesFailureKind.overlap,
        reason: 'the form\'s answer is to change the period, not to reload and '
            'retry -- which is what a generic conflict would suggest',
      );
    });

    test('a version conflict carries the rule as it stands', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'stale',
          'expected_version': 1,
          'actual_version': 3,
          'current_entity': _ruleJson(value: 60, version: 3),
        },
      };

      final result = await adapter.upsert(_upsert());
      final failure = result as ComplianceRulesFailure<ComplianceRuleDto>;

      expect(failure.kind, ComplianceRulesFailureKind.versionConflict);
      expect(failure.versionConflict?.currentRule?.value, 60);
      expect(failure.versionConflict?.actualVersion, 3);
    });

    test('the named field survives a validation failure', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'message': 'A source reference is required',
          'field': 'sourceReference',
        },
      };

      final result = await adapter.upsert(_upsert());

      expect(
        (result as ComplianceRulesFailure<ComplianceRuleDto>).field,
        'sourceReference',
        reason: 'so the form can point at the field that was wrong instead of '
            'showing a sentence beside a form full of inputs',
      );
    });

    test('verify goes to its own command', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': _ruleJson(confidence: 'verified'),
      };

      await adapter.verify(
        VerifyComplianceRuleCommand(
          context: _context(),
          ruleId: 'rule-1',
          expectedVersion: 2,
          verified: true,
        ),
      );

      expect(
        gateway.lastFunction,
        'verify_compliance_rule',
        reason: 'stating the law and vouching for the statement are different '
            'acts, and the audit trail has to say which happened',
      );
      expect(gateway.lastParameters?['p_verified'], true);
    });

    test('a malformed answer fails rather than reporting no rules', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{'as_of_date': '2026-01-01'},
      };

      final result = await adapter.readAsOf(
        const ComplianceRulesQuery(workspaceId: 'ws-1'),
      );

      expect(
        (result as ComplianceRulesFailure<ComplianceRuleSetDto>).kind,
        ComplianceRulesFailureKind.infrastructureFailure,
        reason: '"this workspace has recorded no legal rules" is itself a '
            'legal position, and a broken read must not be able to state one',
      );
    });
  });

  group('rule set lookup', () {
    test('a key with no rule on the date answers null, never the nearest', () {
      final set = ComplianceRuleSetDto(
        asOfDate: DateTime(2023, 6, 1),
        jurisdiction: 'DE',
        rules: <ComplianceRuleDto>[_rule(ruleKey: 'other_key')],
        unverifiedCount: 1,
        decisionSupportCount: 0,
      );

      expect(
        set['co2_price_eur_per_tonne'],
        isNull,
        reason: 'reaching for a neighbouring period would apply a figure to a '
            'year it was not law in',
      );
      expect(set['other_key'], isNotNull);
    });

    test('decision support is never applicable on its own', () {
      final rule = _rule(confidence: ComplianceRuleConfidence.decisionSupport);

      expect(rule.needsHumanDecision, isTrue);
      expect(rule.isApplicableWithoutHumanDecision, isFalse);
    });

    test('unverified is applicable, and says so', () {
      final rule = _rule(confidence: ComplianceRuleConfidence.unverified);

      expect(
        rule.isApplicableWithoutHumanDecision,
        isTrue,
        reason: 'blocking every unchecked rule would leave the product unable '
            'to compute anything until each figure was signed off, and that '
            'pressure is what makes people sign things off unread. It is used '
            'and reported as unchecked',
      );
      expect(rule.isVerified, isFalse);
    });
  });

  group('controller', () {
    late _FakePort port;

    ComplianceRulesController controller({
      Set<String> permissions = const <String>{'workspace.read', 'security.manage'},
    }) {
      final subject = ComplianceRulesController(
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'ws-1',
          actorId: 'actor-a',
          permissions: permissions,
          mutationsSupported: true,
        ),
        idFactory: () => 'id-1',
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() {
      port = _FakePort();
    });

    test('changing the as-of date re-queries the server', () async {
      final subject = controller();
      await subject.load();

      await subject.setAsOfDate(DateTime(2024, 6, 30));

      expect(port.queries, hasLength(2));
      expect(
        port.queries.last.asOfDate,
        DateTime(2024, 6, 30),
        reason: 'the validity periods live on the server. A client-side filter '
            'over one day\'s answer could not produce another day\'s',
      );
    });

    test('a member without security.manage cannot mutate', () async {
      final subject = controller(permissions: const <String>{'workspace.read'});
      await subject.load();

      expect(subject.canMutate, isFalse);

      await subject.verify(rule: _rule(), verified: true);

      expect(
        port.verifyCommands,
        isEmpty,
        reason: 'refused here rather than sent: nobody should spend a round '
            'trip on a certain refusal',
      );
      expect(subject.state.actionPhase, ComplianceRulesActionPhase.failed);
    });

    test('but they can read', () async {
      final subject = controller(permissions: const <String>{'workspace.read'});

      await subject.load();

      expect(subject.state.phase, ComplianceRulesPhase.ready);
    });

    test('editing a rule warns that the confirmation falls away', () async {
      final subject = controller();
      await subject.load();

      await subject.upsert(
        ruleKey: 'co2_price_eur_per_tonne',
        validFrom: DateTime(2026, 1, 1),
        value: 65,
        sourceReference: 'BEHG',
        existing: _rule(confidence: ComplianceRuleConfidence.verified),
      );

      expect(
        subject.state.actionMessage,
        contains('Bestätigung ist damit erloschen'),
        reason: 'a consequence the reader did not ask for has to be said out '
            'loud. Silently dropping a verification would be worse',
      );
    });

    test('a refused read drops the list rather than leaving a stale one', () async {
      final subject = controller();
      await subject.load();
      expect(subject.state.rules, isNotEmpty);

      port.readFailure = ComplianceRulesFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, ComplianceRulesPhase.forbidden);
      expect(subject.state.ruleSet, isNull);
      expect(subject.state.unverifiedCount, 0);
    });

    test('an overlap is explained in the terms of the fix', () async {
      port.upsertFailure = ComplianceRulesFailureKind.overlap;
      final subject = controller();
      await subject.load();

      await subject.upsert(
        ruleKey: 'co2_price_eur_per_tonne',
        validFrom: DateTime(2026, 1, 1),
        value: 65,
        sourceReference: 'BEHG',
      );

      expect(subject.state.actionMessage, contains('zwei Antworten'));
    });

    test('a successful write re-reads instead of patching the list', () async {
      final subject = controller();
      await subject.load();
      expect(port.queries, hasLength(1));

      await subject.upsert(
        ruleKey: 'new_key',
        validFrom: DateTime(2026, 1, 1),
        value: 1,
        sourceReference: 'Quelle',
      );

      expect(
        port.queries,
        hasLength(2),
        reason: 'the rule that changed may have moved out of the date being '
            'shown, and reproducing the server\'s validity arithmetic here is '
            'how two answers to "what applies today" start to differ',
      );
    });
  });
}

ComplianceRuleSetDto _successOf(
  ComplianceRulesResult<ComplianceRuleSetDto> result,
) {
  return (result as ComplianceRulesSuccess<ComplianceRuleSetDto>).value;
}

ComplianceCommandContext _context() {
  return const ComplianceCommandContext(
    workspaceId: 'ws-1',
    actorId: 'actor-a',
    mutationId: 'mutation-1',
    correlationId: 'correlation-1',
  );
}

UpsertComplianceRuleCommand _upsert() {
  return UpsertComplianceRuleCommand(
    context: _context(),
    ruleKey: 'co2_price_eur_per_tonne',
    validFrom: DateTime(2026, 1, 1),
    value: 60,
    sourceReference: 'BEHG',
  );
}

ComplianceRuleDto _rule({
  String ruleKey = 'co2_price_eur_per_tonne',
  ComplianceRuleConfidence confidence = ComplianceRuleConfidence.unverified,
}) {
  return ComplianceRuleDto(
    id: 'rule-1',
    workspaceId: 'ws-1',
    ruleKey: ruleKey,
    jurisdiction: 'DE',
    validFrom: DateTime(2026, 1, 1),
    value: 60,
    sourceReference: 'BEHG',
    confidence: confidence,
    version: 1,
  );
}

Map<String, Object?> _ruleJson({
  Object? value = 55,
  String confidence = 'unverified',
  int version = 1,
  String ruleKey = 'co2_price_eur_per_tonne',
}) {
  return <String, Object?>{
    'id': 'rule-1',
    'workspace_id': 'ws-1',
    'rule_key': ruleKey,
    'jurisdiction': 'DE',
    'valid_from': '2025-01-01',
    'valid_to': '2025-12-31',
    'value': value,
    'unit': 'EUR/t',
    'source_reference': 'BEHG',
    'note': null,
    'confidence': confidence,
    'verified_by': null,
    'verified_at': null,
    'verification_note': null,
    'version': version,
  };
}

Map<String, Object?> _ruleSet({
  int unverified = 1,
  int decisionSupport = 0,
  String confidence = 'unverified',
}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'as_of_date': '2025-06-30',
      'jurisdiction': 'DE',
      'rules': <Object?>[
        _ruleJson(confidence: confidence),
        _ruleJson(ruleKey: 'umlageausfallwagnis_percent_max', value: 2),
      ],
      'unverified_count': unverified,
      'decision_support_count': decisionSupport,
    },
  };
}

class _FakeGateway implements ComplianceSupabaseGateway {
  Object? result;
  String? lastFunction;
  Map<String, Object?>? lastParameters;

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    lastFunction = function;
    lastParameters = parameters;
    return result;
  }
}

class _FakePort implements ComplianceRulesPort {
  final List<ComplianceRulesQuery> queries = <ComplianceRulesQuery>[];
  final List<VerifyComplianceRuleCommand> verifyCommands =
      <VerifyComplianceRuleCommand>[];
  ComplianceRulesFailureKind? readFailure;
  ComplianceRulesFailureKind? upsertFailure;

  @override
  Future<ComplianceRulesResult<ComplianceRuleSetDto>> readAsOf(
    ComplianceRulesQuery query,
  ) async {
    queries.add(query);
    final kind = readFailure;
    if (kind != null) {
      return ComplianceRulesFailure<ComplianceRuleSetDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return ComplianceRulesSuccess<ComplianceRuleSetDto>(
      ComplianceRuleSetDto(
        asOfDate: query.asOfDate ?? DateTime(2026, 9, 7),
        jurisdiction: 'DE',
        rules: <ComplianceRuleDto>[_rule()],
        unverifiedCount: 1,
        decisionSupportCount: 0,
      ),
    );
  }

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> upsert(
    UpsertComplianceRuleCommand command,
  ) async {
    final kind = upsertFailure;
    if (kind != null) {
      return ComplianceRulesFailure<ComplianceRuleDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return ComplianceRulesSuccess<ComplianceRuleDto>(_rule());
  }

  @override
  Future<ComplianceRulesResult<ComplianceRuleDto>> verify(
    VerifyComplianceRuleCommand command,
  ) async {
    verifyCommands.add(command);
    return ComplianceRulesSuccess<ComplianceRuleDto>(
      _rule(confidence: ComplianceRuleConfidence.verified),
    );
  }
}
