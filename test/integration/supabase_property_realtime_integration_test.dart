import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/entitlement_invalidation_source.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_entitlement_invalidation_adapter.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_query_invalidation_source.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_query_invalidation_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceA = '17000000-0000-0000-0000-000000000001';
  const propertyA = '17000000-0000-0000-0000-000000000005';
  const actorA = 'a7000000-0000-0000-0000-000000000001';
  const workspaceB = '27000000-0000-0000-0000-000000000001';
  const propertyB = '27000000-0000-0000-0000-000000000005';
  const actorB = 'b7000000-0000-0000-0000-000000000001';

  test(
    'authorized observer receives only its committed workspace update',
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

      final observer = createSupabaseTestClient(url, publishableKey);
      final writerA = createSupabaseTestClient(url, publishableKey);
      final writerB = createSupabaseTestClient(url, publishableKey);
      StreamSubscription<PropertyQueryInvalidation>? subscription;
      try {
        await Future.wait(<Future<AuthResponse>>[
          observer.auth.signInWithPassword(
            email: 'p1-007@example.test',
            password: 'NexImmo-Test-2026!',
          ),
          writerA.auth.signInWithPassword(
            email: 'p1-007@example.test',
            password: 'NexImmo-Test-2026!',
          ),
          writerB.auth.signInWithPassword(
            email: 'p1-011-b@example.test',
            password: 'NexImmo-Test-2026!',
          ),
        ]);
        await Future.wait<void>(<Future<void>>[
          elevateSupabaseTestClientToAal2(writerA),
          elevateSupabaseTestClientToAal2(writerB),
        ]);

        final source = SupabasePropertyQueryInvalidationAdapter(
          client: observer,
        );
        final ready = Completer<void>();
        final observedUpdate = Completer<PropertyQueryInvalidation>();
        final events = <PropertyQueryInvalidation>[];
        subscription = source
            .watchWorkspace(workspaceId: workspaceA)
            .listen(
              (event) {
                events.add(event);
                if (event.isReconciliation && !ready.isCompleted) {
                  ready.complete();
                } else if (!event.isReconciliation &&
                    !observedUpdate.isCompleted) {
                  observedUpdate.complete(event);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!ready.isCompleted) {
                  ready.completeError(error, stackTrace);
                } else if (!observedUpdate.isCompleted) {
                  observedUpdate.completeError(error, stackTrace);
                }
              },
            );
        await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError('Realtime subscription not ready.'),
        );

        final foreignResult = await SupabasePropertyRepositoryAdapter(
          client: writerB,
        ).update(
          _command(
            workspaceId: workspaceB,
            propertyId: propertyB,
            actorId: actorB,
            mutationId: '27000000-0000-0000-0000-000000000006',
            correlationId: '27000000-0000-0000-0000-000000000007',
            name: 'Foreign After',
          ),
        );
        expect(foreignResult, isA<PropertyRepositorySuccess<PropertyDto>>());

        final ownResult = await SupabasePropertyRepositoryAdapter(
          client: writerA,
        ).update(
          _command(
            workspaceId: workspaceA,
            propertyId: propertyA,
            actorId: actorA,
            mutationId: '17000000-0000-0000-0000-000000000016',
            correlationId: '17000000-0000-0000-0000-000000000017',
            name: 'Realtime After',
          ),
        );
        expect(ownResult, isA<PropertyRepositorySuccess<PropertyDto>>());

        final event = await observedUpdate.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError('Realtime update not observed.'),
        );
        expect(event.workspaceId, workspaceA);
        expect(event.propertyId, propertyA);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(events.where((item) => item.propertyId == propertyB), isEmpty);

        final persisted = await SupabasePropertyRepositoryAdapter(
          client: observer,
        ).getById(workspaceId: workspaceA, propertyId: propertyA);
        final property =
            (persisted as PropertyRepositorySuccess<PropertyDto>).value;
        expect(property.name, 'Realtime After');
        expect(property.version, 2);
      } finally {
        await subscription?.cancel();
        await Future.wait<void>(<Future<void>>[
          observer.auth.signOut(),
          writerA.auth.signOut(),
          writerB.auth.signOut(),
        ]);
      }
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'membership and role revocation clear the active client caches',
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

      final observer = createSupabaseTestClient(url, publishableKey);
      final revoker = createSupabaseTestClient(url, publishableKey);
      StreamSubscription<EntitlementInvalidation>? probeSubscription;
      StreamSubscription<EntitlementInvalidation>? foreignSubscription;
      ReferenceSliceController? controller;
      try {
        await Future.wait(<Future<AuthResponse>>[
          observer.auth.signInWithPassword(
            email: 'p1-007@example.test',
            password: 'NexImmo-Test-2026!',
          ),
          revoker.auth.signInWithPassword(
            email: 'p1-011-b@example.test',
            password: 'NexImmo-Test-2026!',
          ),
        ]);

        final foreignDenied = Completer<void>();
        foreignSubscription = SupabaseEntitlementInvalidationAdapter(
              client: revoker,
            )
            .watchUser(userId: actorA)
            .listen(
              (_) {},
              onError: (Object _, StackTrace __) {
                if (!foreignDenied.isCompleted) {
                  foreignDenied.complete();
                }
              },
            );
        await foreignDenied.future.timeout(
          const Duration(seconds: 10),
          onTimeout:
              () =>
                  throw StateError('Foreign entitlement topic was not denied.'),
        );

        final entitlementEvents = <EntitlementInvalidation>[];
        final probeReady = Completer<void>();
        probeSubscription = SupabaseEntitlementInvalidationAdapter(
          client: observer,
        ).watchUser(userId: actorA).listen((event) {
          entitlementEvents.add(event);
          if (event.isReconciliation && !probeReady.isCompleted) {
            probeReady.complete();
          }
        }, onError: probeReady.completeError);
        await probeReady.future.timeout(
          const Duration(seconds: 10),
          onTimeout:
              () => throw StateError('Entitlement subscription not ready.'),
        );

        controller = ReferenceSliceController(
          identityRepository: SupabaseIdentityAccessRepositoryAdapter(
            client: observer,
          ),
          propertyRepository: SupabasePropertyRepositoryAdapter(
            client: observer,
          ),
          propertyInvalidationSource: SupabasePropertyQueryInvalidationAdapter(
            client: observer,
          ),
          entitlementInvalidationSource: SupabaseEntitlementInvalidationAdapter(
            client: observer,
          ),
          entitlementRevalidationInterval: const Duration(seconds: 30),
        );
        await controller.start();
        await _waitFor(
          () =>
              controller!.state.propertyListPhase == PropertyListPhase.ready &&
              controller.state.properties.isNotEmpty,
          failure: 'Initial property cache was not ready.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));

        final beforeRoleRevocation = entitlementEvents.length;
        await revoker.rpc<void>(
          'p1_017_set_property_read',
          params: const <String, dynamic>{'grant_access': false},
        );
        await _waitFor(
          () => entitlementEvents.length > beforeRoleRevocation,
          failure: 'Role revocation broadcast was not observed.',
        );
        await _waitFor(
          () =>
              controller!.state.propertyListPhase ==
                  PropertyListPhase.forbidden &&
              controller.state.properties.isEmpty &&
              controller.state.selectedProperty == null,
          failure: 'Role revocation did not clear property caches.',
        );

        await revoker.rpc<void>(
          'p1_017_set_property_read',
          params: const <String, dynamic>{'grant_access': true},
        );
        await _waitFor(
          () =>
              controller!.state.propertyListPhase == PropertyListPhase.ready &&
              controller.state.properties.isNotEmpty,
          failure: 'Restored role permission was not revalidated.',
        );

        final beforeMembershipRevocation = entitlementEvents.length;
        await revoker.rpc<void>(
          'p1_017_set_membership_active',
          params: const <String, dynamic>{'active': false},
        );
        await _waitFor(
          () => entitlementEvents.length > beforeMembershipRevocation,
          failure: 'Membership revocation broadcast was not observed.',
        );
        await _waitFor(
          () =>
              controller!.state.workspacePhase == WorkspacePhase.empty &&
              controller.state.workspaces.isEmpty &&
              controller.state.selectedWorkspaceId == null &&
              controller.state.properties.isEmpty &&
              controller.state.selectedProperty == null,
          failure: 'Membership revocation did not clear all client caches.',
        );
      } finally {
        controller?.dispose();
        await probeSubscription?.cancel();
        await foreignSubscription?.cancel();
        await Future.wait<void>(<Future<void>>[
          observer.auth.signOut(),
          revoker.auth.signOut(),
        ]);
      }
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  required String failure,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(failure);
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

PropertyUpdateCommand _command({
  required String workspaceId,
  required String propertyId,
  required String actorId,
  required String mutationId,
  required String correlationId,
  required String name,
}) {
  return PropertyUpdateCommand(
    propertyId: propertyId,
    context: CommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: mutationId,
      expectedVersion: 1,
      correlationId: correlationId,
      reason: 'P1-011 Realtime integration',
    ),
    changes: PropertyUpdateDto(
      name: name,
      addressLine1: 'Realtime Street 2',
      zip: '10117',
      city: 'Berlin',
      country: 'de',
      propertyType: 'mixed_use',
      units: 2,
      status: PropertyStatus.active,
    ),
  );
}
