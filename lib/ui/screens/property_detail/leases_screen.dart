import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../components/nx_card.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'lease_detail_screen.dart';

class LeasesScreen extends ConsumerStatefulWidget {
  const LeasesScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<LeasesScreen> createState() => _LeasesScreenState();
}

class _LeasesScreenState extends ConsumerState<LeasesScreen> {
  List<UnitRecord> _units = const [];
  List<LeaseRecord> _leases = const [];
  List<TenantRecord> _tenants = const [];
  String _query = '';
  String _filter = 'all';
  String _fromPeriod = '${DateTime.now().year}-01';
  String _toPeriod = '${DateTime.now().year}-12';
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLeaseId = ref.watch(selectedOperationsLeaseIdProvider);
    final leases = _filteredLeases();
    LeaseRecord? selectedLease;
    for (final lease in leases) {
      if (lease.id == selectedLeaseId) {
        selectedLease = lease;
        break;
      }
    }

    // KPI Calculation
    final activeLeases = _leases.where((l) => l.status == 'active').toList();
    double totalBaseRent = 0;
    for (final l in activeLeases) {
      totalBaseRent += l.baseRentMonthly;
    }
    final now = DateTime.now();
    final ninetyDaysFromNow = now.add(const Duration(days: 90));
    final expiringSoonCount = activeLeases.where((l) {
      if (l.endDate == null) return false;
      final end = DateTime.fromMillisecondsSinceEpoch(l.endDate!);
      return end.isBefore(ninetyDaysFromNow) && end.isAfter(now);
    }).length;
    final missingDepositCount = activeLeases.where((l) {
      return l.securityDeposit == null || l.securityDeposit == 0 || l.depositStatus == 'pending';
    }).length;

