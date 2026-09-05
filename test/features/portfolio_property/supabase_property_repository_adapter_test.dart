import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';

void main() {
  _searchTests();
  _overviewTests();
  group('SupabasePropertyRepositoryAdapter', () {
    late _FakePropertySupabaseGateway gateway;
    late SupabasePropertyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePropertySupabaseGateway();
      repository = SupabasePropertyRepositoryAdapter.withGateway(gateway);
    });

    test(
      'lists with workspace keyset, archived filter, and limit plus one',
      () async {
        gateway.listResult = <Map<String, dynamic>>[
          _propertySummaryJson(id: 'property-a'),
          _propertySummaryJson(id: 'property-b', status: 'archived'),
          _propertySummaryJson(id: 'property-c'),
        ];

        final result = await repository.list(
          const PropertyListQuery(
            workspaceId: 'workspace-a',
            page: PropertyPageRequest(limit: 2, cursor: 'property-before'),
          ),
        );

        expect(gateway.listWorkspaceId, 'workspace-a');
        expect(gateway.listAfterId, 'property-before');
        expect(gateway.listLimit, 3);
        expect(gateway.listIncludeArchived, isFalse);
        final page =
            (result as PropertyRepositorySuccess<PropertyPageResult>).value;
        expect(page.items.map((property) => property.id), <String>[
          'property-a',
          'property-b',
        ]);
        expect(page.items.first, isA<PropertySummaryDto>());
        expect(page.nextCursor, 'property-b');
      },
    );

    test('forwards includeArchived and omits cursor on first page', () async {
      await repository.list(
        const PropertyListQuery(
          workspaceId: 'workspace-a',
          includeArchived: true,
        ),
      );

      expect(gateway.listAfterId, isNull);
      expect(gateway.listIncludeArchived, isTrue);
      expect(gateway.listLimit, 51);
    });

    test('gets detail only when id and workspace match', () async {
      gateway.getResult = <Map<String, dynamic>>[
        _propertyJson(id: 'foreign-property', workspaceId: 'workspace-b'),
      ];

      final result = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      expect(gateway.getWorkspaceId, 'workspace-a');
      expect(gateway.getPropertyId, 'property-a');
      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('returns not found for an empty scoped detail result', () async {
      final result = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('rejects actor mismatch before calling update RPC', () async {
      gateway.currentUserId = 'another-actor';

      final result = await repository.update(_command());

      expect(gateway.updateCalls, 0);
      expect(
        (result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
    });

    test('updates only through RPC with the complete serialized DTO', () async {
      gateway.updateResult = <String, Object?>{
        'ok': true,
        'property': _propertyJson(version: 2),
      };

      final result = await repository.update(_command());

      expect(gateway.updateCalls, 1);
      expect(gateway.updateParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_property_id': 'property-a',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_changes': <String, Object?>{
          'name': 'Updated property',
          'address_line1': 'New street 2',
          'address_line2': 'Rear building',
          'zip': '20202',
          'city': 'Hamburg',
          'country': 'de',
          'property_type': 'mixed_use',
          'units': 8,
          'sqft': 1234.5,
          'year_built': 1999,
          'notes': 'Updated notes',
          'status': 'active',
        },
        'p_reason': 'Correction',
      });
      final property = (result as PropertyRepositorySuccess<PropertyDto>).value;
      expect(property.version, 2);
      expect(property.sqft, 2500.5);
      expect(property.deletedAt, DateTime.parse('2026-07-13T12:00:00Z'));
      // The update RPC payload never carries deleted_by (DEBT-012 populates it
      // via trigger, surfaced only through table reads).
      expect(property.deletedBy, isNull);
    });

    test('getById surfaces the deleted_by tombstone marker', () async {
      gateway.getResult = <Map<String, dynamic>>[
        _propertyJson(status: 'archived', deletedBy: 'actor-a'),
      ];

      final result = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      final property = (result as PropertyRepositorySuccess<PropertyDto>).value;
      expect(property.status, PropertyStatus.archived);
      expect(property.deletedBy, 'actor-a');
      expect(property.deletedAt, DateTime.parse('2026-07-13T12:00:00Z'));
    });

    test('maps version conflict including current property', () async {
      gateway.updateResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Stale property',
          'expected_version': 1,
          'actual_version': 3,
          'current_property': _propertyJson(version: 3),
        },
      };

      final result = await repository.update(_command());
      final failure = result as PropertyRepositoryFailure<PropertyDto>;

      expect(failure.kind, PropertyRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict?.expectedVersion, 1);
      expect(failure.versionConflict?.actualVersion, 3);
      expect(failure.versionConflict?.currentProperty.version, 3);
    });

    test('maps mutation conflict and in-progress separately', () async {
      for (final entry in <(String, PropertyRepositoryFailureKind)>[
        ('mutation_conflict', PropertyRepositoryFailureKind.mutationConflict),
        ('in_progress', PropertyRepositoryFailureKind.mutationInProgress),
      ]) {
        gateway.updateResult = <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': entry.$1,
            'message': 'Mutation failed',
          },
        };

        final result = await repository.update(_command());

        expect(
          (result as PropertyRepositoryFailure<PropertyDto>).kind,
          entry.$2,
        );
      }
    });

    test('hides malformed response and gateway exception details', () async {
      gateway.listResult = <Map<String, dynamic>>[
        _propertySummaryJson()..remove('address_line1'),
      ];
      final malformed = await repository.list(
        const PropertyListQuery(workspaceId: 'workspace-a'),
      );

      gateway.getError = StateError('sensitive Postgrest detail');
      final failedRead = await repository.getById(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );

      for (final failure in <PropertyRepositoryFailure<dynamic>>[
        malformed as PropertyRepositoryFailure<PropertyPageResult>,
        failedRead as PropertyRepositoryFailure<PropertyDto>,
      ]) {
        expect(
          failure.kind,
          PropertyRepositoryFailureKind.infrastructureFailure,
        );
        expect(failure.message, isNot(contains('sensitive')));
      }
    });
  });
}

