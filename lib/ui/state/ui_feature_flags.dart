import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UiScreenFlag {
  appShellV2,
  dashboardV2,
  propertiesV2,
  propertyShellV2,
}

class UiFeatureFlags {
  static const Map<UiScreenFlag, bool> defaults = <UiScreenFlag, bool>{
    UiScreenFlag.appShellV2: true,
    UiScreenFlag.dashboardV2: true,
    UiScreenFlag.propertiesV2: true,
    UiScreenFlag.propertyShellV2: true,
  };

  const UiFeatureFlags._();
}

final uiFeatureFlagsProvider = Provider<Map<UiScreenFlag, bool>>(
  (ref) => UiFeatureFlags.defaults,
);

final uiScreenFlagProvider = Provider.family<bool, UiScreenFlag>((ref, flag) {
  final flags = ref.watch(uiFeatureFlagsProvider);
  return flags[flag] ?? false;
});
