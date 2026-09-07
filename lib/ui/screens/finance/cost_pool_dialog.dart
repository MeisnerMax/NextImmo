/// Creating or changing a cost pool (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// **The form changes shape with the scope, rather than validating after the
/// fact.** A portfolio pool has no property field at all; a unit pool names
/// its unit; a building, an entrance or a Zählergruppe has a label field and
/// no other identity, because this schema holds no entity for any of the
/// three. The server refuses every mismatch, and a form that let the reader
/// assemble a refusal would be teaching them a rule by rejecting them.
///
/// **The dialog owns the submit.** It stays open while the command runs and
/// while it is refused, keeps everything the user typed, and puts the server's
/// message on the field the server named. A dialog that pops first and reports
/// afterwards has already thrown the input away — which is the whole reason a
/// rejected field is worth carrying at all.
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

import '../../../features/finance_ledger/application/cost_pool_controller.dart';
import '../../../features/finance_ledger/domain/cost_pool_dto.dart';
import '../../components/nx_notice.dart';
import '../../theme/app_theme.dart';

class CostPoolFormResult {
  const CostPoolFormResult({
    required this.poolKey,
    required this.name,
    required this.scope,
    required this.isActive,
    this.propertyId,
    this.unitId,
    this.scopeLabel,
    this.note,
  });

  final String poolKey;
  final String name;
  final CostPoolScope scope;
  final String? propertyId;
  final String? unitId;
  final String? scopeLabel;
  final String? note;
  final bool isActive;
}

/// One unit a pool could name, as little of it as the form needs.
class CostPoolUnitOption {
  const CostPoolUnitOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Chooses a property. Supplied by the screen, because choosing a property is
/// the property feature's job and this dialog only needs the answer.
typedef PropertyPicker = Future<String?> Function(BuildContext context);

/// The units of one property, in the order the leasing contract returns them.
typedef UnitLoader = Future<List<CostPoolUnitOption>> Function(String propertyId);

/// Runs the command. Returns null on success, or why it was refused.
typedef CostPoolSubmit =
    Future<CostPoolActionFailure?> Function(CostPoolFormResult result);

Future<bool?> showCostPoolDialog(
  BuildContext context, {
  CostPoolDto? pool,
  required PropertyPicker pickProperty,
  required UnitLoader loadUnits,
  required String Function(String propertyId) propertyLabel,
  required CostPoolSubmit onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    // The command runs from inside, so a stray tap must not abandon a write
    // that is already in flight.
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _CostPoolDialog(
      pool: pool,
      pickProperty: pickProperty,
      loadUnits: loadUnits,
      propertyLabel: propertyLabel,
      onSubmit: onSubmit,
    ),
  );
}

class _CostPoolDialog extends StatefulWidget {
  const _CostPoolDialog({
    required this.pool,
    required this.pickProperty,
    required this.loadUnits,
    required this.propertyLabel,
    required this.onSubmit,
  });

  final CostPoolDto? pool;
  final PropertyPicker pickProperty;
  final UnitLoader loadUnits;
  final String Function(String propertyId) propertyLabel;
  final CostPoolSubmit onSubmit;

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
  String? _unitId;

  List<CostPoolUnitOption> _units = const <CostPoolUnitOption>[];
  bool _loadingUnits = false;
  bool _submitting = false;
  String? _failureMessage;
  String? _failureField;

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
    _unitId = pool?.unitId;
    if (_propertyId != null && costPoolScopeNeedsUnit(_scope)) {
      _refreshUnits(_propertyId!);
    }
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
    final bool needsUnit = costPoolScopeNeedsUnit(_scope);

