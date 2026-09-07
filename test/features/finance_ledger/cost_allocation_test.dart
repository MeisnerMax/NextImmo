/// COST-ALLOCATION-RULES-01 (P-2a): the client half.
///
/// Three things this side must never do, each of which would look harmless:
///
///   * **Collapse "not classified" into "not apportionable".** They mean
///     different things to a settlement run, and collapsing them makes the
///     unclassified count unexplainable.
///   * **Count its own list.** The unclassified figure is the server's, over
///     every account in the workspace; a page-local count answers a different
///     question in the same words.
///   * **Send a HeizkostenV position on the outflow principle.** The server
///     refuses it and a CHECK makes it impossible — the client refuses it
///     first so the message arrives before the round trip and names the case.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/cost_allocation_controller.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_cost_allocation_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/cost_allocation_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseCostAllocationAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseCostAllocationAdapter.withGateway(gateway);
    });

    test('an unclassified account keeps a null rule', () async {
      gateway.result = _overview();

      final value = _successOf(await adapter.readRules(workspaceId: 'ws-1'));

      expect(value.accounts, hasLength(3));
      expect(value.accounts[0].rule, isNotNull);
      expect(
        value.accounts[2].rule,
        isNull,
        reason: 'an account nobody has classified and one classified as "not '
            'apportionable" mean different things to a settlement run',
      );
      expect(value.accounts[2].isClassified, isFalse);
      expect(value.accounts[1].isClassified, isTrue);
    });

    test('the counts are read, not derived from the list', () async {
      // Three rows returned, nine unclassified across the workspace.
      gateway.result = _overview(classified: 12, unclassified: 9, total: 21);

      final value = _successOf(await adapter.readRules(workspaceId: 'ws-1'));

      expect(value.accounts, hasLength(3));
      expect(value.unclassifiedCount, 9);
      expect(value.totalCount, 21);
      expect(
        value.isComplete,
        isFalse,
        reason: 'a client counting its own three rows would report the work '
            'finished while nine accounts were still unclassified',
      );
    });

    test('a HeizkostenV position on the outflow principle is refused here', () async {
      final result = await adapter.setRule(
        SetCostAllocationRuleCommand(
          context: _context(),
          financeAccountId: 'account-1',
          allocatable: true,
          settlementPrinciple: CostSettlementPrinciple.outflow,
          underHeatingCostRegulation: true,
        ),
      );

      expect(gateway.calls, 0, reason: 'no round trip on a certain refusal');
      final failure = result as FinanceRepositoryFailure<CostAllocationRuleDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.message, contains('BGH VIII ZR 156/11'));
      expect(failure.field, 'settlementPrinciple');
    });

    test('an unrecognised principle is never written back', () async {
      final result = await adapter.setRule(
        SetCostAllocationRuleCommand(
          context: _context(),
          financeAccountId: 'account-1',
          allocatable: true,
          settlementPrinciple: CostSettlementPrinciple.unknown,
        ),
      );

      expect(gateway.calls, 0);
      expect(
        (result as FinanceRepositoryFailure<CostAllocationRuleDto>).kind,
        FinanceRepositoryFailureKind.validationFailed,
        reason: 'writing back a classification this build did not make is '
            'worse than refusing',
      );
    });

    test('the expected version travels as given', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': _ruleJson(version: 3),
      };

      await adapter.setRule(
        SetCostAllocationRuleCommand(
          context: _context(),
          financeAccountId: 'account-1',
          allocatable: true,
          settlementPrinciple: CostSettlementPrinciple.outflow,
          expectedVersion: 2,
        ),
      );

      expect(gateway.lastParameters?['p_expected_version'], 2);
      expect(gateway.lastParameters?['p_settlement_principle'], 'outflow');
    });

    test('a first write sends no version', () async {
      gateway.result = <String, Object?>{'ok': true, 'entity': _ruleJson()};

      await adapter.setRule(
        SetCostAllocationRuleCommand(
          context: _context(),
          financeAccountId: 'account-1',
          allocatable: false,
        ),
      );

      expect(
        gateway.lastParameters?['p_expected_version'],
        isNull,
        reason: 'the server refuses a version on a first write rather than '
            'letting a caller invent one',
      );
    });

    test('a malformed answer fails rather than reporting no accounts', () async {
      gateway.result = <String, Object?>{'ok': true, 'entity': <String, Object?>{}};

      final result = await adapter.readRules(workspaceId: 'ws-1');

      expect(
        (result as FinanceRepositoryFailure<CostAllocationOverviewDto>).kind,
        FinanceRepositoryFailureKind.infrastructureFailure,
        reason: '"no cost accounts" would read as nothing left to classify',
      );
    });
  });

  group('rule semantics', () {
    test('an unrecognised principle is not usable for settlement', () {
      const rule = CostAllocationRuleDto(
        financeAccountId: 'a',
        workspaceId: 'ws-1',
        allocatable: true,
        underHeatingCostRegulation: false,
        settlementPrinciple: CostSettlementPrinciple.unknown,
        version: 1,
      );

      expect(
        rule.isUsableForSettlement,
        isFalse,
        reason: 'a newer server could introduce a stricter principle, and '
            'treating what this build does not recognise as usable is how a '
            'cost gets apportioned on a rule nobody here understands',
      );
    });

    test('a non-apportionable cost is not usable either', () {
      const rule = CostAllocationRuleDto(
        financeAccountId: 'a',
        workspaceId: 'ws-1',
        allocatable: false,
        underHeatingCostRegulation: false,
        version: 1,
      );

      expect(rule.isUsableForSettlement, isFalse);
    });

    test('an apportionable cost with a known principle is', () {
      const rule = CostAllocationRuleDto(
        financeAccountId: 'a',
        workspaceId: 'ws-1',
        allocatable: true,
        underHeatingCostRegulation: true,
        settlementPrinciple: CostSettlementPrinciple.performance,
        version: 1,
      );

      expect(
        rule.isUsableForSettlement,
        isTrue,
        reason: 'paired with the two above so none of them passes by the '
            'getter always answering false',
      );
    });
  });

  group('controller', () {
    late _FakePort port;

    CostAllocationController controller({
      Set<String> permissions = const <String>{'finance.read', 'finance.manage'},
    }) {
      final subject = CostAllocationController(
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

    test('sends the account\'s own version, or none when it has no rule', () async {
      final subject = controller();
      await subject.load();

      await subject.setRule(
        account: _account(withRule: false),
        allocatable: false,
      );
      expect(port.commands.last.expectedVersion, isNull);

      await subject.setRule(
        account: _account(withRule: true),
        allocatable: true,
        settlementPrinciple: CostSettlementPrinciple.outflow,
      );
      expect(port.commands.last.expectedVersion, 4);
    });

    test('a member without finance.manage cannot write', () async {
      final subject = controller(permissions: const <String>{'finance.read'});
      await subject.load();

      expect(subject.canMutate, isFalse);
      await subject.setRule(
        account: _account(withRule: false),
        allocatable: true,
        settlementPrinciple: CostSettlementPrinciple.outflow,
      );

      expect(port.commands, isEmpty);
      expect(subject.state.actionPhase, CostAllocationActionPhase.failed);
    });

    test('a successful write re-reads, because the count is the server\'s',
        () async {
      final subject = controller();
      await subject.load();
      expect(port.reads, 1);

      await subject.setRule(
        account: _account(withRule: false),
        allocatable: false,
      );

      expect(port.reads, 2);
    });

    test('a refused read drops the overview rather than leaving a stale one',
        () async {
      final subject = controller();
      await subject.load();
      expect(subject.state.accounts, isNotEmpty);

      port.readFailure = FinanceRepositoryFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, CostAllocationPhase.forbidden);
      expect(subject.state.overview, isNull);
      expect(subject.state.unclassifiedCount, 0);
    });

    test('a rejected field survives to the state', () async {
      port.writeFailureField = 'settlementPrinciple';
      final subject = controller();
      await subject.load();

      await subject.setRule(
        account: _account(withRule: false),
        allocatable: true,
        settlementPrinciple: CostSettlementPrinciple.outflow,
      );

      expect(subject.state.actionField, 'settlementPrinciple');
      expect(subject.state.actionPhase, CostAllocationActionPhase.failed);
    });
  });
}

