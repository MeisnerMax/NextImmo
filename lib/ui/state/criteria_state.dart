import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/criteria.dart';
import '../../data/repositories/criteria_repo.dart';
import 'app_state.dart';

class CriteriaSetsController
    extends AutoDisposeAsyncNotifier<List<CriteriaSet>> {
  @override
  Future<List<CriteriaSet>> build() async {
    return _repo.listSets();
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.listSets());
  }

  Future<CriteriaSet?> createDefaultSet() async {
    final nowName =
        'Default ${DateTime.now().toIso8601String().substring(0, 10)}';
    final set = await _repo.createSet(name: nowName, isDefault: true);
    await _repo.addRule(
      criteriaSetId: set.id,
      fieldKey: 'cash_on_cash',
      operator: 'gte',
      targetValue: 0.12,
      unit: 'percent',
      severity: 'hard',
    );
    await _repo.addRule(
      criteriaSetId: set.id,
      fieldKey: 'cap_rate',
      operator: 'gte',
      targetValue: 0.06,
      unit: 'percent',
      severity: 'soft',
    );
    await reload();
    return set;
  }

  Future<CriteriaSet?> createSet({
    required String name,
    bool isDefault = false,
  }) async {
    final set = await _repo.createSet(name: name, isDefault: isDefault);
    await reload();
    return set;
  }

  Future<void> renameSet({required String setId, required String name}) async {
    await _repo.updateSet(id: setId, name: name);
    await reload();
  }

  Future<void> setDefault(String id) async {
    await _repo.setDefault(id);
    await reload();
  }

  Future<void> deleteSet(String id) async {
    await _repo.deleteSet(id);
    await reload();
  }

  Future<List<CriteriaRule>> listRules(String setId) {
    return _repo.listRules(setId);
  }

  Future<void> addRule({
    required String criteriaSetId,
    required String fieldKey,
    required String operator,
    required double targetValue,
    required String unit,
    required String severity,
    required bool enabled,
  }) async {
    await _repo.addRule(
      criteriaSetId: criteriaSetId,
      fieldKey: fieldKey,
      operator: operator,
      targetValue: targetValue,
      unit: unit,
      severity: severity,
      enabled: enabled,
    );
  }

  Future<void> updateRule(CriteriaRule rule) {
    return _repo.updateRule(rule);
  }

  Future<void> deleteRule(String ruleId) {
    return _repo.deleteRule(ruleId);
  }

  CriteriaRepository get _repo => ref.read(criteriaRepositoryProvider);
}

final criteriaSetsControllerProvider =
    AutoDisposeAsyncNotifierProvider<CriteriaSetsController, List<CriteriaSet>>(
      CriteriaSetsController.new,
    );
