import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/amortization.dart';

void main() {
  test('GM-FIN-002 builds the approved 30-year amortization schedule', () {
    final result = buildAmortizationSchedule(
      principal: 100000,
      annualRate: 0.06,
      termYears: 30,
    );

    expect(result.monthlyPayment, closeTo(599.55, 0.01));
    expect(result.schedule, hasLength(360));
    expect(result.schedule.first.monthIndex, 1);
    expect(result.schedule.last.monthIndex, 360);
    expect(result.schedule.last.balance, closeTo(0, 0.00000001));
  });
}
