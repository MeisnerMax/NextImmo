import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'unit_detail_screen.dart';
import 'tenants_screen.dart';
import 'leases_screen.dart';
import 'property_tasks_screen.dart';

class UnitsScreen extends ConsumerStatefulWidget {
  const UnitsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends ConsumerState<UnitsScreen> with SingleTickerProviderStateMixin {
  List<UnitRecord> _units = const [];
  List<TenantRecord> _prospects = const [];
  String? _status;
  String _query = '';
  String _statusFilter = 'all';
  late TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _tabIndex = _tabController.index;
        });
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Einheiten'),
                Tab(text: 'Mieter'),
                Tab(text: 'Mietverträge'),
                Tab(text: 'Vermietungspipeline'),
                Tab(text: 'Aufgaben'),
              ],
            ),
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _status!,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(height: AppSpacing.component),
        _buildActiveTab(),
      ],
    );
  }

  Widget _buildActiveTab() {
    switch (_tabIndex) {
      case 0:
        return _buildUnitsTab();
      case 1:
        return TenantsScreen(propertyId: widget.propertyId);
      case 2:
        return LeasesScreen(propertyId: widget.propertyId);
      case 3:
        return _buildPipelineTab();
      case 4:
        return PropertyTasksScreen(propertyId: widget.propertyId);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUnitsTab() {
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

    // KPI Metrics calculation
    final activeUnits = _units.where((u) => u.status != 'archived').toList();
    final totalCount = activeUnits.length;
    final occupiedCount = activeUnits.where((u) => u.status == 'occupied').length;
    final vacantCount = activeUnits.where((u) => u.status == 'vacant').length;
    final occupancyRate = totalCount == 0 ? 0.0 : (occupiedCount / totalCount) * 100;

    double totalTargetRent = 0;
    int targetRentCount = 0;
    double totalMarketRent = 0;
    int marketRentCount = 0;
    for (final u in activeUnits) {
      if (u.targetRentMonthly != null) {
        totalTargetRent += u.targetRentMonthly!;
        targetRentCount++;
      }
      if (u.marketRentMonthly != null) {
        totalMarketRent += u.marketRentMonthly!;
        marketRentCount++;
      }
    }
    final avgTargetRent = targetRentCount == 0 ? 0.0 : totalTargetRent / targetRentCount;
    final avgMarketRent = marketRentCount == 0 ? 0.0 : totalMarketRent / marketRentCount;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Metric Row
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _KpiTile(
                title: 'Belegungsquote',
                value: '${occupancyRate.toStringAsFixed(1)} %',
                subtitle: '$occupiedCount von $totalCount Einheiten',
                icon: Icons.pie_chart_outline,
                color: context.semanticColors.success,
              ),
              _KpiTile(
                title: 'Einheiten gesamt',
                value: '$totalCount',
                icon: Icons.business_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              _KpiTile(
                title: 'Leerstand',
                value: '$vacantCount',
                subtitle: '${(totalCount == 0 ? 0.0 : (vacantCount / totalCount) * 100).toStringAsFixed(1)} % Quote',
                icon: Icons.door_sliding_outlined,
                color: vacantCount > 0 ? context.semanticColors.warning : context.semanticColors.success,
              ),
              _KpiTile(
                title: 'Ø Soll-Miete',
                value: '${avgTargetRent.toStringAsFixed(2)} €',
                icon: Icons.euro_outlined,
                color: context.semanticColors.info,
              ),
              _KpiTile(
                title: 'Ø Marktmiete',
                value: '${avgMarketRent.toStringAsFixed(2)} €',
                icon: Icons.show_chart_outlined,
                color: context.semanticColors.info,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
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

  Widget _buildUnitListItem(BuildContext context, UnitRecord unit, bool isSelected) {
    final semantic = context.semanticColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusColor = switch (unit.status) {
      'occupied' => semantic.success,
      'vacant' => semantic.warning,
      'offline' => semantic.error,
      'archived' => Theme.of(context).colorScheme.outlineVariant,
      _ => semantic.border,
    };

    IconData typeIcon = switch (unit.unitType?.toLowerCase() ?? '') {
      'apartment' || 'wohnung' => Icons.apartment_outlined,
      'commercial' || 'gewerbe' || 'büro' || 'office' => Icons.business_outlined,
      'parking' || 'stellplatz' || 'garage' => Icons.local_parking_outlined,
      _ => Icons.home_work_outlined,
    };

    final bool isMissingVacancyDate = unit.status == 'vacant' && unit.vacancySince == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF))
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : semantic.border,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadiusTokens.md - 1),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: statusColor,
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    ref.read(selectedOperationsUnitIdProvider.notifier).state = unit.id;
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(typeIcon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                unit.unitCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            _buildUnitStatusTag(context, unit.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${unit.floor != null ? "${unit.floor}. Etage · " : ""}${unit.sqft != null ? "${unit.sqft!.toStringAsFixed(1)} m²" : ""}',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (unit.targetRentMonthly != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Soll: ${unit.targetRentMonthly!.toStringAsFixed(2)} €',
                                      style: context.tabularNumericStyle.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isMissingVacancyDate)
                              const Tooltip(
                                message: 'Leerstandsdatum fehlt',
                                child: Icon(
                                  Icons.warning_amber_outlined,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _editUnitDialog(unit),
                              child: const Text('Bearbeiten', style: TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            if (unit.status == 'archived')
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _deleteUnit(unit.id),
                                child: const Text('Löschen', style: TextStyle(fontSize: 11, color: Colors.red)),
                              )
                            else
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _archiveUnit(unit),
                                child: const Text('Archivieren', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitStatusTag(BuildContext context, String status) {
    final semantic = context.semanticColors;
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'occupied':
        bgColor = semantic.success.withValues(alpha: 0.12);
        textColor = semantic.success;
        label = 'Vermietet';
        break;
      case 'vacant':
        bgColor = semantic.warning.withValues(alpha: 0.12);
        textColor = semantic.warning;
        label = 'Leer';
        break;
      case 'offline':
        bgColor = semantic.error.withValues(alpha: 0.12);
        textColor = semantic.error;
        label = 'Offline';
        break;
      case 'archived':
        bgColor = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2);
        textColor = Theme.of(context).colorScheme.onSurfaceVariant;
        label = 'Archiviert';
        break;
      default:
        bgColor = Theme.of(context).colorScheme.outlineVariant;
        textColor = Theme.of(context).colorScheme.onSurface;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
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
              ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final unit in units)
                    _buildUnitListItem(context, unit, unit.id == selectedUnitId),
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

  Widget _buildPipelineTab() {
    final anfragen = _prospects.where((p) => p.moveInReference == null || p.moveInReference!.isEmpty || p.moveInReference == 'request').toList();
    final besichtigungen = _prospects.where((p) => p.moveInReference == 'viewing').toList();
    final bonitaet = _prospects.where((p) => p.moveInReference == 'credit').toList();
    final vertrag = _prospects.where((p) => p.moveInReference == 'contract').toList();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _prospectDialog(),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Interessent anlegen'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKanbanColumn(
                title: 'Mietanfragen',
                stage: 'request',
                prospects: anfragen,
              ),
              const SizedBox(width: 8),
              _buildKanbanColumn(
                title: 'Besichtigungen',
                stage: 'viewing',
                prospects: besichtigungen,
              ),
              const SizedBox(width: 8),
              _buildKanbanColumn(
                title: 'Bonität & Prüfung',
                stage: 'credit',
                prospects: bonitaet,
              ),
              const SizedBox(width: 8),
              _buildKanbanColumn(
                title: 'Vertragsvorbereitung',
                stage: 'contract',
                prospects: vertrag,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanColumn({
    required String title,
    required String stage,
    required List<TenantRecord> prospects,
  }) {
    return Expanded(
      child: Card(
        color: const Color(0xFFF8FAFC),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${prospects.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (prospects.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text(
                      'Keine Interessenten',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: prospects.length,
                  itemBuilder: (context, index) {
                    final prospect = prospects[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prospect.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (prospect.email != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                prospect.email!,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (prospect.phone != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                prospect.phone!,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16),
                                  onPressed: () => _prospectDialog(existing: prospect),
                                  tooltip: 'Bearbeiten',
                                ),
                                Row(
                                  children: [
                                    if (stage != 'request')
                                      IconButton(
                                        icon: const Icon(Icons.arrow_back, size: 16),
                                        onPressed: () => _moveStage(prospect, -1),
                                        tooltip: 'Zurücksetzen',
                                      ),
                                    if (stage != 'contract')
                                      IconButton(
                                        icon: const Icon(Icons.arrow_forward, size: 16),
                                        onPressed: () => _moveStage(prospect, 1),
                                        tooltip: 'Vorrücken',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveStage(TenantRecord prospect, int dir) {
    final stages = ['request', 'viewing', 'credit', 'contract'];
    final currentStage = prospect.moveInReference ?? 'request';
    var idx = stages.indexOf(currentStage);
    if (idx == -1) idx = 0;
    final nextIdx = idx + dir;
    if (nextIdx >= 0 && nextIdx < stages.length) {
      _updateProspectStage(prospect, stages[nextIdx]);
    }
  }

  Future<void> _updateProspectStage(TenantRecord prospect, String stage) async {
    await ref.read(leaseRepositoryProvider).upsertTenant(
          id: prospect.id,
          displayName: prospect.displayName,
          legalName: prospect.legalName,
          email: prospect.email,
          phone: prospect.phone,
          alternativeContact: prospect.alternativeContact,
          billingContact: prospect.billingContact,
          status: prospect.status,
          moveInReference: stage,
          notes: prospect.notes,
        );
    await _reload();
  }

  Future<void> _prospectDialog({TenantRecord? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String stage = existing?.moveInReference ?? 'request';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Interessent anlegen' : 'Interessent bearbeiten'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Anzeigename'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Telefon'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: stage,
                    items: const [
                      DropdownMenuItem(value: 'request', child: Text('Mietanfrage')),
                      DropdownMenuItem(value: 'viewing', child: Text('Besichtigung')),
                      DropdownMenuItem(value: 'credit', child: Text('Bonität & Prüfung')),
                      DropdownMenuItem(value: 'contract', child: Text('Vertragsvorbereitung')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => stage = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Pipeline-Stufe'),
                  ),
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
                final displayName = nameCtrl.text.trim();
                if (displayName.isEmpty) {
                  return;
                }
                try {
                  await ref.read(leaseRepositoryProvider).upsertTenant(
                        id: existing?.id,
                        displayName: displayName,
                        legalName: existing?.legalName,
                        email: _nullIfEmpty(emailCtrl.text),
                        phone: _nullIfEmpty(phoneCtrl.text),
                        status: 'prospect',
                        moveInReference: stage,
                        notes: _nullIfEmpty(notesCtrl.text),
                      );
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
              child: Text(existing == null ? 'Anlegen' : 'Speichern'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _reload() async {
    final units = await ref
        .read(rentRollRepositoryProvider)
        .listUnitsByAsset(widget.propertyId, includeArchived: true);
    final allTenants = await ref.read(leaseRepositoryProvider).listTenants();
    if (!mounted) {
      return;
    }
    final selectedId = ref.read(selectedOperationsUnitIdProvider);
    setState(() {
      _units = units;
      _prospects = allTenants.where((tenant) => tenant.status == 'prospect').toList();
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

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(icon, size: 16, color: color),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ).merge(context.tabularNumericStyle),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