Map<String, dynamic> _propertySummaryJson({
  String id = 'property-a',
  String workspaceId = 'workspace-a',
  String status = 'active',
  int version = 1,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'name': 'Property',
    'address_line1': 'Street 1',
    'zip': '10115',
    'city': 'Berlin',
    'status': status,
    'version': version,
  };
}

PropertyUpdateCommand _command() {
  return const PropertyUpdateCommand(
    propertyId: 'property-a',
    context: CommandContext(
      workspaceId: 'workspace-a',
      actorId: 'actor-a',
      mutationId: 'mutation-a',
      expectedVersion: 1,
      correlationId: 'correlation-a',
      reason: 'Correction',
    ),
    changes: PropertyUpdateDto(
      name: 'Updated property',
      addressLine1: 'New street 2',
      addressLine2: 'Rear building',
      zip: '20202',
      city: 'Hamburg',
      country: 'de',
      propertyType: 'mixed_use',
      units: 8,
      sqft: 1234.5,
      yearBuilt: 1999,
      notes: 'Updated notes',
      status: PropertyStatus.active,
    ),
  );
}

Map<String, dynamic> _propertyJson({
  String id = 'property-a',
  String workspaceId = 'workspace-a',
  String status = 'active',
  int version = 1,
  String? deletedBy,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'name': 'Property',
    'address_line1': 'Street 1',
    'address_line2': 'Building A',
    'zip': '10115',
    'city': 'Berlin',
    'country': 'de',
    'property_type': 'residential',
    'units': 4,
    'sqft': 2500.5,
    'year_built': 1985,
    'notes': 'Notes',
    'status': status,
    'created_at': '2026-07-12T10:00:00Z',
    'updated_at': '2026-07-13T11:00:00Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': version,
    'deleted_at': '2026-07-13T12:00:00Z',
    // The P1-004 update RPC result never carries deleted_by; only table reads
    // (getById/list) do. Omitting the key mirrors the RPC payload.
    if (deletedBy != null) 'deleted_by': deletedBy,
  };
}

