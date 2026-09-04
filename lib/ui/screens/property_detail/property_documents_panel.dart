import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/document_mutation_outcome.dart';
import '../../../features/documents_compliance/application/document_repository.dart';
import '../../../features/documents_compliance/application/property_documents_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_list_skeleton.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_section_header.dart';
import '../../theme/app_theme.dart';
import '../docs/widgets/document_content_opener.dart';
import '../docs/widgets/document_detail_panel.dart';
import '../docs/widgets/document_dialogs.dart';
import '../docs/widgets/document_notices.dart';
import '../docs/widgets/document_requirement_table.dart';
import '../docs/widgets/document_table.dart';
import '../docs/widgets/document_type_registry.dart';

/// The documents of one property (SCR-020, Wave 2, Arbeitspaket 3), built on
/// the `documents_compliance` feature contract through the backend-selected
/// providers of `lib/app_backend_wiring.dart`.
///
/// Deliberately separate from `PropertyDocumentsScreen`: that file is the
/// property workspace's tab host and reaches into legacy, `dart:io`-bound
/// screens, while this panel touches nothing but the feature contract. That is
/// what makes it mountable on its own additive cloud route, where the local
/// `AppScaffold` — and therefore the tab host — never exists.
class PropertyDocumentsPanel extends ConsumerStatefulWidget {
  const PropertyDocumentsPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyDocumentsPanel> createState() =>
      _PropertyDocumentsPanelState();
}

