import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tone of an [NxNotice]. Deliberately smaller than the badge vocabulary:
/// an inline notice explains a condition of the *current view* — success
/// feedback goes through the action-feedback pattern (Foundation §12), not
/// through a lingering notice.
enum NxNoticeKind { info, warning, error }

/// The shared inline notice (Foundation §12/§18).
///
/// A passive, wrapped container for view-level conditions: truncated result
/// sets, read-only backends, partially evaluated data. It consolidates the
/// hand-rolled `_Notice`/`_TruncationNotice` warning boxes. Inline only —
/// this is not a toast and must never become one.
class NxNotice extends StatelessWidget {
  const NxNotice({
    super.key,
    required this.message,
    this.kind = NxNoticeKind.warning,
    this.title,
    this.icon,
    this.action,
  });

  final String message;
  final NxNoticeKind kind;
  final String? title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final tone = switch (kind) {
      NxNoticeKind.info => semantic.info,
      NxNoticeKind.warning => semantic.warning,
      NxNoticeKind.error => semantic.error,
    };
    final fallbackIcon = switch (kind) {
      NxNoticeKind.info => Icons.info_outline,
      NxNoticeKind.warning => Icons.warning_amber_outlined,
      NxNoticeKind.error => Icons.error_outline,
    };
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallbackIcon, size: 18, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
