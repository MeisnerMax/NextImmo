/// COST-POOLS-ALLOCATION-KEYS-01 (P-2b): the client half.
///
/// Four things this side must never do, each of which would look harmless and
/// each of which the legacy implementation actually did:
///
///   * **Treat a missing resolution as resolvable.** The command's snapshot
///     answers "what did I just write", not "what would this distribute over".
///     Absent must read as unresolvable, or a freshly saved key on a basis with
///     no data would show as usable.
///   * **Count its own list.** How many keys could not be resolved is the
///     server's figure over every matching key; a list-local count answers a
///     different question in the same words.
///   * **Act on a basis this build does not recognise.** A newer server can
///     introduce one, and a key whose measure nobody here understands is
///     exactly how a cost gets apportioned wrongly and plausibly.
///   * **Store a key with no explanation.** DEC-014 model consequence 2 makes
///     it one of the four Mindestangaben; its absence makes the statement
///     formally void, which costs the whole claim.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/cost_pool_controller.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_cost_pool_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/cost_pool_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseCostPoolAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseCostPoolAdapter.withGateway(gateway);
    });

    test('a pool at a scope with no entity reports itself unresolvable', () async {
      gateway.result = _poolOverview();

      final CostPoolOverviewDto value = _poolsOf(
        await adapter.readPools(workspaceId: 'ws-1'),
      );

      expect(value.pools, hasLength(3));
      expect(value.pools[0].scopeResolvable, isTrue);
      expect(
        value.pools[2].scopeResolvable,
        isFalse,
        reason: 'building, entrance and meter group have no entity in this '
            'schema, so such a pool can hold costs but cannot be distributed',
      );
      expect(value.pools[2].scopeUnresolvableReason, 'no_entity');
      expect(value.unresolvablePools, hasLength(1));
    });

    test('the resolution counts are read, not derived from the list', () async {
      // Two rows returned, eleven keys in force across the property.
      gateway.result = _keyOverview(resolvable: 4, unresolvable: 7, total: 11);

      final AllocationKeyOverviewDto value = _keysOf(
        await adapter.readAllocationKeys(workspaceId: 'ws-1'),
      );

      expect(value.keys, hasLength(2));
      expect(value.unresolvableCount, 7);
      expect(value.totalCount, 11);
      expect(
        value.hasUnresolvable,
        isTrue,
        reason: 'a client counting its own two rows would report one '
            'unresolvable key while seven could not be used',
      );
    });

    test('the date comes back from the server, not from the device', () async {
      gateway.result = _keyOverview(asOf: '2026-03-01');

      final AllocationKeyOverviewDto value = _keysOf(
        await adapter.readAllocationKeys(workspaceId: 'ws-1'),
      );

      expect(value.asOfDate, DateTime(2026, 3, 1));
      expect(
        gateway.lastParameters!['p_as_of'],
        isNull,
        reason: 'passing no date means "today", and only the server may decide '
            'which day that is',
      );
    });

    test('a key with no resolution is not usable', () async {
      // The write path's snapshot: it answers what was written, not what the
      // basis would distribute over.
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': _keyRow(includeResolution: false),
      };

      final AllocationKeyDto value =
          (await adapter.upsertAllocationKey(_keyCommand())
                  as FinanceRepositorySuccess<AllocationKeyDto>)
              .value;

      expect(value.basisResolution.resolvable, isFalse);
      expect(
        value.isUsableForSettlement,
        isFalse,
        reason: 'absent must not read as resolvable, or a key just saved on a '
            'basis with no data would show as usable',
      );
    });

    test('a resolved key is usable — the counterpart to the case above', () async {
      gateway.result = _keyOverview();

      final AllocationKeyOverviewDto value = _keysOf(
        await adapter.readAllocationKeys(workspaceId: 'ws-1'),
      );

      expect(value.keys[0].basisResolution.resolvable, isTrue);
      expect(value.keys[0].basisResolution.total, 80);
      expect(
        value.keys[0].isUsableForSettlement,
        isTrue,
        reason: 'paired with the case above so neither passes by the getter '
            'always answering false',
      );
    });

    test('an incomplete basis carries how many units are missing it', () async {
      gateway.result = _keyOverview();

      final AllocationKeyOverviewDto value = _keysOf(
        await adapter.readAllocationKeys(workspaceId: 'ws-1'),
      );

      final AllocationBasisResolutionDto resolution =
          value.keys[1].basisResolution;
      expect(resolution.resolvable, isFalse);
      expect(resolution.reason, AllocationUnresolvableReason.incompleteBasis);
      expect(resolution.unitsWithoutValue, 1);
      expect(value.keys[1].isUsableForSettlement, isFalse);
    });

    test('an unrecognised basis is kept but never usable', () async {
      gateway.result = _keyOverview(basis: 'per_moon_phase');

      final AllocationKeyOverviewDto value = _keysOf(
        await adapter.readAllocationKeys(workspaceId: 'ws-1'),
      );

      expect(value.keys[0].basis, AllocationBasis.unknown);
      expect(value.keys[0].rawBasisKey, 'per_moon_phase');
      expect(
        value.keys[0].isUsableForSettlement,
        isFalse,
        reason: 'the server said it resolves; this build does not know what it '
            'measures, and acting on it is how a cost is apportioned wrongly '
            'and plausibly',
      );
    });

    test('an unrecognised basis is never written back', () async {
      final FinanceRepositoryResult<AllocationKeyDto> result = await adapter
          .upsertAllocationKey(_keyCommand(basis: AllocationBasis.unknown));

      expect(gateway.calls, 0, reason: 'no round trip on a certain refusal');
      final failure = result as FinanceRepositoryFailure<AllocationKeyDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.field, 'basis');
    });

    test('a key with no explanation is refused before the round trip', () async {
      final FinanceRepositoryResult<AllocationKeyDto> result = await adapter
          .upsertAllocationKey(_keyCommand(explanation: '   '));

      expect(gateway.calls, 0);
      final failure = result as FinanceRepositoryFailure<AllocationKeyDto>;
      expect(failure.field, 'explanation');
      expect(failure.message, contains('Mindestangaben'));
    });

    test('a labelled scope without its label is refused here', () async {
      final FinanceRepositoryResult<CostPoolDto> result = await adapter
          .upsertPool(
            UpsertCostPoolCommand(
              context: _context(),
              poolKey: 'aufgang',
              name: 'Aufgang',
              scope: CostPoolScope.entrance,
              propertyId: 'property-1',
            ),
          );

      expect(gateway.calls, 0);
      final failure = result as FinanceRepositoryFailure<CostPoolDto>;
      expect(failure.field, 'scopeLabel');
    });

    test('a date is sent as a plain calendar day', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': _keyRow(includeResolution: false),
      };

      await adapter.upsertAllocationKey(
        _keyCommand(validFrom: DateTime(2026, 1, 5), validTo: DateTime(2026, 12, 31)),
      );

      expect(gateway.lastParameters!['p_valid_from'], '2026-01-05');
      expect(
        gateway.lastParameters!['p_valid_to'],
        '2026-12-31',
        reason: 'a timestamp would let a UTC offset move a validity boundary '
            'across the midnight the key takes effect on',
      );
    });

    test('an overlapping period lands as a validation failure, with the '
        'server\'s reason', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_conflict',
          'message': 'Another key already covers part of that period',
        },
      };

      final FinanceRepositoryResult<AllocationKeyDto> result =
          await adapter.upsertAllocationKey(_keyCommand());

      final failure = result as FinanceRepositoryFailure<AllocationKeyDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.message, contains('already covers'));
    });
  });

  group('controller', () {
    late _FakePort port;

    CostPoolController controller({
      Set<String> permissions = const <String>{'finance.read', 'finance.manage'},
    }) {
      final CostPoolController subject = CostPoolController(
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

    test('sends the pool\'s own version, or none when it is new', () async {
      final CostPoolController subject = controller();
      await subject.load();

      await subject.savePool(
        poolKey: 'heizung',
        name: 'Heizung',
        scope: CostPoolScope.property,
        propertyId: 'property-1',
      );
      expect(port.poolCommands.last.expectedVersion, isNull);

      await subject.savePool(
        existing: _pool(),
        poolKey: 'heizung',
        name: 'Heizung',
        scope: CostPoolScope.property,
        propertyId: 'property-1',
      );
      expect(port.poolCommands.last.expectedVersion, 4);
    });

    test('a member without finance.manage cannot write', () async {
      final CostPoolController subject = controller(
        permissions: const <String>{'finance.read'},
      );
      await subject.load();

      expect(subject.canMutate, isFalse);
      await subject.saveKey(
        propertyId: 'property-1',
        basis: AllocationBasis.areaSqm,
        explanation: 'Nach Wohnfläche',
        validFrom: DateTime(2026, 1, 1),
      );

      expect(port.keyCommands, isEmpty);
      expect(subject.state.actionPhase, CostPoolActionPhase.failed);
    });

    test('a successful write re-reads, because the counts are the server\'s',
        () async {
      final CostPoolController subject = controller();
      await subject.load();
      expect(port.keyReads, 1);

      await subject.saveKey(
        propertyId: 'property-1',
        basis: AllocationBasis.areaSqm,
        explanation: 'Nach Wohnfläche',
        validFrom: DateTime(2026, 1, 1),
      );

      expect(port.keyReads, 2);
    });

    test('the date the state shows is the one the server echoed', () async {
      final CostPoolController subject = controller();
      port.asOf = DateTime(2026, 3, 1);
      await subject.load();

      expect(subject.state.asOf, DateTime(2026, 3, 1));

      port.asOf = DateTime(2027, 6, 15);
      await subject.showDate(DateTime(2027, 6, 15));

      expect(port.lastAsOfAsked, DateTime(2027, 6, 15));
      expect(subject.state.asOf, DateTime(2027, 6, 15));
    });

    test('a failing key read drops the pools too', () async {
      final CostPoolController subject = controller();
      await subject.load();
      expect(subject.state.poolList, isNotEmpty);

      port.keyFailure = FinanceRepositoryFailureKind.infrastructureFailure;
      await subject.load();

      expect(subject.state.phase, CostPoolPhase.error);
      expect(
        subject.state.pools,
        isNull,
        reason: 'pools beside an empty key list would read as "no key is in '
            'force", which is the one conclusion this failure does not support',
      );
      expect(subject.state.unresolvableCount, 0);
    });

    test('a refused read drops the lists rather than leaving stale ones',
        () async {
      final CostPoolController subject = controller();
      await subject.load();
      expect(subject.state.keyList, isNotEmpty);

      port.poolFailure = FinanceRepositoryFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, CostPoolPhase.forbidden);
      expect(subject.state.keys, isNull);
      expect(subject.state.totalKeyCount, 0);
    });

    test('a rejected field survives to the state', () async {
      port.writeFailureField = 'explanation';
      final CostPoolController subject = controller();
      await subject.load();

      await subject.saveKey(
        propertyId: 'property-1',
        basis: AllocationBasis.areaSqm,
        explanation: 'Nach Wohnfläche',
        validFrom: DateTime(2026, 1, 1),
      );

      expect(subject.state.actionField, 'explanation');
      expect(subject.state.actionPhase, CostPoolActionPhase.failed);
    });

    test('the unresolvable subset is filtered, not recounted', () async {
      final CostPoolController subject = controller();
      await subject.load();

      expect(subject.state.keyList, hasLength(1));
      expect(subject.state.unresolvableKeys, hasLength(1));
      expect(
        subject.state.unresolvableCount,
        7,
        reason: 'the workspace figure stays the server\'s while the subset on '
            'screen is what the list happens to hold',
      );
    });
  });
}

