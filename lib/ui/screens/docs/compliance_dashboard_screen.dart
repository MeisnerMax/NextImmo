import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/compliance_dashboard_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_formatting.dart';
import 'widgets/document_notices.dart';
import 'widgets/document_requirement_table.dart';

/// Which requirement a finding row points at, so the host decides where that
/// goes. The local shell navigates in place, the additive cloud route pushes
/// the property documents route — neither belongs in this screen.
typedef ComplianceOpenCallback =
    void Function(DocumentRequirementProjection requirement);

/// The workspace compliance dashboard (SCR-052, Wave 2, Arbeitspaket 2).
///
/// Reads the **server-side** requirement projection in one call
/// (`RequirementPolicyRepository.evaluateWorkspace`), replacing the previous
/// client-side loop that called `checkComplianceForEntity` once per property.
/// It derives nothing itself: the KPI tiles count rows the server already
/// classified, so a state can never mean one thing here and another on the
/// document screens.
///
/// Consumes only the feature contract, which is what lets the additive cloud
/// route mount it directly.
class ComplianceDashboardScreen extends ConsumerWidget {
  const ComplianceDashboardScreen({super.key, this.onOpenRequirement});

  final ComplianceOpenCallback? onOpenRequirement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(complianceDashboardControllerProvider);
    final controller = ref.read(
      complianceDashboardControllerProvider.notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NxPageHeader(
          title: 'Compliance',
          subtitle:
              'Geforderte Nachweise der Objekte dieses Arbeitsbereichs — '
              'serverseitig ausgewertet.',
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => controller.setOnlyUnmet(!state.onlyUnmet),
              icon: Icon(
                state.onlyUnmet
                    ? Icons.filter_alt_off_outlined
                    : Icons.filter_alt_outlined,
              ),
              label: Text(
                state.onlyUnmet ? 'Alle anzeigen' : 'Nur offene anzeigen',
              ),
            ),
            OutlinedButton.icon(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        ..._coverageNotices(state),
        if (state.phase == CompliancePhase.ready ||
            state.phase == CompliancePhase.empty) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          _KpiRow(state: state),
        ],
        const SizedBox(height: AppSpacing.section),
        _buildBody(state, controller),
      ],
    );
  }

  /// Coverage is stated, never implied. Both notices exist because the honest
  /// answer to "is this everything?" is sometimes no.
  List<Widget> _coverageNotices(ComplianceDashboardState state) {
    final notices = <Widget>[];
    if (state.scopedRuleCount > 0) {
      notices.addAll(<Widget>[
        const SizedBox(height: AppSpacing.component),
        DocumentNotice(
          title: 'Nicht vollständig ausgewertet',
          icon: Icons.rule_outlined,
          description:
              '${state.scopedRuleCount} Regel(n) gelten nur für bestimmte '
              'Objektarten und lassen sich nur je Objekt auswerten. Sie '
              'stehen in der Dokumentenansicht des jeweiligen Objekts.',
        ),
      ]);
    }
    if (!state.directoryAvailable &&
        state.phase != CompliancePhase.loading &&
        state.phase != CompliancePhase.idle) {
      notices.addAll(<Widget>[
        const SizedBox(height: AppSpacing.component),
        const DocumentNotice(
          title: 'Eingeschränkte Abdeckung',
          icon: Icons.info_outline,
          description:
              'Das Objektverzeichnis ist in diesem Modus nicht verfügbar. '
              'Ausgewertet werden nur Objekte, für die bereits eine '
              'Anforderung oder ein Dokument hinterlegt ist.',
        ),
      ]);
    } else if (!state.directoryComplete) {
      notices.addAll(<Widget>[
        const SizedBox(height: AppSpacing.component),
        const DocumentNotice(
          title: 'Teilweise ausgewertet',
          icon: Icons.info_outline,
          severity: DocumentNoticeSeverity.warning,
          description:
              'Es konnten nicht alle Objekte des Arbeitsbereichs einbezogen '
              'werden. Die Übersicht ist damit unvollständig.',
        ),
      ]);
    }
    return notices;
  }

  Widget _buildBody(
    ComplianceDashboardState state,
    ComplianceDashboardController controller,
  ) {
    switch (state.phase) {
      case CompliancePhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Compliance wird je Arbeitsbereich ausgewertet. Melde dich an '
              'oder wähle einen Arbeitsbereich.',
          icon: Icons.workspaces_outline,
        );
      case CompliancePhase.loading:
        return const NxDataTableShell(loading: true, child: SizedBox.shrink());
      case CompliancePhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Compliance',
          description:
              'Dein Konto darf die Dokumentanforderungen dieses '
              'Arbeitsbereichs nicht sehen. Wende dich an eine '
              'Administratorin oder einen Administrator des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case CompliancePhase.error:
        return NxEmptyState(
          title: 'Compliance konnte nicht ausgewertet werden',
          description:
              'Beim Auswerten der Anforderungen ist ein Fehler aufgetreten. '
              'Bitte versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case CompliancePhase.empty:
        // A positive empty state: nothing outstanding is the good outcome, not
        // an absence of data.
        return NxEmptyState(
          title:
              state.onlyUnmet
                  ? 'Alles erfüllt'
                  : 'Keine Anforderungen hinterlegt',
          description:
              state.onlyUnmet
                  ? 'Für die ausgewerteten Objekte ist derzeit kein Nachweis '
                      'offen.${_checkedSuffix(state)}'
                  : 'Für die Objekte dieses Arbeitsbereichs sind keine '
                      'Pflichtdokumente definiert.${_checkedSuffix(state)}',
          icon:
              state.onlyUnmet
                  ? Icons.verified_outlined
                  : Icons.rule_folder_outlined,
        );
      case CompliancePhase.ready:
        return DocumentRequirementTable(
          requirements: state.requirements,
          entityLabel:
              (requirement) =>
                  state.entityNames[requirement.entityId] ??
                  requirement.entityId,
          onOpen: onOpenRequirement,
        );
    }
  }

  String _checkedSuffix(ComplianceDashboardState state) {
    final checkedAt = state.lastCheckedAt;
    if (checkedAt == null) {
      return '';
    }
    final local = checkedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return ' Zuletzt geprüft: ${formatDocumentDate(checkedAt)}, '
        '$hour:$minute Uhr.';
  }
}

/// Severity-ordered summary. The four tiles together cover every state the
/// table can show except an explicit waiver, so the numbers and the list can
/// never tell different stories.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.state});

  final ComplianceDashboardState state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: <Widget>[
        _KpiTile(
          label: 'Offen',
          value: state.outstandingCount,
          badge: 'davon ${state.blockingCount} pflichtig',
          kind: NxBadgeKind.error,
        ),
        _KpiTile(
          label: 'Läuft ab',
          value: state.expiringCount,
          badge: 'in 45 Tagen',
          kind: NxBadgeKind.warning,
        ),
        _KpiTile(
          label: 'In Prüfung',
          value: state.inReviewCount,
          badge: 'Upload oder Verifikation offen',
          kind: NxBadgeKind.info,
        ),
        _KpiTile(
          label: 'Erfüllt',
          value: state.satisfiedCount,
          badge: 'verifiziert und gültig',
          kind: NxBadgeKind.success,
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.badge,
    required this.kind,
  });

  final String label;
  final int value;
  final String badge;
  final NxBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: NxCard(
        variant: NxCardVariant.kpi,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)
                  .merge(context.tabularNumericStyle),
            ),
            const SizedBox(height: AppSpacing.xs),
            NxStatusBadge(label: badge, kind: kind),
          ],
        ),
      ),
    );
  }
}
