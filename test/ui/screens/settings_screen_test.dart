import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/data/repositories/inputs_repo.dart';
import 'package:neximmo_app/data/repositories/workspace_repo.dart';
import 'package:neximmo_app/ui/screens/settings_screen.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:neximmo_app/ui/state/security_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for `SettingsScreen` (Phase 2 Wave 1 / AP8). The
/// screen hydrates from a single `getSettings` read, so the initial load has one
/// skeleton and one retry state; the draft/save pipeline is exercised through
/// the real controllers. The role is pinned to `admin` so the edit-gated fields
/// are enabled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(
    WidgetTester tester, {
    _SettingsLoad mode = _SettingsLoad.populated,
    String role = 'admin',
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
          inputsRepositoryProvider.overrideWithValue(_FakeInputsRepo(mode)),
          workspaceRepositoryProvider.overrideWithValue(_FakeWorkspaceRepo()),
          activeUserRoleProvider.overrideWithValue(role),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('loading shows a skeleton, not a full-surface spinner', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _SettingsLoad.pending, settle: false);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('settings_skeleton')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('load failure shows retry state without raw exception text', (
    tester,
  ) async {
    await pumpScreen(tester, mode: _SettingsLoad.error);

    expect(
      find.text('Einstellungen konnten nicht geladen werden'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('loaded settings render the template and default section', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Settings'), findsWidgets);
    // General is both a nav entry and the default section intro/body.
    expect(find.text('General'), findsWidgets);
    expect(find.text('General Defaults'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settings_skeleton')), findsNothing);
  });

  testWidgets('selecting a section swaps the content pane', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Operating Defaults'), findsNothing);
    await tester.tap(find.text('Analysis Defaults'));
    await tester.pumpAndSettle();

    expect(find.text('Operating Defaults'), findsOneWidget);
    expect(find.text('General Defaults'), findsNothing);
  });

  testWidgets('editing a field updates the save/draft status', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Pending fields: 0'), findsOneWidget);

    // The first TextField in the General section is the currency code (EUR).
    await tester.enterText(find.byType(TextField).first, 'ZZZ');
    await tester.pump();

    expect(find.text('Pending fields: 1'), findsOneWidget);
    expect(find.text('All changes saved'), findsNothing);
  });

  testWidgets('phone width renders without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(390, 844));
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('tablet width renders without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(1024, 768));
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('desktop width renders without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(1440, 900));
    expect(find.text('Settings'), findsWidgets);
  });
}

enum _SettingsLoad { populated, error, pending }

class _FakeInputsRepo implements InputsRepository {
  _FakeInputsRepo(this.mode);

  final _SettingsLoad mode;

  @override
  Future<AppSettingsRecord> getSettings() {
    switch (mode) {
      case _SettingsLoad.pending:
        return Completer<AppSettingsRecord>().future;
      case _SettingsLoad.error:
        return Future<AppSettingsRecord>.error(Exception('boom'));
      case _SettingsLoad.populated:
        // Root path matches the resolved workspace path so a fresh load starts
        // with zero pending draft changes.
        return Future<AppSettingsRecord>.value(
          const AppSettingsRecord(updatedAt: 1, workspaceRootPath: '/ws'),
        );
    }
  }

  @override
  Future<void> updateSettings(AppSettingsRecord settings) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}

class _FakeWorkspaceRepo implements WorkspaceRepository {
  @override
  Future<WorkspacePaths> resolvePaths(AppSettingsRecord settings) async {
    return const WorkspacePaths(
      rootPath: '/ws',
      docsPath: '/ws/docs',
      exportsPath: '/ws/docs/exports',
      backupsPath: '/ws/backups',
      tempPath: '/ws/tmp',
      dbPath: '/ws/app.db',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not exercised by these tests');
}
