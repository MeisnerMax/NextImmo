import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/document_repository.dart';
import '../../../features/documents_compliance/application/property_documents_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_section_header.dart';
import '../../theme/app_theme.dart';
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
  /// Width at which the archive and one document's detail fit side by side
  /// without either becoming unreadably narrow.
  static const double _splitViewBreakpoint = 1200;

  Set<DocumentColumn> _columns = defaultDocumentColumns;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(propertyDocumentsControllerProvider(widget.propertyId));
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
          primaryAction: FilledButton.icon(
            onPressed:
                controller.canMutate
                    ? () => _createDocument(controller, types)
                    : null,
            icon: const Icon(Icons.add),
            label: const Text('Dokument hinzufügen'),
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
        if (state.actionPhase == PropertyDocumentsActionPhase.contentRejected)
          ...<Widget>[
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
            final conflict = next.versionConflict;
            if (conflict == null) {
              return;
            }
            unawaited(
              showDocumentVersionConflictDialog(
                context: context,
                conflict: conflict,
                onReload: () {
                  controller.clearAction();
                  controller.load();
                  final selectedId = next.selectedDocumentId;
                  if (selectedId != null) {
                    controller.selectDocument(selectedId);
                  }
                },
              ),
            );
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
        return const NxDataTableShell(loading: true, child: SizedBox.shrink());
      case PropertyDocumentsRequirementPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Anforderungen',
          description:
              'Dein Konto darf die Dokumentanforderungen dieses Objekts nicht '
              'sehen. Wende dich an eine Administratorin oder einen '
              'Administrator des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case PropertyDocumentsRequirementPhase.error:
        return NxEmptyState(
          title: 'Anforderungen konnten nicht geladen werden',
          description:
              'Beim Auswerten der Anforderungen ist ein Fehler aufgetreten. '
              'Bitte versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
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
        return const NxDataTableShell(loading: true, child: SizedBox.shrink());
      case PropertyDocumentsListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Dokumente',
          description:
              'Dein Konto darf die Dokumente dieses Objekts nicht sehen. '
              'Wende dich an eine Administratorin oder einen Administrator '
              'des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case PropertyDocumentsListPhase.error:
        return NxEmptyState(
          title: 'Dokumente konnten nicht geladen werden',
          description:
              'Beim Laden der Dokumente ist ein Fehler aufgetreten. Bitte '
              'versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case PropertyDocumentsListPhase.empty:
        return NxEmptyState(
          title: 'Noch keine Dokumente',
          description:
              'Füge das erste Dokument dieses Objekts hinzu — Nachweise, '
              'Verträge und Gutachten liegen hier zentral.',
          icon: Icons.folder_open_outlined,
          primaryAction: FilledButton.icon(
            onPressed:
                controller.canMutate
                    ? () => _createDocument(controller, types)
                    : null,
            icon: const Icon(Icons.add),
            label: const Text('Dokument hinzufügen'),
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
        final split = constraints.maxWidth >= _splitViewBreakpoint;
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
          onDownload: (version) => _download(controller, selected, version),
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
  ) async {
    final result = await showDocumentFormDialog(
      context: context,
      types:
          types
              .where(
                (type) =>
                    type.entityType == DocumentLinkEntityType.property &&
                    type.isActive,
              )
              .toList(growable: false),
    );
    if (result == null) {
      return;
    }
    await controller.createDocument(result.toDraft());
  }

  Future<void> _addVersion(
    PropertyDocumentsController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final content = await showDocumentVersionDialog(
      context: context,
      documentTitle: document.title,
    );
    if (content == null) {
      return;
    }
    await controller.addVersion(
      documentId: document.id,
      expectedVersion: document.version,
      content: content.toDraft(),
    );
  }

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
    await controller.confirmContent(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
    );
  }

  Future<void> _verify(
    PropertyDocumentsController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    final decision = await showDocumentVerifyDialog(
      context: context,
      versionNo: version.versionNo,
    );
    if (decision == null) {
      return;
    }
    await controller.verifyVersion(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
      outcome: decision.outcome,
      note: decision.note,
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
    final candidates =
        state.documents
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
    final successor = await showDocumentSupersedeDialog(
      context: context,
      document: document,
      candidates: candidates,
    );
    if (successor == null) {
      return;
    }
    await controller.transitionStatus(
      documentId: document.id,
      expectedVersion: document.version,
      transition: DocumentStatusTransition.supersede,
      supersededByDocumentId: successor.id,
    );
  }

  Future<void> _archive(
    PropertyDocumentsController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final confirmed = await showDocumentArchiveDialog(
      context: context,
      document: document,
    );
    if (!confirmed) {
      return;
    }
    await controller.transitionStatus(
      documentId: document.id,
      expectedVersion: document.version,
      transition: DocumentStatusTransition.archive,
    );
  }

  Future<void> _download(
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
    await showDocumentSignedUrlDialog(context: context, signedUrl: signedUrl);
  }
}

/// MIG-BND-003 made visible: `confirm_document_content` succeeds in both
/// outcomes, so a rejection must not read as success — and must not vanish
/// with a snackbar either, because it needs a new upload.
class _ContentRejectedNotice extends StatelessWidget {
  const _ContentRejectedNotice({required this.message, required this.onDismiss});

  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        DocumentNotice(
          title: 'Upload abgelehnt',
          icon: Icons.report_problem_outlined,
          severity: DocumentNoticeSeverity.warning,
          description:
              message ??
              'Der hochgeladene Inhalt stimmt nicht mit den angegebenen Daten '
                  'überein. Das Dokument wurde abgelehnt und muss neu '
                  'hochgeladen werden.',
        ),
        TextButton(onPressed: onDismiss, child: const Text('Hinweis schließen')),
      ],
    );
  }
}
