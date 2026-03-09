import 'scenario_snapshot.dart';

class DiffItem {
  const DiffItem({
    required this.section,
    required this.fieldKey,
    required this.before,
    required this.after,
    required this.changeType,
  });

  final String section;
  final String fieldKey;
  final Object? before;
  final Object? after;
  final String changeType;
}

class ScenarioDiff {
  const ScenarioDiff();

  List<DiffItem> computeDiff(ScenarioSnapshot a, ScenarioSnapshot b) {
    final left = _flatten(a.toCanonicalMap());
    final right = _flatten(b.toCanonicalMap());
    final keys = <String>{...left.keys, ...right.keys}.toList()..sort();

    final changes = <DiffItem>[];
    for (final key in keys) {
      final before = left[key];
      final after = right[key];
      if (_equals(before, after)) {
        continue;
      }
      final changeType = _changeType(before, after);
      changes.add(
        DiffItem(
          section: _mapSection(key),
          fieldKey: key,
          before: before,
          after: after,
          changeType: changeType,
        ),
      );
    }
    return changes..sort((x, y) {
      final sectionCompare = x.section.compareTo(y.section);
      if (sectionCompare != 0) {
        return sectionCompare;
      }
      return x.fieldKey.compareTo(y.fieldKey);
    });
  }

  Map<String, Object?> _flatten(
    Map<String, Object?> source, {
    String prefix = '',
  }) {
    final out = <String, Object?>{};
    final keys = source.keys.toList()..sort();
    for (final key in keys) {
      final value = source[key];
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, Object?>) {
        out.addAll(_flatten(value, prefix: path));
        continue;
      }
      if (value is List) {
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          final itemPath = '$path[$i]';
          if (item is Map<String, Object?>) {
            out.addAll(_flatten(item, prefix: itemPath));
          } else {
            out[itemPath] = item;
          }
        }
        continue;
      }
      out[path] = value;
    }
    return out;
  }

  bool _equals(Object? a, Object? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a is num && b is num) {
      return a.toDouble() == b.toDouble();
    }
    return a == b;
  }

  String _changeType(Object? before, Object? after) {
    if (before == null && after != null) {
      return 'added';
    }
    if (before != null && after == null) {
      return 'removed';
    }
    return 'changed';
  }

  String _mapSection(String key) {
    if (key.startsWith('inputs.purchase_price') ||
        key.startsWith('inputs.rehab_budget') ||
        key.startsWith('inputs.closing_cost_buy_') ||
        key.startsWith('inputs.hold_months')) {
      return 'Acquisition';
    }
    if (key.startsWith('inputs.financing_mode') ||
        key.startsWith('inputs.down_payment_percent') ||
        key.startsWith('inputs.loan_amount') ||
        key.startsWith('inputs.interest_rate_percent') ||
        key.startsWith('inputs.term_years') ||
        key.startsWith('inputs.amortization_type')) {
      return 'Financing';
    }
    if (key.startsWith('inputs.rent_') ||
        key.startsWith('inputs.other_income_') ||
        key.startsWith('inputs.vacancy_percent') ||
        key.startsWith('income_lines[')) {
      return 'Income';
    }
    if (key.startsWith('inputs.property_tax_') ||
        key.startsWith('inputs.insurance_') ||
        key.startsWith('inputs.utilities_') ||
        key.startsWith('inputs.hoa_') ||
        key.startsWith('inputs.management_percent') ||
        key.startsWith('inputs.maintenance_percent') ||
        key.startsWith('inputs.capex_percent') ||
        key.startsWith('inputs.other_expenses_') ||
        key.startsWith('expense_lines[')) {
      return 'Expenses';
    }
    if (key.startsWith('inputs.appreciation_percent') ||
        key.startsWith('inputs.rent_growth_percent') ||
        key.startsWith('inputs.expense_growth_percent') ||
        key.startsWith('inputs.sell_after_years')) {
      return 'Projections';
    }
    if (key.startsWith('valuation.') ||
        key.startsWith('inputs.sale_cost_percent') ||
        key.startsWith('inputs.closing_cost_sell_percent')) {
      return 'Exit';
    }
    return 'General';
  }
}
