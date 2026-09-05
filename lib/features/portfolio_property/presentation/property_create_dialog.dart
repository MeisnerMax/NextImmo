import 'package:flutter/material.dart';

import '../../../ui/components/nx_notice.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/utils/number_parse.dart';
import '../domain/property_dto.dart';

/// Result of the create dialog: the draft plus the reason the actor gave.
class PropertyCreateRequest {
  const PropertyCreateRequest({required this.draft, this.reason});

  final PropertyCreateDto draft;
  final String? reason;
}

/// Persists the draft. Returns the server-named field of a rejected value
/// (`name`, `zip`, `country`, …), an empty string for a form-level failure, or
/// null once the property exists. Keeping the dialog open on failure is what
/// preserves the user input.
typedef PropertyCreateSubmit =
    Future<String?> Function(PropertyCreateRequest request);

/// `Objekt anlegen` (PROPERTY-CREATE-01 on the PROPERTY-DATA-02 contract).
///
/// Deliberately the smallest honest form: exactly the fields `create_property`
/// accepts. `status` is absent — a new property is always a draft, and
/// promoting it is an explicit, audited edit in the master-data form. The
/// legacy twelve-step wizard collected far more, but most of it had no cloud
/// contract; inventing those inputs here would only produce data the server
/// discards.
class PropertyCreateDialog extends StatefulWidget {
  const PropertyCreateDialog({super.key, required this.onSubmit});

  final PropertyCreateSubmit onSubmit;

  static Future<void> show(
    BuildContext context, {
    required PropertyCreateSubmit onSubmit,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => PropertyCreateDialog(onSubmit: onSubmit),
    );
  }

  @override
  State<PropertyCreateDialog> createState() => _PropertyCreateDialogState();
}

