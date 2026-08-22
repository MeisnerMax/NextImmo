import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// SECURITY-AAL-CLIENT-03. The gateway is the one place where gotrue's Factor
// objects become the domain model, and it is the place the original bug lived:
// the SDK's `.totp` view is verified-only. This pins the mapping against the
// SDK's own types -- every status, every factor type -- without a server.
void main() {
  group('SupabaseIdentityAccessGateway.inventoryFromFactors', () {
    Factor factor(
      String id, {
      required FactorType type,
      required FactorStatus status,
      String? name,
    }) => Factor(
      id: id,
      friendlyName: name,
      factorType: type,
      status: status,
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
    );

    test('keeps unverified TOTP factors and maps every status', () {
      final inventory = SupabaseIdentityAccessGateway.inventoryFromFactors([
        factor(
          'factor-b',
          type: FactorType.totp,
          status: FactorStatus.unverified,
          name: 'NexImmo',
        ),
        factor(
          'factor-a',
          type: FactorType.totp,
          status: FactorStatus.verified,
          name: 'Primary',
        ),
        factor(
          'factor-c',
          type: FactorType.totp,
          status: FactorStatus.unknown,
          name: 'Odd',
        ),
      ]);

      expect(
        inventory.factors.map((f) => f.id),
        <String>['factor-b', 'factor-c', 'factor-a'],
        reason: 'sorted by friendly name, then id',
      );
      expect(
        inventory.findById('factor-a')?.status,
        TotpFactorStatus.verified,
      );
      expect(
        inventory.findById('factor-b')?.status,
        TotpFactorStatus.unverified,
      );
      expect(
        inventory.findById('factor-c')?.status,
        TotpFactorStatus.unknown,
        reason: 'an unmapped status must not collapse into unverified',
      );
      expect(inventory.challengeable.single.id, 'factor-a');
      expect(inventory.recoverable.single.id, 'factor-b');
      expect(inventory.isAmbiguous, isTrue);
    });

    test('ignores non-TOTP factors whatever their status', () {
      final inventory = SupabaseIdentityAccessGateway.inventoryFromFactors([
        factor('phone', type: FactorType.phone, status: FactorStatus.verified),
        factor(
          'key',
          type: FactorType.webauthn,
          status: FactorStatus.verified,
        ),
        factor(
          'odd-type',
          type: FactorType.unknown,
          status: FactorStatus.unverified,
          name: 'NexImmo',
        ),
      ]);

      expect(inventory.isEmpty, isTrue);
      expect(inventory.challengeable, isEmpty);
      expect(
        inventory.recoverable,
        isEmpty,
        reason: 'a factor of another type is never a TOTP recovery target',
      );
      expect(inventory.interruptedEnrollment, isNull);
    });

    test('a lone unverified factor under the app name is an interruption', () {
      final inventory = SupabaseIdentityAccessGateway.inventoryFromFactors([
        factor(
          'factor-stale',
          type: FactorType.totp,
          status: FactorStatus.unverified,
          name: totpEnrollmentFriendlyName,
        ),
      ]);

      expect(inventory.interruptedEnrollment?.id, 'factor-stale');
      expect(inventory.isAmbiguous, isFalse);
    });
  });
}
