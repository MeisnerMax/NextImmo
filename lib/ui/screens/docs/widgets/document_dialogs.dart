import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/application/document_mutation_outcome.dart';
import '../../../../features/documents_compliance/application/document_repository.dart';
import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_notice.dart';
import '../../../components/responsive_constraints.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// The shared documents_compliance dialogs (`DUP-007`): the property-scoped
/// archive and the workspace register run the exact same create / add-version
/// / confirm / verify / supersede / archive flows, so the flows live here once
/// and the screens only decide *when* to open them.
///
/// DOCUMENTS-V2 (Foundation §10): **the dialog owns the submit.** It calls the
/// controller through [DocumentDialogSubmit], stays open on a version conflict
/// with the server state as a banner ("Neu laden" / "Erneut speichern") and on
/// a validation failure with the message inline — user input is never thrown
/// away. Only success closes it; other failures close it and are reported by
/// the screen's action-feedback listener.
///
/// Two contract facts shape every dialog in this file:
///
/// * **The file is picked here and uploaded by the controller.** The dialog
///   only carries the chosen bytes; `DocumentUploadPort` puts them in the
///   private bucket and returns the declaration the create/add-version commands
///   take.
/// * **There is no delete.** `OPN-DOM-005` is open and `archived` is terminal,
///   so the destructive-looking action is archiving — behind a confirmation
///   that names the document, never a single click.
///
/// And one binding security decision (§6.7/§20.4): there is no dialog that
/// shows, copies or keeps a signed URL. Content opens through
/// `document_content_opener.dart` only.

/// Submits a dialog's result against [document] — the document the dialog
/// currently holds, i.e. the loaded one or, after a conflict, the server's.
/// Callers take `expectedVersion`/`currentVersionNo` from it. Returns the
/// outcome so the dialog can react in place.
typedef DocumentDialogSubmit<R> =
    Future<DocumentMutationOutcome> Function(R result, DocumentDto document);

/// Identity and validity fields of the create form, kept free of the command
/// shapes so the dialog can serve more than one caller.
class DocumentFormResult {
  const DocumentFormResult({
    required this.title,
    required this.file,
    this.documentTypeId,
    this.validFrom,
    this.validUntil,
    this.notes,
  });

  final String title;
  final DocumentFileSelection file;
  final String? documentTypeId;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? notes;
}

/// Outcome of the verification dialog. Rejecting is as legitimate an outcome as
/// verifying, so it is one decision object rather than two entry points.
class DocumentVerificationDecision {
  const DocumentVerificationDecision({
    required this.outcome,
    this.note,
    this.reason,
  });

  final DocumentVerificationOutcome outcome;
  final String? note;

  /// Optional audit reason (`p_reason`), separate from the verification note
  /// that lands on the version.
  final String? reason;
}

class DocumentSupersedeDecision {
  const DocumentSupersedeDecision({required this.successor, this.reason});

  final DocumentDto successor;
  final String? reason;
}

/// Outcome of the archive confirmation. A value object rather than a bare
/// `String?` so that "no reason given" is a complete decision, not a missing
/// one.
class DocumentArchiveDecision {
  const DocumentArchiveDecision({this.reason});

  final String? reason;
}

/// Adds whole months to a date, clamping the day to the target month's length
/// (31 Jan + 1 month = 28/29 Feb, not 3 Mar).
DateTime addDocumentValidityMonths(DateTime from, int months) {
  final targetMonthIndex = from.month - 1 + months;
  final year = from.year + targetMonthIndex ~/ 12;
  final month = targetMonthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, from.day > lastDay ? lastDay : from.day);
}

// --- entry points --------------------------------------------------------------

Future<bool> showDocumentFormDialog({
  required BuildContext context,
  required Future<DocumentMutationOutcome> Function(DocumentFormResult result)
  onSubmit,
  List<DocumentTypeDto> types = const <DocumentTypeDto>[],
}) async {
  final created = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) =>
            _DocumentFormDialog(types: types, onSubmit: onSubmit),
  );
  return created ?? false;
}

Future<bool> showDocumentVersionDialog({
  required BuildContext context,
  required DocumentDto document,
  required DocumentDialogSubmit<DocumentFileSelection> onSubmit,
}) async {
  final added = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) =>
            _DocumentVersionDialog(document: document, onSubmit: onSubmit),
  );
  return added ?? false;
}

