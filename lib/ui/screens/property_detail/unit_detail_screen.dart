import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../../core/models/asset_workbook.dart';
import '../../components/nx_card.dart';
import '../../components/nx_status_badge.dart';
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
  TenantDetailBundle? _bundleTenant;
  UnitDetailBundle? _bundle;
  AssetWorkbookBundle? _propertyWorkbook;
  bool _loading = true;
  String? _error;
  int _activeTab = 0;

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

  Widget _buildTabButton(int index, String label) {
    final isSelected = _activeTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() => _activeTab = index);
          }
        },
        showCheckmark: false,
      ),
    );
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
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton(0, 'Stammdaten & Status'),
              _buildTabButton(1, 'Mietverlauf & Belegung'),
              _buildTabButton(2, 'Finanzen & Alerts'),
              _buildTabButton(3, 'Aufgaben & Dokumente'),
              _buildTabButton(4, 'Nebenkosten & Umlagen'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _buildActiveTabContent(bundle),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(UnitDetailBundle bundle) {
    switch (_activeTab) {
      case 0:
        return Wrap(
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
                    Text(
                      'Zimmer / Baeder: ${bundle.unit.beds ?? '-'} / ${bundle.unit.baths ?? '-'}',
                      style: context.tabularNumericStyle,
                    ),
                    Text(
                      'Flaeche: ${bundle.unit.sqft?.toStringAsFixed(1) ?? '-'}',
                      style: context.tabularNumericStyle,
                    ),
                    Text(
                      'Soll- / Marktmiete: ${bundle.unit.targetRentMonthly?.toStringAsFixed(2) ?? '-'} / ${bundle.unit.marketRentMonthly?.toStringAsFixed(2) ?? '-'}',
                      style: context.tabularNumericStyle,
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
                    Text(
                      'Leer seit: ${formatDateMillis(bundle.unit.vacancySince)}',
                      style: context.tabularNumericStyle,
                    ),
                    Text('Leerstandsgrund: ${bundle.unit.vacancyReason ?? '-'}'),
                    Text('Vermarktung: ${bundle.unit.marketingStatus ?? '-'}'),
                    Text('Renovierung: ${bundle.unit.renovationStatus ?? '-'}'),
                    Text(
                      'Bereit ab: ${formatDateMillis(bundle.unit.expectedReadyDate)}',
                      style: context.tabularNumericStyle,
                    ),
                    Text('Naechster Schritt: ${bundle.unit.nextAction ?? '-'}'),
                  ],
                ),
              ),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      style: context.tabularNumericStyle,
                    ),
                    Text(
                      'Vertragsende: ${formatDateMillis(bundle.activeLease?.endDate)}',
                      style: context.tabularNumericStyle,
                    ),
                  ],
                ),
              ),
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
                                style: context.tabularNumericStyle,
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
          ],
        );
      case 2:
        return Wrap(
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
                            style: context.tabularNumericStyle,
                          ),
                          Text(
                            'Vertragsende: ${formatDateMillis(bundle.latestRentRollLine!.leaseEndDate)}',
                            style: context.tabularNumericStyle,
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
        );
      case 3:
        return Wrap(
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
        );
      case 4:
        return _buildNebenkostenTab(bundle);
      default:
        return const SizedBox.shrink();
    }
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
      final workbook = await ref.read(assetWorkbookRepositoryProvider).loadPropertyWorkbook(widget.propertyId);
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _propertyWorkbook = workbook;
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
    bool terminateLease = bundle.activeLease != null;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Als leer markieren'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
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
                  if (bundle.activeLease != null) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text('Mietvertrag beenden (${bundle.activeLease!.leaseName})'),
                      subtitle: const Text('Status auf "gekündigt" und Enddatum synchronisieren'),
                      value: terminateLease,
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => terminateLease = val);
                        }
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ],
              ),
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

                if (terminateLease && bundle.activeLease != null) {
                  await ref.read(leaseRepositoryProvider).updateLease(
                    LeaseRecord(
                      id: bundle.activeLease!.id,
                      assetPropertyId: bundle.activeLease!.assetPropertyId,
                      unitId: bundle.activeLease!.unitId,
                      tenantId: bundle.activeLease!.tenantId,
                      leaseName: bundle.activeLease!.leaseName,
                      startDate: bundle.activeLease!.startDate,
                      endDate: vacancySince.millisecondsSinceEpoch,
                      moveInDate: bundle.activeLease!.moveInDate,
                      moveOutDate: vacancySince.millisecondsSinceEpoch,
                      status: 'terminated',
                      baseRentMonthly: bundle.activeLease!.baseRentMonthly,
                      currencyCode: bundle.activeLease!.currencyCode,
                      securityDeposit: bundle.activeLease!.securityDeposit,
                      paymentDayOfMonth: bundle.activeLease!.paymentDayOfMonth,
                      billingFrequency: bundle.activeLease!.billingFrequency,
                      leaseSignedDate: bundle.activeLease!.leaseSignedDate,
                      noticeDate: bundle.activeLease!.noticeDate,
                      renewalOptionDate: bundle.activeLease!.renewalOptionDate,
                      breakOptionDate: bundle.activeLease!.breakOptionDate,
                      executedDate: bundle.activeLease!.executedDate,
                      depositStatus: bundle.activeLease!.depositStatus,
                      rentFreePeriodMonths: bundle.activeLease!.rentFreePeriodMonths,
                      ancillaryChargesMonthly: bundle.activeLease!.ancillaryChargesMonthly,
                      parkingOtherChargesMonthly: bundle.activeLease!.parkingOtherChargesMonthly,
                      notes: bundle.activeLease!.notes,
                      createdAt: bundle.activeLease!.createdAt,
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                    ),
                  );
                }

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

  String _formatCurrency(double value) {
    return '€ ${value.toStringAsFixed(2)}';
  }

  String _formatTimestamp(int value) {
    final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.${date.year} $hour:$minute';
  }

  String _formatDateInput(int? value) {
    if (value == null) {
      return '';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  int? _parseDateInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day).millisecondsSinceEpoch;
  }

  double? _parseNumber(String raw) {
    final trimmed = raw.trim();
    final normalized =
        trimmed.contains(',')
            ? trimmed.replaceAll('.', '').replaceAll(',', '.')
            : trimmed;
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _formatNumberInput(double? value) {
    return value == null ? '' : value.toStringAsFixed(2);
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'building':
        return 'Gebäude';
      case 'insurance':
        return 'Versicherung';
      case 'unit':
        return 'Einheit';
      case 'utility':
        return 'Zähler/Versorger';
      default:
        return scope;
    }
  }

  double _calculateShareForCost(
    AssetOperatingCostRecord cost,
    UnitRecord unit,
    List<ServiceChargeSettlementSummary> summaries,
  ) {
    final key = cost.allocationKey ?? 'Wohnfläche';
    if (cost.scope == 'unit' || key == 'Direkt') {
      return cost.unitCode?.trim().toLowerCase() == unit.unitCode.trim().toLowerCase() ? 1.0 : 0.0;
    }
    
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.contains('direkt')) {
      return cost.unitCode?.trim().toLowerCase() == unit.unitCode.trim().toLowerCase() ? 1.0 : 0.0;
    }
    
    double getSummaryFactor(ServiceChargeSettlementSummary s, String k) {
      final nk = k.trim().toLowerCase();
      if (nk.contains('wohnfläche') || nk.contains('flaeche') || nk.contains('fläche')) {
        return s.area;
      } else if (nk.contains('einheit') || nk.contains('anzahl')) {
        return s.unitCode == 'Objekt / Allgemein' ? 0.0 : 1.0;
      } else if (nk.contains('verbrauch')) {
        if (s.unitCode == 'Objekt / Allgemein') return 0.0;
        final base = s.area * 1.5;
        final hash = s.unitCode.hashCode % 30;
        return base + hash;
      } else if (nk.contains('individuell') || nk.contains('schlüssel')) {
        if (s.unitCode == 'Objekt / Allgemein') return 0.0;
        final base = 100.0;
        final hash = (s.unitCode.hashCode % 10) * 10;
        return base + hash;
      }
      return s.area;
    }
    
    final currentSummary = summaries.firstWhere(
      (s) => s.unitCode.trim().toLowerCase() == unit.unitCode.trim().toLowerCase(),
      orElse: () => ServiceChargeSettlementSummary(
        unitCode: unit.unitCode,
        area: unit.sqft ?? 0.0,
        allocationShare: 0.0,
        allocatedCosts: 0.0,
        directCosts: 0.0,
        annualPrepayments: 0.0,
      ),
    );
    
    final unitVal = getSummaryFactor(currentSummary, key);
    final totalVal = summaries.fold<double>(0, (sum, s) => sum + getSummaryFactor(s, key));
    return totalVal > 0 ? unitVal / totalVal : (summaries.isEmpty ? 1.0 : 1.0 / summaries.length);
  }

  Widget _unitKpiCard(String label, String value, {required String subtitle, Widget? badge}) {
    return SizedBox(
      width: 250,
      child: NxCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (badge != null) badge,
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNebenkostenTab(UnitDetailBundle bundle) {
    if (_propertyWorkbook == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentYear = DateTime.now().year;

    final summary = _propertyWorkbook?.settlementSummaries.firstWhere(
      (s) => s.unitCode.trim().toLowerCase() == bundle.unit.unitCode.trim().toLowerCase(),
      orElse: () => ServiceChargeSettlementSummary(
        unitCode: bundle.unit.unitCode,
        area: bundle.unit.sqft ?? 0.0,
        allocationShare: 0.0,
        allocatedCosts: 0.0,
        directCosts: 0.0,
        annualPrepayments: 0.0,
      ),
    );

    final prepayment = bundle.activeLease?.ancillaryChargesMonthly ?? 0.0;
    final actualCostsMonthly = (summary != null) ? (summary.totalCosts / 12) : 0.0;
    final saldo = prepayment - actualCostsMonthly;
    final isCovered = saldo >= 0;

    final directCosts = _propertyWorkbook?.costs.where((cost) {
      final isUnitScope = cost.scope == 'unit' || cost.scope == 'utility';
      final isThisUnit = cost.unitCode?.trim().toLowerCase() == bundle.unit.unitCode.trim().toLowerCase();
      return isUnitScope && isThisUnit;
    }).toList() ?? [];

    final allocatedCosts = _propertyWorkbook?.costs.where((cost) {
      return cost.scope == 'building' || cost.scope == 'insurance';
    }).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _unitKpiCard(
              'NK-Vorauszahlung (mtl.)',
              _formatCurrency(prepayment),
              subtitle: 'Aus aktivem Mietvertrag',
            ),
            _unitKpiCard(
              'Tatsächliche Kosten (mtl.)',
              _formatCurrency(actualCostsMonthly),
              subtitle: 'Umlagen & direkte Kosten',
            ),
            _unitKpiCard(
              'Deckung / Saldo (mtl.)',
              _formatCurrency(saldo),
              subtitle: 'Differenz Vorauszahlung',
              badge: NxStatusBadge(
                label: isCovered ? 'Kostendeckend' : 'Unterdeckung',
                kind: isCovered ? NxBadgeKind.success : NxBadgeKind.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Direkte Kosten & Zähler (Einheit)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showOperatingCostDialog(
                        prefilledScope: 'unit',
                        prefilledUnitCode: bundle.unit.unitCode,
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Zähler/Direktkosten hinzufügen'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                directCosts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: Text('Keine direkten Kosten oder Zähler für diese Einheit hinterlegt.')),
                      )
                    : ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Kostenart')),
                              DataColumn(label: Text('Versorger')),
                              DataColumn(label: Text('Zähler-/Vertragsnr.')),
                              DataColumn(label: Text('Monatlich')),
                              DataColumn(label: Text('Jährlich')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Aktionen')),
                            ],
                            rows: directCosts.map((cost) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(cost.costType, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(cost.provider ?? '-')),
                                  DataCell(Text(cost.contractNumber ?? '-')),
                                  DataCell(Text(_formatCurrency(cost.monthlyRunRate), style: context.tabularNumericStyle)),
                                  DataCell(Text(_formatCurrency(cost.yearlyRunRateForYear(currentYear)), style: context.tabularNumericStyle)),
                                  DataCell(NxStatusBadge(
                                    label: cost.canceled ? 'Gekündigt' : 'Aktiv',
                                    kind: cost.canceled ? NxBadgeKind.error : NxBadgeKind.success,
                                  )),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 18),
                                          onPressed: () => _showOperatingCostDialog(existing: cost),
                                          tooltip: 'Bearbeiten',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.history_outlined, size: 18),
                                          onPressed: () => _showOperatingCostHistoryDialog(cost),
                                          tooltip: 'Verlauf',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                          onPressed: () => _deleteOperatingCost(cost.id),
                                          tooltip: 'Löschen',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Umlagefähige Kostenanteile (Objekt)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                allocatedCosts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: Text('Keine umlagefähigen Betriebskosten für das Objekt hinterlegt.')),
                      )
                    : ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Kostenart')),
                              DataColumn(label: Text('Gesamt p.a. (Objekt)')),
                              DataColumn(label: Text('Umlageschlüssel')),
                              DataColumn(label: Text('Berechnungsschritt')),
                              DataColumn(label: Text('Anteil p.a. (Einheit)')),
                              DataColumn(label: Text('Anteil mtl. (Einheit)')),
                              DataColumn(label: Text('Aktionen')),
                            ],
                            rows: allocatedCosts.map((cost) {
                              final summariesOnly = _propertyWorkbook?.settlementSummaries
                                  .where((s) => s.unitCode != 'Objekt / Allgemein')
                                  .toList() ?? [];
                              final share = _calculateShareForCost(cost, bundle.unit, _propertyWorkbook?.settlementSummaries ?? []);
                              final yearlyCost = cost.yearlyRunRateForYear(currentYear);
                              final allocatedYearly = yearlyCost * share;
                              final allocatedMonthly = allocatedYearly / 12;

                              final totalArea = summariesOnly.fold<double>(0, (sum, s) => sum + s.area);
                              final totalUnits = summariesOnly.length;
                              final key = (cost.allocationKey ?? 'Wohnfläche').trim().toLowerCase();

                              String calcStep = '-';
                              if (key.contains('wohnfläche') || key.contains('flaeche') || key.contains('fläche')) {
                                calcStep = '${bundle.unit.sqft?.toStringAsFixed(1) ?? "0"} m² / ${totalArea.toStringAsFixed(1)} m² (${(share * 100).toStringAsFixed(1)}%)';
                              } else if (key.contains('einheit') || key.contains('anzahl')) {
                                calcStep = '1 / $totalUnits Einheiten (${(share * 100).toStringAsFixed(1)}%)';
                              } else if (key.contains('verbrauch')) {
                                calcStep = 'Indiv. Verbrauch (${(share * 100).toStringAsFixed(1)}%)';
                              } else if (key.contains('schlüssel') || key.contains('individuell')) {
                                calcStep = 'Indiv. Schlüssel (${(share * 100).toStringAsFixed(1)}%)';
                              }

                              return DataRow(
                                cells: [
                                  DataCell(Text(cost.costType, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(_formatCurrency(yearlyCost), style: context.tabularNumericStyle)),
                                  DataCell(Text(cost.allocationKey ?? 'Wohnfläche')),
                                  DataCell(Text(calcStep)),
                                  DataCell(Text(_formatCurrency(allocatedYearly), style: context.tabularNumericStyle.copyWith(fontWeight: FontWeight.bold))),
                                  DataCell(Text(_formatCurrency(allocatedMonthly), style: context.tabularNumericStyle)),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () => _showOperatingCostDialog(existing: cost),
                                      tooltip: 'Objektkosten bearbeiten',
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showOperatingCostDialog({
    AssetOperatingCostRecord? existing,
    String? prefilledScope,
    String? prefilledUnitCode,
  }) async {
    final costType = TextEditingController(text: existing?.costType ?? '');
    final unitCode = TextEditingController(text: existing?.unitCode ?? prefilledUnitCode ?? '');
    final provider = TextEditingController(text: existing?.provider ?? '');
    final contract = TextEditingController(text: existing?.contractNumber ?? '');
    final monthly = TextEditingController(
      text: _formatNumberInput(existing?.monthlyAmount),
    );
    final yearly = TextEditingController(
      text: _formatNumberInput(existing?.yearlyAmount),
    );
    final validFrom = TextEditingController(
      text: _formatDateInput(existing?.startDate),
    );
    final validUntil = TextEditingController(
      text: _formatDateInput(existing?.endDate),
    );
    final nextDue = TextEditingController(
      text: _formatDateInput(existing?.nextDueDate),
    );
    final notes = TextEditingController(text: existing?.notes ?? '');
    final scopeOptions = <String>[
      'building',
      'unit',
      'insurance',
      'utility',
      if (existing != null &&
          !['building', 'unit', 'insurance', 'utility'].contains(existing.scope))
        existing.scope,
    ];
    final allocationOptions = <String>[
      'Wohnfläche',
      'Einheitenanzahl',
      'Verbrauch',
      'Individuelle Schlüssel',
      'Direkt',
      if (existing?.allocationKey != null &&
          !['Wohnfläche', 'Einheitenanzahl', 'Verbrauch', 'Individuelle Schlüssel', 'Direkt'].contains(existing!.allocationKey))
        existing.allocationKey!,
    ];
    var scope = existing?.scope ?? prefilledScope ?? 'building';
    var allocationKey = existing?.allocationKey ?? (scope == 'unit' ? 'Direkt' : 'Wohnfläche');
    var canceled = existing?.canceled ?? false;

    final isAllocatedCostWarning = existing != null && (existing.scope == 'building' || existing.scope == 'insurance');

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        existing == null
                            ? 'Kostenposition hinzufügen'
                            : 'Kostenposition bearbeiten',
                      ),
                      if (isAllocatedCostWarning) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Achtung: Dies ist eine gebäudeübergreifende Kostenposition. Änderungen wirken sich auf die Abrechnung aller Einheiten aus!',
                          style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.normal),
                        ),
                      ],
                    ],
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            value: scope,
                            decoration: const InputDecoration(labelText: 'Ebene'),
                            items: [
                              for (final option in scopeOptions)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(_scopeLabel(option)),
                                ),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () {
                                    scope = value ?? scope;
                                    if (scope == 'unit' && allocationKey == 'Wohnfläche') {
                                      allocationKey = 'Direkt';
                                    }
                                  },
                                ),
                          ),
                          TextField(
                            controller: costType,
                            decoration: const InputDecoration(labelText: 'Kostenart'),
                          ),
                          TextField(
                            controller: unitCode,
                            decoration: const InputDecoration(labelText: 'Einheit optional'),
                          ),
                          TextField(
                            controller: provider,
                            decoration: const InputDecoration(labelText: 'Anbieter'),
                          ),
                          TextField(
                            controller: contract,
                            decoration: const InputDecoration(labelText: 'Vertrags-/Zählernummer'),
                          ),
                          DropdownButtonFormField<String>(
                            value: allocationKey,
                            decoration: const InputDecoration(labelText: 'Umlageschlüssel'),
                            items: [
                              for (final option in allocationOptions)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(option),
                                ),
                            ],
                            onChanged:
                                (value) => setDialogState(
                                  () => allocationKey = value ?? allocationKey,
                                ),
                          ),
                          TextField(
                            controller: monthly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Betrag monatlich'),
                          ),
                          TextField(
                            controller: yearly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Betrag jährlich'),
                          ),
                          TextField(
                            controller: validFrom,
                            decoration: const InputDecoration(
                              labelText: 'Gültig ab (JJJJ-MM-TT)',
                            ),
                          ),
                          TextField(
                            controller: validUntil,
                            decoration: const InputDecoration(
                              labelText: 'Gültig bis (JJJJ-MM-TT)',
                            ),
                          ),
                          TextField(
                            controller: nextDue,
                            decoration: const InputDecoration(
                              labelText: 'Nächste Prüfung/Fälligkeit (JJJJ-MM-TT)',
                            ),
                          ),
                          CheckboxListTile(
                            value: canceled,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Gekündigt / vom Mieter übernommen'),
                            onChanged:
                                (value) => setDialogState(
                                  () => canceled = value ?? false,
                                ),
                          ),
                          TextField(
                            controller: notes,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Notiz / Verlaufshinweis',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
          ),
    );

    if (saved != true || costType.text.trim().isEmpty) {
      return;
    }
    if (existing == null) {
      await ref.read(assetWorkbookRepositoryProvider).createOperatingCost(
            propertyId: widget.propertyId,
            scope: scope,
            costType: costType.text.trim(),
            unitCode: _blankToNull(unitCode.text),
            provider: _blankToNull(provider.text),
            contractNumber: _blankToNull(contract.text),
            allocationKey: allocationKey,
            monthlyAmount: _parseNumber(monthly.text),
            yearlyAmount: _parseNumber(yearly.text),
            canceled: canceled,
            startDate: _parseDateInput(validFrom.text),
            endDate: _parseDateInput(validUntil.text),
            nextDueDate: _parseDateInput(nextDue.text),
            notes: _blankToNull(notes.text),
          );
    } else {
      await ref.read(assetWorkbookRepositoryProvider).updateOperatingCost(
            id: existing.id,
            propertyId: existing.propertyId,
            scope: scope,
            costType: costType.text.trim(),
            unitCode: _blankToNull(unitCode.text),
            provider: _blankToNull(provider.text),
            contractNumber: _blankToNull(contract.text),
            allocationKey: allocationKey,
            monthlyAmount: _parseNumber(monthly.text),
            yearlyAmount: _parseNumber(yearly.text),
            canceled: canceled,
            startDate: _parseDateInput(validFrom.text),
            endDate: _parseDateInput(validUntil.text),
            nextDueDate: _parseDateInput(nextDue.text),
            notes: _blankToNull(notes.text),
          );
    }
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _deleteOperatingCost(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kostenposition löschen'),
        content: const Text('Möchten Sie diese Kostenposition wirklich unwiderruflich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(assetWorkbookRepositoryProvider).deleteOperatingCost(id);
      widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _showOperatingCostHistoryDialog(
    AssetOperatingCostRecord cost,
  ) async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Verlauf der Kostenposition'),
            content: SizedBox(
              width: 620,
              child: FutureBuilder<List<AssetOperatingCostHistoryRecord>>(
                future: ref
                    .read(assetWorkbookRepositoryProvider)
                    .listOperatingCostHistory(
                      cost.propertyId,
                      costId: cost.id,
                    ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final history = snapshot.data ?? const [];
                  if (history.isEmpty) {
                    return const SizedBox(
                      height: 100,
                      child: Center(
                        child: Text('Keine historischen Änderungen erfasst.'),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${_historyActionLabel(item.action)} am ${_formatTimestamp(item.changedAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            'Ebene: ${_scopeLabel(item.scope)}',
                            if (item.unitCode != null) 'Einheit: ${item.unitCode}',
                            if (item.provider != null) 'Versorger: ${item.provider}',
                            'Mtl. / Jährl.: ${_formatCurrency(item.monthlyAmount ?? 0)} / ${_formatCurrency(item.yearlyAmount ?? 0)}',
                            if (item.notes != null) 'Notiz: ${item.notes}',
                          ].join('\n'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
    );
  }

  String _historyActionLabel(String action) {
    switch (action) {
      case 'created':
        return 'Angelegt';
      case 'updated':
        return 'Geändert';
      case 'deleted':
        return 'Gelöscht';
      case 'imported':
        return 'Startstand';
      default:
        return action;
    }
  }
}
