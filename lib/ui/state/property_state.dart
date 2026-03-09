import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/property.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/property_repo.dart';
import 'app_state.dart';

class PropertiesController
    extends AutoDisposeAsyncNotifier<List<PropertyRecord>> {
  @override
  Future<List<PropertyRecord>> build() async {
    return _repo.list();
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.list());
  }

  Future<PropertyRecord?> createPropertyWithBaseScenario({
    required String name,
    required String address,
    required String city,
    required String zip,
    required String country,
    required String propertyType,
    required int units,
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
        strategyType: strategyType,
        settings: settings,
        purchasePrice: purchasePrice,
        rentMonthly: rentMonthly,
        rehabBudget: rehabBudget,
        financingMode: financingMode,
      );
      final property = result.property;

      final current = state.valueOrNull ?? <PropertyRecord>[];
      state = AsyncValue.data(<PropertyRecord>[property, ...current]);
      return property;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }

  Future<void> archive(String propertyId, bool archived) async {
    await _repo.archive(propertyId, archived: archived);
    await reload();
  }

  PropertyRepository get _repo => ref.read(propertyRepositoryProvider);
  InputsRepository get _inputsRepo => ref.read(inputsRepositoryProvider);
}

final propertiesControllerProvider = AutoDisposeAsyncNotifierProvider<
  PropertiesController,
  List<PropertyRecord>
>(PropertiesController.new);