/// MIG-BND-003. Confirming compares the declared object against what really
/// landed in the bucket, and a mismatch drives the document to `rejected` — a
/// real outcome, so the user is told that before running it. No input, so the
/// panel runs the command and handles a conflict by reloading the detail.
Future<bool> showDocumentConfirmContentDialog({
  required BuildContext context,
  required String documentTitle,
  required int versionNo,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          key: const Key('documents-confirm-dialog'),
          title: const Text('Upload bestätigen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 460,
            ),
            child: Text(
              'Version $versionNo von „$documentTitle" wird gegen die '
              'tatsächlich gespeicherte Datei geprüft. Stimmen Größe und '
              'Prüfsumme nicht überein, wird das Dokument abgelehnt und muss '
              'neu hochgeladen werden.',
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('documents-confirm-dialog-submit'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Prüfen und bestätigen'),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

Future<bool> showDocumentVerifyDialog({
  required BuildContext context,
  required DocumentDto document,
  required int versionNo,
  required DocumentDialogSubmit<DocumentVerificationDecision> onSubmit,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _DocumentVerifyDialog(
          document: document,
          versionNo: versionNo,
          onSubmit: onSubmit,
        ),
  );
  return done ?? false;
}

/// Superseding needs a successor, so the decision carries the chosen document.
Future<bool> showDocumentSupersedeDialog({
  required BuildContext context,
  required DocumentDto document,
  required List<DocumentDto> candidates,
  required DocumentDialogSubmit<DocumentSupersedeDecision> onSubmit,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => _DocumentSupersedeDialog(
          document: document,
          candidates: candidates,
          onSubmit: onSubmit,
        ),
  );
  return done ?? false;
}

/// Archiving is terminal and there is no delete path, so it never happens on a
/// single click (Foundation §14: named object, one-sentence consequence,
/// confirm in error colour, optional audited reason).
Future<bool> showDocumentArchiveDialog({
  required BuildContext context,
  required DocumentDto document,
  required DocumentDialogSubmit<DocumentArchiveDecision> onSubmit,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) =>
            _DocumentArchiveDialog(document: document, onSubmit: onSubmit),
  );
  return done ?? false;
}

// --- shared submit/conflict machinery ---------------------------------------------

/// Base of every dialog that owns its submit. Subclasses provide the form and
/// the result; this state runs the submit, keeps the input across a conflict,
/// renders the banner and the two resolution buttons, and guards dirty
/// discards.
abstract class _MutationDialogState<T extends StatefulWidget, R>
    extends State<T> {
  DocumentDto? _baseline;
  DocumentVersionConflict? _conflict;
  bool _submitting = false;
  String? _inlineError;

  /// The document the mutation is versioned against; null for create.
  DocumentDto? get initialDocument;

  String get title;
  String get submitLabel;
  Key get dialogKey;
  bool get destructive => false;
  double get maxWidth => 460;

  /// Whether the form has input worth a discard confirmation.
  bool get isDirty;

  /// Whether the submit button is enabled (beyond `!_submitting`).
  bool get canSubmit => true;

  /// Validates and collects the result; null keeps the dialog open.
  R? collect();

  Future<DocumentMutationOutcome> submit(R result, DocumentDto? baseline);

  /// Called on "Neu laden" with the server document; subclasses reseed what
  /// derives from it. Input fields are deliberately left alone.
  void reseed(DocumentDto current) {}

  Widget buildForm(BuildContext context);

  DocumentDto? get baseline => _baseline;

  @override
  void initState() {
    super.initState();
    _baseline = initialDocument;
  }

  /// [against] retries against the server document of a conflict: the
  /// dialog adopts it as its baseline and submits with its version.
  Future<void> performSubmit({DocumentDto? against}) async {
    if (_submitting) {
      return;
    }
    final result = collect();
    if (result == null) {
      return;
    }
    if (against != null) {
      _baseline = against;
    }
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final outcome = await submit(result, _baseline);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case DocumentMutationSucceeded():
        Navigator.of(context).pop(true);
      case DocumentMutationConflicted(:final conflict):
        setState(() {
          _submitting = false;
          _conflict = conflict;
        });
      case DocumentMutationRejected(:final message, :final isValidation):
        if (isValidation) {
          setState(() {
            _submitting = false;
            _inlineError = message;
          });
        } else {
          // Reported by the screen's action-feedback listener.
          Navigator.of(context).pop(false);
        }
    }
  }

  void _reseedFromConflict() {
    final conflict = _conflict;
    if (conflict == null) {
      return;
    }
    setState(() {
      _baseline = conflict.currentDocument;
      _conflict = null;
      _inlineError = null;
      reseed(conflict.currentDocument);
    });
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (confirmContext) => AlertDialog(
            key: const Key('documents-dialog-discard'),
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
                key: const Key('documents-dialog-discard-confirm'),
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
    final conflict = _conflict;
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
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: maxWidth),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                buildForm(context),
                if (_inlineError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  NxNotice(
                    key: const Key('documents-dialog-error'),
                    kind: NxNoticeKind.error,
                    message: _inlineError!,
                  ),
                ],
                if (conflict != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.component),
                  NxNotice(
                    key: const Key('documents-dialog-conflict'),
                    kind: NxNoticeKind.warning,
                    title: 'Zwischenzeitlich geändert',
                    message:
                        '„${conflict.currentDocument.title}" liegt auf dem '
                        'Server inzwischen in Version ${conflict.actualVersion} '
                        'vor (deine Basis war Version '
                        '${conflict.expectedVersion}), Status: '
                        '${documentStatusLabel(conflict.currentDocument.status)}. '
                        'Deine Eingaben bleiben erhalten.',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      OutlinedButton(
                        key: const Key('documents-dialog-reload'),
                        onPressed: _submitting ? null : _reseedFromConflict,
                        child: const Text('Neu laden'),
                      ),
                      FilledButton(
                        key: const Key('documents-dialog-retry'),
                        onPressed:
                            _submitting || !canSubmit
                                ? null
                                : () => performSubmit(
                                  against: conflict.currentDocument,
                                ),
                        child: const Text('Erneut speichern'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('documents-dialog-cancel'),
            onPressed:
                _submitting ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Abbrechen'),
          ),
          if (conflict == null)
            FilledButton(
              key: const Key('documents-dialog-submit'),
              style:
                  destructive
                      ? FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      )
                      : null,
              onPressed:
                  _submitting || !canSubmit ? null : () => performSubmit(),
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

String? _nullIfBlank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The optional audit reason (`p_reason`, ≤ 2000) offered by every
/// confirmation and decision dialog (§6.4–6.6, §12).
class _ReasonField extends StatelessWidget {
  const _ReasonField({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const Key('documents-dialog-reason'),
      controller: controller,
      maxLength: 2000,
      maxLines: 2,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Grund (optional, wird protokolliert)',
        counterText: '',
      ),
    );
  }
}

// --- create ------------------------------------------------------------------------

class _DocumentFormDialog extends StatefulWidget {
  const _DocumentFormDialog({required this.types, required this.onSubmit});

  final List<DocumentTypeDto> types;
  final Future<DocumentMutationOutcome> Function(DocumentFormResult result)
  onSubmit;

  @override
  State<_DocumentFormDialog> createState() => _DocumentFormDialogState();
}

class _DocumentFormDialogState
    extends _MutationDialogState<_DocumentFormDialog, DocumentFormResult> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DocumentFileSelection? _file;
  String? _documentTypeId;
  DateTime? _validFrom;
  DateTime? _validUntil;

  /// Once "Gültig bis" was edited by hand the type prefill stops overriding it.
  bool _validUntilTouched = false;

  @override
  DocumentDto? get initialDocument => null;

  @override
  String get title => 'Dokument hinzufügen';

  @override
  String get submitLabel => 'Anlegen';

  @override
  Key get dialogKey => const Key('documents-create-dialog');

  @override
  double get maxWidth => 560;

  @override
  bool get isDirty =>
      _title.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _file != null ||
      _documentTypeId != null ||
      _validFrom != null ||
      _validUntil != null;

  @override
  bool get canSubmit => _file != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  DocumentFormResult? collect() {
    final file = _file;
    if (!(_formKey.currentState?.validate() ?? false) || file == null) {
      return null;
    }
    return DocumentFormResult(
      title: _title.text.trim(),
      file: file,
      documentTypeId: _documentTypeId,
      validFrom: _validFrom,
      validUntil: _validUntil,
      notes: _nullIfBlank(_notes.text),
    );
  }

  @override
  Future<DocumentMutationOutcome> submit(
    DocumentFormResult result,
    DocumentDto? baseline,
  ) => widget.onSubmit(result);

  DocumentTypeDto? get _selectedType {
    for (final type in widget.types) {
      if (type.id == _documentTypeId) {
        return type;
      }
    }
    return null;
  }

  /// §6.1 (new in V2): a type with `defaultValidityMonths` plus a "Gültig ab"
  /// prefill "Gültig bis" — client logic only, the field exists for exactly
  /// this, and the value stays editable.
  void _applyValidityPrefill() {
    final months = _selectedType?.defaultValidityMonths;
    final from = _validFrom;
    if (_validUntilTouched || months == null || from == null) {
      return;
    }
    _validUntil = addDocumentValidityMonths(from, months);
  }

  @override
  Widget buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextFormField(
            key: const Key('documents-create-title'),
            controller: _title,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Titel',
              counterText: '',
            ),
            validator: _requiredValidator,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            key: const Key('documents-create-type'),
            value: _documentTypeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dokumenttyp'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Ohne Typ'),
              ),
              for (final type in widget.types)
                DropdownMenuItem<String?>(
                  value: type.id,
                  child: Text(
                    '${documentEntityTypeLabel(type.entityType)} · ${type.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged:
                (value) => setState(() {
                  _documentTypeId = value;
                  _applyValidityPrefill();
                }),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DateField(
            label: 'Gültig ab',
            value: _validFrom,
            onChanged:
                (value) => setState(() {
                  _validFrom = value;
                  _applyValidityPrefill();
                }),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DateField(
            label: 'Gültig bis',
            value: _validUntil,
            helperText:
                _selectedType?.defaultValidityMonths != null
                    ? 'Vorbelegt aus dem Typ '
                        '(${_selectedType!.defaultValidityMonths} Monate), '
                        'änderbar.'
                    : null,
            onChanged:
                (value) => setState(() {
                  _validUntil = value;
                  _validUntilTouched = true;
                }),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('documents-create-notes'),
            controller: _notes,
            maxLines: 2,
            maxLength: 10000,
            decoration: const InputDecoration(
              labelText: 'Notiz',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.component),
          _FilePickerField(onChanged: (file) => setState(() => _file = file)),
        ],
      ),
    );
  }
}

// --- new version ----------------------------------------------------------------------

class _DocumentVersionDialog extends StatefulWidget {
  const _DocumentVersionDialog({
    required this.document,
    required this.onSubmit,
  });

  final DocumentDto document;
  final DocumentDialogSubmit<DocumentFileSelection> onSubmit;

  @override
  State<_DocumentVersionDialog> createState() => _DocumentVersionDialogState();
}

class _DocumentVersionDialogState
    extends
        _MutationDialogState<_DocumentVersionDialog, DocumentFileSelection> {
  DocumentFileSelection? _file;

  @override
  DocumentDto? get initialDocument => widget.document;

  @override
  String get title => 'Neue Version hinzufügen';

  @override
  String get submitLabel => 'Version hinzufügen';

  @override
  Key get dialogKey => const Key('documents-version-dialog');

  @override
  double get maxWidth => 560;

  @override
  bool get isDirty => _file != null;

  @override
  bool get canSubmit => _file != null;

  @override
  DocumentFileSelection? collect() => _file;

  @override
  Future<DocumentMutationOutcome> submit(
    DocumentFileSelection result,
    DocumentDto? baseline,
  ) => widget.onSubmit(result, baseline!);

  @override
  Widget buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Die bisherige Version von „${widget.document.title}" bleibt '
          'unverändert erhalten und wird als ersetzt markiert. Ein Upload auf '
          'einen bereits belegten Pfad schlägt fehl — nichts wird '
          'überschrieben.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.component),
        _FilePickerField(
          onChanged: (selection) => setState(() => _file = selection),
        ),
      ],
    );
  }
}

