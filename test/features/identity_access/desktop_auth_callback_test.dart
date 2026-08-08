import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/desktop_auth_callback.dart';

void main() {
  group('classifyDesktopAuthCallback', () {
    test('accepts the canonical PKCE callback', () {
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri?code=abc123',
      );

      expect(result, isA<DesktopAuthSessionCallback>());
      expect(
        (result as DesktopAuthSessionCallback).uri.queryParameters['code'],
        'abc123',
      );
    });

    test('accepts an implicit-flow token carried in the fragment', () {
      // The implicit flow never puts the token in the query. Reading only the
      // query would silently drop a callback GoTrue would have accepted.
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri#access_token=tok&token_type=bearer',
      );

      expect(result, isA<DesktopAuthSessionCallback>());
    });

    test('accepts the callback with a trailing slash', () {
      final result = classifyDesktopAuthCallbackString(
        'neximmo://auth/callback/?code=abc123',
      );

      expect(result, isA<DesktopAuthSessionCallback>());
    });

    test('is case insensitive about scheme and host', () {
      // Windows hands back whatever the mail client wrote. Scheme and host are
      // case insensitive per RFC 3986, so rejecting on case would drop valid
      // callbacks.
      final result = classifyDesktopAuthCallbackString(
        'NEXIMMO://AUTH/callback?code=abc123',
      );

      expect(result, isA<DesktopAuthSessionCallback>());
    });

    test('rejects a foreign scheme', () {
      final result = classifyDesktopAuthCallbackString(
        'https://evil.example.com/auth/callback?code=abc123',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.unexpectedScheme,
        ),
      );
    });

    test('rejects a foreign host on our own scheme', () {
      // Registering neximmo: makes every neximmo:// URI reachable from any web
      // page. The host is the first thing that separates our callback from one
      // an attacker composed.
      final result = classifyDesktopAuthCallbackString(
        'neximmo://evil/callback?code=abc123',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.unexpectedHost,
        ),
      );
    });

    test('rejects a foreign path on our own host', () {
      final result = classifyDesktopAuthCallbackString(
        'neximmo://auth/other?code=abc123',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.unexpectedPath,
        ),
      );
    });

    test('rejects a deeper path below the callback', () {
      final result = classifyDesktopAuthCallbackString(
        'neximmo://auth/callback/extra?code=abc123',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.unexpectedPath,
        ),
      );
    });

    test('rejects a callback without auth parameters', () {
      final result = classifyDesktopAuthCallbackString(desktopAuthCallbackUri);

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.missingAuthParameters,
        ),
      );
    });

    test('rejects a callback whose code is empty', () {
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri?code=',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.missingAuthParameters,
        ),
      );
    });

    test('rejects an unparseable URI instead of throwing', () {
      // Reached from a stream listener, so a FormatException here would become
      // an unhandled async error rather than a refused sign-in.
      final result = classifyDesktopAuthCallbackString(
        'neximmo://auth:notaport/callback?code=abc123',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.malformedUri,
        ),
      );
    });

    test('rejects a URI whose query cannot be decoded', () {
      // `Uri.parse` accepts this; the FormatException only surfaces when the
      // query is percent-decoded, which is one layer deeper than the parse.
      // A truncated UTF-8 sequence is what actually trips it -- a lone `%` is
      // tolerated and comes back verbatim.
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri?code=%E0%A4%A',
      );

      expect(
        result,
        isA<DesktopAuthRejectedCallback>().having(
          (rejection) => rejection.reason,
          'reason',
          DesktopAuthRejectionReason.malformedUri,
        ),
      );
    });

    test('reports a provider error as an error callback', () {
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri'
        '?error=access_denied&error_description=Email+link+is+invalid',
      );

      expect(
        result,
        isA<DesktopAuthErrorCallback>()
            .having((error) => error.code, 'code', 'access_denied')
            .having(
              (error) => error.description,
              'description',
              'Email link is invalid',
            ),
      );
    });

    test('prefers the error over a code delivered alongside it', () {
      // A callback that reports a failure and still carries a code must not be
      // exchanged; the code belongs to a request the provider refused.
      final result = classifyDesktopAuthCallbackString(
        '$desktopAuthCallbackUri?code=abc123&error=otp_expired',
      );

      expect(result, isA<DesktopAuthErrorCallback>());
    });

    test('distinguishes callbacks by their token', () {
      final first =
          classifyDesktopAuthCallbackString('$desktopAuthCallbackUri?code=one')
              as DesktopAuthSessionCallback;
      final second =
          classifyDesktopAuthCallbackString('$desktopAuthCallbackUri?code=two')
              as DesktopAuthSessionCallback;
      final repeat =
          classifyDesktopAuthCallbackString('$desktopAuthCallbackUri?code=one')
              as DesktopAuthSessionCallback;

      expect(first.token, isNot(second.token));
      expect(first.token, repeat.token);
    });

    test('does not confuse a code with an access token of the same value', () {
      final code =
          classifyDesktopAuthCallbackString('$desktopAuthCallbackUri?code=same')
              as DesktopAuthSessionCallback;
      final token =
          classifyDesktopAuthCallbackString(
                '$desktopAuthCallbackUri?access_token=same',
              )
              as DesktopAuthSessionCallback;

      expect(code.token, isNot(token.token));
    });
  });
}
