import 'package:flutter/material.dart';

import 'nx_card.dart';
import 'nx_section_header.dart';
import '../theme/app_theme.dart';

class NxFormSectionCard extends StatelessWidget {
  const NxFormSectionCard({
    super.key,
    required this.title,
    this.description,
    this.children = const <Widget>[],
    this.body,
    this.trailing,
    this.actions = const <Widget>[],
    this.margin = const EdgeInsets.only(bottom: AppSpacing.component),
    this.contentPadding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  final String title;
  final String? description;

  /// Width-bounded form fields laid out in a wrap. Ignored when [body] is set.
  final List<Widget> children;

  /// Optional full-width section body (custom grids, editors, metric strips)
  /// rendered instead of the [children] wrap. Provides the "section with a
  /// custom body" capability the wizard steps need without forking the card.
  final Widget? body;
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.component),
              decoration: BoxDecoration(
                color: context.semanticColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                border: Border.all(color: context.semanticColors.border),
              ),
              child: NxSectionHeader(
                title: title,
                description: description,
                compact: true,
                trailing: trailing,
                actions: actions,
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            if (body != null)
              SizedBox(width: double.infinity, child: body!)
            else
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
