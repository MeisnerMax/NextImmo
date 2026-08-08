/// P2-D05a real local-client integration test, mirroring
/// `supabase_leasing_repository_integration_test.dart`'s shape.
///
/// Carries the **mandatory parity check** named in Befund 1 of
/// `04c_wave3_leasing_operations.md`: the same business scenario (an active
/// lease expiring in ~20 days, its tenant missing a phone number) is built
/// twice — once against the real local Postgres RPC, once against the legacy
/// SQLite engine that keeps running for SQLite mode — and the resulting
/// signal *types* and *severities* must agree. IDs never can (separate
/// databases), so "same referenced entity" is asserted structurally (both
/// sides reference a lease for the expiry signal, both reference a tenant for
/// the contact signal), not by literal id equality. A mismatch here means one
/// side drifted from the other, which is exactly the RISK-QA-001 this test
/// exists to catch at build time instead of in front of a user.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/repositories/operations_repo.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/features/leasing_operations/application/leasing_repository.dart';
import 'package:neximmo_app/features/leasing_operations/application/operations_signals_contract.dart';
import 'package:neximmo_app/features/leasing_operations/data/legacy_operations_signals_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/data/supabase_leasing_repository_adapter.dart';
import 'package:neximmo_app/features/leasing_operations/domain/lease_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/operations_signal_dto.dart';
import 'package:neximmo_app/features/leasing_operations/domain/unit_dto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'f1000000-0000-0000-0000-000000000001';
  const propertyId = 'f5000000-0000-0000-0000-000000000001';
  const managerId = 'fa000000-0000-0000-0000-000000000001';
  const tenantPartyId = 'f6000000-0000-0000-0000-000000000001';

  var mutationCounter = 0;
  LeasingCommandContext context({String? reason}) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(3, '0');
    return LeasingCommandContext(
      workspaceId: workspaceId,
      actorId: managerId,
      mutationId: 'f8000000-0000-0000-0000-000000000$suffix',
      correlationId: 'f9000000-0000-0000-0000-000000000$suffix',
      reason: reason,
    );
  }

  test(
    'real client computes signals end to end, and parity holds with the legacy engine',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final managerClient = createSupabaseTestClient(url, publishableKey);
      final viewerClient = createSupabaseTestClient(url, publishableKey);
      final leaseEndDate = DateTime.now().add(const Duration(days: 20));
      try {
        await managerClient.auth.signInWithPassword(
          email: 'p2-d05a-manager@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final units = SupabaseUnitRepositoryAdapter(client: managerClient);
        final leases = SupabaseLeaseRepositoryAdapter(client: managerClient);
        final signals = SupabaseOperationsSignalsAdapter(client: managerClient);

        final unit = _success<UnitDto>(
          await units.create(
            CreateUnitCommand(
              context: context(),
              draft: const UnitDraft(
                propertyId: propertyId,
                unitCode: 'SIG-01',
                currencyCode: 'EUR',
              ),
            ),
          ),
        );

        final lease = _successLease(
          await leases.create(
            CreateLeaseCommand(
              context: context(),
              draft: LeaseDraft(
                unitId: unit.id,
                leaseName: 'Vertrag Signale',
                startDate: DateTime.now().subtract(const Duration(days: 300)),
                endDate: leaseEndDate,
                baseRentMonthly: 900,
                currencyCode: 'EUR',
                tenantPartyId: tenantPartyId,
              ),
            ),
          ),
        );
        final active = await _walkToActive(leases, context, lease);
        expect(active.status, LeaseStatus.active);

        // --- Read: every kept signal type this scenario can produce -------

        final firstRead = _successSignals(
          await signals.list(
            const OperationsSignalsQuery(
              workspaceId: workspaceId,
              propertyId: propertyId,
            ),
          ),
        );

        final expiry = firstRead.singleWhere(
          (signal) => signal.type == 'lease_expiry',
        );
        expect(expiry.severity, 'critical');
        expect(expiry.leaseId, active.id);
        expect(expiry.unitId, unit.id);
        expect(expiry.status, 'open');
        expect(expiry.statusVersion, isNull);

        final contact = firstRead.singleWhere(
          (signal) => signal.type == 'missing_tenant_contact',
        );
        expect(contact.severity, 'warning');
        expect(contact.tenantPartyId, tenantPartyId);

        final stale = firstRead.singleWhere(
          (signal) => signal.type == 'stale_rent_roll',
        );
        expect(stale.severity, 'warning');
        expect(stale.unitId, isNull);

        // --- Write: acknowledge the expiry signal, versioned + audited ----

        final ack = _successState(
          await signals.updateStatus(
            UpdateOperationsSignalStatusCommand(
              context: context(reason: 'reviewed renewal'),
              propertyId: propertyId,
              signalType: 'lease_expiry',
              signalKey: expiry.signalKey,
              unitId: unit.id,
              leaseId: active.id,
              tenantPartyId: tenantPartyId,
              status: 'dismissed',
            ),
          ),
        );
        expect(ack.status, 'dismissed');
        expect(ack.version, 1);

        // Creating again without a version is a conflict, not a silent
        // overwrite.
        final reCreate = await signals.updateStatus(
          UpdateOperationsSignalStatusCommand(
            context: context(),
            propertyId: propertyId,
            signalType: 'lease_expiry',
            signalKey: expiry.signalKey,
            unitId: unit.id,
            leaseId: active.id,
            tenantPartyId: tenantPartyId,
            status: 'resolved',
          ),
        );
        expect(
          _failure(reCreate).kind,
          OperationsSignalsFailureKind.versionConflict,
        );

        final resolved = _successState(
          await signals.updateStatus(
            UpdateOperationsSignalStatusCommand(
              context: context(),
              propertyId: propertyId,
              signalType: 'lease_expiry',
              signalKey: expiry.signalKey,
              unitId: unit.id,
              leaseId: active.id,
              tenantPartyId: tenantPartyId,
              status: 'resolved',
              resolutionNote: 'renewed',
              expectedVersion: 1,
            ),
          ),
        );
        expect(resolved.status, 'resolved');
        expect(resolved.version, 2);

        final secondRead = _successSignals(
          await signals.list(
            const OperationsSignalsQuery(
              workspaceId: workspaceId,
              propertyId: propertyId,
            ),
          ),
        );
        expect(
          secondRead
              .singleWhere((signal) => signal.type == 'lease_expiry')
              .status,
          'resolved',
        );

        // --- Authorization: the viewer has no lease.read/lease.manage -----

        await viewerClient.auth.signInWithPassword(
          email: 'p2-d05a-viewer@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final viewerSignals = SupabaseOperationsSignalsAdapter(
          client: viewerClient,
        );
        final viewerRead = await viewerSignals.list(
          const OperationsSignalsQuery(
            workspaceId: workspaceId,
            propertyId: propertyId,
          ),
        );
        expect(
          _failure(viewerRead).kind,
          OperationsSignalsFailureKind.forbidden,
        );

        final viewerWrite = await viewerSignals.updateStatus(
          UpdateOperationsSignalStatusCommand(
            context: LeasingCommandContext(
              workspaceId: workspaceId,
              actorId: 'fa000000-0000-0000-0000-000000000002',
              mutationId: 'f8000000-0000-0000-0000-000000000900',
              correlationId: 'f9000000-0000-0000-0000-000000000900',
            ),
            propertyId: propertyId,
            signalType: 'stale_rent_roll',
            signalKey: 'stale_rent_roll:-:-:-',
            status: 'dismissed',
          ),
        );
        expect(
          _failure(viewerWrite).kind,
          OperationsSignalsFailureKind.forbidden,
        );

        // --- Parity: the same business scenario through the legacy engine -

        final legacySignals = await _legacySignalsForSameScenario(
          leaseEndDate: leaseEndDate,
        );
        final legacyExpiry = legacySignals.singleWhere(
          (signal) => signal.type == 'lease_expiry',
        );
        expect(
          legacyExpiry.severity,
          expiry.severity,
          reason:
              'Both engines must agree on the severity tier for the same '
              'days-to-expiry, or one of them drifted.',
        );
        expect(legacyExpiry.leaseId, isNotNull);
        expect(legacyExpiry.unitId, isNotNull);

        final legacyContact = legacySignals.singleWhere(
          (signal) => signal.type == 'missing_tenant_contact',
        );
        expect(legacyContact.severity, contact.severity);
        expect(legacyContact.tenantPartyId, isNotNull);
      } finally {
        await viewerClient.auth.signOut();
        await managerClient.auth.signOut();
      }
    },
    skip: url.isEmpty || publishableKey.isEmpty
        ? 'Requires the local Supabase integration harness.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Builds the identical business scenario (one active lease expiring in the
/// same number of days, its tenant missing a phone number) against a fresh
/// in-memory legacy SQLite database, and reads it back through
/// [LegacySqliteOperationsSignalsAdapter] — the same contract the cloud half
/// of this test reads through, so the comparison is apples to apples.
Future<List<OperationsSignalDto>> _legacySignalsForSameScenario({
  required DateTime leaseEndDate,
}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
  final db = await appDatabase.instance;
  try {
    const legacyWorkspaceId = 'legacy-parity-workspace';
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('properties', <String, Object?>{
      'id': 'p1',
      'name': 'Property 1',
      'address_line1': 'Street 1',
      'zip': '10115',
      'city': 'Berlin',
      'country': 'DE',
      'property_type': 'multifamily',
      'units': 1,
      'created_at': now,
      'updated_at': now,
      'archived': 0,
    });
    await db.insert('units', <String, Object?>{
      'id': 'u1',
      'asset_property_id': 'p1',
      'unit_code': 'SIG-01',
      'status': 'occupied',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('tenants', <String, Object?>{
      'id': 't1',
      'display_name': 'Mieter Ohne Telefon',
      'email': 'ohnetelefon@example.test',
      'phone': null,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('leases', <String, Object?>{
      'id': 'l1',
      'asset_property_id': 'p1',
      'unit_id': 'u1',
      'tenant_id': 't1',
      'lease_name': 'Vertrag Signale',
      'start_date': DateTime.now()
          .subtract(const Duration(days: 300))
          .millisecondsSinceEpoch,
      'end_date': leaseEndDate.millisecondsSinceEpoch,
      'status': 'active',
      'base_rent_monthly': 900,
      'currency_code': 'EUR',
      'billing_frequency': 'monthly',
      'deposit_status': 'unknown',
      'created_at': now,
      'updated_at': now,
    });

    final adapter = LegacySqliteOperationsSignalsAdapter(
      repo: OperationsRepo(db),
      legacyWorkspaceId: legacyWorkspaceId,
    );
    final result = await adapter.list(
      const OperationsSignalsQuery(
        workspaceId: legacyWorkspaceId,
        propertyId: 'p1',
      ),
    );
    return (result as OperationsSignalsSuccess<List<OperationsSignalDto>>)
        .value;
  } finally {
    await appDatabase.close();
  }
}

Future<LeaseDto> _walkToActive(
  LeaseRepository leases,
  LeasingCommandContext Function({String? reason}) context,
  LeaseDto lease,
) async {
  var current = lease;
  for (final target in <LeaseStatus>[
    LeaseStatus.reviewed,
    LeaseStatus.sent,
    LeaseStatus.tenantSigned,
    LeaseStatus.landlordSigned,
    LeaseStatus.active,
  ]) {
    current = _successLease(
      await leases.transitionStatus(
        TransitionLeaseStatusCommand(
          context: context(),
          leaseId: current.id,
          expectedVersion: current.version,
          targetStatus: target,
        ),
      ),
    );
  }
  return current;
}

T _success<T>(LeasingRepositoryResult<T> result) {
  if (result is LeasingRepositoryFailure<T>) {
    fail('Expected success but got ${result.kind}: ${result.message}');
  }
  return (result as LeasingRepositorySuccess<T>).value;
}

LeaseDto _successLease(LeasingRepositoryResult<LeaseDto> result) =>
    _success<LeaseDto>(result);

List<OperationsSignalDto> _successSignals(
  OperationsSignalsResult<List<OperationsSignalDto>> result,
) {
  if (result is OperationsSignalsFailure<List<OperationsSignalDto>>) {
    fail('Expected success but got ${result.kind}: ${result.message}');
  }
  return (result as OperationsSignalsSuccess<List<OperationsSignalDto>>).value;
}

OperationsSignalStateDto _successState(
  OperationsSignalsResult<OperationsSignalStateDto> result,
) {
  if (result is OperationsSignalsFailure<OperationsSignalStateDto>) {
    fail('Expected success but got ${result.kind}: ${result.message}');
  }
  return (result as OperationsSignalsSuccess<OperationsSignalStateDto>).value;
}

OperationsSignalsFailure<T> _failure<T>(OperationsSignalsResult<T> result) {
  if (result is OperationsSignalsSuccess<T>) {
    fail('Expected a failure but the command succeeded.');
  }
  return result as OperationsSignalsFailure<T>;
}
