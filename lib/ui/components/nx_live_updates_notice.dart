import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'nx_status_badge.dart';

/// Passive marker for a Realtime subscription that stopped delivering
/// (Foundation §13; proven in REALTIME-DEGRADED-UI-01).
///
/// It informs and nothing more: no dialog, no barrier, no sign-out. The
/// repository stays canonical, so everything on the page keeps working —
/// only the *live* part is degraded, and saying so beats presenting a list
/// that quietly stopped moving. Screens show it below the page header while
/// their controller reports degradation and drop it on the next reconcile.
class NxLiveUpdatesNotice extends StatelessWidget {
  const NxLiveUpdatesNotice({super.key, this.message});

  /// Overrides the default copy. Kept parameterized so the reference slice
  /// keeps its established English copy until that surface is rebuilt
  /// (Foundation §19).
  final String? message;

  static const String _defaultMessage =
      'Live-Updates sind vorübergehend unterbrochen. Die Seite bleibt '
      'nutzbar und holt Änderungen automatisch nach.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
      ),
      child: Row(
        children: [
          const NxStatusBadge(label: 'Paused', kind: NxBadgeKind.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message ?? _defaultMessage,
              // Bounded on purpose: the notice sits above a flexible content
              // area, and an unbounded sentence pushes that area past the
              // viewport on a narrow phone.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
