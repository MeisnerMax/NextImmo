/// Editing a contractor's register entry (`SUPPLIER-DETAILS-01`, P-3).
///
/// Until this package the only way to change a trade, a rate, a rating or an
/// insurance date was to re-assign the contractor role, which wrote
/// `party.role.assign` into the audit trail — a statement about who this
/// company is to the workspace rather than about a typo in a number. The panel
/// said so instead of offering a control that would have written the wrong
/// history. This is that control, now that the command behind it exists.
///
/// **It returns a patch, not a record.** Only fields the reader actually
/// changed are in the result, and a field they emptied is present with a null.
/// The distinction is the whole contract: "no agreed rate any more" and "leave
/// the rate alone" are different intents, and a form that sent every field on
/// every save would silently overwrite a colleague's concurrent edit to a field
/// this reader never looked at.
///
/// The form owns its controllers, which is why it is a StatefulWidget rather
/// than a builder function: a dialog's exit animation keeps building the
/// subtree after the pop, and controllers freed by the caller are read after
/// disposal.
library;

import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/application/party_repository.dart';
import '../../../../features/contacts_parties/domain/party_dto.dart';

/// Opens the editor. Returns the patch, or null when the reader cancelled or
/// changed nothing.
Future<Map<String, Object?>?> showContractorDetailsDialog(
  BuildContext context, {
  required ContractorDetailsDto details,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _ContractorDetailsDialog(details: details),
  );
}

/// Parses a decimal the way a German keyboard produces one. Returns null for
/// an empty field, which the caller reads as "cleared".
double? parseContractorNumber(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed.replaceAll(',', '.'));
}

/// The date the register stores, as the field shows it. `yyyy-MM-dd` because
/// that is what the server takes, and a locale-formatted string here would
/// need a second parser to get back.
String formatContractorDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _ContractorDetailsDialog extends StatefulWidget {
  const _ContractorDetailsDialog({required this.details});

  final ContractorDetailsDto details;

  @override
  State<_ContractorDetailsDialog> createState() =>
      _ContractorDetailsDialogState();
}

