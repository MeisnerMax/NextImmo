import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/ui/state/ui_feature_flags.dart';

void main() {
  test('v2 feature flags are enabled by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(uiScreenFlagProvider(UiScreenFlag.appShellV2)),
      isTrue,
    );
    expect(
      container.read(uiScreenFlagProvider(UiScreenFlag.dashboardV2)),
      isTrue,
    );
    expect(
      container.read(uiScreenFlagProvider(UiScreenFlag.propertiesV2)),
      isTrue,
    );
    expect(
      container.read(uiScreenFlagProvider(UiScreenFlag.propertyShellV2)),
      isTrue,
    );
  });
}
