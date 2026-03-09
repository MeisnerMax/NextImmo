import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
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
                label: const Text('Add Tenant'),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Search Tenants',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _filter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Tenants')),
                    DropdownMenuItem(value: 'active', child: Text('active')),
                    DropdownMenuItem(value: 'inactive', child: Text('inactive')),
                    DropdownMenuItem(value: 'missing_contact', child: Text('missing contact')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _filter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Filter'),
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
                  child: filteredTenants.isEmpty
                      ? const Center(child: Text('No tenants match the current filters.'))
                      : ListView.builder(
                          itemCount: filteredTenants.length,
                          itemBuilder: (context, index) {
                            final tenant = filteredTenants[index];
                            final contactOk =
                                (tenant.email?.trim().isNotEmpty ?? false) &&
                                (tenant.phone?.trim().isNotEmpty ?? false);
                            return ListTile(
                              selected: tenant.id == selectedTenantId,
                              title: Text(tenant.displayName),
                              subtitle: Text(
                                '${tenant.status ?? 'active'}${tenant.email == null ? '' : ' · ${tenant.email}'}${tenant.phone == null ? '' : ' · ${tenant.phone}'}',
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  if (!contactOk)
                                    const Tooltip(
                                      message: 'Missing contact data',
                                      child: Icon(Icons.warning_amber_outlined, color: Colors.orange),
                                    ),
                                  TextButton(
                                    onPressed: () => _tenantDialog(existing: tenant),
                                    child: const Text('Edit'),
                                  ),
                                ],
                              ),
                              onTap: () {
                                ref.read(selectedOperationsTenantIdProvider.notifier).state = tenant.id;
                              },
                            );
                          },
                        ),
                );
                final detailPane = Card(
                  child: selectedTenant == null
                      ? const Center(child: Text('Select a tenant to open the detail view.'))
                      : TenantDetailScreen(
                          propertyId: widget.propertyId,
                          tenantId: selectedTenant.id,
                          onEdit: () => _tenantDialog(existing: selectedTenant),
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

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create Tenant' : 'Edit Tenant'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Display Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: legalNameCtrl,
                    decoration: const InputDecoration(labelText: 'Legal Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: altContactCtrl,
                    decoration: const InputDecoration(labelText: 'Alternative Contact'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: billingCtrl,
                    decoration: const InputDecoration(labelText: 'Billing Contact'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('active')),
                      DropdownMenuItem(value: 'inactive', child: Text('inactive')),
                      DropdownMenuItem(value: 'prospect', child: Text('prospect')),
                    ],
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
                    decoration: const InputDecoration(labelText: 'Move In Reference'),
                  ),
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
              child: Text(existing == null ? 'Create' : 'Save'),
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
}
