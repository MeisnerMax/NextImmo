import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/identity_access_repository.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/reference_slice/application/reference_slice_controller.dart';
import 'package:neximmo_app/features/reference_slice/presentation/reference_slice_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

void main() {
  group('ReferenceSliceView', () {
    testWidgets('renders unauthenticated and MFA states without data actions', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _state(authPhase: ReferenceAuthPhase.unauthenticated),
      );

      expect(find.text('Sign in to NexImmo'), findsOneWidget);
      expect(find.byKey(const Key('reference-auth-email')), findsOneWidget);
      expect(find.byKey(const Key('reference-list-pane')), findsNothing);

      await _pumpView(
        tester,
        state: _state(
          authPhase: ReferenceAuthPhase.mfaRequired,
          factors: const <TotpFactor>[
            TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
          ],
        ),
      );

      expect(find.text('Multi-factor authentication required'), findsOneWidget);
      expect(find.byKey(const Key('reference-mfa-code')), findsOneWidget);
      expect(find.byKey(const Key('reference-list-pane')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('submits passwordless email and TOTP step-up actions', (
      tester,
    ) async {
      String? requestedEmail;
      await _pumpView(
        tester,
        state: _state(authPhase: ReferenceAuthPhase.unauthenticated),
        onRequestPasswordlessSignIn: (email) async => requestedEmail = email,
      );

      await tester.enterText(
        find.byKey(const Key('reference-auth-email')),
        'user@example.test',
      );
      await tester.tap(find.byKey(const Key('reference-auth-submit')));
      await tester.pump();
      expect(requestedEmail, 'user@example.test');

      String? factorId;
      String? code;
      await _pumpView(
        tester,
        state: _state(
          authPhase: ReferenceAuthPhase.mfaRequired,
          factors: const <TotpFactor>[
            TotpFactor(id: 'factor-a', friendlyName: 'Primary'),
          ],
        ),
        onVerifyTotp: ({
          required selectedFactorId,
          required selectedCode,
        }) async {
          factorId = selectedFactorId;
          code = selectedCode;
        },
      );
      await tester.enterText(
        find.byKey(const Key('reference-mfa-code')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('reference-mfa-verify')));
      await tester.pump();

      expect(factorId, 'factor-a');
      expect(code, '123456');
    });

    testWidgets('TOTP enrollment remains usable on a small phone', (
      tester,
    ) async {
      String? verifiedCode;
      await _pumpView(
        tester,
        viewport: const Size(320, 568),
        state: _readyState(
          assuranceLevel: AuthenticationAssuranceLevel.aal1,
          totpEnrollment: const TotpEnrollment(
            factorId: 'factor-new',
            secret: 'ABCDEFGHIJKLMNOP',
            uri: 'otpauth://totp/NexImmo',
          ),
        ),
        onVerifyTotp: ({
          required selectedFactorId,
          required selectedCode,
        }) async {
          verifiedCode = selectedCode;
        },
      );

      expect(
        find.byKey(const Key('reference-mfa-enrollment-secret')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('reference-mfa-code')),
        '654321',
      );
      await tester.ensureVisible(
        find.byKey(const Key('reference-mfa-enrollment-verify')),
      );
      await tester.tap(
        find.byKey(const Key('reference-mfa-enrollment-verify')),
      );
      await tester.pump();

      expect(verifiedCode, '654321');
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters the property list without losing workspace scope', (
      tester,
    ) async {
      await _pumpView(tester, state: _readyState(twoProperties: true));

      expect(find.text('Atlas House'), findsWidgets);
      expect(find.text('Beta Offices'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('reference-property-search')),
        'beta',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('reference-property-property-a')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('reference-property-property-b')),
        findsOneWidget,
      );
      expect(find.text('Workspace A'), findsOneWidget);
    });

    testWidgets('phone switches between list and vertically stacked detail', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      var showDetail = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder:
              (context, setState) => _app(
                ReferenceSliceView(
                  state: _readyState(),
                  showCompactDetail: showDetail,
                  onBackToList: () => setState(() => showDetail = false),
                  onOpenProperty:
                      (_) async => setState(() => showDetail = true),
                  onRefreshWorkspaces: _noop,
                  onSelectWorkspace: _noopString,
                  onReloadProperties: _noop,
                  onLoadNextPage: _noop,
                  onUpdateProperty: (_) async {},
                  onRetryUpdate: _noop,
                  onRequestPasswordlessSignIn: _noopString,
                  onBeginTotpEnrollment: _noop,
                  onVerifyTotp: _noopVerify,
                  onSignOut: _noop,
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
      expect(find.byKey(const Key('reference-detail-pane')), findsNothing);

      await tester.tap(find.byKey(const Key('reference-property-property-a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-list-pane')), findsNothing);
      expect(find.byKey(const Key('reference-detail-pane')), findsOneWidget);
      expect(find.byKey(const Key('reference-edit-form')), findsOneWidget);
      expect(find.byKey(const Key('reference-compact-back')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('reference-compact-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
    });

    for (final viewport in const <Size>[
      Size(390, 844),
      Size(767, 900),
      Size(768, 900),
      Size(1024, 768),
      Size(1199, 900),
      Size(1200, 900),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $viewport', (tester) async {
        await _pumpView(tester, state: _readyState(), viewport: viewport);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('reference-list-pane')), findsOneWidget);
        if (viewport.width > 1199) {
          expect(
            find.byKey(const Key('reference-detail-pane')),
            findsOneWidget,
          );
        } else {
          expect(find.byKey(const Key('reference-detail-pane')), findsNothing);
        }
      });
    }

    testWidgets('shows conflict feedback and retryable failure action', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: _readyState(
          mutationPhase: PropertyMutationPhase.conflict,
          versionConflict: PropertyVersionConflict(
            expectedVersion: 1,
            actualVersion: 2,
            currentProperty: _property(version: 2),
          ),
        ),
        viewport: const Size(1440, 900),
      );

      expect(find.textContaining('Version conflict'), findsOneWidget);

      await _pumpView(
        tester,
        state: _readyState(
          mutationPhase: PropertyMutationPhase.failed,
          failureKind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Temporary failure.',
        ),
        viewport: const Size(1440, 900),
      );

      expect(find.text('Temporary failure.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    for (final golden in const <(String, Size)>[
      ('phone', Size(390, 844)),
      ('tablet', Size(1024, 768)),
      ('desktop', Size(1440, 900)),
    ]) {
      testWidgets('matches ready $golden golden', (tester) async {
        await _pumpView(
          tester,
          state: _readyState(twoProperties: true),
          viewport: golden.$2,
        );

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/reference_slice_ready_${golden.$1}.png'),
        );
      });
    }
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required ReferenceSliceState state,
  Size viewport = const Size(1440, 900),
  Future<void> Function(String email)? onRequestPasswordlessSignIn,
  Future<void> Function({
    required String selectedFactorId,
    required String selectedCode,
  })?
  onVerifyTotp,
}) async {
  _setViewport(tester, viewport);
  await tester.pumpWidget(
    _app(
      ReferenceSliceView(
        state: state,
        showCompactDetail: false,
        onBackToList: () {},
        onRefreshWorkspaces: _noop,
        onSelectWorkspace: _noopString,
        onReloadProperties: _noop,
        onLoadNextPage: _noop,
        onOpenProperty: _noopString,
        onUpdateProperty: (_) async {},
        onRetryUpdate: _noop,
        onRequestPasswordlessSignIn: onRequestPasswordlessSignIn ?? _noopString,
        onBeginTotpEnrollment: _noop,
        onVerifyTotp:
            ({required factorId, required code}) =>
                onVerifyTotp == null
                    ? _noopVerify(factorId: factorId, code: code)
                    : onVerifyTotp(
                      selectedFactorId: factorId,
                      selectedCode: code,
                    ),
        onSignOut: _noop,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );
}

void _setViewport(WidgetTester tester, Size viewport) {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _noop() async {}

Future<void> _noopString(String _) async {}

Future<void> _noopVerify({
  required String factorId,
  required String code,
}) async {}

ReferenceSliceState _state({
  required ReferenceAuthPhase authPhase,
  List<TotpFactor> factors = const <TotpFactor>[],
}) {
  return ReferenceSliceState(
    authPhase: authPhase,
    workspacePhase: WorkspacePhase.idle,
    propertyListPhase: PropertyListPhase.idle,
    propertyDetailPhase: PropertyDetailPhase.idle,
    mutationPhase: PropertyMutationPhase.idle,
    totpFactors: factors,
  );
}

ReferenceSliceState _readyState({
  bool twoProperties = false,
  PropertyMutationPhase mutationPhase = PropertyMutationPhase.idle,
  PropertyRepositoryFailureKind? failureKind,
  PropertyVersionConflict? versionConflict,
  String? message,
  AuthenticationAssuranceLevel assuranceLevel =
      AuthenticationAssuranceLevel.aal2,
  TotpEnrollment? totpEnrollment,
}) {
  final property = _property();
  return ReferenceSliceState(
    authPhase: ReferenceAuthPhase.authenticated,
    assuranceLevel: assuranceLevel,
    workspacePhase: WorkspacePhase.selected,
    propertyListPhase: PropertyListPhase.ready,
    propertyDetailPhase: PropertyDetailPhase.ready,
    mutationPhase: mutationPhase,
    userId: 'user-a',
    workspaces: <WorkspaceAccess>[_access()],
    selectedWorkspaceId: 'workspace-a',
    properties: <PropertyDto>[
      property,
      if (twoProperties)
        _property(
          id: 'property-b',
          name: 'Beta Offices',
          address: 'Office Road 2',
        ),
    ],
    selectedProperty: property,
    failureKind: failureKind,
    versionConflict: versionConflict,
    message: message,
    totpEnrollment: totpEnrollment,
  );
}

WorkspaceAccess _access() {
  return WorkspaceAccess(
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
  );
}

PropertyDto _property({
  String id = 'property-a',
  String name = 'Atlas House',
  String address = 'Long Street 123',
  int version = 1,
}) {
  return PropertyDto(
    id: id,
    workspaceId: 'workspace-a',
    name: name,
    addressLine1: address,
    zip: '10115',
    city: 'Berlin',
    country: 'DE',
    propertyType: 'mixed_use',
    units: 12,
    notes: 'Reference slice fixture',
    status: PropertyStatus.active,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 17),
    createdBy: 'user-a',
    updatedBy: 'user-a',
    version: version,
  );
}