class _PropertyCreateDialogState extends State<PropertyCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'de');
  final _propertyType = TextEditingController(text: 'residential');
  final _units = TextEditingController(text: '0');
  final _sqft = TextEditingController();
  final _yearBuilt = TextEditingController();
  final _notes = TextEditingController();
  final _reason = TextEditingController();

  bool _submitting = false;
  String? _formError;
  String? _serverField;

  static final RegExp _normalizedCode = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _addressLine1,
      _addressLine2,
      _zip,
      _city,
      _country,
      _propertyType,
      _units,
      _sqft,
      _yearBuilt,
      _notes,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _formError = null;
      _serverField = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _submitting = true);
    final sqft = _sqft.text.trim();
    final yearBuilt = _yearBuilt.text.trim();
    final request = PropertyCreateRequest(
      draft: PropertyCreateDto(
        name: _name.text.trim(),
        addressLine1: _addressLine1.text.trim(),
        addressLine2: _trimOrNull(_addressLine2.text),
        zip: _zip.text.trim(),
        city: _city.text.trim(),
        // Normalized client-side so the value the user sees matches the value
        // the server stores.
        country: _country.text.trim().toLowerCase(),
        propertyType: _propertyType.text.trim().toLowerCase(),
        units: NumberParse.parseIntFlexible(_units.text) ?? 0,
        sqft: sqft.isEmpty ? null : NumberParse.parseDoubleFlexible(sqft),
        yearBuilt:
            yearBuilt.isEmpty ? null : NumberParse.parseIntFlexible(yearBuilt),
        notes: _trimOrNull(_notes.text),
      ),
      reason: _trimOrNull(_reason.text),
    );

    final failure = await widget.onSubmit(request);
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _serverField = failure.isEmpty ? null : failure;
      _formError =
          failure.isEmpty
              ? 'Das Objekt konnte nicht angelegt werden.'
              : 'Der Server hat einen Wert abgelehnt. Bitte das markierte Feld '
                  'prüfen.';
    });
    // Re-run the validators so the server-rejected field shows its message.
    _formKey.currentState?.validate();
  }

  String? _serverMessageFor(String field) =>
      _serverField == field ? 'Vom Server abgelehnt.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('property-create-dialog'),
      title: const Text('Objekt anlegen'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_formError != null) ...[
                  NxNotice(
                    key: const Key('property-create-error'),
                    kind: NxNoticeKind.error,
                    message: _formError!,
                  ),
                  const SizedBox(height: AppSpacing.component),
                ],
                const Text(
                  'Das Objekt wird als Entwurf angelegt. Es wird erst aktiv, '
                  'wenn du den Status in den Stammdaten änderst.',
                ),
                const SizedBox(height: AppSpacing.component),
                _field(
                  controller: _name,
                  label: 'Name',
                  fieldKey: 'name',
                  widgetKey: const Key('property-create-name'),
                  autofocus: true,
                  validator: _required,
                ),
                _field(
                  controller: _addressLine1,
                  label: 'Adresszeile 1',
                  fieldKey: 'address_line1',
                  widgetKey: const Key('property-create-address-line1'),
                  validator: _required,
                ),
                _field(
                  controller: _addressLine2,
                  label: 'Adresszeile 2 (optional)',
                  fieldKey: 'address_line2',
                  widgetKey: const Key('property-create-address-line2'),
                ),
                _field(
                  controller: _zip,
                  label: 'PLZ',
                  fieldKey: 'zip',
                  widgetKey: const Key('property-create-zip'),
                  validator: _required,
                ),
                _field(
                  controller: _city,
                  label: 'Ort',
                  fieldKey: 'city',
                  widgetKey: const Key('property-create-city'),
                  validator: _required,
                ),
                _field(
                  controller: _country,
                  label: 'Land (Code, z. B. de)',
                  fieldKey: 'country',
                  widgetKey: const Key('property-create-country'),
                  validator: _validateCode,
                ),
                _field(
                  controller: _propertyType,
                  label: 'Objekttyp (Code, z. B. residential)',
                  fieldKey: 'property_type',
                  widgetKey: const Key('property-create-property-type'),
                  validator: _validateCode,
                ),
                _field(
                  controller: _units,
                  label: 'Einheiten',
                  fieldKey: 'units',
                  widgetKey: const Key('property-create-units'),
                  keyboardType: TextInputType.number,
                  validator: _validateUnits,
                ),
                _field(
                  controller: _sqft,
                  label: 'Fläche in ft² (optional)',
                  fieldKey: 'sqft',
                  widgetKey: const Key('property-create-sqft'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validateSqft,
                ),
                _field(
                  controller: _yearBuilt,
                  label: 'Baujahr (optional)',
                  fieldKey: 'year_built',
                  widgetKey: const Key('property-create-year-built'),
                  keyboardType: TextInputType.number,
                  validator: _validateYearBuilt,
                ),
                _field(
                  controller: _notes,
                  label: 'Interne Hinweise (optional)',
                  fieldKey: 'notes',
                  widgetKey: const Key('property-create-notes'),
                  maxLines: 3,
                ),
                _field(
                  controller: _reason,
                  label: 'Grund für das Audit (optional)',
                  fieldKey: 'reason',
                  widgetKey: const Key('property-create-reason'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('property-create-cancel'),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          key: const Key('property-create-submit'),
          onPressed: _submitting ? null : _submit,
          icon:
              _submitting
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.add),
          label: const Text('Anlegen'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String fieldKey,
    required Key widgetKey,
    bool autofocus = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: TextFormField(
        key: widgetKey,
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final server = _serverMessageFor(fieldKey);
          if (server != null) {
            return server;
          }
          return validator?.call(value);
        },
      ),
    );
  }

  // Validation mirrors the server contract; nothing stricter is invented here.

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;

  static String? _validateCode(String? value) {
    final trimmed = value?.trim().toLowerCase() ?? '';
    if (trimmed.isEmpty) {
      return 'Pflichtfeld';
    }
    if (trimmed.length > 100 || !_normalizedCode.hasMatch(trimmed)) {
      return 'Nur Kleinbuchstaben, Ziffern und . _ - erlaubt.';
    }
    return null;
  }

  static String? _validateUnits(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Pflichtfeld';
    }
    final units = NumberParse.parseIntFlexible(value);
    if (units == null || units < 0) {
      return 'Ganze Zahl ab 0 erforderlich.';
    }
    return null;
  }

  static String? _validateSqft(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final sqft = NumberParse.parseDoubleFlexible(value);
    if (sqft == null || sqft.isNaN || sqft.isInfinite) {
      return 'Zahl erforderlich (z. B. 1250,5).';
    }
    if (sqft <= 0) {
      return 'Fläche muss größer als 0 sein.';
    }
    return null;
  }

  static String? _validateYearBuilt(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final year = NumberParse.parseIntFlexible(value);
    if (year == null || year < 1000 || year > 2100) {
      return 'Ganze Jahreszahl zwischen 1000 und 2100.';
    }
    return null;
  }
}
