/// One leasing case in full (Welle 3, AP4).
///
/// The head card is the pipeline in one place: which stage the case is on, the
/// one step forward, and — when that step is not available — *why*, from
/// `LeasingCaseDto.blockedReason` rather than from a rejected round trip. That
/// is the difference between a disabled button and an explained one.
library;

import 'package:flutter/material.dart';

import '../../../../features/leasing_operations/application/leasing_cases_controller.dart';
import '../../../../features/leasing_operations/domain/leasing_case_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_section_header.dart';
import '../../../theme/app_theme.dart';
import 'lease_detail_view.dart';
import 'widgets/lease_lifecycle.dart';
import 'widgets/leasing_badges.dart';

class LeasingCaseDetailView extends StatelessWidget {
  const LeasingCaseDetailView({
    super.key,
    required this.leasingCase,
    required this.unitCode,
    required this.prospectName,
    required this.leaseName,
    required this.canMutate,
    required this.onEdit,
    required this.onAdvance,
    required this.onCancel,
    this.refusal,
  });

  final LeasingCaseDto leasingCase;
  final String? unitCode;
  final String? prospectName;
  final String? leaseName;
  final bool canMutate;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  final LeasingCaseStepRefusal? refusal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = leasingCase.status.nextStage;
    final blocked = leasingCase.blockedReason;
    final terminal = leasingCase.status.isTerminal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      leasingCase.caseName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  LeasingCaseStatusBadge(status: leasingCase.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                terminal
                    ? 'Dieser Fall ist '
                          '${leasingCaseStatusLabel(leasingCase.status).toLowerCase()}. '
                          'Ein neuer Anlauf ist ein neuer Fall.'
                    : 'Stufe ${leasingCase.status.stageRank} von 10. Der '
                          'nächste Schritt ist '
                          '„${leasingCaseStatusLabel(next!)}".',
                style: theme.textTheme.bodySmall,
              ),
              if (blocked != null && !terminal) ...<Widget>[
                const SizedBox(height: 12),
                _BlockedNotice(text: leasingCaseBlockedReasonLabel(blocked)),
              ],
              if (refusal?.serverMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _BlockedNotice(text: refusal!.serverMessage!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (next != null)
                    FilledButton.icon(
                      // Disabled *with* a reason above, never silently.
                      onPressed: canMutate && blocked == null ? onAdvance : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text('Auf „${leasingCaseStatusLabel(next)}"'),
                    ),
                  if (!terminal)
                    OutlinedButton.icon(
                      onPressed: canMutate ? onEdit : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Bearbeiten'),
                    ),
                  if (!terminal)
                    TextButton.icon(
                      onPressed: canMutate ? onCancel : null,
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Fall abbrechen'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(title: 'Fall'),
              LeaseDetailRow(
                label: 'Herkunft',
                value: leasingCaseSourceLabel(leasingCase.source),
              ),
              LeaseDetailRow(
                label: 'Interessent',
                value: leasingCase.prospectPartyId == null
                    ? 'Noch nicht identifiziert'
                    : prospectName ?? 'Partei nicht auflösbar',
              ),
              LeaseDetailRow(
                label: 'Einheit',
                value: leasingCase.unitId == null
                    ? 'Noch offen'
                    : unitCode ?? 'Einheit nicht auflösbar',
              ),
              LeaseDetailRow(
                label: 'Erzeugter Vertrag',
                value: leasingCase.leaseId == null
                    ? 'Noch keiner'
                    : leaseName ?? 'Vertrag nicht auflösbar',
              ),
              if (leasingCase.notes != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(leasingCase.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(
                title: 'Verlauf',
                description: 'Die vollständige Stufenhistorie liegt im '
                    'Änderungsprotokoll.',
              ),
              LeaseDetailRow(
                label: 'Eröffnet',
                value: formatLeaseDate(leasingCase.openedAt),
              ),
              LeaseDetailRow(
                label: 'Abgeschlossen',
                value: formatLeaseDate(leasingCase.completedAt),
              ),
              LeaseDetailRow(
                label: 'Abgebrochen',
                value: formatLeaseDate(leasingCase.cancelledAt),
              ),
              LeaseDetailRow(
                label: 'Zuletzt geändert',
                value: formatLeaseDate(leasingCase.updatedAt),
              ),
              LeaseDetailRow(label: 'Version', value: '${leasingCase.version}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlockedNotice extends StatelessWidget {
  const _BlockedNotice({required this.text});

  final String text;

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
          Icon(Icons.rule_outlined, color: semantic.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Der nächste Schritt ist noch nicht möglich',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
