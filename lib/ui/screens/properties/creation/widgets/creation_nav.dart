import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// One entry in the wizard's left navigation rail. Shows the step number, its
/// label, and a state icon derived from the live [PropertyCreationAssessment].
/// Former private `_StepNavTile`.
class CreationStepNavTile extends StatelessWidget {
  const CreationStepNavTile({
    super.key,
    required this.index,
    required this.label,
    required this.selected,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final PropertyCreationStepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final icon = switch (state) {
      PropertyCreationStepState.complete => Icons.check_circle,
      PropertyCreationStepState.warning => Icons.warning_amber,
      PropertyCreationStepState.incomplete => Icons.error_outline,
      PropertyCreationStepState.untouched => Icons.radio_button_unchecked,
    };
    final color = switch (state) {
      PropertyCreationStepState.complete => semantic.success,
      PropertyCreationStepState.warning => semantic.warning,
      PropertyCreationStepState.incomplete => semantic.error,
      PropertyCreationStepState.untouched => semantic.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        enabled: onTap != null,
        selected: selected,
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        ),
        leading: Icon(icon, color: color, size: 20),
        title: Text('${index + 1}. $label', maxLines: 2),
        onTap: onTap,
      ),
    );
  }
}

/// Data-quality summary card at the top of the navigation rail. Former private
/// `_QualityPanel`, now built on [NxCard].
class CreationQualityPanel extends StatelessWidget {
  const CreationQualityPanel({super.key, required this.assessment});

  final PropertyCreationAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datenqualitaet',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: assessment.metrics.dataQualityScore / 100,
          ),
          const SizedBox(height: 8),
          Text(
            '${assessment.metrics.dataQualityScore}% · '
            '${assessment.metrics.dataQualityStatus}',
          ),
        ],
      ),
    );
  }
}
