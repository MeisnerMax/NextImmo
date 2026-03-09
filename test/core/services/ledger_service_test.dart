import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/services/ledger_service.dart';

void main() {
  const service = LedgerService();

  test('derivePeriodKey uses YYYY-MM', () {
    final key = service.derivePeriodKey(
      DateTime(2026, 3, 3, 12, 0, 0).millisecondsSinceEpoch,
    );
    expect(key, '2026-03');
  });

  test('computeSignedAmount handles in/out', () {
    expect(service.computeSignedAmount(direction: 'in', amount: 10), 10);
    expect(service.computeSignedAmount(direction: 'out', amount: 10), -10);
  });
}
