/// The workspace worklist (`ALERT-READER-01`, P-10).
///
/// This is the cloud Dashboard destination, which until now rendered
/// "Dashboard ist noch nicht cloudfähig" — a menu entry that led to a notice
/// about itself. It now answers the question a property manager actually opens
/// the app with: what needs attention today, across every building.
///
/// **Three things it refuses to do**, each because the alternative reads as a
/// fact that is not one:
///
///   * It does not count what it can see. Every number comes from the server's
///     own count over the matched set, taken before the cap. Counting the
///     rendered list would report "3 kritisch" when 40 were cut off.
///   * It does not filter what it holds. Both filters re-query, because
///     filtering a capped page searches only what fitted.
///   * It does not show an empty list when a read failed. A worklist with
///     nothing on it is good news, and it must never be how a refusal looks.
///
/// There is no scheduler anywhere in this product (finding B-4), so nothing
/// here is a push. The freshness stamp under the header is what says when the
/// deadlines were last judged, and it is the honest substitute for a promise
/// this stack cannot keep.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/leasing_operations/application/workspace_alerts_controller.dart';
import '../../../features/leasing_operations/domain/operations_signal_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_status_badge.dart';
import '../../navigation/app_navigation.dart';
import '../../state/app_state.dart';
import '../../navigation/cloud_route_request.dart';
import '../../theme/app_theme.dart';

/// German label for a signal type. An unmapped key is shown as it came: a new
/// server signal must be visible, not silently dropped or renamed into
/// something this build guessed.
String workspaceAlertTypeLabel(String type) => switch (type) {
  'lease_expiry' => 'Vertrag läuft aus',
  'lease_expired_open' => 'Vertrag überfällig',
  'vacancy_missing_since' => 'Leerstand ohne Datum',
  'vacancy_aged' => 'Langer Leerstand',
  'offline_missing_reason' => 'Einheit offline ohne Grund',
  'missing_tenant_contact' => 'Mieterkontakt unvollständig',
  'stale_rent_roll' => 'Mietaufstellung veraltet',
  _ => type,
};

String workspaceAlertSeverityLabel(String severity) => switch (severity) {
  'critical' => 'Kritisch',
  'warning' => 'Warnung',
  'info' => 'Hinweis',
  _ => severity,
};

NxBadgeKind workspaceAlertSeverityKind(String severity) => switch (severity) {
  'critical' => NxBadgeKind.error,
  'warning' => NxBadgeKind.warning,
  'info' => NxBadgeKind.info,
  _ => NxBadgeKind.neutral,
};

