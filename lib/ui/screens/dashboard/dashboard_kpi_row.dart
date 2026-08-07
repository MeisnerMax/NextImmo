import 'package:flutter/material.dart';

import '../../components/nx_card.dart';
import '../../theme/app_theme.dart';
import 'dashboard_view_model.dart';

/// Headline portfolio KPIs as `NxCard` tiles (SCR-004). Wraps to three columns
/// on desktop, two on tablet, one on phone — no fixed widths that break on
/// small viewports.
class DashboardKpiRow extends StatelessWidget {
  const DashboardKpiRow({super.key, required this.overview});

  final DashboardOverviewData overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final neutralTone = theme.colorScheme.onSurface;

    final rentableUnits = overview.occupiedUnits + overview.vacantUnits;
    final occupancyRate =
        rentableUnits == 0 ? 0.0 : overview.occupiedUnits / rentableUnits;
    final costRatio = overview.annualRent == 0
        ? 0.0
        : overview.annualOperatingCosts / overview.annualRent;

    final tiles = <_DashboardKpiSpec>[
      _DashboardKpiSpec(
        label: 'JAHRESMIETE',
        value: formatDashboardCurrency(overview.annualRent),
        tone: neutralTone,
      ),
      _DashboardKpiSpec(
        label: 'MONATSLAUF',
        value: formatDashboardCurrency(overview.monthlyRentRunRate),
        tone: semantic.success,
        badge: Icons.trending_up,
      ),
      _DashboardKpiSpec(
        label: 'VERMIETUNGSQUOTE',
        value: formatDashboardPercent(occupancyRate),
        tone: neutralTone,
      ),
      _DashboardKpiSpec(
        label: 'BK / KOSTEN P.A.',
        value: formatDashboardCurrency(overview.annualOperatingCosts),
        tone: costRatio > 0.35 ? semantic.warning : neutralTone,
      ),
      _DashboardKpiSpec(
        label: 'OFFENE KAUTIONEN',
        value: formatDashboardCurrency(overview.openDepositAmount),
        tone: overview.openDepositAmount > 0
            ? semantic.warning
            : semantic.success,
      ),
      _DashboardKpiSpec(
        label: 'OFFENE AKTIONEN',
        value: '${overview.criticalActions}',
        tone: overview.criticalActions > 0 ? semantic.error : semantic.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600
            ? 1
            : (constraints.maxWidth < 1080 ? 2 : 3);
        const gap = AppSpacing.component;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _DashboardKpiTile(spec: tile),
              ),
          ],
        );
      },
    );
  }
}

class _DashboardKpiSpec {
  const _DashboardKpiSpec({
    required this.label,
    required this.value,
    required this.tone,
    this.badge,
  });

  final String label;
  final String value;
  final Color tone;
  final IconData? badge;
}

class _DashboardKpiTile extends StatelessWidget {
  const _DashboardKpiTile({required this.spec});

  final _DashboardKpiSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      variant: NxCardVariant.kpi,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              spec.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.semanticColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      spec.value,
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall
                          ?.merge(context.tabularNumericStyle)
                          .copyWith(
                            color: spec.tone,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                if (spec.badge != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: spec.tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                    ),
                    child: Icon(spec.badge, color: spec.tone, size: 16),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
