import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/desktop_auth_callback.dart';

/// What the observer did with one incoming link. Emitted for diagnostics and
/// asserted by the tests; nothing navigates off it. The session itself reaches
/// the UI the way every other session does — through `onAuthStateChange`, which
/// the existing security gate already watches.
sealed class DesktopAuthCallbackEvent {
  const DesktopAuthCallbackEvent();
}

final class DesktopAuthCallbackAccepted extends DesktopAuthCallbackEvent {
  const DesktopAuthCallbackAccepted();
}

final class DesktopAuthCallbackDuplicate extends DesktopAuthCallbackEvent {
  const DesktopAuthCallbackDuplicate();
}

final class DesktopAuthCallbackIgnored extends DesktopAuthCallbackEvent {
  const DesktopAuthCallbackIgnored(this.reason);

  final DesktopAuthRejectionReason reason;
}

final class DesktopAuthCallbackFailed extends DesktopAuthCallbackEvent {
  const DesktopAuthCallbackFailed(this.message);

  final String? message;
}

/// Turns desktop deep links into Supabase sessions.
///
/// `supabase_flutter` ships an observer of its own, but it forwards *any* URI
/// carrying a `code` parameter to the session exchange without checking scheme,
/// host or path. Once the app registers `neximmo:` with Windows, any web page
/// can produce such a URI, so this app disables that observer on desktop
/// (`detectSessionInUri: false`) and validates first.
///
/// On Windows both delivery paths end up in the same stream: `app_links` emits
/// the command-line URI when the app was cold-started by the protocol handler,
/// and emits `WM_COPYDATA` URIs that a second launch forwarded to the running
/// instance. That is why one subscription covers warm and cold start, and also
/// why deduplication is required — the two paths can describe the same click.
class DesktopAuthDeepLinkObserver {
  DesktopAuthDeepLinkObserver({
    required Stream<Uri> links,
    required Future<void> Function(Uri uri) exchangeSession,
    void Function(DesktopAuthCallbackEvent event)? onEvent,
  }) : _links = links,
       _exchangeSession = exchangeSession,
       _onEvent = onEvent;

  /// Wires the observer against the real client. Kept separate from the
  /// constructor so the logic above stays testable without a Supabase client or
  /// a platform channel.
  factory DesktopAuthDeepLinkObserver.forClient(
    SupabaseClient client, {
    void Function(DesktopAuthCallbackEvent event)? onEvent,
  }) {
    return DesktopAuthDeepLinkObserver(
      links: AppLinks().uriLinkStream,
      exchangeSession: (uri) => client.auth.getSessionFromUrl(uri),
      onEvent: onEvent,
    );
  }

  final Stream<Uri> _links;
  final Future<void> Function(Uri uri) _exchangeSession;
  final void Function(DesktopAuthCallbackEvent event)? _onEvent;

  /// Credentials already redeemed, newest last. Bounded because the scheme is
  /// open to the world: a hostile page could fire an unlimited number of
  /// distinct links, and an unbounded set would grow with them. The cap is far
  /// above the handful of callbacks a real sign-in produces, which is all the
  /// deduplication has to cover.
  final _redeemed = <String>[];
  static const _redeemedLimit = 32;

  StreamSubscription<Uri>? _subscription;

  void start() {
    _subscription ??= _links.listen(
      (uri) => unawaited(handle(uri)),
      // A broken link stream must not take the app down. Sign-in stays
      // reachable through the existing web flow.
      onError: (Object _, StackTrace __) {},
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Processes one link. Public so tests can drive it directly instead of
  /// racing a stream.
  Future<void> handle(Uri uri) async {
    final callback = classifyDesktopAuthCallback(uri);
    switch (callback) {
      case DesktopAuthRejectedCallback(:final reason):
        _emit(DesktopAuthCallbackIgnored(reason));
      case DesktopAuthErrorCallback(:final description, :final code):
        _emit(DesktopAuthCallbackFailed(description ?? code));
      case DesktopAuthSessionCallback(:final token, uri: final callbackUri):
        if (_redeemed.contains(token)) {
          _emit(const DesktopAuthCallbackDuplicate());
          return;
        }
        // Recorded before the exchange, not after: the duplicate we are
        // guarding against is the second delivery of the same click, which can
        // arrive while the first exchange is still in flight.
        _redeemed.add(token);
        if (_redeemed.length > _redeemedLimit) {
          _redeemed.removeAt(0);
        }
        try {
          await _exchangeSession(callbackUri);
          _emit(const DesktopAuthCallbackAccepted());
        } on AuthException catch (error) {
          _emit(DesktopAuthCallbackFailed(error.message));
        } catch (_) {
          _emit(const DesktopAuthCallbackFailed(null));
        }
    }
  }

  void _emit(DesktopAuthCallbackEvent event) => _onEvent?.call(event);
}
