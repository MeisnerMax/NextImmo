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
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_account_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/betrkv_catalogue.dart';
import 'package:neximmo_app/features/finance_ledger/domain/cost_allocation_dto.dart';
import 'package:neximmo_app/features/finance_ledger/domain/finance_actuals_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  _costTypeTests();

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
    late _FakeAccountsPort accountsPort;

    CostAllocationController controller({
      Set<String> permissions = const <String>{'finance.read', 'finance.manage'},
    }) {
      final subject = CostAllocationController(
        port: port,
        accountsPort: accountsPort,
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
      accountsPort = _FakeAccountsPort();
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

CostAccountAllocationDto _account({
  required bool withRule,
  int? version = 7,
}) {
  return CostAccountAllocationDto(
    financeAccountId: 'account-1',
    code: '4210',
    name: 'Heizkosten',
    accountType: 'expense',
    isActive: true,
    version: version,
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

  /// Null models a server that predates FINANCE-COST-TYPES-01.
  int? accountVersion = 7;
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
        accounts: <CostAccountAllocationDto>[
          _account(withRule: false, version: accountVersion),
        ],
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


class _FakeAccountsPort implements FinanceAccountsPort {
  final List<CreateFinanceAccountCommand> creates =
      <CreateFinanceAccountCommand>[];
  final List<UpdateFinanceAccountCommand> updates =
      <UpdateFinanceAccountCommand>[];
  String? failureField;

  @override
  Future<FinanceRepositoryResult<CostAccountAllocationDto>> createAccount(
    CreateFinanceAccountCommand command,
  ) async {
    creates.add(command);
    return _answer();
  }

  @override
  Future<FinanceRepositoryResult<CostAccountAllocationDto>> updateAccount(
    UpdateFinanceAccountCommand command,
  ) async {
    updates.add(command);
    return _answer();
  }

  FinanceRepositoryResult<CostAccountAllocationDto> _answer() {
    final String? field = failureField;
    if (field != null) {
      return FinanceRepositoryFailure<CostAccountAllocationDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'refused',
        field: field,
      );
    }
    return FinanceRepositorySuccess<CostAccountAllocationDto>(
      _account(withRule: false),
    );
  }
}

/// FINANCE-COST-TYPES-01: the cost types themselves.
///
/// The account tree had audited, idempotent, granted commands and no client
/// that could call them, because `update_finance_account` requires a version
/// the only account-listing read did not return. These tests are about the
/// half of that fix that lives here.
void _costTypeTests() {
  group('cost type adapter', () {
    late _FakeGateway gateway;
    late SupabaseFinanceAccountAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseFinanceAccountAdapter.withGateway(gateway);
    });

    test('a code that could not be stored is refused before the round trip',
        () async {
      final FinanceRepositoryResult<CostAccountAllocationDto> result =
          await adapter.createAccount(
        CreateFinanceAccountCommand(
          context: _context(),
          code: 'Heiz kosten',
          name: 'Heizkosten',
          accountType: FinanceAccountType.expense,
        ),
      );

      expect(gateway.calls, 0);
      final failure =
          result as FinanceRepositoryFailure<CostAccountAllocationDto>;
      expect(failure.field, 'code');
      expect(
        failure.message,
        contains('nicht mehr ändern'),
        reason: 'the reason a code is fussy is that it is permanent, and the '
            'message is the only place the reader learns that before they '
            'commit to one',
      );
    });

    test('an account kind this build does not know is never written back',
        () async {
      final FinanceRepositoryResult<CostAccountAllocationDto> result =
          await adapter.createAccount(
        CreateFinanceAccountCommand(
          context: _context(),
          code: '4210',
          name: 'Heizkosten',
          accountType: FinanceAccountType.unknown,
        ),
      );

      expect(gateway.calls, 0);
      expect(
        (result as FinanceRepositoryFailure<CostAccountAllocationDto>).field,
        'accountType',
      );
    });

    test('the create parses the command snapshot, which names the id "id"',
        () async {
      // Not `finance_account_id`: that is the list read's shape. Two shapes
      // for one row is exactly where a parser quietly returns nothing.
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'id': 'account-9',
          'workspace_id': 'ws-1',
          'code': '4300',
          'name': 'Hausmeister',
          'account_type': 'expense',
          'parent_account_id': null,
          'is_active': true,
          'version': 1,
        },
      };

      final CostAccountAllocationDto value =
          (await adapter.createAccount(
                    CreateFinanceAccountCommand(
                      context: _context(),
                      code: '4300',
                      name: 'Hausmeister',
                      accountType: FinanceAccountType.expense,
                    ),
                  )
                  as FinanceRepositorySuccess<CostAccountAllocationDto>)
              .value;

      expect(value.financeAccountId, 'account-9');
      expect(value.version, 1);
      expect(value.isEditable, isTrue);
      expect(gateway.lastParameters!['p_account_type'], 'expense');
    });

    test('a taken code lands as a validation failure with the server\'s reason',
        () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_conflict',
          'message': 'An account with this code already exists',
        },
      };

      final FinanceRepositoryResult<CostAccountAllocationDto> result =
          await adapter.createAccount(
        CreateFinanceAccountCommand(
          context: _context(),
          code: '4300',
          name: 'Hausmeister',
          accountType: FinanceAccountType.expense,
        ),
      );

      final failure =
          result as FinanceRepositoryFailure<CostAccountAllocationDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.message, contains('already exists'));
    });

    test('the update sends the version it was given, and no code', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'id': 'account-1',
          'workspace_id': 'ws-1',
          'code': '4210',
          'name': 'Heizung',
          'account_type': 'expense',
          'parent_account_id': null,
          'is_active': true,
          'version': 8,
        },
      };

      await adapter.updateAccount(
        UpdateFinanceAccountCommand(
          context: _context(),
          accountId: 'account-1',
          expectedVersion: 7,
          name: 'Heizung',
        ),
      );

      expect(gateway.lastParameters!['p_expected_version'], 7);
      expect(
        gateway.lastParameters!.containsKey('p_code'),
        isFalse,
        reason: 'the server takes no code on an update, so sending one would '
            'be sending a parameter that does not exist',
      );
    });
  });

  group('cost type controller', () {
    late _FakePort port;
    late _FakeAccountsPort accountsPort;

    CostAllocationController controller({
      Set<String> permissions = const <String>{'finance.read', 'finance.manage'},
    }) {
      final subject = CostAllocationController(
        port: port,
        accountsPort: accountsPort,
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
      accountsPort = _FakeAccountsPort();
    });

    test('a create re-reads, because the unclassified count is the server\'s',
        () async {
      final subject = controller();
      await subject.load();
      expect(port.reads, 1);

      final CostAllocationActionFailure? failure = await subject.createAccount(
        code: '4300',
        name: 'Hausmeister',
        accountType: FinanceAccountType.expense,
      );

      expect(failure, isNull);
      expect(accountsPort.creates.single.code, '4300');
      expect(port.reads, 2);
    });

    test('a refusal is returned, not only put in state', () async {
      accountsPort.failureField = 'code';
      final subject = controller();
      await subject.load();

      final CostAllocationActionFailure? failure = await subject.createAccount(
        code: '4300',
        name: 'Hausmeister',
        accountType: FinanceAccountType.expense,
      );

      expect(
        failure?.field,
        'code',
        reason: 'a dialog has to stay open and point at the field; it cannot '
            'do that from a state it stopped watching when it popped',
      );
    });

    test('the update reads the version from its own state, not from the caller',
        () async {
      final subject = controller();
      await subject.load();

      await subject.updateAccount(accountId: 'account-1', name: 'Heizung');

      expect(
        accountsPort.updates.single.expectedVersion,
        7,
        reason: 'the version comes from the list this controller last loaded, '
            'so a retry after a version conflict sends the fresh one',
      );
    });

    test('an account the server sent no version for is refused, with the reason',
        () async {
      port.accountVersion = null;
      final subject = controller();
      await subject.load();

      final CostAllocationActionFailure? failure =
          await subject.updateAccount(accountId: 'account-1', name: 'Heizung');

      expect(accountsPort.updates, isEmpty);
      expect(failure, isNotNull);
      expect(
        failure!.message,
        contains('keine Version'),
        reason: 'an edit with an invented version is refused server-side, so '
            'the honest refusal is here and it says why',
      );
    });

    test('a member without finance.manage cannot create one', () async {
      final subject = controller(permissions: const <String>{'finance.read'});
      await subject.load();

      final CostAllocationActionFailure? failure = await subject.createAccount(
        code: '4300',
        name: 'Hausmeister',
        accountType: FinanceAccountType.expense,
      );

      expect(accountsPort.creates, isEmpty);
      expect(failure, isNotNull);
    });
  });

  group('BetrKV suggestions', () {
    test('the catalogue is the seventeen positions of § 2', () {
      expect(betrkvSuggestions, hasLength(17));
      expect(
        betrkvSuggestions.map((BetrkvSuggestion s) => s.position),
        <String>[
          '1', '2', '3', '4', '5', '6', '7', '8', '9',
          '10', '11', '12', '13', '14', '15', '16', '17',
        ],
      );
    });

    test('the heating positions pre-fill the HeizkostenV flag', () {
      final Iterable<String> heating = betrkvSuggestions
          .where((BetrkvSuggestion s) => s.underHeatingCostRegulation)
          .map((BetrkvSuggestion s) => s.position);
      expect(
        heating,
        <String>['4', '5', '6'],
        reason: 'P-2a already enforces the consequence as a CHECK; this only '
            'pre-fills the form, and the person creating the cost type '
            'confirms it',
      );
    });

    test('every suggestion has a storable code', () {
      for (final BetrkvSuggestion suggestion in betrkvSuggestions) {
        expect(
          financeAccountCodePattern.hasMatch(suggestion.suggestedCode),
          isTrue,
          reason: 'a suggestion the server would refuse is worse than no '
              'suggestion: ${suggestion.suggestedCode}',
        );
      }
    });

    test('adopted positions drop out, matched on the position text', () {
      final List<BetrkvSuggestion> outstanding = outstandingBetrkvSuggestions(
        <String?>[
          '  kosten der gartenpflege  ',
          'Kosten für den Hauswart',
          null,
          'Etwas ganz anderes',
        ],
      );

      expect(outstanding, hasLength(15));
      expect(
        outstanding.map((BetrkvSuggestion s) => s.position),
        isNot(contains('10')),
        reason: 'matched case- and whitespace-insensitively, because the '
            'workspace types the position text and nobody should be offered '
            'an item twice over a stray space',
      );
      expect(outstanding.map((BetrkvSuggestion s) => s.position),
          isNot(contains('14')));
    });

    test('a workspace that renamed a cost type is not offered it again', () {
      // The name and the code belong to the workspace; the position text is
      // what identifies the item.
      final List<BetrkvSuggestion> outstanding = outstandingBetrkvSuggestions(
        <String?>['Kosten für den Hauswart'],
      );
      expect(
        outstanding.map((BetrkvSuggestion s) => s.position),
        isNot(contains('14')),
      );
    });

    test('nothing is offered once every position is taken', () {
      expect(
        outstandingBetrkvSuggestions(
          betrkvSuggestions.map((BetrkvSuggestion s) => s.positionText),
        ),
        isEmpty,
      );
    });
  });
}