class _ContractorDetailsDialogState extends State<_ContractorDetailsDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _trade;
  late final TextEditingController _rate;
  late final TextEditingController _area;
  late final TextEditingController _insurance;
  late final Map<String, TextEditingController> _ratings;
  late bool _isActive;

  /// The five, in the order the register lists them.
  static const List<({String key, String label})> _ratingFields =
      <({String key, String label})>[
        (key: 'rating_price', label: 'Preis'),
        (key: 'rating_quality', label: 'Qualität'),
        (key: 'rating_speed', label: 'Tempo'),
        (key: 'rating_communication', label: 'Kommunikation'),
        (key: 'rating_punctuality', label: 'Pünktlichkeit'),
      ];

  @override
  void initState() {
    super.initState();
    final ContractorDetailsDto d = widget.details;
    _trade = TextEditingController(text: d.tradeCategory);
    _rate = TextEditingController(text: _number(d.hourlyRate));
    _area = TextEditingController(text: d.serviceArea ?? '');
    _insurance = TextEditingController(
      text: formatContractorDate(d.insuranceCertExpiry),
    );
    _ratings = <String, TextEditingController>{
      'rating_price': TextEditingController(text: _number(d.ratingPrice)),
      'rating_quality': TextEditingController(text: _number(d.ratingQuality)),
      'rating_speed': TextEditingController(text: _number(d.ratingSpeed)),
      'rating_communication': TextEditingController(
        text: _number(d.ratingCommunication),
      ),
      'rating_punctuality': TextEditingController(
        text: _number(d.ratingPunctuality),
      ),
    };
    _isActive = d.isActive;
  }

  static String _number(double? value) {
    if (value == null) {
      return '';
    }
    // Trailing zeros dropped so a rate of 85 does not come back as "85.0" and
    // read as an edit the reader did not make.
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _trade.dispose();
    _rate.dispose();
    _area.dispose();
    _insurance.dispose();
    for (final TextEditingController controller in _ratings.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('contractor-details-dialog'),
      title: const Text('Handwerkerdaten bearbeiten'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  key: const Key('contractor-details-trade'),
                  controller: _trade,
                  decoration: const InputDecoration(labelText: 'Gewerk'),
                  // The one field that cannot be emptied. The column is NOT
                  // NULL, and an empty trade would leave a row that is a
                  // contractor record in name only.
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld'
                      : null,
                ),
                TextFormField(
                  key: const Key('contractor-details-rate'),
                  controller: _rate,
                  decoration: const InputDecoration(
                    labelText: 'Stundensatz',
                    helperText: 'Leer lassen heißt: kein vereinbarter Satz.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _numberValidator(min: 0),
                ),
                TextFormField(
                  key: const Key('contractor-details-area'),
                  controller: _area,
                  decoration: const InputDecoration(labelText: 'Einsatzgebiet'),
                ),
                TextFormField(
                  key: const Key('contractor-details-insurance'),
                  controller: _insurance,
                  decoration: const InputDecoration(
                    labelText: 'Versicherung gültig bis (JJJJ-MM-TT)',
                    // A past date is accepted deliberately: an expired
                    // certificate is a fact worth recording, and refusing it
                    // would leave the register showing the old valid one.
                    helperText: 'Ein bereits abgelaufenes Datum ist zulässig.',
                  ),
                  validator: (String? value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return null;
                    }
                    return DateTime.tryParse(trimmed) == null
                        ? 'Datum im Format JJJJ-MM-TT'
                        : null;
                  },
                ),
                for (final ({String key, String label}) field in _ratingFields)
                  TextFormField(
                    key: Key('contractor-details-${field.key}'),
                    controller: _ratings[field.key],
                    decoration: InputDecoration(
                      labelText: '${field.label} (0–5)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: _numberValidator(min: 0, max: 5),
                  ),
                SwitchListTile(
                  key: const Key('contractor-details-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktiv'),
                  subtitle: const Text(
                    'Inaktive Handwerker bleiben im Verzeichnis.',
                  ),
                  value: _isActive,
                  onChanged: (bool value) => setState(() => _isActive = value),
                ),
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
          key: const Key('contractor-details-save'),
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  String? Function(String?) _numberValidator({double? min, double? max}) {
    return (String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = parseContractorNumber(trimmed);
      if (parsed == null) {
        return 'Zahl erwartet';
      }
      if (min != null && parsed < min) {
        return 'Mindestens $min';
      }
      if (max != null && parsed > max) {
        return 'Höchstens $max';
      }
      return null;
    };
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final ContractorDetailsDto d = widget.details;
    final changes = <String, Object?>{};

    // Each field is compared against what it held. Unchanged fields are absent
    // from the patch, so a save cannot overwrite a colleague's concurrent edit
    // to a field this reader never touched.
    void putIfChanged(String key, Object? current, Object? next) {
      if (current != next) {
        changes[key] = next;
      }
    }

    putIfChanged('trade_category', d.tradeCategory, _trade.text.trim());
    putIfChanged('hourly_rate', d.hourlyRate, parseContractorNumber(_rate.text));
    putIfChanged(
      'service_area',
      d.serviceArea,
      _area.text.trim().isEmpty ? null : _area.text.trim(),
    );
    putIfChanged(
      'insurance_cert_expiry',
      formatContractorDate(d.insuranceCertExpiry),
      _insurance.text.trim(),
    );
    // The comparison above is on the formatted strings, so the value that goes
    // out has to be re-derived: an empty field is a clear, not an empty string.
    if (changes.containsKey('insurance_cert_expiry')) {
      changes['insurance_cert_expiry'] = _insurance.text.trim().isEmpty
          ? null
          : _insurance.text.trim();
    }

    final ratingValues = <String, double?>{
      'rating_price': d.ratingPrice,
      'rating_quality': d.ratingQuality,
      'rating_speed': d.ratingSpeed,
      'rating_communication': d.ratingCommunication,
      'rating_punctuality': d.ratingPunctuality,
    };
    for (final MapEntry<String, double?> entry in ratingValues.entries) {
      putIfChanged(
        entry.key,
        entry.value,
        parseContractorNumber(_ratings[entry.key]!.text),
      );
    }

    putIfChanged('is_active', d.isActive, _isActive);

    // An unchanged form closes without a command. The server would refuse an
    // empty change set, and spending a round trip on a certain refusal is the
    // thing the pre-checks around this screen already avoid.
    Navigator.of(context).pop(changes.isEmpty ? null : changes);
  }
}

/// Named so the call site reads as what it is. The keys are the server's, and
/// [contractorDetailChanges] is the other way to build the same map when the
/// caller knows the fields at compile time.
typedef ContractorDetailsPatch = Map<String, Object?>;
