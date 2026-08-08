import 'package:flutter/material.dart';

import 'package:neximmo_app/ui/components/responsive_constraints.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:neximmo_app/ui/utils/number_parse.dart';

/// Form-field builders bound to a single [onChanged] rebuild callback, replacing
/// the former private `_text`/`_number`/`_dropdown`/... methods on the wizard
/// State. Each setter mutates the draft in place and [onChanged] triggers the
/// parent rebuild — preserving the exact mutate-then-`setState` pattern across
/// the BIG-012 file split.
class CreationFieldFactory {
  const CreationFieldFactory(this.onChanged);

  final VoidCallback onChanged;

  Widget text(
    String label,
    String value,
    ValueChanged<String> setter, {
    int maxLines = 1,
  }) {
    return TextFormField(
      initialValue: value,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        setter(v);
        onChanged();
      },
    );
  }

  Widget number(String label, double? value, ValueChanged<double?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : trimCreationNumber(value),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        setter(parseDoubleFlexible(v));
        onChanged();
      },
    );
  }

  Widget intField(String label, int? value, ValueChanged<int?> setter) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        setter(parseIntFlexible(v));
        onChanged();
      },
    );
  }

  Widget date(String label, int? value, ValueChanged<int?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : formatCreationDate(value),
      decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
      onChanged: (v) {
        setter(parseCreationDate(v));
        onChanged();
      },
    );
  }

  Widget dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onSelected,
  }) {
    return DropdownButtonFormField<String>(
      value: items.containsKey(value) ? value : items.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v == null) {
          return;
        }
        onSelected(v);
        onChanged();
      },
    );
  }

  Widget condition(String label, String value, ValueChanged<String> setter) {
    return dropdown(
      label: label,
      value: value,
      items: const {
        'very_good': 'Sehr gut',
        'good': 'Gut',
        'medium': 'Mittel',
        'poor': 'Schlecht',
        'critical': 'Kritisch',
        'unknown': 'Unbekannt',
      },
      onSelected: setter,
    );
  }

  Widget switchTile(String label, bool value, ValueChanged<bool> setter) {
    return SwitchListTile(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      onChanged: (v) {
        setter(v);
        onChanged();
      },
    );
  }
}

/// Two-column form grid used as an [NxFormSectionCard] body. Two columns at or
/// above 760 logical px, one column below — the exact behaviour of the former
/// private `_twoColumnGrid` on the wizard State.
class CreationFieldGrid extends StatelessWidget {
  const CreationFieldGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            for (final child in children)
              SizedBox(
                width: twoColumns
                    ? (constraints.maxWidth - AppSpacing.component) / 2
                    : constraints.maxWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

/// Responsive fixed-width wrapper for inline fields inside editors and the
/// document checklist (former top-level `_workflowField`).
Widget creationWorkflowField(BuildContext context, Widget child) {
  return SizedBox(
    width: ResponsiveConstraints.itemWidth(
      context,
      idealWidth: 220,
      minWidth: 160,
      maxWidth: 280,
    ),
    child: child,
  );
}

String formatCreationCurrency(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${value.toStringAsFixed(value.abs() >= 1000 ? 0 : 2)} EUR';
}

String formatCreationPercent(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${(value * 100).toStringAsFixed(1)}%';
}

String formatCreationSqm(double? value) {
  if (value == null) {
    return 'offen';
  }
  return '${value.toStringAsFixed(1)} qm';
}

String formatCreationNumber(double? value) {
  if (value == null) {
    return 'offen';
  }
  return value.toStringAsFixed(2);
}

String trimCreationNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

String formatCreationDate(int millis) {
  return DateTime.fromMillisecondsSinceEpoch(millis)
      .toIso8601String()
      .substring(0, 10);
}

int? parseCreationDate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day).millisecondsSinceEpoch;
}
