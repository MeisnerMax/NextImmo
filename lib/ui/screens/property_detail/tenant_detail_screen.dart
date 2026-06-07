import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operations.dart';
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

    final contactOk =
        (bundle.tenant.email?.trim().isNotEmpty ?? false) &&
        (bundle.tenant.phone?.trim().isNotEmpty ?? false);

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
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: 360,
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
              width: 360,
              child: OperationsSectionCard(
                title: 'Kontaktqualitaet',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('E-Mail: ${bundle.tenant.email ?? '-'}'),
                    Text('Telefon: ${bundle.tenant.phone ?? '-'}'),
                    Text(contactOk ? 'Kontaktdaten: vollstaendig' : 'Kontaktdaten: unvollstaendig'),
                    if ((bundle.tenant.legalName?.trim().isEmpty ?? true))
                      const Text('Empfehlung: Rechtlichen Namen fuer formelle Schreiben ergaenzen.'),
                    if (bundle.duplicateWarnings.isNotEmpty) ...bundle.duplicateWarnings.map(Text.new),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Hinweise',
                child: bundle.alerts.isEmpty
                    ? const Text('Keine offenen Hinweise fuer diesen Mieter.')
                    : Column(
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
            ),
          ],
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
        const SizedBox(height: AppSpacing.component),
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
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Aufgaben',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'Noch keine Aufgaben fuer diesen Mieter.',
                ),
              ),
            ),
            SizedBox(
              width: 420,
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
                  emptyHint:
                      'Noch keine Mieterdokumente verknuepft.',
                ),
              ),
            ),
          ],
        ),
        ],
      ),
    );
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
