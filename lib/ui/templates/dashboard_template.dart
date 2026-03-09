import 'package:flutter/material.dart';

import '../components/nx_page_header.dart';
import '../theme/app_theme.dart';

class DashboardTemplateSection {
  const DashboardTemplateSection({required this.title, required this.child});

  final String title;
  final Widget child;
}

class DashboardTemplate extends StatelessWidget {
  const DashboardTemplate({
    super.key,
    required this.title,
    required this.breadcrumbs,
    this.subtitle,
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
    required this.kpis,
    required this.insights,
    this.actionCenter,
    this.activity,
  });

  final String title;
  final List<String> breadcrumbs;
  final String? subtitle;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;
  final List<Widget> kpis;
  final List<DashboardTemplateSection> insights;
  final DashboardTemplateSection? actionCenter;
  final DashboardTemplateSection? activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: ListView(
        children: [
          NxPageHeader(
            title: title,
            breadcrumbs: breadcrumbs,
            subtitle: subtitle,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: kpis,
          ),
          const SizedBox(height: AppSpacing.section),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1120;
              final insightWidgets = insights
                  .map((section) => _sectionBlock(context, section))
                  .toList(growable: false);
              if (stacked) {
                return Column(
                  children: [
                    ...insightWidgets,
                    if (actionCenter != null) ...[
                      const SizedBox(height: AppSpacing.component),
                      _sectionBlock(context, actionCenter!),
                    ],
                    if (activity != null) ...[
                      const SizedBox(height: AppSpacing.component),
                      _sectionBlock(context, activity!),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            for (var i = 0; i < insightWidgets.length; i++) ...[
                              if (i > 0)
                                const SizedBox(height: AppSpacing.component),
                              insightWidgets[i],
                            ],
                          ],
                        ),
                      ),
                      if (actionCenter != null) ...[
                        const SizedBox(width: AppSpacing.component),
                        Expanded(
                          flex: 2,
                          child: _sectionBlock(context, actionCenter!),
                        ),
                      ],
                    ],
                  ),
                  if (activity != null) ...[
                    const SizedBox(height: AppSpacing.component),
                    _sectionBlock(context, activity!),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionBlock(BuildContext context, DashboardTemplateSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.component),
        section.child,
      ],
    );
  }
}
