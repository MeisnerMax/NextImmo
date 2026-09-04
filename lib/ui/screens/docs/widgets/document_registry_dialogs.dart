import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../features/documents_compliance/application/document_mutation_outcome.dart';
import '../../../../features/documents_compliance/application/document_registry_controller.dart';
import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_notice.dart';
import '../../../components/responsive_constraints.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// The registry dialogs of DOCUMENTS-V2 increment B1 (`documents.md`
/// §6.8–6.10, §12): document type create/edit/deactivate, requirement rule
/// create/edit (request, waive with a mandatory reason) and retire.
///
/// Every dialog owns its submit and keeps the input on a failure; validation
/// failures render inline. There is no version conflict path: both registry
/// RPCs are upserts without `expectedVersion`. And there is no delete — the
/// legacy "Loeschen" dies with the legacy tabs.

typedef DocumentRegistrySubmit<R> =
    Future<DocumentMutationOutcome> Function(R draft);

/// Outcome of the retire confirmation; "no reason" is a complete decision.
class RequiredDocumentRetireDecision {
  const RequiredDocumentRetireDecision({this.reason});

  final String? reason;
}

Future<bool> showDocumentTypeDialog({
  required BuildContext context,
  required DocumentRegistrySubmit<DocumentTypeDraft> onSubmit,
  DocumentTypeDto? existing,
  DocumentLinkEntityType initialEntityType = DocumentLinkEntityType.property,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _DocumentTypeDialog(
          existing: existing,
          initialEntityType: initialEntityType,
          onSubmit: onSubmit,
        ),
  );
  return saved ?? false;
}

Future<bool> showRequiredDocumentDialog({
  required BuildContext context,
  required DocumentLinkEntityType entityType,
  required List<DocumentTypeDto> types,
  required DocumentRegistrySubmit<RequiredDocumentDraft> onSubmit,
  RequiredDocumentDto? existing,
  String? existingTypeName,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _RequiredDocumentDialog(
          entityType: entityType,
          types: types,
          existing: existing,
          existingTypeName: existingTypeName,
          onSubmit: onSubmit,
        ),
  );
  return saved ?? false;
}

/// Foundation §14: names the rule, states the consequence in one sentence,
/// confirms with the verb in error colour, offers an optional audited reason.
Future<bool> showRequiredDocumentRetireDialog({
  required BuildContext context,
  required RequiredDocumentDto rule,
  required String typeName,
  required DocumentRegistrySubmit<RequiredDocumentRetireDecision> onSubmit,
}) async {
  final retired = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _RequiredDocumentRetireDialog(
          rule: rule,
          typeName: typeName,
          onSubmit: onSubmit,
        ),
  );
  return retired ?? false;
}

// --- shared ------------------------------------------------------------------

abstract class _RegistryDialogState<T extends StatefulWidget, R>
    extends State<T> {
  bool _submitting = false;
  String? _inlineError;

  String get title;
  String get submitLabel;
  Key get dialogKey;
  Key get submitKey;
  bool get destructive => false;
  bool get isDirty;
  bool get canSubmit => true;
  R? collect();
  Future<DocumentMutationOutcome> submit(R draft);
  Widget buildForm(BuildContext context);

  Future<void> performSubmit() async {
    if (_submitting) {
      return;
    }
    final draft = collect();
    if (draft == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final outcome = await submit(draft);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case DocumentMutationSucceeded():
        Navigator.of(context).pop(true);
      case DocumentMutationConflicted(:final conflict):
        setState(() {
          _submitting = false;
          _inlineError =
              'Zwischenzeitlich geändert (Server-Version '
              '${conflict.actualVersion}). Bitte erneut speichern.';
        });
      case DocumentMutationRejected(:final message, :final isValidation):
        if (isValidation) {
          setState(() {
            _submitting = false;
            _inlineError = message;
          });
        } else {
          Navigator.of(context).pop(false);
        }
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (confirmContext) => AlertDialog(
            title: const Text('Änderungen verwerfen?'),
            content: const Text(
              'Deine Eingaben in diesem Dialog gehen verloren.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(confirmContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(confirmContext).pop(true),
                child: const Text('Verwerfen'),
              ),
            ],
          ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirty = isDirty && !_submitting;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: AlertDialog(
        key: dialogKey,
        title: Text(title),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                buildForm(context),
                if (_inlineError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  NxNotice(
                    key: const Key('documents-registry-dialog-error'),
                    kind: NxNoticeKind.error,
                    message: _inlineError!,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: submitKey,
            style:
                destructive
                    ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    )
                    : null,
            onPressed: _submitting || !canSubmit ? null : performSubmit,
            child:
                _submitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(submitLabel),
          ),
        ],
      ),
    );
  }
}

