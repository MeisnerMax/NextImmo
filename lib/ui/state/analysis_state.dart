import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/criteria/criteria_engine.dart';
import '../../core/engine/analysis_engine.dart';
import '../../core/models/analysis_result.dart';
import '../../core/models/criteria.dart';
import '../../core/models/inputs.dart';
import '../../core/models/scenario_valuation.dart';
import '../../core/models/settings.dart';
import '../../data/repositories/criteria_repo.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/scenario_version_repo.dart';
import '../../data/repositories/scenario_valuation_repo.dart';
import '../../data/repositories/scenario_repo.dart';
import 'app_state.dart';

class ScenarioAnalysisState {
  const ScenarioAnalysisState({
    required this.propertyId,
    required this.settings,
    required this.inputs,
    required this.valuation,
    required this.incomeLines,
    required this.expenseLines,
    required this.analysis,
    required this.criteria,
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.lastSavedAt,
    required this.dirtyFields,
    required this.saveError,
  });

  final String? propertyId;
  final AppSettingsRecord settings;
  final ScenarioInputs inputs;
  final ScenarioValuationRecord valuation;
  final List<IncomeLine> incomeLines;
  final List<ExpenseLine> expenseLines;
  final AnalysisResult analysis;
  final CriteriaEvaluationResult? criteria;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final int? lastSavedAt;
  final Set<String> dirtyFields;
  final String? saveError;

  ScenarioAnalysisState copyWith({
    String? propertyId,
    bool keepPropertyId = true,
    AppSettingsRecord? settings,
    ScenarioInputs? inputs,
    ScenarioValuationRecord? valuation,
    List<IncomeLine>? incomeLines,
    List<ExpenseLine>? expenseLines,
    AnalysisResult? analysis,
    CriteriaEvaluationResult? criteria,
    bool clearCriteria = false,
    bool? isSaving,
    bool? hasUnsavedChanges,
    int? lastSavedAt,
    Set<String>? dirtyFields,
    String? saveError,
    bool clearSaveError = false,
  }) {
    return ScenarioAnalysisState(
      propertyId: keepPropertyId ? (propertyId ?? this.propertyId) : propertyId,
      settings: settings ?? this.settings,
      inputs: inputs ?? this.inputs,
      valuation: valuation ?? this.valuation,
      incomeLines: incomeLines ?? this.incomeLines,
      expenseLines: expenseLines ?? this.expenseLines,
      analysis: analysis ?? this.analysis,
      criteria: clearCriteria ? null : (criteria ?? this.criteria),
      isSaving: isSaving ?? this.isSaving,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      dirtyFields: dirtyFields ?? this.dirtyFields,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}

final scenarioAnalysisControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      ScenarioAnalysisController,
      ScenarioAnalysisState,
      String
    >(ScenarioAnalysisController.new);

class ScenarioAnalysisController
    extends AutoDisposeFamilyAsyncNotifier<ScenarioAnalysisState, String> {
  Timer? _debounce;

  @override
  Future<ScenarioAnalysisState> build(String scenarioId) async {
    ref.onDispose(() {
      _debounce?.cancel();
      if (state.valueOrNull?.hasUnsavedChanges ?? false) {
        unawaited(flushPendingSave());
      }
    });

    final scenario = await _scenarioRepo.getById(scenarioId);
    final settings = await _inputsRepo.getSettings();
    final inputs = await _inputsRepo.getInputs(
      scenarioId: scenarioId,
      settings: settings,
    );
    final valuation = await _valuationRepo.getForScenario(scenarioId);
    final incomeLines = await _inputsRepo.listIncomeLines(scenarioId);
    final expenseLines = await _inputsRepo.listExpenseLines(scenarioId);

    final analysis = _analysisEngine.run(
      inputs: inputs,
      settings: settings,
      incomeLines: incomeLines,
      expenseLines: expenseLines,
      valuation: valuation,
    );

    final criteria = await _evaluateCriteria(
      propertyId: scenario?.propertyId,
      inputs: inputs,
      analysis: analysis,
    );

    return ScenarioAnalysisState(
      propertyId: scenario?.propertyId,
      settings: settings,
      inputs: inputs,
      valuation: valuation,
      incomeLines: incomeLines,
      expenseLines: expenseLines,
      analysis: analysis,
      criteria: criteria,
      isSaving: false,
      hasUnsavedChanges: false,
      lastSavedAt: _maxTimestamp(inputs.updatedAt, valuation.updatedAt),
      dirtyFields: const <String>{},
      saveError: null,
    );
  }

  void patchInputs(
    ScenarioInputs Function(ScenarioInputs current) updateFn, {
    Iterable<String> dirtyFields = const <String>[],
  }) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final updatedInputs = updateFn(
      current.inputs,
    ).copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);

    final analysis = _analysisEngine.run(
      inputs: updatedInputs,
      settings: current.settings,
      incomeLines: current.incomeLines,
      expenseLines: current.expenseLines,
      valuation: current.valuation,
    );

    final criteria =
        current.criteria == null
            ? null
            : _criteriaEngine.evaluate(
              rules: current.criteria!.evaluations.map((e) => e.rule).toList(),
              analysis: analysis,
              inputs: updatedInputs,
            );

    state = AsyncValue.data(
      current.copyWith(
        inputs: updatedInputs,
        analysis: analysis,
        criteria: criteria,
        isSaving: false,
        hasUnsavedChanges: true,
        dirtyFields: {...current.dirtyFields, ...dirtyFields},
        clearSaveError: true,
      ),
    );

    _schedulePersist();
  }

