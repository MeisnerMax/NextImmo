import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';

void main() {
  group('ValuationFactor provenance', () {
    test('userProvided factor is usable', () {
      final f = ValuationFactor.user(
        id: 'rohertrag',
        label: 'Rohertrag',
        value: 12000,
        unit: '€',
      );
      expect(f.isUsable, isTrue);
      expect(f.usableValue, 12000);
    });

    test('derived factor is usable', () {
      final f = ValuationFactor.derived(
        id: 'vervielfaeltiger',
        label: 'Vervielfältiger',
        value: 20.0,
      );
      expect(f.isUsable, isTrue);
      expect(f.usableValue, 20.0);
    });

    test('unconfirmed suggestedDefault is NOT usable and yields no value', () {
      final f = ValuationFactor.suggested(
        id: 'liegenschaftszins',
        label: 'Liegenschaftszinssatz',
        value: 0.035,
        unit: '%',
      );
      expect(f.isUsable, isFalse);
      expect(f.usableValue, isNull);
    });

    test('accept() turns a suggestion into a usable accepted factor', () {
      final suggested = ValuationFactor.suggested(
        id: 'liegenschaftszins',
        label: 'Liegenschaftszinssatz',
        value: 0.035,
      );
      final accepted = suggested.accept();
      expect(accepted.provenance, FactorProvenance.accepted);
      expect(accepted.isUsable, isTrue);
      expect(accepted.usableValue, 0.035);
    });

    test('accept() is a no-op for non-suggestion provenance', () {
      final user = ValuationFactor.user(id: 'x', label: 'X', value: 1);
      expect(identical(user.accept(), user), isTrue);
    });

    test('missing factor is not usable', () {
      final f = ValuationFactor.missing(id: 'bodenrichtwert', label: 'Bodenrichtwert');
      expect(f.isUsable, isFalse);
      expect(f.value, isNull);
      expect(f.usableValue, isNull);
    });
  });

  group('FactorSet.missingAmong', () {
    test('reports notEntered for an absent required factor', () {
      final set = FactorSet(const []);
      final missing = set.missingAmong(['bodenrichtwert']);
      expect(missing, hasLength(1));
      expect(missing.single.reason, MissingFactorReason.notEntered);
      expect(missing.single.factorId, 'bodenrichtwert');
    });

    test('reports suggestionNotConfirmed for an unconfirmed suggestion', () {
      final set = FactorSet([
        ValuationFactor.suggested(
          id: 'liegenschaftszins',
          label: 'Liegenschaftszinssatz',
          value: 0.035,
        ),
      ]);
      final missing = set.missingAmong(['liegenschaftszins']);
      expect(missing.single.reason, MissingFactorReason.suggestionNotConfirmed);
    });

    test('does not report usable factors', () {
      final set = FactorSet([
        ValuationFactor.user(id: 'rohertrag', label: 'Rohertrag', value: 12000),
        ValuationFactor.suggested(id: 'lz', label: 'LZ', value: 0.035).accept(),
      ]);
      expect(set.missingAmong(['rohertrag', 'lz']), isEmpty);
    });
  });

  group('FactorSet accessors', () {
    test('value returns only usable values', () {
      final set = FactorSet([
        ValuationFactor.user(id: 'a', label: 'A', value: 5),
        ValuationFactor.suggested(id: 'b', label: 'B', value: 9),
      ]);
      expect(set.value('a'), 5);
      expect(set.value('b'), isNull);
      expect(set.has('a'), isTrue);
      expect(set.has('b'), isFalse);
      expect(set.value('missing'), isNull);
    });

    test('withFactor replaces an existing factor by id', () {
      final set = FactorSet([
        ValuationFactor.suggested(id: 'lz', label: 'LZ', value: 0.035),
      ]);
      final updated = set.withFactor(set['lz']!.accept());
      expect(updated.value('lz'), 0.035);
      expect(updated.all, hasLength(1));
    });
  });
}
