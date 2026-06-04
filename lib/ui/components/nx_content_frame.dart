import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NxContentFrame extends StatelessWidget {
  const NxContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: child,
    );
  }
}