class WorkspaceAlertsScreen extends ConsumerWidget {
  const WorkspaceAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceAlertsControllerProvider);
    final controller = ref.read(workspaceAlertsControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NxPageHeader(
            title: 'Was heute ansteht',
            subtitle: _subtitle(state),
            secondaryActions: <Widget>[
              IconButton(
                key: const Key('workspace-alerts-reload'),
                tooltip: 'Neu laden',
                onPressed: () => controller.load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, ref, state, controller)),
        ],
      ),
    );
  }

  String _subtitle(WorkspaceAlertsState state) {
    final DateTime? computedAt = state.computedAt;
    if (computedAt == null) {
      return 'Offene Signale aus allen Objekten dieses Workspace.';
    }
    final local = computedAt.toLocal();
    final time =
        '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.${local.year}, '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    // Stated, not implied. Nothing pushes these; they were judged when this
    // read ran, and a list that looked live would be a promise the stack
    // cannot keep.
    return 'Serverseitig ermittelt am $time.';
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    WorkspaceAlertsState state,
    WorkspaceAlertsController controller,
  ) {
    switch (state.phase) {
      case WorkspaceAlertsPhase.idle:
      case WorkspaceAlertsPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('workspace-alerts-loading')),
        );
      case WorkspaceAlertsPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('workspace-alerts-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für diese Übersicht fehlt die Berechtigung, Verträge zu lesen.',
            icon: Icons.lock_outline,
          ),
        );
      case WorkspaceAlertsPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('workspace-alerts-error'),
            title: 'Die Übersicht konnte nicht geladen werden',
            // Never an empty list here. A worklist with nothing on it is good
            // news, and a failure must not be able to look like it.
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case WorkspaceAlertsPhase.ready:
        return _ready(context, ref, state, controller);
    }
  }

  Widget _ready(
    BuildContext context,
    WidgetRef ref,
    WorkspaceAlertsState state,
    WorkspaceAlertsController controller,
  ) {
    final semantic = context.semanticColors;
    return ListView(
      key: const Key('workspace-alerts-list'),
      children: <Widget>[
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Kritisch',
              value: '${state.criticalCount}',
              status: state.criticalCount > 0 ? semantic.error : null,
              // The server's count over everything that matched, not over the
              // rows below. With a cap in play the two differ, and the smaller
              // one would be the reassuring lie.
              caption: 'im gesamten Workspace',
            ),
            NxKpiTile(
              label: 'Warnungen',
              value: '${state.warningCount}',
              status: state.warningCount > 0 ? semantic.warning : null,
              caption: 'im gesamten Workspace',
            ),
            NxKpiTile(
              label: 'Hinweise',
              value: '${state.infoCount}',
              caption: 'im gesamten Workspace',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _Filters(state: state, controller: controller),
        if (state.truncated) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('workspace-alerts-truncated'),
            title: 'Nicht alle Signale angezeigt',
            message:
                '${state.signals.length} von ${state.total} Signalen werden '
                'gezeigt, die kritischsten zuerst. Die Zahlen oben zählen alle.',
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (state.signals.isEmpty)
          const NxCard(
            child: NxEmptyState(
              key: Key('workspace-alerts-empty'),
              title: 'Nichts offen',
              description:
                  'Für diesen Filter meldet der Server kein Signal. Das ist '
                  'eine Antwort, keine leere Liste: die Zahlen oben zeigen, '
                  'was insgesamt vorliegt.',
              icon: Icons.check_circle_outline,
            ),
          )
        else
          for (final OperationsSignalDto signal in state.signals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _AlertRow(signal: signal),
            ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.controller});

  final WorkspaceAlertsState state;
  final WorkspaceAlertsController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            key: const Key('workspace-alerts-severity'),
            value: state.severityFilter,
            // Without this the field lays out to its widest item and overflows
            // the box the Wrap gave it; "Zurückgestellt" is the one that does
            // it on the status field beside this one.
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dringlichkeit',
              isDense: true,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: workspaceAlertSeverityAll,
                child: Text('Alle'),
              ),
              DropdownMenuItem<String>(value: 'critical', child: Text('Kritisch')),
              DropdownMenuItem<String>(value: 'warning', child: Text('Warnung')),
              DropdownMenuItem<String>(value: 'info', child: Text('Hinweis')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                controller.setSeverityFilter(value);
              }
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            key: const Key('workspace-alerts-status'),
            value: state.statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: workspaceAlertStatusAll,
                child: Text('Alle'),
              ),
              DropdownMenuItem<String>(value: 'open', child: Text('Offen')),
              DropdownMenuItem<String>(
                value: 'dismissed',
                child: Text('Zurückgestellt'),
              ),
              DropdownMenuItem<String>(value: 'resolved', child: Text('Erledigt')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                controller.setStatusFilter(value);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.signal});

  final OperationsSignalDto signal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return NxCard(
      variant: NxCardVariant.interactive,
      // Straight to the property's own alert surface, where the signal can be
      // acknowledged. The workspace list deliberately does not acknowledge:
      // that write needs the property context and a reason, and offering it
      // from a row here would invite dismissing things unread.
      onTap: () => requestCloudRoute(
        ref,
        CloudRouteTarget(
          page: GlobalPage.properties,
          surface: CloudRouteSurface.operationsAlerts,
          propertyId: signal.propertyId,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  workspaceAlertTypeLabel(signal.type),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              NxStatusBadge(
                label: workspaceAlertSeverityLabel(signal.severity),
                kind: workspaceAlertSeverityKind(signal.severity),
              ),
              if (signal.status != 'open') ...<Widget>[
                const SizedBox(width: AppSpacing.xxs),
                NxStatusBadge(
                  label: signal.status == 'dismissed'
                      ? 'Zurückgestellt'
                      : 'Erledigt',
                  kind: NxBadgeKind.neutral,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            // The property name, always: without it a workspace-wide message
            // like "Lease 4B expires in 12 days" names nothing findable.
            signal.propertyName ?? 'Objekt ${signal.propertyId}',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(signal.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(signal.recommendedAction, style: muted),
        ],
      ),
    );
  }
}
