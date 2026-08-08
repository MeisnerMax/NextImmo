import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the boundary AP-X02-2b established: **no legacy SQLite application
/// runtime wiring**.
///
/// Deliberately not "no legacy SQLite code exists anywhere". SQLite is still
/// required for migration, cutover, dry runs and the operations-signals parity
/// test, and those uses stay legitimate. What must never come back is a SQLite
/// path inside the productive app entrypoint or composition root, because that
/// is what made the app dual-backend in the first place.
///
/// The guard reads source text rather than analysing types: an accidental
/// reintroduction usually arrives as a pasted import or a resurrected branch,
/// and text is exactly the level at which that shows up.
void main() {
  const runtimeFiles = <String>[
    'lib/main.dart',
    'lib/app.dart',
    'lib/app_backend_wiring.dart',
  ];

  /// The five adapters AP-X02-2b deleted plus the two it retained. The retained
  /// pair may still be referenced by migration tooling and by the parity test —
  /// but never from the three files above.
  const forbiddenLegacyAdapters = <String>[
    'LegacySqlitePartyRepositoryAdapter',
    'LegacySqliteLeasingRepositoryAdapter',
    'LegacySqliteUnitRepositoryAdapter',
    'LegacySqliteLeaseRepositoryAdapter',
    'LegacySqliteLeasingCaseRepositoryAdapter',
    'LegacySqliteRentRollAdapter',
    'LegacySqliteMaintenanceTicketRepositoryAdapter',
    'LegacySqliteCapexProjectRepositoryAdapter',
    'LegacySqlitePlatformRepositoryAdapter',
    'LegacySqliteValuationRepositoryAdapter',
    'LegacySqliteDocumentRepositoryAdapter',
    'LegacySqliteOperationsSignalsAdapter',
  ];

  /// SQLite bootstrap symbols. Their presence in the entrypoint means the app
  /// opens a local database again.
  const forbiddenBootstrap = <String>[
    'sqfliteFfiInit',
    'databaseFactoryFfi',
    'AppDatabase(',
    'bootstrapDefaults',
    'StartupTaskService',
    'databaseProvider',
    'appDatabaseProvider',
  ];

  String read(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$path is missing; the guard cannot verify what it cannot read.',
    );
    return file.readAsStringSync();
  }

  group('no legacy SQLite application runtime wiring', () {
    for (final path in runtimeFiles) {
      test('$path selects no SQLite backend', () {
        final source = read(path);

        expect(
          source.contains('DataBackend.sqlite'),
          isFalse,
          reason:
              '$path references DataBackend.sqlite. Supabase is the only '
              'application runtime backend since AP-X02-2b (DEC-024).',
        );
      });

      test('$path wires no legacy adapter', () {
        final source = read(path);

        for (final adapter in forbiddenLegacyAdapters) {
          expect(
            source.contains(adapter),
            isFalse,
            reason:
                '$path references $adapter. Legacy adapters may only be used '
                'by migration tooling and the parity test, never by the '
                'productive app wiring.',
          );
        }
      });

      test('$path boots no local database', () {
        final source = read(path);

        for (final symbol in forbiddenBootstrap) {
          expect(
            source.contains(symbol),
            isFalse,
            reason:
                '$path references $symbol. The application runtime must not '
                'open or seed a local SQLite database.',
          );
        }
      });
    }

    test('DataBackend offers no backend to choose from', () {
      final source = read('lib/core/config/app_environment.dart');

      // NEXIMMO_DATA_BACKEND stays as a deployment guard, so the enum stays
      // too -- but with exactly one member, there is nothing left to switch on.
      expect(source.contains('enum DataBackend { supabase }'), isTrue);
      expect(source.contains('sqlite,'), isFalse);
    });

    test('the retained legacy adapters keep their non-runtime users', () {
      // The other half of the contract: this guard must not tempt anyone into
      // deleting the retained pair. Their legitimate users have to survive.
      expect(
        read(
          'lib/features/documents_compliance/data/'
          'sqlite_to_postgres_documents_compliance_dry_run_mapper.dart',
        ).contains('LegacySqliteDocumentRepositoryAdapter'),
        isTrue,
        reason:
            'The documents dry-run mapper still normalises type keys through '
            'the retained legacy adapter; that dependency is why the file was '
            'kept.',
      );
      expect(
        read(
          'test/integration/supabase_operations_signals_integration_test.dart',
        ).contains('LegacySqliteOperationsSignalsAdapter'),
        isTrue,
        reason:
            'The operations-signals parity test compares the cloud adapter '
            'against the legacy one; that comparison is why the file was kept.',
      );
    });
  });
}
