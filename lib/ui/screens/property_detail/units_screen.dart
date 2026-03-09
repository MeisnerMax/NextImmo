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
      final matchesStatus = _statusFilter == 'all' || unit.status == _statusFilter;
      final needle = _query.trim().toLowerCase();
      final matchesQuery =
          needle.isEmpty ||
          unit.unitCode.toLowerCase().contains(needle) ||
          (unit.unitType?.toLowerCase().contains(needle) ?? false) ||
          (unit.floor?.toLowerCase().contains(needle) ?? false);
      return matchesStatus && matchesQuery;
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
                label: const Text('Add Unit'),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Search Units',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'occupied', child: Text('occupied')),
                    DropdownMenuItem(value: 'vacant', child: Text('vacant')),
                    DropdownMenuItem(value: 'offline', child: Text('offline')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _statusFilter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1100;
                final listPane = Card(
                  child: filteredUnits.isEmpty
                      ? const Center(child: Text('No units match the current filters.'))
                      : ListView.builder(
                          itemCount: filteredUnits.length,
                          itemBuilder: (context, index) {
                            final unit = filteredUnits[index];
                            return ListTile(
                              selected: unit.id == selectedUnitId,
                              title: Text(unit.unitCode),
                              subtitle: Text(
                                '${unit.status}${unit.unitType == null ? '' : ' · ${unit.unitType}'}${unit.targetRentMonthly == null ? '' : ' · target ${unit.targetRentMonthly!.toStringAsFixed(2)}'}',
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  if (unit.status == 'vacant' && unit.vacancySince == null)
                                    const Tooltip(
                                      message: 'Missing vacancy date',
                                      child: Icon(Icons.warning_amber_outlined, color: Colors.orange),
                                    ),
                                  TextButton(
                                    onPressed: () => _editUnitDialog(unit),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    onPressed: () => _deleteUnit(unit.id),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                              onTap: () {
                                ref.read(selectedOperationsUnitIdProvider.notifier).state = unit.id;
                              },
                            );
                          },
                        ),
                );
                final detailPane = Card(
                  child: selectedUnit == null
                      ? const Center(child: Text('Select a unit to open the detail view.'))
                      : UnitDetailScreen(
                          propertyId: widget.propertyId,
                          unitId: selectedUnit.id,
                          onEdit: () => _editUnitDialog(selectedUnit),
                          onChanged: _reload,
                        ),
                );
                if (stacked) {
                  return Column(
                    children: [
                      Expanded(child: listPane),
                      const SizedBox(height: AppSpacing.component),
                      Expanded(child: detailPane),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 420, child: listPane),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(child: detailPane),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final units = await ref.read(rentRollRepositoryProvider).listUnitsByAsset(widget.propertyId);
    if (!mounted) {
      return;
    }
    final selectedId = ref.read(selectedOperationsUnitIdProvider);
    setState(() {
      _units = units;
      _status = null;
    });
    if (units.isNotEmpty && !units.any((unit) => unit.id == selectedId)) {
      ref.read(selectedOperationsUnitIdProvider.notifier).state = units.first.id;
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

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Unit' : 'Create Unit'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Unit Number / Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: unitTypeCtrl,
                    decoration: const InputDecoration(labelText: 'Unit Type'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'occupied', child: Text('occupied')),
                      DropdownMenuItem(value: 'vacant', child: Text('vacant')),
                      DropdownMenuItem(value: 'offline', child: Text('offline')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => status = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: floorCtrl, decoration: const InputDecoration(labelText: 'Floor')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bedsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Beds'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bathsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Baths'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sqftCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Size'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Target Rent'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: marketCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Market Rent'),
                  ),
                  if (status == 'offline') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: offlineReasonCtrl,
                      decoration: const InputDecoration(labelText: 'Offline Reason'),
                    ),
                  ],
                  if (status == 'vacant') ...[
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Vacancy Since',
                      value: vacancySince,
                      onPick: (value) => setDialogState(() => vacancySince = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: vacancyReasonCtrl,
                      decoration: const InputDecoration(labelText: 'Vacancy Reason'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: marketingStatusCtrl,
                      decoration: const InputDecoration(labelText: 'Marketing Status'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: renovationStatusCtrl,
                      decoration: const InputDecoration(labelText: 'Renovation Status'),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Expected Ready Date',
                      value: expectedReadyDate,
                      onPick: (value) => setDialogState(() => expectedReadyDate = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nextActionCtrl,
                      decoration: const InputDecoration(labelText: 'Next Action'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
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
              child: Text(isEdit ? 'Save' : 'Create'),
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
    await ref.read(rentRollRepositoryProvider).deleteUnit(unitId);
    if (ref.read(selectedOperationsUnitIdProvider) == unitId) {
      ref.read(selectedOperationsUnitIdProvider.notifier).state = null;
    }
    await _reload();
  }

  double? _parseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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
            child: Text(value == null ? 'Not set' : value!.toIso8601String().substring(0, 10)),
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
            child: const Text('Select'),
          ),
          if (value != null)
            TextButton(
              onPressed: () => onPick(null),
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}
