import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'nx_card.dart';

/// The one KPI tile of the design system.
///
/// Exists because three screens had grown their own: the portfolio header,
/// the tenants overview, and the KPI widgets under `lib/ui/widgets/`. Each
/// drifted differently — different type sizes, different padding, one with an
/// optional subtitle that made its neighbours uneven.
///
/// The structure is fixed at label / value / caption. Every tile renders all
/// three slots, so a row of tiles is the same height whether or not a caption
/// has content. Two rules from the layout audit are enforced here rather than
/// left to call sites:
///
/// * **The value is never colored.** Status rides on [status] as a dot beside
///   the label. Action Cyan is the navigational accent; spending it on a
///   static figure devalues it, and several coloured figures side by side
///   read as competing alarms.
/// * **The value is never auto-scaled.** No `FittedBox` — fixed size and
///   ellipsis, so tiles cannot settle at different optical sizes.
class NxKpiTile extends StatelessWidget {
  const NxKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.status,
    this.trailing,
    this.delta,
  });

  final String label;
  final String value;

  /// Denominator or unit that makes the value interpretable on its own.
  /// Rendered as blank space when absent so sibling tiles stay aligned.
  final String? caption;

  /// Status color, rendered as a dot beside the label — never on the value.
  final Color? status;

  /// Right-aligned affordance on the label row — in practice an
  /// `InfoTooltip` explaining how a derived figure is calculated.
  final Widget? trailing;

  /// Change indicator below the caption. Carries [status] as its colour,
  /// because a delta genuinely *is* the status signal.
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    return NxCard(
      variant: NxCardVariant.kpi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (status != null) ...[
                _StatusDot(color: status!),
                const SizedBox(width: 6),
              ],
              Expanded(
                // Uppercased here, not by the caller: uppercase-with-tracking
                // is the system's marker for metadata, and leaving it to call
                // sites is how half the KPI bands ended up in sentence case.
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall
                ?.merge(context.dataMonoStyle)
                .copyWith(fontSize: 26, height: 1.2),
          ),
          const SizedBox(height: 2),
          Text(
            caption ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text(
              delta!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.merge(context.dataMonoStyle)
                  .copyWith(color: status ?? semantic.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Distributes KPI tiles evenly across the full available width.
///
/// Tiles used to be laid out at a fixed 190px in a `Wrap`, which left most of
/// a desktop row empty. A KPI band summarises the content below it and spans
/// it.
class NxKpiRow extends StatelessWidget {
  const NxKpiRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        // Never squeeze more than two tiles onto a tablet width — that is
        // what forced the value text to shrink in the first place.
        final maxColumns = total < 640 ? 1 : (total < 1100 ? 2 : children.length);
        final columns = children.length < maxColumns
            ? children.length
            : maxColumns;
        final width =
            (total - (columns - 1) * AppSpacing.component) / columns;

        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Carries the status signal that would otherwise be applied to the value.
/// Always paired with the label, so it is never colour-only signalling.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Loading placeholder that matches [NxKpiTile]'s three-slot skeleton, so the
/// loading state cannot drift out of alignment with the loaded state.
class NxKpiTileSkeleton extends StatelessWidget {
  const NxKpiTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholder = context.semanticColors.surfaceAlt;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholder,
        borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
      ),
    );

    return NxCard(
      variant: NxCardVariant.kpi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bar(120, 12),
          const SizedBox(height: AppSpacing.xs),
          bar(96, 26),
          const SizedBox(height: 2),
          bar(64, 14),
        ],
      ),
    );
  }
}
