import 'package:flutter/material.dart';

import '../../../../core/models/portfolio_analytics.dart';
import '../../../components/nx_card.dart';
import '../../../theme/app_theme.dart';
import 'property_formatters.dart';

/// Portfolio-level KPI tiles shown above the properties list.
class PortfolioKpiHeader extends StatelessWidget {
  const PortfolioKpiHeader({super.key, required this.metrics});

  final PortfolioMetricsSnapshot metrics;

  @override
  Widget build(BuildContext context) {
    final ltvColor = metrics.ltv < 0.60
        ? context.semanticColors.success
        : (metrics.ltv <= 0.75
            ? context.semanticColors.warning
            : context.semanticColors.error);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth < 640
            ? constraints.maxWidth
            : (constraints.maxWidth - 3 * AppSpacing.component) / 4;

        final cardList = [
          _KpiCardSpec(
            title: 'PORTFOLIO-GESAMTWERT',
            value:
                '${formatCompactCurrency(metrics.totalValue)} / ${formatCompactCurrency(metrics.totalAcquisitionCosts)}',
            valueStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          _KpiCardSpec(
            title: 'Ø MIETRENDITE',
            value: formatPercentOneDecimal(metrics.netYield),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          _KpiCardSpec(
            title: 'GESAMT-LEERSTAND',
            value: formatPercentOneDecimal(metrics.vacancyRate),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: metrics.vacancyRate > 0.10
                      ? context.semanticColors.warning
                      : context.semanticColors.success,
                ),
          ),
          _KpiCardSpec(
            title: 'PORTFOLIO-LTV',
            value: formatPercentOneDecimal(metrics.ltv),
            valueStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ltvColor,
                ),
          ),
        ];

        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: cardList
              .map(
                (spec) => SizedBox(
                  width: width,
                  child: NxCard(
                    variant: NxCardVariant.kpi,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.title,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: context.semanticColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            spec.value,
                            style: (spec.valueStyle ??
                                    Theme.of(context).textTheme.titleLarge ??
                                    const TextStyle())
                                .merge(context.tabularNumericStyle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

/// Loading placeholder matching the KPI tile layout (no full-page spinner).
class PortfolioKpiHeaderSkeleton extends StatelessWidget {
  const PortfolioKpiHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth < 640
            ? constraints.maxWidth
            : (constraints.maxWidth - 3 * AppSpacing.component) / 4;
        Widget bar(double barWidth, double height) => Container(
              width: barWidth,
              height: height,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
              ),
            );
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: List.generate(
            4,
            (_) => SizedBox(
              width: width,
              child: NxCard(
                variant: NxCardVariant.kpi,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(120, 10),
                    const SizedBox(height: 12),
                    bar(80, 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KpiCardSpec {
  const _KpiCardSpec({
    required this.title,
    required this.value,
    this.valueStyle,
  });

  final String title;
  final String value;
  final TextStyle? valueStyle;
}
