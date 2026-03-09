double? computeIrr(
  List<double> cashflows, {
  int maxIterations = 100,
  double epsilon = 1e-7,
}) {
  if (cashflows.length < 2) {
    return null;
  }

  final hasPositive = cashflows.any((value) => value > 0);
  final hasNegative = cashflows.any((value) => value < 0);
  if (!hasPositive || !hasNegative) {
    return null;
  }

  double npv(double rate) {
    double sum = 0;
    for (var i = 0; i < cashflows.length; i++) {
      sum += cashflows[i] / _pow1p(rate, i);
    }
    return sum;
  }

  double derivative(double rate) {
    double sum = 0;
    for (var i = 1; i < cashflows.length; i++) {
      sum -= i * cashflows[i] / _pow1p(rate, i + 1);
    }
    return sum;
  }

  var guess = 0.1;
  for (var i = 0; i < maxIterations; i++) {
    final value = npv(guess);
    if (value.abs() < epsilon) {
      return guess;
    }
    final slope = derivative(guess);
    if (slope.abs() < 1e-12) {
      break;
    }
    final next = guess - value / slope;
    if (next <= -0.9999 || next.isInfinite || next.isNaN) {
      break;
    }
    if ((next - guess).abs() < epsilon) {
      return next;
    }
    guess = next;
  }

  // Fallback to binary search over a wide range.
  var low = -0.99;
  var high = 10.0;
  var lowValue = npv(low);
  var highValue = npv(high);

  if (lowValue * highValue > 0) {
    return null;
  }

  for (var i = 0; i < maxIterations * 2; i++) {
    final mid = (low + high) / 2;
    final midValue = npv(mid);

    if (midValue.abs() < epsilon) {
      return mid;
    }

    if (lowValue * midValue < 0) {
      high = mid;
      highValue = midValue;
    } else {
      low = mid;
      lowValue = midValue;
    }
  }

  return (low + high) / 2;
}

double _pow1p(double rate, int exponent) {
  return (1 + rate).clamp(1e-9, double.infinity).toDouble().pow(exponent);
}

extension on double {
  double pow(int exponent) {
    if (exponent == 0) {
      return 1;
    }
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