CostPoolOverviewDto _poolsOf(FinanceRepositoryResult<CostPoolOverviewDto> r) =>
    (r as FinanceRepositorySuccess<CostPoolOverviewDto>).value;

AllocationKeyOverviewDto _keysOf(
  FinanceRepositoryResult<AllocationKeyOverviewDto> r,
) => (r as FinanceRepositorySuccess<AllocationKeyOverviewDto>).value;

FinanceCommandContext _context() => const FinanceCommandContext(
  workspaceId: 'ws-1',
  actorId: 'actor-a',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

UpsertAllocationKeyCommand _keyCommand({
  AllocationBasis basis = AllocationBasis.areaSqm,
  String explanation = 'Nach Wohnfläche, § 556a Abs. 1 BGB',
  DateTime? validFrom,
  DateTime? validTo,
}) {
  return UpsertAllocationKeyCommand(
    context: _context(),
    propertyId: 'property-1',
    basis: basis,
    explanation: explanation,
    validFrom: validFrom ?? DateTime(2026, 1, 1),
    validTo: validTo,
  );
}

CostPoolDto _pool() => const CostPoolDto(
  id: 'pool-1',
  workspaceId: 'ws-1',
  poolKey: 'heizung',
  name: 'Heizung',
  scope: CostPoolScope.property,
  propertyId: 'property-1',
  isActive: true,
  version: 4,
  scopeResolvable: true,
);

Map<String, Object?> _poolRow({
  required String id,
  required String poolKey,
  required String scope,
  String? propertyId,
  String? scopeLabel,
  bool scopeResolvable = true,
  String? unresolvableReason,
}) {
  return <String, Object?>{
    'id': id,
    'workspace_id': 'ws-1',
    'pool_key': poolKey,
    'name': 'Pool $poolKey',
    'scope': scope,
    'property_id': propertyId,
    'property_name': propertyId == null ? null : 'Poolhaus A',
    'scope_label': scopeLabel,
    'note': null,
    'is_active': true,
    'version': 1,
    'scope_resolvable': scopeResolvable,
    'scope_unresolvable_reason': unresolvableReason,
  };
}

Map<String, Object?> _poolOverview() {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'pools': <Map<String, Object?>>[
        _poolRow(id: 'pool-1', poolKey: 'betrieb', scope: 'portfolio'),
        _poolRow(
          id: 'pool-2',
          poolKey: 'heizung',
          scope: 'property',
          propertyId: 'property-1',
        ),
        _poolRow(
          id: 'pool-3',
          poolKey: 'aufgang',
          scope: 'entrance',
          propertyId: 'property-1',
          scopeLabel: 'Aufgang West',
          scopeResolvable: false,
          unresolvableReason: 'no_entity',
        ),
      ],
    },
  };
}

