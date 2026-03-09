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
                _metricCard('Units Total', '${bundle.unitsTotal}'),
                _metricCard('Occupied', '${bundle.occupiedUnits}'),
                _metricCard('Vacant', '${bundle.vacantUnits}'),
                _metricCard('Offline', '${bundle.offlineUnits}'),
                _metricCard('Active Leases', '${bundle.activeLeases}'),
                _metricCard('Alerts', '${bundle.openOperationalAlerts}'),
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
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionButton('New Unit', PropertyDetailPage.units),
                        _actionButton('New Tenant', PropertyDetailPage.tenants),
                        _actionButton('New Lease', PropertyDetailPage.leases),
                        _actionButton('Generate Rent Roll', PropertyDetailPage.rentRoll),
                        _actionButton('Review Expiring Leases', PropertyDetailPage.alerts),
                        _actionButton('Review Vacancies', PropertyDetailPage.units),
                        _actionButton('Review Data Issues', PropertyDetailPage.alerts),
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
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
                child: Text(line),
              )),
            ],
          ),
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
