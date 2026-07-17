import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/finance/covenant_engine.dart';

void main() {
  test('GM-COV-001 evaluates DSCR and LTV covenant checks', () {
    const engine = CovenantEngine();

    expect(engine.computeDSCR(120, 100), 1.2);
    expect(engine.computeLTV(600, 1000), 0.6);
    expect(
      engine.evaluate(operator: 'gte', actual: 1.2, threshold: 1.2),
      isTrue,
    );
    expect(
      engine.evaluate(operator: 'gte', actual: 1.19, threshold: 1.2),
      isFalse,
    );
    expect(
      engine.evaluate(operator: 'lte', actual: 0.6, threshold: 0.6),
      isTrue,
    );
    expect(
      engine.evaluate(operator: 'lte', actual: 0.61, threshold: 0.6),
      isFalse,
    );

    expect(engine.computeDSCR(null, 100), isNull);
    expect(engine.computeDSCR(120, null), isNull);
    expect(engine.computeDSCR(120, 0), isNull);
    expect(engine.computeDSCR(120, -1), isNull);
    expect(engine.computeLTV(null, 1000), isNull);
    expect(engine.computeLTV(600, null), isNull);
    expect(engine.computeLTV(600, 0), isNull);
    expect(engine.computeLTV(600, -1), isNull);
    expect(
      engine.evaluate(operator: 'gte', actual: null, threshold: 1),
      isNull,
    );
    expect(
      () => engine.evaluate(operator: 'eq', actual: 1, threshold: 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unsupported covenant operator: eq',
        ),
      ),
    );
  });
}
