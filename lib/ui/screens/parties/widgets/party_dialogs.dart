import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/contacts_parties/application/parties_controller.dart';
import '../../../../features/contacts_parties/application/party_repository.dart';
import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../components/nx_card.dart';
import '../../../theme/app_theme.dart';
import 'party_badges.dart';

/// Identity fields of the create/edit form. The caller turns this into a
/// [PartyDraft] or a [PartyUpdateDto] — the dialog itself stays free of the
/// command shapes so it can serve both.
class PartyFormResult {
  const PartyFormResult({
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

  PartyDraft toDraft() => PartyDraft(
    type: type,
    displayName: displayName,
    legalName: legalName,
    email: email,
    phone: phone,
    notes: notes,
  );

  PartyUpdateDto toUpdate() => PartyUpdateDto(
    type: type,
    displayName: displayName,
    legalName: legalName,
    email: email,
    phone: phone,
    notes: notes,
  );
}

Future<PartyFormResult?> showPartyFormDialog({
  required BuildContext context,
  PartyDto? existing,
}) {
  return showDialog<PartyFormResult>(
    context: context,
    builder: (dialogContext) => _PartyFormDialog(existing: existing),
  );
}

class _PartyFormDialog extends ConsumerStatefulWidget {
  const _PartyFormDialog({this.existing});

  final PartyDto? existing;

  @override
  ConsumerState<_PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<_PartyFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _legalName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late PartyType _type;
  Timer? _probeDebounce;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? PartyType.person;
    _displayName = TextEditingController(text: existing?.displayName ?? '');
    _legalName = TextEditingController(text: existing?.legalName ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _probeDebounce?.cancel();
    _displayName.dispose();
    _legalName.dispose();
    _email.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _scheduleDuplicateProbe() {
    _probeDebounce?.cancel();
    _probeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(partiesControllerProvider.notifier)
            .probeDuplicates(
              displayName: _displayName.text,
              email: _email.text,
              phone: _phone.text,
            ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = ref.watch(
      partiesControllerProvider.select((state) => state.duplicates),
    );
    final editing = widget.existing != null;
    final visibleDuplicates =
        duplicates
            .where((candidate) => candidate.party.id != widget.existing?.id)
            .toList(growable: false);

    return AlertDialog(
      title: Text(editing ? 'Partei bearbeiten' : 'Neue Partei'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SegmentedButton<PartyType>(
                  segments: <ButtonSegment<PartyType>>[
                    ButtonSegment<PartyType>(
                      value: PartyType.person,
                      label: Text(partyTypeLabel(PartyType.person)),
                    ),
                    ButtonSegment<PartyType>(
                      value: PartyType.organization,
                      label: Text(partyTypeLabel(PartyType.organization)),
                    ),
                  ],
                  selected: <PartyType>{_type},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      (selection) => setState(() => _type = selection.first),
                ),
                const SizedBox(height: AppSpacing.component),
                TextFormField(
                  controller: _displayName,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Anzeigename',
                  ),
                  validator:
                      (value) =>
                          (value ?? '').trim().isEmpty
                              ? 'Anzeigename ist erforderlich.'
                              : null,
                  onChanged: (_) => _scheduleDuplicateProbe(),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _legalName,
                  decoration: const InputDecoration(
                    labelText: 'Rechtsname (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail (optional)',
                  ),
                  onChanged: (_) => _scheduleDuplicateProbe(),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (optional)',
                  ),
                  onChanged: (_) => _scheduleDuplicateProbe(),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notizen (optional)',
                  ),
                ),
                if (visibleDuplicates.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  _DuplicateWarning(candidates: visibleDuplicates),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Speichern' : 'Anlegen'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      PartyFormResult(
        type: _type,
        displayName: _displayName.text.trim(),
        legalName: _trimToNull(_legalName.text),
        email: _trimToNull(_email.text),
        phone: _trimToNull(_phone.text),
        notes: _trimToNull(_notes.text),
      ),
    );
  }

  static String? _trimToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Warns, never blocks: duplicate detection is advisory, the user decides
/// whether this really is a new party.
class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.candidates});

  final List<PartyDuplicateCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_outlined, color: semantic.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mögliche Dublette',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Diese Parteien ähneln der Eingabe. Prüfe, ob eine davon gemeint '
            'ist, bevor du eine neue anlegst.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final candidate in candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${candidate.party.displayName} — '
                '${_matchSummary(candidate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static String _matchSummary(PartyDuplicateCandidate candidate) {
    final matches = <String>[
      if (candidate.matchName) 'Name',
      if (candidate.matchEmail) 'E-Mail',
      if (candidate.matchPhone) 'Telefon',
    ];
    return matches.isEmpty ? 'ähnlich' : 'Treffer: ${matches.join(', ')}';
  }
}

/// Result of the role dialog. [contractorDetails] is only ever set for the
/// contractor role — the command asserts that invariant too.
class PartyRoleFormResult {
  const PartyRoleFormResult({
    required this.roleType,
    this.validFrom,
    this.validUntil,
    this.contractorDetails,
  });

  final PartyRoleType roleType;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final ContractorDetailsInput? contractorDetails;
}

Future<PartyRoleFormResult?> showPartyRoleDialog({
  required BuildContext context,
}) {
  return showDialog<PartyRoleFormResult>(
    context: context,
    builder: (dialogContext) => const _PartyRoleDialog(),
  );
}

class _PartyRoleDialog extends StatefulWidget {
  const _PartyRoleDialog();

  @override
  State<_PartyRoleDialog> createState() => _PartyRoleDialogState();
}