/// The workspace-wide search (`PROPERTY-LOOKUP-01`).
///
/// The adapter turns a user's query into the terms the filter ANDs together.
/// Everything it does there is a bound: lower-cased for the generated column,
/// five terms at most, each capped in length. What it deliberately does not do
/// is strip pattern characters — they widen the match, they cannot reach past
/// the row policy, and removing them would make a property whose name contains
/// one impossible to find.
void _searchTests() {
  group('propertySearchTerms', () {
    test('splits on whitespace and lower-cases', () {
      expect(propertySearchTerms('Atlas   HAUS'), <String>['atlas', 'haus']);
    });

    test('a blank query is no filter at all', () {
      expect(propertySearchTerms(null), isEmpty);
      expect(propertySearchTerms('   '), isEmpty);
    });

    test('caps the number of terms', () {
      expect(propertySearchTerms('a b c d e f g'), <String>[
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('caps the length of a term', () {
      expect(propertySearchTerms('x' * 200).single.length, 64);
    });

    test('keeps pattern characters instead of dropping them', () {
      expect(propertySearchTerms('50%'), <String>['50%']);
    });
  });

  group('SupabasePropertyRepositoryAdapter.list search', () {
    late _FakePropertySupabaseGateway gateway;
    late SupabasePropertyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePropertySupabaseGateway();
      repository = SupabasePropertyRepositoryAdapter.withGateway(gateway);
    });

    test('passes the tokenized term to the gateway', () async {
      await repository.list(
        const PropertyListQuery(
          workspaceId: 'workspace-a',
          searchTerm: 'Atlas Berlin',
        ),
      );

      expect(gateway.listSearchTerms, <String>['atlas', 'berlin']);
      expect(
        gateway.listWorkspaceId,
        'workspace-a',
        reason: 'a search is still workspace-scoped',
      );
    });

    test('no term means no filter', () async {
      await repository.list(
        const PropertyListQuery(workspaceId: 'workspace-a'),
      );

      expect(gateway.listSearchTerms, isEmpty);
    });
  });
}

/// The overview read (`PROPERTY-OVERVIEW-DATA-01`).
///
/// The adapter is where a permission-scoped payload could quietly turn into a
/// zero, so these tests pin the opposite: an unavailable section arrives with
/// no counters at all, attention keeps the server's order, and an unknown
/// severity degrades downward instead of escalating itself.
void _overviewTests() {
  group('SupabasePropertyRepositoryAdapter.overview', () {
    late _FakePropertySupabaseGateway gateway;
    late SupabasePropertyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePropertySupabaseGateway();
      repository = SupabasePropertyRepositoryAdapter.withGateway(gateway);
    });

    Future<PropertyRepositoryResult<PropertyOverviewDto>> read() {
      return repository.overview(
        workspaceId: 'workspace-a',
        propertyId: 'property-a',
      );
    }

    test('maps sections, freshness and attention', () async {
      gateway.overviewResult = _overviewPayload();

      final result = await read();

      expect(gateway.overviewParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_property_id': 'property-a',
      });
      final overview =
          (result as PropertyRepositorySuccess<PropertyOverviewDto>).value;
      expect(overview.propertyId, 'property-a');
      expect(overview.asOf, DateTime.utc(2026, 9, 6, 8, 15));
      expect(overview.leasing.available, isTrue);
      expect(overview.leasing['units_total'], 12);
      expect(overview.leasing['units_vacant'], 3);
      expect(overview.valuation['cases_total'], 2);
      expect(overview.lastValuationUpdatedAt, DateTime.utc(2026, 8, 30, 10));
    });

    test(
      'an unavailable section carries the capability and no counters',
      () async {
        gateway.overviewResult = _overviewPayload(
          maintenance: <String, Object?>{
            'available': false,
            'permission': 'maintenance.read',
          },
        );

        final overview =
            (await read() as PropertyRepositorySuccess<PropertyOverviewDto>)
                .value;

        expect(overview.maintenance.available, isFalse);
        expect(overview.maintenance.permission, 'maintenance.read');
        expect(
          overview.maintenance['tickets_open'],
          isNull,
          reason: 'no number exists, so no call site can read one',
        );
        expect(overview.maintenance.counters, isEmpty);
      },
    );

    test('attention keeps the payload order', () async {
      gateway.overviewResult = _overviewPayload(
        attention: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'tickets_overdue',
            'severity': 'critical',
            'count': 2,
            'domain': 'operations',
          },
          <String, Object?>{
            'type': 'units_vacant',
            'severity': 'info',
            'count': 3,
            'domain': 'leasing',
          },
        ],
      );

      final overview =
          (await read() as PropertyRepositorySuccess<PropertyOverviewDto>)
              .value;

      expect(overview.attention.map((entry) => entry.type), <String>[
        'tickets_overdue',
        'units_vacant',
      ]);
      expect(
        overview.attention.first.severity,
        PropertyAttentionSeverity.critical,
      );
      expect(overview.attention.first.count, 2);
      expect(overview.attention.first.domain, 'operations');
    });

    test(
      'an unknown severity degrades to info rather than escalating',
      () async {
        gateway.overviewResult = _overviewPayload(
          attention: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'insurance_expired',
              'severity': 'catastrophic',
              'count': 1,
              'domain': 'documents',
            },
          ],
        );

        final overview =
            (await read() as PropertyRepositorySuccess<PropertyOverviewDto>)
                .value;

        expect(
          overview.attention.single.severity,
          PropertyAttentionSeverity.info,
        );
        expect(
          overview.attention.single.type,
          'insurance_expired',
          reason: 'the signal itself stays, only its rank is conservative',
        );
      },
    );

    test('a malformed attention entry is dropped, not guessed at', () async {
      gateway.overviewResult = _overviewPayload(
        attention: <Object?>[
          <String, Object?>{'type': 'tickets_overdue', 'count': 'many'},
          'nonsense',
          <String, Object?>{
            'type': 'tasks_blocked',
            'severity': 'warning',
            'count': 1,
            'domain': 'operations',
          },
        ],
      );

      final overview =
          (await read() as PropertyRepositorySuccess<PropertyOverviewDto>)
              .value;

      expect(overview.attention.map((entry) => entry.type), <String>[
        'tasks_blocked',
      ]);
    });

    test('a payload for another workspace is refused', () async {
      gateway.overviewResult = _overviewPayload(workspaceId: 'workspace-b');

      final result = await read();

      expect(
        (result as PropertyRepositoryFailure<PropertyOverviewDto>).kind,
        PropertyRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('server refusals map onto their kinds', () async {
      gateway.overviewResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'Property access is not permitted',
        },
      };
      expect(
        (await read() as PropertyRepositoryFailure<PropertyOverviewDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );

      gateway.overviewResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'not_found',
          'message': 'Property not found',
        },
      };
      expect(
        (await read() as PropertyRepositoryFailure<PropertyOverviewDto>).kind,
        PropertyRepositoryFailureKind.notFound,
      );
    });

    test('a transport failure is an infrastructure failure', () async {
      gateway.overviewError = StateError('offline');

      expect(
        (await read() as PropertyRepositoryFailure<PropertyOverviewDto>).kind,
        PropertyRepositoryFailureKind.infrastructureFailure,
      );
    });
  });
}

