import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../features/documents_compliance/domain/document_dto.dart';

/// The one way document content is reached (DOCUMENTS-V2 §6.7 / §20.4,
/// binding security decision).
///
/// A signed URL is minted **immediately before** the open, handed straight to
/// the platform launcher, and then forgotten: it is never rendered, never put
/// on the clipboard, never kept in widget or controller state, never logged —
/// not in telemetry, not in an error message. A failed or expired URL is not
/// retried; the next click mints a fresh one.
///
/// The launcher is a provider so widget tests can capture the URI without a
/// platform channel; production binds `url_launcher` (web: new tab, desktop:
/// system handler).
typedef DocumentUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternally(Uri uri) {
  return launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}

final documentUrlLauncherProvider = Provider<DocumentUrlLauncher>(
  (ref) => _launchExternally,
);

/// Copy shown when the platform refused to open the URL. Deliberately carries
/// nothing of the URL itself.
const String documentOpenFailedMessage =
    'Der Inhalt konnte nicht geöffnet werden.';

/// Opens [signedUrl] through [launcher]. Returns false when the launcher
/// refused; the caller reports [documentOpenFailedMessage] and nothing else.
Future<bool> openSignedDocumentUrl(
  SignedDocumentUrl signedUrl,
  DocumentUrlLauncher launcher,
) async {
  final uri = Uri.tryParse(signedUrl.url);
  if (uri == null) {
    return false;
  }
  try {
    return await launcher(uri);
  } on Object {
    // The exception text may echo the URL; it stays out of state and logs.
    return false;
  }
}

/// Reports an open failure through the scaffold messenger, URL-free.
void reportDocumentOpenFailure(BuildContext context) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(const SnackBar(content: Text(documentOpenFailedMessage)));
}
