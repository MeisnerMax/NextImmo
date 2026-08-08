import 'package:flutter/material.dart';

import '../../../components/nx_empty_state.dart';
import '../../../i18n/app_strings.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';

/// Empty/onboarding guidance of the overview screen as an `NxEmptyState`
/// "next step" card (SCR-011 mandatory empty state): names the concrete next
/// actions and navigates straight into the source modules.
class OverviewOnboardingCard extends StatelessWidget {
  const OverviewOnboardingCard({super.key, required this.onNavigate});

  final ValueChanged<PropertyDetailPage> onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final actions = <
      ({IconData icon, String title, String description, PropertyDetailPage page})
    >[
      (
        icon: Icons.tune_outlined,
        title: s.text('Add financial assumptions'),
        description: s.text('Purchase price, financing and capex assumptions'),
        page: PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.flag_outlined,
        title: s.text('Set strategy'),
        description: s.text('Choose the base scenario and investment approach'),
        page: PropertyDetailPage.scenarios,
      ),
      (
        icon: Icons.bar_chart_outlined,
        title: s.text('Add rent data'),
        description: s.text('Enter rent, vacancy and operating income data'),
        page: PropertyDetailPage.inputs,
      ),
      (
        icon: Icons.folder_open_outlined,
        title: s.text('Add documents'),
        description: s.text(
          'Upload leases, diligence files and supporting material',
        ),
        page: PropertyDetailPage.documents,
      ),
    ];

    return NxEmptyState(
      title: s.text('Next Steps'),
      description: s.text(
        'This property was created with the basics only. Add the next inputs to unlock a reliable analysis.',
      ),
      icon: Icons.flag_outlined,
      primaryAction: Wrap(
        spacing: AppSpacing.component,
        runSpacing: AppSpacing.component,
        alignment: WrapAlignment.center,
        children: [
          for (final action in actions)
            SizedBox(
              width: 260,
              child: OutlinedButton(
                onPressed: () => onNavigate(action.page),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(action.icon),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      action.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      action.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
