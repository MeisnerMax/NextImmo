class NumberParse {
  const NumberParse._();

  static double? parseDoubleFlexible(String raw) {
    final normalized = _normalize(raw);
    if (normalized == null) {
      return null;
    }
    return double.tryParse(normalized);
  }

  static int? parseIntFlexible(String raw) {
    final value = parseDoubleFlexible(raw);
    if (value == null || value.isNaN || value.isInfinite) {
      return null;
    }
    final rounded = value.roundToDouble();
    if (rounded != value) {
      return null;
    }
    return value.toInt();
  }

  static String? _normalize(String raw) {
    var input = raw.trim();
    if (input.isEmpty) {
      return null;
    }

    // Remove regular and locale-specific spaces used as grouping separators.
    input = input
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(RegExp(r'\s+'), '');

    if (input.isEmpty) {
      return null;
    }

    if (RegExp(r'[+-]').allMatches(input).length > 1) {
      return null;
    }
    if (input.contains('+') || input.contains('-')) {
      if (!(input.startsWith('+') || input.startsWith('-'))) {
        return null;
      }
    }

    final sign =
        (input.startsWith('-') || input.startsWith('+'))
            ? input.substring(0, 1)
            : '';
    final unsigned = sign.isEmpty ? input : input.substring(1);
    if (unsigned.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[0-9.,]+$').hasMatch(unsigned)) {
      return null;
    }
    if (!RegExp(r'[0-9]').hasMatch(unsigned)) {
      return null;
    }

    final dotCount = '.'.allMatches(unsigned).length;
    final commaCount = ','.allMatches(unsigned).length;

    if (dotCount == 0 && commaCount == 0) {
      return '$sign$unsigned';
    }

    final decimalSep = _resolveDecimalSeparator(unsigned, dotCount, commaCount);
    if (decimalSep == null) {
      return null;
    }

    final decimalIndex =
        decimalSep.isEmpty ? -1 : unsigned.lastIndexOf(decimalSep);
    if (decimalSep.isNotEmpty && decimalIndex == unsigned.length - 1) {
      return null;
    }

    final normalized = StringBuffer(sign);
    for (var i = 0; i < unsigned.length; i++) {
      final ch = unsigned[i];
      if (ch == '.' || ch == ',') {
        if (decimalSep.isNotEmpty && i == decimalIndex) {
          normalized.write('.');
        }
        continue;
      }
      normalized.write(ch);
    }

    final value = normalized.toString();
    if (value == sign || value.isEmpty || value == '$sign.') {
      return null;
    }
    return value;
  }

  static String? _resolveDecimalSeparator(
    String unsigned,
    int dotCount,
    int commaCount,
  ) {
    if (dotCount > 0 && commaCount > 0) {
      final dotLast = unsigned.lastIndexOf('.');
      final commaLast = unsigned.lastIndexOf(',');
      return dotLast > commaLast ? '.' : ',';
    }

    final sep = dotCount > 0 ? '.' : ',';
    final count = dotCount > 0 ? dotCount : commaCount;

    if (count == 1) {
      final idx = unsigned.indexOf(sep);
      final fractionDigits = unsigned.length - idx - 1;
      // Treat 3 trailing digits as a thousands grouping (e.g. 1.790 / 1,790).
      if (fractionDigits == 3 && idx > 0) {
        return '';
      }
      return sep;
    }

    final parts = unsigned.split(sep);
    if (parts.any((p) => p.isEmpty)) {
      return null;
    }

    final allGrouped = parts.skip(1).every((p) => p.length == 3);
    if (allGrouped && parts.first.length <= 3) {
      return '';
    }

    return null;
  }
}

double? parseDoubleFlexible(String raw) => NumberParse.parseDoubleFlexible(raw);

int? parseIntFlexible(String raw) => NumberParse.parseIntFlexible(raw);
