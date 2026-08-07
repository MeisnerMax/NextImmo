import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/application/document_repository.dart';
import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/responsive_constraints.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// The shared documents_compliance dialogs (`DUP-007`): the property-scoped
/// archive (SCR-020) and the workspace-wide workplace (SCR-051) run the exact
/// same create / add-version / confirm / verify / supersede / archive flows, so
/// the flows live here once and the screens only decide *when* to open them.
///
/// Two contract facts shape every dialog in this file:
///
/// * **The file is picked here and uploaded by the controller.** The dialog
///   only carries the chosen bytes; `DocumentUploadPort` puts them in the
///   private bucket and returns the declaration the create/add-version commands
///   take. Until that port existed this form could only ask a user to type a
///   storage path and a sha256 by hand, which no real workflow could satisfy.
/// * **There is no delete.** `OPN-DOM-005` is open and `archived` is terminal,
///   so the destructive-looking action is archiving — behind a confirmation,
///   never a single click.

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
  const DocumentVerificationDecision({required this.outcome, this.note});

  final DocumentVerificationOutcome outcome;
  final String? note;
}

Future<DocumentFormResult?> showDocumentFormDialog({
  required BuildContext context,
  List<DocumentTypeDto> types = const <DocumentTypeDto>[],
}) {
  return showDialog<DocumentFormResult>(
    context: context,
    builder: (dialogContext) => _DocumentFormDialog(types: types),
  );
}

Future<DocumentFileSelection?> showDocumentVersionDialog({
  required BuildContext context,
  required String documentTitle,
}) {
  return showDialog<DocumentFileSelection>(
    context: context,
    builder:
        (dialogContext) => _DocumentVersionDialog(documentTitle: documentTitle),
  );
}

