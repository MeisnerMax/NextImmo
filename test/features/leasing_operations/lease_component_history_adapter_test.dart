/// LEASING-COMPONENTS-02 (V-2b): the client half of the history read.
///
/// What this file guards is that the client never re-decides anything the
/// server already decided. `in_force` is read, not derived from the dates;
/// gaps are read, not computed from the periods. Both are computable here, and
/// computing them would put two answers to the same question in the product —
/// which is the defect DEC-026 and the whole components line exist to avoid.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_component_dto.dart';

import 'leasing_gateway_fake.dart';

void main() {
  late FakeLeasingGateway gateway;
  late SupabaseLeaseComponentAdapter adapter;

  setUp(() {
    gateway = FakeLeasingGateway();
    adapter = SupabaseLeaseComponentAdapter.withGateway(gateway);
  });

  Future<LeasingRepositoryResult<LeaseComponentHistoryDto>> read() {
    return adapter.readHistory(
      const LeaseComponentHistoryQuery(
        workspaceId: 'ws-1',
        leaseId: 'lease-1',
      ),
    );
  }

  LeaseComponentHistoryDto valueOf(
    LeasingRepositoryResult<LeaseComponentHistoryDto> result,
  ) {
    return (result as LeasingRepositorySuccess<LeaseComponentHistoryDto>).value;
  }

  test('parses periods in the order the server sent them', () async {
    gateway.rpcResult = _answer();

    final history = valueOf(await read());

    expect(history.leaseId, 'lease-1');
    expect(history.timelines, hasLength(2));
    final base = history.timelines.first;
    expect(base.componentType, LeaseComponentType.baseRent);
    expect(base.periods, hasLength(3));
    expect(
      base.periods.map((LeaseComponentPeriodDto p) => p.amount),
      <double>[800, 900, 950],
      reason: 'the server ordered them oldest first; re-sorting here would be '
          'a second opinion about a sequence that is already decided',
    );
  });

  test('in_force is read, never derived', () async {
    gateway.rpcResult = _answer(
      // Deliberately contradictory: the flag says the *first* period is
      // current, which the dates would not support. The adapter must report
      // what the server said. If it ever starts computing this from the dates,
      // this expectation is what fails.
      inForceIndex: 0,
    );

    final base = valueOf(await read()).timelines.first;

    expect(base.periods[0].inForce, isTrue);
    expect(base.periods[1].inForce, isFalse);
    expect(base.current?.amount, 800);
  });

  test('a type with a hole has no current period, and that is an answer', () async {
    gateway.rpcResult = _answer(inForceIndex: null);

    final base = valueOf(await read()).timelines.first;

    expect(
      base.current,
      isNull,
      reason: 'null means the type has a gap at the date asked for -- not a '
          'lookup failure, and not a reason to fall back to a neighbouring '
          'period',
    );
  });

  test('gaps come back inclusive on both ends', () async {
    gateway.rpcResult = _answer();

    final base = valueOf(await read()).timelines.first;

    expect(base.gaps, hasLength(1));
    expect(base.gaps.single.from, DateTime.parse('2024-07-01'));
    expect(
      base.gaps.single.to,
      DateTime.parse('2024-12-31'),
      reason: 'the server converts its half-open range back at the boundary; '
          'a client that treated `to` as exclusive would move every gap end by '
          'a day',
    );
    expect(base.hasGap, isTrue);
  });

  test('a type without gaps reports none, and is not confused with one that '
      'has them', () async {
    gateway.rpcResult = _answer();

    final timelines = valueOf(await read()).timelines;

    expect(timelines[0].hasGap, isTrue);
    expect(
      timelines[1].hasGap,
      isFalse,
      reason: 'paired with the assertion above so neither could pass by the '
          'parser dropping gaps altogether',
    );
    expect(timelines[1].gaps, isEmpty);
  });

  test('a missing gaps field is empty, not a failure', () async {
    // An older server that has the periods but not the gap judgement. The
    // periods are still right, and refusing the whole read because one field
    // is younger than the deployment would lose the useful part with the new.
    gateway.rpcResult = _answer(omitGaps: true);

    final base = valueOf(await read()).timelines.first;

    expect(base.periods, hasLength(3));
    expect(base.gaps, isEmpty);
  });

  test('the note and the VAT treatment travel with the period', () async {
    gateway.rpcResult = _answer();

    final base = valueOf(await read()).timelines.first;

    expect(base.periods[2].note, 'Erhöhung');
    expect(base.periods[0].note, isNull);
    final vat = valueOf(await read()).timelines[1].periods.single;
    expect(vat.vatMode, LeaseComponentVatMode.net);
    expect(vat.grossMonthly, closeTo(119, 0.001));
  });

  test('a net period without a rate has no gross figure', () async {
    gateway.rpcResult = _answer(vatRate: null);

    final vat = valueOf(await read()).timelines[1].periods.single;

    expect(
      vat.grossMonthly,
      isNull,
      reason: 'returning the net amount as gross is the one thing this must '
          'never do -- it is the same rule the component row already holds, '
          'which is why both now call one function',
    );
  });

  test('an unfamiliar type keeps its raw key', () async {
    gateway.rpcResult = _answer(firstTypeKey: 'index_rent');

    final first = valueOf(await read()).timelines.first;

    expect(first.componentType, LeaseComponentType.unknown);
    expect(
      first.rawTypeKey,
      'index_rent',
      reason: 'shown verbatim, so a row from a newer server is visibly '
          'unfamiliar rather than quietly labelled "Sonstiges"',
    );
  });

  test('forbidden maps to the forbidden failure', () async {
    gateway.rpcResult = <String, Object?>{
      'ok': false,
      'error': <String, Object?>{
        'code': 'forbidden',
        'message': 'Not permitted to read leases',
      },
    };

    final result = await read();

    expect(
      (result as LeasingRepositoryFailure<LeaseComponentHistoryDto>).kind,
      LeasingRepositoryFailureKind.forbidden,
    );
  });

  test('a malformed answer fails rather than returning an empty history', () async {
    gateway.rpcResult = <String, Object?>{
      'ok': true,
      'entity': <String, Object?>{'lease_id': 'lease-1'},
    };

    final result = await read();

    expect(
      (result as LeasingRepositoryFailure<LeaseComponentHistoryDto>).kind,
      LeasingRepositoryFailureKind.infrastructureFailure,
      reason: 'an empty timeline list would render as "nothing was ever '
          'recorded", which is a claim about the contract',
    );
  });

  test('the lease scope reaches the server as given', () async {
    gateway.rpcResult = _answer();

    await adapter.readHistory(
      LeaseComponentHistoryQuery(
        workspaceId: 'ws-9',
        leaseId: 'lease-9',
        asOfDate: DateTime(2026, 3, 1),
      ),
    );

    expect(gateway.lastRpcName, 'lease_component_history');
    expect(gateway.lastRpcParameters?['p_workspace_id'], 'ws-9');
    expect(gateway.lastRpcParameters?['p_lease_id'], 'lease-9');
    expect(
      gateway.lastRpcParameters?['p_as_of'],
      '2026-03-01',
      reason: 'the calendar day as given, with no UTC conversion -- a shift '
          'here would mark the wrong period as current for anyone east of '
          'Greenwich',
    );
  });
}

