import 'package:flutter/material.dart';

import 'nx_card.dart';

enum NxChartState { loading, empty, ready, error }

class NxChartContainer extends StatelessWidget {
  const NxChartContainer({
    super.key,
    required this.title,
    this.subtitle,
    required this.state,
    required this.child,
    this.emptyText = 'No data available.',
    this.errorText = 'Chart could not be loaded.',
  });

  final String title;
  final String? subtitle;
  final NxChartState state;
  final Widget child;
  final String emptyText;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (state) {
      case NxChartState.loading:
        return const Center(child: CircularProgressIndicator());
      case NxChartState.empty:
        return Center(child: Text(emptyText));
      case NxChartState.error:
        return Center(child: Text(errorText));
      case NxChartState.ready:
        return child;
    }
  }
}
