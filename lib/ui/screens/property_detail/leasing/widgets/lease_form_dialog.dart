/// The shared lease form (Welle 3, AP3) — one dialog for creating and for
/// editing, because the two differ in exactly three places and building them
/// twice is how the legacy screen grew to 1211 lines.
///
/// The three differences are contract facts, not styling:
///
///   * **The unit is chosen once.** `LeaseUpdateDto` has no `unitId`; moving a
///     lease to another unit would silently rewrite two units' occupancy, so
///     the server does not allow it and the form shows the unit as a fact when
///     editing.
///   * **The currency is chosen once.** `LeaseUpdateDto` has no `currencyCode`
///     either — a lease keeps the currency it was written in (DEC-011).
///   * **Editing is only offered while the lease is not binding.** The caller
///     gates that; this dialog is never opened for a signed lease.
///
/// Deliberately absent: a status field. Status moves through STM-005
/// transitions, and a lease always starts as a draft.
library;

import 'package:flutter/material.dart';

import '../../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../../../features/leasing_operations/domain/lease_dto.dart';
import '../../../../../features/leasing_operations/domain/unit_dto.dart';
import '../../../../components/responsive_constraints.dart';
import 'lease_lifecycle.dart';

/// The union of what a lease draft and a lease update carry. The caller maps it
/// to the shape its command needs — the form does not know about commands.
class LeaseFormResult {
  const LeaseFormResult({
    required this.unitId,
    required this.leaseName,
    required this.startDate,
    required this.baseRentMonthly,
    required this.currencyCode,
    required this.billingFrequency,
    this.tenantPartyId,
    this.endDate,
    this.moveInDate,
    this.signedDate,
    this.noticeDate,
    this.renewalOptionDate,
    this.breakOptionDate,
    this.ancillaryChargesMonthly,
    this.parkingOtherChargesMonthly,
    this.securityDeposit,
    this.paymentDayOfMonth,
    this.rentFreePeriodMonths,
    this.notes,
  });

  final String unitId;
  final String leaseName;
  final DateTime startDate;
  final double baseRentMonthly;
  final String currencyCode;
  final LeaseBillingFrequency billingFrequency;
  final String? tenantPartyId;
  final DateTime? endDate;
  final DateTime? moveInDate;
  final DateTime? signedDate;
  final DateTime? noticeDate;
  final DateTime? renewalOptionDate;
  final DateTime? breakOptionDate;
  final double? ancillaryChargesMonthly;
  final double? parkingOtherChargesMonthly;
  final double? securityDeposit;
  final int? paymentDayOfMonth;
  final int? rentFreePeriodMonths;
  final String? notes;
}

String leaseBillingFrequencyLabel(LeaseBillingFrequency value) =>
    switch (value) {
      LeaseBillingFrequency.monthly => 'Monatlich',
      LeaseBillingFrequency.quarterly => 'Quartalsweise',
      LeaseBillingFrequency.semiannual => 'Halbjährlich',
      LeaseBillingFrequency.annual => 'Jährlich',
    };

