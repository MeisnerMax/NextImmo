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
      return const Center(child: Text('Select a tenant.'));
    }

    final contactOk =
        (bundle.tenant.email?.trim().isNotEmpty ?? false) &&
        (bundle.tenant.phone?.trim().isNotEmpty ?? false);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: widget.onEdit,
              child: const Text('Edit Tenant'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                await showCreateTaskDialog(
                  context: context,
                  ref: ref,
                  entityType: 'tenant',
                  entityId: bundle.tenant.id,
                  defaultTitle: 'Contact tenant ${bundle.tenant.displayName}',
                );
                await _load();
              },
              child: const Text('Create Task'),
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
                title: 'Master Data',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Display name: ${bundle.tenant.displayName}'),
                    Text('Legal name: ${bundle.tenant.legalName ?? '-'}'),
                    Text('Status: ${bundle.tenant.status ?? 'active'}'),
                    Text('Move-in reference: ${bundle.tenant.moveInReference ?? '-'}'),
                    Text('Alternative contact: ${bundle.tenant.alternativeContact ?? '-'}'),
                    Text('Billing contact: ${bundle.tenant.billingContact ?? '-'}'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Contact Quality',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email: ${bundle.tenant.email ?? '-'}'),
                    Text('Phone: ${bundle.tenant.phone ?? '-'}'),
                    Text(contactOk ? 'Contact quality: complete' : 'Contact quality: missing fields'),
                    if ((bundle.tenant.legalName?.trim().isEmpty ?? true))
                      const Text('Recommendation: add legal name for formal correspondence.'),
                    if (bundle.duplicateWarnings.isNotEmpty) ...bundle.duplicateWarnings.map(Text.new),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: OperationsSectionCard(
                title: 'Alerts',
                child: bundle.alerts.isEmpty
                    ? const Text('No open alerts for this tenant.')
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
          title: 'Leases',
          child: bundle.historicalLeases.isEmpty
              ? const Text('No leases for this tenant.')
              : Column(
                  children: bundle.historicalLeases
                      .map(
                        (lease) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(lease.leaseName),
                          subtitle: Text(
                            '${lease.status} · ${formatDateMillis(lease.startDate)} to ${formatDateMillis(lease.endDate)}',
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              ref.read(selectedOperationsLeaseIdProvider.notifier).state = lease.id;
                              ref.read(propertyDetailPageProvider.notifier).state =
                                  PropertyDetailPage.leases;
                            },
                            child: const Text('Open'),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: AppSpacing.component),
        OperationsSectionCard(
          title: 'Related Units',
          child: bundle.relatedUnits.isEmpty
              ? const Text('No units linked yet.')
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
                title: 'Tasks',
                child: OperationsTasksPanel(
                  tasks: bundle.tasks,
                  emptyHint: 'No tenant tasks yet.',
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: OperationsSectionCard(
                title: 'Documents',
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
                  child: const Text('Add Hook'),
                ),
                child: OperationsDocumentsPanel(
                  documents: bundle.documents,
                  emptyHint:
                      'No tenant documents linked yet. Hooks are ready for onboarding files, IDs and correspondence.',
                ),
              ),
            ),
          ],
        ),
      ],
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
        _error = 'Failed to load tenant detail: $error';
        _loading = false;
      });
    }
  }
}
