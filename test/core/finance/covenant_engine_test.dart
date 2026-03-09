import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/covenant_engine.dart';

void main() {
  test('evaluates DSCR and LTV covenant checks', () {
    const engine = CovenantEngine();

    expect(engine.computeDSCR(120, 100), 1.2);
    expect(engine.computeLTV(600, 1000), 0.6);
    expect(
      engine.evaluate(operator: 'gte', actual: 1.2, threshold: 1.1),
      isTrue,
    );
    expect(
      engine.evaluate(operator: 'lte', actual: 0.6, threshold: 0.65),
      isTrue,
    );
    expect(
      engine.evaluate(operator: 'gte', actual: null, threshold: 1),
      isNull,
    );
  });
}
