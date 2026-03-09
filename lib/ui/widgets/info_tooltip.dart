import 'package:flutter/material.dart';

import '../docs/metric_definitions.dart';
import '../theme/app_theme.dart';

class InfoTooltip extends StatelessWidget {
  const InfoTooltip({
    super.key,
    required this.metricKey,
    this.size = 16,
    this.showDialogOnTap = true,
  });

  final String metricKey;
  final double size;
  final bool showDialogOnTap;

  @override
  Widget build(BuildContext context) {
    final definition =
        MetricDefinitions.byKey(metricKey) ??
        MetricDefinitions.fallback(metricKey);
    final semantic = context.semanticColors;

    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: semantic.border),
      ),
      alignment: Alignment.center,
      child: Text(
        'i',
        style: TextStyle(
          color: semantic.textSecondary,
          fontSize: size * 0.65,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );

    final wrapped = Tooltip(
      waitDuration: const Duration(milliseconds: 250),
      message: definition.description,
      child: icon,
    );

    if (!showDialogOnTap) {
      return wrapped;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: () {
        showDialog<void>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(definition.title),
                content: Text(definition.description),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      },
      child: wrapped,
    );
  }
}
