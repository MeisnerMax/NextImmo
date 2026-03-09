import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/inputs.dart';
import '../models/scenario_valuation.dart';

class ScenarioSnapshot {
  const ScenarioSnapshot({
    required this.scenarioId,
    required this.inputs,
    required this.incomeLines,
    required this.expenseLines,
    required this.valuation,
  });

  final String scenarioId;
  final ScenarioInputs inputs;
  final List<IncomeLine> incomeLines;
  final List<ExpenseLine> expenseLines;
  final ScenarioValuationRecord valuation;

  Map<String, Object?> toCanonicalMap() {
    final sortedIncome = incomeLines.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    final sortedExpense = expenseLines.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));

    return _sortMap(<String, Object?>{
      'scenario_id': scenarioId,
      'inputs': inputs.toMap(),
      'income_lines': sortedIncome.map((line) => line.toMap()).toList(),
      'expense_lines': sortedExpense.map((line) => line.toMap()).toList(),
      'valuation': valuation.toMap(),
    });
  }

  String toCanonicalJson() {
    return jsonEncode(toCanonicalMap());
  }

  String computeHash() {
    return sha256.convert(utf8.encode(toCanonicalJson())).toString();
  }

  factory ScenarioSnapshot.fromCanonicalMap(Map<String, Object?> map) {
    final rawIncome = (map['income_lines'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => IncomeLine.fromMap(
            row.map((k, v) => MapEntry<String, Object?>(k, v)),
          ),
        )
        .toList(growable: false);
    final rawExpense = (map['expense_lines'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => ExpenseLine.fromMap(
            row.map((k, v) => MapEntry<String, Object?>(k, v)),
          ),
        )
        .toList(growable: false);
    final inputsMap = (map['inputs'] as Map<String, dynamic>).map(
      (k, v) => MapEntry<String, Object?>(k, v),
    );
    final valuationMap = (map['valuation'] as Map<String, dynamic>).map(
      (k, v) => MapEntry<String, Object?>(k, v),
    );
    return ScenarioSnapshot(
      scenarioId: map['scenario_id']! as String,
      inputs: ScenarioInputs.fromMap(inputsMap),
      incomeLines: rawIncome,
      expenseLines: rawExpense,
      valuation: ScenarioValuationRecord.fromMap(valuationMap),
    );
  }
}

Map<String, Object?> _sortMap(Map<String, Object?> input) {
  final keys = input.keys.toList()..sort();
  final sorted = <String, Object?>{};
  for (final key in keys) {
    final value = input[key];
    if (value is Map<String, Object?>) {
      sorted[key] = _sortMap(value);
      continue;
    }
    if (value is Map<String, dynamic>) {
      sorted[key] = _sortMap(
        value.map((k, v) => MapEntry<String, Object?>(k, v)),
      );
      continue;
    }
    if (value is List) {
      sorted[key] = value
          .map((entry) {
            if (entry is Map<String, Object?>) {
              return _sortMap(entry);
            }
            if (entry is Map<String, dynamic>) {
              return _sortMap(
                entry.map((k, v) => MapEntry<String, Object?>(k, v)),
              );
            }
            return entry;
          })
          .toList(growable: false);
      continue;
    }
    sorted[key] = value;
  }
  return sorted;
}
