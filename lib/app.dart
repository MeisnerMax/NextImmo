import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/security/security_gate.dart';
import 'ui/state/app_state.dart';
import 'ui/theme/app_theme.dart';

class NexImmoApp extends ConsumerWidget {
  const NexImmoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final densityMode = AppTheme.resolveDensityMode(
      settings?.uiDensityMode ?? 'comfort',
    );

    return MaterialApp(
      title: 'Deal Analyzer Desktop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(densityMode: densityMode),
      darkTheme: AppTheme.dark(densityMode: densityMode),
      themeMode: AppTheme.resolveThemeMode(settings?.uiThemeMode ?? 'system'),
      home: const SecurityGate(),
    );
  }
}
