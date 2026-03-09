import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.page),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.cardPadding),
          child: SelectableText(
            'Offline-first app. No external web requests are used in V1.\n\n'
            'Workflow:\n'
            '1. Create property\n'
            '2. Edit scenario inputs\n'
            '3. Review analysis and criteria\n'
            '4. Use offer solver\n'
            '5. Export reports (PDF/JSON/CSV)',
          ),
        ),
      ),
    );
  }
}
