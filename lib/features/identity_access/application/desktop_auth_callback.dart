/// Desktop authentication callback contract.
///
/// The browser completes the Supabase sign-in and then hands control back to
/// the desktop app through a custom URI scheme. Everything about that handoff
/// that does not need an SDK lives here, so it can be exercised as plain unit
/// tests: the canonical URI, what counts as our callback, and what must be
/// ignored.
library;

/// The one canonical desktop callback URI.
///
/// It is registered with Windows as a protocol handler, sent to Supabase as
/// `emailRedirectTo`, and must appear in the Supabase redirect allowlist of
/// every environment the desktop app talks to. There is deliberately no second
/// desktop callback: the allowlist is a security boundary, and every extra
/// entry widens it.
const desktopAuthCallbackUri = 'neximmo://auth/callback';

const _expectedScheme = 'neximmo';
const _expectedHost = 'auth';
const _expectedPath = '/callback';

/// Auth material GoTrue understands. `code` is the PKCE authorization code,
/// `access_token` the implicit-flow token; the `error*` triple is how the
/// provider reports a refusal.
const _sessionParameters = <String>{'code', 'access_token'};
const _errorParameters = <String>{'error', 'error_code', 'error_description'};

/// What an incoming URI turned out to be.
sealed class DesktopAuthCallback {
  const DesktopAuthCallback();
}

/// A well-formed callback carrying auth material. Only this variant may reach
/// the session exchange.
final class DesktopAuthSessionCallback extends DesktopAuthCallback {
  const DesktopAuthSessionCallback({required this.uri, required this.token});

  /// The full URI, passed to the exchange unchanged — GoTrue reads the
  /// parameters itself and we must not paraphrase them.
  final Uri uri;

  /// The single-use credential the callback carries. Used as the deduplication
  /// key, because it is exactly what must not be redeemed twice.
  final String token;
}

/// A well-formed callback in which the provider reported a failure. Carries no
/// auth material, so there is nothing to exchange.
final class DesktopAuthErrorCallback extends DesktopAuthCallback {
  const DesktopAuthErrorCallback({required this.code, required this.description});

  final String? code;
  final String? description;
}

/// Not our callback, or not usable. Must be ignored — never forwarded.
final class DesktopAuthRejectedCallback extends DesktopAuthCallback {
  const DesktopAuthRejectedCallback(this.reason);

  final DesktopAuthRejectionReason reason;
}

enum DesktopAuthRejectionReason {
  malformedUri,
  unexpectedScheme,
  unexpectedHost,
  unexpectedPath,
  missingAuthParameters,
}

/// Classifies a raw deep-link string.
///
/// Windows will hand us whatever a `neximmo:` link contained, and any web page
/// can produce such a link. Nothing here trusts the input: an unparseable
/// string is a rejection, not an exception.
DesktopAuthCallback classifyDesktopAuthCallbackString(String value) {
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    return const DesktopAuthRejectedCallback(
      DesktopAuthRejectionReason.malformedUri,
    );
  }
  return classifyDesktopAuthCallback(uri);
}

/// Classifies an incoming deep link.
///
/// Fails closed in the order scheme → host → path → parameters, so a rejection
/// names the first thing that did not match rather than a generic "invalid".
/// The SDK's own observer checks none of this — it treats *any* URI carrying a
/// `code` parameter as an auth callback — which is why this app does the
/// routing itself.
DesktopAuthCallback classifyDesktopAuthCallback(Uri uri) {
  if (uri.scheme.toLowerCase() != _expectedScheme) {
    return const DesktopAuthRejectedCallback(
      DesktopAuthRejectionReason.unexpectedScheme,
    );
  }
  if (uri.host.toLowerCase() != _expectedHost) {
    return const DesktopAuthRejectedCallback(
      DesktopAuthRejectionReason.unexpectedHost,
    );
  }
  if (_normalizedPath(uri.path) != _expectedPath) {
    return const DesktopAuthRejectedCallback(
      DesktopAuthRejectionReason.unexpectedPath,
    );
  }

  final parameters = _authParameters(uri);
  if (parameters == null) {
    return const DesktopAuthRejectedCallback(
      DesktopAuthRejectionReason.malformedUri,
    );
  }

  // Errors are checked before auth material. A callback that reports a failure
  // and still carries a stale `code` must not be exchanged.
  final hasError = _errorParameters.any(parameters.containsKey);
  if (hasError) {
    return DesktopAuthErrorCallback(
      code: parameters['error_code'] ?? parameters['error'],
      description: parameters['error_description'],
    );
  }

  for (final key in _sessionParameters) {
    final token = parameters[key];
    if (token != null && token.isNotEmpty) {
      return DesktopAuthSessionCallback(uri: uri, token: '$key:$token');
    }
  }

  return const DesktopAuthRejectedCallback(
    DesktopAuthRejectionReason.missingAuthParameters,
  );
}

/// Reads parameters from the query and the fragment, or `null` if either is
/// undecodable.
///
/// PKCE puts the code in the query, the implicit flow puts the token in the
/// fragment, and GoTrue accepts both. Both are percent-decoded here, and both
/// can fail on input `Uri.parse` accepted: `?code=%` is a valid URI whose
/// query throws on decode. Reading half a callback would be worse than
/// refusing it, so an undecodable part fails the whole classification.
Map<String, String>? _authParameters(Uri uri) {
  try {
    final parameters = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      parameters.addAll(Uri.splitQueryString(uri.fragment));
    }
    return parameters;
  } on FormatException {
    return null;
  }
}

/// `neximmo://auth/callback` and `neximmo://auth/callback/` are the same
/// endpoint; anything deeper is not.
String _normalizedPath(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}
