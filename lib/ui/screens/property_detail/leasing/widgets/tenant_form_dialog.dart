/// The tenant form and the end-of-role confirmation (Welle 3, AP5).
///
/// The form collects **party** attributes, because that is what a tenant is.
/// There is deliberately no status field: the legacy tenant record carried
/// `active`/`prospect`/`inactive`, of which `prospect` now belongs to the
/// pipeline (AP4) and the other two are answered by whether the party holds an
/// open `tenant` role. A second status here would be a third opinion about the
/// same fact.
library;

import 'package:flutter/material.dart';

import '../../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../../components/responsive_constraints.dart';
import '../../../parties/widgets/party_badges.dart';
import 'lease_lifecycle.dart';

class TenantFormResult {
  const TenantFormResult({
    required this.type,
    required this.displayName,
    this.legalName,
    this.email,
    this.phone,
    this.notes,
  });

  final PartyType type;
  final String displayName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? notes;
}

Future<TenantFormResult?> showTenantFormDialog(
  BuildContext context, {
  PartyDto? existing,
}) async {
  final nameController = TextEditingController(
    text: existing?.displayName ?? '',
  );
  final legalNameController = TextEditingController(
    text: existing?.legalName ?? '',
  );
  final emailController = TextEditingController(text: existing?.email ?? '');
  final phoneController = TextEditingController(text: existing?.phone ?? '');
  final notesController = TextEditingController(text: existing?.notes ?? '');
  final formKey = GlobalKey<FormState>();
  PartyType type = existing?.type ?? PartyType.person;

  final result = await showDialog<TenantFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'Mieter anlegen' : 'Mieter bearbeiten'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 460),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (existing == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Angelegt wird eine Partei mit Mieter-Rolle — kein '
                        'separater Mieterstammsatz.',
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ),
                  DropdownButtonFormField<PartyType>(
                    value: type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Typ'),
                    items: <DropdownMenuItem<PartyType>>[
                      for (final value in PartyType.values)
                        DropdownMenuItem<PartyType>(
                          value: value,
                          child: Text(partyTypeLabel(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Anzeigename *',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Pflichtfeld.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: legalNameController,
                    decoration: const InputDecoration(
                      labelText: 'Rechtlicher Name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefon'),
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
                TenantFormResult(
                  type: type,
                  displayName: nameController.text.trim(),
                  legalName: _trimToNull(legalNameController.text),
                  email: _trimToNull(emailController.text),
                  phone: _trimToNull(phoneController.text),
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
    legalNameController,
    emailController,
    phoneController,
    notesController,
  ]) {
    controller.dispose();
  }
  return result;
}

class EndTenantRoleResult {
  const EndTenantRoleResult({this.validUntil});

  final DateTime? validUntil;
}

/// Confirms ending the tenant role. It says what ending does and, when the
/// party still holds effective leases, that those are **not** touched — the
/// role and the lease are separate facts, and ending one does not terminate the
/// other.
Future<EndTenantRoleResult?> showEndTenantRoleDialog(
  BuildContext context, {
  required String displayName,
  required int openLeaseCount,
}) async {
  DateTime? validUntil;
  return showDialog<EndTenantRoleResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Mieter-Rolle von $displayName beenden'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(dialogContext, maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Die Partei bleibt im Verzeichnis und behält ihre übrigen '
                'Rollen — sie verschwindet nur aus der Mieterliste. Gelöscht '
                'wird nichts.',
              ),
              if (openLeaseCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  openLeaseCount == 1
                      ? 'Achtung: auf diese Partei läuft noch 1 wirksamer '
                            'Vertrag. Das Beenden der Rolle beendet ihn nicht '
                            '— ein Vertrag wird über seinen eigenen '
                            'Lebenszyklus beendet.'
                      : 'Achtung: auf diese Partei laufen noch '
                            '$openLeaseCount wirksame Verträge. Das Beenden '
                            'der Rolle beendet sie nicht — ein Vertrag wird '
                            'über seinen eigenen Lebenszyklus beendet.',
                ),
              ],
              const SizedBox(height: 16),
              LeaseDateField(
                label: 'Gültig bis (optional)',
                value: validUntil,
                onChanged: (value) => setDialogState(() => validUntil = value),
              ),
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
              EndTenantRoleResult(validUntil: validUntil),
            ),
            child: const Text('Rolle beenden'),
          ),
        ],
      ),
    ),
  );
}

String? _trimToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
