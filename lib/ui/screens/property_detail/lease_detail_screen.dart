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
      return const Center(child: Text('Mietvertrag auswaehlen.'));
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: widget.onEdit,
              child: const Text('Mietvertrag bearbeiten'),
            ),
            FilledButton.tonal(
              onPressed: widget.onAddRule,
              child: const Text('Indexregel anlegen'),
            ),
            FilledButton.tonal(
              onPressed: widget.onAddManualOverride,
              child: const Text('Manuelle Miete anlegen'),
            ),
            FilledButton.tonal(
              onPressed: _renewLease,
              child: const Text('Vertrag verlaengern'),
            ),
            FilledButton.tonal(
              onPressed: _endLease,
              child: const Text('Vertrag beenden'),
            ),
            if (bundle.tenant != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsTenantIdProvider.notifier).state = bundle.tenant!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.tenants;
                },
                child: const Text('Mieter oeffnen'),
              ),
            if (bundle.unit != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsUnitIdProvider.notifier).state = bundle.unit!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.units;
                },
                child: const Text('Einheit oeffnen'),
              ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'lease',
                  entityId: bundle.lease.id,
                  defaultTitle: 'Mietvertrag ${bundle.lease.leaseName} pruefen',
                );
                await _load();
              },
              child: const Text('Aufgabe anlegen'),
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
                title: 'Stammdaten',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vertrag: ${bundle.lease.leaseName}'),
                    Text('Status: ${_leaseStatusLabel(bundle.lease.status)}'),
                    Text('Einheit: ${bundle.unit?.unitCode ?? bundle.lease.unitId}'),
                    Text('Mieter: ${bundle.tenant?.displayName ?? '-'}'),
                    Text('Abrechnung: ${_billingLabel(bundle.lease.billingFrequency)}'),
                    Text('Zahlungstag: ${bundle.lease.paymentDayOfMonth ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Laufzeit',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start: ${formatDateMillis(bundle.lease.startDate)}'),
                    Text('Ende: ${formatDateMillis(bundle.lease.endDate)}'),
                    Text('Einzug: ${formatDateMillis(bundle.lease.moveInDate)}'),
                    Text('Auszug: ${formatDateMillis(bundle.lease.moveOutDate)}'),
                    Text('Unterschrieben: ${formatDateMillis(bundle.lease.leaseSignedDate)}'),
                    Text('Kuendigung: ${formatDateMillis(bundle.lease.noticeDate)}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Miete und Kaution',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grundmiete: ${bundle.lease.baseRentMonthly.toStringAsFixed(2)} ${bundle.lease.currencyCode}',
                    ),
                    Text(
                      'Kaution: ${bundle.lease.securityDeposit?.toStringAsFixed(2) ?? '-'}',
                    ),
                    Text('Kautionsstatus: ${_depositLabel(bundle.lease.depositStatus ?? 'unknown')}'),
                    Text(
                      'Nebenkosten / Sonstiges: ${bundle.lease.ancillaryChargesMonthly?.toStringAsFixed(2) ?? '-'} / ${bundle.lease.parkingOtherChargesMonthly?.toStringAsFixed(2) ?? '-'}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Naechste Ereignisse',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verlaengerungsoption: ${formatDateMillis(bundle.lease.renewalOptionDate)}'),
              Text('Sonderkuendigung: ${formatDateMillis(bundle.lease.breakOptionDate)}'),
              Text('Ausgefuehrt: ${formatDateMillis(bundle.lease.executedDate)}'),
              Text(
                'Letztes Mietende: ${formatDateMillis(bundle.latestRentRollLine?.leaseEndDate)}',
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
                title: 'Indexregeln',
                child: bundle.rules.isEmpty
                    ? const Text('Keine Indexregeln hinterlegt.')
                    : Column(
                        children: bundle.rules
                            .map(
                              (rule) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${_ruleKindLabel(rule.kind)} ab ${rule.effectiveFromPeriodKey}'),
                                subtitle: Text(
                                  'jaehrlich ${rule.annualPercent?.toStringAsFixed(4) ?? '-'} · Schritt ${rule.fixedStepAmount?.toStringAsFixed(2) ?? '-'}',
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
                title: 'Mietplan',
                child: bundle.schedule.isEmpty
                    ? const Text('Noch keine Mietplanzeilen erzeugt.')
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
                title: 'Hinweise',
                child: bundle.alerts.isEmpty
                    ? const Text('Keine offenen Hinweise fuer diesen Vertrag.')
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
                title: 'Aufgaben',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'Noch keine Aufgaben fuer diesen Vertrag.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Dokumente',
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
            child: const Text('Verknuepfung anlegen'),
          ),
          child: OperationsDocumentsPanel(
            documents: bundle.documents,
            emptyHint:
                'Noch keine Vertragsdokumente verknuepft.',
          ),
        ),
        ],
      ),
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
        _error = 'Mietvertragsdetails konnten nicht geladen werden: $error';
        _loading = false;
      });
    }
  }

  Future<void> _renewLease() async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final nameCtrl = TextEditingController(text: '${bundle.lease.leaseName} Verlaengerung');
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
          title: const Text('Mietvertrag verlaengern'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Vertragsname'),
                ),
                const SizedBox(height: 8),
                _DialogDateField(
                  label: 'Startdatum',
                  value: startDate,
                  onChanged: (value) => setDialogState(() => startDate = value),
                ),
                const SizedBox(height: 8),
                _DialogDateField(
                  label: 'Enddatum',
                  value: endDate,
                  onChanged: (value) => setDialogState(() => endDate = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rentCtrl,
                  decoration: const InputDecoration(labelText: 'Grundmiete'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final rent = double.tryParse(rentCtrl.text.trim().replaceAll(',', '.'));
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
              child: const Text('Verlaengerung anlegen'),
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
          title: const Text('Mietvertrag beenden'),
          content: SizedBox(
            width: 360,
            child: _DialogDateField(
              label: 'Enddatum',
              value: endDate,
              onChanged: (value) => setDialogState(() => endDate = value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
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
              child: const Text('Beenden'),
            ),
          ],
        ),
      ),
    );
  }

  String _leaseStatusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Entwurf';
      case 'future':
        return 'Zukuenftig';
      case 'active':
        return 'Aktiv';
      case 'terminated':
        return 'Gekuendigt';
      case 'expired':
        return 'Abgelaufen';
      default:
        return status;
    }
  }

  String _billingLabel(String value) {
    switch (value) {
      case 'monthly':
        return 'Monatlich';
      case 'quarterly':
        return 'Quartalsweise';
      case 'yearly':
        return 'Jaehrlich';
      default:
        return value;
    }
  }

  String _depositLabel(String value) {
    switch (value) {
      case 'unknown':
        return 'Unbekannt';
      case 'pending':
        return 'Ausstehend';
      case 'received':
        return 'Erhalten';
      case 'waived':
        return 'Erlassen';
      default:
        return value;
    }
  }

  String _ruleKindLabel(String value) {
    switch (value) {
      case 'cpi':
        return 'Index';
      case 'fixed_step':
        return 'Fester Schritt';
      case 'manual':
        return 'Manuell';
      default:
        return value;
    }
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
            child: const Text('Auswaehlen'),
          ),
        ],
      ),
    );
  }
}