    return AlertDialog(
      key: const Key('cost-pool-dialog'),
      title: Text(
        widget.pool == null ? 'Kostenpool anlegen' : 'Kostenpool ändern',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_failureMessage != null) ...<Widget>[
                  NxNotice(
                    key: const Key('cost-pool-dialog-failure'),
                    message: _failureMessage!,
                    kind: NxNoticeKind.error,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('cost-pool-key'),
                  controller: _key,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: 'Schlüssel',
                    helperText:
                        'Kleinbuchstaben, Ziffern, Punkt, Bindestrich oder '
                        'Unterstrich. Wird von Abrechnungszeilen zitiert.',
                    errorText: _errorFor('poolKey'),
                  ),
                  validator: (String? value) {
                    final String text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Ein Schlüssel ist erforderlich.';
                    }
                    if (!RegExp(
                      r'^[a-z0-9][a-z0-9._-]{0,49}$',
                    ).hasMatch(text)) {
                      return 'Nur Kleinbuchstaben, Ziffern, . _ - (max. 50).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('cost-pool-name'),
                  controller: _name,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: 'Bezeichnung',
                    errorText: _errorFor('name'),
                  ),
                  validator: (String? value) => (value ?? '').trim().isEmpty
                      ? 'Eine Bezeichnung ist erforderlich.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<CostPoolScope>(
                  key: const Key('cost-pool-scope'),
                  value: _scope,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Geltungsbereich',
                    errorText: _errorFor('scope'),
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
                  onChanged: _submitting
                      ? null
                      : (CostPoolScope? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _scope = value;
                            // Cleared rather than kept hidden. A portfolio
                            // pool with a stashed property id would be refused
                            // by the server for a reason nothing on screen
                            // shows.
                            if (!costPoolScopeNeedsProperty(value)) {
                              _propertyId = null;
                            }
                            if (!costPoolScopeNeedsLabel(value)) {
                              _label.clear();
                            }
                            if (!costPoolScopeNeedsUnit(value)) {
                              _unitId = null;
                            }
                          });
                          if (costPoolScopeNeedsUnit(value) &&
                              _propertyId != null) {
                            _refreshUnits(_propertyId!);
                          }
                        },
                ),
                if (needsLabel) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('cost-pool-label'),
                    controller: _label,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: 'Bezeichnung des Bereichs',
                      helperText:
                          'Für Gebäude, Aufgang und Zählergruppe gibt es in '
                          'diesem Modell keine eigene Entität. Diese Angabe '
                          'ist die einzige Identität des Bereichs und muss je '
                          'Objekt eindeutig sein.',
                      errorText: _errorFor('scopeLabel'),
                    ),
                    validator: (String? value) => (value ?? '').trim().isEmpty
                        ? 'Ohne Bezeichnung hat dieser Bereich keine Identität.'
                        : null,
                  ),
                ],
                if (needsProperty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Objekt',
                      errorText:
                          _errorFor('propertyId') ??
                          (_propertyId == null
                              ? 'Dieser Geltungsbereich braucht ein Objekt.'
                              : null),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _propertyId == null
                                ? 'Kein Objekt gewählt'
                                : widget.propertyLabel(_propertyId!),
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          key: const Key('cost-pool-pick-property'),
                          onPressed: _submitting ? null : _pickProperty,
                          child: const Text('Wählen'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (needsUnit) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String?>(
                    key: const Key('cost-pool-unit'),
                    // Guarded: a unit id with no matching item would trip
                    // DropdownButton's own assertion, which is how a form
                    // silently loses the value it was opened to show.
                    value:
                        _units.any(
                          (CostPoolUnitOption unit) => unit.id == _unitId,
                        )
                        ? _unitId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Einheit',
                      helperText: _propertyId == null
                          ? 'Zuerst ein Objekt wählen.'
                          : (_loadingUnits
                                ? 'Einheiten werden geladen …'
                                : null),
                      errorText:
                          _errorFor('unitId') ??
                          (_unitId == null && !_loadingUnits
                              ? 'Ein Einheiten-Pool benennt seine Einheit.'
                              : null),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      for (final CostPoolUnitOption unit in _units)
                        DropdownMenuItem<String?>(
                          value: unit.id,
                          child: Text(unit.label),
                        ),
                    ],
                    onChanged: _submitting || _loadingUnits
                        ? null
                        : (String? value) => setState(() => _unitId = value),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('cost-pool-note'),
                  controller: _note,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
                const SizedBox(height: AppSpacing.xs),
                SwitchListTile(
                  key: const Key('cost-pool-active'),
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: _submitting
                      ? null
                      : (bool value) => setState(() => _active = value),
                  title: const Text('Aktiv'),
                  subtitle: const Text(
                    'Ein inaktiver Pool bleibt in der Liste, kann aber von '
                    'keinem neuen Umlageschlüssel mehr benannt werden.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('cost-pool-submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
      ],
    );
  }

  String? _errorFor(String field) =>
      _failureField == field ? _failureMessage : null;

  Future<void> _refreshUnits(String propertyId) async {
    setState(() => _loadingUnits = true);
    final List<CostPoolUnitOption> units = await widget.loadUnits(propertyId);
    if (!mounted) {
      return;
    }
    setState(() {
      _units = units;
      _loadingUnits = false;
      // A unit from the property that was just replaced would be refused by
      // the server. Dropped here rather than carried invisibly.
      if (!units.any((CostPoolUnitOption unit) => unit.id == _unitId)) {
        _unitId = null;
      }
    });
  }

  Future<void> _pickProperty() async {
    final String? chosen = await widget.pickProperty(context);
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      _propertyId = chosen;
      _unitId = null;
      _units = const <CostPoolUnitOption>[];
    });
    if (costPoolScopeNeedsUnit(_scope)) {
      await _refreshUnits(chosen);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _failureMessage = null;
      _failureField = null;
    });
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (costPoolScopeNeedsProperty(_scope) && _propertyId == null) {
      // The property and unit fields live outside the Form, so their errors
      // are surfaced by re-rendering rather than by validate().
      setState(() {});
      return;
    }
    if (costPoolScopeNeedsUnit(_scope) && _unitId == null) {
      setState(() {});
      return;
    }

    setState(() => _submitting = true);
    final CostPoolActionFailure? failure = await widget.onSubmit(
      CostPoolFormResult(
        poolKey: _key.text.trim(),
        name: _name.text.trim(),
        scope: _scope,
        propertyId: _propertyId,
        unitId: costPoolScopeNeedsUnit(_scope) ? _unitId : null,
        scopeLabel: costPoolScopeNeedsLabel(_scope) ? _label.text.trim() : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        isActive: _active,
      ),
    );
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _failureMessage = failure.message;
      _failureField = failure.field;
    });
  }
}