Map<String, Object?> _keyRow({
  String id = 'key-1',
  String basis = 'area_sqm',
  bool includeResolution = true,
  Map<String, Object?>? resolution,
}) {
  return <String, Object?>{
    'id': id,
    'workspace_id': 'ws-1',
    'property_id': 'property-1',
    'property_name': 'Poolhaus A',
    'finance_account_id': 'account-1',
    'finance_account_code': '4210',
    'finance_account_name': 'Heizkosten',
    'cost_pool_id': null,
    'cost_pool_key': null,
    'cost_pool_name': null,
    'basis': basis,
    'explanation': 'Nach Wohnfläche, § 556a Abs. 1 BGB',
    'valid_from': '2026-01-01',
    'valid_to': null,
    'note': null,
    'version': 1,
    if (includeResolution)
      'basis_resolution':
          resolution ??
          <String, Object?>{
            'resolvable': true,
            'reason': null,
            'unit_count': 2,
            'units_without_value': 0,
            'total': 80,
            'detail': 'The sum of units.area_sqm.',
          },
  };
}

Map<String, Object?> _keyOverview({
  String asOf = '2026-06-01',
  int resolvable = 1,
  int unresolvable = 1,
  int total = 2,
  String basis = 'area_sqm',
}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'as_of_date': asOf,
      'keys': <Map<String, Object?>>[
        _keyRow(basis: basis),
        _keyRow(
          id: 'key-2',
          resolution: <String, Object?>{
            'resolvable': false,
            'reason': 'incomplete_basis',
            'unit_count': 2,
            'units_without_value': 1,
            'total': 40,
            'detail': 'The sum of units.area_sqm.',
          },
        ),
      ],
      'resolvable_count': resolvable,
      'unresolvable_count': unresolvable,
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

class _FakePort implements CostPoolsPort {
  int poolReads = 0;
  int keyReads = 0;
  DateTime? asOf;
  DateTime? lastAsOfAsked;
  final List<UpsertCostPoolCommand> poolCommands = <UpsertCostPoolCommand>[];
  final List<UpsertAllocationKeyCommand> keyCommands =
      <UpsertAllocationKeyCommand>[];
  FinanceRepositoryFailureKind? poolFailure;
  FinanceRepositoryFailureKind? keyFailure;
  String? writeFailureField;

  @override
  Future<FinanceRepositoryResult<CostPoolOverviewDto>> readPools({
    required String workspaceId,
    String? propertyId,
    bool includeInactive = false,
  }) async {
    poolReads++;
    final FinanceRepositoryFailureKind? kind = poolFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<CostPoolOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<CostPoolOverviewDto>(
      CostPoolOverviewDto(pools: <CostPoolDto>[_pool()]),
    );
  }

  @override
  Future<FinanceRepositoryResult<AllocationKeyOverviewDto>> readAllocationKeys({
    required String workspaceId,
    DateTime? asOf,
    String? propertyId,
    String? financeAccountId,
  }) async {
    keyReads++;
    lastAsOfAsked = asOf;
    final FinanceRepositoryFailureKind? kind = keyFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<AllocationKeyOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<AllocationKeyOverviewDto>(
      AllocationKeyOverviewDto(
        asOfDate: this.asOf ?? DateTime(2026, 6, 1),
        keys: <AllocationKeyDto>[
          AllocationKeyDto(
            id: 'key-1',
            workspaceId: 'ws-1',
            propertyId: 'property-1',
            basis: AllocationBasis.persons,
            explanation: 'Nach Personenzahl',
            validFrom: DateTime(2026, 1, 1),
            version: 1,
            basisResolution: const AllocationBasisResolutionDto(
              resolvable: false,
              reason: AllocationUnresolvableReason.noBasisStore,
            ),
          ),
        ],
        resolvableCount: 4,
        unresolvableCount: 7,
        totalCount: 11,
      ),
    );
  }

  @override
  Future<FinanceRepositoryResult<CostPoolDto>> upsertPool(
    UpsertCostPoolCommand command,
  ) async {
    poolCommands.add(command);
    return _write<CostPoolDto>(_pool());
  }

  @override
  Future<FinanceRepositoryResult<AllocationKeyDto>> upsertAllocationKey(
    UpsertAllocationKeyCommand command,
  ) async {
    keyCommands.add(command);
    return _write<AllocationKeyDto>(
      AllocationKeyDto(
        id: 'key-1',
        workspaceId: 'ws-1',
        propertyId: 'property-1',
        basis: AllocationBasis.areaSqm,
        explanation: 'Nach Wohnfläche',
        validFrom: DateTime(2026, 1, 1),
        version: 1,
        basisResolution: const AllocationBasisResolutionDto(resolvable: false),
      ),
    );
  }

  FinanceRepositoryResult<T> _write<T>(T value) {
    final String? field = writeFailureField;
    if (field != null) {
      return FinanceRepositoryFailure<T>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'refused',
        field: field,
      );
    }
    return FinanceRepositorySuccess<T>(value);
  }
}