/// MIG-BND-003. Confirming compares the declared object against what really
/// landed in the bucket, and a mismatch drives the document to `rejected` — a
/// real outcome, so the user is told that before running it.
Future<bool> showDocumentConfirmContentDialog({
  required BuildContext context,
  required String documentTitle,
  required int versionNo,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Upload bestätigen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 460,
            ),
            child: Text(
              'Version $versionNo von "$documentTitle" wird gegen die '
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
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Prüfen und bestätigen'),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

Future<DocumentVerificationDecision?> showDocumentVerifyDialog({
  required BuildContext context,
  required int versionNo,
}) {
  return showDialog<DocumentVerificationDecision>(
    context: context,
    builder: (dialogContext) => _DocumentVerifyDialog(versionNo: versionNo),
  );
}

/// Archiving is terminal and there is no delete path, so it never happens on a
/// single click.
Future<bool> showDocumentArchiveDialog({
  required BuildContext context,
  required DocumentDto document,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Dokument archivieren'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 460,
            ),
            child: Text(
              '"${document.title}" wird archiviert. Archivierte Dokumente '
              'zählen nicht mehr für Anforderungen und lassen sich nicht '
              'wieder aktivieren. Gelöscht wird nichts — die Historie bleibt '
              'vollständig erhalten.',
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Archivieren'),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

/// Superseding needs a successor, so this returns the chosen document rather
/// than a bare confirmation.
Future<DocumentDto?> showDocumentSupersedeDialog({
  required BuildContext context,
  required DocumentDto document,
  required List<DocumentDto> candidates,
}) {
  return showDialog<DocumentDto>(
    context: context,
    builder:
        (dialogContext) =>
            _DocumentSupersedeDialog(document: document, candidates: candidates),
  );
}

/// Explicit conflict resolution: both versions are shown and the refreshed
/// record is offered, instead of silently overwriting or silently failing.
Future<void> showDocumentVersionConflictDialog({
  required BuildContext context,
  required DocumentVersionConflict conflict,
  required VoidCallback onReload,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Zwischenzeitlich geändert'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 420,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '"${conflict.currentDocument.title}" wurde geändert, seit du '
                  'es geladen hast.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Deine Version: ${conflict.expectedVersion} · '
                  'Aktuelle Version: ${conflict.actualVersion}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Text(
                      'Aktueller Stand: ',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    DocumentStatusBadge(
                      status: conflict.currentDocument.status,
                    ),
                  ],
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

/// A minted signed URL is short-lived by design, so it is presented with its
/// expiry rather than silently handed to a launcher.
Future<void> showDocumentSignedUrlDialog({
  required BuildContext context,
  required SignedDocumentUrl signedUrl,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Download-Link'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(
              dialogContext,
              maxWidth: 520,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Der Link gilt '
                  '${signedUrl.appliedTtl.inMinutes} Minuten und läuft um '
                  '${_formatTime(signedUrl.expiresAt)} ab.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  signedUrl.url,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
  );
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _DocumentFormDialog extends StatefulWidget {
  const _DocumentFormDialog({required this.types});

  final List<DocumentTypeDto> types;

  @override
  State<_DocumentFormDialog> createState() => _DocumentFormDialogState();
}

class _DocumentFormDialogState extends State<_DocumentFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DocumentFileSelection? _file;
  String? _documentTypeId;
  DateTime? _validFrom;
  DateTime? _validUntil;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final file = _file;
    if (!(_formKey.currentState?.validate() ?? false) || file == null) {
      return;
    }
    Navigator.of(context).pop(
      DocumentFormResult(
        title: _title.text.trim(),
        file: file,
        documentTypeId: _documentTypeId,
        validFrom: _validFrom,
        validUntil: _validUntil,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dokument hinzufügen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Titel'),
                  validator:
                      (value) =>
                          (value ?? '').trim().isEmpty
                              ? 'Bitte einen Titel angeben.'
                              : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  value: _documentTypeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Dokumenttyp'),
                  items: <DropdownMenuItem<String>>[
                    for (final type in widget.types)
                      DropdownMenuItem<String>(
                        value: type.id,
                        child: Text(
                          type.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _documentTypeId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateField(
                  label: 'Gültig ab',
                  value: _validFrom,
                  onChanged: (value) => setState(() => _validFrom = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateField(
                  label: 'Gültig bis',
                  value: _validUntil,
                  onChanged: (value) => setState(() => _validUntil = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
                const SizedBox(height: AppSpacing.component),
                _FilePickerField(
                  onChanged: (file) => setState(() => _file = file),
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
          // Disabled until a file is chosen: a document without content is not
          // a state this contract has.
          onPressed: _file == null ? null : _submit,
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}

class _DocumentVersionDialog extends StatefulWidget {
  const _DocumentVersionDialog({required this.documentTitle});

  final String documentTitle;

  @override
  State<_DocumentVersionDialog> createState() => _DocumentVersionDialogState();
}

class _DocumentVersionDialogState extends State<_DocumentVersionDialog> {
  DocumentFileSelection? _file;

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return AlertDialog(
      title: const Text('Neue Version hinzufügen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Die bisherige Version von "${widget.documentTitle}" bleibt '
                'unverändert erhalten und wird als ersetzt markiert.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.component),
              _FilePickerField(
                onChanged: (selection) => setState(() => _file = selection),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: file == null ? null : () => Navigator.of(context).pop(file),
          child: const Text('Version hinzufügen'),
        ),
      ],
    );
  }
}

class _DocumentVerifyDialog extends StatefulWidget {
  const _DocumentVerifyDialog({required this.versionNo});

  final int versionNo;

  @override
  State<_DocumentVerifyDialog> createState() => _DocumentVerifyDialogState();
}

class _DocumentVerifyDialogState extends State<_DocumentVerifyDialog> {
  final TextEditingController _note = TextEditingController();
  DocumentVerificationOutcome _outcome = DocumentVerificationOutcome.verified;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Version ${widget.versionNo} prüfen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Die Prüfung gilt für diese Version. Ablauf und Verifikation '
              'sind getrennt: ein abgelaufenes Dokument kann verifiziert sein, '
              'ein verifiziertes kann ablaufen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.component),
            RadioListTile<DocumentVerificationOutcome>(
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
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Prüfnotiz'),
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
              () => Navigator.of(context).pop(
                DocumentVerificationDecision(
                  outcome: _outcome,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
              ),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _DocumentSupersedeDialog extends StatefulWidget {
  const _DocumentSupersedeDialog({
    required this.document,
    required this.candidates,
  });

  final DocumentDto document;
  final List<DocumentDto> candidates;

  @override
  State<_DocumentSupersedeDialog> createState() =>
      _DocumentSupersedeDialogState();
}

class _DocumentSupersedeDialogState extends State<_DocumentSupersedeDialog> {
  DocumentDto? _successor;

  @override
  Widget build(BuildContext context) {
    final successor = _successor;
    return AlertDialog(
      title: const Text('Dokument ersetzen'),
      content: SizedBox(
        width: ResponsiveConstraints.dialogWidth(context, maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '"${widget.document.title}" wird als ersetzt markiert und zählt '
              'danach nicht mehr für Anforderungen. Das Nachfolgedokument '
              'übernimmt diese Rolle.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<String>(
              value: successor?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nachfolgedokument'),
              items: <DropdownMenuItem<String>>[
                for (final candidate in widget.candidates)
                  DropdownMenuItem<String>(
                    value: candidate.id,
                    child: Text(
                      candidate.title,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              successor == null
                  ? null
                  : () => Navigator.of(context).pop(successor),
          child: const Text('Ersetzen'),
        ),
      ],
    );
  }
}

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
