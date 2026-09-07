/// Creating or changing a cost pool (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// **The form changes shape with the scope, rather than validating after the
/// fact.** A portfolio pool has no property field at all; a building, an
/// entrance or a Zählergruppe has a label field and no other identity, because
/// this schema holds no entity for any of the three. The server refuses both
/// mismatches, and a form that let the reader assemble a refusal would be
/// teaching them a rule by rejecting them.
///
/// **The pool key is not the name.** The key is what a later settlement line
/// cites and is constrained to a machine-safe shape; the name is what a human
/// reads and is free. Keeping them apart is what stops a renamed pool from
/// orphaning the lines that quoted it.
///
/// The form owns its controllers: a dialog's exit animation keeps building the
/// subtree after the pop.
library;

import 'package:flutter/material.dart';

import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../theme/app_theme.dart';

class CostPoolFormResult {
  const CostPoolFormResult({
    required this.poolKey,
    required this.name,
    required this.scope,
    required this.isActive,
    this.propertyId,
    this.scopeLabel,
    this.note,
  });

  final String poolKey;
  final String name;
  final CostPoolScope scope;
  final String? propertyId;
  final String? scopeLabel;
  final String? note;
  final bool isActive;
}

/// Resolves a property id to something a reader recognises, and offers a way
/// to pick another. Supplied by the screen, because choosing a property is the
/// property feature's job and this dialog only needs the answer.
typedef PropertyPicker = Future<String?> Function(BuildContext context);

Future<CostPoolFormResult?> showCostPoolDialog(
  BuildContext context, {
  CostPoolDto? pool,
  required PropertyPicker pickProperty,
  required String Function(String propertyId) propertyLabel,
}) {
  return showDialog<CostPoolFormResult>(
    context: context,
    builder: (BuildContext dialogContext) => _CostPoolDialog(
      pool: pool,
      pickProperty: pickProperty,
      propertyLabel: propertyLabel,
    ),
  );
}

class _CostPoolDialog extends StatefulWidget {
  const _CostPoolDialog({
    required this.pool,
    required this.pickProperty,
    required this.propertyLabel,
  });

  final CostPoolDto? pool;
  final PropertyPicker pickProperty;
  final String Function(String propertyId) propertyLabel;

  @override
  State<_CostPoolDialog> createState() => _CostPoolDialogState();
}

class _CostPoolDialogState extends State<_CostPoolDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _label;
  late final TextEditingController _note;
  late CostPoolScope _scope;
  late bool _active;
  String? _propertyId;

  @override
  void initState() {
    super.initState();
    final CostPoolDto? pool = widget.pool;
    _key = TextEditingController(text: pool?.poolKey ?? '');
    _name = TextEditingController(text: pool?.name ?? '');
    _label = TextEditingController(text: pool?.scopeLabel ?? '');
    _note = TextEditingController(text: pool?.note ?? '');
    // A scope this build does not recognise is not carried into the form: the
    // command layer refuses to write it back, so offering it would build a
    // submission that cannot succeed.
    _scope = pool == null || pool.scope == CostPoolScope.unknown
        ? CostPoolScope.property
        : pool.scope;
    _active = pool?.isActive ?? true;
    _propertyId = pool?.propertyId;
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool needsProperty = costPoolScopeNeedsProperty(_scope);
    final bool needsLabel = costPoolScopeNeedsLabel(_scope);

    return AlertDialog(
      key: const Key('cost-pool-dialog'),
      title: Text(widget.pool == null ? 'Kostenpool anlegen' : 'Kostenpool ändern'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  key: const Key('cost-pool-key'),
                  controller: _key,
                  decoration: const InputDecoration(
                    labelText: 'Schlüssel',
                    helperText:
                        'Kleinbuchstaben, Ziffern, Punkt, Bindestrich oder '
                        'Unterstrich. Wird von Abrechnungszeilen zitiert.',
                  ),
                  validator: (String? value) {
                    final String text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Ein Schlüssel ist erforderlich.';
                    }
                    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,49}$').hasMatch(text)) {
                      return 'Nur Kleinbuchstaben, Ziffern, . _ - (max. 50).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('cost-pool-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  validator: (String? value) =>
                      (value ?? '').trim().isEmpty
                          ? 'Eine Bezeichnung ist erforderlich.'
                          : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<CostPoolScope>(
                  key: const Key('cost-pool-scope'),
                  value: _scope,
                  decoration: const InputDecoration(
                    labelText: 'Geltungsbereich',
                  ),
                  items: const <DropdownMenuItem<CostPoolScope>>[
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.portfolio,
                      child: Text('Gesamtes Portfolio'),
                    ),
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.property,
                      child: Text('Objekt'),
                    ),
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.unit,
                      child: Text('Einheit'),
                    ),
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.building,
                      child: Text('Gebäude (ohne eigene Entität)'),
                    ),
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.entrance,
                      child: Text('Aufgang (ohne eigene Entität)'),
                    ),
                    DropdownMenuItem<CostPoolScope>(
                      value: CostPoolScope.meterGroup,
                      child: Text('Zählergruppe (ohne eigene Entität)'),
                    ),
                  ],
                  onChanged: (CostPoolScope? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _scope = value;
                      // Cleared rather than kept hidden. A portfolio pool with
                      // a stashed property id would be refused by the server
                      // for a reason nothing on screen shows.
                      if (!costPoolScopeNeedsProperty(value)) {
                        _propertyId = null;
                      }
                      if (!costPoolScopeNeedsLabel(value)) {
                        _label.clear();
                      }
                    });
                  },
                ),
                if (needsLabel) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('cost-pool-label'),
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung des Bereichs',
                      helperText:
                          'Für Gebäude, Aufgang und Zählergruppe gibt es in '
                          'diesem Modell keine eigene Entität. Diese Angabe '
                          'ist die einzige Identität des Bereichs.',
                    ),
                    validator: (String? value) =>
                        (value ?? '').trim().isEmpty
                            ? 'Ohne Bezeichnung hat dieser Bereich keine '
                                  'Identität.'
                            : null,
                  ),
                ],
                if (needsProperty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Objekt',
                      errorText: _propertyId == null
                          ? 'Dieser Geltungsbereich braucht ein Objekt.'
                          : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _propertyId == null
                                ? 'Kein Objekt gewählt'
                                : widget.propertyLabel(_propertyId!),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          key: const Key('cost-pool-pick-property'),
                          onPressed: _pickProperty,
                          child: const Text('Wählen'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('cost-pool-note'),
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
                const SizedBox(height: AppSpacing.xs),
                SwitchListTile(
                  key: const Key('cost-pool-active'),
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (bool value) => setState(() => _active = value),
                  title: const Text('Aktiv'),
                  subtitle: const Text(
                    'Ein inaktiver Pool bleibt erhalten und wird nicht mehr '
                    'angeboten.',
                  ),
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
          key: const Key('cost-pool-submit'),
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _pickProperty() async {
    final String? chosen = await widget.pickProperty(context);
    if (chosen == null || !mounted) {
      return;
    }
    setState(() => _propertyId = chosen);
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (costPoolScopeNeedsProperty(_scope) && _propertyId == null) {
      // The property field lives in an InputDecorator rather than a
      // FormField, so its error is not part of validate(). Re-rendering is
      // what surfaces it.
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      CostPoolFormResult(
        poolKey: _key.text.trim(),
        name: _name.text.trim(),
        scope: _scope,
        propertyId: _propertyId,
        scopeLabel: costPoolScopeNeedsLabel(_scope)
            ? _label.text.trim()
            : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        isActive: _active,
      ),
    );
  }
}
