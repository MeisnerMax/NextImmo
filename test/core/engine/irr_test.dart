import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/irr.dart';

void main() {
  test('computeIrr returns expected approximate value', () {
    final irr = computeIrr(<double>[-1000, 300, 420, 680]);
    expect(irr, isNotNull);
    expect(irr!, closeTo(0.1634, 0.01));
  });

  test('computeIrr returns null for non-mixed cashflows', () {
    final irr = computeIrr(<double>[-1000, -100, -50]);
    expect(irr, isNull);
  });
}
