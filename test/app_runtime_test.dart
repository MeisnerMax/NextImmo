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
import 'package:neximmo_app/ui/shell/app_scaffold.dart';
import 'package:neximmo_app/ui/shell/sidebar.dart';

void main() {
  testWidgets('Supabase stays fail-closed without an authenticated session', (
    tester,
  ) async {
    const environment = AppEnvironment(
      environment: NexImmoEnvironment.local,
      dataBackend: DataBackend.supabase,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'public-test-key',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityAccessRepositoryProvider.overrideWithValue(
            _IdentityRepository(session: null),
          ),
          referencePropertyRepositoryProvider.overrideWithValue(
            _PropertyRepository(),
          ),
        ],
        child: const NexImmoApp(environment: environment),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to NexImmo'), findsOneWidget);
    expect(find.byType(AppScaffold), findsNothing);
  });

  testWidgets('Supabase root opens the canonical shell without SQLite', (
    tester,
  ) async {
    const environment = AppEnvironment(
      environment: NexImmoEnvironment.local,
      dataBackend: DataBackend.supabase,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'public-test-key',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityAccessRepositoryProvider.overrideWithValue(
            _IdentityRepository(),
          ),
          referencePropertyRepositoryProvider.overrideWithValue(
            _PropertyRepository(),
          ),
        ],
        child: const NexImmoApp(environment: environment),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(
      find.byKey(const Key('cloud-destination-migration-dashboard')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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
    tester
        .binding
        .platformDispatcher
        .defaultRouteNameTestValue = referencePropertyRoute('property-a');
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
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
    expect(properties.detailPropertyIds, <String>['property-a']);
    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.text('Atlas House'), findsWidgets);
    expect(find.byKey(const Key('reference-detail-pane')), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });
}

class _IdentityRepository implements IdentityAccessRepository {
  _IdentityRepository({AuthenticatedSession? session = _session})
    : _currentSession = session;

  static const _session = AuthenticatedSession(
    userId: 'user-a',
    currentAssuranceLevel: AuthenticationAssuranceLevel.aal2,
    nextAssuranceLevel: AuthenticationAssuranceLevel.aal2,
  );
  final AuthenticatedSession? _currentSession;

  @override
  AuthenticatedSession? get currentSession => _currentSession;

  @override
  Future<IdentityAccessResult<TotpChallenge>> challengeTotp({
    required String factorId,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<TotpEnrollment>> enrollTotp() async =>
      throw UnimplementedError();

  @override
  Future<IdentityAccessResult<TotpFactorInventory>>
  listTotpFactorInventory() async =>
      const IdentityAccessSuccess<TotpFactorInventory>(
        TotpFactorInventory.empty(),
      );

  @override
  Future<IdentityAccessResult<void>> unenrollTotpFactor({
    required String factorId,
  }) async => throw UnimplementedError();

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
  Future<IdentityAccessResult<void>> signInWithPassword({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> requestPasswordlessSignIn({
    required String email,
  }) async => throw UnimplementedError();

  @override
  Future<IdentityAccessResult<void>> signOut() async =>
      const IdentityAccessSuccess<void>(null);

  @override
  Future<IdentityAccessResult<AuthenticatedSession>> verifyTotp({
    required TotpChallenge challenge,
    required String code,
  }) async => throw UnimplementedError();

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