CostAllocationOverviewDto _successOf(
  FinanceRepositoryResult<CostAllocationOverviewDto> result,
) {
  return (result as FinanceRepositorySuccess<CostAllocationOverviewDto>).value;
}

FinanceCommandContext _context() {
  return const FinanceCommandContext(
    workspaceId: 'ws-1',
    actorId: 'actor-a',
    mutationId: 'mutation-1',
    correlationId: 'correlation-1',
  );
}

CostAccountAllocationDto _account({required bool withRule}) {
  return CostAccountAllocationDto(
    financeAccountId: 'account-1',
    code: '4210',
    name: 'Heizkosten',
    accountType: 'expense',
    isActive: true,
    rule: withRule
        ? const CostAllocationRuleDto(
            financeAccountId: 'account-1',
            workspaceId: 'ws-1',
            allocatable: true,
            underHeatingCostRegulation: true,
            settlementPrinciple: CostSettlementPrinciple.performance,
            version: 4,
          )
        : null,
  );
}

Map<String, Object?> _ruleJson({int version = 1}) {
  return <String, Object?>{
    'finance_account_id': 'account-1',
    'workspace_id': 'ws-1',
    'allocatable': true,
    'betrkv_position': null,
    'under_heating_cost_regulation': false,
    'settlement_principle': 'outflow',
    'note': null,
    'version': version,
  };
}