class _PropertyDocumentsPanelState
    extends ConsumerState<PropertyDocumentsPanel> {
  Set<DocumentColumn> _columns = defaultDocumentColumns;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      propertyDocumentsControllerProvider(widget.propertyId),
    );
    final controller = ref.read(
      propertyDocumentsControllerProvider(widget.propertyId).notifier,
    );
    final types =
        ref.watch(documentTypeRegistryProvider).valueOrNull ??
        const <DocumentTypeDto>[];
    _listenForActionFeedback(controller);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NxPageHeader(
          title: 'Dokumente',
          subtitle:
              'Nachweise dieses Objekts: Anforderungen, Versionen und '
              'Verifikation.',
          primaryAction: Tooltip(
            message:
                controller.canMutate
                    ? 'Ein Dokument dieses Objekts anlegen'
                    : 'Benötigt die Berechtigung (document.manage)',
            child: FilledButton.icon(
              key: const Key('property-documents-create'),
              onPressed:
                  controller.canMutate
                      ? () => _createDocument(controller, types)
                      : null,
              icon: const Icon(Icons.add),
              label: const Text('Dokument hinzufügen'),
            ),
          ),
          secondaryActions: <Widget>[
            PopupMenuButton<DocumentColumn>(
              tooltip: 'Spalten wählen',
              icon: const Icon(Icons.view_column_outlined),
              itemBuilder:
                  (context) => <PopupMenuEntry<DocumentColumn>>[
                    for (final column in DocumentColumn.values)
                      CheckedPopupMenuItem<DocumentColumn>(
                        value: column,
                        checked: _columns.contains(column),
                        child: Text(documentColumnLabel(column)),
                      ),
                  ],
              onSelected: (column) {
                setState(() {
                  final next = <DocumentColumn>{..._columns};
                  if (!next.remove(column)) {
                    next.add(column);
                  }
                  _columns = next;
                });
              },
            ),
            OutlinedButton.icon(
              onPressed:
                  () => controller.setIncludeInactive(!state.includeInactive),
              icon: Icon(
                state.includeInactive
                    ? Icons.visibility_off_outlined
                    : Icons.history_outlined,
              ),
              label: Text(
                state.includeInactive
                    ? 'Nur aktive zeigen'
                    : 'Ersetzte und archivierte zeigen',
              ),
            ),
            OutlinedButton.icon(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        if (controller.isReadOnlyBackend) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          const DocumentReadOnlyNotice(),
        ],
        if (state.actionPhase ==
            PropertyDocumentsActionPhase.contentRejected) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          _ContentRejectedNotice(
            message: state.actionMessage,
            onDismiss: controller.clearAction,
          ),
        ],
        const SizedBox(height: AppSpacing.section),
        const NxSectionHeader(
          title: 'Anforderungen',
          description:
              'Abgeleitet aus den Regeln des Arbeitsbereichs und den '
              'verknüpften Dokumenten.',
          compact: true,
        ),
        const SizedBox(height: AppSpacing.component),
        _buildRequirements(state, controller),
        const SizedBox(height: AppSpacing.section),
        const NxSectionHeader(
          title: 'Vorhandene Dokumente',
          description: 'Hochgeladene Nachweise mit Version und Verifikation.',
          compact: true,
        ),
        const SizedBox(height: AppSpacing.component),
        _buildArchive(context, state, controller, types),
      ],
    );
  }

  void _listenForActionFeedback(PropertyDocumentsController controller) {
    ref.listen<PropertyDocumentsState>(
      propertyDocumentsControllerProvider(widget.propertyId),
      (previous, next) {
        if (previous?.actionPhase == next.actionPhase) {
          return;
        }
        switch (next.actionPhase) {
          case PropertyDocumentsActionPhase.conflict:
            // Owned by the dialog that submitted (banner + "Neu laden" /
            // "Erneut speichern"), or by the row action that reloads.
            return;
          case PropertyDocumentsActionPhase.contentRejected:
            // Kept on screen as an inline notice instead of a snackbar that
            // disappears: a rejected upload needs a follow-up action.
            return;
          case PropertyDocumentsActionPhase.succeeded:
          case PropertyDocumentsActionPhase.readOnly:
          case PropertyDocumentsActionPhase.forbidden:
          case PropertyDocumentsActionPhase.failed:
            final message = next.actionMessage;
            if (message == null) {
              return;
            }
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
            controller.clearAction();
          case PropertyDocumentsActionPhase.idle:
          case PropertyDocumentsActionPhase.submitting:
            return;
        }
      },
    );
  }

  Widget _buildRequirements(
    PropertyDocumentsState state,
    PropertyDocumentsController controller,
  ) {
    switch (state.requirementPhase) {
      case PropertyDocumentsRequirementPhase.idle:
        return const SizedBox.shrink();
      case PropertyDocumentsRequirementPhase.loading:
        return const NxCard(
          key: Key('property-documents-requirements-loading'),
          child: NxListSkeleton(rows: 3),
        );
      case PropertyDocumentsRequirementPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-documents-requirements-forbidden'),
          title: 'Kein Zugriff auf Anforderungen',
          description:
              'Die Anforderungen dieses Objekts benötigen die Berechtigung '
              '(document.read).',
          icon: Icons.lock_outline,
        );
      case PropertyDocumentsRequirementPhase.error:
        return NxEmptyState.error(
          key: const Key('property-documents-requirements-error'),
          title: 'Anforderungen konnten nicht geladen werden',
          description:
              'Beim Auswerten der Anforderungen ist ein Fehler aufgetreten. '
              'Bitte versuche es erneut.',
          onRetry: controller.load,
        );
      case PropertyDocumentsRequirementPhase.empty:
        return const NxEmptyState(
          title: 'Keine Anforderungen hinterlegt',
          description:
              'Für dieses Objekt sind keine Pflichtdokumente definiert. '
              'Anforderungen werden im Arbeitsbereich gepflegt.',
          icon: Icons.rule_folder_outlined,
        );
      case PropertyDocumentsRequirementPhase.ready:
        return DocumentRequirementTable(requirements: state.requirements);
    }
  }

  Widget _buildArchive(
    BuildContext context,
    PropertyDocumentsState state,
    PropertyDocumentsController controller,
    List<DocumentTypeDto> types,
  ) {
    switch (state.listPhase) {
      case PropertyDocumentsListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Dokumente werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um den Bestand zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case PropertyDocumentsListPhase.loading:
        return const NxCard(
          key: Key('property-documents-loading'),
          child: NxListSkeleton(rows: 6),
        );
      case PropertyDocumentsListPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-documents-forbidden'),
          title: 'Kein Zugriff auf Dokumente',
          description:
              'Die Dokumente dieses Objekts benötigen die Berechtigung '
              '(document.read).',
          icon: Icons.lock_outline,
        );
      case PropertyDocumentsListPhase.error:
        return NxEmptyState.error(
          key: const Key('property-documents-error'),
          title: 'Dokumente konnten nicht geladen werden',
          description:
              'Beim Laden der Dokumente ist ein Fehler aufgetreten. Bitte '
              'versuche es erneut.',
          onRetry: controller.load,
        );
      case PropertyDocumentsListPhase.empty:
        return NxEmptyState(
          title: 'Noch keine Dokumente',
          description:
              'Füge das erste Dokument dieses Objekts hinzu — Nachweise, '
              'Verträge und Gutachten liegen hier zentral.',
          icon: Icons.folder_open_outlined,
          primaryAction: Tooltip(
            message:
                controller.canMutate
                    ? 'Ein Dokument dieses Objekts anlegen'
                    : 'Benötigt die Berechtigung (document.manage)',
            child: FilledButton.icon(
              onPressed:
                  controller.canMutate
                      ? () => _createDocument(controller, types)
                      : null,
              icon: const Icon(Icons.add),
              label: const Text('Dokument hinzufügen'),
            ),
          ),
        );
      case PropertyDocumentsListPhase.ready:
        return _buildSplit(context, state, controller, types);
    }
  }

  Widget _buildSplit(
    BuildContext context,
    PropertyDocumentsState state,
    PropertyDocumentsController controller,
    List<DocumentTypeDto> types,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= AppLayout.splitViewMinWidth;
        final selected = _selectedDocument(state);
        final list = _buildList(state, controller, types);
        final detail = DocumentDetailPanel(
          document: selected,
          versions: state.versions,
          typeName:
              selected == null
                  ? null
                  : documentTypeName(types, selected.documentTypeId),
          canMutate: controller.canMutate,
          canVerify: controller.canVerify,
          readOnlyBackend: controller.isReadOnlyBackend,
          showCloseAction: !split,
          onClose: () => controller.selectDocument(null),
          onAddVersion: () => _addVersion(controller, selected),
          onConfirmContent:
              (version) => _confirmContent(controller, selected, version),
          onVerify: (version) => _verify(controller, selected, version),
          onSupersede: () => _supersede(controller, state, selected),
          onArchive: () => _archive(controller, selected),
          onOpen: (version) => _open(controller, selected, version),
        );

        if (split) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 3, child: list),
              const SizedBox(width: AppSpacing.component),
              Expanded(flex: 2, child: detail),
            ],
          );
        }
        return selected != null ? detail : list;
      },
    );
  }

  Widget _buildList(
    PropertyDocumentsState state,
    PropertyDocumentsController controller,
    List<DocumentTypeDto> types,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DocumentTable(
          documents: state.documents,
          columns: _columns,
          // The split view's list pane is narrower than a full page; keep it a
          // table there instead of dropping to the phone tile list.
          mobileBreakpoint: 640,
          selectedDocumentId: state.selectedDocumentId,
          onSelect: (document) => controller.selectDocument(document.id),
          typeNameResolver:
              (documentTypeId) => documentTypeName(types, documentTypeId) ?? '',
        ),
        if (state.hasMore) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          Center(
            child: OutlinedButton.icon(
              onPressed: state.loadingMore ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(
                state.loadingMore ? 'Lädt …' : 'Weitere Dokumente laden',
              ),
            ),
          ),
        ],
      ],
    );
  }

  DocumentDto? _selectedDocument(PropertyDocumentsState state) {
    final selectedId = state.selectedDocumentId;
    if (selectedId == null) {
      return null;
    }
    for (final document in state.documents) {
      if (document.id == selectedId) {
        return document;
      }
    }
    return null;
  }

  Future<void> _createDocument(
    PropertyDocumentsController controller,
    List<DocumentTypeDto> types,
  ) {
    return showDocumentFormDialog(
      context: context,
      types: types
          .where(
            (type) =>
                type.entityType == DocumentLinkEntityType.property &&
                type.isActive,
          )
          .toList(growable: false),
      onSubmit:
          (result) => controller.createDocument(
            title: result.title,
            file: result.file,
            documentTypeId: result.documentTypeId,
            validFrom: result.validFrom,
            validUntil: result.validUntil,
            notes: result.notes,
          ),
    );
  }

  Future<void> _addVersion(
    PropertyDocumentsController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentVersionDialog(
      context: context,
      document: document,
      onSubmit:
          (file, current) => controller.addVersion(
            documentId: current.id,
            expectedVersion: current.version,
            nextVersionNo: current.currentVersionNo + 1,
            file: file,
          ),
    );
  }

  /// No form input, so a conflict reloads the server state and says so.
  Future<void> _confirmContent(
    PropertyDocumentsController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    final confirmed = await showDocumentConfirmContentDialog(
      context: context,
      documentTitle: document.title,
      versionNo: version.versionNo,
    );
    if (!confirmed) {
      return;
    }
    final outcome = await controller.confirmContent(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
    );
    if (outcome is DocumentMutationConflicted && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '„${document.title}" wurde zwischenzeitlich geändert. Der aktuelle '
            'Stand wurde geladen.',
          ),
        ),
      );
      controller.clearAction();
      await controller.load();
      await controller.selectDocument(document.id);
    }
  }

  Future<void> _verify(
    PropertyDocumentsController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentVerifyDialog(
      context: context,
      document: document,
      versionNo: version.versionNo,
      onSubmit:
          (decision, current) => controller.verifyVersion(
            documentId: current.id,
            versionNo: version.versionNo,
            expectedVersion: current.version,
            outcome: decision.outcome,
            note: decision.note,
            reason: decision.reason,
          ),
    );
  }

  Future<void> _supersede(
    PropertyDocumentsController controller,
    PropertyDocumentsState state,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final candidates = state.documents
        .where(
          (candidate) =>
              candidate.id != document.id && candidate.status.isActive,
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Es gibt kein anderes aktives Dokument, das dieses ersetzen '
            'könnte.',
          ),
        ),
      );
      return;
    }
    await showDocumentSupersedeDialog(
      context: context,
      document: document,
      candidates: candidates,
      onSubmit:
          (decision, current) => controller.transitionStatus(
            documentId: current.id,
            expectedVersion: current.version,
            transition: DocumentStatusTransition.supersede,
            supersededByDocumentId: decision.successor.id,
            reason: decision.reason,
          ),
    );
  }

  Future<void> _archive(
    PropertyDocumentsController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentArchiveDialog(
      context: context,
      document: document,
      onSubmit:
          (decision, current) => controller.transitionStatus(
            documentId: current.id,
            expectedVersion: current.version,
            transition: DocumentStatusTransition.archive,
            reason: decision.reason,
          ),
    );
  }

  /// `PROPERTY_DOCUMENTS_V2.md` §8 / DOCUMENTS-V2 §6.7: the signed URL is
  /// minted on the click, handed to the launcher and forgotten. Same flow,
  /// same security, as the workspace register.
  Future<void> _open(
    PropertyDocumentsController controller,
    DocumentDto? document,
    DocumentVersionDto? version,
  ) async {
    if (document == null) {
      return;
    }
    final signedUrl = await controller.resolveDownloadUrl(
      documentId: document.id,
      versionNo: version?.versionNo,
    );
    if (signedUrl == null || !mounted) {
      return;
    }
    final opened = await openSignedDocumentUrl(
      signedUrl,
      ref.read(documentUrlLauncherProvider),
    );
    if (!opened && mounted) {
      reportDocumentOpenFailure(context);
    }
  }
}

/// MIG-BND-003 made visible: `confirm_document_content` succeeds in both
/// outcomes, so a rejection must not read as success — and must not vanish
/// with a snackbar either, because it needs a new upload.
class _ContentRejectedNotice extends StatelessWidget {
  const _ContentRejectedNotice({
    required this.message,
    required this.onDismiss,
  });

  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return NxNotice(
      key: const Key('property-documents-content-rejected'),
      kind: NxNoticeKind.warning,
      icon: Icons.report_problem_outlined,
      title: 'Upload abgelehnt',
      message:
          message ??
          'Der hochgeladene Inhalt stimmt nicht mit den angegebenen Daten '
              'überein. Das Dokument wurde abgelehnt und muss neu '
              'hochgeladen werden.',
      action: TextButton(
        onPressed: onDismiss,
        child: const Text('Hinweis schließen'),
      ),
    );
  }
}
