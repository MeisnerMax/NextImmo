import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/platform_audit_jobs/domain/task_category.dart';

void main() {
  group('TaskCategory', () {
    test('round-trips every §7.5 vocabulary value', () {
      const wire = <String>[
        'general',
        'letting',
        'maintenance',
        'renovation',
        'finance',
        'document',
        'compliance',
        'valuation',
      ];

      expect(
        TaskCategory.values.map((category) => category.wireName),
        wire,
      );
      for (final value in wire) {
        expect(TaskCategory.tryFromWire(value)?.wireName, value);
        expect(TaskCategory.fromWire(value).wireName, value);
      }
    });

    test('an unknown server value is preserved, not normalized', () {
      // Shared §7.5/§17: unknown values are displayed and survive an edit
      // cycle. `tryFromWire` returning null is the hook that keeps the raw
      // string alive; only `fromWire` falls back for concrete defaults.
      expect(TaskCategory.tryFromWire('sonderpruefung'), isNull);
      expect(TaskCategory.fromWire('sonderpruefung'), TaskCategory.general);
      expect(TaskCategory.tryFromWire(null), isNull);
      expect(TaskCategory.fromWire(null), TaskCategory.general);
      // Exact wire match only — no trimming or case folding that would turn
      // a distinct server value into a known one.
      expect(TaskCategory.tryFromWire('Letting'), isNull);
      expect(TaskCategory.tryFromWire(' letting'), isNull);
    });
  });
}
