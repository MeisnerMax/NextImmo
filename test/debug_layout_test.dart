import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/data/sqlite/db.dart';
import 'package:neximmo_app/ui/shell/app_scaffold.dart';
import 'package:neximmo_app/ui/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appDatabase = AppDatabase(overridePath: inMemoryDatabasePath);
    db = await appDatabase.instance;
  });

  tearDownAll(() async {
    await appDatabase.close();
  });

  testWidgets('debug dashboard layout', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appDatabaseProvider.overrideWithValue(appDatabase),
          ],
          child: const MaterialApp(home: AppScaffold()),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 200));
    });

    await tester.pump();

    debugPrint('--- RENDER FLEX DIAGNOSTICS (DASHBOARD) ---');
    void visitor(Element element) {
      final renderObject = element.renderObject;
      if (renderObject is RenderFlex) {
        final parentData = renderObject.parentData;
        final offset = parentData is BoxParentData ? parentData.offset : null;
        
        // Check if there is an overflow
        // We can inspect if the renderObject has overflowed by comparing size with constraints or using its internal fields if accessible,
        // or just print details for all horizontal ones.
        if (renderObject.direction == Axis.horizontal) {
          debugPrint('Horizontal RenderFlex:');
          debugPrint('  Creator: ${element.widget.runtimeType}');
          debugPrint('  Constraints: ${renderObject.constraints}');
          debugPrint('  Size: ${renderObject.hasSize ? renderObject.size : "No Size"}');
          debugPrint('  Offset: $offset');
          
          final ancestors = <String>[];
          element.visitAncestorElements((parent) {
            ancestors.add(parent.widget.runtimeType.toString());
            return ancestors.length < 5;
          });
          debugPrint('  Ancestors: ${ancestors.join(" -> ")}');
        }
      }
      element.visitChildren(visitor);
    }

    tester.binding.rootElement?.visitChildren(visitor);
    debugPrint('-------------------------------------------');
  });
}
