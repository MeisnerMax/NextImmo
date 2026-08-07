import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_migration_dry_run.dart';
import 'package:neximmo_app/features/contacts_parties/data/sqlite_to_postgres_contacts_parties_dry_run_mapper.dart';

const _mapper = SqliteToPostgresContactsPartiesDryRunMapper();

PartyMigrationDryRunRequest _request() {
  return const PartyMigrationDryRunRequest(
    sourceWorkspaceId: 'legacy',
    targetWorkspaceId: 'a1a1a1a1-1111-4111-8111-111111111111',
    targetWorkspaceKey: 'target-workspace',
    migrationActorId: 'b2b2b2b2-2222-4222-9222-222222222222',
  );
}

Map<String, Object?> _tenant({String id = 't1'}) => <String, Object?>{
  'id': id,
  'display_name': 'Tina Tenant',
  'legal_name': null,
  'email': 'Tina@example.test',
  'phone': '+49 30 5',
  'alternative_contact': null,
  'billing_contact': null,
  'status': null,
  'move_in_reference': null,
  'notes': null,
  'created_at': 1000,
  'updated_at': 2000,
};

Map<String, Object?> _contractor({String id = 'c1'}) => <String, Object?>{
  'id': id,
  'company_name': 'Acme Plumbing',
  'trade_category': 'Sanitär',
  'contact_name': 'Carla Contractor',
  'phone': '+49 30 7',
  'email': 'acme@example.test',
  'address': 'Berlin',
  'hourly_rate': 85.5,
  'service_areas_json': '["Berlin","Potsdam"]',
  'notes': null,
  'created_at': 1500,
  'updated_at': 2500,
  'rating_quality': 4.5,
  'insurance_cert_expiry': null,
  'is_active': 1,
};

Map<String, Object?> _contact({String id = 'k1', String role = 'buyer'}) =>
    <String, Object?>{
      'id': id,
      'display_name': 'Karl Contact',
      'legal_name': null,
      'role': role,
      'email': 'karl@example.test',
      'phone': '+49 30 9',
      'notes': null,
      'created_at': 1200,
      'updated_at': 2200,
    };

PartyMigrationSourceSnapshot _snapshot({
  List<Map<String, Object?>>? tenants,
  List<Map<String, Object?>>? contractors,
  List<Map<String, Object?>>? contacts,
}) {
  return PartyMigrationSourceSnapshot(
    tenants: tenants ?? <Map<String, Object?>>[_tenant()],
    contractors: contractors ?? <Map<String, Object?>>[_contractor()],
    contacts: contacts ?? <Map<String, Object?>>[_contact()],
  );
}

class _AlwaysAbort implements PartyMigrationAbortSignal {
  const _AlwaysAbort();
  @override
  bool get isAborted => true;
}

void main() {
  group('SqliteToPostgresContactsPartiesDryRunMapper', () {
    test('maps a clean snapshot to a reconciled, import-ready report', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());

      expect(report.status, PartyMigrationStatus.ready);
      expect(report.productionImportReady, isTrue);
      for (final summary in report.summaries) {
        expect(summary.countsReconcile, isTrue, reason: summary.entity.name);
        expect(summary.checksumsReconcile, isTrue, reason: summary.entity.name);
        expect(summary.mappedRows, 1);
        expect(summary.rejectedRows, 0);
      }
    });

    test('is deterministic across runs', () {
      final first = _mapper.map(snapshot: _snapshot(), request: _request());
      final second = _mapper.map(snapshot: _snapshot(), request: _request());

      expect(first.manifestChecksum, isNotEmpty);
      expect(first.manifestChecksum, second.manifestChecksum);
      expect(first.toCanonicalJson(), second.toCanonicalJson());
    });

    test('derives the functional role per source entity', () {
      final report = _mapper.map(snapshot: _snapshot(), request: _request());
      final byEntity = {
        for (final mapping in report.mappings) mapping.entity: mapping,
      };

      expect(byEntity[PartyMigrationEntity.tenant]?.targetRoleId, isNotNull);
      expect(byEntity[PartyMigrationEntity.contractor]?.targetRoleId, isNotNull);
      expect(byEntity[PartyMigrationEntity.contact]?.targetRoleId, isNotNull);
      // Target party ids are deterministic UUIDs.
      expect(
        byEntity[PartyMigrationEntity.tenant]?.targetPartyId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('projects an unmapped contact role as an identity-only party', () {
      final report = _mapper.map(
        snapshot: _snapshot(contacts: <Map<String, Object?>>[
          _contact(role: 'notary'),
        ]),
        request: _request(),
      );

      final contactMapping = report.mappings.firstWhere(
        (mapping) => mapping.entity == PartyMigrationEntity.contact,
      );
      expect(contactMapping.targetRoleId, isNull);
      expect(
        report.issues.any(
          (issue) =>
              issue.entity == PartyMigrationEntity.contact &&
              issue.code == 'mapping.role_not_mapped',
        ),
        isTrue,
      );
      // A mapped identity-only party still reconciles.
      expect(report.status, PartyMigrationStatus.ready);
    });

    test('rejects an invalid row and marks the report invalid', () {
      final report = _mapper.map(
        snapshot: _snapshot(tenants: <Map<String, Object?>>[
          <String, Object?>{..._tenant(), 'display_name': '  '},
        ]),
        request: _request(),
      );

      expect(report.status, PartyMigrationStatus.invalid);
      expect(report.productionImportReady, isFalse);
      final tenantSummary = report.summaries.firstWhere(
        (summary) => summary.entity == PartyMigrationEntity.tenant,
      );
      expect(tenantSummary.rejectedRows, 1);
      expect(tenantSummary.mappedRows, 0);
      expect(tenantSummary.errorCount, greaterThan(0));
    });

    test('rejects an invalid request without dereferencing rows', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: const PartyMigrationDryRunRequest(
          sourceWorkspaceId: 'legacy',
          targetWorkspaceId: 'not-a-uuid',
          targetWorkspaceKey: 'target-workspace',
          migrationActorId: 'b2b2b2b2-2222-4222-9222-222222222222',
        ),
      );

      expect(report.status, PartyMigrationStatus.invalid);
      expect(
        report.issues.any(
          (issue) => issue.code == 'request.invalid_target_workspace_id',
        ),
        isTrue,
      );
      for (final summary in report.summaries) {
        expect(summary.mappedRows, 0);
        expect(summary.rejectedRows, summary.sourceRows);
      }
    });

    test('reports an aborted run', () {
      final report = _mapper.map(
        snapshot: _snapshot(),
        request: _request(),
        abortSignal: const _AlwaysAbort(),
      );

      expect(report.status, PartyMigrationStatus.aborted);
      expect(
        report.issues.any((issue) => issue.code == 'run.aborted'),
        isTrue,
      );
    });
  });
}
