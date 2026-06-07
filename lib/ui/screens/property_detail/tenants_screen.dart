import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../components/nx_card.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'tenant_detail_screen.dart';

class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  List<TenantRecord> _tenants = const [];
  String? _status;
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTenantId = ref.watch(selectedOperationsTenantIdProvider);
    final filteredTenants = _tenants.where((tenant) {
      final needle = _query.trim().toLowerCase();
      final matchesQuery =
          needle.isEmpty ||
          tenant.displayName.toLowerCase().contains(needle) ||
          (tenant.legalName?.toLowerCase().contains(needle) ?? false) ||
          (tenant.email?.toLowerCase().contains(needle) ?? false);
      final hasContact =
          (tenant.email?.trim().isNotEmpty ?? false) &&
          (tenant.phone?.trim().isNotEmpty ?? false);
      final matchesFilter =
          _filter == 'all' ||
          (_filter == 'active' && (tenant.status ?? 'active') == 'active') ||
          (_filter == 'inactive' && (tenant.status ?? 'active') != 'active') ||
          (_filter == 'missing_contact' && !hasContact);
      return matchesQuery && matchesFilter;
    }).toList(growable: false);

    TenantRecord? selectedTenant;
    for (final tenant in filteredTenants) {
      if (tenant.id == selectedTenantId) {
        selectedTenant = tenant;
        break;
      }
    }

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
                onPressed: _createTenantDialog,
                icon: const Icon(Icons.add),
                label: const Text('Mieter anlegen'),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Mieter suchen',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _filter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle Mieter')),
                    DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                    DropdownMenuItem(value: 'missing_contact', child: Text('Kontakt fehlt')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _filter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Filter'),
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
              final listPane = _tenantListCard(
                context: context,
                tenants: filteredTenants,
                selectedTenantId: selectedTenantId,
              );
              final detailPane = _tenantDetailCard(selectedTenant);
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

  Widget _tenantListCard({
    required BuildContext context,
    required List<TenantRecord> tenants,
    required String? selectedTenantId,
  }) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mieter', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (tenants.isEmpty)
            const Text('Keine Mieter fuer diese Filter.')
          else
            Column(
              children: [
                for (final tenant in tenants)
                  ListTile(
                    selected: tenant.id == selectedTenantId,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tenant.displayName),
                    subtitle: Text(
                      '${_tenantStatusLabel(tenant.status ?? 'active')}${tenant.email == null ? '' : ' · ${tenant.email}'}${tenant.phone == null ? '' : ' · ${tenant.phone}'}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (!_hasContact(tenant))
                          const Tooltip(
                            message: 'Kontaktdaten fehlen',
                            child: Icon(
                              Icons.warning_amber_outlined,
                              color: Colors.orange,
                            ),
                          ),
                        TextButton(
                          onPressed: () => _tenantDialog(existing: tenant),
                          child: const Text('Bearbeiten'),
                        ),
                      ],
                    ),
                    onTap:
                        () =>
                            ref
                                .read(
                                  selectedOperationsTenantIdProvider.notifier,
                                )
                                .state = tenant.id,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tenantDetailCard(TenantRecord? selectedTenant) {
    if (selectedTenant == null) {
      return const NxCard(
        child: Text('Mieter auswaehlen, um Details zu oeffnen.'),
      );
    }
    return NxCard(
      padding: EdgeInsets.zero,
      child: TenantDetailScreen(
        propertyId: widget.propertyId,
        tenantId: selectedTenant.id,
        onEdit: () => _tenantDialog(existing: selectedTenant),
        onChanged: _reload,
      ),
    );
  }

  Future<void> _reload() async {
    final tenants = await ref.read(leaseRepositoryProvider).listTenants();
    if (!mounted) {
      return;
    }
    final selectedId = ref.read(selectedOperationsTenantIdProvider);
    setState(() {
      _tenants = tenants;
      _status = null;
    });
    if (tenants.isNotEmpty && !tenants.any((tenant) => tenant.id == selectedId)) {
      ref.read(selectedOperationsTenantIdProvider.notifier).state = tenants.first.id;
    }
  }

  Future<void> _createTenantDialog() => _tenantDialog();

  bool _hasContact(TenantRecord tenant) {
    return (tenant.email?.trim().isNotEmpty ?? false) &&
        (tenant.phone?.trim().isNotEmpty ?? false);
  }

  Future<void> _tenantDialog({TenantRecord? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    final legalNameCtrl = TextEditingController(text: existing?.legalName ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final altContactCtrl = TextEditingController(text: existing?.alternativeContact ?? '');
    final billingCtrl = TextEditingController(text: existing?.billingContact ?? '');
    final moveInReferenceCtrl = TextEditingController(text: existing?.moveInReference ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String status = existing?.status ?? 'active';
    const allowedStatuses = <String>['active', 'inactive', 'prospect'];
    final statusItems = <DropdownMenuItem<String>>[
      if (!allowedStatuses.contains(status))
        DropdownMenuItem(value: status, child: Text(_tenantStatusLabel(status))),
      const DropdownMenuItem(value: 'active', child: Text('Aktiv')),
      const DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
      const DropdownMenuItem(value: 'prospect', child: Text('Interessent')),
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Mieter anlegen' : 'Mieter bearbeiten'),
          content: SizedBox(
            width: 520,
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
                    controller: legalNameCtrl,
                    decoration: const InputDecoration(labelText: 'Rechtlicher Name'),
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
                  TextField(
                    controller: altContactCtrl,
                    decoration: const InputDecoration(labelText: 'Alternativer Kontakt'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: billingCtrl,
                    decoration: const InputDecoration(labelText: 'Abrechnungskontakt'),
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
                  TextField(
                    controller: moveInReferenceCtrl,
                    decoration: const InputDecoration(labelText: 'Einzugsreferenz'),
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
                  final tenant = await ref.read(leaseRepositoryProvider).upsertTenant(
                        id: existing?.id,
                        displayName: displayName,
                        legalName: _nullIfEmpty(legalNameCtrl.text),
                        email: _nullIfEmpty(emailCtrl.text),
                        phone: _nullIfEmpty(phoneCtrl.text),
                        alternativeContact: _nullIfEmpty(altContactCtrl.text),
                        billingContact: _nullIfEmpty(billingCtrl.text),
                        status: status,
                        moveInReference: _nullIfEmpty(moveInReferenceCtrl.text),
                        notes: _nullIfEmpty(notesCtrl.text),
                      );
                  ref.read(selectedOperationsTenantIdProvider.notifier).state = tenant.id;
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
    legalNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    altContactCtrl.dispose();
    billingCtrl.dispose();
    moveInReferenceCtrl.dispose();
    notesCtrl.dispose();
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _tenantStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Aktiv';
      case 'inactive':
        return 'Inaktiv';
      case 'prospect':
        return 'Interessent';
      default:
        return status;
    }
  }
}
