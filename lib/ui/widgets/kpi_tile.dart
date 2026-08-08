import 'package:flutter/material.dart';

import '../components/nx_kpi_tile.dart';
import '../theme/app_theme.dart';
import 'info_tooltip.dart';

enum KpiTileStatus { normal, positive, negative, warning }

/// Metric tile with a mandatory explanation tooltip.
///
/// Thin wrapper over [NxKpiTile] — it exists only to map [KpiTileStatus] onto
/// a semantic colour and to attach the [InfoTooltip] that every derived
/// financial figure is required to carry. It used to be the third independent
/// implementation of this tile (fixed 240px, Material `Card`, a status colour
/// on a 3px left border rather than the shared status dot); the visual
/// contract now lives in one place.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.title,
    required this.value,
    required this.metricKey,
    this.subtitle,
    this.delta,
    this.status = KpiTileStatus.normal,
    this.width,
  });

  final String title;
  final String value;
  final String metricKey;
  final String? subtitle;
  final String? delta;
  final KpiTileStatus status;

  /// Optional fixed width. Prefer leaving this null and letting [NxKpiRow]
  /// distribute the tiles — a fixed width in a `Wrap` is what left KPI bands
  /// stranded in the left third of the page.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final statusColor = switch (status) {
      KpiTileStatus.normal => null,
      KpiTileStatus.positive => semantic.success,
      KpiTileStatus.negative => semantic.error,
      KpiTileStatus.warning => semantic.warning,
    };

    final tile = NxKpiTile(
      label: title,
      value: value,
      caption: subtitle,
      status: statusColor,
      delta: delta,
      trailing: InfoTooltip(metricKey: metricKey),
    );

    return width == null ? tile : SizedBox(width: width, child: tile);
  }
}
