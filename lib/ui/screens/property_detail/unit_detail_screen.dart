import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class UnitDetailScreen extends ConsumerStatefulWidget {
  const UnitDetailScreen({
    super.key,
    required this.propertyId,
    required this.unitId,
    this.onEdit,
    this.onChanged,
  });

  final String propertyId;
  final String unitId;
  final VoidCallback? onEdit;
  final VoidCallback? onChanged;

  @override
  ConsumerState<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends ConsumerState<UnitDetailScreen> {
  UnitDetailBundle? _bundle;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UnitDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId || oldWidget.propertyId != widget.propertyId) {
      _load();
    }
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
      return const Center(child: Text('Select a unit.'));
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: widget.onEdit,
              child: const Text('Edit Unit'),
            ),
            FilledButton.tonal(
              onPressed: _markVacant,
              child: const Text('Mark Vacant'),
            ),
            FilledButton.tonal(
              onPressed: _markOffline,
              child: const Text('Mark Offline'),
            ),
            FilledButton.tonal(
              onPressed: () {
                ref.read(selectedOperationsUnitIdProvider.notifier).state = bundle.unit.id;
                ref.read(propertyDetailPageProvider.notifier).state = PropertyDetailPage.leases;
              },
              child: const Text('Add Lease'),
            ),
            if (bundle.activeTenant != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsTenantIdProvider.notifier).state =
                      bundle.activeTenant!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.tenants;
                },
                child: const Text('Open Tenant'),
              ),
            if (bundle.activeLease != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsLeaseIdProvider.notifier).state =
                      bundle.activeLease!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.leases;
                },
                child: const Text('Open Lease'),
              ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'unit',
                  entityId: bundle.unit.id,
                  defaultTitle: 'Review unit ${bundle.unit.unitCode}',
                );
                await _load();
              },
              child: const Text('Create Task'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Master Data',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unit: ${bundle.unit.unitCode}'),
                    Text('Type: ${bundle.unit.unitType ?? '-'}'),
                    Text('Status: ${bundle.unit.status}'),
                    Text('Floor: ${bundle.unit.floor ?? '-'}'),
                    Text('Beds / Baths: ${bundle.unit.beds ?? '-'} / ${bundle.unit.baths ?? '-'}'),
                    Text('Size: ${bundle.unit.sqft?.toStringAsFixed(1) ?? '-'} sqft'),
                    Text(
                      'Target / Market Rent: ${bundle.unit.targetRentMonthly?.toStringAsFixed(2) ?? '-'} / ${bundle.unit.marketRentMonthly?.toStringAsFixed(2) ?? '-'}',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Current Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline reason: ${bundle.unit.offlineReason ?? '-'}'),
                    Text('Vacancy since: ${formatDateMillis(bundle.unit.vacancySince)}'),
                    Text('Vacancy reason: ${bundle.unit.vacancyReason ?? '-'}'),
                    Text('Marketing: ${bundle.unit.marketingStatus ?? '-'}'),
                    Text('Renovation: ${bundle.unit.renovationStatus ?? '-'}'),
                    Text('Expected ready: ${formatDateMillis(bundle.unit.expectedReadyDate)}'),
                    Text('Next action: ${bundle.unit.nextAction ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Occupancy',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active lease: ${bundle.activeLease?.leaseName ?? 'No active lease'}'),
                    Text('Tenant: ${bundle.activeTenant?.displayName ?? '-'}'),
                    Text(
                      'Base rent: ${bundle.activeLease?.baseRentMonthly.toStringAsFixed(2) ?? '-'}',
                    ),
                    Text(
                      'Lease end: ${formatDateMillis(bundle.activeLease?.endDate)}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Lease History',
          child: bundle.leaseHistory.isEmpty
              ? const Text('No lease history yet.')
              : Column(
                  children: bundle.leaseHistory
                      .map(
                        (lease) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(lease.leaseName),
                          subtitle: Text(
                            '${lease.status} · ${formatDateMillis(lease.startDate)} to ${formatDateMillis(lease.endDate)}',
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              ref.read(selectedOperationsLeaseIdProvider.notifier).state = lease.id;
                              ref.read(propertyDetailPageProvider.notifier).state =
                                  PropertyDetailPage.leases;
                            },
                            child: const Text('Open'),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Latest Rent Roll',
                child: bundle.latestRentRollLine == null
                    ? const Text('No rent roll line available for this unit.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status: ${bundle.latestRentRollLine!.status}'),
                          Text(
                            'In place / Market: ${bundle.latestRentRollLine!.inPlaceRentMonthly.toStringAsFixed(2)} / ${bundle.latestRentRollLine!.marketRentMonthly?.toStringAsFixed(2) ?? '-'}',
                          ),
                          Text(
                            'Lease end: ${formatDateMillis(bundle.latestRentRollLine!.leaseEndDate)}',
                          ),
                        ],
                      ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Open Alerts',
                child: bundle.alerts.isEmpty
                    ? const Text('No open alerts for this unit.')
                    : Column(
                        children: bundle.alerts
                            .map(
                              (alert) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(alert.message),
                                subtitle: Text(alert.recommendedAction ?? alert.type),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Tasks',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'No unit tasks yet.',
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Documents',
                action: TextButton(
                  onPressed: () async {
                    await showCreateDocumentHookDialog(
                      context: context,
                      ref: ref,
                      entityType: 'unit',
                      entityId: bundle.unit.id,
                    );
                    await _load();
                  },
                  child: const Text('Add Hook'),
                ),
                child: OperationsDocumentsPanel(
                  documents: bundle.documents,
                  emptyHint:
                      'No documents linked yet. Document hooks are ready for later lease packs, handover files and evidence.',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bundle = await ref.read(operationsRepositoryProvider).loadUnitDetail(
            propertyId: widget.propertyId,
            unitId: widget.unitId,
          );
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
        _error = 'Failed to load unit detail: $error';
        _loading = false;
      });
    }
  }

  Future<void> _markVacant() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    DateTime vacancySince = DateTime.now();
    final reasonCtrl = TextEditingController(text: bundle.unit.vacancyReason ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mark Vacant'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Vacancy Since'),
                  child: Row(
                    children: [
                      Expanded(child: Text(formatDateMillis(vacancySince.millisecondsSinceEpoch))),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: vacancySince,
                            firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (picked != null && context.mounted) {
                            setDialogState(() => vacancySince = picked);
                          }
                        },
                        child: const Text('Select'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Vacancy Reason'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updated = UnitRecord(
                  id: bundle.unit.id,
                  assetPropertyId: bundle.unit.assetPropertyId,
                  unitCode: bundle.unit.unitCode,
                  unitType: bundle.unit.unitType,
                  beds: bundle.unit.beds,
                  baths: bundle.unit.baths,
                  sqft: bundle.unit.sqft,
                  floor: bundle.unit.floor,
                  status: 'vacant',
                  targetRentMonthly: bundle.unit.targetRentMonthly,
                  marketRentMonthly: bundle.unit.marketRentMonthly,
                  offlineReason: null,
                  vacancySince: vacancySince.millisecondsSinceEpoch,
                  vacancyReason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                  marketingStatus: bundle.unit.marketingStatus,
                  renovationStatus: bundle.unit.renovationStatus,
                  expectedReadyDate: bundle.unit.expectedReadyDate,
                  nextAction: bundle.unit.nextAction,
                  notes: bundle.unit.notes,
                  createdAt: bundle.unit.createdAt,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );
                await ref.read(rentRollRepositoryProvider).updateUnit(updated);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                widget.onChanged?.call();
                await _load();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  Future<void> _markOffline() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final reasonCtrl = TextEditingController(text: bundle.unit.offlineReason ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Offline'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Offline Reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updated = UnitRecord(
                id: bundle.unit.id,
                assetPropertyId: bundle.unit.assetPropertyId,
                unitCode: bundle.unit.unitCode,
                unitType: bundle.unit.unitType,
                beds: bundle.unit.beds,
                baths: bundle.unit.baths,
                sqft: bundle.unit.sqft,
                floor: bundle.unit.floor,
                status: 'offline',
                targetRentMonthly: bundle.unit.targetRentMonthly,
                marketRentMonthly: bundle.unit.marketRentMonthly,
                offlineReason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                vacancySince: null,
                vacancyReason: null,
                marketingStatus: null,
                renovationStatus: null,
                expectedReadyDate: null,
                nextAction: null,
                notes: bundle.unit.notes,
                createdAt: bundle.unit.createdAt,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              );
              await ref.read(rentRollRepositoryProvider).updateUnit(updated);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              widget.onChanged?.call();
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
  }
}
