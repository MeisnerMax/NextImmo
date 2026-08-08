import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_migration_dry_run.dart';
import 'package:neximmo_app/features/contacts_parties/data/sqlite_to_postgres_contacts_parties_dry_run_mapper.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_migration_dry_run.dart';
import 'package:neximmo_app/features/leasing_operations/data/sqlite_to_postgres_leasing_operations_dry_run_mapper.dart';
import 'package:neximmo_app/features/portfolio_property/application/reference_migration_dry_run.dart';
import 'package:neximmo_app/features/portfolio_property/data/sqlite_to_postgres_reference_dry_run_mapper.dart';

const _mapper = SqliteToPostgresLeasingOperationsDryRunMapper();
const _targetWorkspaceId = 'a1a1a1a1-1111-4111-8111-111111111111';
const _actorId = 'b2b2b2b2-2222-4222-9222-222222222222';

LeasingMigrationDryRunRequest _request() {
  return const LeasingMigrationDryRunRequest(
    sourceWorkspaceId: 'legacy',
    targetWorkspaceId: _targetWorkspaceId,
    targetWorkspaceKey: 'target-workspace',
    migrationActorId: _actorId,
  );
}

void main() {
  group('happy path', () {
    test('maps units and leases with derived ids and reconciles', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'occupied', targetRent: 1100),
          ],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'active'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
      expect(report.manifestChecksum, isNotEmpty);
      expect(
        report.summaries.every(
          (summary) => summary.countsReconcile && summary.checksumsReconcile,
        ),
        isTrue,
      );
      expect(report.mappings, hasLength(2));
      for (final mapping in report.mappings) {
        expect(mapping.targetId, matches(_uuidPattern));
      }
    });

    test('is deterministic across runs', () {
      final snapshot = LeasingMigrationSourceSnapshot(
        units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
        leases: <Map<String, Object?>>[
          _lease(id: 'l1', unitId: 'u1', status: 'draft'),
        ],
      );

      final first = _mapper.map(snapshot: snapshot, request: _request());
      final second = _mapper.map(snapshot: snapshot, request: _request());

      expect(first.toCanonicalJson(), second.toCanonicalJson());
      expect(first.manifestChecksum, second.manifestChecksum);
    });

    test('does not reorder-sensitively depend on the source row order', () {
      final ordered = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'vacant'),
            _unit(id: 'u2', status: 'vacant'),
          ],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );
      final reversed = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u2', status: 'vacant'),
            _unit(id: 'u1', status: 'vacant'),
          ],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      expect(ordered.manifestChecksum, reversed.manifestChecksum);
    });
  });

  group('cross-mapper identity', () {
    test(
      'a migrated lease points at the party the P2-D02 mapper produces',
      () {
        // The load-bearing check of this whole mapper: if these two derivations
        // ever drift, every migrated lease silently loses its tenant.
        const partyMapper = SqliteToPostgresContactsPartiesDryRunMapper();
        final partyReport = partyMapper.map(
          snapshot: const PartyMigrationSourceSnapshot(
            tenants: <Map<String, Object?>>[
              <String, Object?>{
                'id': 'tenant-1',
                'display_name': 'Tina Tenant',
                'legal_name': null,
                'email': null,
                'phone': null,
                'notes': null,
                'created_at': 1000,
                'updated_at': 2000,
              },
            ],
            contractors: <Map<String, Object?>>[],
            contacts: <Map<String, Object?>>[],
          ),
          request: const PartyMigrationDryRunRequest(
            sourceWorkspaceId: 'legacy',
            targetWorkspaceId: _targetWorkspaceId,
            targetWorkspaceKey: 'target-workspace',
            migrationActorId: _actorId,
          ),
        );
        final partyId = partyReport.mappings
            .singleWhere(
              (mapping) => mapping.entity == PartyMigrationEntity.tenant,
            )
            .targetPartyId;

        expect(
          leasingMigrationTenantPartyId(
            targetWorkspaceId: _targetWorkspaceId,
            legacyTenantId: 'tenant-1',
          ),
          partyId,
        );
      },
    );

    test(
      'a migrated unit points at the property the P1-012 mapper produces',
      () {
        const referenceMapper = SqliteToPostgresReferenceDryRunMapper();
        final referenceReport = referenceMapper.map(
          snapshot: const ReferenceMigrationSourceSnapshot(
            workspaces: <Map<String, Object?>>[
              <String, Object?>{
                'id': 'ws_default',
                'name': 'Default Workspace',
                'docs_root_path': 'workspace/docs',
                'created_at': 1000,
              },
            ],
            properties: <Map<String, Object?>>[
              <String, Object?>{
                'id': 'property-1',
                'name': 'Musterobjekt',
                'address_line1': 'Musterstrasse 1',
                'address_line2': null,
                'zip': '10115',
                'city': 'Berlin',
                'country': 'DE',
                'property_type': 'mixed_use',
                'units': 4,
                'sqft': 420.5,
                'year_built': 1998,
                'notes': null,
                'created_at': 2000,
                'updated_at': 3000,
                'archived': 0,
              },
            ],
          ),
          request: const ReferenceMigrationDryRunRequest(
            sourceWorkspaceId: 'ws_default',
            targetWorkspaceId: _targetWorkspaceId,
            targetWorkspaceKey: 'target-workspace',
            migrationActorId: _actorId,
            confirmGlobalPropertyWorkspaceBinding: true,
            inferArchivedAtFromUpdatedAt: false,
          ),
        );
        final propertyId = referenceReport.mappings
            .singleWhere(
              (mapping) =>
                  mapping.entity == ReferenceMigrationEntity.property,
            )
            .targetId;

        expect(
          leasingMigrationPropertyId(
            targetWorkspaceId: _targetWorkspaceId,
            legacyPropertyId: 'property-1',
          ),
          propertyId,
        );
      },
    );
  });

  group('status vocabulary', () {
    test('archived units are rejected with a warning, not an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'archived')],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      final units = _summary(report, LeasingMigrationEntity.unit);
      expect(units.sourceRows, 1);
      expect(units.mappedRows, 0);
      expect(units.rejectedRows, 1);
      expect(units.countsReconcile, isTrue);
      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.unit_archived_not_migrated'),
      );
      // A soft-deleted row must not block the whole import.
      expect(report.status, LeasingMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
    });

    test('an unrecognised unit status is an error, unlike in the adapter', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'holdover')],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.unmapped_unit_status'),
      );
    });

    test('an unrecognised lease status is an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'holdover'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.unmapped_lease_status'),
      );
    });

    test('future becomes draft and says so', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'future'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.lease_future_to_draft'),
      );
    });

    test('terminated collapses to ended and derives ended_at', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'terminated'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(
        report.issues.map((issue) => issue.code),
        containsAll(<String>[
          'mapping.lease_status_collapsed_to_ended',
          // leases_ended_marker_check makes null unrepresentable, so the
          // substitution is flagged rather than hidden.
          'mapping.ended_at_derived_from_updated_at',
        ]),
      );
    });

    test('yearly is renamed to annual', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(
              id: 'l1',
              unitId: 'u1',
              status: 'draft',
              billingFrequency: 'yearly',
            ),
          ],
        ),
        request: _request(),
      );

      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.billing_frequency_renamed'),
      );
    });
  });

  group('cloud constraints caught before the import', () {
    test('a unit whose status contradicts its leases is an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'occupied')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'draft'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.occupancy_contradicts_leases'),
      );
    });

    test('an offline unit is exempt from the occupancy invariant', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'offline')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'active'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
    });

    test('several active leases on one unit are lawful (OPN-DOM-001)', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'occupied')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'active'),
            _lease(id: 'l2', unitId: 'u1', status: 'active'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(_summary(report, LeasingMigrationEntity.lease).mappedRows, 2);
    });

    test('a unit amount without a derivable currency is an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'vacant', targetRent: 900),
          ],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.currency_underivable'),
      );
    });

    test('disagreeing lease currencies leave the unit underivable', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'occupied', targetRent: 900),
          ],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'active'),
            _lease(
              id: 'l2',
              unitId: 'u1',
              status: 'active',
              currencyCode: 'CHF',
            ),
          ],
        ),
        request: _request(),
      );

      expect(
        report.issues.map((issue) => issue.code),
        contains('source.currency_underivable'),
      );
    });

    test('a derivable currency is reported as derived', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'occupied', targetRent: 900),
          ],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'active'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.currency_derived_from_leases'),
      );
    });

    test('a payment day the cloud forbids is an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'draft', paymentDay: 30),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.payment_day_out_of_cloud_range'),
      );
    });

    test('a lease of a non-migrated unit is an error', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'archived')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'draft'),
          ],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(
        report.issues.map((issue) => issue.code),
        contains('source.unit_not_migrated'),
      );
    });

    test('a stale offline reason is dropped, not carried', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'vacant', offlineReason: 'alte Notiz'),
          ],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      expect(report.status, LeasingMigrationStatus.ready);
      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.stale_offline_reason_dropped'),
      );
      expect(report.toCanonicalJson(), isNot(contains('alte Notiz')));
    });
  });

  group('reporting', () {
    test('legacy rent roll snapshots are reported as not migrated', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: const <Map<String, Object?>>[],
          rentRollSnapshotCount: 3,
        ),
        request: _request(),
      );

      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.rent_roll_not_migrated'),
      );
      // Not migrating them is a documented scope decision, not a failure.
      expect(report.status, LeasingMigrationStatus.ready);
    });

    test('a lease with a tenant states the P2-D02 dependency', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(
              id: 'l1',
              unitId: 'u1',
              status: 'draft',
              tenantId: 'tenant-1',
            ),
          ],
        ),
        request: _request(),
      );

      expect(
        report.issues.map((issue) => issue.code),
        contains('mapping.tenant_party_requires_p2_d02_import'),
      );
    });

    test('an invalid request rejects every row without mapping any', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: <Map<String, Object?>>[
            _lease(id: 'l1', unitId: 'u1', status: 'draft'),
          ],
        ),
        request: const LeasingMigrationDryRunRequest(
          sourceWorkspaceId: '',
          targetWorkspaceId: 'not-a-uuid',
          targetWorkspaceKey: 'Invalid Key',
          migrationActorId: 'also-not-a-uuid',
        ),
      );

      expect(report.status, LeasingMigrationStatus.invalid);
      expect(report.mappings, isEmpty);
      expect(
        report.summaries.every((summary) => summary.countsReconcile),
        isTrue,
      );
      expect(
        report.issues.map((issue) => issue.code),
        containsAll(<String>[
          'request.invalid_source_workspace_id',
          'request.invalid_target_workspace_id',
          'request.invalid_target_workspace_key',
          'request.invalid_migration_actor_id',
        ]),
      );
    });

    test('an aborted run is reported as aborted and never ready', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[_unit(id: 'u1', status: 'vacant')],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
        abortSignal: _AlwaysAbort(),
      );

      expect(report.status, LeasingMigrationStatus.aborted);
      expect(report.productionImportReady, isFalse);
      expect(
        report.issues.map((issue) => issue.code),
        contains('run.aborted'),
      );
    });

    test('never leaks a note into the canonical report of a rejected row', () {
      final report = _mapper.map(
        snapshot: LeasingMigrationSourceSnapshot(
          units: <Map<String, Object?>>[
            _unit(id: 'u1', status: 'holdover', notes: 'Vertrauliche Notiz'),
          ],
          leases: const <Map<String, Object?>>[],
        ),
        request: _request(),
      );

      expect(report.toCanonicalJson(), isNot(contains('Vertrauliche Notiz')));
    });
  });
}

