/// The operations overview of a property (Welle 3, AP9 — SCR-022).
///
/// Fully on cloud contracts (Befund 3 in `04c_wave3_leasing_operations.md`):
/// no legacy fallback, no "not yet available" tile. Alerts and data-quality
/// issues are **one list** here, because `P2-D05a` (AP8) already computes
/// them as one — see `operations_overview_controller.dart`'s header for why
/// this collapses what the legacy bundle kept as two separate figures.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/leasing_operations/application/operations_overview_controller.dart';
import '../../../../features/leasing_operations/domain/operations_signal_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_page_header.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import 'widgets/lease_lifecycle.dart';

class OperationsOverviewPanel extends ConsumerWidget {
  const OperationsOverviewPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = operationsOverviewControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxPageHeader(
          title: 'Betriebsübersicht',
          subtitle: state.summary == null
              ? 'Belegung, Verträge und operative Hinweise dieses Objekts.'
              : 'Stand ${formatLeaseDate(state.summary!.rentRoll.asOfDate)}, '
                    'berechnet ${_formatTime(state.summary!.rentRoll.computedAt)} Uhr.',
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, ref, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    OperationsOverviewState state,
    OperationsOverviewController controller,
  ) {
    switch (state.phase) {
      case OperationsOverviewPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Die Betriebsübersicht wird je Arbeitsbereich geführt. Melde '
              'dich an oder wähle einen Arbeitsbereich.',
          icon: Icons.workspaces_outline,
        );
      case OperationsOverviewPhase.loading:
        return const _OverviewSkeleton();
      case OperationsOverviewPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf die Betriebsübersicht',
          description:
              'Für dieses Objekt fehlt die Leseberechtigung für Einheiten '
              'und Verträge (lease.read).',
          icon: Icons.lock_outline,
        );
      case OperationsOverviewPhase.error:
        return NxEmptyState(
          title: 'Betriebsübersicht konnte nicht geladen werden',
          description:
              state.message ?? 'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case OperationsOverviewPhase.ready:
        final summary = state.summary;
        if (summary == null) {
          return const NxEmptyState(
            title: 'Keine Daten verfügbar',
            description: 'Für dieses Objekt liegen noch keine Betriebsdaten vor.',
            icon: Icons.info_outline,
          );
        }
        return _buildReady(context, ref, summary);
    }
  }

  Widget _buildReady(
    BuildContext context,
    WidgetRef ref,
    OperationsOverviewSummary summary,
  ) {
    return ListView(
      children: <Widget>[
        if (summary.truncated) ...<Widget>[
          const _TruncationNotice(),
          const SizedBox(height: AppSpacing.component),
        ],
        _KpiCard(summary: summary),
        const SizedBox(height: AppSpacing.component),
        _LettingWorkflowCard(onNavigate: (page) => _navigate(ref, page)),
        const SizedBox(height: AppSpacing.component),
        _QuickActionsCard(onNavigate: (page) => _navigate(ref, page)),
        const SizedBox(height: AppSpacing.component),
        _ExpiryCard(summary: summary),
        const SizedBox(height: AppSpacing.component),
        _AlertsCard(
          summary: summary,
          onOpenAlerts: () => _navigate(ref, PropertyDetailPage.alerts),
        ),
      ],
    );
  }

  void _navigate(WidgetRef ref, PropertyDetailPage page) {
    ref.read(propertyDetailPageProvider.notifier).state = page;
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.summary});

  final OperationsOverviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final rentRoll = summary.rentRoll;
    return NxCard(
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: <Widget>[
          _Kpi(label: 'Einheiten', value: '${rentRoll.unitCount}'),
          _Kpi(label: 'Vermietet', value: '${rentRoll.occupiedUnitCount}'),
          _Kpi(label: 'Leerstand', value: '${rentRoll.vacantUnitCount}'),
          _Kpi(label: 'Offline', value: '${rentRoll.offlineUnitCount}'),
          _Kpi(label: 'Belegungsquote', value: _rate(rentRoll.occupancyRate)),
          _Kpi(
            label: 'Aktive Verträge',
            value: '${rentRoll.effectiveLeaseCount}',
          ),
          _Kpi(
            label: 'Vermietete Fläche',
            value: '${summary.leasedAreaSqm.toStringAsFixed(1)} m²',
          ),
          _Kpi(
            label: 'Grundmiete / Monat',
            value: rentRoll.hasMixedCurrencies
                ? rentRoll.currencies.join(' + ')
                : formatLeaseMoney(
                    rentRoll.totalBaseRentMonthly,
                    rentRoll.currencyCode,
                  ),
          ),
          _Kpi(
            label: 'Offene Hinweise',
            value: '${summary.openAlertCount}',
          ),
        ],
      ),
    );
  }
}

