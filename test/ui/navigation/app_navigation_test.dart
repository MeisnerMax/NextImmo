import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/navigation/app_navigation.dart';
import 'package:neximmo_app/ui/state/app_state.dart';

void main() {
  test('reference property route round-trips a stable encoded id', () {
    final route = referencePropertyRoute('property / ä');

    expect(route, '/properties/property%20%2F%20%C3%A4');
    expect(referencePropertyIdFromRoute(route), 'property / ä');
    expect(referencePropertyIdFromRoute('/properties'), isNull);
    expect(referencePropertyIdFromRoute('/properties/'), isNull);
    expect(referencePropertyIdFromRoute('/other/property-a'), isNull);
    expect(() => referencePropertyRoute('  '), throwsArgumentError);
  });

  test('unknown or missing roles cannot access navigation pages', () {
    for (final page in GlobalPage.values) {
      expect(isPageAllowedForRole(page, ''), isFalse);
      expect(isPageAllowedForRole(page, 'unknown'), isFalse);
    }
  });
}
