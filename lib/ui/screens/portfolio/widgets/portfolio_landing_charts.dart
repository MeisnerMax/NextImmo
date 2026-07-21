import 'package:flutter/material.dart';

import '../../../../core/models/asset_workbook.dart';
import '../../../../core/models/property.dart';
import '../../../theme/app_theme.dart';
import 'portfolio_landing_support.dart';

/// Chart panels and the equity ranking card for the portfolio landing
/// (SCR-043), extracted verbatim from the former `portfolios_screen.dart`
/// monolith (BIG-004 split). These render with `CustomPaint` /
/// `LinearProgressIndicator` (not fl_chart). Behaviour is unchanged; the only
/// edit is replacing raw `TextStyle` literals in the ranking card with
/// `textTheme`-derived styles (DEBT-TOKEN-001).
class PortfolioManagementCharts extends StatelessWidget {
  const PortfolioManagementCharts({
    super.key,
    required this.overview,
    required this.properties,
    required this.timeframe,
    required this.marketValue,
    required this.bookValue,
  });

  final PortfolioRentalOverview overview;
  final List<PropertyRecord> properties;
  final String timeframe;
  final double marketValue;
  final double bookValue;

  @override
  Widget build(BuildContext context) {
    final months = timeframeMonths(timeframe);
    final label = timeframeLabel(timeframe);
    final propertyById = {
      for (final property in properties) property.id: property,
    };
    final noiByProperty = [...overview.rows]
      ..sort((a, b) => b.netAnnualAfterCosts.compareTo(a.netAnnualAfterCosts));
    final locationTotals = <String, double>{};
    final typeTotals = <String, double>{};
    for (final row in overview.rows) {
      final property = propertyById[row.propertyId];
      final region = property == null ? 'Ohne Region' : regionForProperty(property);
      locationTotals[region] =
          (locationTotals[region] ?? 0) + row.netAnnualAfterCosts;
      typeTotals[row.propertyType] =
          (typeTotals[row.propertyType] ?? 0) + row.annualRent;
    }
    final budgetData = <PortfolioChartDatum>[
      PortfolioChartDatum('Plan', overview.annualOperatingCosts * 1.08),
      PortfolioChartDatum('Ist', overview.annualOperatingCosts),
      PortfolioChartDatum(
        'Delta',
        (overview.annualOperatingCosts * 1.08) -
            overview.annualOperatingCosts,
      ),
    ];
    final vacancyRate =
        overview.rentedUnits + overview.emptyUnits == 0
            ? 0.0
            : overview.emptyUnits / (overview.rentedUnits + overview.emptyUnits);

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth =
            constraints.maxWidth < 760
                ? constraints.maxWidth
                : (constraints.maxWidth - AppSpacing.component) / 2;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Wertentwicklung',
              subtitle: '$label, abgeleitet aus NOI und Cap Rate',
              child: PortfolioTrendChart(
                values: trendSeries(marketValue, months, 0.018),
                formatter: formatPortfolioCurrency,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Mietentwicklung',
              subtitle: '$label, aktuelle Run Rate fortgeschrieben',
              child: PortfolioTrendChart(
                values: trendSeries(
                  overview.monthlyRentRunRate,
                  months,
                  0.011,
                ),
                formatter: formatPortfolioCurrency,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Leerstandsentwicklung',
              subtitle: '$label, Quote nach aktuellem Einheitenstand',
              child: PortfolioTrendChart(
                values: boundedTrendSeries(vacancyRate, months, 0.006),
                formatter: formatPortfolioPercent,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Objektvergleich',
              subtitle: 'NOI je Objekt',
              child: PortfolioBarList(
                data: noiByProperty
                    .take(6)
                    .map(
                      (row) => PortfolioChartDatum(
                        row.propertyName,
                        row.netAnnualAfterCosts,
                      ),
                    )
                    .toList(growable: false),
                formatter: formatPortfolioCurrency,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Standortvergleich',
              subtitle: 'NOI nach Region',
              child: PortfolioBarList(
                data: chartDataFromTotals(locationTotals, limit: 6),
                formatter: formatPortfolioCurrency,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Budget vs. Ist',
              subtitle: 'Operative Kosten als Management-Signal',
              child: PortfolioBarList(data: budgetData, formatter: formatPortfolioCurrency),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Mietmix nach Typ',
              subtitle: 'Jahresmiete je Objektart',
              child: PortfolioBarList(
                data: chartDataFromTotals(typeTotals, limit: 6),
                formatter: formatPortfolioCurrency,
              ),
            ),
            PortfolioChartPanel(
              width: panelWidth,
              title: 'Wertbasis',
              subtitle: 'Marktwert gegen Flächen-Buchwert',
              child: PortfolioBarList(
                data: <PortfolioChartDatum>[
                  PortfolioChartDatum('Marktwert', marketValue),
                  PortfolioChartDatum('Buchwert', bookValue),
                ],
                formatter: formatPortfolioCurrency,
              ),
            ),
          ],
        );
      },
    );
  }
}

