import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import 'nx_card.dart';

enum NxChartState { loading, empty, ready, error }

class NxChartContainer extends StatelessWidget {
  const NxChartContainer({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.state,
    required this.child,
    this.height,
    this.emptyText = 'No data available.',
    this.errorText = 'Chart could not be loaded.',
  });

  final String title;
  final String? subtitle;

  /// Optional header action (e.g. a period toggle) rendered to the right of
  /// the title.
  final Widget? trailing;
  final NxChartState state;
  final Widget child;

  /// Fixed height for the chart area. When set, the content is laid out in a
  /// [SizedBox] of this height instead of an [Expanded], so the container can
  /// live inside unbounded-height parents (e.g. a full-page scroll view).
  /// When null, behavior is unchanged: the chart expands to fill the parent's
  /// bounded height.
  final double? height;
  final String emptyText;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    return NxCard(
      child: Column(
        mainAxisSize: height != null ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (height != null)
            SizedBox(height: height, child: content)
          else
            Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (state) {
      case NxChartState.loading:
        return const Center(child: CircularProgressIndicator());
      case NxChartState.empty:
        return Center(child: Text(context.strings.text(emptyText)));
      case NxChartState.error:
        return Center(child: Text(context.strings.text(errorText)));
      case NxChartState.ready:
        return child;
    }
  }
}