String? _requiredValidator(String? value) =>
    (value ?? '').trim().isEmpty ? 'Pflichtfeld' : null;

String? _monthsValidator(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) {
    return null;
  }
  final months = int.tryParse(text);
  if (months == null || months < 1 || months > 1200) {
    return 'Zwischen 1 und 1200 Monaten.';
  }
  return null;
}

int? _monthsOf(String value) {
  final text = value.trim();
  return text.isEmpty ? null : int.tryParse(text);
}

String? _nullIfBlank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

// --- Dokumenttyp -----------------------------------------------------------------

class _DocumentTypeDialog extends StatefulWidget {
  const _DocumentTypeDialog({
    required this.existing,
    required this.initialEntityType,
    required this.onSubmit,
  });

  final DocumentTypeDto? existing;
  final DocumentLinkEntityType initialEntityType;
  final DocumentRegistrySubmit<DocumentTypeDraft> onSubmit;

  @override
  State<_DocumentTypeDialog> createState() => _DocumentTypeDialogState();
}

class _DocumentTypeDialogState
    extends _RegistryDialogState<_DocumentTypeDialog, DocumentTypeDraft> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _key;
  late final TextEditingController _validity;
  late DocumentLinkEntityType _entityType;
  late bool _active;

  /// The key follows the name until it was edited by hand.
  bool _keyTouched = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _key = TextEditingController(text: existing?.key ?? '');
    _validity = TextEditingController(
      text: existing?.defaultValidityMonths?.toString() ?? '',
    );
    _entityType = existing?.entityType ?? widget.initialEntityType;
    _active = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _validity.dispose();
    super.dispose();
  }

  @override
  String get title => _isNew ? 'Dokumenttyp anlegen' : 'Dokumenttyp bearbeiten';

  @override
  String get submitLabel => _isNew ? 'Anlegen' : 'Speichern';

  @override
  Key get dialogKey => const Key('documents-type-dialog');

  @override
  Key get submitKey => const Key('documents-type-dialog-submit');

  @override
  bool get isDirty {
    final existing = widget.existing;
    if (existing == null) {
      return _name.text.trim().isNotEmpty ||
          _key.text.trim().isNotEmpty ||
          _validity.text.trim().isNotEmpty;
    }
    return _name.text.trim() != existing.name ||
        _entityType != existing.entityType ||
        _active != existing.isActive ||
        _monthsOf(_validity.text) != existing.defaultValidityMonths;
  }

  @override
  DocumentTypeDraft? collect() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return null;
    }
    return DocumentTypeDraft(
      key: _isNew ? _key.text.trim() : widget.existing!.key,
      name: _name.text.trim(),
      entityType: _entityType,
      defaultValidityMonths: _monthsOf(_validity.text),
      isActive: _active,
    );
  }

  @override
  Future<DocumentMutationOutcome> submit(DocumentTypeDraft draft) =>
      widget.onSubmit(draft);

  @override
  Widget buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextFormField(
            key: const Key('documents-type-dialog-name'),
            controller: _name,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Name',
              counterText: '',
            ),
            validator: _requiredValidator,
            onChanged: (value) {
              setState(() {
                if (_isNew && !_keyTouched) {
                  _key.text = suggestDocumentTypeKey(value);
                }
              });
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_isNew)
            TextFormField(
              key: const Key('documents-type-dialog-key'),
              controller: _key,
              maxLength: 100,
              style: theme.textTheme.bodyMedium?.merge(context.dataMonoStyle),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                labelText: 'Key',
                helperText:
                    'Technischer Schlüssel, nach dem Anlegen unveränderlich. '
                    'Kleinbuchstaben, Ziffern, . _ -',
                counterText: '',
              ),
              validator: validateDocumentTypeKey,
              onChanged: (_) => setState(() => _keyTouched = true),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Key',
                helperText: 'Nach dem Anlegen unveränderlich.',
              ),
              child: Text(
                widget.existing!.key,
                key: const Key('documents-type-dialog-key-readonly'),
                style: theme.textTheme.bodyMedium?.merge(context.dataMonoStyle),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<DocumentLinkEntityType>(
            key: const Key('documents-type-dialog-level'),
            value: _entityType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ebene'),
            items: <DropdownMenuItem<DocumentLinkEntityType>>[
              for (final entityType in DocumentLinkEntityType.values)
                DropdownMenuItem<DocumentLinkEntityType>(
                  value: entityType,
                  child: Text(documentEntityTypeLabel(entityType)),
                ),
            ],
            onChanged:
                (value) => setState(() => _entityType = value ?? _entityType),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('documents-type-dialog-validity'),
            controller: _validity,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Standard-Gültigkeit in Monaten (optional)',
              helperText:
                  'Belegt „Gültig bis" beim Anlegen eines Dokuments vor.',
            ),
            validator: _monthsValidator,
            onChanged: (_) => setState(() {}),
          ),
          if (!_isNew) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              key: const Key('documents-type-dialog-active'),
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Aktiv'),
              subtitle: const Text(
                'Deaktivierte Typen verschwinden aus den Auswahllisten, '
                'bleiben aber an bestehenden Dokumenten und Regeln benannt.',
              ),
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Pflichtregel ------------------------------------------------------------------