class PortfolioChartPanel extends StatelessWidget {
  const PortfolioChartPanel({
    super.key,
    required this.width,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final double width;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class PortfolioTrendChart extends StatelessWidget {
  const PortfolioTrendChart({
    super.key,
    required this.values,
    required this.formatter,
  });

  final List<double> values;
  final String Function(double value) formatter;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = values.isEmpty ? const <double>[0] : values;
    final first = nonEmpty.first;
    final last = nonEmpty.last;
    return SizedBox(
      height: 172,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _TrendChartPainter(
                values: nonEmpty,
                lineColor: Theme.of(context).colorScheme.primary,
                fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                gridColor: context.semanticColors.border,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatter(first),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                formatter(last),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue == 0 ? 1.0 : maxValue - minValue;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * (i / (values.length - 1));
      final y = size.height - ((values[i] - minValue) / range * size.height);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) {
      return;
    }
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(points.last, 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class PortfolioBarList extends StatelessWidget {
  const PortfolioBarList({
    super.key,
    required this.data,
    required this.formatter,
  });

  final List<PortfolioChartDatum> data;
  final String Function(double value) formatter;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 172,
        child: Center(
          child: Text(
            'Keine Daten',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final maxValue = data.fold<double>(
      0,
      (max, item) => item.value.abs() > max ? item.value.abs() : max,
    );
    final denominator = maxValue == 0 ? 1.0 : maxValue;
    return SizedBox(
      height: 172,
      child: Column(
        children: [
          for (final item in data) ...[
            Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value:
                          (item.value.abs() / denominator).clamp(0.0, 1.0).toDouble(),
                      minHeight: 10,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      color:
                          item.value < 0
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: Text(
                    formatter(item.value),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class EquityRankingCard extends StatefulWidget {
  const EquityRankingCard({super.key, required this.data});

  final List<PropertyEquityData> data;

  @override
  State<EquityRankingCard> createState() => _EquityRankingCardState();
}

class _EquityRankingCardState extends State<EquityRankingCard> {
  String _selectedMetric = 'equity'; // 'equity', 'debt', 'ratio'

  @override
  Widget build(BuildContext context) {
    final list = List<PropertyEquityData>.from(widget.data);
    if (_selectedMetric == 'equity') {
      list.sort((a, b) => b.equity.compareTo(a.equity));
    } else if (_selectedMetric == 'debt') {
      list.sort((a, b) => b.debt.compareTo(a.debt));
    } else if (_selectedMetric == 'ratio') {
      list.sort((a, b) => b.equityRatio.compareTo(a.equityRatio));
    }

    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kapitalbindung (Rangliste)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedMetric,
                underline: const SizedBox(),
                icon: const Icon(Icons.sort_outlined),
                items: const [
                  DropdownMenuItem(value: 'equity', child: Text('Eigenkapital')),
                  DropdownMenuItem(value: 'debt', child: Text('Restschulden')),
                  DropdownMenuItem(value: 'ratio', child: Text('Eigenkapitalquote')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMetric = val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(child: Text('Keine Objektdaten vorhanden.')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length.clamp(0, 5),
              itemBuilder: (context, index) {
                final item = list[index];
                double value = 0.0;
                String formatted = '';
                if (_selectedMetric == 'equity') {
                  value = item.equity;
                  formatted = formatPortfolioCurrency(value);
                } else if (_selectedMetric == 'debt') {
                  value = item.debt;
                  formatted = formatPortfolioCurrency(value);
                } else if (_selectedMetric == 'ratio') {
                  value = item.equityRatio;
                  formatted = formatPortfolioPercent(value);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.propertyName,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedMetric == 'equity'
                                  ? 'Marktwert: ${formatPortfolioCurrency(item.marketValue)}'
                                  : _selectedMetric == 'debt'
                                      ? 'Eigenkapital: ${formatPortfolioCurrency(item.equity)}'
                                      : 'Restschuld: ${formatPortfolioCurrency(item.debt)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatted,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ).merge(context.tabularNumericStyle),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
