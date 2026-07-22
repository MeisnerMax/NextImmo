import 'package:flutter/material.dart';

import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Single selectable option in the [CreationOptionGrid].
class CreationOptionSpec {
  const CreationOptionSpec(this.value, this.title, this.icon, this.description);

  final String value;
  final String title;
  final IconData icon;
  final String description;
}

/// Responsive card grid for the property-type picker (step 0). Four columns on
/// wide surfaces, two below — the former private `_OptionGrid`, now token-based
/// and used as an [NxFormSectionCard] body.
class CreationOptionGrid extends StatelessWidget {
  const CreationOptionGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<CreationOptionSpec> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 3 * AppSpacing.component) / 4
            : (constraints.maxWidth - AppSpacing.component) / 2;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final option in options)
              SizedBox(
                width: width,
                child: InkWell(
                  onTap: () => onSelected(option.value),
                  borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 128),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected == option.value
                          ? theme.colorScheme.primaryContainer
                          : semantic.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                      border: Border.all(
                        color: selected == option.value
                            ? theme.colorScheme.primary
                            : semantic.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(option.icon),
                        const SizedBox(height: 10),
                        Text(
                          option.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          option.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
