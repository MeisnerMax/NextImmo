import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'unit_detail_screen.dart';

class UnitsScreen extends ConsumerStatefulWidget {
  const UnitsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends ConsumerState<UnitsScreen> {
  List<UnitRecord> _units = const [];
  String? _status;
  String _query = '';
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final selectedUnitId = ref.watch(selectedOperationsUnitIdProvider);
    final filteredUnits = _units.where((unit) {
      final visibleByArchive =
          _statusFilter == 'archived'
              ? unit.status == 'archived'
              : unit.status != 'archived';
      final matchesStatus =
          _statusFilter == 'all' ||
          _statusFilter == 'archived' ||
          unit.status == _statusFilter;
      final needle = _query.trim().toLowerCase();
      final matchesQuery =
          needle.isEmpty ||
          unit.unitCode.toLowerCase().contains(needle) ||
          (unit.unitType?.toLowerCase().contains(needle) ?? false) ||
          (unit.floor?.toLowerCase().contains(needle) ?? false);
      return visibleByArchive && matchesStatus && matchesQuery;
    }).toList(growable: false);
    final selectedUnit = filteredUnits
        .where((unit) => unit.id == selectedUnitId)
        .cast<UnitRecord?>()
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _createUnitDialog,
                icon: const Icon(Icons.add),
                label: const Text('Einheit hinzufügen'),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Einheiten suchen',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Aktive anzeigen')),
                    DropdownMenuItem(value: 'occupied', child: Text('Vermietet')),
                    DropdownMenuItem(value: 'vacant', child: Text('Leer')),
                    DropdownMenuItem(value: 'offline', child: Text('Offline')),
                    DropdownMenuItem(value: 'archived', child: Text('archiviert')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _statusFilter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: AppSpacing.component),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1100;
              final listPane = _unitListCard(
                context: context,
                units: filteredUnits,
                selectedUnitId: selectedUnitId,
              );
              final detailPane = _unitDetailCard(selectedUnit);
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    listPane,
                    const SizedBox(height: AppSpacing.component),
                    detailPane,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 420, child: listPane),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(child: detailPane),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _unitListCard({
    required BuildContext context,
    required List<UnitRecord> units,
    required String? selectedUnitId,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Einheiten', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (units.isEmpty)
              const Text('Keine Einheiten für diesen Filter.')
            else
              Column(
                children: [
                  for (final unit in units)
                    ListTile(
                      selected: unit.id == selectedUnitId,
                      contentPadding: EdgeInsets.zero,
                      title: Text(unit.unitCode),
                      subtitle: Text(
                        '${_statusLabel(unit.status)}${unit.unitType == null ? '' : ' · ${unit.unitType}'}${unit.targetRentMonthly == null ? '' : ' · Soll ${unit.targetRentMonthly!.toStringAsFixed(2)}'}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (unit.status == 'vacant' &&
                              unit.vacancySince == null)
                            const Tooltip(
                              message: 'Leerstandsdatum fehlt',
                              child: Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.orange,
                              ),
                            ),
                          TextButton(
                            onPressed: () => _editUnitDialog(unit),
                            child: const Text('Bearbeiten'),
                          ),
                          if (unit.status == 'archived')
                            TextButton(
                              onPressed: () => _deleteUnit(unit.id),
                              child: const Text('Endgültig löschen'),
                            )
                          else
                            TextButton(
                              onPressed: () => _archiveUnit(unit),
                              child: const Text('Archivieren'),
                            ),
                        ],
                      ),
                      onTap:
                          () =>
                              ref
                                  .read(
                                    selectedOperationsUnitIdProvider.notifier,
                                  )
                                  .state = unit.id,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _unitDetailCard(UnitRecord? selectedUnit) {
    return Card(
      child:
          selectedUnit == null
              ? const Padding(
                padding: EdgeInsets.all(AppSpacing.cardPadding),
                child: Text('Einheit auswählen, um Details zu öffnen.'),
              )
              : UnitDetailScreen(
                propertyId: widget.propertyId,
                unitId: selectedUnit.id,
                onEdit: () => _editUnitDialog(selectedUnit),
                onChanged: _reload,
              ),
    );
  }

  Future<void> _reload() async {
    final units = await ref
        .read(rentRollRepositoryProvider)
        .listUnitsByAsset(widget.propertyId, includeArchived: true);
    if (!mounted) {
      return;
    }
    final selectedId = ref.read(selectedOperationsUnitIdProvider);
    setState(() {
      _units = units;
      _status = null;
    });
    if (units.isNotEmpty && !units.any((unit) => unit.id == selectedId)) {
      final firstVisible = units
          .where((unit) => unit.status != 'archived')
          .cast<UnitRecord?>()
          .firstOrNull;
      ref.read(selectedOperationsUnitIdProvider.notifier).state =
          firstVisible?.id;
    }
  }

  Future<void> _createUnitDialog() => _unitDialog();

  Future<void> _editUnitDialog(UnitRecord unit) => _unitDialog(existing: unit);

  Future<void> _unitDialog({UnitRecord? existing}) async {
    final isEdit = existing != null;
    final codeCtrl = TextEditingController(text: existing?.unitCode ?? '');
    final unitTypeCtrl = TextEditingController(text: existing?.unitType ?? 'apartment');
    final floorCtrl = TextEditingController(text: existing?.floor ?? '');
    final bedsCtrl = TextEditingController(text: existing?.beds?.toString() ?? '');
    final bathsCtrl = TextEditingController(text: existing?.baths?.toString() ?? '');
    final sqftCtrl = TextEditingController(text: existing?.sqft?.toString() ?? '');
    final targetCtrl = TextEditingController(text: existing?.targetRentMonthly?.toString() ?? '');
    final marketCtrl = TextEditingController(text: existing?.marketRentMonthly?.toString() ?? '');
    final offlineReasonCtrl = TextEditingController(text: existing?.offlineReason ?? '');
    final vacancyReasonCtrl = TextEditingController(text: existing?.vacancyReason ?? '');
    final marketingStatusCtrl = TextEditingController(text: existing?.marketingStatus ?? '');
    final renovationStatusCtrl = TextEditingController(text: existing?.renovationStatus ?? '');
    final nextActionCtrl = TextEditingController(text: existing?.nextAction ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String status = existing?.status ?? 'vacant';
    DateTime? vacancySince =
        existing?.vacancySince == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.vacancySince!);
    DateTime? expectedReadyDate =
        existing?.expectedReadyDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing!.expectedReadyDate!);
    const allowedStatuses = <String>['occupied', 'vacant', 'offline', 'archived'];
    final statusItems = <DropdownMenuItem<String>>[
      if (!allowedStatuses.contains(status))
        DropdownMenuItem(value: status, child: Text(status)),
      const DropdownMenuItem(value: 'occupied', child: Text('Vermietet')),
      const DropdownMenuItem(value: 'vacant', child: Text('Leer')),
      const DropdownMenuItem(value: 'offline', child: Text('Offline')),
      const DropdownMenuItem(value: 'archived', child: Text('archiviert')),
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Einheit bearbeiten' : 'Einheit anlegen'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Einheit / Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: unitTypeCtrl,
                    decoration: const InputDecoration(labelText: 'Einheitstyp'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: status,
                    items: statusItems,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => status = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: floorCtrl, decoration: const InputDecoration(labelText: 'Etage')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bedsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Zimmer'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bathsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Bäder'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sqftCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Fläche'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Sollmiete'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: marketCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Marktmiete'),
                  ),
                  if (status == 'offline') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: offlineReasonCtrl,
                      decoration: const InputDecoration(labelText: 'Offline-Grund'),
                    ),
                  ],
                  if (status == 'vacant') ...[
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Leer seit',
                      value: vacancySince,
                      onPick: (value) => setDialogState(() => vacancySince = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: vacancyReasonCtrl,
                      decoration: const InputDecoration(labelText: 'Leerstandsgrund'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: marketingStatusCtrl,
                      decoration: const InputDecoration(labelText: 'Vermarktungsstatus'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: renovationStatusCtrl,
                      decoration: const InputDecoration(labelText: 'Renovierungsstatus'),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Bereit ab',
                      value: expectedReadyDate,
                      onPick: (value) => setDialogState(() => expectedReadyDate = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nextActionCtrl,
                      decoration: const InputDecoration(labelText: 'Nächster Schritt'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notizen'),
                  ),
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
                final code = codeCtrl.text.trim();
                if (code.isEmpty) {
                  return;
                }
                try {
                  if (isEdit) {
                    await ref.read(rentRollRepositoryProvider).updateUnit(
                          UnitRecord(
                            id: existing.id,
                            assetPropertyId: existing.assetPropertyId,
                            unitCode: code,
                            unitType: _nullIfEmpty(unitTypeCtrl.text),
                            beds: _parseDouble(bedsCtrl.text),
                            baths: _parseDouble(bathsCtrl.text),
                            sqft: _parseDouble(sqftCtrl.text),
                            floor: _nullIfEmpty(floorCtrl.text),
                            status: status,
                            targetRentMonthly: _parseDouble(targetCtrl.text),
                            marketRentMonthly: _parseDouble(marketCtrl.text),
                            offlineReason:
                                status == 'offline' ? _nullIfEmpty(offlineReasonCtrl.text) : null,
                            vacancySince:
                                status == 'vacant' ? vacancySince?.millisecondsSinceEpoch : null,
                            vacancyReason:
                                status == 'vacant' ? _nullIfEmpty(vacancyReasonCtrl.text) : null,
                            marketingStatus:
                                status == 'vacant' ? _nullIfEmpty(marketingStatusCtrl.text) : null,
                            renovationStatus:
                                status == 'vacant'
                                    ? _nullIfEmpty(renovationStatusCtrl.text)
                                    : null,
                            expectedReadyDate:
                                status == 'vacant'
                                    ? expectedReadyDate?.millisecondsSinceEpoch
                                    : null,
                            nextAction:
                                status == 'vacant' ? _nullIfEmpty(nextActionCtrl.text) : null,
                            notes: _nullIfEmpty(notesCtrl.text),
                            createdAt: existing.createdAt,
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                    ref.read(selectedOperationsUnitIdProvider.notifier).state = existing.id;
                  } else {
                    final created = await ref.read(rentRollRepositoryProvider).createUnit(
                          assetPropertyId: widget.propertyId,
                          unitCode: code,
                          unitType: _nullIfEmpty(unitTypeCtrl.text),
                          beds: _parseDouble(bedsCtrl.text),
                          baths: _parseDouble(bathsCtrl.text),
                          sqft: _parseDouble(sqftCtrl.text),
                          floor: _nullIfEmpty(floorCtrl.text),
                          status: status,
                          targetRentMonthly: _parseDouble(targetCtrl.text),
                          marketRentMonthly: _parseDouble(marketCtrl.text),
                          offlineReason:
                              status == 'offline' ? _nullIfEmpty(offlineReasonCtrl.text) : null,
                          vacancySince:
                              status == 'vacant' ? vacancySince?.millisecondsSinceEpoch : null,
                          vacancyReason:
                              status == 'vacant' ? _nullIfEmpty(vacancyReasonCtrl.text) : null,
                          marketingStatus:
                              status == 'vacant' ? _nullIfEmpty(marketingStatusCtrl.text) : null,
                          renovationStatus:
                              status == 'vacant'
                                  ? _nullIfEmpty(renovationStatusCtrl.text)
                                  : null,
                          expectedReadyDate:
                              status == 'vacant'
                                  ? expectedReadyDate?.millisecondsSinceEpoch
                                  : null,
                          nextAction:
                              status == 'vacant' ? _nullIfEmpty(nextActionCtrl.text) : null,
                          notes: _nullIfEmpty(notesCtrl.text),
                        );
                    ref.read(selectedOperationsUnitIdProvider.notifier).state = created.id;
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  await _reload();
                } catch (error) {
                  if (mounted) {
                    setState(() => _status = error.toString());
                  }
                }
              },
              child: Text(isEdit ? 'Speichern' : 'Anlegen'),
            ),
          ],
        ),
      ),
    );

    codeCtrl.dispose();
    unitTypeCtrl.dispose();
    floorCtrl.dispose();
    bedsCtrl.dispose();
    bathsCtrl.dispose();
    sqftCtrl.dispose();
    targetCtrl.dispose();
    marketCtrl.dispose();
    offlineReasonCtrl.dispose();
    vacancyReasonCtrl.dispose();
    marketingStatusCtrl.dispose();
    renovationStatusCtrl.dispose();
    nextActionCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _deleteUnit(String unitId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Einheit endgueltig loeschen'),
            content: const Text(
              'Diese archivierte Einheit wirklich dauerhaft entfernen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.semanticColors.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Loeschen'),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(rentRollRepositoryProvider).deleteUnit(unitId);
    if (ref.read(selectedOperationsUnitIdProvider) == unitId) {
      ref.read(selectedOperationsUnitIdProvider.notifier).state = null;
    }
    await _reload();
  }

  Future<void> _archiveUnit(UnitRecord unit) async {
    await ref.read(rentRollRepositoryProvider).updateUnit(
          UnitRecord(
            id: unit.id,
            assetPropertyId: unit.assetPropertyId,
            unitCode: unit.unitCode,
            unitType: unit.unitType,
            beds: unit.beds,
            baths: unit.baths,
            sqft: unit.sqft,
            floor: unit.floor,
            status: 'archived',
            targetRentMonthly: unit.targetRentMonthly,
            marketRentMonthly: unit.marketRentMonthly,
            offlineReason: unit.offlineReason,
            vacancySince: unit.vacancySince,
            vacancyReason: unit.vacancyReason,
            marketingStatus: unit.marketingStatus,
            renovationStatus: unit.renovationStatus,
            expectedReadyDate: unit.expectedReadyDate,
            nextAction: unit.nextAction,
            notes: unit.notes,
            createdAt: unit.createdAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (ref.read(selectedOperationsUnitIdProvider) == unit.id) {
      ref.read(selectedOperationsUnitIdProvider.notifier).state = null;
    }
    await _reload();
  }

  double? _parseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

String _statusLabel(String status) {
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Text(value == null ? 'Nicht gesetzt' : value!.toIso8601String().substring(0, 10)),
          ),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (context.mounted) {
                onPick(picked);
              }
            },
            child: const Text('Auswaehlen'),
          ),
          if (value != null)
            TextButton(
              onPressed: () => onPick(null),
              child: const Text('Leeren'),
            ),
        ],
      ),
    );
  }
}
