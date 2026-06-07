import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class OperationsOverviewScreen extends ConsumerStatefulWidget {
  const OperationsOverviewScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<OperationsOverviewScreen> createState() =>
      _OperationsOverviewScreenState();
}

class _OperationsOverviewScreenState
    extends ConsumerState<OperationsOverviewScreen> {
  bool _loading = true;
  String? _error;
  OperationsOverviewBundle? _bundle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final bundle = _bundle;
    if (bundle == null) {
      return const Center(child: Text('No operations data available.'));
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                _metricCard('Einheiten', '${bundle.unitsTotal}'),
                _metricCard('Vermietet', '${bundle.occupiedUnits}'),
                _metricCard('Leerstand', '${bundle.vacantUnits}'),
                _metricCard('Offline', '${bundle.offlineUnits}'),
                _metricCard('Aktive Verträge', '${bundle.activeLeases}'),
                _metricCard('Hinweise', '${bundle.openOperationalAlerts}'),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            _lettingWorkflowCard(),
            const SizedBox(height: AppSpacing.component),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schnellaktionen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionButton('Einheit anlegen', PropertyDetailPage.units),
                        _actionButton('Mieter anlegen', PropertyDetailPage.tenants),
                        _actionButton('Vertrag anlegen', PropertyDetailPage.leases),
                        _actionButton('Rent Roll erzeugen', PropertyDetailPage.rentRoll),
                        _actionButton('Mietenden prüfen', PropertyDetailPage.alerts),
                        _actionButton('Leerstand prüfen', PropertyDetailPage.units),
                        _actionButton('Datenqualität prüfen', PropertyDetailPage.alerts),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                _summaryCard(
                  title: 'Occupancy Area',
                  lines: [
                    'Occupied units: ${bundle.occupiedUnits}',
                    'Occupied area: ${bundle.occupiedAreaSqft.toStringAsFixed(1)} sqft',
                    'Leased area: ${bundle.leasedAreaSqft.toStringAsFixed(1)} sqft',
                  ],
                ),
                _summaryCard(
                  title: 'Lease Expiry Windows',
                  lines: [
                    '30 days: ${bundle.expiringIn30Days}',
                    '60 days: ${bundle.expiringIn60Days}',
                    '90 days: ${bundle.expiringIn90Days}',
                    '180 days: ${bundle.expiringIn180Days}',
                  ],
                ),
                _summaryCard(
                  title: 'Data Quality',
                  lines: [
                    'Units without active lease: ${bundle.unitsWithoutActiveLease}',
                    'Missing tenant contact: ${bundle.unitsWithMissingTenantMasterData}',
                    'Critical conflicts: ${bundle.dataConflicts}',
                    'Total issues: ${bundle.dataQualityIssues.length}',
                  ],
                ),
                _summaryCard(
                  title: 'Rent Roll',
                  lines: [
                    'Latest period: ${bundle.latestRentRollPeriod ?? '-'}',
                    'Rent delta: ${bundle.rentRollDelta == null ? '-' : bundle.rentRollDelta!.inPlaceRentDelta.toStringAsFixed(2)}',
                    'Occupancy delta: ${bundle.rentRollDelta == null ? '-' : '${(bundle.rentRollDelta!.occupancyRateDelta * 100).toStringAsFixed(1)}%'}',
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.component),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open Operational Alerts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (bundle.alerts.isEmpty)
                      const Text('No open operational alerts.')
                    else
                      ...bundle.alerts.take(8).map(
                        (alert) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            alert.severity == 'critical'
                                ? Icons.error_outline
                                : alert.severity == 'warning'
                                ? Icons.warning_amber_outlined
                                : Icons.info_outline,
                            color:
                                alert.severity == 'critical'
                                    ? Colors.red
                                    : alert.severity == 'warning'
                                    ? Colors.orange
                                    : Colors.blueGrey,
                          ),
                          title: Text(alert.message),
                          subtitle: Text(alert.type),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700).merge(context.tabularNumericStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required List<String> lines,
  }) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: context.tabularNumericStyle),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lettingWorkflowCard() {
    final steps = <_LettingWorkflowStep>[
      const _LettingWorkflowStep(
        number: '1',
        title: 'Einheit',
        detail: 'Fläche und Status',
        icon: Icons.apartment_outlined,
        targetPage: PropertyDetailPage.units,
      ),
      const _LettingWorkflowStep(
        number: '2',
        title: 'Interessent',
        detail: 'Mieterprofil',
        icon: Icons.person_add_alt_outlined,
        targetPage: PropertyDetailPage.tenants,
      ),
      const _LettingWorkflowStep(
        number: '3',
        title: 'Dokumente',
        detail: 'Nachweise und Vertrag',
        icon: Icons.folder_open_outlined,
        targetPage: PropertyDetailPage.documents,
      ),
      const _LettingWorkflowStep(
        number: '4',
        title: 'Vertrag',
        detail: 'Konditionen',
        icon: Icons.description_outlined,
        targetPage: PropertyDetailPage.leases,
      ),
      const _LettingWorkflowStep(
        number: '5',
        title: 'Mietbeginn',
        detail: 'Start und Übergabe',
        icon: Icons.event_available_outlined,
        targetPage: PropertyDetailPage.leases,
      ),
      const _LettingWorkflowStep(
        number: '6',
        title: 'Kaution',
        detail: 'Soll und Zahlung',
        icon: Icons.savings_outlined,
        targetPage: PropertyDetailPage.leases,
      ),
      const _LettingWorkflowStep(
        number: '7',
        title: 'Laufende Miete',
        detail: 'Rent Roll',
        icon: Icons.payments_outlined,
        targetPage: PropertyDetailPage.rentRoll,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vermietungsworkflow',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  steps.map((step) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                      onTap: () {
                        ref.read(propertyDetailPageProvider.notifier).state =
                            step.targetPage;
                      },
                      child: Container(
                        width: context.viewport == AppViewport.mobile ? double.infinity : 220,
                        padding: const EdgeInsets.all(AppSpacing.component),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                          border: Border.all(color: context.semanticColors.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(radius: 15, child: Text(step.number)),
                            const SizedBox(width: AppSpacing.sm),
                            Icon(step.icon, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  Text(
                                    step.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, PropertyDetailPage targetPage) {
    return FilledButton.tonal(
      onPressed: () {
        ref.read(propertyDetailPageProvider.notifier).state = targetPage;
      },
      child: Text(label),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bundle = await ref
          .read(operationsRepositoryProvider)
          .loadOverview(widget.propertyId);
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load operations overview: $error';
        _loading = false;
      });
    }
  }
}

class _LettingWorkflowStep {
  const _LettingWorkflowStep({
    required this.number,
    required this.title,
    required this.detail,
    required this.icon,
    required this.targetPage,
  });

  final String number;
  final String title;
  final String detail;
  final IconData icon;
  final PropertyDetailPage targetPage;
}
