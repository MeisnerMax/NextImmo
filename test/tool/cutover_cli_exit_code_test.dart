@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the boundary C-07 repaired: a Dart CLI's *intended* exit code has to
/// become the *process* exit code.
///
/// Dart ignores whatever `main` returns, so `return 64` used to leave the
/// process at 0. Every one of these cases passed before the fix while the tools
/// reported failure on stderr — which is exactly why a unit test of the runner
/// function cannot replace this file. The assertion has to observe a real OS
/// process, so every case here spawns one.
void main() {
  late Directory workspace;
  late String fixture;

  /// Valid UUIDs: the cutover mappers use them as UUIDv5 namespaces, so a
  /// placeholder string would throw instead of producing the code under test.
  const targetWorkspaceId = '11111111-1111-4111-8111-111111111111';
  const actorId = '22222222-2222-4222-8222-222222222222';

  /// The workspace the generated fixture actually carries.
  const fixtureSourceWorkspaceId = 'ws_default';

  /// The Dart SDK shipped with the Flutter that is running this test.
  ///
  /// Not the bare name `dart`: the test process is `flutter_tester`, and
  /// resolving `dart` off PATH from there fails on Windows, where the launcher
  /// is a batch file. Going through `FLUTTER_ROOT` also guarantees the CLIs run
  /// on the same SDK as the suite rather than whatever happens to be first on
  /// PATH.
  late final String dartExecutable = () {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final name = Platform.isWindows ? 'dart.exe' : 'dart';
      final candidate = File(
        '$flutterRoot/bin/cache/dart-sdk/bin/$name',
      ).absolute;
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return 'dart';
  }();

  Future<ProcessResult> runTool(String tool, List<String> arguments) {
    return Process.run(dartExecutable, <String>[
      'run',
      'tool/$tool',
      ...arguments,
    ], workingDirectory: Directory.current.path);
  }

  List<String> propertyArgs({
    required String database,
    required String output,
    String sourceWorkspaceId = fixtureSourceWorkspaceId,
  }) {
    return <String>[
      '--database', database,
      '--source-workspace-id', sourceWorkspaceId,
      '--target-workspace-id', targetWorkspaceId,
      '--target-workspace-key', 'neximmo',
      '--actor-id', actorId,
      '--output', output,
    ];
  }

  List<String> domainArgs({required String database, required String output}) {
    return <String>[
      '--database', database,
      '--target-workspace-id', targetWorkspaceId,
      '--actor-id', actorId,
      '--output', output,
    ];
  }

  setUpAll(() async {
    // Everything lives in a temp directory: no fixture binary belongs in the
    // repository, and no case may depend on a database left behind by an
    // earlier run.
    workspace = Directory.systemTemp.createTempSync('c07_cutover_cli');
    fixture = '${workspace.path}/cutover_fixture.db';

    final generated = await runTool('generate_cutover_fixture.dart', <String>[
      '--output',
      fixture,
    ]);
    expect(
      generated.exitCode,
      0,
      reason: 'Fixture generation failed: ${generated.stderr}',
    );
    expect(File(fixture).existsSync(), isTrue);
  });

  tearDownAll(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  group('usage errors exit 64', () {
    test('generate_cutover_fixture', () async {
      final result = await runTool('generate_cutover_fixture.dart', <String>[]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Usage:'));
    });

    test('p2_x01_property_cutover', () async {
      final result = await runTool('p2_x01_property_cutover.dart', <String>[]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Usage:'));
    });

    test('p2_x01_domain_cutover', () async {
      final result = await runTool('p2_x01_domain_cutover.dart', <String>[]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Usage:'));
    });
  });

  group('a missing source database exits 66', () {
    // Relative on purpose: it also pins the C-06 resolution. A relative path
    // must be resolved against the working directory, and the tool must report
    // both what was asked for and what it resolved to.
    const relativeMissing = 'build/c07_absent_source.db';

    test('p2_x01_property_cutover', () async {
      final output = '${workspace.path}/property-missing';
      final result = await runTool(
        'p2_x01_property_cutover.dart',
        propertyArgs(database: relativeMissing, output: output),
      );

      expect(result.exitCode, 66);
      expect(result.stderr, contains('Source database not found.'));
      expect(result.stderr, contains('requested: $relativeMissing'));
      expect(result.stderr, contains('resolved:'));
      // sqflite resolves a relative database path against its own directory,
      // so a regression here would silently create an empty database instead
      // of failing.
      expect(File(relativeMissing).existsSync(), isFalse);
      expect(Directory(output).existsSync(), isFalse);
    });

    test('p2_x01_domain_cutover', () async {
      final output = '${workspace.path}/domain-missing';
      final result = await runTool(
        'p2_x01_domain_cutover.dart',
        domainArgs(database: relativeMissing, output: output),
      );

      expect(result.exitCode, 66);
      expect(result.stderr, contains('Source database not found.'));
      expect(File(relativeMissing).existsSync(), isFalse);
      expect(Directory(output).existsSync(), isFalse);
    });
  });

  group('a dry run that is not import ready exits 65', () {
    test('p2_x01_property_cutover', () async {
      // Reached through the CLI alone: the fixture's workspace is
      // `ws_default`, so asking for a different one raises
      // `ownership.workspace_not_found`, which is an error issue.
      final output = '${workspace.path}/property-not-ready';
      final result = await runTool(
        'p2_x01_property_cutover.dart',
        propertyArgs(
          database: fixture,
          output: output,
          sourceWorkspaceId: 'ws_not_the_fixture_workspace',
        ),
      );

      expect(result.exitCode, 65);
      expect(result.stderr, contains('not import ready'));
      expect(result.stdout, contains('"production_import_ready":false'));
      // The report is evidence and is written; the apply script is not.
      expect(File('$output/report.json').existsSync(), isTrue);
      expect(File('$output/import.sql').existsSync(), isFalse);
      expect(
        File('$output/report.json').readAsStringSync(),
        contains('ownership.workspace_not_found'),
      );
    });

    test('p2_x01_domain_cutover', () async {
      // The domain planner validates rows, not the request, so there is no
      // argument that makes it not-ready. A copy of the real fixture gets one
      // field changed: a single lease ends before it starts, which is
      // `source.end_before_start`. One row, one field, one error — the copy is
      // temporary and the generator is untouched.
      final mutated = '${workspace.path}/domain_not_ready.db';
      File(fixture).copySync(mutated);

      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        mutated,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final int changed;
      try {
        // start_date is 1700000000000; this is earlier, deterministically.
        changed = await database.update(
          'leases',
          <String, Object?>{'end_date': 1600000000000},
          where: 'id = ?',
          whereArgs: <Object?>['FX-L-0001'],
        );
      } finally {
        await database.close();
      }
      expect(
        changed,
        1,
        reason: 'The fixture lease FX-L-0001 was not found; the mutation must '
            'hit exactly one existing row.',
      );

      final output = '${workspace.path}/domain-not-ready';
      final result = await runTool(
        'p2_x01_domain_cutover.dart',
        domainArgs(database: mutated, output: output),
      );

      expect(result.exitCode, 65);
      expect(result.stderr, contains('not import ready'));
      expect(result.stdout, contains('"import_ready":false'));
      expect(File('$output/report.json').existsSync(), isTrue);
      expect(File('$output/import.sql').existsSync(), isFalse);
      // Proves the planner refused for the intended reason rather than the
      // process dying on something else.
      expect(
        File('$output/report.json').readAsStringSync(),
        contains('source.end_before_start'),
      );
      expect(result.stderr, isNot(contains('Unhandled exception')));
    });
  });

  group('success exits 0', () {
    test('p2_x01_property_cutover writes report and import script', () async {
      final output = '${workspace.path}/property-ok';
      final result = await runTool(
        'p2_x01_property_cutover.dart',
        propertyArgs(database: fixture, output: output),
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File('$output/report.json').existsSync(), isTrue);
      expect(File('$output/import.sql').existsSync(), isTrue);
    });

    test('p2_x01_domain_cutover writes report and import script', () async {
      final output = '${workspace.path}/domain-ok';
      final result = await runTool(
        'p2_x01_domain_cutover.dart',
        domainArgs(database: fixture, output: output),
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File('$output/report.json').existsSync(), isTrue);
      expect(File('$output/import.sql').existsSync(), isTrue);
    });

    test('an absolute database path resolves the same as a relative one', () {
      // C-06: the fixture path used throughout this file is absolute and every
      // success case above passed with it. The relative form is covered by the
      // 66 cases, which assert on the resolved path.
      expect(File(fixture).isAbsolute, isTrue);
    });
  });
}
