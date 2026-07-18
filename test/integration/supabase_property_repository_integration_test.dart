import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/identity_access/data/supabase_identity_access_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_repository_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = '17000000-0000-0000-0000-000000000001';
  const propertyId = '17000000-0000-0000-0000-000000000005';
  const actorId = 'a7000000-0000-0000-0000-000000000001';

  test(
    'real client enforces RLS and the property mutation contract',
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

      final client = createSupabaseTestClient(url, publishableKey);
      final identityRepository = SupabaseIdentityAccessRepositoryAdapter(
        client: client,
      );
      final passwordlessResult = await identityRepository
          .requestPasswordlessSignIn(email: 'p1-007@example.test');
      expect(
        passwordlessResult,
        isA<IdentityAccessSuccess<void>>(),
        reason: switch (passwordlessResult) {
          IdentityAccessFailure<void>(:final kind, :final message) =>
            '$kind: $message',
          _ => null,
        },
      );
      await client.auth.signInWithPassword(
        email: 'p1-007@example.test',
        password: 'NexImmo-Test-2026!',
      );
      final accessResult = await identityRepository.listWorkspaceAccesses(
        userId: actorId,
      );
      final access =
          (accessResult as IdentityAccessSuccess<List<WorkspaceAccess>>)
              .value
              .single;
      expect(access.workspace.id, workspaceId);
      expect(
        access.permissions,
        containsAll(<String>[
          'workspace.read',
          'property.read',
          'property.update',
        ]),
      );
      final repository = SupabasePropertyRepositoryAdapter(client: client);

      final pageResult = await repository.list(
        const PropertyListQuery(workspaceId: workspaceId),
      );
      final page =
          (pageResult as PropertyRepositorySuccess<PropertyPageResult>).value;
      expect(page.items.map((property) => property.id), <String>[propertyId]);

      final command = PropertyUpdateCommand(
        propertyId: propertyId,
        context: const CommandContext(
          workspaceId: workspaceId,
          actorId: actorId,
          mutationId: '17000000-0000-0000-0000-000000000006',
          expectedVersion: 1,
          correlationId: '17000000-0000-0000-0000-000000000007',
          reason: 'P1-007 integration',
        ),
        changes: const PropertyUpdateDto(
          name: 'After',
          addressLine1: 'Integration Street 2',
          zip: '10117',
          city: 'Berlin',
          country: 'de',
          propertyType: 'mixed_use',
          units: 2,
          sqft: 2500.5,
          yearBuilt: 2001,
          notes: 'Remote adapter integration',
          status: PropertyStatus.active,
        ),
      );

      final aal1Result = await repository.update(command);
      expect(
        (aal1Result as PropertyRepositoryFailure<PropertyDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );

      await elevateSupabaseTestClientToAal2(client);
      final first = await repository.update(command);
      final retry = await repository.update(command);
      expect(
        (first as PropertyRepositorySuccess<PropertyDto>).value.version,
        2,
      );
      expect(
        (retry as PropertyRepositorySuccess<PropertyDto>).value.version,
        2,
      );

      final stale = await repository.update(
        PropertyUpdateCommand(
          propertyId: propertyId,
          context: const CommandContext(
            workspaceId: workspaceId,
            actorId: actorId,
            mutationId: '17000000-0000-0000-0000-000000000008',
            expectedVersion: 1,
            correlationId: '17000000-0000-0000-0000-000000000009',
          ),
          changes: command.changes,
        ),
      );
      final conflict = stale as PropertyRepositoryFailure<PropertyDto>;
      expect(conflict.kind, PropertyRepositoryFailureKind.versionConflict);
      expect(conflict.versionConflict?.actualVersion, 2);

      final persisted = await repository.getById(
        workspaceId: workspaceId,
        propertyId: propertyId,
      );
      expect(
        (persisted as PropertyRepositorySuccess<PropertyDto>).value.name,
        'After',
      );

      expect(
        await identityRepository.signOut(),
        isA<IdentityAccessSuccess<void>>(),
      );
      expect(identityRepository.currentSession, isNull);
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
