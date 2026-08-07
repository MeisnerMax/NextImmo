import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_math.dart';

void main() {
  group('presentValueAnnuityFactor (Vervielfältiger)', () {
    test('matches the closed-form value for 5% over 10 years', () {
      final v = presentValueAnnuityFactor(rate: 0.05, years: 10);
      expect(v, isNotNull);
      expect(v!, closeTo(7.7217, 0.0005));
    });

    test('equals the term count when the rate is zero', () {
      expect(presentValueAnnuityFactor(rate: 0, years: 30), 30.0);
    });

    test('returns null for invalid inputs instead of a wrong number', () {
      expect(presentValueAnnuityFactor(rate: 0.05, years: 0), isNull);
      expect(presentValueAnnuityFactor(rate: -1, years: 10), isNull);
    });
  });

  group('discountFactor', () {
    test('is 1 at year 0 and 1/(1+r) at year 1', () {
      expect(discountFactor(rate: 0.05, years: 0), 1.0);
      expect(discountFactor(rate: 0.05, years: 1)!, closeTo(0.95238, 0.0001));
    });

    test('returns null for invalid inputs', () {
      expect(discountFactor(rate: -1, years: 5), isNull);
      expect(discountFactor(rate: 0.05, years: -1), isNull);
    });
  });

  group('linearRemainingValueFactor (Alterswertminderung)', () {
    test('is 0.75 at 20 of 80 years', () {
      expect(linearRemainingValueFactor(age: 20, totalUsefulLife: 80), 0.75);
    });

    test('clamps to 0 when age exceeds the useful life', () {
      expect(linearRemainingValueFactor(age: 100, totalUsefulLife: 80), 0.0);
    });

    test('returns null for invalid inputs', () {
      expect(linearRemainingValueFactor(age: 10, totalUsefulLife: 0), isNull);
      expect(linearRemainingValueFactor(age: -1, totalUsefulLife: 80), isNull);
    });
  });

  group('remainingUsefulLife (Restnutzungsdauer)', () {
    test('is GND minus age', () {
      expect(remainingUsefulLife(totalUsefulLife: 80, age: 30), 50);
    });

    test('never goes below zero', () {
      expect(remainingUsefulLife(totalUsefulLife: 80, age: 100), 0);
    });

    test('returns null for invalid inputs', () {
      expect(remainingUsefulLife(totalUsefulLife: 0, age: 10), isNull);
      expect(remainingUsefulLife(totalUsefulLife: 80, age: -1), isNull);
    });
  });
}
