import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class RentRollScreen extends ConsumerStatefulWidget {
  const RentRollScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<RentRollScreen> createState() => _RentRollScreenState();
}

class _RentRollScreenState extends ConsumerState<RentRollScreen> {
  String _periodKey =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  List<RentRollSnapshotRecord> _snapshots = const [];
  RentRollSnapshotBundle? _selected;
  List<UnitRecord> _units = const [];
  List<LeaseRecord> _leases = const [];
  List<OperationsAlertRecord> _alerts = const [];
  String _statusFilter = 'all';
  String _unitTypeFilter = 'all';
  String _query = '';
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    final filteredRows = rows.where((row) {
      final matchesStatus = _statusFilter == 'all' || row.line.status == _statusFilter;
      final matchesUnitType = _unitTypeFilter == 'all' || row.unitType == _unitTypeFilter;
      final needle = _query.trim().toLowerCase();
      final matchesQuery =
          needle.isEmpty ||
          row.unitLabel.toLowerCase().contains(needle) ||
          row.tenantLabel.toLowerCase().contains(needle) ||
          row.leaseLabel.toLowerCase().contains(needle);
      return matchesStatus && matchesUnitType && matchesQuery;
    }).toList(growable: false);
    final priorSnapshot = _selected == null ? null : _findPriorSnapshot(_selected!.snapshot.id);
    final occupiedCount = rows.where((row) => row.line.status == 'occupied').length;
    final vacancyCount = rows.where((row) => row.line.status == 'vacant').length;
    final offlineCount = rows.where((row) => row.line.status == 'offline').length;
    final totalInPlace = rows.fold<double>(0, (sum, row) => sum + row.line.inPlaceRentMonthly);
    final averageRent = rows.isEmpty ? 0 : totalInPlace / rows.length;
    final deltaInPlace = priorSnapshot == null
        ? null
        : _selected!.snapshot.inPlaceRentMonthly - priorSnapshot.inPlaceRentMonthly;
    final deltaOccupancy = priorSnapshot == null
        ? null
        : _selected!.snapshot.occupancyRate - priorSnapshot.occupancyRate;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MonthField(
                label: 'Period',
                value: _periodKey,
                onChanged: (value) => setState(() => _periodKey = value),
              ),
              ElevatedButton(
                onPressed: _generateSnapshot,
                child: const Text('Generate Snapshot'),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
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
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _unitTypeFilter,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Types')),
                    ..._unitTypes()
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _unitTypeFilter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Unit Type'),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Search Unit or Tenant',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kpiTile('Occupied', '$occupiedCount'),
              _kpiTile('Vacant', '$vacancyCount'),
              _kpiTile('Offline', '$offlineCount'),
              _kpiTile('In Place Rent', totalInPlace.toStringAsFixed(2)),
              _kpiTile('Average Rent', averageRent.toStringAsFixed(2)),
              _kpiTile(
                'Delta vs Prior',
                deltaInPlace == null
                    ? '-'
                    : '${deltaInPlace.toStringAsFixed(2)} / ${(deltaOccupancy! * 100).toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: _snapshots.isEmpty
                        ? const Center(child: Text('No snapshots yet.'))
                        : ListView.builder(
                            itemCount: _snapshots.length,
                            itemBuilder: (context, index) {
                              final snapshot = _snapshots[index];
                              return ListTile(
                                selected: _selected?.snapshot.id == snapshot.id,
                                title: Text(snapshot.periodKey),
                                subtitle: Text(
                                  'Occ ${(snapshot.occupancyRate * 100).toStringAsFixed(1)}% · In Place ${snapshot.inPlaceRentMonthly.toStringAsFixed(2)}',
                                ),
                                onTap: () => _loadSnapshot(snapshot.id),
                                trailing: TextButton(
                                  onPressed: () => _deleteSnapshot(snapshot.id),
                                  child: const Text('Delete'),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.component),
                Expanded(
                  flex: 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: _selected == null
                          ? const Center(child: Text('Select a snapshot'))
                          : filteredRows.isEmpty
                              ? const Center(child: Text('No rent roll rows match the current filters.'))
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Unit')),
                                      DataColumn(label: Text('Tenant')),
                                      DataColumn(label: Text('Lease')),
                                      DataColumn(label: Text('Status')),
                                      DataColumn(label: Text('In Place')),
                                      DataColumn(label: Text('Market')),
                                      DataColumn(label: Text('Variance')),
                                      DataColumn(label: Text('Deposit')),
                                      DataColumn(label: Text('Lease End')),
                                      DataColumn(label: Text('Days')),
                                      DataColumn(label: Text('Flags')),
                                    ],
                                    rows: filteredRows
                                        .map(
                                          (row) => DataRow(
                                            cells: [
                                              DataCell(Text(row.unitLabel)),
                                              DataCell(Text(row.tenantLabel)),
                                              DataCell(Text(row.leaseLabel)),
                                              DataCell(Text(row.line.status)),
                                              DataCell(Text(row.line.inPlaceRentMonthly.toStringAsFixed(2))),
                                              DataCell(Text(row.line.marketRentMonthly?.toStringAsFixed(2) ?? '-')),
                                              DataCell(Text(row.varianceText)),
                                              DataCell(Text(row.depositStatus)),
                                              DataCell(Text(formatDateMillis(row.line.leaseEndDate))),
                                              DataCell(Text(row.daysToExpiryText)),
                                              DataCell(
                                                SizedBox(
                                                  width: 220,
                                                  child: Wrap(
                                                    spacing: 4,
                                                    runSpacing: 4,
                                                    children: row.flags
                                                        .map(
                                                          (flag) => Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFFEAF1F8),
                                                              borderRadius: BorderRadius.circular(999),
                                                            ),
                                                            child: Text(flag, style: const TextStyle(fontSize: 12)),
                                                          ),
                                                        )
                                                        .toList(growable: false),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFEAF1F8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final rentRollRepo = ref.read(rentRollRepositoryProvider);
    final leaseRepo = ref.read(leaseRepositoryProvider);
    final operationsRepo = ref.read(operationsRepositoryProvider);
    final snapshots = await rentRollRepo.listSnapshots(widget.propertyId);
    final units = await rentRollRepo.listUnitsByAsset(widget.propertyId);
    final leases = await leaseRepo.listLeasesByAsset(widget.propertyId);
    final alerts = await operationsRepo.loadAlerts(widget.propertyId);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshots = snapshots;
      _units = units;
      _leases = leases;
      _alerts = alerts.where((alert) => alert.status == 'open').toList(growable: false);
    });
    if (snapshots.isNotEmpty) {
      await _loadSnapshot(snapshots.first.id);
    }
  }

  Future<void> _generateSnapshot() async {
    try {
      final bundle = await ref.read(rentRollRepositoryProvider).generateSnapshot(
            assetPropertyId: widget.propertyId,
            periodKey: _periodKey,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _selected = bundle;
        _status = 'Snapshot generated for $_periodKey';
      });
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Failed to generate snapshot: $error';
      });
    }
  }

  Future<void> _loadSnapshot(String snapshotId) async {
    final bundle = await ref.read(rentRollRepositoryProvider).getSnapshot(snapshotId);
    if (!mounted || bundle == null) {
      return;
    }
    setState(() {
      _selected = bundle;
    });
  }

  Future<void> _deleteSnapshot(String snapshotId) async {
    await ref.read(rentRollRepositoryProvider).deleteSnapshot(snapshotId);
    await _reload();
  }

  List<String> _unitTypes() {
    return _units
        .map((unit) => unit.unitType)
        .whereType<String>()
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  RentRollSnapshotRecord? _findPriorSnapshot(String snapshotId) {
    for (var index = 0; index < _snapshots.length; index += 1) {
      if (_snapshots[index].id == snapshotId && index + 1 < _snapshots.length) {
        return _snapshots[index + 1];
      }
    }
    return null;
  }

  List<_RentRollDisplayRow> _buildRows() {
    final selected = _selected;
    if (selected == null) {
      return const <_RentRollDisplayRow>[];
    }
    final leasesById = <String, LeaseRecord>{for (final lease in _leases) lease.id: lease};
    final unitsById = <String, UnitRecord>{for (final unit in _units) unit.id: unit};
    return selected.lines
        .map((line) {
          final lease = line.leaseId == null ? null : leasesById[line.leaseId];
          final unit = unitsById[line.unitId];
          final flags = _alerts
              .where(
                (alert) =>
                    alert.unitId == line.unitId ||
                    (line.leaseId != null && alert.leaseId == line.leaseId),
              )
              .map((alert) => alert.type.replaceAll('_', ' '))
              .toSet()
              .toList(growable: false);
          if (flags.isEmpty && lease == null && line.status == 'occupied') {
            flags.add('no active lease');
          }
          return _RentRollDisplayRow(
            line: line,
            unitLabel: unit?.unitCode ?? line.unitId,
            unitType: unit?.unitType ?? '-',
            tenantLabel: line.tenantName ?? '-',
            leaseLabel: lease?.leaseName ?? '-',
            depositStatus: lease?.depositStatus ?? '-',
            flags: flags,
          );
        })
        .toList(growable: false);
  }
}

class _RentRollDisplayRow {
  const _RentRollDisplayRow({
    required this.line,
    required this.unitLabel,
    required this.unitType,
    required this.tenantLabel,
    required this.leaseLabel,
    required this.depositStatus,
    required this.flags,
  });

  final RentRollLineRecord line;
  final String unitLabel;
  final String unitType;
  final String tenantLabel;
  final String leaseLabel;
  final String depositStatus;
  final List<String> flags;

  String get varianceText {
    if (line.marketRentMonthly == null) {
      return '-';
    }
    return (line.inPlaceRentMonthly - line.marketRentMonthly!).toStringAsFixed(2);
  }

  String get daysToExpiryText {
    if (line.leaseEndDate == null) {
      return '-';
    }
    final days = DateTime.fromMillisecondsSinceEpoch(line.leaseEndDate!)
        .difference(DateTime.now())
        .inDays;
    return '$days';
  }
}

class _MonthField extends StatelessWidget {
  const _MonthField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            TextButton(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _parsePeriod(value) ?? now,
                  firstDate: DateTime(now.year - 20),
                  lastDate: DateTime(now.year + 20),
                );
                if (picked != null && context.mounted) {
                  onChanged('${picked.year}-${picked.month.toString().padLeft(2, '0')}');
                }
              },
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _parsePeriod(String value) {
    final parts = value.split('-');
    if (parts.length != 2) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) {
      return null;
    }
    return DateTime(year, month);
  }
}
