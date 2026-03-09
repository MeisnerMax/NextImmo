import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SaveStatusTone { neutral, success, error, working, warning }

class SaveStatusIndicator extends StatelessWidget {
  const SaveStatusIndicator({
    super.key,
    required this.label,
    this.detail,
    this.tone = SaveStatusTone.neutral,
    this.compact = false,
  });

  final String label;
  final String? detail;
  final SaveStatusTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final palette = _palette(semantic);
    final icon = _iconForTone();
    final content =
        compact
            ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: palette.foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: palette.foreground),
                ),
              ],
            )
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: palette.foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: palette.foreground),
                      ),
                      if (detail != null && detail!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: palette.foreground.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(compact ? 999 : AppRadiusTokens.md),
        border: Border.all(color: palette.border),
      ),
      child: content,
    );
  }

  _SaveStatusPalette _palette(AppSemanticColors semantic) {
    switch (tone) {
      case SaveStatusTone.success:
        return _SaveStatusPalette(
          background: semantic.success.withValues(alpha: 0.12),
          foreground: semantic.success,
          border: semantic.success.withValues(alpha: 0.28),
        );
      case SaveStatusTone.error:
        return _SaveStatusPalette(
          background: semantic.error.withValues(alpha: 0.12),
          foreground: semantic.error,
          border: semantic.error.withValues(alpha: 0.28),
        );
      case SaveStatusTone.working:
        return _SaveStatusPalette(
          background: semantic.info.withValues(alpha: 0.12),
          foreground: semantic.info,
          border: semantic.info.withValues(alpha: 0.28),
        );
      case SaveStatusTone.warning:
        return _SaveStatusPalette(
          background: semantic.warning.withValues(alpha: 0.12),
          foreground: semantic.warning,
          border: semantic.warning.withValues(alpha: 0.28),
        );
      case SaveStatusTone.neutral:
        return _SaveStatusPalette(
          background: semantic.surfaceAlt,
          foreground: semantic.textSecondary,
          border: semantic.border,
        );
    }
  }

  IconData _iconForTone() {
    switch (tone) {
      case SaveStatusTone.success:
        return Icons.cloud_done_outlined;
      case SaveStatusTone.error:
        return Icons.error_outline;
      case SaveStatusTone.working:
        return Icons.sync;
      case SaveStatusTone.warning:
        return Icons.pending_outlined;
      case SaveStatusTone.neutral:
        return Icons.save_outlined;
    }
  }
}

class _SaveStatusPalette {
  const _SaveStatusPalette({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}
