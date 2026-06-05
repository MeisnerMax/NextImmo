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
      return const Center(child: Text('Einheit auswaehlen.'));
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
              child: const Text('Einheit bearbeiten'),
            ),
            FilledButton.tonal(
              onPressed: _markVacant,
              child: const Text('Als leer markieren'),
            ),
            FilledButton.tonal(
              onPressed: _markOffline,
              child: const Text('Offline setzen'),
            ),
            FilledButton.tonal(
              onPressed: () {
                ref.read(selectedOperationsUnitIdProvider.notifier).state = bundle.unit.id;
                ref.read(propertyDetailPageProvider.notifier).state = PropertyDetailPage.leases;
              },
              child: const Text('Mietvertrag anlegen'),
            ),
            if (bundle.activeTenant != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsTenantIdProvider.notifier).state =
                      bundle.activeTenant!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.tenants;
                },
                child: const Text('Mieter oeffnen'),
              ),
            if (bundle.activeLease != null)
              FilledButton.tonal(
                onPressed: () {
                  ref.read(selectedOperationsLeaseIdProvider.notifier).state =
                      bundle.activeLease!.id;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.leases;
                },
                child: const Text('Mietvertrag oeffnen'),
              ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'unit',
                  entityId: bundle.unit.id,
                  defaultTitle: 'Einheit ${bundle.unit.unitCode} pruefen',
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
                    Text('Einheit: ${bundle.unit.unitCode}'),
                    Text('Typ: ${bundle.unit.unitType ?? '-'}'),
                    Text('Status: ${_unitStatusLabel(bundle.unit.status)}'),
                    Text('Etage: ${bundle.unit.floor ?? '-'}'),
                    Text('Zimmer / Baeder: ${bundle.unit.beds ?? '-'} / ${bundle.unit.baths ?? '-'}'),
                    Text('Flaeche: ${bundle.unit.sqft?.toStringAsFixed(1) ?? '-'}'),
                    Text(
                      'Soll- / Marktmiete: ${bundle.unit.targetRentMonthly?.toStringAsFixed(2) ?? '-'} / ${bundle.unit.marketRentMonthly?.toStringAsFixed(2) ?? '-'}',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Aktueller Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline-Grund: ${bundle.unit.offlineReason ?? '-'}'),
                    Text('Leer seit: ${formatDateMillis(bundle.unit.vacancySince)}'),
                    Text('Leerstandsgrund: ${bundle.unit.vacancyReason ?? '-'}'),
                    Text('Vermarktung: ${bundle.unit.marketingStatus ?? '-'}'),
                    Text('Renovierung: ${bundle.unit.renovationStatus ?? '-'}'),
                    Text('Bereit ab: ${formatDateMillis(bundle.unit.expectedReadyDate)}'),
                    Text('Naechster Schritt: ${bundle.unit.nextAction ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Belegung',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aktiver Vertrag: ${bundle.activeLease?.leaseName ?? 'Kein aktiver Vertrag'}'),
                    Text('Mieter: ${bundle.activeTenant?.displayName ?? '-'}'),
                    Text(
                      'Grundmiete: ${bundle.activeLease?.baseRentMonthly.toStringAsFixed(2) ?? '-'}',
                    ),
                    Text(
                      'Vertragsende: ${formatDateMillis(bundle.activeLease?.endDate)}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Mietverlauf',
          child: bundle.leaseHistory.isEmpty
              ? const Text('Noch kein Mietverlauf.')
              : Column(
                  children: bundle.leaseHistory
                      .map(
                        (lease) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(lease.leaseName),
                          subtitle: Text(
                            '${_leaseStatusLabel(lease.status)} · ${formatDateMillis(lease.startDate)} bis ${formatDateMillis(lease.endDate)}',
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              ref.read(selectedOperationsLeaseIdProvider.notifier).state = lease.id;
                              ref.read(propertyDetailPageProvider.notifier).state =
                                  PropertyDetailPage.leases;
                            },
                            child: const Text('Oeffnen'),
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
                title: 'Aktuelle Miete',
                child: bundle.latestRentRollLine == null
                    ? const Text('Keine Mietzeile fuer diese Einheit verfuegbar.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status: ${bundle.latestRentRollLine!.status}'),
                          Text(
                            'Ist / Markt: ${bundle.latestRentRollLine!.inPlaceRentMonthly.toStringAsFixed(2)} / ${bundle.latestRentRollLine!.marketRentMonthly?.toStringAsFixed(2) ?? '-'}',
                          ),
                          Text(
                            'Vertragsende: ${formatDateMillis(bundle.latestRentRollLine!.leaseEndDate)}',
                          ),
                        ],
                      ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Offene Hinweise',
                child: bundle.alerts.isEmpty
                    ? const Text('Keine offenen Hinweise fuer diese Einheit.')
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
                title: 'Aufgaben',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'Noch keine Aufgaben fuer diese Einheit.',
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Dokumente',
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
                  child: const Text('Verknuepfung anlegen'),
                ),
                child: OperationsDocumentsPanel(
                  documents: bundle.documents,
                  emptyHint:
                      'Noch keine Dokumente verknuepft.',
                ),
              ),
            ),
          ],
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
        _error = 'Einheitsdetails konnten nicht geladen werden: $error';
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
          title: const Text('Als leer markieren'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Leer seit'),
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
                        child: const Text('Auswaehlen'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Leerstandsgrund'),
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
              child: const Text('Speichern'),
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
        title: const Text('Offline setzen'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Offline-Grund'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
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
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
  }

  String _unitStatusLabel(String status) {
    switch (status) {
      case 'occupied':
        return 'Vermietet';
      case 'vacant':
        return 'Leer';
      case 'offline':
        return 'Offline';
      case 'archived':
        return 'Archiviert';
      default:
        return status;
    }
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
}
