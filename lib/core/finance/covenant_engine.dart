class CovenantEngine {
  const CovenantEngine();

  double? computeDSCR(double? noi, double? debtService) {
    if (noi == null || debtService == null || debtService <= 0) {
      return null;
    }
    return noi / debtService;
  }

  double? computeLTV(double? balance, double? valuation) {
    if (balance == null || valuation == null || valuation <= 0) {
      return null;
    }
    return balance / valuation;
  }

  bool? evaluate({
    required String operator,
    required double? actual,
    required double threshold,
  }) {
    if (actual == null) {
      return null;
    }
    if (operator == 'gte') {
      return actual >= threshold;
    }
    if (operator == 'lte') {
      return actual <= threshold;
    }
    throw StateError('Unsupported covenant operator: $operator');
  }
}