/// Opens the lease form. [existing] switches it to edit mode; [units] must be
/// non-empty for creation, which the caller checks so the empty case can be
/// explained rather than shown as a dead dropdown.
Future<LeaseFormResult?> showLeaseFormDialog(
  BuildContext context, {
  required List<UnitSummaryDto> units,
  required List<PartySummaryDto> tenants,
  LeaseDto? existing,
  String? initialUnitId,
}) async {
  final nameController = TextEditingController(text: existing?.leaseName ?? '');
  final rentController = TextEditingController(
    text: existing?.baseRentMonthly.toStringAsFixed(2) ?? '',
  );
  final currencyController = TextEditingController(
    text: existing?.currencyCode ?? 'EUR',
  );
  final ancillaryController = TextEditingController(
    text: existing?.ancillaryChargesMonthly?.toString() ?? '',
  );
  final parkingController = TextEditingController(
    text: existing?.parkingOtherChargesMonthly?.toString() ?? '',
  );
  final depositController = TextEditingController(
    text: existing?.securityDeposit?.toString() ?? '',
  );
  final paymentDayController = TextEditingController(
    text: existing?.paymentDayOfMonth?.toString() ?? '',
  );
  final rentFreeController = TextEditingController(
    text: existing?.rentFreePeriodMonths?.toString() ?? '',
  );
  final notesController = TextEditingController(text: existing?.notes ?? '');
  final formKey = GlobalKey<FormState>();

  String? unitId = existing?.unitId ??
      (initialUnitId != null && units.any((unit) => unit.id == initialUnitId)
          ? initialUnitId
          : units.isEmpty
              ? null
              : units.first.id);
  String? tenantPartyId = existing?.tenantPartyId;
  LeaseBillingFrequency billing =
      existing?.billingFrequency ?? LeaseBillingFrequency.monthly;
  DateTime startDate = existing?.startDate ?? _today();
  DateTime? endDate = existing?.endDate;
  DateTime? moveInDate = existing?.moveInDate;
  DateTime? signedDate = existing?.signedDate;
  DateTime? noticeDate = existing?.noticeDate;
  DateTime? renewalOptionDate = existing?.renewalOptionDate;
  DateTime? breakOptionDate = existing?.breakOptionDate;

  final unitLabel = units
          .where((unit) => unit.id == (existing?.unitId ?? unitId))
          .map((unit) => unit.unitCode)
          .firstOrNull ??
      '—';

  final result = await showDialog<LeaseFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(
          existing == null ? 'Vertrag anlegen' : 'Vertrag bearbeiten',
        ),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 560),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (existing == null)
                    DropdownButtonFormField<String>(
                      value: unitId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Einheit *'),
                      items: <DropdownMenuItem<String>>[
                        for (final unit in units)
                          DropdownMenuItem<String>(
                            value: unit.id,
                            child: Text(unit.unitCode),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => unitId = value),
                      validator: (value) =>
                          value == null ? 'Bitte eine Einheit wählen.' : null,
                    )
                  else
                    _ReadOnlyField(
                      label: 'Einheit',
                      value: unitLabel,
                      // The contract has no unitId on an update: moving a lease
                      // would rewrite two units' occupancy behind the user's
                      // back, so it is a new lease, not an edit.
                      helper: 'Die Einheit eines bestehenden Vertrags ist nicht '
                          'änderbar.',
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: tenants.any((party) => party.id == tenantPartyId)
                        ? tenantPartyId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Mieter',
                      helperText:
                          'Eine Partei mit Mieter-Rolle — es gibt keine '
                          'separate Mieterkartei.',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Noch nicht benannt'),
                      ),
                      for (final party in tenants)
                        DropdownMenuItem<String?>(
                          value: party.id,
                          child: Text(party.displayName),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => tenantPartyId = value),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Vertragsname *',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Pflichtfeld.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  LeaseDateField(
                    label: 'Beginn *',
                    value: startDate,
                    onChanged: (value) =>
                        setDialogState(() => startDate = value ?? startDate),
                  ),
                  const SizedBox(height: 8),
                  LeaseDateField(
                    label: 'Ende',
                    value: endDate,
                    onChanged: (value) => setDialogState(() => endDate = value),
                  ),
                  const SizedBox(height: 8),
                  LeaseDateField(
                    label: 'Einzug',
                    value: moveInDate,
                    onChanged: (value) =>
                        setDialogState(() => moveInDate = value),
                  ),
                  const SizedBox(height: 8),
                  LeaseDateField(
                    label: 'Unterschrieben am',
                    value: signedDate,
                    onChanged: (value) =>
                        setDialogState(() => signedDate = value),
                  ),
                  if (existing != null) ...<Widget>[
                    const SizedBox(height: 8),
                    LeaseDateField(
                      label: 'Kündigungsdatum',
                      value: noticeDate,
                      onChanged: (value) =>
                          setDialogState(() => noticeDate = value),
                    ),
                    const SizedBox(height: 8),
                    LeaseDateField(
                      label: 'Verlängerungsoption',
                      value: renewalOptionDate,
                      onChanged: (value) =>
                          setDialogState(() => renewalOptionDate = value),
                    ),
                    const SizedBox(height: 8),
                    LeaseDateField(
                      label: 'Sonderkündigungsrecht',
                      value: breakOptionDate,
                      onChanged: (value) =>
                          setDialogState(() => breakOptionDate = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: rentController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Grundmiete / Monat *',
                    ),
                    validator: (value) => _parseDouble(value ?? '') == null
                        ? 'Bitte einen Betrag angeben.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  if (existing == null)
                    TextFormField(
                      controller: currencyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Währung *',
                        helperText: 'Zu einem Betrag gehört eine Währung.',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().length != 3)
                              ? 'Drei Buchstaben, z. B. EUR.'
                              : null,
                    )
                  else
                    _ReadOnlyField(
                      label: 'Währung',
                      value: existing.currencyCode,
                      helper: 'Die Währung eines bestehenden Vertrags ist nicht '
                          'änderbar.',
                    ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: ancillaryController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Nebenkosten / Monat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: parkingController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Stellplatz / Sonstiges / Monat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: depositController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Kaution'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LeaseBillingFrequency>(
                    value: billing,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Abrechnungsrhythmus',
                    ),
                    items: <DropdownMenuItem<LeaseBillingFrequency>>[
                      for (final value in LeaseBillingFrequency.values)
                        DropdownMenuItem<LeaseBillingFrequency>(
                          value: value,
                          child: Text(leaseBillingFrequencyLabel(value)),
                        ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => billing = value ?? billing,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: paymentDayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Zahltag im Monat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: rentFreeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mietfreie Monate',
                    ),
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
              final selectedUnit = existing?.unitId ?? unitId;
              if (selectedUnit == null) {
                return;
              }
              Navigator.of(dialogContext).pop(
                LeaseFormResult(
                  unitId: selectedUnit,
                  leaseName: nameController.text.trim(),
                  startDate: startDate,
                  baseRentMonthly: _parseDouble(rentController.text) ?? 0,
                  currencyCode: existing?.currencyCode ??
                      currencyController.text.trim().toUpperCase(),
                  billingFrequency: billing,
                  tenantPartyId: tenantPartyId,
                  endDate: endDate,
                  moveInDate: moveInDate,
                  signedDate: signedDate,
                  noticeDate: noticeDate,
                  renewalOptionDate: renewalOptionDate,
                  breakOptionDate: breakOptionDate,
                  ancillaryChargesMonthly:
                      _parseDouble(ancillaryController.text),
                  parkingOtherChargesMonthly:
                      _parseDouble(parkingController.text),
                  securityDeposit: _parseDouble(depositController.text),
                  paymentDayOfMonth: _parseInt(paymentDayController.text),
                  rentFreePeriodMonths: _parseInt(rentFreeController.text),
                  notes: _trimToNull(notesController.text),
                ),
              );
            },
            child: Text(existing == null ? 'Anlegen' : 'Speichern'),
          ),
        ],
      ),
    ),
  );

  for (final controller in <TextEditingController>[
    nameController,
    rentController,
    currencyController,
    ancillaryController,
    parkingController,
    depositController,
    paymentDayController,
    rentFreeController,
    notesController,
  ]) {
    controller.dispose();
  }
  return result;
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, helperText: helper),
      child: Text(value),
    );
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day);
}

double? _parseDouble(String value) {
  final trimmed = value.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed);
}

int? _parseInt(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return int.tryParse(trimmed);
}

String? _trimToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
