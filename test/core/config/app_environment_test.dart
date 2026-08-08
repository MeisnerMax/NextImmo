import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/config/app_environment.dart';

void main() {
  // NEXIMMO_DATA_BACKEND survives AP-X02-2b as a deployment safety guard: every
  // build must still declare which backend it was configured for. What changed
  // is that `supabase` is now the only answer that parses, so a stale `sqlite`
  // define fails exactly like a missing one instead of silently booting a
  // backend that no longer exists.

  group('accepted', () {
    for (final environment in <String>['local', 'staging', 'production']) {
      test('$environment with supabase is valid', () {
        final config = AppEnvironment.fromValues(
          environment: environment,
          dataBackend: 'supabase',
          supabaseUrl: 'https://project.supabase.co',
          supabasePublishableKey: 'publishable-key',
        );

        expect(config.environment.name, environment);
        expect(config.dataBackend, DataBackend.supabase);
        expect(config.supabaseUrl, 'https://project.supabase.co');
        expect(config.supabasePublishableKey, 'publishable-key');
      });
    }

    test('trims surrounding whitespace on the Supabase values', () {
      final config = AppEnvironment.fromValues(
        environment: 'local',
        dataBackend: 'supabase',
        supabaseUrl: '  http://127.0.0.1:54321  ',
        supabasePublishableKey: '  publishable-key  ',
      );

      expect(config.supabaseUrl, 'http://127.0.0.1:54321');
      expect(config.supabasePublishableKey, 'publishable-key');
    });
  });

  group('fails closed', () {
    test('a missing backend is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: '',
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the retired sqlite backend is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: 'sqlite',
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an unknown backend is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: 'automatic',
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a missing environment is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: '',
          dataBackend: 'supabase',
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an unknown environment is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'sandbox',
          dataBackend: 'supabase',
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a missing Supabase URL is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: 'supabase',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a malformed Supabase URL is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: 'supabase',
          supabaseUrl: 'not-a-url',
          supabasePublishableKey: 'publishable-key',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a missing publishable key is rejected', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'local',
          dataBackend: 'supabase',
          supabaseUrl: 'http://127.0.0.1:54321',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
