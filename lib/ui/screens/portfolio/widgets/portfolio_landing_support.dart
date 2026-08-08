import '../../../../core/models/asset_workbook.dart';
import '../../../../core/models/property.dart';

/// Shared models, filter helpers, projection math and formatters for the
/// portfolio landing (SCR-043) and its presentational widgets. Extracted from
/// the former `portfolios_screen.dart` monolith (BIG-004 split); behaviour is
/// unchanged — only the private members became public so the landing view and
/// the widgets in this folder can share them.
const String kPortfolioAllFilter = '__all__';

class PortfolioLandingFilters {
  const PortfolioLandingFilters({
    this.propertyId = kPortfolioAllFilter,
    this.region = kPortfolioAllFilter,
    this.propertyType = kPortfolioAllFilter,
    this.owner = kPortfolioAllFilter,
    this.timeframe = '12m',
  });

  final String propertyId;
  final String region;
  final String propertyType;
  final String owner;
  final String timeframe;

  PortfolioLandingFilters copyWith({
    String? propertyId,
    String? region,
    String? propertyType,
    String? owner,
    String? timeframe,
  }) {
    return PortfolioLandingFilters(
      propertyId: propertyId ?? this.propertyId,
      region: region ?? this.region,
      propertyType: propertyType ?? this.propertyType,
      owner: owner ?? this.owner,
      timeframe: timeframe ?? this.timeframe,
    );
  }
}

class PortfolioFilterOption {
  const PortfolioFilterOption(this.value, this.label);

  final String value;
  final String label;
}

class PortfolioChartDatum {
  const PortfolioChartDatum(this.label, this.value);

  final String label;
  final double value;
}

class PropertyEquityData {
  const PropertyEquityData({
    required this.propertyId,
    required this.propertyName,
    required this.marketValue,
    required this.debt,
    required this.equity,
    required this.equityRatio,
    required this.cashflow,
    required this.returnOnEquity,
  });

  final String propertyId;
  final String propertyName;
  final double marketValue;
  final double debt;
  final double equity;
  final double equityRatio;
  final double cashflow;
  final double returnOnEquity;
}

List<PortfolioRentalOverviewRow> filterPortfolioRows({
  required List<PortfolioRentalOverviewRow> rows,
  required Map<String, PropertyRecord> propertyById,
  required PortfolioLandingFilters filters,
}) {
  return rows.where((row) {
    if (filters.propertyId != kPortfolioAllFilter &&
        row.propertyId != filters.propertyId) {
      return false;
    }
    if (filters.propertyType != kPortfolioAllFilter &&
        row.propertyType != filters.propertyType) {
      return false;
    }
    if (filters.owner != kPortfolioAllFilter &&
        !row.ownerLabels.contains(filters.owner)) {
      return false;
    }
    final property = propertyById[row.propertyId];
    if (filters.region != kPortfolioAllFilter &&
        (property == null || regionForProperty(property) != filters.region)) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

PortfolioRentalOverview aggregatePortfolioOverview(
  List<PortfolioRentalOverviewRow> rows,
  PortfolioRentalOverview fallback,
) {
  if (rows.length == fallback.rows.length) {
    return fallback;
  }
  return PortfolioRentalOverview(
    rows: rows,
    assetsTotal: rows.length,
    assetsNotActive: 0,
    rentedUnits: rows.fold<int>(0, (sum, row) => sum + row.occupiedUnits),
    emptyUnits: rows.fold<int>(0, (sum, row) => sum + row.vacantUnits),
    annualRent: rows.fold<double>(0, (sum, row) => sum + row.annualRent),
    monthlyRentRunRate:
        rows.fold<double>(0, (sum, row) => sum + row.monthlyRentRunRate),
    annualOperatingCosts:
        rows.fold<double>(0, (sum, row) => sum + row.annualOperatingCosts),
    openDepositAmount:
        rows.fold<double>(0, (sum, row) => sum + row.openDepositAmount),
    serviceChargeBalance:
        rows.fold<double>(0, (sum, row) => sum + row.serviceChargeBalance),
    sourceAreasComplete:
        rows.fold<int>(0, (sum, row) => sum + row.sourceAreasComplete),
    sourceAreasTotal:
        rows.fold<int>(0, (sum, row) => sum + row.sourceAreasTotal),
  );
}

List<PortfolioFilterOption> sortedPortfolioFilterOptions(
  Iterable<String> values, {
  required String allLabel,
}) {
  final unique = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return <PortfolioFilterOption>[
    PortfolioFilterOption(kPortfolioAllFilter, allLabel),
    for (final value in unique) PortfolioFilterOption(value, value),
  ];
}

String safePortfolioFilterValue(String value, List<PortfolioFilterOption> options) {
  return options.any((option) => option.value == value)
      ? value
      : options.first.value;
}

String regionForProperty(PropertyRecord property) {
  final city = property.city.trim();
  if (city.isNotEmpty) {
    return city;
  }
  final country = property.country.trim();
  return country.isEmpty ? 'Ohne Region' : country;
}

int timeframeMonths(String value) {
  switch (value) {
    case '3m':
      return 3;
    case '6m':
      return 6;
    case '24m':
      return 24;
    case '36m':
      return 36;
    case '12m':
    default:
      return 12;
  }
}

String timeframeLabel(String value) {
  switch (value) {
    case '3m':
      return 'Letzte 3 Monate';
    case '6m':
      return 'Letzte 6 Monate';
    case '24m':
      return 'Letzte 24 Monate';
    case '36m':
      return 'Letzte 36 Monate';
    case '12m':
    default:
      return 'Letzte 12 Monate';
  }
}

List<double> trendSeries(double base, int months, double monthlyGrowth) {
  final points = _seriesPointCount(months);
  if (base <= 0) {
    return List<double>.filled(points, 0);
  }
  final start = base / (1 + (monthlyGrowth * points));
  return List<double>.generate(points, (index) {
    final seasonal = index.isEven ? 0.006 : -0.003;
    return start * (1 + (monthlyGrowth * index) + seasonal);
  }, growable: false);
}

List<double> boundedTrendSeries(double base, int months, double monthlyChange) {
  final points = _seriesPointCount(months);
  return List<double>.generate(points, (index) {
    final drift = (index - points + 1) * monthlyChange;
    return (base + drift).clamp(0.0, 1.0).toDouble();
  }, growable: false);
}

int _seriesPointCount(int months) {
  if (months <= 6) {
    return months;
  }
  return 8;
}

List<PortfolioChartDatum> chartDataFromTotals(
  Map<String, double> totals, {
  required int limit,
}) {
  final data = totals.entries
      .map((entry) => PortfolioChartDatum(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return data.take(limit).toList(growable: false);
}

String formatPortfolioCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return '$sign€ ${(absValue / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absValue >= 1000) {
    return '$sign€ ${(absValue / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absValue.toStringAsFixed(0)}';
}

String formatPortfolioPercent(double value) {
  return '${(value * 100).clamp(0, 999).toStringAsFixed(1)}%';
}
