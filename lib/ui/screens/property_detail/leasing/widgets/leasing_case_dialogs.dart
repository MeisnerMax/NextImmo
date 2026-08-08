/// The shared STM-004 dialogs (Welle 3, AP4): the case form, the one-step
/// confirmation, and the abort with its mandatory reason.
///
/// The step confirmation is where the pipeline hands over to the lease surface.
/// Reaching [LeasingCaseStatus.signed] means naming the lease the case
/// produced, so the dialog offers the leases of the case's unit — and when
/// there is none, it says where one is created instead of presenting an empty
/// dropdown. Growing a second lease-creation path here would duplicate AP3 and
/// the STM-005 rules with it.
library;

import 'package:flutter/material.dart';

import '../../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../../../features/leasing_operations/domain/leasing_case_dto.dart';
import '../../../../../features/leasing_operations/domain/unit_dto.dart';
import '../../../../components/responsive_constraints.dart';
import 'leasing_badges.dart';

/// What the case form collected. Mapped by the caller to a draft or an update —
/// the form does not know about commands.
class LeasingCaseFormResult {
  const LeasingCaseFormResult({
    required this.caseName,
    required this.source,
    this.unitId,
    this.prospectPartyId,
    this.notes,
  });

  final String caseName;
  final LeasingCaseSource source;
  final String? unitId;
  final String? prospectPartyId;
  final String? notes;
}

/// [parties] is deliberately the unfiltered party directory: a prospect holds
/// no `tenant` role yet, and there is no `prospect` role to filter by. The role
/// attaches when a lease names the party.
Future<LeasingCaseFormResult?> showLeasingCaseFormDialog(
  BuildContext context, {
  required List<UnitSummaryDto> units,
  required List<PartySummaryDto> parties,
  LeasingCaseDto? existing,
}) async {
  final nameController = TextEditingController(text: existing?.caseName ?? '');
  final notesController = TextEditingController(text: existing?.notes ?? '');
  final formKey = GlobalKey<FormState>();

  String? unitId = existing?.unitId;
  String? prospectPartyId = existing?.prospectPartyId;
  LeasingCaseSource source = existing?.source ?? LeasingCaseSource.other;

  final result = await showDialog<LeasingCaseFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'Fall anlegen' : 'Fall bearbeiten'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 480),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung *',
                      hintText: 'z. B. Anfrage Familie Meier, 3 Zimmer',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Pflichtfeld.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LeasingCaseSource>(
                    value: source,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Herkunft'),
                    items: <DropdownMenuItem<LeasingCaseSource>>[
                      for (final value in LeasingCaseSource.values)
                        DropdownMenuItem<LeasingCaseSource>(
                          value: value,
                          child: Text(leasingCaseSourceLabel(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => source = value ?? source),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: units.any((unit) => unit.id == unitId)
                        ? unitId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Einheit',
                      helperText: 'Ab dem Angebot erforderlich.',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Noch offen'),
                      ),
                      for (final unit in units)
                        DropdownMenuItem<String?>(
                          value: unit.id,
                          child: Text(unit.unitCode),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => unitId = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: parties.any((party) => party.id == prospectPartyId)
                        ? prospectPartyId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Interessent',
                      helperText:
                          'Eine Partei aus dem Verzeichnis. Die Mieter-Rolle '
                          'entsteht erst mit dem Vertrag, nicht hier.',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Noch nicht identifiziert'),
                      ),
                      for (final party in parties)
                        DropdownMenuItem<String?>(
                          value: party.id,
                          child: Text(party.displayName),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => prospectPartyId = value),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notizen'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.of(dialogContext).pop(
                LeasingCaseFormResult(
                  caseName: nameController.text.trim(),
                  source: source,
                  unitId: unitId,
                  prospectPartyId: prospectPartyId,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                ),
              );
            },
            child: Text(existing == null ? 'Anlegen' : 'Speichern'),
          ),
        ],
      ),
    ),
  );

  nameController.dispose();
  notesController.dispose();
  return result;
}

class LeasingCaseAdvanceRequest {
  const LeasingCaseAdvanceRequest({this.leaseId});

  final String? leaseId;
}

/// Confirms the one stage forward. On the step into
/// [LeasingCaseStatus.signed] it also collects the lease the case produced,
/// unless the case already names one.
Future<LeasingCaseAdvanceRequest?> showLeasingCaseAdvanceDialog(
  BuildContext context, {
  required LeasingCaseDto leasingCase,
  required List<LeaseSummaryDto> availableLeases,
}) async {
  final target = leasingCase.status.nextStage;
  if (target == null) {
    return null;
  }
  final needsLease =
      target == LeasingCaseStatus.signed && leasingCase.leaseId == null;
  String? leaseId;

  return showDialog<LeasingCaseAdvanceRequest>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Nächste Stufe'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${leasingCase.caseName}: '
                '${leasingCaseStatusLabel(leasingCase.status)} → '
                '${leasingCaseStatusLabel(target)}',
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Pipeline geht nur vorwärts. Ein Rückschritt ist nicht '
                'vorgesehen — scheitert der Fall, ist das ein Abbruch mit '
                'Grund, und ein neuer Anlauf ist ein neuer Fall.',
              ),
              if (needsLease) ...<Widget>[
                const SizedBox(height: 16),
                if (availableLeases.isEmpty)
                  const Text(
                    'Für diese Stufe muss der Vertrag benannt werden, den der '
                    'Fall erzeugt hat — für diese Einheit gibt es noch keinen. '
                    'Lege ihn im Reiter „Mietverträge" an und komm dann '
                    'hierher zurück.',
                  )
                else
                  DropdownButtonFormField<String>(
                    value: leaseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Erzeugter Vertrag *',
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final lease in availableLeases)
                        DropdownMenuItem<String>(
                          value: lease.id,
                          child: Text(
                            '${lease.leaseName} · '
                            '${leaseStatusLabel(lease.status)}',
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => leaseId = value),
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
            onPressed: needsLease && leaseId == null
                ? null
                : () => Navigator.of(dialogContext).pop(
                    LeasingCaseAdvanceRequest(leaseId: leaseId),
                  ),
            child: Text('Auf „${leasingCaseStatusLabel(target)}" setzen'),
          ),
        ],
      ),
    ),
  );
}

/// Collects the mandatory reason for aborting a case.
Future<String?> showLeasingCaseCancellationDialog(
  BuildContext context, {
  required LeasingCaseDto leasingCase,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${leasingCase.caseName} abbrechen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 420),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Ein abgebrochener Fall lässt sich nicht wieder öffnen — die '
                'erreichte Stufe bleibt als Tatsache im Änderungsprotokoll. '
                'Ein neuer Anlauf ist ein neuer Fall.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Grund',
                  hintText: 'z. B. Bonität nicht ausreichend',
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
          child: const Text('Fall abbrechen'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
