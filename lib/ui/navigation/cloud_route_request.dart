import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_navigation.dart';

/// State-first cross-screen navigation to a cloud *surface* (Foundation §2:
/// "in-shell navigation sets `globalPageProvider` plus surface providers").
///
/// `globalPageProvider` alone cannot carry a surface or a property id — the
/// shell resets its route target to the bare page whenever the page changes.
/// Screens that need to land on a specific surface (the compliance finding →
/// `/property-documents/<id>`, DOCUMENTS-V2 §3) publish the full
/// [CloudRouteTarget] here; `AppScaffold.cloud` consumes it once, adopts it
/// as its active target and aligns the page provider. No screen builds its
/// own `Navigator` flow for this (the earlier `pushNamed` stacked a second
/// shell).
///
/// One-shot by design: the shell clears the request after adopting it, so a
/// later sidebar navigation is not dragged back to the surface.
final cloudRouteRequestProvider = StateProvider<CloudRouteTarget?>(
  (ref) => null,
);

void requestCloudRoute(WidgetRef ref, CloudRouteTarget target) {
  ref.read(cloudRouteRequestProvider.notifier).state = target;
}
