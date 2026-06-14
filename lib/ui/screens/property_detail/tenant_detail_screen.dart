import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'operations_detail_support.dart';

class TenantDetailScreen extends ConsumerStatefulWidget {
  const TenantDetailScreen({
    super.key,
    required this.propertyId,
    required this.tenantId,
    this.onEdit,
    this.onChanged,
  });

  final String propertyId;
  final String tenantId;
  final VoidCallback? onEdit;
  final VoidCallback? onChanged;

  @override
  ConsumerState<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends ConsumerState<TenantDetailScreen> {
  TenantDetailBundle? _bundle;
  bool _loading = true;
  String? _error;
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId || oldWidget.propertyId != widget.propertyId) {
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
      return const Center(child: Text('Mieter auswaehlen.'));
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
              child: const Text('Mieter bearbeiten'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'tenant',
                  entityId: bundle.tenant.id,
                  defaultTitle: 'Mieter ${bundle.tenant.displayName} kontaktieren',
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
        // Tab Selection Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton(0, 'Mieterdaten & Kontakt'),
              _buildTabButton(1, 'Verträge & Einheiten'),
              _buildTabButton(2, 'Aufgaben & Dokumente'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _buildActiveTabContent(bundle),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(TenantDetailBundle bundle) {
    final contactOk =
        (bundle.tenant.email?.trim().isNotEmpty ?? false) &&
        (bundle.tenant.phone?.trim().isNotEmpty ?? false);

    switch (_activeTab) {
      case 0:
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 360),
              child: OperationsSectionCard(
                title: 'Stammdaten',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anzeigename: ${bundle.tenant.displayName}'),
                    Text('Rechtlicher Name: ${bundle.tenant.legalName ?? '-'}'),
                    Text('Status: ${_tenantStatusLabel(bundle.tenant.status ?? 'active')}'),
                    Text('Einzugsreferenz: ${bundle.tenant.moveInReference ?? '-'}'),
                    Text('Alternativer Kontakt: ${bundle.tenant.alternativeContact ?? '-'}'),
                    Text('Abrechnungskontakt: ${bundle.tenant.billingContact ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: ResponsiveConstraints.itemWidth(context, idealWidth: 360),
              child: OperationsSectionCard(
                title: 'Kontaktqualitaet',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('E-Mail: ${bundle.tenant.email ?? '-'}'),
                    Text('Telefon: ${bundle.tenant.phone ?? '-'}'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: contactOk ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: contactOk ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            contactOk ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                            color: contactOk ? Colors.green : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              contactOk ? 'Kontaktdaten vollständig' : 'Kontaktdaten unvollständig',
                              style: TextStyle(
                                color: contactOk ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((bundle.tenant.legalName?.trim().isEmpty ?? true)) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Empfehlung: Rechtlichen Namen fuer formelle Schreiben ergaenzen.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (bundle.duplicateWarnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...bundle.duplicateWarnings.map(
                        (w) => Text(
                          w,
                          style: const TextStyle(fontSize: 11, color: Colors.red),
                        ),
                      ),
                    ],
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
            OperationsSectionCard(
              title: 'Verknuepfte Einheiten',
              child: bundle.relatedUnits.isEmpty
                  ? const Text('Noch keine Einheiten verknuepft.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: bundle.relatedUnits
                          .map(
                            (unit) => ActionChip(
                              label: Text(unit.unitCode),
                              onPressed: () {
                                ref.read(selectedOperationsUnitIdProvider.notifier).state = unit.id;
                                ref.read(propertyDetailPageProvider.notifier).state =
                                    PropertyDetailPage.units;
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
            const SizedBox(height: AppSpacing.component),
            OperationsSectionCard(
              title: 'Mietvertraege',
              child: bundle.historicalLeases.isEmpty
                  ? const Text('Keine Mietvertraege fuer diesen Mieter.')
                  : Column(
                      children: bundle.historicalLeases
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bundle.alerts.isNotEmpty) ...[
              OperationsSectionCard(
                title: 'Hinweise',
                child: Column(
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
              const SizedBox(height: AppSpacing.component),
            ],
            Wrap(
              spacing: AppSpacing.component,
              runSpacing: AppSpacing.component,
              children: [
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(context, idealWidth: 420),
                  child: OperationsSectionCard(
                    title: 'Aufgaben',
                    child: OperationsTasksPanel(
                      tasks: bundle.tasks,
                      emptyHint: 'Noch keine Aufgaben fuer diesen Mieter.',
                    ),
                  ),
                ),
                SizedBox(
                  width: ResponsiveConstraints.itemWidth(context, idealWidth: 420),
                  child: OperationsSectionCard(
                    title: 'Dokumente',
                    action: TextButton(
                      onPressed: () async {
                        await showCreateDocumentHookDialog(
                          context: context,
                          ref: ref,
                          entityType: 'tenant',
                          entityId: bundle.tenant.id,
                        );
                        await _load();
                      },
                      child: const Text('Verknuepfung anlegen'),
                    ),
                    child: OperationsDocumentsPanel(
                      documents: bundle.documents,
                      emptyHint: 'Noch keine Mieterdokumente verknuepft.',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
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
      final bundle = await ref.read(operationsRepositoryProvider).loadTenantDetail(
            propertyId: widget.propertyId,
            tenantId: widget.tenantId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Mieterdetails konnten nicht geladen werden: $error';
        _loading = false;
      });
    }
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
}
