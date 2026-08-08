import 'package:flutter/material.dart';

import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_section_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'dashboard_view_model.dart';

/// "Aktuelle Hinweise" — the attention-needed list (left column on desktop).
/// Every row navigates directly to its source via [onOpenTarget]; there is no
/// generic list detour. Severity is shown by both an accent bar and a labelled
/// [NxStatusBadge] (never color alone).
class DashboardAttentionList extends StatelessWidget {
  const DashboardAttentionList({
    super.key,
    required this.items,
    required this.onOpenTarget,
  });

  final List<DashboardActionItem> items;
  final ValueChanged<DashboardNavigationTarget> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NxSectionHeader(
          title: 'Aktuelle Hinweise',
          description: 'Auffälligkeiten und Fälligkeiten, nach Rolle priorisiert.',
        ),
        const SizedBox(height: AppSpacing.component),
        if (items.isEmpty)
          const NxEmptyState(
            title: 'Keine kritischen offenen Punkte',
            description:
                'Aktuell gibt es keine offenen Dashboard-Aktionen. Neue Hinweise '
                'erscheinen hier automatisch.',
            icon: Icons.check_circle_outline,
          )
        else
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.component),
            _AttentionRow(
              key: ValueKey<String>('dashboard-action-$index'),
              item: items[index],
              onTap: () => onOpenTarget(items[index].target),
            ),
          ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  final DashboardActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = dashboardSeverityColor(context, item.severity);
    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        NxStatusBadge(
                          label: dashboardSeverityLabel(item.severity),
                          kind: dashboardSeverityBadgeKind(item.severity),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.semanticColors.textSecondary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          item.nextStep,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
