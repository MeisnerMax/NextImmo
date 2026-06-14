import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/property.dart';
import '../../core/models/property_creation.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/property_repo.dart';
import 'app_state.dart';

class PropertiesController
    extends AutoDisposeAsyncNotifier<List<PropertyRecord>> {
  @override
  Future<List<PropertyRecord>> build() async {
    return _repo.list(includeArchived: true);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.list(includeArchived: true));
  }

  Future<PropertyRecord?> createPropertyWithBaseScenario({
    required String name,
    required String address,
    required String city,
    required String zip,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
    required String strategyType,
    required double purchasePrice,
    required double rentMonthly,
    required double rehabBudget,
    required String financingMode,
  }) async {
    final result = await createPropertyWithBaseScenarioResult(
      name: name,
      address: address,
      city: city,
      zip: zip,
      country: country,
      propertyType: propertyType,
      units: units,
      sqft: sqft,
      yearBuilt: yearBuilt,
      notes: notes,
      strategyType: strategyType,
      purchasePrice: purchasePrice,
      rentMonthly: rentMonthly,
      rehabBudget: rehabBudget,
      financingMode: financingMode,
    );
    return result?.property;
  }

  Future<PropertyCreateResult?> createPropertyWithBaseScenarioResult({
    required String name,
    required String address,
    required String city,
    required String zip,
    required String country,
    required String propertyType,
    required int units,
    double? sqft,
    int? yearBuilt,
    String? notes,
    required String strategyType,
    required double purchasePrice,
    required double rentMonthly,
    required double rehabBudget,
    required String financingMode,
  }) async {
    try {
      final settings = await _inputsRepo.getSettings();
      final result = await _repo.createWithBaseScenario(
        name: name,
        addressLine1: address,
        zip: zip,
        city: city,
        country: country,
        propertyType: propertyType,
        units: units,
        sqft: sqft,
        yearBuilt: yearBuilt,
        notes: notes,
        strategyType: strategyType,
        settings: settings,
        purchasePrice: purchasePrice,
        rentMonthly: rentMonthly,
        rehabBudget: rehabBudget,
        financingMode: financingMode,
      );
      final property = result.property;
      await ref.read(valuationDataRepositoryProvider).createPropertySnapshot(
        scenarioId: result.scenario.id,
        propertyId: property.id,
      );

      final current = state.valueOrNull ?? <PropertyRecord>[];
      state = AsyncValue.data(<PropertyRecord>[property, ...current]);
      return result;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<void> updateProperty(PropertyRecord property) async {
    await _repo.update(property);
    await reload();
  }

  Future<PropertyRecord?> createPropertyFromDraft({
    required PropertyCreationDraft draft,
    required PropertyCreationAssessment assessment,
  }) async {
    try {
      final settings = await _inputsRepo.getSettings();
      final result = await _repo.createFromOnboardingDraft(
        draft: draft,
        assessment: assessment,
        settings: settings,
      );
      final scenario = result.scenario;
      if (scenario != null) {
        await ref.read(valuationDataRepositoryProvider).createPropertySnapshot(
          scenarioId: scenario.id,
          propertyId: result.property.id,
        );
      }

      final current = state.valueOrNull ?? <PropertyRecord>[];
      state = AsyncValue.data(<PropertyRecord>[result.property, ...current]);
      return result.property;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<void> archive(String propertyId, bool archived) async {
    await _repo.archive(propertyId, archived: archived);
    await reload();
  }

  Future<void> deletePermanently(String propertyId) async {
    await _repo.deletePermanently(propertyId);
    final selectedPropertyId = ref.read(selectedPropertyIdProvider);
    if (selectedPropertyId == propertyId) {
      ref.read(selectedScenarioIdProvider.notifier).state = null;
      ref.read(selectedPropertyIdProvider.notifier).state = null;
      ref.read(propertyDetailPageProvider.notifier).state =
          PropertyDetailPage.overview;
    }
    await reload();
  }

  PropertyRepository get _repo => ref.read(propertyRepositoryProvider);
  InputsRepository get _inputsRepo => ref.read(inputsRepositoryProvider);
}

final propertiesControllerProvider = AutoDisposeAsyncNotifierProvider<
  PropertiesController,
  List<PropertyRecord>
>(PropertiesController.new);
