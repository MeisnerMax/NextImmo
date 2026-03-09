import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/inputs.dart';
import '../../core/models/scenario.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/scenario_repo.dart';
import 'app_state.dart';

final scenariosByPropertyProvider = AutoDisposeAsyncNotifierProviderFamily<
  ScenariosByPropertyController,
  List<ScenarioRecord>,
  String
>(ScenariosByPropertyController.new);

class ScenariosByPropertyController
    extends AutoDisposeFamilyAsyncNotifier<List<ScenarioRecord>, String> {
  @override
  Future<List<ScenarioRecord>> build(String propertyId) async {
    return _repo.listByProperty(propertyId);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.listByProperty(arg));
  }

  Future<ScenarioRecord?> create({
    required String name,
    required String strategyType,
  }) async {
    try {
      final scenario = await _repo.create(
        propertyId: arg,
        name: name,
        strategyType: strategyType,
      );

      final settings = await _inputsRepo.getSettings();
      final inputs = ScenarioInputs.defaults(
        scenarioId: scenario.id,
        settings: settings,
      );
      await _inputsRepo.upsertInputs(inputs);

      final current = state.valueOrNull ?? <ScenarioRecord>[];
      state = AsyncValue.data(<ScenarioRecord>[scenario, ...current]);
      return scenario;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<ScenarioRecord?> duplicate({
    required ScenarioRecord source,
    required String newName,
  }) async {
    final duplicated = await _repo.duplicate(source: source, newName: newName);
    await reload();
    return duplicated;
  }

  Future<void> rename(String id, String newName) async {
    await _repo.rename(id, newName);
    await reload();
  }

  Future<void> submitForReview({
    required String scenarioId,
    String? reviewComment,
  }) async {
    await _repo.submitForReview(
      scenarioId: scenarioId,
      reviewComment: reviewComment,
    );
    await reload();
  }

  Future<void> approve({
    required String scenarioId,
    String? reviewComment,
  }) async {
    await _repo.approve(scenarioId: scenarioId, reviewComment: reviewComment);
    await reload();
  }

  Future<void> reject({
    required String scenarioId,
    String? reviewComment,
  }) async {
    await _repo.reject(scenarioId: scenarioId, reviewComment: reviewComment);
    await reload();
  }

  Future<void> archive(String scenarioId) async {
    await _repo.archive(scenarioId);
    await reload();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await reload();
  }

  ScenarioRepository get _repo => ref.read(scenarioRepositoryProvider);
  InputsRepository get _inputsRepo => ref.read(inputsRepositoryProvider);
}
