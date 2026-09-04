import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/compliance_dashboard_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_list_skeleton.dart';
import '../../components/nx_notice.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_formatting.dart';
import 'widgets/document_requirement_table.dart';

/// Which requirement a finding row points at, so the host decides where that
/// goes — state-first through the cloud route request, never a `Navigator`
/// flow of this screen (DOCUMENTS-V2 §3).
typedef ComplianceOpenCallback =
    void Function(DocumentRequirementProjection requirement);

/// The workspace compliance view — tab `Compliance` of the documents
/// destination (DOCUMENTS-V2 increment C).
///
/// Reads the **server-side** requirement projection in one call
/// (`RequirementPolicyRepository.evaluateWorkspace`). It derives nothing
/// itself: the KPI tiles count rows the server already classified, so a state
/// can never mean one thing here and another on the document screens.
/// Coverage is stated, never implied — the three notices exist because the
/// honest answer to "is this everything?" is sometimes no.
///
/// A pull surface (§9): registry and link changes raise no invalidation until
/// `DOCUMENTS-REALTIME-01`; "Aktualisieren" lives in the host header. No
/// reminders are produced from these states (`DOCUMENTS-REMINDERS-01`).
class ComplianceDashboardScreen extends ConsumerWidget {
  const ComplianceDashboardScreen({super.key, this.onOpenRequirement});

  final ComplianceOpenCallback? onOpenRequirement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(complianceDashboardControllerProvider);
    final controller = ref.read(complianceDashboardControllerProvider.notifier);

    return Column(
      key: const Key('documents-compliance'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListFilterBar(
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('documents-compliance-only-unmet'),
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
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.section),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ..._coverageNotices(state),
                if (state.phase == CompliancePhase.ready ||
                    state.phase == CompliancePhase.empty) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  _KpiRow(state: state),
                  const SizedBox(height: AppSpacing.component),
                ],
                _buildBody(state, controller),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _coverageNotices(ComplianceDashboardState state) {
    final notices = <Widget>[];
    if (state.scopedRuleCount > 0) {
      notices.addAll(<Widget>[
        const SizedBox(height: AppSpacing.component),
        NxNotice(
          key: const Key('documents-compliance-scoped-rules'),
          kind: NxNoticeKind.info,
          icon: Icons.rule_outlined,
          title: 'Nicht vollständig ausgewertet',
          message:
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
        const NxNotice(
          key: Key('documents-compliance-directory-missing'),
          kind: NxNoticeKind.info,
          title: 'Eingeschränkte Abdeckung',
          message:
              'Das Objektverzeichnis ist in dieser Sitzung nicht lesbar '
              '(property.read). Ausgewertet werden nur Objekte, für die '
              'bereits eine Anforderung oder ein Dokument hinterlegt ist.',
        ),
      ]);
    } else if (!state.directoryComplete) {
      notices.addAll(<Widget>[
        const SizedBox(height: AppSpacing.component),
        const NxNotice(
          key: Key('documents-compliance-directory-partial'),
          kind: NxNoticeKind.warning,
          title: 'Teilweise ausgewertet',
          message:
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
        return const _Fill(
          child: NxEmptyState(
            key: Key('documents-compliance-idle'),
            title: 'Kein Arbeitsbereich aktiv',
            description:
                'Compliance wird je Arbeitsbereich ausgewertet. Melde dich an '
                'oder wähle einen Arbeitsbereich.',
            icon: Icons.workspaces_outline,
          ),
        );
      case CompliancePhase.loading:
        return const _Fill(
          child: NxCard(
            key: Key('documents-compliance-loading'),
            child: NxListSkeleton(rows: 6),
          ),
        );
      case CompliancePhase.forbidden:
        return const _Fill(
          child: NxEmptyState(
            key: Key('documents-compliance-forbidden'),
            title: 'Kein Zugriff auf Compliance',
            description:
                'Die Auswertung der Dokumentanforderungen benötigt die '
                'Berechtigung (document.read).',
            icon: Icons.lock_outline,
          ),
        );
      case CompliancePhase.error:
        return _Fill(
          child: NxEmptyState.error(
            key: const Key('documents-compliance-error'),
            title: 'Compliance konnte nicht ausgewertet werden',
            description:
                'Beim Auswerten der Anforderungen ist ein Fehler aufgetreten. '
                'Bitte versuche es erneut.',
            onRetry: controller.load,
          ),
        );
      case CompliancePhase.empty:
        // A positive empty state: nothing outstanding is the good outcome, not
        // an absence of data.
        return _Fill(
          child: NxEmptyState(
            key: const Key('documents-compliance-empty'),
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
          ),
        );
      case CompliancePhase.ready:
        return _Fill(
          child: DocumentRequirementTable(
            key: const Key('documents-compliance-table'),
            requirements: state.requirements,
            entityLabel:
                (requirement) =>
                    state.entityNames[requirement.entityId] ??
                    requirement.entityId,
            onOpen: onOpenRequirement,
          ),
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

/// Severity-ordered summary on the shared tiles (Foundation §12). The four
/// tiles together cover every state the table can show except an explicit
/// waiver, so the numbers and the list can never tell different stories.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.state});

  final ComplianceDashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return NxKpiRow(
      key: const Key('documents-compliance-kpis'),
      children: <Widget>[
        NxKpiTile(
          label: 'Offen',
          value: '${state.outstandingCount}',
          caption: 'davon ${state.blockingCount} pflichtig',
          status: colors.error,
        ),
        NxKpiTile(
          label: 'Läuft ab',
          value: '${state.expiringCount}',
          caption: 'in 45 Tagen',
          status: colors.warning,
        ),
        NxKpiTile(
          label: 'In Prüfung',
          value: '${state.inReviewCount}',
          caption: 'Upload oder Verifikation offen',
          status: colors.info,
        ),
        NxKpiTile(
          label: 'Erfüllt',
          value: '${state.satisfiedCount}',
          caption: 'verifiziert und gültig',
          status: colors.success,
        ),
      ],
    );
  }
}

/// Body slot inside the tab's one scroll region.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
