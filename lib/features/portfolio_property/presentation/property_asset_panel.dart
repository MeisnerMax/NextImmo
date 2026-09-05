import 'package:flutter/material.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/components/nx_section_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/utils/number_parse.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/property_repository.dart';
import '../application/property_workspace_host_state.dart';
import '../domain/property_dto.dart';
import 'property_presentation.dart';

/// Persists the form; true when the canonical readback landed (mutation
/// phase `succeeded`), false for conflict, forbidden, validation or failure.
typedef PropertyAssetUpdate =
    Future<bool> Function(PropertyUpdateDto changes, {int? expectedVersion});

/// Property Asset V2 (`PROPERTY_ASSET_V2.md`): the trusted, compact master
/// record of one property inside the workspace — `Objekt`.
///
/// Rehosts the reference slice's detail contract unchanged: fields are seeded
/// from an immutable copy of the canonical DTO, saves carry the seeded version
/// (optimistic concurrency), a conflict keeps every input and reseeds only the
/// version, a clean form follows canonical refreshes and a dirty form never
/// gets overwritten by realtime. Adds the contract fields the slice left out
/// (`addressLine2`, `sqft`, `yearBuilt`); `status` and `propertyType` are
/// read-only and travel unchanged in the full-record update.
class PropertyAssetPanel extends StatefulWidget {
  const PropertyAssetPanel({
    super.key,
    required this.state,
    required this.canEdit,
    required this.editing,
    required this.onEditingChanged,
    required this.dirtyRegistry,
    required this.onUpdate,
    required this.onRetry,
    this.mediaBuilder,
  });

  final ReferenceSliceState state;

  /// `property.update` on the membership plus an aal2 session. Without it the
  /// surface is fully read-only — no disabled form.
  final bool canEdit;

  /// Edit mode is owned by the host (its header carries the edit action);
  /// the panel reports exits through [onEditingChanged].
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final PropertyWorkspaceDirtyRegistry dirtyRegistry;
  final PropertyAssetUpdate onUpdate;
  final VoidCallback onRetry;

  /// Builds the property's media gallery (`PROPERTY-MEDIA-DATA-01`). Injected
  /// by the connected host so this panel stays pumpable without a provider
  /// graph; null simply omits the section.
  final Widget Function(BuildContext context, String propertyId)? mediaBuilder;

  static const String notProvided = 'Nicht hinterlegt';

  @override
  State<PropertyAssetPanel> createState() => _PropertyAssetPanelState();
}