    return SingleChildScrollView(
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
                title: 'Mieteinnahmen mtl.',
                value: '${totalBaseRent.toStringAsFixed(2)} €',
                subtitle: 'Aus aktiven Verträgen',
                icon: Icons.monetization_on_outlined,
                color: context.semanticColors.success,
              ),
              _KpiTile(
                title: 'Aktive Verträge',
                value: '${activeLeases.length}',
                icon: Icons.assignment_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              _KpiTile(
                title: 'Auslaufend (90 Tage)',
                value: '$expiringSoonCount',
                icon: Icons.running_with_errors_outlined,
                color: expiringSoonCount > 0 ? context.semanticColors.warning : context.semanticColors.success,
              ),
              _KpiTile(
                title: 'Kaution ausstehend',
                value: '$missingDepositCount',
                icon: Icons.lock_clock_outlined,
                color: missingDepositCount > 0 ? context.semanticColors.error : context.semanticColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _leaseDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Mietvertrag anlegen'),
              ),
              OutlinedButton(
                onPressed: () => _tenantDialog(),
                child: const Text('Mieter anlegen'),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Mietvertraege suchen',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _filter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle Vertraege')),
                    DropdownMenuItem(value: 'draft', child: Text('Entwurf')),
                    DropdownMenuItem(value: 'future', child: Text('Zukuenftig')),
                    DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                    DropdownMenuItem(value: 'terminated', child: Text('Gekuendigt')),
                    DropdownMenuItem(value: 'expired', child: Text('Abgelaufen')),
                    DropdownMenuItem(value: 'expiring_soon', child: Text('Laeuft bald aus')),
                    DropdownMenuItem(value: 'missing_deposit', child: Text('Kaution fehlt')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _filter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Filter'),
                ),
              ),
              _MonthField(
                label: 'Von',
                value: _fromPeriod,
                onChanged: (value) => setState(() => _fromPeriod = value),
              ),
              _MonthField(
                label: 'Bis',
                value: _toPeriod,
                onChanged: (value) => setState(() => _toPeriod = value),
              ),
              OutlinedButton(
                onPressed: selectedLease == null ? null : _generateSchedule,
                child: const Text('Mietplan erzeugen'),
              ),
              OutlinedButton(onPressed: _reload, child: const Text('Aktualisieren')),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_status!, style: const TextStyle(color: Colors.red)),
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1120;
              final listPane = _leaseListCard(
                context: context,
                leases: leases,
                selectedLeaseId: selectedLeaseId,
              );
              final detailPane = _leaseDetailCard(selectedLease);
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

  Widget _buildLeaseListItem(BuildContext context, LeaseRecord lease, bool isSelected) {
    final semantic = context.semanticColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusColor = switch (lease.status) {
      'active' => semantic.success,
      'draft' => Theme.of(context).colorScheme.outlineVariant,
      'future' => Theme.of(context).colorScheme.primary,
      'terminated' => semantic.warning,
      'expired' => semantic.error,
      _ => semantic.border,
    };

    final bool isMissingDeposit = _hasMissingDeposit(lease);

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
                    ref.read(selectedOperationsLeaseIdProvider.notifier).state = lease.id;
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.description_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                lease.leaseName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            _buildLeaseStatusTag(context, lease.status),
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
                                    'Einheit: ${_unitName(lease.unitId)} · Mieter: ${_tenantName(lease.tenantId)}',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Miete: ${lease.baseRentMonthly.toStringAsFixed(2)} €',
                                    style: context.tabularNumericStyle.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isMissingDeposit)
                              const Tooltip(
                                message: 'Kaution ausstehend / fehlt',
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
                              onPressed: () => _leaseDialog(existing: lease),
                              child: const Text('Bearbeiten', style: TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _deleteLease(lease.id),
                              child: const Text('Löschen', style: TextStyle(fontSize: 11, color: Colors.red)),
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

  Widget _buildLeaseStatusTag(BuildContext context, String status) {
    final semantic = context.semanticColors;
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'active':
        bgColor = semantic.success.withValues(alpha: 0.12);
        textColor = semantic.success;
        label = 'Aktiv';
        break;
      case 'draft':
        bgColor = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2);
        textColor = Theme.of(context).colorScheme.onSurfaceVariant;
        label = 'Entwurf';
        break;
      case 'future':
        bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
        textColor = Theme.of(context).colorScheme.primary;
        label = 'Zukünftig';
        break;
      case 'terminated':
        bgColor = semantic.warning.withValues(alpha: 0.12);
        textColor = semantic.warning;
        label = 'Gekündigt';
        break;
      case 'expired':
        bgColor = semantic.error.withValues(alpha: 0.12);
        textColor = semantic.error;
        label = 'Abgelaufen';
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

  Widget _leaseListCard({
    required BuildContext context,
    required List<LeaseRecord> leases,
    required String? selectedLeaseId,
  }) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mietverträge', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (leases.isEmpty)
            const Text('Keine Mietvertraege fuer diese Filter.')
          else
            Column(
              children: [
                for (final lease in leases)
                  _buildLeaseListItem(context, lease, lease.id == selectedLeaseId),
              ],
            ),
        ],
      ),
    );
  }

  Widget _leaseDetailCard(LeaseRecord? selectedLease) {
    if (selectedLease == null) {
      return const NxCard(
        child: Text('Mietvertrag auswaehlen, um Details zu oeffnen.'),
      );
    }
    return NxCard(
      padding: EdgeInsets.zero,
      child: LeaseDetailScreen(
        propertyId: widget.propertyId,
        leaseId: selectedLease.id,
        onEdit: () => _leaseDialog(existing: selectedLease),
        onAddRule: _addRuleDialog,
        onAddManualOverride: _manualOverrideDialog,
        onChanged: _reload,
      ),
    );
  }

  List<LeaseRecord> _filteredLeases() {
    return _leases.where((lease) {
      final needle = _query.trim().toLowerCase();
      final expiringSoon =
          lease.endDate != null &&
          DateTime.fromMillisecondsSinceEpoch(lease.endDate!).isBefore(
            DateTime.now().add(const Duration(days: 90)),
          ) &&
          DateTime.fromMillisecondsSinceEpoch(lease.endDate!).isAfter(DateTime.now());
      final matchesFilter =
          _filter == 'all' ||
          lease.status == _filter ||
          (_filter == 'expiring_soon' && expiringSoon) ||
          (_filter == 'missing_deposit' && _hasMissingDeposit(lease));
      final matchesQuery =
          needle.isEmpty ||
          lease.leaseName.toLowerCase().contains(needle) ||
          _unitName(lease.unitId).toLowerCase().contains(needle) ||
          _tenantName(lease.tenantId).toLowerCase().contains(needle);
      return matchesFilter && matchesQuery;
    }).toList(growable: false);
  }

  Future<void> _reload() async {
    final rentRollRepo = ref.read(rentRollRepositoryProvider);
    final leaseRepo = ref.read(leaseRepositoryProvider);
    final units = await rentRollRepo.listUnitsByAsset(
      widget.propertyId,
      includeArchived: true,
    );
    final leases = await leaseRepo.listLeasesByAsset(widget.propertyId);
    final tenants = await leaseRepo.listTenants();
    if (!mounted) {
      return;
    }
    final selectedId = ref.read(selectedOperationsLeaseIdProvider);
    setState(() {
      _units = units;
      _leases = leases;
      _tenants = tenants;
      _status = null;
    });
    if (leases.isNotEmpty && !leases.any((lease) => lease.id == selectedId)) {
      ref.read(selectedOperationsLeaseIdProvider.notifier).state = leases.first.id;
    }
  }

  Future<void> _tenantDialog({TenantRecord? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Mieter anlegen' : 'Mieter bearbeiten'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
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
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                return;
              }
              await ref.read(leaseRepositoryProvider).upsertTenant(
                    id: existing?.id,
                    displayName: name,
                    email: _nullIfEmpty(emailCtrl.text),
                    phone: _nullIfEmpty(phoneCtrl.text),
                  );
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              await _reload();
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _leaseDialog({LeaseRecord? existing}) async {
    if (_units.isEmpty) {
      setState(() => _status = 'Bitte zuerst eine Einheit anlegen.');
      return;
    }
    final selectedUnitId = ref.read(selectedOperationsUnitIdProvider);
    String unitId =
        existing?.unitId ??
        (selectedUnitId != null && _units.any((unit) => unit.id == selectedUnitId)
            ? selectedUnitId
            : _units.first.id);
    String? tenantId = existing?.tenantId ?? (_tenants.isEmpty ? null : _tenants.first.id);
    String status = existing?.status ?? 'draft';
    String billingFrequency = existing?.billingFrequency ?? 'monthly';
    String depositStatus = existing?.depositStatus ?? 'unknown';
    final nameCtrl = TextEditingController(text: existing?.leaseName ?? '');
    final rentCtrl = TextEditingController(text: existing?.baseRentMonthly.toStringAsFixed(2) ?? '');
    final depositCtrl = TextEditingController(text: existing?.securityDeposit?.toString() ?? '');
    final paymentCtrl = TextEditingController(text: existing?.paymentDayOfMonth?.toString() ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    DateTime startDate =
        existing == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(existing.startDate);
    DateTime? endDate =
        existing?.endDate == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.endDate!);
    DateTime? moveInDate =
        existing?.moveInDate == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.moveInDate!);
    DateTime? moveOutDate =
        existing?.moveOutDate == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.moveOutDate!);
    DateTime? signedDate =
        existing?.leaseSignedDate == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.leaseSignedDate!);
    DateTime? noticeDate =
        existing?.noticeDate == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!.noticeDate!);
    final unitItems = <DropdownMenuItem<String>>[
      if (!_units.any((unit) => unit.id == unitId))
        DropdownMenuItem(
          value: unitId,
          child: Text('Aktuelle Einheit: $unitId'),
        ),
      ..._units.map(
        (unit) => DropdownMenuItem(value: unit.id, child: Text(unit.unitCode)),
      ),
    ];
    final tenantItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('Kein Mieter')),
      if (tenantId != null && !_tenants.any((tenant) => tenant.id == tenantId))
        DropdownMenuItem<String?>(
          value: tenantId,
          child: Text('Aktueller Mieter: $tenantId'),
        ),
      ..._tenants.map(
        (tenant) => DropdownMenuItem<String?>(
          value: tenant.id,
          child: Text(tenant.displayName),
        ),
      ),
    ];
    const allowedBillingFrequencies = <String>['monthly', 'quarterly', 'yearly'];
    final billingItems = <DropdownMenuItem<String>>[
      if (!allowedBillingFrequencies.contains(billingFrequency))
        DropdownMenuItem(value: billingFrequency, child: Text(_billingLabel(billingFrequency))),
      const DropdownMenuItem(value: 'monthly', child: Text('Monatlich')),
      const DropdownMenuItem(value: 'quarterly', child: Text('Quartalsweise')),
      const DropdownMenuItem(value: 'yearly', child: Text('Jaehrlich')),
    ];
    const allowedStatuses = <String>[
      'draft',
      'future',
      'active',
      'terminated',
      'expired',
    ];
    final statusItems = <DropdownMenuItem<String>>[
      if (!allowedStatuses.contains(status))
        DropdownMenuItem(value: status, child: Text(_leaseStatusLabel(status))),
      const DropdownMenuItem(value: 'draft', child: Text('Entwurf')),
      const DropdownMenuItem(value: 'future', child: Text('Zukuenftig')),
      const DropdownMenuItem(value: 'active', child: Text('Aktiv')),
      const DropdownMenuItem(value: 'terminated', child: Text('Gekuendigt')),
      const DropdownMenuItem(value: 'expired', child: Text('Abgelaufen')),
    ];
    const allowedDepositStatuses = <String>[
      'unknown',
      'pending',
      'received',
      'waived',
    ];
    final depositItems = <DropdownMenuItem<String>>[
      if (!allowedDepositStatuses.contains(depositStatus))
        DropdownMenuItem(value: depositStatus, child: Text(_depositLabel(depositStatus))),
      const DropdownMenuItem(value: 'unknown', child: Text('Unbekannt')),
      const DropdownMenuItem(value: 'pending', child: Text('Ausstehend')),
      const DropdownMenuItem(value: 'received', child: Text('Erhalten')),
      const DropdownMenuItem(value: 'waived', child: Text('Erlassen')),
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Mietvertrag anlegen' : 'Mietvertrag bearbeiten'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: unitId,
                    items: unitItems,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => unitId = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Einheit'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: tenantId,
                    items: tenantItems,
                    onChanged: (value) => setDialogState(() => tenantId = value),
                    decoration: const InputDecoration(labelText: 'Mieter'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Vertragsname')),
                  const SizedBox(height: 8),
                  _DateField(label: 'Startdatum', value: startDate, onPick: (value) => setDialogState(() => startDate = value ?? startDate)),
                  const SizedBox(height: 8),
                  _DateField(label: 'Enddatum', value: endDate, onPick: (value) => setDialogState(() => endDate = value)),
                  const SizedBox(height: 8),
                  _DateField(label: 'Einzugsdatum', value: moveInDate, onPick: (value) => setDialogState(() => moveInDate = value)),
                  const SizedBox(height: 8),
                  _DateField(label: 'Auszugsdatum', value: moveOutDate, onPick: (value) => setDialogState(() => moveOutDate = value)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: rentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Grundmiete'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: depositCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Kaution'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: paymentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Zahlungstag im Monat'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: billingFrequency,
                    items: billingItems,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => billingFrequency = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Abrechnungsrhythmus'),
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
                  DropdownButtonFormField<String>(
                    value: depositStatus,
                    items: depositItems,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => depositStatus = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Kautionsstatus'),
                  ),
                  const SizedBox(height: 8),
                  _DateField(label: 'Unterschrieben am', value: signedDate, onPick: (value) => setDialogState(() => signedDate = value)),
                  const SizedBox(height: 8),
                  _DateField(label: 'Kuendigungsdatum', value: noticeDate, onPick: (value) => setDialogState(() => noticeDate = value)),
                  const SizedBox(height: 8),
                  TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Notizen')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                final rent = _parseDouble(rentCtrl.text);
                if (nameCtrl.text.trim().isEmpty || rent == null) {
                  return;
                }
                try {
                  if (existing == null) {
                    final created = await ref.read(leaseRepositoryProvider).createLease(
                          assetPropertyId: widget.propertyId,
                          unitId: unitId,
                          tenantId: tenantId,
                          leaseName: nameCtrl.text.trim(),
                          startDate: startDate.millisecondsSinceEpoch,
                          endDate: endDate?.millisecondsSinceEpoch,
                          moveInDate: moveInDate?.millisecondsSinceEpoch,
                          moveOutDate: moveOutDate?.millisecondsSinceEpoch,
                          status: status,
                          baseRentMonthly: rent,
                          securityDeposit: _parseDouble(depositCtrl.text),
                          paymentDayOfMonth: _parseInt(paymentCtrl.text),
                          billingFrequency: billingFrequency,
                          leaseSignedDate: signedDate?.millisecondsSinceEpoch,
                          noticeDate: noticeDate?.millisecondsSinceEpoch,
                          depositStatus: depositStatus,
                          notes: _nullIfEmpty(notesCtrl.text),
                        );
                    ref.read(selectedOperationsLeaseIdProvider.notifier).state = created.id;
                  } else {
                    await ref.read(leaseRepositoryProvider).updateLease(
                          LeaseRecord(
                            id: existing.id,
                            assetPropertyId: existing.assetPropertyId,
                            unitId: unitId,
                            tenantId: tenantId,
                            leaseName: nameCtrl.text.trim(),
                            startDate: startDate.millisecondsSinceEpoch,
                            endDate: endDate?.millisecondsSinceEpoch,
                            moveInDate: moveInDate?.millisecondsSinceEpoch,
                            moveOutDate: moveOutDate?.millisecondsSinceEpoch,
                            status: status,
                            baseRentMonthly: rent,
                            currencyCode: existing.currencyCode,
                            securityDeposit: _parseDouble(depositCtrl.text),
                            paymentDayOfMonth: _parseInt(paymentCtrl.text),
                            billingFrequency: billingFrequency,
                            leaseSignedDate: signedDate?.millisecondsSinceEpoch,
                            noticeDate: noticeDate?.millisecondsSinceEpoch,
                            renewalOptionDate: existing.renewalOptionDate,
                            breakOptionDate: existing.breakOptionDate,
                            executedDate: existing.executedDate,
                            depositStatus: depositStatus,
                            rentFreePeriodMonths: existing.rentFreePeriodMonths,
                            ancillaryChargesMonthly: existing.ancillaryChargesMonthly,
                            parkingOtherChargesMonthly: existing.parkingOtherChargesMonthly,
                            notes: _nullIfEmpty(notesCtrl.text),
                            createdAt: existing.createdAt,
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                    ref.read(selectedOperationsLeaseIdProvider.notifier).state = existing.id;
                  }

                  if (status == 'active') {
                    final unitRecord = _units.where((u) => u.id == unitId).firstOrNull;
                    if (unitRecord != null && unitRecord.status != 'occupied') {
                      await ref.read(rentRollRepositoryProvider).updateUnit(
                        UnitRecord(
                          id: unitRecord.id,
                          assetPropertyId: unitRecord.assetPropertyId,
                          unitCode: unitRecord.unitCode,
                          unitType: unitRecord.unitType,
                          beds: unitRecord.beds,
                          baths: unitRecord.baths,
                          sqft: unitRecord.sqft,
                          floor: unitRecord.floor,
                          status: 'occupied',
                          targetRentMonthly: unitRecord.targetRentMonthly,
                          marketRentMonthly: unitRecord.marketRentMonthly,
                          offlineReason: null,
                          vacancySince: null,
                          vacancyReason: null,
                          marketingStatus: null,
                          renovationStatus: null,
                          expectedReadyDate: null,
                          nextAction: null,
                          notes: unitRecord.notes,
                          createdAt: unitRecord.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                        ),
                      );
                    }
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
              child: Text(existing == null ? 'Anlegen' : 'Speichern'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    rentCtrl.dispose();
    depositCtrl.dispose();
    paymentCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _addRuleDialog() async {
    final leaseId = ref.read(selectedOperationsLeaseIdProvider);
    if (leaseId == null) {
      return;
    }
    String kind = 'cpi';
    String effectiveFrom = _fromPeriod;
    final annualCtrl = TextEditingController(text: '0.02');
    final stepCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Indexregel anlegen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: kind,
                  items: const [
                    DropdownMenuItem(value: 'cpi', child: Text('Index')),
                    DropdownMenuItem(value: 'fixed_step', child: Text('Fester Schritt')),
                    DropdownMenuItem(value: 'manual', child: Text('Manuell')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => kind = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _MonthField(
                  label: 'Gueltig ab',
                  value: effectiveFrom,
                  onChanged: (value) => setDialogState(() => effectiveFrom = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: annualCtrl,
                  decoration: const InputDecoration(labelText: 'Jaehrlicher Prozentsatz'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stepCtrl,
                  decoration: const InputDecoration(labelText: 'Fester Betrag'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                await ref.read(leaseRepositoryProvider).upsertIndexationRule(
                      leaseId: leaseId,
                      kind: kind,
                      effectiveFromPeriodKey: effectiveFrom,
                      annualPercent: _parseDouble(annualCtrl.text),
                      fixedStepAmount: _parseDouble(stepCtrl.text),
                    );
                await ref.read(leaseRepositoryProvider).rebuildRentSchedule(
                      leaseId: leaseId,
                      fromPeriod: _fromPeriod,
                      toPeriod: _toPeriod,
                    );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _reload();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    annualCtrl.dispose();
    stepCtrl.dispose();
  }

  Future<void> _manualOverrideDialog() async {
    final leaseId = ref.read(selectedOperationsLeaseIdProvider);
    if (leaseId == null) {
      return;
    }
    String period = _fromPeriod;
    final rentCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manuelle Anpassung'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MonthField(
                  label: 'Periode',
                  value: period,
                  onChanged: (value) => setDialogState(() => period = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rentCtrl,
                  decoration: const InputDecoration(labelText: 'Monatsmiete'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                final rent = _parseDouble(rentCtrl.text);
                if (rent == null) {
                  return;
                }
                await ref.read(leaseRepositoryProvider).upsertManualOverride(
                      leaseId: leaseId,
                      periodKey: period,
                      rentMonthly: rent,
                    );
                await ref.read(leaseRepositoryProvider).rebuildRentSchedule(
                      leaseId: leaseId,
                      fromPeriod: _fromPeriod,
                      toPeriod: _toPeriod,
                    );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _reload();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    rentCtrl.dispose();
  }

  Future<void> _generateSchedule() async {
    final leaseId = ref.read(selectedOperationsLeaseIdProvider);
    if (leaseId == null) {
      return;
    }
    await ref.read(leaseRepositoryProvider).rebuildRentSchedule(
          leaseId: leaseId,
          fromPeriod: _fromPeriod,
          toPeriod: _toPeriod,
        );
    await _reload();
  }

  Future<void> _deleteLease(String leaseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Mietvertrag loeschen'),
            content: const Text('Diesen Mietvertrag wirklich loeschen?'),
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
    await ref.read(leaseRepositoryProvider).deleteLease(leaseId);
    if (ref.read(selectedOperationsLeaseIdProvider) == leaseId) {
      ref.read(selectedOperationsLeaseIdProvider.notifier).state = null;
    }
    await _reload();
  }

  bool _hasMissingDeposit(LeaseRecord lease) {
    return lease.status == 'active' && (lease.securityDeposit == null || lease.securityDeposit == 0);
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

  String _unitName(String unitId) {
    for (final unit in _units) {
      if (unit.id == unitId) {
        return unit.unitCode;
      }
    }
    return unitId;
  }

  String _tenantName(String? tenantId) {
    if (tenantId == null) {
      return 'Kein Mieter';
    }
    for (final tenant in _tenants) {
      if (tenant.id == tenantId) {
        return tenant.displayName;
      }
    }
    return tenantId;
  }

  double? _parseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
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
            TextButton(onPressed: () => onPick(null), child: const Text('Leeren')),
        ],
      ),
    );
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
              child: const Text('Auswaehlen'),
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