// --- verify ---------------------------------------------------------------------------

class _DocumentVerifyDialog extends StatefulWidget {
  const _DocumentVerifyDialog({
    required this.document,
    required this.versionNo,
    required this.onSubmit,
  });

  final DocumentDto document;
  final int versionNo;
  final DocumentDialogSubmit<DocumentVerificationDecision> onSubmit;

  @override
  State<_DocumentVerifyDialog> createState() => _DocumentVerifyDialogState();
}

class _DocumentVerifyDialogState
    extends
        _MutationDialogState<
          _DocumentVerifyDialog,
          DocumentVerificationDecision
        > {
  final TextEditingController _note = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  DocumentVerificationOutcome _outcome = DocumentVerificationOutcome.verified;

  @override
  DocumentDto? get initialDocument => widget.document;

  @override
  String get title => 'Version ${widget.versionNo} prüfen';

  @override
  String get submitLabel => 'Speichern';

  @override
  Key get dialogKey => const Key('documents-verify-dialog');

  @override
  bool get isDirty =>
      _note.text.trim().isNotEmpty ||
      _reason.text.trim().isNotEmpty ||
      _outcome != DocumentVerificationOutcome.verified;

  @override
  void dispose() {
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  DocumentVerificationDecision collect() {
    return DocumentVerificationDecision(
      outcome: _outcome,
      note: _nullIfBlank(_note.text),
      reason: _nullIfBlank(_reason.text),
    );
  }

  @override
  Future<DocumentMutationOutcome> submit(
    DocumentVerificationDecision result,
    DocumentDto? baseline,
  ) => widget.onSubmit(result, baseline!);

  @override
  Widget buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Die Prüfung gilt für diese Version. Ablauf und Verifikation sind '
          'getrennt: ein abgelaufenes Dokument kann verifiziert sein, ein '
          'verifiziertes kann ablaufen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.component),
        RadioListTile<DocumentVerificationOutcome>(
          key: const Key('documents-verify-outcome-verified'),
          contentPadding: EdgeInsets.zero,
          value: DocumentVerificationOutcome.verified,
          groupValue: _outcome,
          title: const Text('Verifizieren'),
          onChanged:
              (value) => setState(
                () => _outcome = value ?? DocumentVerificationOutcome.verified,
              ),
        ),
        RadioListTile<DocumentVerificationOutcome>(
          key: const Key('documents-verify-outcome-rejected'),
          contentPadding: EdgeInsets.zero,
          value: DocumentVerificationOutcome.rejected,
          groupValue: _outcome,
          title: const Text('Ablehnen'),
          onChanged:
              (value) => setState(
                () => _outcome = value ?? DocumentVerificationOutcome.rejected,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const Key('documents-dialog-note'),
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Prüfnotiz'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReasonField(controller: _reason, onChanged: (_) => setState(() {})),
      ],
    );
  }
}