class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({required this.summary});

  final OperationsOverviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Vertragsablauf', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Jede Zahl zählt kumulativ — läuft ein Vertrag in 20 Tagen aus, '
            'zählt er in allen vier Fenstern.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: <Widget>[
              _Kpi(label: '30 Tage', value: '${summary.expiringIn30Days}'),
              _Kpi(label: '60 Tage', value: '${summary.expiringIn60Days}'),
              _Kpi(label: '90 Tage', value: '${summary.expiringIn90Days}'),
              _Kpi(label: '180 Tage', value: '${summary.expiringIn180Days}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.summary, required this.onOpenAlerts});

  final OperationsOverviewSummary summary;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final alerts = summary.alerts.take(8).toList(growable: false);
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Operative Hinweise',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: onOpenAlerts, child: const Text('Alle ansehen')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.criticalAlertCount} kritisch, '
            '${summary.warningAlertCount} Warnung, '
            '${summary.alerts.length} insgesamt.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (alerts.isEmpty)
            const Text('Keine offenen Hinweise.')
          else
            ...alerts.map((alert) => _AlertTile(alert: alert)),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final OperationsSignalDto alert;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final color = switch (alert.severity) {
      'critical' => semantic.error,
      'warning' => semantic.warning,
      _ => semantic.textSecondary,
    };
    final icon = switch (alert.severity) {
      'critical' => Icons.error_outline,
      'warning' => Icons.warning_amber_outlined,
      _ => Icons.info_outline,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(alert.message),
      subtitle: Text('${alert.type.replaceAll('_', ' ')} · ${alert.status}'),
    );
  }
}

class _LettingWorkflowCard extends StatelessWidget {
  const _LettingWorkflowCard({required this.onNavigate});

  final void Function(PropertyDetailPage) onNavigate;

  @override
  Widget build(BuildContext context) {
    final steps = <_LettingWorkflowStep>[
      _LettingWorkflowStep('1', 'Einheit', 'Fläche und Status',
          Icons.apartment_outlined, PropertyDetailPage.units),
      _LettingWorkflowStep('2', 'Interessent', 'Vertriebsfall (Einheiten-Tab)',
          Icons.person_add_alt_outlined, PropertyDetailPage.units),
      _LettingWorkflowStep('3', 'Dokumente', 'Nachweise und Vertrag',
          Icons.folder_open_outlined, PropertyDetailPage.documents),
      _LettingWorkflowStep('4', 'Vertrag', 'Konditionen',
          Icons.description_outlined, PropertyDetailPage.leases),
      _LettingWorkflowStep('5', 'Mieter', 'Rollen und Kontakt',
          Icons.badge_outlined, PropertyDetailPage.tenants),
      _LettingWorkflowStep('6', 'Laufende Miete', 'Rent Roll',
          Icons.payments_outlined, PropertyDetailPage.rentRoll),
    ];

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Vermietungsworkflow', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: steps.map((step) {
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                onTap: () => onNavigate(step.targetPage),
                child: Container(
                  width: context.viewport == AppViewport.mobile
                      ? double.infinity
                      : 220,
                  padding: const EdgeInsets.all(AppSpacing.component),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
                    border: Border.all(color: context.semanticColors.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(radius: 15, child: Text(step.number)),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(step.icon, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              step.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              step.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.onNavigate});

  final void Function(PropertyDetailPage) onNavigate;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Schnellaktionen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _actionButton('Einheit anlegen', PropertyDetailPage.units, onNavigate),
              _actionButton('Mieter verwalten', PropertyDetailPage.tenants, onNavigate),
              _actionButton('Vertrag anlegen', PropertyDetailPage.leases, onNavigate),
              _actionButton(
                'Rent Roll ansehen',
                PropertyDetailPage.rentRoll,
                onNavigate,
              ),
              _actionButton('Hinweise prüfen', PropertyDetailPage.alerts, onNavigate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    PropertyDetailPage page,
    void Function(PropertyDetailPage) onNavigate,
  ) {
    return FilledButton.tonal(
      onPressed: () => onNavigate(page),
      child: Text(label),
    );
  }
}

class _LettingWorkflowStep {
  const _LettingWorkflowStep(
    this.number,
    this.title,
    this.detail,
    this.icon,
    this.targetPage,
  );

  final String number;
  final String title;
  final String detail;
  final IconData icon;
  final PropertyDetailPage targetPage;
}

String _rate(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

/// A bounded read that says it was bounded.
class _TruncationNotice extends StatelessWidget {
  const _TruncationNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: semantic.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: semantic.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Nur ein Teil des Objekts', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'Der Bestand überschreitet, was diese Sicht in einem Zug '
                  'liest. Die Zahlen oben beschreiben deshalb nur die '
                  'gelesenen Einheiten und Verträge.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 5; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}
