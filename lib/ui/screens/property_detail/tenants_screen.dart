import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../../core/models/property.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_status_badge.dart';
import '../../components/responsive_constraints.dart';
import '../../templates/list_filter_template.dart';
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

    // Page structure, per the layout audit. The whole screen used to sit in
    // one SingleChildScrollView, so a long tenant list scrolled the KPI band
    // and the filters off the top. Header context and filters are now fixed
    // and only the panes scroll.
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Screen-level actions live here, above the KPI band — not inside
          // the filter strip. Creating a tenant is not a way of filtering the
          // list, and mixing the two made the primary action compete with the
          // search field for attention.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mieterübersicht',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Aktualisieren'),
              ),
              const SizedBox(width: AppSpacing.xs),
              ElevatedButton.icon(
                onPressed: _createTenantDialog,
                icon: const Icon(Icons.add),
                label: const Text('Mieter anlegen'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          NxKpiRow(
            children: [
              NxKpiTile(
                label: 'AKTIVE MIETER',
                value: '$activeCount',
                caption: 'von ${_tenants.length} erfasst',
                status: context.semanticColors.success,
              ),
              NxKpiTile(
                label: 'INTERESSENTEN',
                value: '$prospectCount',
                caption: 'in Anbahnung',
              ),
              NxKpiTile(
                label: 'PROFIL UNVOLLSTÄNDIG',
                value: '$incompleteCount',
                caption: 'E-Mail oder Telefon fehlt',
                status: incompleteCount > 0
                    ? context.semanticColors.warning
                    : context.semanticColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          ListFilterBar(
            trailing: Text(
              filteredTenants.length == _tenants.length
                  ? '${_tenants.length} Mieter'
                  : '${filteredTenants.length} von ${_tenants.length} Mietern',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            children: [
              SizedBox(
                width: 240,
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
                  // Without this the longest item ("Kontakt fehlt") forces its
                  // intrinsic width and overflows the fixed box.
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Alle Mieter')),
                    DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                    DropdownMenuItem(
                      value: 'missing_contact',
                      child: Text('Kontakt fehlt'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _filter = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Filter'),
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _status!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.semanticColors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1100;
                final listPane = _tenantListCard(
                  context: context,
                  tenants: filteredTenants,
                  selectedTenantId: selectedTenantId,
                );
                final detailPane = _tenantDetailCard(selectedTenant);
                if (stacked) {
                  // Below the split threshold the panes stack and the page as
                  // a whole scrolls — two independently scrolling regions in
                  // one narrow column is worse than one.
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        listPane,
                        const SizedBox(height: AppSpacing.component),
                        detailPane,
                      ],
                    ),
                  );
                }
                // Proportional split rather than a fixed 420px list column,
                // so the extra width of a wide monitor reaches both panes.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: listPane),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(flex: 6, child: detailPane),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// High-density tenant row.
  ///
  /// Rebuilt against the layout audit. Previously: selection was signalled
  /// three times at once (fill + 1.5px border + drop shadow) using two
  /// hardcoded hex colors behind a `Brightness` check, while the 5px left bar
  /// carried *status* — so the one affordance the design reserves for
  /// selection was already taken. Now selection owns the left bracket, status
  /// owns the badge, and rows separate by background alternate.
  Widget _buildTenantListItem(
    BuildContext context,
    TenantRecord tenant,
    bool isSelected, {
    required bool alternate,
  }) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final primary = theme.colorScheme.primary;

    final bool hasContact = (tenant.email?.trim().isNotEmpty ?? false) &&
        (tenant.phone?.trim().isNotEmpty ?? false);

    return Material(
      color: isSelected
          ? primary.withValues(alpha: 0.08)
          : alternate
              ? semantic.surfaceAlt.withValues(alpha: 0.35)
              : Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(selectedOperationsTenantIdProvider.notifier).state =
              tenant.id;
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              // Reserved even when unselected so the row never shifts.
              left: BorderSide(
                color: isSelected ? primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    (tenant.status ?? 'active') == 'prospect'
                        ? Icons.person_search_outlined
                        : Icons.person_outline,
                    size: AppIconTokens.sm,
                    color: semantic.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      tenant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? primary : null,
                      ),
                    ),
                  ),
                  _buildTenantStatusTag(context, tenant.status ?? 'active'),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tenant.email != null && tenant.email!.isNotEmpty)
                          Text(
                            tenant.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                        if (tenant.phone != null &&
                            tenant.phone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tenant.phone!,
                            style: theme.textTheme.bodySmall
                                ?.merge(context.dataMonoStyle)
                                .copyWith(color: semantic.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!hasContact)
                    Tooltip(
                      message: 'Kontaktdaten unvollständig',
                      child: Icon(
                        Icons.warning_amber_outlined,
                        color: semantic.warning,
                        size: AppIconTokens.md,
                      ),
                    ),
                  // Folded into the contact line instead of occupying a third
                  // row of its own — at 30px per tenant that line was the
                  // largest single cost to list density.
                  const SizedBox(width: AppSpacing.xs),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _tenantDialog(existing: tenant),
                    child: const Text('Bearbeiten'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tenant workflow status.
  ///
  /// Was a third hand-rolled status chip (4px radius, 10px bold text, custom
  /// border) alongside `NxStatusBadge` and the parties badges. Same rule as
  /// the breadcrumbs fork: one component, extended once, not re-implemented
  /// per screen — otherwise the shape and colour mapping drift the moment the
  /// design system moves.
  Widget _buildTenantStatusTag(BuildContext context, String status) {
    return switch (status) {
      'active' => const NxStatusBadge(
        label: 'Aktiv',
        kind: NxBadgeKind.success,
      ),
      'inactive' => const NxStatusBadge(
        label: 'Inaktiv',
        kind: NxBadgeKind.error,
      ),
      'prospect' => const NxStatusBadge(
        label: 'Interessent',
        kind: NxBadgeKind.info,
      ),
      _ => NxStatusBadge(label: status, kind: NxBadgeKind.neutral),
    };
  }

  Widget _tenantListCard({
    required BuildContext context,
    required List<TenantRecord> tenants,
    required String? selectedTenantId,
  }) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'Mieter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // The list scrolls, not the page — so the KPI band and filters stay
          // put while a long tenant roll is browsed.
          Expanded(
            child: tenants.isEmpty
                ? const NxEmptyState(
                    title: 'Keine Mieter zugeordnet',
                    description:
                        'Für dieses Objekt sind noch keine Mieter erfasst. '
                        'Legen Sie den ersten Mieter an.',
                    icon: Icons.people_outline,
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: tenants.length,
                    itemBuilder: (context, index) {
                      final tenant = tenants[index];
                      return _buildTenantListItem(
                        context,
                        tenant,
                        tenant.id == selectedTenantId,
                        alternate: index.isOdd,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tenantDetailCard(TenantRecord? selectedTenant) {
    if (selectedTenant == null) {
      return const NxCard(
        child: NxEmptyState(
          title: 'Kein Mieter ausgewählt',
          description:
              'Wählen Sie links einen Mieter, um Stammdaten, Verträge und '
              'Kontakthistorie zu sehen.',
          icon: Icons.person_search_outlined,
        ),
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