Map<String, Object?> _overviewPayload({
  String workspaceId = 'workspace-a',
  Map<String, Object?>? maintenance,
  List<Object?> attention = const <Object?>[],
}) {
  return <String, Object?>{
    'ok': true,
    'overview': <String, Object?>{
      'as_of': '2026-09-06T08:15:00Z',
      'property': <String, Object?>{
        'id': 'property-a',
        'workspace_id': workspaceId,
        'name': 'Atlas House',
        'status': 'active',
        'version': 3,
        'updated_at': '2026-09-05T10:00:00Z',
      },
      'leasing': <String, Object?>{
        'available': true,
        'units_total': 12,
        'units_occupied': 9,
        'units_vacant': 3,
      },
      'maintenance':
          maintenance ??
          <String, Object?>{
            'available': true,
            'tickets_open': 5,
            'tickets_overdue': 2,
          },
      'capex': <String, Object?>{'available': true, 'projects_open': 3},
      'tasks': <String, Object?>{'available': true, 'tasks_open': 7},
      'documents': <String, Object?>{
        'available': true,
        'requirements_total': 6,
      },
      'valuation': <String, Object?>{
        'available': true,
        'cases_total': 2,
        'cases_open': 1,
        'last_case_updated_at': '2026-08-30T10:00:00Z',
      },
      'attention': attention,
    },
  };
}

class _FakePropertySupabaseGateway implements PropertySupabaseGateway {
  @override
  String? currentUserId = 'actor-a';

  Object? overviewResult;
  Object? overviewError;
  int overviewCalls = 0;
  Map<String, Object?>? overviewParameters;

  List<Map<String, dynamic>> listResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> getResult = <Map<String, dynamic>>[];
  Object? updateResult;
  Object? createResult;
  Object? listError;
  Object? getError;
  Object? updateError;
  Object? createError;

  String? listWorkspaceId;
  String? listAfterId;
  int? listLimit;
  bool? listIncludeArchived;
  List<String>? listSearchTerms;
  String? getWorkspaceId;
  String? getPropertyId;
  int updateCalls = 0;
  Map<String, Object?>? updateParameters;
  int createCalls = 0;
  Map<String, Object?>? createParameters;

  @override
  Future<Object?> createProperty(Map<String, Object?> parameters) async {
    createCalls++;
    createParameters = parameters;
    if (createError != null) {
      throw createError!;
    }
    return createResult;
  }

  @override
  Future<Object?> propertyOverview(Map<String, Object?> parameters) async {
    overviewCalls++;
    overviewParameters = parameters;
    if (overviewError != null) {
      throw overviewError!;
    }
    return overviewResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
    List<String> searchTerms = const <String>[],
  }) async {
    if (listError != null) {
      throw listError!;
    }
    listWorkspaceId = workspaceId;
    listAfterId = afterId;
    listLimit = limit;
    listIncludeArchived = includeArchived;
    listSearchTerms = searchTerms;
    return listResult;
  }

  @override
  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  }) async {
    if (getError != null) {
      throw getError!;
    }
    getWorkspaceId = workspaceId;
    getPropertyId = propertyId;
    return getResult;
  }

  @override
  Future<Object?> updateProperty(Map<String, Object?> parameters) async {
    updateCalls++;
    updateParameters = parameters;
    if (updateError != null) {
      throw updateError!;
    }
    return updateResult;
  }
}
