import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/app.dart';
import 'package:neximmo_app/core/config/app_environment.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_providers.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_query_invalidation_source.dart';
import 'package:neximmo_app/features/platform_audit_jobs/application/platform_repository.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/notification_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_controller.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_port.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_media_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';
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
          notificationPortProvider.overrideWithValue(_EmptyNotificationPort()),
          platformQueryInvalidationSourceProvider.overrideWithValue(
            _SilentInvalidationSource(),
          ),
          propertyMediaPortProvider.overrideWithValue(_EmptyPropertyMedia()),
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
          notificationPortProvider.overrideWithValue(_EmptyNotificationPort()),
          platformQueryInvalidationSourceProvider.overrideWithValue(
            _SilentInvalidationSource(),
          ),
          propertyMediaPortProvider.overrideWithValue(_EmptyPropertyMedia()),
        ],
        child: const NexImmoApp(environment: environment),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    // UX-FOUNDATION-IMPL-01 (Foundation §2): the root landing is the working
    // properties page, not the dashboard's migrationRequired empty state.
    expect(
      find.byKey(const Key('cloud-destination-migration-dashboard')),
      findsNothing,
    );
    // PROPERTY-WORKSPACE-01 A1: the properties destination is the Property
    // List V2 in front of the workspace host.
    expect(find.byKey(const Key('property-list')), findsOneWidget);
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
          notificationPortProvider.overrideWithValue(_EmptyNotificationPort()),
          platformQueryInvalidationSourceProvider.overrideWithValue(
            _SilentInvalidationSource(),
          ),
          propertyMediaPortProvider.overrideWithValue(_EmptyPropertyMedia()),
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
    // The deep link lands in the Property Workspace (host + `Übersicht`) after
    // the canonical getById, without any Navigator push.
    expect(find.byKey(const Key('property-workspace')), findsOneWidget);
    expect(find.byKey(const Key('property-overview')), findsOneWidget);
    expect(properties.overviewPropertyIds, <String>['property-a']);
    expect(navigator.canPop(), isFalse);
  });

  // PROPERTY-WORKSPACE-01 A1 QC: the real list → workspace handoff through
  // the connected provider graph. `openProperty` settles the Riverpod state
  // to `ready` and completes before the consumer rebuild has delivered that
  // state to the host's widget snapshot, so the host must not decide from
  // `widget.state` after the await. Harness tests cannot reproduce this;
  // only the provider-backed path does.
  testWidgets('Supabase list click opens the workspace after the canonical '
      'read', (tester) async {
    final identity = _IdentityRepository();
    final properties = _PropertyRepository();
    const environment = AppEnvironment(
      environment: NexImmoEnvironment.local,
      dataBackend: DataBackend.supabase,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'public-test-key',
    );
    // Desktop width: the table (with its explicit open action) renders above
    // the table shell's mobile fallback.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityAccessRepositoryProvider.overrideWithValue(identity),
          referencePropertyRepositoryProvider.overrideWithValue(properties),
          notificationPortProvider.overrideWithValue(_EmptyNotificationPort()),
          platformQueryInvalidationSourceProvider.overrideWithValue(
            _SilentInvalidationSource(),
          ),
          // The Objekt surface carries the media gallery
          // (PROPERTY-MEDIA-DATA-01); the port fails closed when unconfigured.
          propertyMediaPortProvider.overrideWithValue(_EmptyPropertyMedia()),
        ],
        child: const NexImmoApp(environment: environment),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('property-list')), findsOneWidget);
    expect(find.byKey(const Key('property-workspace')), findsNothing);
    expect(properties.detailPropertyIds, isEmpty, reason: 'list read only');

    await tester.tap(find.byKey(const Key('property-list-open-property-a')));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(
      properties.detailPropertyIds,
      <String>['property-a'],
      reason: 'exactly one canonical getById before the workspace shows',
    );
    expect(find.byKey(const Key('property-workspace')), findsOneWidget);
    // PROPERTY-OVERVIEW-DATA-01: the workspace lands on `Übersicht`, which
    // reads the summary contract for exactly the opened property.
    expect(find.byKey(const Key('property-overview')), findsOneWidget);
    expect(properties.overviewPropertyIds, <String>['property-a']);
    expect(find.byKey(const Key('property-list')), findsNothing);
    expect(find.text('Atlas House'), findsWidgets);
    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(navigator.canPop(), isFalse, reason: 'state-first, no push');

    // And `Objekt` is one domain switch away, on the same open property.
    await tester.tap(find.byKey(const Key('property-workspace-nav-asset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('property-asset')), findsOneWidget);
    expect(properties.detailPropertyIds, <String>[
      'property-a',
    ], reason: 'a domain switch re-reads nothing');
    expect(tester.takeException(), isNull);
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
  final List<String> createdNames = <String>[];
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

  /// Property ids the overview read was asked for. `Übersicht` is the default
  /// landing domain, so the connected host must reach exactly this contract.
  final List<String> overviewPropertyIds = <String>[];

  @override
  Future<PropertyRepositoryResult<PropertyOverviewDto>> overview({
    required String workspaceId,
    required String propertyId,
  }) async {
    overviewPropertyIds.add(propertyId);
    return PropertyRepositorySuccess<PropertyOverviewDto>(
      PropertyOverviewDto(
        propertyId: propertyId,
        workspaceId: workspaceId,
        name: property.name,
        asOf: DateTime.utc(2026, 9, 6, 8),
        leasing: const PropertyOverviewSection.available(<String, int>{
          'units_total': 12,
          'units_vacant': 2,
        }),
        maintenance: const PropertyOverviewSection.unavailable(
          'maintenance.read',
        ),
        capex: const PropertyOverviewSection.unavailable('capex.read'),
        tasks: const PropertyOverviewSection.unavailable('task.read'),
        documents: const PropertyOverviewSection.unavailable('document.read'),
        valuation: const PropertyOverviewSection.unavailable('valuation.read'),
      ),
    );
  }

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
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async {
    createdNames.add(command.draft.name);
    return PropertyRepositorySuccess<PropertyDto>(property);
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    return PropertyRepositorySuccess<PropertyDto>(property);
  }
}

// PERMISSION-CATALOG-02: the notification bell is part of the standard shell
// for every member (the own feed needs no permission), so the runtime harness
// binds an empty platform notification surface like the real wiring does.
class _EmptyNotificationPort implements NotificationPort {
  @override
  Future<PlatformRepositoryResult<PlatformPageResult<NotificationDto>>>
  notificationFeed(NotificationFeedQuery query) async {
    return const PlatformRepositorySuccess<PlatformPageResult<NotificationDto>>(
      PlatformPageResult<NotificationDto>(items: <NotificationDto>[]),
    );
  }

  @override
  Future<PlatformRepositoryResult<NotificationFanOutReceipt>>
  fanOutNotification(CreateNotificationCommand command) async {
    throw UnsupportedError('not part of the runtime harness');
  }

  @override
  Future<PlatformRepositoryResult<NotificationDto>> markNotificationRead(
    MarkNotificationReadCommand command,
  ) async {
    throw UnsupportedError('not part of the runtime harness');
  }
}

class _SilentInvalidationSource implements PlatformQueryInvalidationSource {
  @override
  Stream<PlatformQueryInvalidation> watchWorkspace({
    required String workspaceId,
  }) => const Stream<PlatformQueryInvalidation>.empty();
}

class _EmptyPropertyMedia implements PropertyMediaPort {
  @override
  Future<PropertyRepositoryResult<List<PropertyMediaDto>>> list({
    required String workspaceId,
    required String propertyId,
    bool includeArchived = false,
  }) async => const PropertyRepositorySuccess<List<PropertyMediaDto>>(
    <PropertyMediaDto>[],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the runtime test');
}
