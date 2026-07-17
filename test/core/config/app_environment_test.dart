import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/config/app_environment.dart';

void main() {
  test('accepts an explicit local SQLite environment', () {
    final config = AppEnvironment.fromValues(
      environment: 'local',
      dataBackend: 'sqlite',
    );

    expect(config.environment, NexImmoEnvironment.local);
    expect(config.dataBackend, DataBackend.sqlite);
    expect(config.supabaseUrl, isNull);
  });

  test('requires URL and publishable key for Supabase', () {
    expect(
      () => AppEnvironment.fromValues(
        environment: 'staging',
        dataBackend: 'supabase',
      ),
      throwsStateError,
    );
    expect(
      () => AppEnvironment.fromValues(
        environment: 'staging',
        dataBackend: 'supabase',
        supabaseUrl: 'not-a-url',
        supabasePublishableKey: 'public-key',
      ),
      throwsStateError,
    );
  });

  test('accepts complete Supabase public configuration', () {
    final config = AppEnvironment.fromValues(
      environment: 'production',
      dataBackend: 'supabase',
      supabaseUrl: 'https://project.supabase.co',
      supabasePublishableKey: 'public-key',
    );

    expect(config.environment, NexImmoEnvironment.production);
    expect(config.dataBackend, DataBackend.supabase);
    expect(config.supabaseUrl, 'https://project.supabase.co');
    expect(config.supabasePublishableKey, 'public-key');
  });

  test('unknown environment and backend values fail closed', () {
    expect(
      () => AppEnvironment.fromValues(
        environment: 'preview',
        dataBackend: 'sqlite',
      ),
      throwsStateError,
    );
    expect(
      () => AppEnvironment.fromValues(
        environment: 'local',
        dataBackend: 'automatic',
      ),
      throwsStateError,
    );
  });
}
