/// UNIT-BASIS-VALUES-01 (P-2c): the client half.
///
/// Four things this side must never do:
///
///   * **Derive its own verdict.** Whether a basis is usable is the server's
///     answer, and it is the same answer the settlement engine will get. A
///     screen that recomputed it could report the basis ready while the run
///     refuses it.
///   * **Read an unanswered question as "yes".** A payload with no resolution
///     is an unresolved basis with an unstated reason, never a resolved one.
///   * **Send a figure with no convention.** No counting rule is agreed for
///     any of these three bases, so a figure that does not say how it was
///     measured cannot be checked, and two measured differently cannot be
///     added.
///   * **Confuse zero with unrecorded.** A unit with nobody in it is a real
///     answer; a unit nobody has recorded is what makes the basis
///     unresolvable. Collapsing them would make the missing count
///     unexplainable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/cost_pool_controller.dart'
    show CostPoolActionFailure;
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/application/unit_basis_value_controller.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_unit_basis_value_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/cost_pool_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  _figureParserTests();

  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseUnitBasisValueAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseUnitBasisValueAdapter.withGateway(gateway);
    });

    test('a unit with no figure keeps a null value', () async {
      gateway.result = _overview();

      final UnitBasisOverviewDto value = _successOf(
        await adapter.readBasisValues(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
          basis: AllocationBasis.persons,
        ),
      );

      expect(value.units, hasLength(3));
      expect(value.units[0].hasValue, isTrue);
      expect(
        value.units[2].value,
        isNull,
        reason: 'a unit nobody has recorded and a unit recorded as zero mean '
            'different things, and only one of them blocks the basis',
      );
      expect(value.recordedCount, 2);
      expect(value.missing, hasLength(1));
    });

    test('zero is a recorded figure, not an absent one', () async {
      gateway.result = _overview();

      final UnitBasisOverviewDto value = _successOf(
        await adapter.readBasisValues(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
          basis: AllocationBasis.persons,
        ),
      );

      expect(value.units[1].value!.value, 0);
      expect(
        value.units[1].hasValue,
        isTrue,
        reason: 'paired with the case above so neither passes by hasValue '
            'always answering the same thing',
      );
    });

    test('the verdict is read, never derived from the rows', () async {
      // Two of three rows carry a figure, yet the server says the basis
      // resolves — because it counted over the units it knows about, not the
      // ones this payload happened to carry.
      gateway.result = _overview(
        resolution: <String, Object?>{
          'resolvable': true,
          'reason': null,
          'unit_count': 2,
          'units_without_value': 0,
          'total': 5,
          'convention': 'Stichtag 1. Januar',
          'convention_count': 1,
          'detail': 'Sum of the recorded values.',
        },
      );

      final UnitBasisOverviewDto value = _successOf(
        await adapter.readBasisValues(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
          basis: AllocationBasis.persons,
        ),
      );

      expect(value.resolution.resolvable, isTrue);
      expect(value.resolution.total, 5);
      expect(value.resolution.convention, 'Stichtag 1. Januar');
    });

    test('mixed conventions come through as their own reason', () async {
      gateway.result = _overview(
        resolution: <String, Object?>{
          'resolvable': false,
          'reason': 'mixed_conventions',
          'unit_count': 3,
          'units_without_value': 0,
          'total': null,
          'convention': null,
          'convention_count': 2,
          'detail': 'The units state 2 different conventions.',
        },
      );

      final UnitBasisOverviewDto value = _successOf(
        await adapter.readBasisValues(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
          basis: AllocationBasis.persons,
        ),
      );

      expect(
        value.resolution.reason,
        AllocationUnresolvableReason.mixedConventions,
      );
      expect(value.resolution.conventionCount, 2);
      expect(
        value.resolution.total,
        isNull,
        reason: 'adding a Stichtag figure to a Personenmonate figure does not '
            'produce a denominator, so no total is offered',
      );
    });

    test('a payload with no resolution is not resolvable', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': <String, Object?>{
          'as_of_date': '2026-06-01',
          'basis': 'persons',
          'units': <Map<String, Object?>>[],
        },
      };

      final UnitBasisOverviewDto value = _successOf(
        await adapter.readBasisValues(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
          basis: AllocationBasis.persons,
        ),
      );

      expect(value.resolution.resolvable, isFalse);
      expect(
        value.resolution.reason,
        AllocationUnresolvableReason.notEvaluated,
        reason: 'an unanswered question must not land on "yes"',
      );
    });

    test('a basis this store does not hold is refused before the round trip',
        () async {
      final FinanceRepositoryResult<UnitBasisOverviewDto> result = await adapter
          .readBasisValues(
            workspaceId: 'ws-1',
            propertyId: 'property-1',
            basis: AllocationBasis.areaSqm,
          );

      expect(gateway.calls, 0);
      final failure =
          result as FinanceRepositoryFailure<UnitBasisOverviewDto>;
      expect(failure.field, 'basis');
    });

    test('a figure with no convention is refused before the round trip',
        () async {
      final FinanceRepositoryResult<UnitBasisValueDto> result = await adapter
          .upsertBasisValue(_command(convention: '   '));

      expect(gateway.calls, 0);
      final failure = result as FinanceRepositoryFailure<UnitBasisValueDto>;
      expect(failure.field, 'convention');
      expect(failure.message, contains('Zählregel'));
    });

    test('a negative figure is refused, and zero is not', () async {
      final FinanceRepositoryResult<UnitBasisValueDto> refused = await adapter
          .upsertBasisValue(_command(value: -1));
      expect(gateway.calls, 0);
      expect(
        (refused as FinanceRepositoryFailure<UnitBasisValueDto>).field,
        'value',
      );

      gateway.result = <String, Object?>{'ok': true, 'entity': _valueRow(value: 0)};
      final FinanceRepositoryResult<UnitBasisValueDto> accepted = await adapter
          .upsertBasisValue(_command(value: 0));
      expect(accepted, isA<FinanceRepositorySuccess<UnitBasisValueDto>>());
      expect(gateway.lastParameters!['p_value'], 0);
    });

    test('dates are sent as plain calendar days', () async {
      gateway.result = <String, Object?>{'ok': true, 'entity': _valueRow()};

      await adapter.upsertBasisValue(
        _command(
          validFrom: DateTime(2026, 1, 5),
          validTo: DateTime(2026, 12, 31),
        ),
      );

      expect(gateway.lastParameters!['p_valid_from'], '2026-01-05');
      expect(
        gateway.lastParameters!['p_valid_to'],
        '2026-12-31',
        reason: 'a timestamp would let a UTC offset move the day a figure '
            'takes effect',
      );
    });

    test('an overlapping period lands as a validation failure with the '
        'server\'s reason', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_conflict',
          'message': 'This unit already has a value covering part of that period',
        },
      };

      final FinanceRepositoryResult<UnitBasisValueDto> result =
          await adapter.upsertBasisValue(_command());

      final failure = result as FinanceRepositoryFailure<UnitBasisValueDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.message, contains('already has a value'));
    });
  });

  group('controller', () {
    late _FakePort port;

    UnitBasisController controller({
      Set<String> permissions = const <String>{'finance.read', 'finance.manage'},
    }) {
      final UnitBasisController subject = UnitBasisController(
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'ws-1',
          actorId: 'actor-a',
          permissions: permissions,
          mutationsSupported: true,
        ),
        propertyId: 'property-1',
        basis: AllocationBasis.persons,
        idFactory: () => 'id-1',
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() {
      port = _FakePort();
    });

    test('reads the version from its own state, not from the caller', () async {
      final UnitBasisController subject = controller();
      await subject.load();

      await subject.saveValue(
        unitId: 'unit-2',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(port.commands.last.expectedVersion, isNull);

      await subject.saveValue(
        unitId: 'unit-1',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(port.commands.last.expectedVersion, 4);
    });

    test('a member without finance.manage cannot write', () async {
      final UnitBasisController subject = controller(
        permissions: const <String>{'finance.read'},
      );
      await subject.load();

      final CostPoolActionFailure? failure = await subject.saveValue(
        unitId: 'unit-1',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );

      expect(port.commands, isEmpty);
      expect(failure, isNotNull);
      expect(subject.state.actionPhase, UnitBasisActionPhase.failed);
    });

    test('a refusal is returned, not only put in state', () async {
      port.writeFailureField = 'convention';
      final UnitBasisController subject = controller();
      await subject.load();

      final CostPoolActionFailure? failure = await subject.saveValue(
        unitId: 'unit-1',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );

      expect(
        failure?.field,
        'convention',
        reason: 'a dialog has to stay open and point at the field; it cannot '
            'do that from a state it stopped watching when it popped',
      );
    });

    test('a write re-reads either way, because one figure changes the verdict '
        'for the whole property', () async {
      final UnitBasisController subject = controller();
      await subject.load();
      expect(port.reads, 1);

      await subject.saveValue(
        unitId: 'unit-1',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(port.reads, 2);

      port.writeFailureField = 'expectedVersion';
      await subject.saveValue(
        unitId: 'unit-1',
        value: 3,
        convention: 'Stichtag',
        validFrom: DateTime(2026, 1, 1),
      );
      expect(
        port.reads,
        3,
        reason: 'without this a version conflict re-sends the same stale '
            'version forever',
      );
    });

    test('the date the state shows is the one the server echoed', () async {
      final UnitBasisController subject = controller();
      port.asOf = DateTime(2026, 3, 1);
      await subject.load();
      expect(subject.state.asOf, DateTime(2026, 3, 1));

      port.asOf = DateTime(2024, 12, 31);
      await subject.showDate(DateTime(2024, 12, 31));
      expect(port.lastAsOfAsked, DateTime(2024, 12, 31));
      expect(subject.state.asOf, DateTime(2024, 12, 31));
    });

    test('a refused read drops the overview rather than leaving a stale one',
        () async {
      final UnitBasisController subject = controller();
      await subject.load();
      expect(subject.state.units, isNotEmpty);

      port.readFailure = FinanceRepositoryFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, UnitBasisPhase.forbidden);
      expect(subject.state.overview, isNull);
      expect(subject.state.isResolvable, isFalse);
      expect(subject.state.missingCount, 0);
    });

    test('the resolvable verdict comes from the port, not from the rows',
        () async {
      final UnitBasisController subject = controller();
      await subject.load();

      // The fake returns one row without a figure and a verdict that says the
      // basis resolves. A controller deriving its own answer would disagree.
      expect(subject.state.missingCount, 1);
      expect(
        subject.state.isResolvable,
        isTrue,
        reason: 'the settlement engine reads the same verdict, and a screen '
            'that computed its own could contradict it',
      );
    });
  });
}

UnitBasisOverviewDto _successOf(
  FinanceRepositoryResult<UnitBasisOverviewDto> result,
) => (result as FinanceRepositorySuccess<UnitBasisOverviewDto>).value;

FinanceCommandContext _context() => const FinanceCommandContext(
  workspaceId: 'ws-1',
  actorId: 'actor-a',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

UpsertUnitBasisValueCommand _command({
  num value = 3,
  String convention = 'Stichtag 1. Januar, gemeldete Bewohner',
  DateTime? validFrom,
  DateTime? validTo,
}) {
  return UpsertUnitBasisValueCommand(
    context: _context(),
    unitId: 'unit-1',
    basis: AllocationBasis.persons,
    value: value,
    convention: convention,
    validFrom: validFrom ?? DateTime(2026, 1, 1),
    validTo: validTo,
  );
}

UnitBasisValueDto _valueDto() => UnitBasisValueDto(
  id: 'value-1',
  workspaceId: 'ws-1',
  unitId: 'unit-1',
  basis: AllocationBasis.persons,
  value: 3,
  convention: 'Stichtag 1. Januar',
  validFrom: DateTime(2026, 1, 1),
  version: 4,
);

Map<String, Object?> _valueRow({String id = 'value-1', num value = 3}) {
  return <String, Object?>{
    'id': id,
    'workspace_id': 'ws-1',
    'unit_id': 'unit-1',
    'basis': 'persons',
    'value': value,
    'convention': 'Stichtag 1. Januar, gemeldete Bewohner',
    'valid_from': '2026-01-01',
    'valid_to': null,
    'note': null,
    'version': 1,
  };
}

Map<String, Object?> _overview({Map<String, Object?>? resolution}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'as_of_date': '2026-06-01',
      'basis': 'persons',
      'units': <Map<String, Object?>>[
        <String, Object?>{
          'unit_id': 'unit-1',
          'unit_code': 'A-01',
          'area_sqm': 50,
          'value': _valueRow(value: 2),
        },
        <String, Object?>{
          'unit_id': 'unit-2',
          'unit_code': 'A-02',
          'area_sqm': 30,
          // Zero is a real answer, and must not read as absent.
          'value': _valueRow(id: 'value-2', value: 0),
        },
        <String, Object?>{
          'unit_id': 'unit-3',
          'unit_code': 'A-03',
          'area_sqm': 40,
          'value': null,
        },
      ],
      'resolution':
          resolution ??
          <String, Object?>{
            'resolvable': false,
            'reason': 'incomplete_basis',
            'unit_count': 3,
            'units_without_value': 1,
            'total': null,
            'convention': 'Stichtag 1. Januar, gemeldete Bewohner',
            'convention_count': 1,
            'detail': 'Recorded for 2 of 3 units.',
          },
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

class _FakePort implements UnitBasisValuesPort {
  int reads = 0;
  DateTime? asOf;
  DateTime? lastAsOfAsked;
  final List<UpsertUnitBasisValueCommand> commands =
      <UpsertUnitBasisValueCommand>[];
  FinanceRepositoryFailureKind? readFailure;
  String? writeFailureField;

  @override
  Future<FinanceRepositoryResult<UnitBasisOverviewDto>> readBasisValues({
    required String workspaceId,
    required String propertyId,
    required AllocationBasis basis,
    DateTime? asOf,
  }) async {
    reads++;
    lastAsOfAsked = asOf;
    final FinanceRepositoryFailureKind? kind = readFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<UnitBasisOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<UnitBasisOverviewDto>(
      UnitBasisOverviewDto(
        asOfDate: this.asOf ?? DateTime(2026, 6, 1),
        basis: AllocationBasis.persons,
        units: <UnitBasisRowDto>[
          UnitBasisRowDto(
            unitId: 'unit-1',
            unitCode: 'A-01',
            areaSqm: 50,
            value: _valueDto(),
          ),
          const UnitBasisRowDto(unitId: 'unit-2', unitCode: 'A-02'),
        ],
        // Deliberately at odds with the rows above, so a controller deriving
        // its own verdict would answer differently from this one.
        resolution: const AllocationBasisResolutionDto(
          resolvable: true,
          total: 3,
          unitCount: 1,
          unitsWithoutValue: 0,
          convention: 'Stichtag 1. Januar',
          conventionCount: 1,
        ),
      ),
    );
  }

  @override
  Future<FinanceRepositoryResult<UnitBasisValueDto>> upsertBasisValue(
    UpsertUnitBasisValueCommand command,
  ) async {
    commands.add(command);
    final String? field = writeFailureField;
    if (field != null) {
      return FinanceRepositoryFailure<UnitBasisValueDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'refused',
        field: field,
      );
    }
    return FinanceRepositorySuccess<UnitBasisValueDto>(_valueDto());
  }
}

/// The figure parser (`parseGermanFigure`).
///
/// The form is German and the store feeds a settlement denominator, so a
/// misread separator is not a formatting nuisance: "1.000" read as one instead
/// of a thousand divides every share by a thousand and nothing downstream can
/// tell. The parser therefore refuses the one genuinely ambiguous shape rather
/// than picking a reading.
void _figureParserTests() {
  group('parseGermanFigure', () {
    num parsed(String raw) =>
        (parseGermanFigure(raw) as ParsedFigureValue).value;

    ParsedFigureProblemKind problem(String raw) =>
        (parseGermanFigure(raw) as ParsedFigureProblem).kind;

    test('a comma is the decimal separator', () {
      expect(parsed('2,5'), 2.5);
      expect(parsed('0,000001'), 0.000001);
    });

    test('full stops before a comma group thousands', () {
      expect(parsed('1.234,5'), 1234.5);
      expect(parsed('1.234.567,89'), 1234567.89);
    });

    test('several full stops can only be grouping', () {
      expect(parsed('1.234.567'), 1234567);
    });

    test('a lone full stop that is not a grouping pattern is a decimal point',
        () {
      expect(
        parsed('2.5'),
        2.5,
        reason: 'typed by somebody used to an English keyboard, and it has '
            'only one reading',
      );
      expect(parsed('1.0000'), 1.0);
    });

    test('"1.000" is refused, because it has two readings', () {
      expect(
        problem('1.000'),
        ParsedFigureProblemKind.ambiguousSeparator,
        reason: 'a thousand or one, and the difference is the whole '
            'denominator. Guessing is how a plausible wrong number gets in',
      );
      expect(problem('235.000'), ParsedFigureProblemKind.ambiguousSeparator);
    });

    test('the old normalisation would have silently misread it', () {
      // `text.replaceAll(',', '.')` then `num.parse` — what this form did
      // before. Kept as an assertion so the regression is named, not just
      // fixed.
      expect(num.parse('1.000'.replaceAll(',', '.')), 1.0);
      expect(
        parseGermanFigure('1.000'),
        isA<ParsedFigureProblem>(),
        reason: 'the entered thousand became one, and both the adapter and '
            'the server would have accepted it',
      );
    });

    test('NaN, infinities and overflow are refused as input, not as transport',
        () {
      expect(problem('NaN'), ParsedFigureProblemKind.notFinite);
      expect(problem('Infinity'), ParsedFigureProblemKind.notFinite);
      expect(
        problem('1e999'),
        ParsedFigureProblemKind.notFinite,
        reason: 'num.tryParse overflows it to infinity, and a sign test does '
            'not catch any of the three',
      );
    });

    test('empty, negative and unreadable each say which they are', () {
      expect(problem(''), ParsedFigureProblemKind.empty);
      expect(problem('   '), ParsedFigureProblemKind.empty);
      expect(problem('-1'), ParsedFigureProblemKind.negative);
      expect(problem('-2,5'), ParsedFigureProblemKind.negative);
      expect(problem('drei'), ParsedFigureProblemKind.notANumber);
      expect(problem('1,2,3'), ParsedFigureProblemKind.notANumber);
    });

    test('a negative figure is refused by default and allowed for the ledger', () {
      expect(problem('-1'), ParsedFigureProblemKind.negative);
      expect(
        (parseGermanFigure('-1.234,50', allowNegative: true)
                as ParsedFigureValue)
            .value,
        -1234.5,
        reason: 'the ledger amount is signed on purpose: a negative booking '
            'is a counter-booking, which is the only correction the schema '
            'offers',
      );
      expect(
        parseGermanFigure('-1.000', allowNegative: true),
        isA<ParsedFigureProblem>(),
        reason: 'the thousand-separator ambiguity is refused with a sign too',
      );
    });

    test('zero reads as zero, which is a figure and not an absence', () {
      expect(parsed('0'), 0);
      expect(parsed('0,0'), 0);
    });

    test('spaces and non-breaking spaces are ignored', () {
      expect(parsed('1 234,5'), 1234.5);
      expect(parsed('\u00a02,5\u00a0'), 2.5);
    });
  });
}
