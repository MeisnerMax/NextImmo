/// Shared number/label formatting for the valuation UI.
///
/// One rule everywhere: a value that could not be determined renders as
/// [notDeterminable] — never as `0`, `–` or an empty cell, because each of
/// those reads either like a number or like a loading state.
///
/// Formatting is hand-rolled German grouping rather than `intl`: the project
/// has no `intl` dependency and adding a package for four format calls is not
/// worth it (`CLAUDE.md`: no new packages without an explicit request).
library;

const String notDeterminable = 'nicht ermittelbar';

String formatEuro(double? amount) =>
    amount == null ? notDeterminable : '${_grouped(amount, decimals: 0)} €';

String formatPercent(double? fraction, {int decimals = 1}) => fraction == null
    ? notDeterminable
    : '${_grouped(fraction * 100, decimals: decimals)} %';

/// A breakdown line's amount: euro when the line carries the € unit, a
/// percentage for share-like values, a plain number for factors/multipliers.
String formatBreakdownAmount(double? amount, String? unit) {
  if (amount == null) return notDeterminable;
  return switch (unit) {
    '€' => formatEuro(amount),
    '%' => formatPercent(amount),
    final String u when u.isNotEmpty => '${_grouped(amount, decimals: 2)} $u',
    _ => _grouped(amount, decimals: 4),
  };
}

String formatFactorValue(double? value, String? unit) =>
    formatBreakdownAmount(value, unit);

/// German grouping: `.` for thousands, `,` for the decimal separator, trailing
/// zeros of the fractional part dropped.
String _grouped(double value, {required int decimals}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }

  var fraction = parts.length > 1 ? parts[1] : '';
  while (fraction.isNotEmpty && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }

  final sign = negative ? '−' : '';
  return fraction.isEmpty
      ? '$sign$buffer'
      : '$sign$buffer,$fraction';
}