class _PartyRoleDialogState extends State<_PartyRoleDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _tradeCategory = TextEditingController();
  final TextEditingController _hourlyRate = TextEditingController();
  final TextEditingController _serviceArea = TextEditingController();
  PartyRoleType _roleType = PartyRoleType.tenant;
  DateTime? _validFrom;
  DateTime? _validUntil;

  @override
  void dispose() {
    _tradeCategory.dispose();
    _hourlyRate.dispose();
    _serviceArea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isContractor = _roleType == PartyRoleType.contractor;
    return AlertDialog(
      title: const Text('Rolle zuweisen'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<PartyRoleType>(
                  value: _roleType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rolle'),
                  items: <DropdownMenuItem<PartyRoleType>>[
                    for (final role in PartyRoleType.values)
                      DropdownMenuItem<PartyRoleType>(
                        value: role,
                        child: Text(partyRoleLabel(role)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _roleType = value);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateField(
                  label: 'Gültig ab (optional)',
                  value: _validFrom,
                  onChanged: (value) => setState(() => _validFrom = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateField(
                  label: 'Gültig bis (optional)',
                  value: _validUntil,
                  onChanged: (value) => setState(() => _validUntil = value),
                ),
                if (isContractor) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  TextFormField(
                    controller: _tradeCategory,
                    decoration: const InputDecoration(labelText: 'Gewerk'),
                    validator:
                        (value) =>
                            (value ?? '').trim().isEmpty
                                ? 'Gewerk ist für Dienstleister erforderlich.'
                                : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _hourlyRate,
                    decoration: const InputDecoration(
                      labelText: 'Stundensatz (optional)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _serviceArea,
                    decoration: const InputDecoration(
                      labelText: 'Einsatzgebiet (optional)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Zuweisen')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final isContractor = _roleType == PartyRoleType.contractor;
    Navigator.of(context).pop(
      PartyRoleFormResult(
        roleType: _roleType,
        validFrom: _validFrom,
        validUntil: _validUntil,
        contractorDetails:
            isContractor
                ? ContractorDetailsInput(
                  tradeCategory: _tradeCategory.text.trim(),
                  hourlyRate: double.tryParse(
                    _hourlyRate.text.trim().replaceAll(',', '.'),
                  ),
                  serviceArea:
                      _serviceArea.text.trim().isEmpty
                          ? null
                          : _serviceArea.text.trim(),
                )
                : null,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
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
          Expanded(
            child: Text(
              value == null ? 'Nicht gesetzt' : _formatDate(value!),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: 'Datum wählen',
            icon: const Icon(Icons.event_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (picked != null) {
                onChanged(picked);
              }
            },
          ),
          if (value != null)
            IconButton(
              tooltip: 'Zurücksetzen',
              icon: const Icon(Icons.clear),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}

/// Merging is consequential and audited, so it never happens on a single click.
Future<PartySummaryDto?> showPartyMergeDialog({
  required BuildContext context,
  required PartyDto target,
  required List<PartySummaryDto> candidates,
}) {
  return showDialog<PartySummaryDto>(
    context: context,
    builder:
        (dialogContext) =>
            _PartyMergeDialog(target: target, candidates: candidates),
  );
}

class _PartyMergeDialog extends StatefulWidget {
  const _PartyMergeDialog({required this.target, required this.candidates});

  final PartyDto target;
  final List<PartySummaryDto> candidates;

  @override
  State<_PartyMergeDialog> createState() => _PartyMergeDialogState();
}

class _PartyMergeDialogState extends State<_PartyMergeDialog> {
  PartySummaryDto? _source;

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return AlertDialog(
      title: const Text('Parteien zusammenführen'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Die gewählte Partei wird in "${widget.target.displayName}" '
              'überführt. Rollen und Historie bleiben erhalten, die Quelle '
              'wird als zusammengeführt markiert. Das lässt sich nicht per '
              'Klick rückgängig machen.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<String>(
              value: source?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Quelle (wird überführt)',
              ),
              items: <DropdownMenuItem<String>>[
                for (final candidate in widget.candidates)
                  DropdownMenuItem<String>(
                    value: candidate.id,
                    child: Text(
                      candidate.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _source = widget.candidates.firstWhere(
                    (candidate) => candidate.id == value,
                  );
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed:
              source == null ? null : () => Navigator.of(context).pop(source),
          child: const Text('Zusammenführen'),
        ),
      ],
    );
  }
}

/// Explicit conflict resolution: both versions are shown and the refreshed
/// record is offered, instead of silently overwriting or silently failing.
Future<void> showPartyVersionConflictDialog({
  required BuildContext context,
  required PartyVersionConflict conflict,
  required VoidCallback onReload,
}) {
  final current = conflict.currentParty;
  final role = conflict.currentRole;
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Zwischenzeitlich geändert'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  current != null
                      ? '"${current.displayName}" wurde geändert, seit du sie '
                          'geladen hast.'
                      : role != null
                      ? 'Die Rolle "${partyRoleLabel(role.roleType)}" wurde '
                          'geändert, seit du sie geladen hast.'
                      : 'Der Datensatz wurde zwischenzeitlich geändert.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Deine Version: ${conflict.expectedVersion} · '
                  'Aktuelle Version: ${conflict.actualVersion}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Deine Änderung wurde nicht gespeichert. Lade den aktuellen '
                  'Stand und wende sie erneut an.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onReload();
              },
              child: const Text('Aktuellen Stand laden'),
            ),
          ],
        ),
  );
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
