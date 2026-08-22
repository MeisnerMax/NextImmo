import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';

// SECURITY-AAL-CLIENT-03. The inventory is where the client decides which of
// the four account shapes it is looking at -- factorless, verified, interrupted,
// mixed -- and whether it is looking at anything it understands at all. Every
// destructive decision downstream rests on these answers.
void main() {
  group('TotpFactorInventory', () {
    const verified = TotpFactor(id: 'factor-good', friendlyName: 'Primary');
    const interrupted = TotpFactor(
      id: 'factor-stale',
      friendlyName: 'NexImmo',
      status: TotpFactorStatus.unverified,
    );

    test('an empty inventory is factorless, not interrupted', () {
      const inventory = TotpFactorInventory.empty();

      expect(inventory.isEmpty, isTrue);
      expect(inventory.challengeable, isEmpty);
      expect(inventory.recoverable, isEmpty);
      expect(inventory.interruptedEnrollment, isNull);
      expect(inventory.isAmbiguous, isFalse);
    });

    test('a lone unverified factor under the app name is an interruption', () {
      final inventory = TotpFactorInventory(
        factors: const <TotpFactor>[interrupted],
      );

      expect(inventory.challengeable, isEmpty);
      expect(inventory.recoverable.single.id, 'factor-stale');
      expect(inventory.interruptedEnrollment?.id, 'factor-stale');
      expect(inventory.isAmbiguous, isFalse);
    });

    test('a verified factor takes precedence over an interrupted one', () {
      final inventory = TotpFactorInventory(
        factors: const <TotpFactor>[interrupted, verified],
      );

      expect(inventory.challengeable.single.id, 'factor-good');
      expect(inventory.recoverable.single.id, 'factor-stale');
      expect(
        inventory.interruptedEnrollment,
        isNull,
        reason: 'aal2 is reachable through the verified factor; nothing to '
            'recover, nothing to delete',
      );
      expect(inventory.isAmbiguous, isFalse);
    });

    test('an unverified factor under a foreign name is not a target', () {
      final inventory = TotpFactorInventory(
        factors: const <TotpFactor>[
          TotpFactor(
            id: 'factor-other',
            friendlyName: 'Elsewhere',
            status: TotpFactorStatus.unverified,
          ),
        ],
      );

      expect(inventory.recoverable.single.id, 'factor-other');
      expect(inventory.interruptedEnrollment, isNull);
      expect(inventory.isAmbiguous, isFalse);
    });

    test('two unverified factors under the app name are ambiguous', () {
      final inventory = TotpFactorInventory(
        factors: const <TotpFactor>[
          interrupted,
          TotpFactor(
            id: 'factor-stale-2',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unverified,
          ),
        ],
      );

      expect(inventory.interruptedEnrollment, isNull);
      expect(inventory.isAmbiguous, isTrue);
    });

    test('an unknown status is neither challengeable nor recoverable', () {
      final inventory = TotpFactorInventory(
        factors: const <TotpFactor>[
          TotpFactor(
            id: 'factor-odd',
            friendlyName: 'NexImmo',
            status: TotpFactorStatus.unknown,
          ),
        ],
      );

      expect(inventory.challengeable, isEmpty);
      expect(
        inventory.recoverable,
        isEmpty,
        reason: 'a factor the SDK could not classify must never be deletable',
      );
      expect(inventory.interruptedEnrollment, isNull);
      expect(inventory.isAmbiguous, isTrue);
      expect(inventory.findById('factor-odd')?.status, TotpFactorStatus.unknown);
      expect(inventory.findById('missing'), isNull);
    });
  });
}
