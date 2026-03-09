import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/comps.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/info_tooltip.dart';
import '../../widgets/kpi_tile.dart';

class CompsScreen extends ConsumerStatefulWidget {
  const CompsScreen({
    super.key,
    required this.propertyId,
    required this.scenarioId,
  });

  final String propertyId;
  final String scenarioId;

  @override
  ConsumerState<CompsScreen> createState() => _CompsScreenState();
}

class _CompsScreenState extends ConsumerState<CompsScreen> {
  late Future<List<CompSale>> _salesFuture;
  late Future<List<CompRental>> _rentalsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );
    final analysisController = ref.read(
      scenarioAnalysisControllerProvider(widget.scenarioId).notifier,
    );

    return analysisAsync.when(
      data: (analysisState) {
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [Tab(text: 'Sales Comps'), Tab(text: 'Rental Comps')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSales(analysisState, analysisController),
                    _buildRentals(analysisState, analysisController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildSales(
    ScenarioAnalysisState analysisState,
    ScenarioAnalysisController analysisController,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: FutureBuilder<List<CompSale>>(
        future: _salesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final comps = snapshot.data!;
          final estimate = _estimateSales(comps);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.component,
                children: [
                  ElevatedButton(
                    onPressed: _addSale,
                    child: const Text('Add Sale Comp'),
                  ),
                  OutlinedButton(
                    onPressed: _reloadWithState,
                    child: const Text('Refresh'),
                  ),
                  OutlinedButton(
                    onPressed:
                        estimate == null
                            ? null
                            : () {
                              analysisController.patchInputs(
                                (current) =>
                                    current.copyWith(arvOverride: estimate),
                              );
                            },
                    child: const Text('Apply ARV Estimate'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      analysisController.patchInputs(
                        (current) => current.copyWith(clearArvOverride: true),
                      );
                    },
                    child: const Text('Clear ARV Override'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  KpiTile(
                    title: 'ARV Estimate',
                    value: estimate?.toStringAsFixed(2) ?? 'N/A',
                    metricKey: 'arv_estimate',
                  ),
                  KpiTile(
                    title: 'ARV Override',
                    value:
                        analysisState.inputs.arvOverride?.toStringAsFixed(2) ??
                        'none',
                    metricKey: 'arv_estimate',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child:
                    comps.isEmpty
                        ? const Text('No sales comps yet.')
                        : ListView.builder(
                          itemCount: comps.length,
                          itemBuilder: (context, index) {
                            final comp = comps[index];
                            return Card(
                              child: ListTile(
                                title: Text(comp.address),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      'Price ${comp.price.toStringAsFixed(0)} | Weight ${comp.weight.toStringAsFixed(2)}',
                                    ),
                                    const SizedBox(width: 6),
                                    const InfoTooltip(
                                      metricKey: 'arv_estimate',
                                      size: 14,
                                    ),
                                  ],
                                ),
                                leading: Checkbox(
                                  value: comp.selected,
                                  onChanged: (value) async {
                                    await ref
                                        .read(compsRepositoryProvider)
                                        .updateSale(
                                          id: comp.id,
                                          selected: value ?? false,
                                        );
                                    _reloadWithState();
                                  },
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: () async {
                                        final newWeight = (comp.weight - 0.25)
                                            .clamp(0.25, 10.0);
                                        await ref
                                            .read(compsRepositoryProvider)
                                            .updateSale(
                                              id: comp.id,
                                              weight: newWeight,
                                            );
                                        _reloadWithState();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () async {
                                        final newWeight = (comp.weight + 0.25)
                                            .clamp(0.25, 10.0);
                                        await ref
                                            .read(compsRepositoryProvider)
                                            .updateSale(
                                              id: comp.id,
                                              weight: newWeight,
                                            );
                                        _reloadWithState();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRentals(
    ScenarioAnalysisState analysisState,
    ScenarioAnalysisController analysisController,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: FutureBuilder<List<CompRental>>(
        future: _rentalsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final comps = snapshot.data!;
          final estimate = _estimateRentals(comps);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.component,
                children: [
                  ElevatedButton(
                    onPressed: _addRental,
                    child: const Text('Add Rental Comp'),
                  ),
                  OutlinedButton(
                    onPressed: _reloadWithState,
                    child: const Text('Refresh'),
                  ),
                  OutlinedButton(
                    onPressed:
                        estimate == null
                            ? null
                            : () {
                              analysisController.patchInputs(
                                (current) =>
                                    current.copyWith(rentOverride: estimate),
                              );
                            },
                    child: const Text('Apply Rent Estimate'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      analysisController.patchInputs(
                        (current) => current.copyWith(clearRentOverride: true),
                      );
                    },
                    child: const Text('Clear Rent Override'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  KpiTile(
                    title: 'Rent Estimate',
                    value: estimate?.toStringAsFixed(2) ?? 'N/A',
                    metricKey: 'rent_estimate',
                  ),
                  KpiTile(
                    title: 'Rent Override',
                    value:
                        analysisState.inputs.rentOverride?.toStringAsFixed(2) ??
                        'none',
                    metricKey: 'rent_estimate',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child:
                    comps.isEmpty
                        ? const Text('No rental comps yet.')
                        : ListView.builder(
                          itemCount: comps.length,
                          itemBuilder: (context, index) {
                            final comp = comps[index];
                            return Card(
                              child: ListTile(
                                title: Text(comp.address),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      'Rent ${comp.rentMonthly.toStringAsFixed(0)} | Weight ${comp.weight.toStringAsFixed(2)}',
                                    ),
                                    const SizedBox(width: 6),
                                    const InfoTooltip(
                                      metricKey: 'rent_estimate',
                                      size: 14,
                                    ),
                                  ],
                                ),
                                leading: Checkbox(
                                  value: comp.selected,
                                  onChanged: (value) async {
                                    await ref
                                        .read(compsRepositoryProvider)
                                        .updateRental(
                                          id: comp.id,
                                          selected: value ?? false,
                                        );
                                    _reloadWithState();
                                  },
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: () async {
                                        final newWeight = (comp.weight - 0.25)
                                            .clamp(0.25, 10.0);
                                        await ref
                                            .read(compsRepositoryProvider)
                                            .updateRental(
                                              id: comp.id,
                                              weight: newWeight,
                                            );
                                        _reloadWithState();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () async {
                                        final newWeight = (comp.weight + 0.25)
                                            .clamp(0.25, 10.0);
                                        await ref
                                            .read(compsRepositoryProvider)
                                            .updateRental(
                                              id: comp.id,
                                              weight: newWeight,
                                            );
                                        _reloadWithState();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          );
        },
      ),
    );
  }

  double? _estimateSales(List<CompSale> comps) {
    final selected = comps.where((comp) => comp.selected).toList();
    if (selected.isEmpty) {
      return null;
    }

    final totalWeight = selected.fold<double>(
      0,
      (sum, comp) => sum + comp.weight,
    );
    if (totalWeight <= 0) {
      return null;
    }

    final weightedPrice = selected.fold<double>(
      0,
      (sum, comp) => sum + (comp.price * comp.weight),
    );
    return weightedPrice / totalWeight;
  }

  double? _estimateRentals(List<CompRental> comps) {
    final selected = comps.where((comp) => comp.selected).toList();
    if (selected.isEmpty) {
      return null;
    }

    final totalWeight = selected.fold<double>(
      0,
      (sum, comp) => sum + comp.weight,
    );
    if (totalWeight <= 0) {
      return null;
    }

    final weightedRent = selected.fold<double>(
      0,
      (sum, comp) => sum + (comp.rentMonthly * comp.weight),
    );
    return weightedRent / totalWeight;
  }

  void _reload() {
    _salesFuture = ref
        .read(compsRepositoryProvider)
        .listSales(widget.propertyId);
    _rentalsFuture = ref
        .read(compsRepositoryProvider)
        .listRentals(widget.propertyId);
  }

  void _reloadWithState() {
    setState(_reload);
  }

  Future<void> _addSale() async {
    await ref
        .read(compsRepositoryProvider)
        .addSale(
          propertyId: widget.propertyId,
          address: 'Manual comp ${DateTime.now().millisecondsSinceEpoch}',
          price: 300000,
        );
    _reloadWithState();
  }

  Future<void> _addRental() async {
    await ref
        .read(compsRepositoryProvider)
        .addRental(
          propertyId: widget.propertyId,
          address:
              'Manual rental comp ${DateTime.now().millisecondsSinceEpoch}',
          rentMonthly: 1700,
        );
    _reloadWithState();
  }
}
