import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/desktop_auth_callback.dart';
import 'package:neximmo_app/features/identity_access/data/desktop_auth_deep_link_observer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

void main() {
  late StreamController<Uri> links;
  late List<Uri> exchanged;
  late List<DesktopAuthCallbackEvent> events;
  late Object? exchangeError;

  DesktopAuthDeepLinkObserver build() {
    return DesktopAuthDeepLinkObserver(
      links: links.stream,
      exchangeSession: (uri) async {
        exchanged.add(uri);
        final error = exchangeError;
        if (error != null) {
          throw error;
        }
      },
      onEvent: events.add,
    );
  }

  setUp(() {
    links = StreamController<Uri>();
    exchanged = <Uri>[];
    events = <DesktopAuthCallbackEvent>[];
    exchangeError = null;
  });

  tearDown(() {
    // Deliberately not awaited. Most cases here drive `handle` directly and
    // never subscribe, and closing a single-subscription controller that was
    // never listened to does not complete until someone does.
    unawaited(links.close());
  });

  test('exchanges a valid callback exactly once', () async {
    final observer = build();

    await observer.handle(Uri.parse('$desktopAuthCallbackUri?code=abc123'));

    expect(exchanged, hasLength(1));
    expect(exchanged.single.queryParameters['code'], 'abc123');
    expect(events.single, isA<DesktopAuthCallbackAccepted>());
  });

  test('ignores a repeated delivery of the same callback', () async {
    // Windows can deliver the same click twice -- once on the command line of
    // the cold-started process and once as a forwarded WM_COPYDATA message.
    // The second exchange would fail against a consumed PKCE code and surface
    // as a sign-in error to a user who is already signed in.
    final observer = build();
    final uri = Uri.parse('$desktopAuthCallbackUri?code=abc123');

    await observer.handle(uri);
    await observer.handle(uri);

    expect(exchanged, hasLength(1));
    expect(events.last, isA<DesktopAuthCallbackDuplicate>());
  });

  test('deduplicates concurrent deliveries of the same callback', () async {
    // Both deliveries can be in flight before either exchange completes, so
    // recording the token only after a successful exchange would let both
    // through.
    final observer = build();
    final uri = Uri.parse('$desktopAuthCallbackUri?code=abc123');

    await Future.wait(<Future<void>>[observer.handle(uri), observer.handle(uri)]);

    expect(exchanged, hasLength(1));
  });

  test('still exchanges a genuinely different callback', () async {
    final observer = build();

    await observer.handle(Uri.parse('$desktopAuthCallbackUri?code=first'));
    await observer.handle(Uri.parse('$desktopAuthCallbackUri?code=second'));

    expect(exchanged, hasLength(2));
  });

  test('never exchanges a callback from a foreign scheme', () async {
    final observer = build();

    await observer.handle(
      Uri.parse('https://evil.example.com/auth/callback?code=abc123'),
    );

    expect(exchanged, isEmpty);
    expect(
      events.single,
      isA<DesktopAuthCallbackIgnored>().having(
        (event) => event.reason,
        'reason',
        DesktopAuthRejectionReason.unexpectedScheme,
      ),
    );
  });

  test('never exchanges a callback from a foreign host or path', () async {
    final observer = build();

    await observer.handle(Uri.parse('neximmo://evil/callback?code=abc123'));
    await observer.handle(Uri.parse('neximmo://auth/other?code=abc123'));

    expect(exchanged, isEmpty);
    expect(events, everyElement(isA<DesktopAuthCallbackIgnored>()));
  });

  test('never exchanges a callback that carries no auth material', () async {
    final observer = build();

    await observer.handle(Uri.parse(desktopAuthCallbackUri));

    expect(exchanged, isEmpty);
  });

  test('reports a provider error without attempting an exchange', () async {
    final observer = build();

    await observer.handle(
      Uri.parse('$desktopAuthCallbackUri?error=access_denied&'
          'error_description=Email+link+is+invalid'),
    );

    expect(exchanged, isEmpty);
    expect(
      events.single,
      isA<DesktopAuthCallbackFailed>().having(
        (event) => event.message,
        'message',
        'Email link is invalid',
      ),
    );
  });

  test('reports a failed exchange instead of throwing', () async {
    exchangeError = const AuthException('code verifier missing');
    final observer = build();

    await observer.handle(Uri.parse('$desktopAuthCallbackUri?code=abc123'));

    expect(
      events.single,
      isA<DesktopAuthCallbackFailed>().having(
        (event) => event.message,
        'message',
        'code verifier missing',
      ),
    );
  });

  test('survives a non-auth error from the exchange', () async {
    exchangeError = StateError('socket closed');
    final observer = build();

    await observer.handle(Uri.parse('$desktopAuthCallbackUri?code=abc123'));

    expect(events.single, isA<DesktopAuthCallbackFailed>());
  });

  test('processes links arriving on the stream', () async {
    // Covers the wiring itself: cold start and warm delivery both reach the app
    // as stream events, so a subscription that never fires would break both.
    final observer = build();
    observer.start();

    links.add(Uri.parse('$desktopAuthCallbackUri?code=abc123'));
    await pumpEventQueue();

    expect(exchanged, hasLength(1));
    await observer.dispose();
  });

  test('stops processing after dispose', () async {
    final observer = build();
    observer.start();
    await observer.dispose();

    links.add(Uri.parse('$desktopAuthCallbackUri?code=abc123'));
    await pumpEventQueue();

    expect(exchanged, isEmpty);
  });

  test('survives an error on the link stream', () async {
    final observer = build();
    observer.start();

    links.addError(StateError('platform channel died'));
    links.add(Uri.parse('$desktopAuthCallbackUri?code=abc123'));
    await pumpEventQueue();

    expect(exchanged, hasLength(1));
    await observer.dispose();
  });
}
