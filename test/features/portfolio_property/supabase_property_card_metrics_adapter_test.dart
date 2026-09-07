/// PROPERTY-CARD-METRICS-01: the client half of the batch card read.
///
/// The adapter's job here is almost entirely about refusing to invent. A batch
/// answer arrives with three kinds of gap in it — a property the server
/// withheld, a section the caller may not read, and a row it could not parse —
/// and every one of them has to end up as *absent*, because absent is what the
/// card renders as no figures. A zero anywhere in this file would be a number
/// the server never sent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_card_metrics_dto.dart';

void main() {
  late _FakeGateway gateway;
  late SupabasePropertyRepositoryAdapter adapter;

  setUp(() {
    gateway = _FakeGateway();
    adapter = SupabasePropertyRepositoryAdapter.withGateway(gateway);
  });

  Future<PropertyRepositoryResult<PropertyCardMetricsBatch>> read({
    List<String> ids = const <String>['p-1'],
  }) {
    return adapter.cardMetrics(workspaceId: 'ws-1', propertyIds: ids);
  }

  test('parses the sections of a batch answer', () async {
    gateway.result = _answer(
      properties: <Object?>[
        <String, Object?>{
          'property_id': 'p-1',
          'leasing': <String, Object?>{
            'available': true,
            'units_total': 4,
            'units_occupied': 3,
            'leases_ending_90d': 1,
          },
          'maintenance': <String, Object?>{
            'available': true,
            'tickets_open': 2,
            'tickets_overdue': 1,
          },
        },
      ],
    );

    final result = await read();

    expect(result, isA<PropertyRepositorySuccess<PropertyCardMetricsBatch>>());
    final batch =
        (result as PropertyRepositorySuccess<PropertyCardMetricsBatch>).value;
    expect(batch['p-1']!.leasing['units_total'], 4);
    expect(batch['p-1']!.leasing['units_occupied'], 3);
    expect(batch['p-1']!.maintenance['tickets_overdue'], 1);
    expect(
      batch.asOf,
      DateTime.parse('2026-09-07T08:00:00Z'),
      reason: 'the freshness stamp travels with the payload, so a card can '
          'state how old its numbers are instead of implying they are live',
    );
  });

  test('sends the ids as one call, not one call per property', () async {
    gateway.result = _answer(properties: const <Object?>[]);

    await read(ids: const <String>['p-1', 'p-2', 'p-3']);

    expect(gateway.calls, 1, reason: 'the N+1 this package exists to remove');
    expect(gateway.parameters?['p_property_ids'], <String>['p-1', 'p-2', 'p-3']);
    expect(gateway.parameters?['p_workspace_id'], 'ws-1');
  });

  test('an empty page is answered without asking the server', () async {
    final result = await read(ids: const <String>[]);

    expect(gateway.calls, 0);
    final batch =
        (result as PropertyRepositorySuccess<PropertyCardMetricsBatch>).value;
    expect(batch.byPropertyId, isEmpty);
    expect(batch.withheld, isEmpty);
  });

  test('a withheld property is absent, and named in withheld', () async {
    gateway.result = _answer(
      properties: <Object?>[
        <String, Object?>{
          'property_id': 'p-1',
          'leasing': <String, Object?>{'available': true, 'units_total': 4},
          'maintenance': <String, Object?>{'available': true},
        },
      ],
      withheld: <Object?>['p-2'],
    );

    final batch =
        (await read(ids: const <String>['p-1', 'p-2'])
                as PropertyRepositorySuccess<PropertyCardMetricsBatch>)
            .value;

    expect(batch['p-2'], isNull);
    expect(batch.withheld, <String>['p-2']);
    expect(
      batch['p-1']!.leasing['units_total'],
      4,
      reason: 'and the property that was answered still is -- one withheld id '
          'must not cost the rest of the page its numbers',
    );
  });

  test('a section the caller may not read reports no counters at all', () async {
    gateway.result = _answer(
      properties: <Object?>[
        <String, Object?>{
          'property_id': 'p-1',
          'leasing': <String, Object?>{'available': true, 'units_total': 4},
          'maintenance': <String, Object?>{
            'available': false,
            'permission': 'maintenance.read',
          },
        },
      ],
    );

    final batch =
        (await read() as PropertyRepositorySuccess<PropertyCardMetricsBatch>)
            .value;

    expect(batch['p-1']!.maintenance.available, isFalse);
    expect(batch['p-1']!.maintenance.permission, 'maintenance.read');
    expect(
      batch['p-1']!.maintenance['tickets_open'],
      isNull,
      reason: 'not 0. A card showing "0 Tickets offen" to someone who may not '
          'see tickets states something the server never said',
    );
    expect(
      batch['p-1']!.leasing['units_total'],
      4,
      reason: 'while the section they may read is unaffected',
    );
  });

  test('a row without a usable id is skipped rather than defaulted', () async {
    gateway.result = _answer(
      properties: <Object?>[
        <String, Object?>{'leasing': <String, Object?>{'available': true}},
        'not an object',
        <String, Object?>{
          'property_id': 'p-2',
          'leasing': <String, Object?>{'available': true, 'units_total': 1},
          'maintenance': <String, Object?>{'available': true},
        },
      ],
    );

    final batch =
        (await read() as PropertyRepositorySuccess<PropertyCardMetricsBatch>)
            .value;

    expect(batch.byPropertyId.keys, <String>['p-2']);
    expect(
      batch['p-2']!.leasing['units_total'],
      1,
      reason: 'the unusable rows must not take the usable one with them',
    );
  });

  test('forbidden maps to the forbidden failure', () async {
    gateway.result = <String, Object?>{
      'ok': false,
      'error': <String, Object?>{
        'code': 'forbidden',
        'message': 'AAL2 is required for property metrics',
      },
    };

    final result = await read();

    expect(
      (result as PropertyRepositoryFailure<PropertyCardMetricsBatch>).kind,
      PropertyRepositoryFailureKind.forbidden,
    );
    expect(result.message, 'AAL2 is required for property metrics');
  });

  test('the cap is a validation failure, not a truncation', () async {
    gateway.result = <String, Object?>{
      'ok': false,
      'error': <String, Object?>{
        'code': 'validation_failed',
        'message': 'At most 200 properties can be read at once',
        'field': 'propertyIds',
      },
    };

    final result = await read();

    expect(
      (result as PropertyRepositoryFailure<PropertyCardMetricsBatch>).kind,
      PropertyRepositoryFailureKind.validationFailed,
      reason: 'a caller that asked for more than a page gets told so. Silently '
          'answering for the first 200 would look like a complete answer',
    );
  });

  test('a thrown transport error becomes a failure, not an empty page', () async {
    gateway.error = StateError('socket closed');

    final result = await read();

    expect(
      (result as PropertyRepositoryFailure<PropertyCardMetricsBatch>).kind,
      PropertyRepositoryFailureKind.infrastructureFailure,
      reason: 'an empty success here would render as a portfolio with nothing '
          'open, which is the one thing this package must never claim',
    );
  });

  test('a malformed answer is a failure rather than a silent empty', () async {
    gateway.result = <String, Object?>{'entity': <String, Object?>{}};

    final result = await read();

    expect(
      (result as PropertyRepositoryFailure<PropertyCardMetricsBatch>).kind,
      PropertyRepositoryFailureKind.infrastructureFailure,
    );
  });
}

Map<String, Object?> _answer({
  required List<Object?> properties,
  List<Object?> withheld = const <Object?>[],
}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'as_of': '2026-09-07T08:00:00Z',
      'properties': properties,
      'withheld': withheld,
    },
  };
}

class _FakeGateway implements PropertySupabaseGateway {
  Object? result;
  Object? error;
  int calls = 0;
  Map<String, Object?>? parameters;

  @override
  String? get currentUserId => 'actor-a';

  @override
  Future<Object?> propertyCardMetrics(Map<String, Object?> parameters) async {
    calls++;
    this.parameters = parameters;
    if (error != null) {
      throw error!;
    }
    return result;
  }

  @override
  Future<Object?> propertyOverview(Map<String, Object?> parameters) async =>
      throw UnimplementedError('propertyOverview');

  @override
  Future<Object?> createProperty(Map<String, Object?> parameters) async =>
      throw UnimplementedError('createProperty');

  @override
  Future<Object?> updateProperty(Map<String, Object?> parameters) async =>
      throw UnimplementedError('updateProperty');

  @override
  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  }) async => throw UnimplementedError('getProperty');

  @override
  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
    List<String> searchTerms = const <String>[],
  }) async => throw UnimplementedError('listProperties');
}
