import 'package:flutter/material.dart';

import '../docs/metric_definitions.dart';
import 'kpi_tile.dart';

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final key = MetricDefinitions.normalizeKey(label);
    final definition =
        MetricDefinitions.byKey(context, key) ??
        MetricDefinitions.fallback(context, label);
    return KpiTile(
      title: definition.title,
      value: value,
      subtitle: subtitle,
      metricKey: key,
    );
  }
}
