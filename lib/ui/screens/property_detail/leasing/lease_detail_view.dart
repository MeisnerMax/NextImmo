/// The full detail of one lease (Welle 3, AP3 — SCR-029).
///
/// Replaces the 920-LOC legacy `LeaseDetailScreen`, which carried zero `Nx*`
/// components and presented the lifecycle as a status dropdown. Here STM-005 is
/// the surface: the head card names the one lawful next step as its primary
/// action, the abort edge sits beside it, and nothing else is offered — a move
/// the chain does not contain is not a disabled button, it simply does not
/// exist.
///
/// Two refusals are explained rather than shown as failures:
///
///   * **A binding lease cannot be edited.** From the first signature on,
///     `update_lease` refuses; the view says why instead of offering an edit
///     that would bounce ("a change of terms is a new lease").
///   * **A refused transition names what STM-005 does allow**, not what it
///     rejected — see [LeaseTransitionRejection].
library;

import 'package:flutter/material.dart';

import '../../../../features/leasing_operations/application/leases_controller.dart';
import '../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_section_header.dart';
import '../../../theme/app_theme.dart';
import 'widgets/lease_form_dialog.dart';
import 'widgets/lease_lifecycle.dart';
import 'widgets/leasing_badges.dart';

class LeaseDetailView extends StatelessWidget {
  const LeaseDetailView({
    super.key,
    required this.lease,
    required this.unitCode,
    required this.tenantName,
    required this.canMutate,
    required this.onEdit,
    required this.onAdvance,
    required this.onCancel,
    this.rejection,
  });

  final LeaseDto lease;

