import 'package:flutter/material.dart';

import '../../../../core/models/analysis_result.dart';
import '../../../components/nx_card.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/info_tooltip.dart';

/// Metric grid of the overview screen as `NxCard` tiles (SCR-011 section 1).
/// Every tile navigates to its source module (the analysis screen) and every
/// derived metric carries an [InfoTooltip] with its formula.
class OverviewMetricGrid extends StatelessWidget {
  const OverviewMetricGrid({
    super.key,
    required this.metrics,
    required this.onOpenAnalysis,
  });

  final AnalysisMetrics metrics;
  final VoidCallback onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final neutralTone = Theme.of(context).colorScheme.onSurface;
    Color toneFor(double value) {
      if (value < 0) {
        return semantic.error;
      }
      if (value > 0) {
        return semantic.success;
      }
      return neutralTone;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final twoColumn =
            constraints.maxWidth >= 520 && constraints.maxWidth < 980;
        final metricWidth =
            compact
                ? constraints.maxWidth
                : twoColumn
                ? (constraints.maxWidth - AppSpacing.component) / 2
                : 220.0;
        final wideWidth =
            compact || twoColumn
                ? metricWidth
                : (metricWidth * 2) + AppSpacing.component;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _MetricTile(
              width: metricWidth,
              icon: Icons.payments_outlined,
              label: 'Monthly Cashflow',
              metricKey: 'monthly_cashflow',
              value: metrics.monthlyCashflowYear1.toStringAsFixed(2),
              tone: toneFor(metrics.monthlyCashflowYear1),
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: metricWidth,
              icon: Icons.bar_chart_outlined,
              label: 'NOI Y1',
              metricKey: 'noi',
              value: metrics.noiYear1.toStringAsFixed(2),
              tone: toneFor(metrics.noiYear1),
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: metricWidth,
              icon: Icons.percent_outlined,
              label: 'Cap Rate',
              metricKey: 'cap_rate',
              value: '${(metrics.capRate * 100).toStringAsFixed(2)}%',
              tone: neutralTone,
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: metricWidth,
              icon: Icons.currency_exchange_outlined,
              label: 'Cash on Cash',
              metricKey: 'cash_on_cash',
              value: '${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
              tone: toneFor(metrics.cashOnCash),
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: metricWidth,
              icon: Icons.show_chart_outlined,
              label: 'IRR',
              metricKey: 'irr',
              value:
                  metrics.irr == null
                      ? 'N/A'
                      : '${(metrics.irr! * 100).toStringAsFixed(2)}%',
              tone: metrics.irr == null ? neutralTone : toneFor(metrics.irr!),
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: metricWidth,
              icon: Icons.trending_up_outlined,
              label: 'ROI',
              metricKey: 'roi',
              value: '${(metrics.roi * 100).toStringAsFixed(2)}%',
              tone: toneFor(metrics.roi),
              onTap: onOpenAnalysis,
            ),
            _MetricTile(
              width: wideWidth,
              icon: Icons.balance_outlined,
              label: 'DSCR',
              metricKey: 'dscr',
              value: metrics.dscr?.toStringAsFixed(2) ?? 'N/A',
              subtitle: metrics.dscr == null ? null : 'Ratio',
              tone: neutralTone,
              onTap: onOpenAnalysis,
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.metricKey,
    required this.value,
    required this.tone,
    required this.onTap,
    this.subtitle,
  });

  final double width;
  final IconData icon;
  final String label;
  final String metricKey;
  final String value;
  final Color tone;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return SizedBox(
      width: width,
      child: NxCard(
        variant: NxCardVariant.interactive,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppIconTokens.sm, color: semantic.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.strings.text(label).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: semantic.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                InfoTooltip(metricKey: metricKey, size: 14),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.headlineSmall?.merge(
                            context.tabularNumericStyle.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                    ),
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
