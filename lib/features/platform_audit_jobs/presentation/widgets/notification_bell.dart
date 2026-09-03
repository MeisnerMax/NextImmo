import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../ui/state/app_state.dart';
import '../../../reference_slice/application/reference_slice_controller.dart';
import '../../application/notification_inbox_controller.dart';
import '../notification_inbox_screen.dart';

/// The CloudTopBar bell (A14): the most important entry into the inbox — an
/// inbox one has to seek out is never read. Fed from the same `unreadOnly`
/// feed as the inbox itself (one shared controller instance), so badge and
/// Ungelesen tab cannot diverge. **There is no count RPC**: the badge shows
/// the exact number up to one page and "50+" beyond it — never an invented
/// total; the tooltip names that semantics.
///
/// Rendered only for sessions that can reach the page at all: a workspace at
/// AAL2 whose membership holds `notification.read` (Foundation §3 — the
/// sidebar hides the destination the same way).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(referenceSliceControllerProvider);
    final scope = notificationInboxScopeOf(reference);
    if (scope == null || !scope.canMutate || !scope.canRead) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(notificationInboxControllerProvider(scope));
    final count = state.unreadBadgeCount;
    final label = state.unreadBadgeLabel;
    final semantics = state.unreadBadgeCapped
        ? 'mehr als $count ungelesene Mitteilungen'
        : '$count ungelesene Mitteilungen';

    return Semantics(
      label: semantics,
      button: true,
      child: Tooltip(
        message: state.unreadBadgeCapped
            ? 'Mitteilungen — mehr als $count ungelesen'
            : 'Mitteilungen — $count ungelesen',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              key: const Key('cloud-notification-bell'),
              onPressed: () {
                // State-first in-shell navigation (Foundation §2).
                ref.read(globalPageProvider.notifier).state =
                    GlobalPage.notifications;
              },
              icon: const Icon(Icons.notifications_none),
            ),
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  child: Container(
                    key: const Key('cloud-notification-bell-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