// --- supersede ------------------------------------------------------------------------

class _DocumentSupersedeDialog extends StatefulWidget {
  const _DocumentSupersedeDialog({
    required this.document,
    required this.candidates,
    required this.onSubmit,
  });

  final DocumentDto document;
  final List<DocumentDto> candidates;
  final DocumentDialogSubmit<DocumentSupersedeDecision> onSubmit;

  @override
  State<_DocumentSupersedeDialog> createState() =>
      _DocumentSupersedeDialogState();
}

class _DocumentSupersedeDialogState
    extends
        _MutationDialogState<
          _DocumentSupersedeDialog,
          DocumentSupersedeDecision
        > {
  final TextEditingController _reason = TextEditingController();
  DocumentDto? _successor;

  @override
  DocumentDto? get initialDocument => widget.document;

  @override
  String get title => 'Dokument ersetzen';

  @override
  String get submitLabel => 'Ersetzen';

  @override
  Key get dialogKey => const Key('documents-supersede-dialog');

  @override
  bool get destructive => true;

  @override
  bool get isDirty => _successor != null || _reason.text.trim().isNotEmpty;

  @override
  bool get canSubmit => _successor != null;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  DocumentSupersedeDecision? collect() {
    final successor = _successor;
    if (successor == null) {
      return null;
    }
    return DocumentSupersedeDecision(
      successor: successor,
      reason: _nullIfBlank(_reason.text),
    );
  }

  @override
  Future<DocumentMutationOutcome> submit(
    DocumentSupersedeDecision result,
    DocumentDto? baseline,
  ) => widget.onSubmit(result, baseline!);

  @override
  Widget buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '„${widget.document.title}" wird als ersetzt markiert und zählt '
          'danach nicht mehr für Anforderungen. Das Nachfolgedokument '
          'übernimmt diese Rolle.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.component),
        DropdownButtonFormField<String>(
          key: const Key('documents-supersede-successor'),
          value: _successor?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Nachfolgedokument'),
          items: <DropdownMenuItem<String>>[
            for (final candidate in widget.candidates)
              DropdownMenuItem<String>(
                value: candidate.id,
                child: Text(candidate.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _successor = widget.candidates.firstWhere(
                (candidate) => candidate.id == value,
              );
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReasonField(controller: _reason, onChanged: (_) => setState(() {})),
      ],
    );
  }
}

// --- archive --------------------------------------------------------------------------

class _DocumentArchiveDialog extends StatefulWidget {
  const _DocumentArchiveDialog({
    required this.document,
    required this.onSubmit,
  });

  final DocumentDto document;
  final DocumentDialogSubmit<DocumentArchiveDecision> onSubmit;

  @override
  State<_DocumentArchiveDialog> createState() => _DocumentArchiveDialogState();
}

class _DocumentArchiveDialogState
    extends
        _MutationDialogState<_DocumentArchiveDialog, DocumentArchiveDecision> {
  final TextEditingController _reason = TextEditingController();

  @override
  DocumentDto? get initialDocument => widget.document;

  @override
  String get title => 'Dokument archivieren';

  @override
  String get submitLabel => 'Archivieren';

  @override
  Key get dialogKey => const Key('documents-archive-dialog');

  @override
  bool get destructive => true;

  @override
  bool get isDirty => _reason.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  DocumentArchiveDecision collect() =>
      DocumentArchiveDecision(reason: _nullIfBlank(_reason.text));

  @override
  Future<DocumentMutationOutcome> submit(
    DocumentArchiveDecision result,
    DocumentDto? baseline,
  ) => widget.onSubmit(result, baseline!);

  @override
  Widget buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '„${widget.document.title}" wird archiviert. Archivierte Dokumente '
          'zählen nicht mehr für Anforderungen und lassen sich nicht wieder '
          'aktivieren. Gelöscht wird nichts — die Historie bleibt vollständig '
          'erhalten.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.component),
        _ReasonField(controller: _reason, onChanged: (_) => setState(() {})),
      ],
    );
  }
}

