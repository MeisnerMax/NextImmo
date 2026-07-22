/// Shared display formatting for the properties list (cards + table).
String formatCompactCurrency(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} Mio. €';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)}k €';
  }
  return '${value.toStringAsFixed(0)} €';
}

String formatPercentOneDecimal(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}

String formatDateFromMillis(int millis) {
  return DateTime.fromMillisecondsSinceEpoch(millis)
      .toIso8601String()
      .substring(0, 10);
}