  /// Null when the companion unit read could not resolve the reference — shown
  /// as an unresolved reference rather than as an empty cell.
  final String? unitCode;
  final String? tenantName;
  final bool canMutate;
  final VoidCallback onEdit;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  final LeaseTransitionRejection? rejection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final advanceLabel = leaseAdvanceLabel(lease.status);
    final terminal = lease.status.isTerminal;

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
                      lease.leaseName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  LeaseStatusBadge(status: lease.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(_lifecyclePosition(), style: theme.textTheme.bodySmall),
              if (rejection != null) ...<Widget>[
                const SizedBox(height: 12),
                _RejectionNotice(rejection: rejection!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (advanceLabel != null)
                    FilledButton.icon(
                      onPressed: canMutate ? onAdvance : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(advanceLabel),
                    ),
                  if (lease.status.isEditable)
                    OutlinedButton.icon(
                      onPressed: canMutate ? onEdit : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Bearbeiten'),
                    ),
                  if (!terminal)
                    TextButton.icon(
                      onPressed: canMutate ? onCancel : null,
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Vertrag abbrechen'),
                    ),
                ],
              ),
              if (!lease.status.isEditable && !terminal) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Dieser Vertrag ist bindend: seine Konditionen sind nicht '
                  'mehr änderbar. Eine Änderung der Konditionen ist ein neuer '
                  'Vertrag.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(title: 'Vertragsdaten'),
              LeaseDetailRow(
                label: 'Einheit',
                value: unitCode ?? 'Einheit nicht auflösbar',
              ),
              LeaseDetailRow(
                label: 'Mieter',
                value: _tenantValue(),
              ),
              LeaseDetailRow(
                label: 'Abrechnung',
                value: leaseBillingFrequencyLabel(lease.billingFrequency),
              ),
              if (lease.notes != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(lease.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(title: 'Laufzeit und Fristen'),
              LeaseDetailRow(
                label: 'Beginn',
                value: formatLeaseDate(lease.startDate),
              ),
              LeaseDetailRow(
                label: 'Ende',
                value: lease.endDate == null
                    ? 'Unbefristet'
                    : formatLeaseDate(lease.endDate),
              ),
              LeaseDetailRow(
                label: 'Einzug',
                value: formatLeaseDate(lease.moveInDate),
              ),
              LeaseDetailRow(
                label: 'Auszug',
                value: formatLeaseDate(lease.moveOutDate),
              ),
              LeaseDetailRow(
                label: 'Unterschrieben am',
                value: formatLeaseDate(lease.signedDate),
              ),
              LeaseDetailRow(
                label: 'Kündigung',
                value: formatLeaseDate(lease.noticeDate),
              ),
              LeaseDetailRow(
                label: 'Verlängerungsoption',
                value: formatLeaseDate(lease.renewalOptionDate),
              ),
              LeaseDetailRow(
                label: 'Sonderkündigungsrecht',
                value: formatLeaseDate(lease.breakOptionDate),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(
                title: 'Miete und Nebenkosten',
                // The total comes from the DTO; recomputing it in the screen is
                // how two numbers start disagreeing.
                description: 'Gesamtmiete laut Vertrag, nicht im Screen '
                    'nachgerechnet.',
              ),
              LeaseDetailRow(
                label: 'Grundmiete',
                value: formatLeaseMoney(
                  lease.baseRentMonthly,
                  lease.currencyCode,
                ),
              ),
              LeaseDetailRow(
                label: 'Nebenkosten',
                value: formatLeaseMoney(
                  lease.ancillaryChargesMonthly,
                  lease.currencyCode,
                ),
              ),
              LeaseDetailRow(
                label: 'Stellplatz / Sonstiges',
                value: formatLeaseMoney(
                  lease.parkingOtherChargesMonthly,
                  lease.currencyCode,
                ),
              ),
              LeaseDetailRow(
                label: 'Gesamt / Monat',
                value: formatLeaseMoney(
                  lease.totalRentMonthly,
                  lease.currencyCode,
                ),
              ),
              LeaseDetailRow(
                label: 'Kaution',
                value: formatLeaseMoney(
                  lease.securityDeposit,
                  lease.currencyCode,
                ),
              ),
              LeaseDetailRow(
                label: 'Zahltag',
                value: lease.paymentDayOfMonth == null
                    ? '—'
                    : '${lease.paymentDayOfMonth}. des Monats',
              ),
              LeaseDetailRow(
                label: 'Mietfreie Monate',
                value: lease.rentFreePeriodMonths?.toString() ?? '—',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(
                title: 'Statusverlauf',
                // Honest about the source: the contract exposes the terminal
                // stamps and the last writer, not a transition log. The full
                // append-only history lives in the audit trail.
                description: 'Die vollständige Übergangshistorie liegt im '
                    'Änderungsprotokoll.',
              ),
              LeaseDetailRow(
                label: 'Aktueller Status',
                value: leaseStatusLabel(lease.status),
              ),
              LeaseDetailRow(
                label: 'Beendet am',
                value: formatLeaseDate(lease.endedAt),
              ),
              LeaseDetailRow(
                label: 'Abgebrochen am',
                value: formatLeaseDate(lease.cancelledAt),
              ),
              LeaseDetailRow(
                label: 'Angelegt',
                value: formatLeaseDate(lease.createdAt),
              ),
              LeaseDetailRow(
                label: 'Zuletzt geändert',
                value: formatLeaseDate(lease.updatedAt),
              ),
              LeaseDetailRow(label: 'Version', value: '${lease.version}'),
            ],
          ),
        ),
      ],
    );
  }

  /// Where the lease stands in the chain, in one sentence. A terminal lease
  /// says so rather than leaving the missing action unexplained.
  String _lifecyclePosition() {
    final next = lease.status.nextStatus;
    if (next == null) {
      return 'Dieser Vertrag ist ${leaseStatusLabel(lease.status).toLowerCase()} '
          'und damit abgeschlossen. Ein neuer Anlauf ist ein neuer Vertrag.';
    }
    final effective = lease.isEffective
        ? 'Er ist wirksam und zählt für Belegung und Rent Roll. '
        : 'Er ist noch nicht wirksam und zählt weder für die Belegung noch für '
            'den Rent Roll. ';
    return '$effective'
        'Der nächste zulässige Schritt ist „${leaseStatusLabel(next)}".';
  }

  String _tenantValue() {
    if (lease.tenantPartyId == null) {
      return 'Noch nicht benannt';
    }
    return tenantName ?? 'Partei nicht auflösbar';
  }
}

/// The explained refusal. It names what STM-005 allows instead of repeating
/// what it rejected, and keeps the server's own message underneath so nothing
/// is hidden.
class _RejectionNotice extends StatelessWidget {
  const _RejectionNotice({required this.rejection});

  final LeaseTransitionRejection rejection;

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
                  'Dieser Schritt ist nicht möglich',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  leaseTransitionRefusedExplanation(
                    from: rejection.from,
                    attempted: rejection.attempted,
                  ),
                ),
                if (rejection.serverMessage != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    rejection.serverMessage!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LeaseDetailRow extends StatelessWidget {
  const LeaseDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 160,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
