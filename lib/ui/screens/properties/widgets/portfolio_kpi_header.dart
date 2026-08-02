import 'package:flutter/material.dart';

import '../../../../core/models/portfolio_analytics.dart';
import '../../../components/nx_kpi_tile.dart';
import '../../../theme/app_theme.dart';
import 'property_formatters.dart';

/// Portfolio-level KPI tiles shown above the properties list.
///
/// Structure and the label/value/caption rules live in [NxKpiTile]; this file
/// only decides which four figures the portfolio band shows and when each one
/// counts as a warning.
class PortfolioKpiHeader extends StatelessWidget {
  const PortfolioKpiHeader({super.key, required this.metrics});

  final PortfolioMetricsSnapshot metrics;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;

    return NxKpiRow(
      children: [
        NxKpiTile(
          label: 'PORTFOLIO-GESAMTWERT',
          value: formatCompactCurrency(metrics.totalValue),
          caption: 'AK ${formatCompactCurrency(metrics.totalAcquisitionCosts)}',
        ),
        NxKpiTile(
          label: 'Ø MIETRENDITE',
          value: formatPercentOneDecimal(metrics.netYield),
          caption: 'netto p. a.',
          status:
              metrics.netYield >= 0.04 ? semantic.success : semantic.warning,
        ),
        NxKpiTile(
          label: 'GESAMT-LEERSTAND',
          value: formatPercentOneDecimal(metrics.vacancyRate),
          caption: 'der Mietfläche',
          status:
              metrics.vacancyRate > 0.10 ? semantic.warning : semantic.success,
        ),
        NxKpiTile(
          label: 'PORTFOLIO-LTV',
          value: formatPercentOneDecimal(metrics.ltv),
          caption: formatCompactCurrency(metrics.totalLoanPrincipal),
          status:
              metrics.ltv < 0.60
                  ? semantic.success
                  : (metrics.ltv <= 0.75
                      ? semantic.warning
                      : semantic.error),
        ),
      ],
    );
  }
}

/// Loading placeholder matching the KPI tile layout (no full-page spinner).
class PortfolioKpiHeaderSkeleton extends StatelessWidget {
  const PortfolioKpiHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const NxKpiRow(
      children: [
        NxKpiTileSkeleton(),
        NxKpiTileSkeleton(),
        NxKpiTileSkeleton(),
        NxKpiTileSkeleton(),
      ],
    );
  }
}