LeasingMigrationEntitySummary _summary(
  LeasingMigrationDryRunReport report,
  LeasingMigrationEntity entity,
) => report.summaries.singleWhere((summary) => summary.entity == entity);

Map<String, Object?> _unit({
  required String id,
  required String status,
  double? targetRent,
  String? offlineReason,
  String? notes,
}) => <String, Object?>{
  'id': id,
  'asset_property_id': 'property-1',
  'unit_code': 'A-01',
  'unit_type': 'apartment',
  'beds': 3,
  'baths': 1,
  'sqft': 72.5,
  'floor': '1',
  'status': status,
  'target_rent_monthly': targetRent,
  'market_rent_monthly': null,
  'offline_reason': offlineReason,
  'vacancy_since': null,
  'vacancy_reason': null,
  'marketing_status': null,
  'renovation_status': null,
  'expected_ready_date': null,
  'next_action': null,
  'notes': notes,
  'created_at': 1000,
  'updated_at': 2000,
};

Map<String, Object?> _lease({
  required String id,
  required String unitId,
  required String status,
  String? tenantId,
  String currencyCode = 'EUR',
  String billingFrequency = 'monthly',
  int? paymentDay,
}) => <String, Object?>{
  'id': id,
  'asset_property_id': 'property-1',
  'unit_id': unitId,
  'tenant_id': tenantId,
  'lease_name': 'Vertrag $id',
  'start_date': 1000,
  'end_date': null,
  'move_in_date': null,
  'move_out_date': null,
  'status': status,
  'base_rent_monthly': 1000,
  'currency_code': currencyCode,
  'security_deposit': null,
  'payment_day_of_month': paymentDay,
  'billing_frequency': billingFrequency,
  'lease_signed_date': null,
  'notice_date': null,
  'renewal_option_date': null,
  'break_option_date': null,
  'executed_date': null,
  'deposit_status': null,
  'rent_free_period_months': null,
  'ancillary_charges_monthly': null,
  'parking_other_charges_monthly': null,
  'notes': null,
  'created_at': 1000,
  'updated_at': 2000,
};

class _AlwaysAbort implements LeasingMigrationAbortSignal {
  @override
  bool get isAborted => true;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
