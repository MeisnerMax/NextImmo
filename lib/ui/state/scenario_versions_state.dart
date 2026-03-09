import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/scenario_version.dart';
import '../../core/versioning/scenario_diff.dart';
import '../../data/repositories/scenario_version_repo.dart';
import 'analysis_state.dart';
import 'app_state.dart';

class ScenarioVersionsState {
  const ScenarioVersionsState({
    required this.versions,
    required this.diff,
    required this.showArchived,
    required this.isBusy,
    required this.error,
  });

  final List<ScenarioVersionRecord> versions;
  final List<DiffItem> diff;
  final bool showArchived;
  final bool isBusy;
  final String? error;

  ScenarioVersionsState copyWith({
    List<ScenarioVersionRecord>? versions,
    List<DiffItem>? diff,
    bool? showArchived,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) {
    return ScenarioVersionsState(
      versions: versions ?? this.versions,
      diff: diff ?? this.diff,
      showArchived: showArchived ?? this.showArchived,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final scenarioVersionsControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      ScenarioVersionsController,
      ScenarioVersionsState,
      String
    >(ScenarioVersionsController.new);

class ScenarioVersionsController
    extends AutoDisposeFamilyAsyncNotifier<ScenarioVersionsState, String> {
  @override
  Future<ScenarioVersionsState> build(String scenarioId) async {
    final versions = await _repo.listVersions(scenarioId);
    return ScenarioVersionsState(
      versions: versions,
      diff: const <DiffItem>[],
      showArchived: false,
      isBusy: false,
      error: null,
    );
  }

  Future<void> reload() async {
    final current = state.valueOrNull;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final versions = await _repo.listVersions(arg);
      return (current ??
              const ScenarioVersionsState(
                versions: <ScenarioVersionRecord>[],
                diff: <DiffItem>[],
                showArchived: false,
                isBusy: false,
                error: null,
              ))
          .copyWith(versions: versions, isBusy: false, clearError: true);
    });
  }

  Future<void> saveVersion({
    required String label,
    String? notes,
    String? createdBy,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      await _repo.saveVersion(
        scenarioId: arg,
        label: label,
        notes: notes,
        createdBy: createdBy,
      );
      final versions = await _repo.listVersions(arg);
      state = AsyncValue.data(
        current.copyWith(versions: versions, isBusy: false, clearError: true),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  Future<void> compareVersions(String versionAId, String versionBId) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      final diff = await _repo.diffVersions(versionAId, versionBId);
      state = AsyncValue.data(
        current.copyWith(diff: diff, isBusy: false, clearError: true),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  Future<void> rollbackToVersion({
    required String versionId,
    String? rollbackBy,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      await _repo.rollbackToVersion(
        scenarioId: arg,
        versionId: versionId,
        rollbackBy: rollbackBy,
      );
      await ref
          .read(auditLogRepositoryProvider)
          .recordEvent(
            entityType: 'scenario',
            entityId: arg,
            action: 'rollback',
            summary: 'Scenario rolled back to version $versionId',
            source: 'ui',
          );
      await ref.read(scenarioAnalysisControllerProvider(arg).notifier).reload();
      final versions = await _repo.listVersions(arg);
      state = AsyncValue.data(
        current.copyWith(
          versions: versions,
          diff: const <DiffItem>[],
          isBusy: false,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  Future<void> renameVersion({
    required String versionId,
    required String label,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      await _repo.updateVersionMetadata(versionId: versionId, label: label);
      final versions = await _repo.listVersions(arg);
      state = AsyncValue.data(
        current.copyWith(versions: versions, isBusy: false, clearError: true),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  Future<void> updateVersionNotes({
    required String versionId,
    required String? notes,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      await _repo.updateVersionMetadata(versionId: versionId, notes: notes);
      final versions = await _repo.listVersions(arg);
      state = AsyncValue.data(
        current.copyWith(versions: versions, isBusy: false, clearError: true),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  Future<void> setVersionArchived({
    required String versionId,
    required bool archived,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isBusy: true, clearError: true));
    try {
      await _repo.setArchived(versionId: versionId, archived: archived);
      final versions = await _repo.listVersions(arg);
      state = AsyncValue.data(
        current.copyWith(versions: versions, isBusy: false, clearError: true),
      );
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(isBusy: false, error: error.toString()),
      );
    }
  }

  void toggleShowArchived(bool value) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(showArchived: value));
  }

  ScenarioVersionRepo get _repo => ref.read(scenarioVersionRepositoryProvider);
}
