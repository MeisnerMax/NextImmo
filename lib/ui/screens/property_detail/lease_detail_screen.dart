import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class LeaseDetailScreen extends ConsumerStatefulWidget {
  const LeaseDetailScreen({
    super.key,
    required this.propertyId,
    required this.leaseId,
    this.onEdit,
    this.onAddRule,
    this.onAddManualOverride,
    this.onChanged,
  });

  final String propertyId;
  final String leaseId;
  final VoidCallback? onEdit;
  final VoidCallback? onAddRule;
  final VoidCallback? onAddManualOverride;
  final VoidCallback? onChanged;

  @override
  ConsumerState<LeaseDetailScreen> createState() => _LeaseDetailScreenState();
}

class _LeaseDetailScreenState extends ConsumerState<LeaseDetailScreen> {
  LeaseDetailBundle? _bundle;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeaseDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leaseId != widget.leaseId || oldWidget.propertyId != widget.propertyId) {
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
      return const Center(child: Text('Select a lease.'));
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
              child: const Text('Edit Lease'),
            ),
            FilledButton.tonal(
              onPressed: widget.onAddRule,
              child: const Text('Add Indexation Rule'),
            ),
            FilledButton.tonal(
              onPressed: widget.onAddManualOverride,
              child: const Text('Add Manual Rent Step'),
            ),
            FilledButton.tonal(
              onPressed: _renewLease,
              child: const Text('Renew Lease'),
            ),
            FilledButton.tonal(
              onPressed: _endLease,
              child: const Text('End Lease'),
            ),
            if (bundle.tenant != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsTenantIdProvider.notifier).state = bundle.tenant!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.tenants;
                },
                child: const Text('Open Tenant'),
              ),
            if (bundle.unit != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsUnitIdProvider.notifier).state = bundle.unit!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.units;
                },
                child: const Text('Open Unit'),
              ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'lease',
                  entityId: bundle.lease.id,
                  defaultTitle: 'Review lease ${bundle.lease.leaseName}',
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
                    Text('Lease: ${bundle.lease.leaseName}'),
                    Text('Status: ${bundle.lease.status}'),
                    Text('Unit: ${bundle.unit?.unitCode ?? bundle.lease.unitId}'),
                    Text('Tenant: ${bundle.tenant?.displayName ?? '-'}'),
                    Text('Billing: ${bundle.lease.billingFrequency}'),
                    Text('Payment day: ${bundle.lease.paymentDayOfMonth ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Term',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start: ${formatDateMillis(bundle.lease.startDate)}'),
                    Text('End: ${formatDateMillis(bundle.lease.endDate)}'),
                    Text('Move in: ${formatDateMillis(bundle.lease.moveInDate)}'),
                    Text('Move out: ${formatDateMillis(bundle.lease.moveOutDate)}'),
                    Text('Signed: ${formatDateMillis(bundle.lease.leaseSignedDate)}'),
                    Text('Notice: ${formatDateMillis(bundle.lease.noticeDate)}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Rent and Deposit',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Base rent: ${bundle.lease.baseRentMonthly.toStringAsFixed(2)} ${bundle.lease.currencyCode}',
                    ),
                    Text(
                      'Deposit: ${bundle.lease.securityDeposit?.toStringAsFixed(2) ?? '-'}',
                    ),
                    Text('Deposit status: ${bundle.lease.depositStatus ?? 'unknown'}'),
                    Text(
                      'Ancillary / Other: ${bundle.lease.ancillaryChargesMonthly?.toStringAsFixed(2) ?? '-'} / ${bundle.lease.parkingOtherChargesMonthly?.toStringAsFixed(2) ?? '-'}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Next Events',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Renewal option: ${formatDateMillis(bundle.lease.renewalOptionDate)}'),
              Text('Break option: ${formatDateMillis(bundle.lease.breakOptionDate)}'),
              Text('Executed: ${formatDateMillis(bundle.lease.executedDate)}'),
              Text(
                'Latest rent roll end: ${formatDateMillis(bundle.latestRentRollLine?.leaseEndDate)}',
              ),
            ],
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
                title: 'Indexation Rules',
                child: bundle.rules.isEmpty
                    ? const Text('No indexation rules defined.')
                    : Column(
                        children: bundle.rules
                            .map(
                              (rule) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${rule.kind} from ${rule.effectiveFromPeriodKey}'),
                                subtitle: Text(
                                  'annual ${rule.annualPercent?.toStringAsFixed(4) ?? '-'} · step ${rule.fixedStepAmount?.toStringAsFixed(2) ?? '-'}',
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Rent Schedule',
                child: bundle.schedule.isEmpty
                    ? const Text('No rent schedule rows generated yet.')
                    : Column(
                        children: bundle.schedule.take(24)
                            .map(
                              (row) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(row.periodKey),
                                subtitle: Text('${row.source} · ${row.rentMonthly.toStringAsFixed(2)}'),
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
                title: 'Alerts',
                child: bundle.alerts.isEmpty
                    ? const Text('No open alerts for this lease.')
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
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Tasks',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'No lease tasks yet.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Documents',
          action: TextButton(
            onPressed: () async {
              await showCreateDocumentHookDialog(
                context: context,
                ref: ref,
                entityType: 'lease',
                entityId: bundle.lease.id,
              );
              await _load();
            },
            child: const Text('Add Hook'),
          ),
          child: OperationsDocumentsPanel(
            documents: bundle.documents,
            emptyHint:
                'No lease documents linked yet. Hooks are ready for signed leases, notices, deposit evidence and move-in packs.',
          ),
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
      final bundle = await ref.read(operationsRepositoryProvider).loadLeaseDetail(
            propertyId: widget.propertyId,
            leaseId: widget.leaseId,
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
        _error = 'Failed to load lease detail: $error';
        _loading = false;
      });
    }
  }

  Future<void> _renewLease() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final nameCtrl = TextEditingController(text: '${bundle.lease.leaseName} Renewal');
    final rentCtrl = TextEditingController(text: bundle.lease.baseRentMonthly.toStringAsFixed(2));
    DateTime startDate =
        bundle.lease.endDate == null
            ? DateTime.now().add(const Duration(days: 1))
            : DateTime.fromMillisecondsSinceEpoch(bundle.lease.endDate!).add(const Duration(days: 1));
    DateTime endDate = DateTime(startDate.year + 1, startDate.month, startDate.day);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Renew Lease'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Lease Name'),
                ),
                const SizedBox(height: 8),
                _DialogDateField(
                  label: 'Start Date',
                  value: startDate,
                  onChanged: (value) => setDialogState(() => startDate = value),
                ),
                const SizedBox(height: 8),
                _DialogDateField(
                  label: 'End Date',
                  value: endDate,
                  onChanged: (value) => setDialogState(() => endDate = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rentCtrl,
                  decoration: const InputDecoration(labelText: 'Base Rent'),
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
                final rent = double.tryParse(rentCtrl.text.trim());
                if (nameCtrl.text.trim().isEmpty || rent == null) {
                  return;
                }
                final renewed = await ref.read(leaseRepositoryProvider).createLease(
                      assetPropertyId: bundle.lease.assetPropertyId,
                      unitId: bundle.lease.unitId,
                      tenantId: bundle.lease.tenantId,
                      leaseName: nameCtrl.text.trim(),
                      startDate: startDate.millisecondsSinceEpoch,
                      endDate: endDate.millisecondsSinceEpoch,
                      moveInDate: startDate.millisecondsSinceEpoch,
                      moveOutDate: null,
                      status: startDate.isAfter(DateTime.now()) ? 'future' : 'active',
                      baseRentMonthly: rent,
                      currencyCode: bundle.lease.currencyCode,
                      securityDeposit: bundle.lease.securityDeposit,
                      paymentDayOfMonth: bundle.lease.paymentDayOfMonth,
                      billingFrequency: bundle.lease.billingFrequency,
                      depositStatus: bundle.lease.depositStatus,
                      notes: bundle.lease.notes,
                    );
                ref.read(selectedOperationsLeaseIdProvider.notifier).state = renewed.id;
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                widget.onChanged?.call();
                await _load();
              },
              child: const Text('Create Renewal'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    rentCtrl.dispose();
  }

  Future<void> _endLease() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    DateTime endDate =
        bundle.lease.endDate == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(bundle.lease.endDate!);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('End Lease'),
          content: SizedBox(
            width: 360,
            child: _DialogDateField(
              label: 'End Date',
              value: endDate,
              onChanged: (value) => setDialogState(() => endDate = value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await ref.read(leaseRepositoryProvider).updateLease(
                      LeaseRecord(
                        id: bundle.lease.id,
                        assetPropertyId: bundle.lease.assetPropertyId,
                        unitId: bundle.lease.unitId,
                        tenantId: bundle.lease.tenantId,
                        leaseName: bundle.lease.leaseName,
                        startDate: bundle.lease.startDate,
                        endDate: endDate.millisecondsSinceEpoch,
                        moveInDate: bundle.lease.moveInDate,
                        moveOutDate: endDate.millisecondsSinceEpoch,
                        status: 'terminated',
                        baseRentMonthly: bundle.lease.baseRentMonthly,
                        currencyCode: bundle.lease.currencyCode,
                        securityDeposit: bundle.lease.securityDeposit,
                        paymentDayOfMonth: bundle.lease.paymentDayOfMonth,
                        billingFrequency: bundle.lease.billingFrequency,
                        leaseSignedDate: bundle.lease.leaseSignedDate,
                        noticeDate: bundle.lease.noticeDate,
                        renewalOptionDate: bundle.lease.renewalOptionDate,
                        breakOptionDate: bundle.lease.breakOptionDate,
                        executedDate: bundle.lease.executedDate,
                        depositStatus: bundle.lease.depositStatus,
                        rentFreePeriodMonths: bundle.lease.rentFreePeriodMonths,
                        ancillaryChargesMonthly: bundle.lease.ancillaryChargesMonthly,
                        parkingOtherChargesMonthly: bundle.lease.parkingOtherChargesMonthly,
                        notes: bundle.lease.notes,
                        createdAt: bundle.lease.createdAt,
                        updatedAt: DateTime.now().millisecondsSinceEpoch,
                      ),
                    );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                widget.onChanged?.call();
                await _load();
              },
              child: const Text('End Lease'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogDateField extends StatelessWidget {
  const _DialogDateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(value.toIso8601String().substring(0, 10))),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null && context.mounted) {
                onChanged(picked);
              }
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
}
