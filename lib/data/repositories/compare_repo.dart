import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/engine/analysis_engine.dart';
import '../../core/models/analysis_result.dart';
import '../../core/models/inputs.dart';
import '../../core/models/property.dart';
import '../../core/models/scenario.dart';
import '../../core/models/scenario_valuation.dart';
import '../../core/models/settings.dart';
import 'inputs_repo.dart';

class CompareScenarioBundle {
  const CompareScenarioBundle({
    required this.property,
    required this.scenario,
    required this.inputs,
    required this.valuation,
    required this.incomeLines,
    required this.expenseLines,
    required this.analysis,
  });

  final PropertyRecord property;
  final ScenarioRecord scenario;
  final ScenarioInputs inputs;
  final ScenarioValuationRecord valuation;
  final List<IncomeLine> incomeLines;
  final List<ExpenseLine> expenseLines;
  final AnalysisResult analysis;
}

class CompareRepo {
  const CompareRepo(this._db, this._inputsRepo, this._analysisEngine);

  final Database _db;
  final InputsRepository _inputsRepo;
  final AnalysisEngine _analysisEngine;

  Future<(AppSettingsRecord, List<CompareScenarioBundle>)> loadScenarioBundles({
    Set<String>? allowedPropertyIds,
  }) async {
    final settings = await _inputsRepo.getSettings();
    final properties = await _loadProperties(allowedPropertyIds: allowedPropertyIds);
    if (properties.isEmpty) {
      return (settings, const <CompareScenarioBundle>[]);
    }

    final propertyIds = properties.map((property) => property.id).toList(growable: false);
    final scenarios = await _loadScenarios(propertyIds);
    if (scenarios.isEmpty) {
      return (settings, const <CompareScenarioBundle>[]);
    }

    final propertyById = <String, PropertyRecord>{
      for (final property in properties) property.id: property,
    };
    final scenarioIds = scenarios.map((scenario) => scenario.id).toList(growable: false);
    final inputsByScenarioId = await _loadInputs(settings, scenarioIds);
    final valuationsByScenarioId = await _loadValuations(scenarioIds);
    final incomeLinesByScenarioId = await _loadIncomeLines(scenarioIds);
    final expenseLinesByScenarioId = await _loadExpenseLines(scenarioIds);

    final bundles = <CompareScenarioBundle>[];
    for (final scenario in scenarios) {
      final property = propertyById[scenario.propertyId];
      if (property == null) {
        continue;
      }
      final inputs = inputsByScenarioId[scenario.id] ??
          ScenarioInputs.defaults(scenarioId: scenario.id, settings: settings);
      final valuation = valuationsByScenarioId[scenario.id] ??
          ScenarioValuationRecord.defaults(scenarioId: scenario.id);
      final incomeLines = incomeLinesByScenarioId[scenario.id] ?? const <IncomeLine>[];
      final expenseLines = expenseLinesByScenarioId[scenario.id] ?? const <ExpenseLine>[];
      final analysis = _analysisEngine.run(
        inputs: inputs,
        settings: settings,
        incomeLines: incomeLines,
        expenseLines: expenseLines,
        valuation: valuation,
      );
      bundles.add(
        CompareScenarioBundle(
          property: property,
          scenario: scenario,
          inputs: inputs,
          valuation: valuation,
          incomeLines: incomeLines,
          expenseLines: expenseLines,
          analysis: analysis,
        ),
      );
    }
    return (settings, bundles);
  }

  Future<List<PropertyRecord>> _loadProperties({
    required Set<String>? allowedPropertyIds,
  }) async {
    final rows = await _db.query(
      'properties',
      where: _buildInWhere(
        baseCondition: 'archived = 0',
        column: 'id',
        values: allowedPropertyIds?.toList(growable: false),
      ),
      whereArgs: allowedPropertyIds?.toList(growable: false),
      orderBy: 'updated_at DESC',
    );
    return rows.map(PropertyRecord.fromMap).toList(growable: false);
  }

  Future<List<ScenarioRecord>> _loadScenarios(List<String> propertyIds) async {
    final rows = await _db.query(
      'scenarios',
      where: _buildInWhere(column: 'property_id', values: propertyIds),
      whereArgs: propertyIds,
      orderBy: 'updated_at DESC',
    );
    return rows.map(ScenarioRecord.fromMap).toList(growable: false);
  }

  Future<Map<String, ScenarioInputs>> _loadInputs(
    AppSettingsRecord settings,
    List<String> scenarioIds,
  ) async {
    final rows = await _db.query(
      'scenario_inputs',
      where: _buildInWhere(column: 'scenario_id', values: scenarioIds),
      whereArgs: scenarioIds,
    );
    final result = <String, ScenarioInputs>{
      for (final row in rows)
        (row['scenario_id']! as String): ScenarioInputs.fromMap(row),
    };
    for (final scenarioId in scenarioIds) {
      result.putIfAbsent(
        scenarioId,
        () => ScenarioInputs.defaults(scenarioId: scenarioId, settings: settings),
      );
    }
    return result;
  }

  Future<Map<String, ScenarioValuationRecord>> _loadValuations(
    List<String> scenarioIds,
  ) async {
    final rows = await _db.query(
      'scenario_valuation',
      where: _buildInWhere(column: 'scenario_id', values: scenarioIds),
      whereArgs: scenarioIds,
    );
    return <String, ScenarioValuationRecord>{
      for (final row in rows)
        (row['scenario_id']! as String): ScenarioValuationRecord.fromMap(row),
    };
  }

  Future<Map<String, List<IncomeLine>>> _loadIncomeLines(List<String> scenarioIds) async {
    final rows = await _db.query(
      'income_lines',
      where: _buildInWhere(column: 'scenario_id', values: scenarioIds),
      whereArgs: scenarioIds,
      orderBy: 'rowid ASC',
    );
    final grouped = <String, List<IncomeLine>>{};
    for (final row in rows) {
      final line = IncomeLine.fromMap(row);
      grouped.putIfAbsent(line.scenarioId, () => <IncomeLine>[]).add(line);
    }
    return grouped;
  }

  Future<Map<String, List<ExpenseLine>>> _loadExpenseLines(List<String> scenarioIds) async {
    final rows = await _db.query(
      'expense_lines',
      where: _buildInWhere(column: 'scenario_id', values: scenarioIds),
      whereArgs: scenarioIds,
      orderBy: 'rowid ASC',
    );
    final grouped = <String, List<ExpenseLine>>{};
    for (final row in rows) {
      final line = ExpenseLine.fromMap(row);
      grouped.putIfAbsent(line.scenarioId, () => <ExpenseLine>[]).add(line);
    }
    return grouped;
  }

  String? _buildInWhere({
    String? baseCondition,
    required String column,
    required List<String>? values,
  }) {
    if (values == null) {
      return baseCondition;
    }
    if (values.isEmpty) {
      return '${baseCondition == null ? '' : '$baseCondition AND '}1 = 0';
    }
    final placeholders = List<String>.filled(values.length, '?').join(',');
    final condition = '$column IN ($placeholders)';
    if (baseCondition == null) {
      return condition;
    }
    return '$baseCondition AND $condition';
  }
}
