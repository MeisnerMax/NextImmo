enum NexImmoEnvironment { local, staging, production }

enum DataBackend { sqlite, supabase }

class AppEnvironment {
  const AppEnvironment({
    required this.environment,
    required this.dataBackend,
    this.supabaseUrl,
    this.supabasePublishableKey,
  });

  factory AppEnvironment.fromValues({
    required String environment,
    required String dataBackend,
    String supabaseUrl = '',
    String supabasePublishableKey = '',
  }) {
    final parsedEnvironment =
        NexImmoEnvironment.values
            .where((value) => value.name == environment)
            .firstOrNull;
    if (parsedEnvironment == null) {
      throw StateError('NEXIMMO_ENV is missing or invalid.');
    }

    final parsedBackend =
        DataBackend.values
            .where((value) => value.name == dataBackend)
            .firstOrNull;
    if (parsedBackend == null) {
      throw StateError('NEXIMMO_DATA_BACKEND is missing or invalid.');
    }

    final normalizedUrl = supabaseUrl.trim();
    final normalizedKey = supabasePublishableKey.trim();
    if (parsedBackend == DataBackend.supabase) {
      final uri = Uri.tryParse(normalizedUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw StateError('SUPABASE_URL is missing or invalid.');
      }
      if (normalizedKey.isEmpty) {
        throw StateError('SUPABASE_PUBLISHABLE_KEY is missing.');
      }
    }

    return AppEnvironment(
      environment: parsedEnvironment,
      dataBackend: parsedBackend,
      supabaseUrl: normalizedUrl.isEmpty ? null : normalizedUrl,
      supabasePublishableKey: normalizedKey.isEmpty ? null : normalizedKey,
    );
  }

  factory AppEnvironment.fromDartDefines() {
    return AppEnvironment.fromValues(
      environment: const String.fromEnvironment('NEXIMMO_ENV'),
      dataBackend: const String.fromEnvironment('NEXIMMO_DATA_BACKEND'),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
    );
  }

  final NexImmoEnvironment environment;
  final DataBackend dataBackend;
  final String? supabaseUrl;
  final String? supabasePublishableKey;
}
