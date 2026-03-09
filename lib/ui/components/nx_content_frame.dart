import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NxContentFrame extends StatelessWidget {
  const NxContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: semantic.border),
      ),
      child: child,
    );
  }
}
