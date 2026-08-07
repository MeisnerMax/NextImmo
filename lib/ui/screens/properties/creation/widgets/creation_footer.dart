import 'package:flutter/material.dart';

import 'package:neximmo_app/ui/components/nx_action_toolbar.dart';

/// Wizard footer built on [NxActionToolbar] (former private `_FooterBar`):
/// step counter, jump-to-review, back/next, and the final save action. The
/// enable/disable rules are unchanged from the pre-split screen.
class CreationFooter extends StatelessWidget {
  const CreationFooter({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.canSave,
    required this.saving,
    required this.created,
    required this.onBack,
    required this.onNext,
    required this.onSummary,
    required this.onSave,
  });

  final int currentStep;
  final int totalSteps;
  final bool canSave;
  final bool saving;
  final bool created;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSummary;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return NxActionToolbar(
      children: [
        Text('Schritt ${currentStep + 1} von $totalSteps'),
        TextButton(onPressed: onSummary, child: const Text('Zur Pruefung')),
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Zurueck'),
        ),
        if (currentStep < totalSteps - 1)
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Weiter'),
          )
        else
          FilledButton.icon(
            onPressed: canSave && !saving && !created ? onSave : null,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
          ),
      ],
    );
  }
}
