import '../models/analysis_result.dart';

class AmortizationResult {
  const AmortizationResult({
    required this.monthlyPayment,
    required this.schedule,
  });

  final double monthlyPayment;
  final List<AmortizationEntry> schedule;
}

AmortizationResult buildAmortizationSchedule({
  required double principal,
  required double annualRate,
  required int termYears,
}) {
  if (principal <= 0 || termYears <= 0) {
    return const AmortizationResult(
      monthlyPayment: 0,
      schedule: <AmortizationEntry>[],
    );
  }

  final monthlyRate = annualRate / 12;
  final months = termYears * 12;

  final payment =
      monthlyRate == 0
          ? principal / months
          : principal * monthlyRate / (1 - _pow(1 + monthlyRate, -months));

  var balance = principal;
  final schedule = <AmortizationEntry>[];

  for (var month = 1; month <= months; month++) {
    final interest = balance * monthlyRate;
    var principalPart = payment - interest;

    if (month == months || principalPart > balance) {
      principalPart = balance;
    }

    balance = (balance - principalPart).clamp(0, double.infinity).toDouble();

    schedule.add(
      AmortizationEntry(
        monthIndex: month,
        payment: payment,
        interest: interest,
        principal: principalPart,
        balance: balance,
      ),
    );
  }

  return AmortizationResult(monthlyPayment: payment, schedule: schedule);
}

double _pow(double base, int exponent) {
  if (exponent == 0) {
    return 1;
  }

  if (exponent < 0) {
    return 1 / _pow(base, -exponent);
  }

  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= base;
  }
  return value;
}