// --- file picker / date field ---------------------------------------------------------

/// The file picker shared by the create and add-version dialogs.
///
/// Bytes are read here and uploaded by the controller through
/// [DocumentUploadPort]; the size limit is checked eagerly so a user learns
/// about an oversized file before waiting for a failed upload.
class _FilePickerField extends StatefulWidget {
  const _FilePickerField({required this.onChanged});

  final ValueChanged<DocumentFileSelection?> onChanged;

  @override
  State<_FilePickerField> createState() => _FilePickerFieldState();
}

class _FilePickerFieldState extends State<_FilePickerField> {
  DocumentFileSelection? _selection;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final file = await openFile();
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > DocumentUploadPort.maxByteSize) {
        setState(() {
          _selection = null;
          _error = 'Die Datei ist größer als 50 MB.';
        });
        widget.onChanged(null);
        return;
      }
      if (bytes.isEmpty) {
        setState(() {
          _selection = null;
          _error = 'Die Datei ist leer.';
        });
        widget.onChanged(null);
        return;
      }
      final selection = DocumentFileSelection(
        bytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeOf(file.mimeType, file.name),
      );
      setState(() {
        _selection = selection;
        _error = null;
      });
      widget.onChanged(selection);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Datei', style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Die Datei wird in den geschützten Dokumentenspeicher geladen. Der '
          'Server prüft anschließend, ob dort wirklich dieselbe Datei liegt.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('documents-file-pick'),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(selection == null ? 'Datei wählen' : 'Andere Datei'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                selection == null
                    ? 'Keine Datei gewählt'
                    : '${selection.filename} '
                        '(${formatDocumentByteSize(selection.byteSize)})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.semanticColors.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// `XFile.mimeType` is null on most desktop pickers, so the extension is the
/// fallback. The server records what it is told here; it never sniffs.
String _mimeTypeOf(String? reported, String filename) {
  final declared = reported?.trim();
  if (declared != null && declared.isNotEmpty) {
    return declared;
  }
  final dot = filename.lastIndexOf('.');
  final extension = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final DateTime? value;
  final String? helperText;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, helperText: helperText),
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