class _PropertyAssetPanelState extends State<PropertyAssetPanel>
    implements PropertyWorkspaceDirtyChild {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _units = TextEditingController();
  final _sqft = TextEditingController();
  final _yearBuilt = TextEditingController();
  final _notes = TextEditingController();

  /// The canonical record the form was seeded from. `status` and
  /// `propertyType` are taken from here for the update payload.
  PropertyDto? _seeded;

  /// The version the field contents are based on; sent as expectedVersion.
  int? _seededVersion;
  Map<String, Object?> _seededValues = const <String, Object?>{};
  bool _submitting = false;

  static final RegExp _normalizedCode = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');

  @override
  void initState() {
    super.initState();
    widget.dirtyRegistry.register(this);
    _seed(widget.state.selectedProperty);
  }

  @override
  void didUpdateWidget(covariant PropertyAssetPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dirtyRegistry, widget.dirtyRegistry)) {
      oldWidget.dirtyRegistry.unregister(this);
      widget.dirtyRegistry.register(this);
    }
    final property = widget.state.selectedProperty;
    if (property?.id != _seeded?.id) {
      _seed(property);
      return;
    }
    if (property == null) {
      return;
    }
    if (!oldWidget.editing && widget.editing) {
      // Entering edit mode always starts from the canonical record.
      _seed(property);
      return;
    }
    final mutationPhase = widget.state.mutationPhase;
    if (mutationPhase != oldWidget.state.mutationPhase) {
      if (mutationPhase == PropertyMutationPhase.succeeded) {
        // Our own save landed: the canonical readback carries this form's
        // values, so reseeding leaves a clean record and edit mode ends.
        _seed(property);
        _exitEditing();
        return;
      }
      if (mutationPhase == PropertyMutationPhase.conflict) {
        // Input stays; only the version the user is shown moves on, so the
        // next save proceeds against exactly that version.
        _seededVersion = property.version;
        return;
      }
    }
    if (!_isDirty && property.version != _seededVersion) {
      // A clean form follows canonical refreshes (realtime, reload). A dirty
      // form keeps its input and seeded version; the "newer version" notice
      // and the conflict mechanism decide what happens to unsaved edits.
      _seed(property);
    }
  }

  @override
  void dispose() {
    widget.dirtyRegistry.unregister(this);
    _name.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _zip.dispose();
    _city.dispose();
    _country.dispose();
    _units.dispose();
    _sqft.dispose();
    _yearBuilt.dispose();
    _notes.dispose();
    super.dispose();
  }

  // --- Dirty-child contract ------------------------------------------------

  @override
  bool get hasUnsavedChanges => widget.editing && widget.canEdit && _isDirty;

  @override
  Future<bool> saveChanges() => _submit();

  @override
  void discardChanges() {
    _seed(widget.state.selectedProperty);
    _exitEditing();
  }

  // --- Seeding and dirty comparison ---------------------------------------

  void _seed(PropertyDto? property) {
    _seeded = property;
    _seededVersion = property?.version;
    if (property == null) {
      _seededValues = const <String, Object?>{};
      return;
    }
    _name.text = property.name;
    _addressLine1.text = property.addressLine1;
    _addressLine2.text = property.addressLine2 ?? '';
    _zip.text = property.zip;
    _city.text = property.city;
    _country.text = property.country;
    _units.text = property.units.toString();
    _sqft.text = property.sqft == null ? '' : _seedNumber(property.sqft!);
    _yearBuilt.text = property.yearBuilt?.toString() ?? '';
    _notes.text = property.notes ?? '';
    _seededValues = _normalizedValues();
  }

  static String _seedNumber(double value) {
    final text =
        value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString();
    return text.replaceAll('.', ',');
  }

  static String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Normalized, deterministic view of the form — trimmed text, empty
  /// optionals as null, numbers parsed. The dirty check compares this against
  /// the seeded record, never widget state.
  Map<String, Object?> _normalizedValues() {
    return <String, Object?>{
      'name': _name.text.trim(),
      'addressLine1': _addressLine1.text.trim(),
      'addressLine2': _trimOrNull(_addressLine2.text),
      'zip': _zip.text.trim(),
      'city': _city.text.trim(),
      'country': _country.text.trim(),
      'units': NumberParse.parseIntFlexible(_units.text),
      'sqft':
          _sqft.text.trim().isEmpty
              ? null
              : NumberParse.parseDoubleFlexible(_sqft.text),
      'yearBuilt':
          _yearBuilt.text.trim().isEmpty
              ? null
              : NumberParse.parseIntFlexible(_yearBuilt.text),
      'notes': _trimOrNull(_notes.text),
    };
  }

  bool get _isDirty {
    if (_seeded == null) {
      return false;
    }
    final current = _normalizedValues();
    for (final entry in current.entries) {
      if (_seededValues[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  bool get _remoteNewerVersion {
    final property = widget.state.selectedProperty;
    final seeded = _seededVersion;
    return widget.editing &&
        property != null &&
        seeded != null &&
        property.version > seeded &&
        widget.state.mutationPhase != PropertyMutationPhase.conflict;
  }

  void _exitEditing() {
    if (!widget.editing) {
      return;
    }
    // didUpdateWidget runs inside the parent's build; the host flips its own
    // state after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onEditingChanged(false);
      }
    });
  }

  // --- Mutation -------------------------------------------------------------

  bool get _mutationInFlight =>
      _submitting ||
      widget.state.mutationPhase == PropertyMutationPhase.submitting ||
      widget.state.mutationPhase == PropertyMutationPhase.retrying;

  PropertyUpdateDto _buildChanges(PropertyDto seeded) {
    final sqftText = _sqft.text.trim();
    final yearText = _yearBuilt.text.trim();
    return PropertyUpdateDto(
      name: _name.text.trim(),
      addressLine1: _addressLine1.text.trim(),
      addressLine2: _trimOrNull(_addressLine2.text),
      zip: _zip.text.trim(),
      city: _city.text.trim(),
      country: _country.text.trim(),
      // Read-only in V2: the full-record contract still requires them, so the
      // canonical values travel unchanged.
      propertyType: seeded.propertyType,
      units: NumberParse.parseIntFlexible(_units.text)!,
      sqft: sqftText.isEmpty ? null : NumberParse.parseDoubleFlexible(sqftText),
      yearBuilt:
          yearText.isEmpty ? null : NumberParse.parseIntFlexible(yearText),
      notes: _trimOrNull(_notes.text),
      status: seeded.status,
    );
  }

  Future<bool> _submit() async {
    final seeded = _seeded;
    if (seeded == null || !widget.canEdit || _mutationInFlight) {
      return false;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return false;
    }
    setState(() => _submitting = true);
    try {
      return await widget.onUpdate(
        _buildChanges(seeded),
        expectedVersion: _seededVersion,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _cancel() async {
    if (_isDirty) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) {
        return;
      }
    }
    discardChanges();
  }

  Future<void> _reloadCanonical() async {
    if (_isDirty) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) {
        return;
      }
    }
    setState(() => _seed(widget.state.selectedProperty));
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            key: const Key('property-asset-discard-dialog'),
            title: const Text('Änderungen verwerfen?'),
            content: const Text(
              'Ungespeicherte Eingaben gehen verloren und der zuletzt geladene '
              'Stand wird wiederhergestellt.',
            ),
            actions: [
              TextButton(
                key: const Key('property-asset-discard-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                key: const Key('property-asset-discard-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Verwerfen'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final property = widget.state.selectedProperty;
    if (property == null) {
      return const SizedBox.shrink();
    }
    final editing = widget.editing && widget.canEdit;
    return ListView(
      key: const Key('property-asset-scroll'),
      children: [
        _buildStatusLine(context, property),
        ..._buildFeedback(context),
        const SizedBox(height: AppSpacing.component),
        if (editing)
          _buildForm(context, property)
        else ...<Widget>[
          _buildRead(context, property),
          // Media sits under the master data rather than in a domain of its
          // own: a photo is a property field, and PROPERTY_WORKSPACE_V2 caps
          // the navigation at seven domains. It is hidden while the form is
          // open, because an upload during an unsaved edit would be a second
          // mutation competing with the first.
          if (widget.mediaBuilder != null) ...<Widget>[
            const SizedBox(height: AppSpacing.component),
            widget.mediaBuilder!(context, property.id),
          ],
        ],
      ],
    );
  }

  Widget _buildStatusLine(BuildContext context, PropertyDto property) {
    final theme = Theme.of(context);
    return Wrap(
      key: const Key('property-asset-status-line'),
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NxStatusBadge(
          label: propertyStatusLabel(property.status),
          kind: propertyStatusBadgeKind(property.status),
        ),
        NxStatusBadge(
          key: const Key('property-asset-version'),
          label: 'Version ${property.version}',
        ),
        Text(
          'Stand: ${formatPropertyTimestamp(property.updatedAt)}',
          key: const Key('property-asset-updated-at'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _buildFeedback(BuildContext context) {
    final state = widget.state;
    final notices = <Widget>[];
    switch (state.mutationPhase) {
      case PropertyMutationPhase.submitting:
      case PropertyMutationPhase.retrying:
        notices.add(
          const LinearProgressIndicator(key: Key('property-asset-saving')),
        );
      case PropertyMutationPhase.succeeded:
        notices.add(
          const NxNotice(
            key: Key('property-asset-saved'),
            kind: NxNoticeKind.info,
            icon: Icons.check_circle_outline,
            message:
                'Stammdaten gespeichert. Der kanonische Stand wurde geladen.',
          ),
        );
      case PropertyMutationPhase.conflict:
        final conflict = state.versionConflict;
        notices.add(
          NxNotice(
            key: const Key('property-asset-conflict'),
            kind: NxNoticeKind.warning,
            icon: Icons.sync_problem_outlined,
            title: 'Versionskonflikt',
            message:
                'Das Objekt wurde inzwischen geändert (Serverversion '
                '${conflict?.actualVersion ?? '?'} statt '
                '${conflict?.expectedVersion ?? '?'}). Deine Eingaben bleiben '
                'erhalten; „Erneut speichern“ übernimmt sie auf die angezeigte '
                'Version, „Neu laden“ verwirft sie.',
            action:
                widget.editing
                    ? TextButton(
                      key: const Key('property-asset-conflict-reload'),
                      onPressed: _reloadCanonical,
                      child: const Text('Neu laden'),
                    )
                    : null,
          ),
        );
      case PropertyMutationPhase.forbidden:
        notices.add(
          NxNotice(
            key: const Key('property-asset-forbidden'),
            kind: NxNoticeKind.error,
            icon: Icons.lock_outline,
            message:
                state.message ??
                'Die Änderung wurde abgelehnt. Sie benötigt die Berechtigung '
                    '(property.update).',
          ),
        );
      case PropertyMutationPhase.failed:
        final retryable =
            state.failureKind ==
                PropertyRepositoryFailureKind.infrastructureFailure ||
            state.failureKind ==
                PropertyRepositoryFailureKind.mutationInProgress;
        notices.add(
          NxNotice(
            key: const Key('property-asset-failed'),
            kind: NxNoticeKind.error,
            title:
                state.failureKind ==
                        PropertyRepositoryFailureKind.validationFailed
                    ? 'Servervalidierung fehlgeschlagen'
                    : 'Speichern fehlgeschlagen',
            message:
                state.message ??
                'Die Stammdaten konnten nicht gespeichert werden.',
            action:
                retryable
                    ? TextButton(
                      key: const Key('property-asset-retry'),
                      onPressed: widget.onRetry,
                      child: const Text('Erneut versuchen'),
                    )
                    : null,
          ),
        );
      case PropertyMutationPhase.idle:
        break;
    }
    if (_remoteNewerVersion) {
      final current = state.selectedProperty!.version;
      notices.add(
        NxNotice(
          key: const Key('property-asset-remote-newer'),
          kind: NxNoticeKind.info,
          icon: Icons.update_outlined,
          title: 'Neuere Version verfügbar',
          message:
              'Dieses Objekt wurde inzwischen auf Version $current geändert. '
              'Deine ungespeicherten Eingaben bleiben erhalten; Speichern '
              'prüft gegen die geladene Version $_seededVersion.',
          action: TextButton(
            key: const Key('property-asset-remote-newer-reload'),
            onPressed: _reloadCanonical,
            child: const Text('Neu laden'),
          ),
        ),
      );
    }
    return [
      for (final notice in notices) ...[
        const SizedBox(height: AppSpacing.component),
        notice,
      ],
    ];
  }

  // --- Read mode --------------------------------------------------------------

  Widget _buildRead(BuildContext context, PropertyDto property) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        final cardWidth =
            twoColumns
                ? (constraints.maxWidth - AppSpacing.component) / 2
                : constraints.maxWidth;
        return Wrap(
          key: const Key('property-asset-read'),
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _readGroup(
              width: cardWidth,
              key: const Key('property-asset-group-identity'),
              title: 'Identität',
              rows: [
                _ReadRow(label: 'Name', value: property.name),
                _ReadRow(
                  label: 'Typ',
                  value: property.propertyType,
                  mono: true,
                ),
                _ReadRow(
                  label: 'Status',
                  child: NxStatusBadge(
                    label: propertyStatusLabel(property.status),
                    kind: propertyStatusBadgeKind(property.status),
                  ),
                ),
              ],
            ),
            _readGroup(
              width: cardWidth,
              key: const Key('property-asset-group-address'),
              title: 'Adresse',
              rows: [
                _ReadRow(label: 'Adresszeile 1', value: property.addressLine1),
                _ReadRow(
                  label: 'Adresszeile 2',
                  value: _trimOrNull(property.addressLine2 ?? '') ?? '—',
                ),
                _ReadRow(label: 'PLZ', value: property.zip, mono: true),
                _ReadRow(label: 'Ort', value: property.city),
                _ReadRow(label: 'Land', value: property.country, mono: true),
              ],
            ),
            _readGroup(
              width: cardWidth,
              key: const Key('property-asset-group-physical'),
              title: 'Physische Eckdaten',
              rows: [
                _ReadRow(
                  label: 'Einheiten',
                  value: property.units.toString(),
                  mono: true,
                ),
                _ReadRow(
                  label: 'Fläche (gespeichert in ft²)',
                  value:
                      property.sqft == null
                          ? PropertyAssetPanel.notProvided
                          : formatSquareFeet(property.sqft!),
                  mono: property.sqft != null,
                  muted: property.sqft == null,
                ),
                _ReadRow(
                  label: 'Baujahr',
                  value:
                      property.yearBuilt?.toString() ??
                      PropertyAssetPanel.notProvided,
                  mono: property.yearBuilt != null,
                  muted: property.yearBuilt == null,
                ),
              ],
            ),
            _readGroup(
              width: cardWidth,
              key: const Key('property-asset-group-system'),
              title: 'Systemdaten',
              rows: [
                _ReadRow(
                  label: 'Version',
                  value: property.version.toString(),
                  mono: true,
                ),
                _ReadRow(
                  label: 'Zuletzt geändert',
                  value: formatPropertyTimestamp(property.updatedAt),
                  mono: true,
                ),
                _ReadRow(
                  label: 'Angelegt',
                  value: formatPropertyTimestamp(property.createdAt),
                  mono: true,
                ),
              ],
            ),
            _readGroup(
              width: constraints.maxWidth,
              key: const Key('property-asset-group-notes'),
              title: 'Interne Hinweise',
              rows: [
                _ReadRow(
                  label: 'Notizen',
                  value:
                      _trimOrNull(property.notes ?? '') ??
                      PropertyAssetPanel.notProvided,
                  muted: _trimOrNull(property.notes ?? '') == null,
                  multiline: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _readGroup({
    required double width,
    required Key key,
    required String title,
    required List<_ReadRow> rows,
  }) {
    return SizedBox(
      width: width,
      child: NxCard(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NxSectionHeader(title: title, compact: true),
            const SizedBox(height: AppSpacing.component),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  // --- Edit mode --------------------------------------------------------------

  Widget _buildForm(BuildContext context, PropertyDto property) {
    final conflict =
        widget.state.mutationPhase == PropertyMutationPhase.conflict;
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 720;
          final fieldWidth =
              twoColumns
                  ? (constraints.maxWidth - AppSpacing.component) / 2
                  : constraints.maxWidth;
          return Column(
            key: const Key('property-asset-form'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _formGroup(
                title: 'Identität',
                children: [
                  _field(
                    fieldWidth,
                    _name,
                    'Name',
                    key: const Key('property-asset-edit-name'),
                    validator: _required,
                    autofocus: true,
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _ReadRow(
                      label: 'Typ (nicht änderbar)',
                      value: property.propertyType,
                      mono: true,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _ReadRow(
                      label: 'Status (nicht änderbar)',
                      child: NxStatusBadge(
                        label: propertyStatusLabel(property.status),
                        kind: propertyStatusBadgeKind(property.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              _formGroup(
                title: 'Adresse',
                children: [
                  _field(
                    fieldWidth,
                    _addressLine1,
                    'Adresszeile 1',
                    key: const Key('property-asset-edit-address-line1'),
                    validator: _required,
                    keyboardType: TextInputType.streetAddress,
                  ),
                  _field(
                    fieldWidth,
                    _addressLine2,
                    'Adresszeile 2 (optional)',
                    key: const Key('property-asset-edit-address-line2'),
                    keyboardType: TextInputType.streetAddress,
                  ),
                  _field(
                    fieldWidth,
                    _zip,
                    'PLZ',
                    key: const Key('property-asset-edit-zip'),
                    validator: _required,
                  ),
                  _field(
                    fieldWidth,
                    _city,
                    'Ort',
                    key: const Key('property-asset-edit-city'),
                    validator: _required,
                  ),
                  _field(
                    fieldWidth,
                    _country,
                    'Land (Code, z. B. de)',
                    key: const Key('property-asset-edit-country'),
                    validator: _validateCountry,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              _formGroup(
                title: 'Physische Eckdaten',
                children: [
                  _field(
                    fieldWidth,
                    _units,
                    'Einheiten',
                    key: const Key('property-asset-edit-units'),
                    keyboardType: TextInputType.number,
                    validator: _validateUnits,
                  ),
                  _field(
                    fieldWidth,
                    _sqft,
                    'Fläche in ft² (optional)',
                    key: const Key('property-asset-edit-sqft'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _validateSqft,
                  ),
                  _field(
                    fieldWidth,
                    _yearBuilt,
                    'Baujahr (optional)',
                    key: const Key('property-asset-edit-year-built'),
                    keyboardType: TextInputType.number,
                    validator: _validateYearBuilt,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              _formGroup(
                title: 'Interne Hinweise',
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    child: TextFormField(
                      key: const Key('property-asset-edit-notes'),
                      controller: _notes,
                      decoration: const InputDecoration(
                        labelText: 'Notizen (optional)',
                      ),
                      minLines: 3,
                      maxLines: 8,
                      validator: _validateNotes,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Wrap(
                key: const Key('property-asset-actions'),
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(
                    key: const Key('property-asset-cancel'),
                    onPressed: _mutationInFlight ? null : _cancel,
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton.icon(
                    key: const Key('property-asset-save'),
                    onPressed: _mutationInFlight ? null : _submit,
                    icon:
                        _mutationInFlight
                            ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.save_outlined),
                    label: Text(conflict ? 'Erneut speichern' : 'Speichern'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _formGroup({required String title, required List<Widget> children}) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxSectionHeader(title: title, compact: true),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: children,
          ),
        ],
      ),
    );
  }

  Widget _field(
    double width,
    TextEditingController controller,
    String label, {
    Key? key,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool autofocus = false,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: key,
        controller: controller,
        keyboardType: keyboardType,
        autofocus: autofocus,
        decoration: InputDecoration(labelText: label),
        validator: validator,
      ),
    );
  }

  // --- Validation (mirrors the server contract, invents nothing stricter) ---

  static String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;
  }

  static String? _validateCountry(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Pflichtfeld';
    }
    if (trimmed.length < 2 ||
        trimmed.length > 100 ||
        !_normalizedCode.hasMatch(trimmed)) {
      return 'Normalisierter Code: Kleinbuchstaben, Ziffern, . _ - (z. B. de).';
    }
    return null;
  }

  static String? _validateUnits(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Pflichtfeld';
    }
    final units = NumberParse.parseIntFlexible(value);
    if (units == null || units < 0 || units > 2147483647) {
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

  static String? _validateNotes(String? value) {
    if (value != null && value.trim().length > 10000) {
      return 'Maximal 10.000 Zeichen.';
    }
    return null;
  }
}

/// One label/value pair of the read view. The label and value are coupled
/// semantically so a screen reader announces them together.
class _ReadRow extends StatelessWidget {
  const _ReadRow({
    required this.label,
    this.value,
    this.child,
    this.mono = false,
    this.muted = false,
    this.multiline = false,
  }) : assert(value != null || child != null);

  final String label;
  final String? value;
  final Widget? child;
  final bool mono;
  final bool muted;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: context.semanticColors.textSecondary,
    );
    var valueStyle = theme.textTheme.bodyMedium;
    if (mono) {
      valueStyle = context.dataMonoStyle.copyWith(
        fontSize: valueStyle?.fontSize,
        color: valueStyle?.color,
      );
    }
    if (muted) {
      valueStyle = valueStyle?.copyWith(
        color: context.semanticColors.textSecondary,
        fontStyle: FontStyle.italic,
      );
    }
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          if (child != null)
            child!
          else
            Text(
              value!,
              style: valueStyle,
              softWrap: true,
              maxLines: multiline ? null : 3,
              overflow: multiline ? null : TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
