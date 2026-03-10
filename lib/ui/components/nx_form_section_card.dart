import 'package:flutter/material.dart';

import 'nx_card.dart';
import 'nx_section_header.dart';
import '../theme/app_theme.dart';

class NxFormSectionCard extends StatelessWidget {
  const NxFormSectionCard({
    super.key,
    required this.title,
    this.description,
    required this.children,
    this.trailing,
    this.actions = const <Widget>[],
    this.margin = const EdgeInsets.only(bottom: AppSpacing.component),
    this.contentPadding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final Widget? trailing;
  final List<Widget> actions;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: NxCard(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NxSectionHeader(
              title: title,
              description: description,
              compact: true,
              trailing: trailing,
              actions: actions,
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: children,
            ),
          ],
        ),
      ),
    );
  }
}