Map<String, Object?> _answer({
  int? inForceIndex = 1,
  bool omitGaps = false,
  double? vatRate = 19,
  String firstTypeKey = 'base_rent',
}) {
  Map<String, Object?> period(
    String id,
    String from,
    String? to,
    double amount, {
    String? note,
    String vatMode = 'exempt',
    double? rate,
    required bool inForce,
  }) {
    return <String, Object?>{
      'id': id,
      'valid_from': from,
      'valid_to': to,
      'amount': amount,
      'currency_code': 'EUR',
      'vat_mode': vatMode,
      'vat_rate_percent': rate,
      'note': note,
      'version': 1,
      'updated_at': '2026-09-07T08:00:00Z',
      'in_force': inForce,
    };
  }

  final base = <String, Object?>{
    'component_type': firstTypeKey,
    'periods': <Object?>[
      period('p-1', '2024-01-01', '2024-06-30', 800, inForce: inForceIndex == 0),
      period('p-2', '2025-01-01', '2027-01-31', 900, inForce: inForceIndex == 1),
      period(
        'p-3',
        '2027-02-01',
        null,
        950,
        note: 'Erhöhung',
        inForce: inForceIndex == 2,
      ),
    ],
    if (!omitGaps)
      'gaps': <Object?>[
        <String, Object?>{'from': '2024-07-01', 'to': '2024-12-31'},
      ],
  };

  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'lease_id': 'lease-1',
      'property_id': 'property-1',
      'currency_code': 'EUR',
      'as_of_date': '2026-09-07',
      'component_types': <Object?>[
        base,
        <String, Object?>{
          'component_type': 'heating_advance',
          'periods': <Object?>[
            period(
              'p-4',
              '2025-01-01',
              null,
              100,
              vatMode: 'net',
              rate: vatRate,
              inForce: true,
            ),
          ],
          'gaps': <Object?>[],
        },
      ],
    },
  };
}
