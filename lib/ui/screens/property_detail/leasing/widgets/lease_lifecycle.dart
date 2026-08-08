/// STM-005 as a guided lifecycle (Welle 3, AP3) — the shared transition
/// building block for the lease list and the lease detail.
///
/// The chain has exactly one forward edge per state and one abort edge, so the
/// UI offers exactly that: a single primary action named after the step it
/// performs, plus "abbrechen" with a mandatory reason. A status dropdown would
/// invite six moves the server refuses; naming the one lawful step makes the
/// state machine legible instead of hiding it behind a generic form.
///
/// Two rules of the migration are visible here rather than only enforced:
///
///   * **Activating is the write that changes occupancy.** The confirmation
///     says so, because the consequence lands on a different aggregate than the
///     one the user is looking at (AGG-004).
///   * **A move-out date belongs only to ending a lease.** It is offered on
///     that step and nowhere else — `transition_lease_status` refuses it
///     elsewhere with `validationFailed`, and offering it anyway would be an
///     affordance built to fail.
library;

import 'package:flutter/material.dart';

import '../../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../../components/responsive_constraints.dart';
import 'leasing_badges.dart';

/// The label of the one lawful forward step out of [status], or null when the
/// lease is terminal and there is nothing left to offer.
String? leaseAdvanceLabel(LeaseStatus status) => switch (status.nextStatus) {
  LeaseStatus.reviewed => 'Als geprüft markieren',
  LeaseStatus.sent => 'Als versendet markieren',
  LeaseStatus.tenantSigned => 'Unterschrift Mieter erfassen',
  LeaseStatus.landlordSigned => 'Unterschrift Vermieter erfassen',
  LeaseStatus.active => 'Vertrag aktivieren',
  LeaseStatus.ended => 'Vertrag beenden',
  _ => null,
};

/// What the step actually does, in the words of the domain rather than of the
/// schema. Shown in the confirmation so the user commits to a consequence, not
/// to a status name.
String leaseAdvanceExplanation(LeaseStatus status) => switch (status.nextStatus) {
  LeaseStatus.reviewed =>
    'Der Entwurf gilt danach als geprüft. Die Konditionen bleiben änderbar, '
        'bis der Vertrag unterschrieben ist.',
  LeaseStatus.sent =>
    'Der Vertrag gilt danach als an den Mieter versendet.',
  LeaseStatus.tenantSigned =>
    'Ab der Unterschrift des Mieters ist der Vertrag bindend: die Konditionen '
        'sind danach nicht mehr änderbar — eine Änderung ist ein neuer Vertrag.',
  LeaseStatus.landlordSigned =>
    'Der Vertrag ist danach von beiden Seiten unterschrieben und kann '
        'aktiviert werden.',
  LeaseStatus.active =>
    'Mit der Aktivierung wird der Vertrag wirksam und die Einheit gilt als '
        'vermietet. Die Belegung folgt aus den wirksamen Verträgen — sie wird '
        'nicht separat gesetzt.',
  LeaseStatus.ended =>
    'Der Vertrag ist danach beendet. Ist es der letzte wirksame Vertrag der '
        'Einheit, gilt sie wieder als leerstehend. Ein Auszugsdatum ist genau '
        'hier zulässig und sonst nirgends.',
  _ => '',
};

/// The explanation for a refused transition, built from STM-005 itself rather
/// than from the raw server message: naming what *is* allowed is more useful
/// than repeating what was not.
String leaseTransitionRefusedExplanation({
  required LeaseStatus from,
  required LeaseStatus attempted,
}) {
  final next = from.nextStatus;
  final current = leaseStatusLabel(from);
  final target = leaseStatusLabel(attempted);
  if (next == null) {
    return 'Dieser Vertrag ist $current und damit abgeschlossen — aus diesem '
        'Zustand führt kein Schritt mehr heraus, auch nicht nach „$target".';
  }
  return 'STM-005 erlaubt von „$current" nur „${leaseStatusLabel(next)}" oder '
      'den Abbruch — „$target" ist von hier aus kein zulässiger Schritt. '
      'Rückwärts geht es nicht: ein neuer Anlauf ist ein neuer Vertrag.';
}

/// What a caller confirmed in [showLeaseAdvanceDialog]. [moveOutDate] is only
/// ever non-null on the step into [LeaseStatus.ended].
class LeaseAdvanceRequest {
  const LeaseAdvanceRequest({this.moveOutDate});

  final DateTime? moveOutDate;
}

/// Confirms the one forward step out of [lease]'s current status. Returns null
/// when the user backs out.
Future<LeaseAdvanceRequest?> showLeaseAdvanceDialog(
  BuildContext context, {
  required LeaseDto lease,
}) async {
  final target = lease.status.nextStatus;
  final label = leaseAdvanceLabel(lease.status);
  if (target == null || label == null) {
    return null;
  }
  final endsLease = target == LeaseStatus.ended;
  DateTime? moveOutDate = lease.moveOutDate;

  return showDialog<LeaseAdvanceRequest>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${lease.leaseName}: ${leaseStatusLabel(lease.status)} → '
                  '${leaseStatusLabel(target)}'),
              const SizedBox(height: 12),
              Text(leaseAdvanceExplanation(lease.status)),
              if (endsLease) ...<Widget>[
                const SizedBox(height: 16),
                LeaseDateField(
                  label: 'Auszugsdatum (optional)',
                  value: moveOutDate,
                  onChanged: (value) =>
                      setDialogState(() => moveOutDate = value),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              LeaseAdvanceRequest(moveOutDate: endsLease ? moveOutDate : null),
            ),
            child: Text(label),
          ),
        ],
      ),
    ),
  );
}

/// Collects the mandatory reason for aborting a lease. Returns null when the
/// user backs out; never returns an empty reason — the server requires one and
/// so does this dialog.
Future<String?> showLeaseCancellationDialog(
  BuildContext context, {
  required LeaseDto lease,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${lease.leaseName} abbrechen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 420),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Ein Abbruch ist endgültig: der Vertrag lässt sich danach nicht '
                'wieder öffnen, ein neuer Anlauf ist ein neuer Vertrag. Der '
                'Grund wird im Änderungsprotokoll festgehalten.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Grund',
                  hintText: 'z. B. Mieter zurückgetreten',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Bitte einen Grund angeben.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Zurück'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            }
          },
          child: const Text('Vertrag abbrechen'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// A nullable date input shared by the transition dialogs and the lease form.
class LeaseDateField extends StatelessWidget {
  const LeaseDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(value == null ? 'Nicht gesetzt' : formatLeaseDate(value))),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (picked != null) {
                onChanged(DateTime.utc(picked.year, picked.month, picked.day));
              }
            },
            child: const Text('Wählen'),
          ),
          if (value != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Leeren'),
            ),
        ],
      ),
    );
  }
}

String formatLeaseDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

/// DEC-011: an amount is never rendered without its currency. Lease amounts
/// always carry one server-side, but the formatter is shared with nullable
/// fields, so the honest fallback stays.
String formatLeaseMoney(double? amount, String? currency) {
  if (amount == null) {
    return '—';
  }
  if (currency == null || currency.isEmpty) {
    return '${amount.toStringAsFixed(2)} (Währung nicht hinterlegt)';
  }
  return '${amount.toStringAsFixed(2)} $currency';
}