  Future<void> reload() async {
    await flushPendingSave();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> addIncomeLine({
    required String name,
    required double amountMonthly,
  }) async {
    await flushPendingSave();
    await _inputsRepo.addIncomeLine(
      scenarioId: arg,
      name: name,
      amountMonthly: amountMonthly,
    );
    await reload();
  }

  Future<void> addExpenseLine({
    required String name,
    required String kind,
    required double amountMonthly,
    required double percent,
  }) async {
    await flushPendingSave();
    await _inputsRepo.addExpenseLine(
      scenarioId: arg,
      name: name,
      kind: kind,
      amountMonthly: amountMonthly,
      percent: percent,
    );
    await reload();
  }

  Future<void> updateIncomeLine(IncomeLine line) async {
    await _inputsRepo.updateIncomeLine(line);
    await reload();
  }

  Future<void> updateExpenseLine(ExpenseLine line) async {
    await _inputsRepo.updateExpenseLine(line);
    await reload();
  }

  Future<void> setIncomeLineEnabled(String id, bool enabled) async {
    await _inputsRepo.setIncomeLineEnabled(id, enabled);
    await reload();
  }

  Future<void> setExpenseLineEnabled(String id, bool enabled) async {
    await _inputsRepo.setExpenseLineEnabled(id, enabled);
    await reload();
  }

  Future<void> deleteIncomeLine(String id) async {
    await _inputsRepo.deleteIncomeLine(id);
    await reload();
  }

  Future<void> deleteExpenseLine(String id) async {
    await _inputsRepo.deleteExpenseLine(id);
    await reload();
  }

  Future<void> applyCurrentSettingsDefaults() async {
    await flushPendingSave();
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final settings = await _inputsRepo.getSettings();
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedInputs = current.inputs.copyWith(
      closingCostBuyPercent: settings.defaultClosingCostBuyPercent,
      vacancyPercent: settings.defaultVacancyPercent,
      managementPercent: settings.defaultManagementPercent,
      maintenancePercent: settings.defaultMaintenancePercent,
      capexPercent: settings.defaultCapexPercent,
      downPaymentPercent: settings.defaultDownPaymentPercent,
      interestRatePercent: settings.defaultInterestRatePercent,
      termYears: settings.defaultTermYears,
      appreciationPercent: settings.defaultAppreciationPercent,
      rentGrowthPercent: settings.defaultRentGrowthPercent,
      expenseGrowthPercent: settings.defaultExpenseGrowthPercent,
      saleCostPercent: settings.defaultSaleCostPercent,
      closingCostSellPercent: settings.defaultClosingCostSellPercent,
      sellAfterYears: settings.defaultHorizonYears,
      updatedAt: now,
    );

    final analysis = _analysisEngine.run(
      inputs: updatedInputs,
      settings: settings,
      incomeLines: current.incomeLines,
      expenseLines: current.expenseLines,
      valuation: current.valuation,
    );
    final criteria = await _evaluateCriteria(
      propertyId: current.propertyId,
      inputs: updatedInputs,
      analysis: analysis,
    );

    await _inputsRepo.upsertInputs(updatedInputs);
    state = AsyncValue.data(
      current.copyWith(
        settings: settings,
        inputs: updatedInputs,
        valuation: current.valuation,
        analysis: analysis,
        criteria: criteria,
        isSaving: false,
        hasUnsavedChanges: false,
        lastSavedAt: now,
        dirtyFields: const <String>{},
        clearSaveError: true,
      ),
    );
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_persistCurrentState());
    });
  }

  Future<void> flushPendingSave() async {
    _debounce?.cancel();
    _debounce = null;
    await _persistCurrentState();
  }

  Future<void> _persistCurrentState() async {
    final current = state.valueOrNull;
    if (current == null || current.isSaving || !current.hasUnsavedChanges) {
      return;
    }

    try {
      state = AsyncValue.data(current.copyWith(isSaving: true));
      await _inputsRepo.upsertInputs(current.inputs);
      await _valuationRepo.upsert(current.valuation);
      await _maybeCreateAutoDailyVersion(current);
      final refreshedCriteria = await _evaluateCriteria(
        propertyId: current.propertyId,
        inputs: current.inputs,
        analysis: current.analysis,
      );
      final latest = state.valueOrNull;
      final savedAt = DateTime.now().millisecondsSinceEpoch;
      if (latest == null) {
        return;
      }
      if (!_isSameSnapshot(current, latest)) {
        state = AsyncValue.data(
          latest.copyWith(isSaving: false, lastSavedAt: savedAt),
        );
        return;
      }
      state = AsyncValue.data(
        current.copyWith(
          isSaving: false,
          hasUnsavedChanges: false,
          lastSavedAt: savedAt,
          dirtyFields: const <String>{},
          criteria: refreshedCriteria,
          clearSaveError: true,
        ),
      );
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncValue.data(
        latest.copyWith(
          isSaving: false,
          hasUnsavedChanges: true,
          saveError: 'Autosave failed: $error',
        ),
      );
    }
  }

  void patchValuation(
    ScenarioValuationRecord Function(ScenarioValuationRecord current)
    updateFn, {
    Iterable<String> dirtyFields = const <String>[],
  }) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final updatedValuation = updateFn(
      current.valuation,
    ).copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);

    final analysis = _analysisEngine.run(
      inputs: current.inputs,
      settings: current.settings,
      incomeLines: current.incomeLines,
      expenseLines: current.expenseLines,
      valuation: updatedValuation,
    );

    final criteria =
        current.criteria == null
            ? null
            : _criteriaEngine.evaluate(
              rules: current.criteria!.evaluations.map((e) => e.rule).toList(),
              analysis: analysis,
              inputs: current.inputs,
            );

    state = AsyncValue.data(
      current.copyWith(
        valuation: updatedValuation,
        analysis: analysis,
        criteria: criteria,
        isSaving: false,
        hasUnsavedChanges: true,
        dirtyFields: {...current.dirtyFields, ...dirtyFields},
        clearSaveError: true,
      ),
    );
    _schedulePersist();
  }

  Future<CriteriaEvaluationResult?> _evaluateCriteria({
    required String? propertyId,
    required ScenarioInputs inputs,
    required AnalysisResult analysis,
  }) async {
    String? criteriaSetId;
    if (propertyId != null) {
      criteriaSetId = await _criteriaRepo.getPropertyOverride(propertyId);
    }

    if (criteriaSetId == null) {
      final set = await _criteriaRepo.getDefaultSet();
      criteriaSetId = set?.id;
    }

    if (criteriaSetId == null) {
      return null;
    }

    final rules = await _criteriaRepo.listRules(criteriaSetId);
    if (rules.isEmpty) {
      return null;
    }
    return _criteriaEngine.evaluate(
      rules: rules,
      analysis: analysis,
      inputs: inputs,
    );
  }

  InputsRepository get _inputsRepo => ref.read(inputsRepositoryProvider);
  CriteriaRepository get _criteriaRepo => ref.read(criteriaRepositoryProvider);
  ScenarioRepository get _scenarioRepo => ref.read(scenarioRepositoryProvider);
  ScenarioVersionRepo get _scenarioVersionRepo =>
      ref.read(scenarioVersionRepositoryProvider);
  ScenarioValuationRepo get _valuationRepo =>
      ref.read(scenarioValuationRepositoryProvider);
  AnalysisEngine get _analysisEngine => ref.read(analysisEngineProvider);
  CriteriaEngine get _criteriaEngine => ref.read(criteriaEngineProvider);

  Future<void> _maybeCreateAutoDailyVersion(
    ScenarioAnalysisState current,
  ) async {
    if (!current.settings.scenarioAutoDailyVersionsEnabled) {
      return;
    }
    final now = DateTime.now();
    final label =
        'Auto Daily ${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final versions = await _scenarioVersionRepo.listVersions(arg);
    if (versions.any((v) => v.label == label)) {
      return;
    }
    await _scenarioVersionRepo.saveVersion(
      scenarioId: arg,
      label: label,
      notes: 'Automatic daily snapshot from autosave.',
      createdBy: current.settings.scenarioAutoDailyVersionsUserId,
    );
  }

  bool _isSameSnapshot(
    ScenarioAnalysisState left,
    ScenarioAnalysisState right,
  ) {
    return left.inputs.updatedAt == right.inputs.updatedAt &&
        left.valuation.updatedAt == right.valuation.updatedAt;
  }

  int _maxTimestamp(int left, int right) {
    return left >= right ? left : right;
  }
}