Map<String, Object?> _overview({
  int classified = 2,
  int unclassified = 1,
  int total = 3,
}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'accounts': <Object?>[
        <String, Object?>{
          'finance_account_id': 'account-1',
          'code': '4210',
          'name': 'Heizkosten',
          'account_type': 'expense',
          'is_active': true,
          'rule': _ruleJson(),
        },
        <String, Object?>{
          'finance_account_id': 'account-2',
          'code': '4900',
          'name': 'Instandhaltung',
          'account_type': 'expense',
          'is_active': true,
          'rule': <String, Object?>{
            'finance_account_id': 'account-2',
            'workspace_id': 'ws-1',
            'allocatable': false,
            'betrkv_position': null,
            'under_heating_cost_regulation': false,
            'settlement_principle': null,
            'note': null,
            'version': 1,
          },
        },
        <String, Object?>{
          'finance_account_id': 'account-3',
          'code': '4240',
          'name': 'Ungeklaert',
          'account_type': 'expense',
          'is_active': true,
          'rule': null,
        },
      ],
      'classified_count': classified,
      'unclassified_count': unclassified,
      'total_count': total,
    },
  };
}

class _FakeGateway implements FinanceSupabaseGateway {
  Object? result;
  int calls = 0;
  Map<String, Object?>? lastParameters;

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    calls++;
    lastParameters = parameters;
    return result;
  }
}

class _FakePort implements CostAllocationRulesPort {
  int reads = 0;
  final List<SetCostAllocationRuleCommand> commands =
      <SetCostAllocationRuleCommand>[];
  FinanceRepositoryFailureKind? readFailure;
  String? writeFailureField;

  @override
  Future<FinanceRepositoryResult<CostAllocationOverviewDto>> readRules({
    required String workspaceId,
    bool allocatableOnly = false,
  }) async {
    reads++;
    final kind = readFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<CostAllocationOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<CostAllocationOverviewDto>(
      CostAllocationOverviewDto(
        accounts: <CostAccountAllocationDto>[_account(withRule: false)],
        classifiedCount: 0,
        unclassifiedCount: 1,
        totalCount: 1,
      ),
    );
  }

  @override
  Future<FinanceRepositoryResult<CostAllocationRuleDto>> setRule(
    SetCostAllocationRuleCommand command,
  ) async {
    commands.add(command);
    final field = writeFailureField;
    if (field != null) {
      return FinanceRepositoryFailure<CostAllocationRuleDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'refused',
        field: field,
      );
    }
    return const FinanceRepositorySuccess<CostAllocationRuleDto>(
      CostAllocationRuleDto(
        financeAccountId: 'account-1',
        workspaceId: 'ws-1',
        allocatable: false,
        underHeatingCostRegulation: false,
        version: 1,
      ),
    );
  }
}