enum _RuleScope { all, objectType }

class _RequiredDocumentDialog extends StatefulWidget {
  const _RequiredDocumentDialog({
    required this.entityType,
    required this.types,
    required this.existing,
    required this.existingTypeName,
    required this.onSubmit,
  });

  final DocumentLinkEntityType entityType;
  final List<DocumentTypeDto> types;
  final RequiredDocumentDto? existing;
  final String? existingTypeName;
  final DocumentRegistrySubmit<RequiredDocumentDraft> onSubmit;

  @override
  State<_RequiredDocumentDialog> createState() =>
      _RequiredDocumentDialogState();
}

class _RequiredDocumentDialogState
    extends
        _RegistryDialogState<_RequiredDocumentDialog, RequiredDocumentDraft> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _scopeKey;
  late final TextEditingController _validity;
  late final TextEditingController _note;
  late final TextEditingController _waiverReason;
  String? _documentTypeId;
  _RuleScope _scope = _RuleScope.all;
  late bool _mandatory;
  DateTime? _dueAt;
  late bool _requested;
  late bool _waived;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _scopeKey = TextEditingController(text: existing?.scopeKey ?? '');
    _validity = TextEditingController(
      text: existing?.validityMonths?.toString() ?? '',
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _waiverReason = TextEditingController(text: existing?.waiverReason ?? '');
    _documentTypeId = existing?.documentTypeId;
    _scope =
        existing?.scopeKey != null ? _RuleScope.objectType : _RuleScope.all;
    _mandatory = existing?.isMandatory ?? true;
    _dueAt = existing?.dueAt;
    _requested = existing?.requestedAt != null;
    _waived = existing?.waivedAt != null;
  }

  @override
  void dispose() {
    _scopeKey.dispose();
    _validity.dispose();
    _note.dispose();
    _waiverReason.dispose();
    super.dispose();
  }

  @override
  String get title =>
      _isNew ? 'Pflichtregel anlegen' : 'Pflichtregel bearbeiten';

  @override
  String get submitLabel => _isNew ? 'Anlegen' : 'Speichern';

  @override
  Key get dialogKey => const Key('documents-requirement-dialog');

  @override
  Key get submitKey => const Key('documents-requirement-dialog-submit');

  @override
  bool get isDirty {
    final existing = widget.existing;
    if (existing == null) {
      return _documentTypeId != null ||
          _scopeKey.text.trim().isNotEmpty ||
          _validity.text.trim().isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _dueAt != null ||
          !_mandatory;
    }
    return _mandatory != existing.isMandatory ||
        _dueAt != existing.dueAt ||
        _monthsOf(_validity.text) != existing.validityMonths ||
        _nullIfBlank(_note.text) != existing.note ||
        _requested != (existing.requestedAt != null) ||
        _waived != (existing.waivedAt != null) ||
        _nullIfBlank(_waiverReason.text) != existing.waiverReason;
  }

  @override
  RequiredDocumentDraft? collect() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return null;
    }
    final documentTypeId = _documentTypeId;
    if (documentTypeId == null) {
      return null;
    }
    final existing = widget.existing;
    final scopeKey =
        existing != null
            ? existing.scopeKey
            : _scope == _RuleScope.objectType
            ? _nullIfBlank(_scopeKey.text)
            : null;
    return RequiredDocumentDraft(
      entityType: widget.entityType,
      documentTypeId: documentTypeId,
      entityId: existing?.entityId,
      scopeKey: scopeKey,
      isMandatory: _mandatory,
      dueAt: _dueAt,
      validityMonths: _monthsOf(_validity.text),
      ownerUserId: existing?.ownerUserId,
      note: _nullIfBlank(_note.text),
      requested: _requested,
      waived: _waived,
      waiverReason: _waived ? _nullIfBlank(_waiverReason.text) : null,
    );
  }

  @override
  Future<DocumentMutationOutcome> submit(RequiredDocumentDraft draft) =>
      widget.onSubmit(draft);

  @override
  Widget buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final levelLabel = documentEntityTypeLabel(widget.entityType);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: context.semanticColors.textSecondary,
    );
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Ebene: $levelLabel', style: theme.textTheme.bodyMedium),
          if (existing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Ebene, Dokumenttyp und Geltung bestimmen die Regel und lassen '
              'sich nicht ändern. Für eine andere Kombination lege eine neue '
              'Regel an.',
              style: secondary,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (existing == null)
            DropdownButtonFormField<String?>(
              key: const Key('documents-requirement-dialog-type'),
              value: _documentTypeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Dokumenttyp'),
              items: <DropdownMenuItem<String?>>[
                for (final type in widget.types)
                  DropdownMenuItem<String?>(
                    value: type.id,
                    child: Text(type.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (value) => value == null ? 'Pflichtfeld' : null,
              onChanged: (value) => setState(() => _documentTypeId = value),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Dokumenttyp'),
              child: Text(
                widget.existingTypeName ?? '—',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (existing == null) ...<Widget>[
            Text('Geltung', style: theme.textTheme.titleSmall),
            RadioListTile<_RuleScope>(
              key: const Key('documents-requirement-dialog-scope-all'),
              contentPadding: EdgeInsets.zero,
              value: _RuleScope.all,
              groupValue: _scope,
              title: Text(
                'Alle ${documentEntityTypePluralLabel(widget.entityType)}',
              ),
              onChanged:
                  (value) => setState(() => _scope = value ?? _RuleScope.all),
            ),
            RadioListTile<_RuleScope>(
              key: const Key('documents-requirement-dialog-scope-key'),
              contentPadding: EdgeInsets.zero,
              value: _RuleScope.objectType,
              groupValue: _scope,
              title: const Text('Nur Objektart'),
              onChanged:
                  (value) => setState(() => _scope = value ?? _RuleScope.all),
            ),
            if (_scope == _RuleScope.objectType) ...<Widget>[
              TextFormField(
                key: const Key('documents-requirement-dialog-scope-key-field'),
                controller: _scopeKey,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Objektart',
                  helperText: 'Freitext wie am Objekt hinterlegt.',
                  counterText: '',
                ),
                validator: _requiredValidator,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ] else
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Geltung'),
              child: Text(
                documentRequirementScopeLabel(
                  entityType: existing.entityType,
                  entityId: existing.entityId,
                  scopeKey: existing.scopeKey,
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const Key('documents-requirement-dialog-mandatory'),
            contentPadding: EdgeInsets.zero,
            value: _mandatory,
            title: const Text('Pflichtdokument'),
            onChanged: (value) => setState(() => _mandatory = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DateField(
            fieldKey: const Key('documents-requirement-dialog-due'),
            label: 'Frist (optional)',
            value: _dueAt,
            onChanged: (value) => setState(() => _dueAt = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('documents-requirement-dialog-validity'),
            controller: _validity,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Gültigkeit in Monaten (optional)',
            ),
            validator: _monthsValidator,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('documents-requirement-dialog-note'),
            controller: _note,
            maxLines: 2,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Notiz',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (existing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('Zustand', style: theme.textTheme.titleSmall),
            SwitchListTile(
              key: const Key('documents-requirement-dialog-requested'),
              contentPadding: EdgeInsets.zero,
              value: _requested,
              title: const Text('Angefordert'),
              subtitle: const Text('Der Nachweis wurde angefordert.'),
              onChanged: (value) => setState(() => _requested = value),
            ),
            SwitchListTile(
              key: const Key('documents-requirement-dialog-waived'),
              contentPadding: EdgeInsets.zero,
              value: _waived,
              title: const Text('Nicht relevant (Verzicht)'),
              subtitle: const Text(
                'Ein Verzicht ist eine protokollierte Entscheidung und '
                'braucht eine Begründung.',
              ),
              onChanged: (value) => setState(() => _waived = value),
            ),
            if (_waived)
              TextFormField(
                key: const Key('documents-requirement-dialog-waiver-reason'),
                controller: _waiverReason,
                maxLines: 2,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Begründung des Verzichts',
                  counterText: '',
                ),
                validator: _requiredValidator,
                onChanged: (_) => setState(() {}),
              ),
          ],
        ],
      ),
    );
  }
}

// --- Zurückziehen -----------------------------------------------------------------

class _RequiredDocumentRetireDialog extends StatefulWidget {
  const _RequiredDocumentRetireDialog({
    required this.rule,
    required this.typeName,
    required this.onSubmit,
  });

  final RequiredDocumentDto rule;
  final String typeName;
  final DocumentRegistrySubmit<RequiredDocumentRetireDecision> onSubmit;

  @override
  State<_RequiredDocumentRetireDialog> createState() =>
      _RequiredDocumentRetireDialogState();
}

class _RequiredDocumentRetireDialogState
    extends
        _RegistryDialogState<
          _RequiredDocumentRetireDialog,
          RequiredDocumentRetireDecision
        > {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  String get title => 'Pflichtregel zurückziehen';

  @override
  String get submitLabel => 'Zurückziehen';

  @override
  Key get dialogKey => const Key('documents-requirement-retire-dialog');

  @override
  Key get submitKey => const Key('documents-requirement-retire-confirm');

  @override
  bool get destructive => true;

  @override
  bool get isDirty => _reason.text.trim().isNotEmpty;

  @override
  RequiredDocumentRetireDecision collect() =>
      RequiredDocumentRetireDecision(reason: _nullIfBlank(_reason.text));

  @override
  Future<DocumentMutationOutcome> submit(
    RequiredDocumentRetireDecision draft,
  ) => widget.onSubmit(draft);

  @override
  Widget buildForm(BuildContext context) {
    final scope = documentRequirementScopeLabel(
      entityType: widget.rule.entityType,
      entityId: widget.rule.entityId,
      scopeKey: widget.rule.scopeKey,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '„${widget.typeName}" · $scope: Die Regel gilt ab sofort nicht '
          'mehr; bestehende Dokumente bleiben unberührt. Eine gleiche Regel '
          'kann später neu angelegt werden.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.component),
        TextFormField(
          key: const Key('documents-requirement-retire-reason'),
          controller: _reason,
          maxLength: 2000,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Grund (optional, wird protokolliert)',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      key: fieldKey,
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatDocumentDate(value),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: '$label wählen',
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(picked);
              }
            },
          ),
          if (value != null)
            IconButton(
              tooltip: '$label entfernen',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}
