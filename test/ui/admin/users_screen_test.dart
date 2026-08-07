import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/security.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/ui/screens/admin/users_screen.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for `UsersScreen` (Phase 2 Wave 1 / AP7c). The
/// screen is gated on the same role check the navigation uses, so a non-admin
/// role sees an explicit forbidden state. The security context is provided by a
/// fake `SecurityController`; the user list load is driven through its
/// `listUsers`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seedUsers = <LocalUserRecord>[
    LocalUserRecord(
      id: 'me',
      workspaceId: 'w1',
      email: 'me@hq.io',
      displayName: 'Me Admin',
      passwordHash: 'x',
      passwordSalt: 'y',
      role: 'admin',
      createdAt: 1,
    ),
    LocalUserRecord(
      id: 'u2',
      workspaceId: 'w1',
      email: null,
      displayName: 'Bob Manager',
      passwordHash: null,
      passwordSalt: null,
      role: 'asset_manager',
      createdAt: 2,
    ),
  ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    String role = 'admin',
    _UsersLoad mode = _UsersLoad.populated,
    Size size = const Size(1280, 800),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityControllerProvider.overrideWith(
            () => _FakeSecurityController(role: role, mode: mode, users: seedUsers),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: UsersScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('non-admin role sees an explicit forbidden state', (tester) async {
    await pumpScreen(tester, role: 'viewer');

    expect(find.text('Kein Zugriff'), findsOneWidget);
    expect(find.text('Benutzer anlegen'), findsNothing);
  });

  testWidgets('loading shows a skeleton, not a full-surface spinner', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _UsersLoad.pending, settle: false);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('users_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty user list shows the empty state', (tester) async {
    await pumpScreen(tester, mode: _UsersLoad.empty);

    expect(find.text('Keine Benutzer'), findsOneWidget);
  });

  testWidgets('load failure shows retry state without raw exception text', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _UsersLoad.error);

    expect(
      find.text('Benutzer konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('admin sees the user list', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Benutzer'), findsWidgets);
    expect(find.text('Me Admin'), findsOneWidget);
    expect(find.text('Bob Manager'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
  });

  testWidgets('phone width renders the user list without overflow', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(390, 844));
    expect(find.text('Bob Manager'), findsOneWidget);
  });

  testWidgets('tablet width renders without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(1024, 768));
    expect(find.text('Bob Manager'), findsOneWidget);
  });

  testWidgets('desktop width renders without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(1440, 900));
    expect(find.text('Bob Manager'), findsOneWidget);
  });
}

enum _UsersLoad { populated, empty, error, pending }

class _FakeSecurityController extends SecurityController {
  _FakeSecurityController({
    required this.role,
    required this.mode,
    required this.users,
  });

  final String role;
  final _UsersLoad mode;
  final List<LocalUserRecord> users;

  @override
  Future<SecurityState> build() async {
    return SecurityState(
      settings: const AppSettingsRecord(updatedAt: 1),
      context: SecurityContextRecord(
        workspace: const WorkspaceRecord(
          id: 'w1',
          name: 'HQ',
          docsRootPath: '.',
          createdAt: 1,
        ),
        user: LocalUserRecord(
          id: 'me',
          workspaceId: 'w1',
          email: 'me@hq.io',
          displayName: 'Me Admin',
          passwordHash: 'x',
          passwordSalt: 'y',
          role: role,
          createdAt: 1,
        ),
      ),
      isLocked: false,
    );
  }

  @override
  Future<List<LocalUserRecord>> listUsers(String workspaceId) {
    switch (mode) {
      case _UsersLoad.pending:
        return Completer<List<LocalUserRecord>>().future;
      case _UsersLoad.error:
        return Future<List<LocalUserRecord>>.error(Exception('boom'));
      case _UsersLoad.empty:
        return Future<List<LocalUserRecord>>.value(const <LocalUserRecord>[]);
      case _UsersLoad.populated:
        return Future<List<LocalUserRecord>>.value(users);
    }
  }
}
