import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'info_tooltip.dart';

enum KpiTileStatus { normal, positive, negative, warning }

class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.title,
    required this.value,
    required this.metricKey,
    this.subtitle,
    this.delta,
    this.status = KpiTileStatus.normal,
    this.width = 240,
  });

  final String title;
  final String value;
  final String metricKey;
  final String? subtitle;
  final String? delta;
  final KpiTileStatus status;
  final double width;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final statusColor = switch (status) {
      KpiTileStatus.normal => semantic.border,
      KpiTileStatus.positive => semantic.success,
      KpiTileStatus.negative => semantic.error,
      KpiTileStatus.warning => semantic.warning,
    };

    return SizedBox(
      width: width,
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: statusColor, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  InfoTooltip(metricKey: metricKey),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (delta != null) ...[
                const SizedBox(height: 6),
                Text(
                  delta!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
