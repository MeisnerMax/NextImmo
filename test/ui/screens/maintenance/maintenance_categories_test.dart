import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/screens/maintenance/widgets/maintenance_categories.dart';

void main() {
  group('curated vocabulary', () {
    test('carries the seven the spec names, in its order', () {
      expect(curatedMaintenanceCategories, <String>[
        'damage',
        'defect',
        'repair',
        'maintenance',
        'inspection',
        'minor_repair',
        'general',
      ]);
    });

    test('does not resurrect the three the spec dropped', () {
      // `renovation` and `modernization` are CapEx measures rather than
      // tickets; `warranty` was a legacy shadow value no dropdown could
      // produce. Listing them again would quietly re-open decisions.
      expect(curatedMaintenanceCategories, isNot(contains('renovation')));
      expect(curatedMaintenanceCategories, isNot(contains('modernization')));
      expect(curatedMaintenanceCategories, isNot(contains('warranty')));
    });

    test('labels the curated keys and leaves everything else alone', () {
      expect(maintenanceCategoryLabel('minor_repair'), 'Kleinreparatur');
      // The raw key, not "Sonstiges": a value this build does not know is
      // still a real category somebody chose, and inventing a label hides it.
      expect(maintenanceCategoryLabel('elevator'), 'elevator');
      expect(isCuratedMaintenanceCategory('elevator'), isFalse);
      expect(isCuratedMaintenanceCategory('general'), isTrue);
    });
  });

  group('options', () {
    test('curated first, then what the workspace actually uses', () {
      final options = maintenanceCategoryOptions(<String>[
        'water',
        'elevator',
        'hvac',
      ]);

      expect(options.take(7), curatedMaintenanceCategories);
      // Alphabetical after, and stable: a list that reordered itself as
      // tickets were created would move the option under the reader's cursor.
      expect(options.skip(7), <String>['elevator', 'hvac', 'water']);
    });

    test('a workspace value that matches a curated one is not repeated', () {
      final options = maintenanceCategoryOptions(<String>[
        'general',
        'defect',
        'hvac',
      ]);

      expect(options.where((o) => o == 'general'), hasLength(1));
      expect(options.where((o) => o == 'defect'), hasLength(1));
      expect(options, contains('hvac'));
    });

    test('duplicates in the census collapse', () {
      expect(
        maintenanceCategoryOptions(<String>['hvac', 'hvac', 'hvac']).skip(7),
        <String>['hvac'],
      );
    });

    test('an empty census still offers the curated list', () {
      // The filter must work on day one, before anybody has typed anything.
      expect(
        maintenanceCategoryOptions(const <String>[]),
        curatedMaintenanceCategories,
      );
    });
  });
}
