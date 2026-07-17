import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../../core/models/property.dart';
import '../../components/nx_card.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
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
    final property = _currentProperty(
      ref.watch(propertiesControllerProvider).valueOrNull,
    );
    if (property != null &&
        !propertySupportsRentalOperations(property.propertyType)) {
      return _nonRentalState(context, property);
    }
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

    // KPI calculation
    final activeCount = _tenants.where((t) => (t.status ?? 'active') == 'active').length;
    final prospectCount = _tenants.where((t) => t.status == 'prospect').length;
    final incompleteCount = _tenants.where((t) =>
      (t.status ?? 'active') == 'active' &&
      ((t.email == null || t.email!.trim().isEmpty) ||
       (t.phone == null || t.phone!.trim().isEmpty))
    ).length;

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
                title: 'Aktive Mieter',
                value: '$activeCount',
                icon: Icons.people_outline,
                color: context.semanticColors.success,
              ),
              _KpiTile(
                title: 'Interessenten',
                value: '$prospectCount',
                icon: Icons.person_search_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              _KpiTile(
                title: 'Profil unvollständig',
                value: '$incompleteCount',
                subtitle: 'E-Mail oder Telefon fehlt',
                icon: Icons.assignment_late_outlined,
                color: incompleteCount > 0 ? context.semanticColors.warning : context.semanticColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _createTenantDialog,
                icon: const Icon(Icons.add),
                label: const Text('Mieter-Stammdaten anlegen'),
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

  Widget _buildTenantListItem(BuildContext context, TenantRecord tenant, bool isSelected) {
    final semantic = context.semanticColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusColor = switch (tenant.status ?? 'active') {
      'active' => semantic.success,
      'inactive' => semantic.error,
      'prospect' => Theme.of(context).colorScheme.primary,
      _ => semantic.border,
    };

    final bool hasContact = (tenant.email?.trim().isNotEmpty ?? false) &&
        (tenant.phone?.trim().isNotEmpty ?? false);

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
                    ref.read(selectedOperationsTenantIdProvider.notifier).state = tenant.id;
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              (tenant.status ?? 'active') == 'prospect'
                                  ? Icons.person_search_outlined
                                  : Icons.person_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tenant.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            _buildTenantStatusTag(context, tenant.status ?? 'active'),
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
                                  if (tenant.email != null && tenant.email!.isNotEmpty)
                                    Text(
                                      tenant.email!,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (tenant.phone != null && tenant.phone!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      tenant.phone!,
                                      style: context.tabularNumericStyle.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!hasContact)
                              const Tooltip(
                                message: 'Kontaktdaten unvollständig',
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
                              onPressed: () => _tenantDialog(existing: tenant),
                              child: const Text('Bearbeiten', style: TextStyle(fontSize: 11)),
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

  Widget _buildTenantStatusTag(BuildContext context, String status) {
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
      case 'inactive':
        bgColor = semantic.error.withValues(alpha: 0.12);
        textColor = semantic.error;
        label = 'Inaktiv';
        break;
      case 'prospect':
        bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
        textColor = Theme.of(context).colorScheme.primary;
        label = 'Interessent';
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
            const Text('Fuer dieses Objekt sind noch keine Mieter zugeordnet.')
          else
            Column(
              children: [
                for (final tenant in tenants)
                  _buildTenantListItem(context, tenant, tenant.id == selectedTenantId),
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
    final tenants = await ref
        .read(leaseRepositoryProvider)
        .getTenantsForProperty(widget.propertyId);
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

  PropertyRecord? _currentProperty(List<PropertyRecord>? properties) {
    if (properties == null) {
      return null;
    }
    for (final property in properties) {
      if (property.id == widget.propertyId) {
        return property;
      }
    }
    return null;
  }

  Widget _nonRentalState(BuildContext context, PropertyRecord property) {
    final message = switch (propertyKindFromType(property.propertyType)) {
      PropertyKind.sale =>
        'Dieses Objekt ist als Verkaufsobjekt angelegt. Mieterverwaltung ist hier deaktiviert.',
      PropertyKind.condoSale =>
        'Dieses Objekt ist als Eigentumswohnungs-Verkauf angelegt. Verwende Kaeufer, Interessenten und Reservierungen statt Mieter.',
      PropertyKind.hotel =>
        'Dieses Objekt ist als Hotel angelegt. Verwende Gaeste, Reservierungen und Zimmer statt Mieter.',
      PropertyKind.other =>
        'Fuer diese Objektart ist keine Mieterverwaltung aktiviert.',
      PropertyKind.rental || PropertyKind.mixed =>
        'Fuer dieses Objekt sind noch keine Mieter zugeordnet.',
    };
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: NxCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
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
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 520),
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
