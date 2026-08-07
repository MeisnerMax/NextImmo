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
  const workspaceId = '1d000000-0000-0000-0000-000000000001';
  const propertyId = '1d000000-0000-0000-0000-000000000005';
  const actorId = 'ad000000-0000-0000-0000-000000000001';

  PropertyUpdateDto changesWithStatus(PropertyStatus status) {
    return PropertyUpdateDto(
      name: 'Tombstone Target',
      addressLine1: 'Tombstone Street 1',
      zip: '10115',
      city: 'Berlin',
      country: 'de',
      propertyType: 'multifamily',
      units: 4,
      status: status,
    );
  }

  test(
    'archive tombstones the property server-side and un-archive restores it',
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
      await client.auth.signInWithPassword(
        email: 'debt-012@example.test',
        password: 'NexImmo-Test-2026!',
      );
      await elevateSupabaseTestClientToAal2(client);
      final repository = SupabasePropertyRepositoryAdapter(client: client);

      // Active reads show the property before it is tombstoned.
      final beforeList = await repository.list(
        const PropertyListQuery(workspaceId: workspaceId),
      );
      expect(
        (beforeList as PropertyRepositorySuccess<PropertyPageResult>).value.items
            .map((property) => property.id),
        <String>[propertyId],
      );

      // Archive == tombstone: the row is kept, marked and audited.
      final archive = await repository.update(
        PropertyUpdateCommand(
          propertyId: propertyId,
          context: const CommandContext(
            workspaceId: workspaceId,
            actorId: actorId,
            mutationId: '1d000000-0000-0000-0000-0000000000a1',
            expectedVersion: 1,
            correlationId: '1d000000-0000-0000-0000-0000000000a2',
            reason: 'tombstone via archive',
          ),
          changes: changesWithStatus(PropertyStatus.archived),
        ),
      );
      final archived = (archive as PropertyRepositorySuccess<PropertyDto>).value;
      expect(archived.version, 2);
      expect(archived.status, PropertyStatus.archived);

      // Active reads exclude the tombstoned row...
      final activeAfterArchive = await repository.list(
        const PropertyListQuery(workspaceId: workspaceId),
      );
      expect(
        (activeAfterArchive as PropertyRepositorySuccess<PropertyPageResult>)
            .value
            .items,
        isEmpty,
      );

      // ...while the archive view retains it for audit and restore.
      final archivedView = await repository.list(
        const PropertyListQuery(workspaceId: workspaceId, includeArchived: true),
      );
      expect(
        (archivedView as PropertyRepositorySuccess<PropertyPageResult>).value
            .items
            .map((property) => property.id),
        <String>[propertyId],
      );

      // The retained row carries the delete marker and the acting user.
      final tombstoned = await repository.getById(
        workspaceId: workspaceId,
        propertyId: propertyId,
      );
      final tombstonedProperty =
          (tombstoned as PropertyRepositorySuccess<PropertyDto>).value;
      expect(tombstonedProperty.status, PropertyStatus.archived);
      expect(tombstonedProperty.deletedAt, isNotNull);
      expect(tombstonedProperty.deletedBy, actorId);

      // Restore == un-archive: the marker and deleter are cleared.
      final restore = await repository.update(
        PropertyUpdateCommand(
          propertyId: propertyId,
          context: const CommandContext(
            workspaceId: workspaceId,
            actorId: actorId,
            mutationId: '1d000000-0000-0000-0000-0000000000a3',
            expectedVersion: 2,
            correlationId: '1d000000-0000-0000-0000-0000000000a4',
            reason: 'restore via un-archive',
          ),
          changes: changesWithStatus(PropertyStatus.active),
        ),
      );
      final restoredResult =
          (restore as PropertyRepositorySuccess<PropertyDto>).value;
      expect(restoredResult.version, 3);
      expect(restoredResult.status, PropertyStatus.active);

      final restored = await repository.getById(
        workspaceId: workspaceId,
        propertyId: propertyId,
      );
      final restoredProperty =
          (restored as PropertyRepositorySuccess<PropertyDto>).value;
      expect(restoredProperty.deletedAt, isNull);
      expect(restoredProperty.deletedBy, isNull);

      final activeAfterRestore = await repository.list(
        const PropertyListQuery(workspaceId: workspaceId),
      );
      expect(
        (activeAfterRestore as PropertyRepositorySuccess<PropertyPageResult>)
            .value
            .items
            .map((property) => property.id),
        <String>[propertyId],
      );

      expect(
        await identityRepository.signOut(),
        isA<IdentityAccessSuccess<void>>(),
      );
    },
    skip:
        url.isEmpty || publishableKey.isEmpty
            ? 'Requires the local Supabase integration harness.'
            : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
