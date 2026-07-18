import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/app.dart';
import 'package:neximmo_app/core/config/app_environment.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';

void main() {
  testWidgets('Supabase property deep link opens the scoped stable id', (
    tester,
  ) async {
    final identity = _IdentityRepository();
    final properties = _PropertyRepository();
    const environment = AppEnvironment(
      environment: NexImmoEnvironment.local,
      dataBackend: DataBackend.supabase,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'public-test-key',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityAccessRepositoryProvider.overrideWithValue(identity),
          referencePropertyRepositoryProvider.overrideWithValue(properties),
        ],
        child: const NexImmoApp(environment: environment),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushNamed(referencePropertyRoute('property-a')));
    await tester.pumpAndSettle();

    expect(properties.detailPropertyIds, <String>['property-a']);
    expect(find.text('Atlas House'), findsWidgets);
    expect(find.byKey(const Key('reference-detail-pane')), findsOneWidget);
  });
}

class _IdentityRepository implements IdentityAccessRepository {
  static const _session = AuthenticatedSession(
    userId: 'user-a',
    currentAssuranceLevel: AuthenticationAssuranceLevel.aal2,
    nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
  );

  @override
  AuthenticatedSession get currentSession => _session;

  @override
  Future<IdentityAccessResult<List<WorkspaceAccess>>> listWorkspaceAccesses({
    required String userId,
  }) async {
    return IdentityAccessSuccess<List<WorkspaceAccess>>(<WorkspaceAccess>[
      WorkspaceAccess(
        workspace: const WorkspaceSummary(
          id: 'workspace-a',
          key: 'workspace-a',
          name: 'Workspace A',
          version: 1,
        ),
        membership: const MembershipSummary(
          id: 'membership-a',
          workspaceId: 'workspace-a',
          userId: 'user-a',
          roleId: 'manager',
          version: 1,
        ),
        permissions: <String>{'property.read', 'property.update'},
      ),
    ]);
  }

  @override
  Stream<AuthenticatedSession?> watchSession() => const Stream.empty();
}

class _PropertyRepository implements PropertyRepository {
  final List<String> detailPropertyIds = <String>[];
  final PropertyDto property = PropertyDto(
    id: 'property-a',
    workspaceId: 'workspace-a',
    name: 'Atlas House',
    addressLine1: 'Long Street 123',
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'mixed_use',
    units: 12,
    status: PropertyStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 17),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: 1,
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    detailPropertyIds.add(propertyId);
    return PropertyRepositorySuccess<PropertyDto>(property);
  }

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    return PropertyRepositorySuccess<PropertyPageResult>(
      PropertyPageResult(items: <PropertyDto>[property]),
    );
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    return PropertyRepositorySuccess<PropertyDto>(property);
  }
}
