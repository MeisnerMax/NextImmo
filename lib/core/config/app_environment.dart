enum NexImmoEnvironment { local, staging, production }

/// Supabase is the only application runtime backend (`DEC-024`, AP-X02-2b).
///
/// The enum keeps a single member on purpose rather than disappearing:
/// `NEXIMMO_DATA_BACKEND` stays a deployment safety guard, so every build must
/// still state which backend it was configured for. A binary that was built
/// without that define, or with the retired `sqlite` value, refuses to start
/// instead of quietly assuming Supabase.
enum DataBackend { supabase }

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

    // `sqlite` no longer parses: it is not a member any more, so the retired
    // value fails here exactly like a missing or unknown one.
    final parsedBackend =
        DataBackend.values
            .where((value) => value.name == dataBackend)
            .firstOrNull;
    if (parsedBackend == null) {
      throw StateError(
        'NEXIMMO_DATA_BACKEND is missing or invalid; only "supabase" is supported.',
      );
    }

    final normalizedUrl = supabaseUrl.trim();
    final normalizedKey = supabasePublishableKey.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('SUPABASE_URL is missing or invalid.');
    }
    if (normalizedKey.isEmpty) {
      throw StateError('SUPABASE_PUBLISHABLE_KEY is missing.');
    }

    return AppEnvironment(
      environment: parsedEnvironment,
      dataBackend: parsedBackend,
      supabaseUrl: normalizedUrl,
      supabasePublishableKey: normalizedKey,
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
